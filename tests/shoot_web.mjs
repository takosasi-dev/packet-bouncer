// Web 書き出しを、窓なし・消音の Chrome と Edge(使い捨てのプロフィール)で開いて撮る(仕様書 §8.1・AC-3)。
// URL を渡さなければ build/web を /packet-bouncer/ の下に置いて手元で配信する。Pages の URL を渡すとそれを開く。
// 起動したか・転送量(キャッシュ無効)・通信先のホスト・コンソールのエラーを出す。画像は build/web_shots/
//   node tests/shoot_web.mjs [https://takosasi-dev.github.io/packet-bouncer/]
import { spawn } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { setTimeout as sleep } from 'node:timers/promises';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const WEB = path.join(ROOT, 'build', 'web');
const OUT = path.join(ROOT, 'build', 'web_shots');
const HTTP_PORT = 8771;
const CDP_PORT = 9771;
const BOOT_TIMEOUT_MS = 60000;
const SETTLE_MS = 3000; // 起動の知らせの後、画面が描かれるまで
const BROWSERS = {
	chrome: 'C:/Program Files/Google/Chrome/Application/chrome.exe',
	edge: 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',
};

let failures = 0;
function expect(ok, label) {
	console.log(`${ok ? 'OK' : 'NG'}  ${label}`);
	if (!ok) failures++;
	return ok;
}

async function waitFor(fn, timeoutMs) {
	const end = Date.now() + timeoutMs;
	while (Date.now() < end) {
		const v = await fn();
		if (v) return v;
		await sleep(500);
	}
	return null;
}

async function connect(url) {
	const ws = new WebSocket(url);
	await new Promise((ok, ng) => { ws.onopen = ok; ws.onerror = ng; });
	let id = 0;
	const pending = new Map();
	const listeners = [];
	ws.onmessage = (m) => {
		const msg = JSON.parse(m.data);
		if (msg.id && pending.has(msg.id)) {
			const { ok, ng } = pending.get(msg.id);
			pending.delete(msg.id);
			msg.error ? ng(new Error(msg.error.message)) : ok(msg.result);
		} else listeners.forEach((f) => f(msg));
	};
	return {
		send: (method, params = {}) => new Promise((ok, ng) => {
			const i = ++id;
			pending.set(i, { ok, ng });
			ws.send(JSON.stringify({ id: i, method, params }));
		}),
		onEvent: (f) => listeners.push(f),
		close: () => ws.close(),
	};
}

async function shoot(name, exe, url) {
	const profile = mkdtempSync(path.join(tmpdir(), `pb-${name}-`));
	const browser = spawn(exe, [
		'--headless=new', '--mute-audio', `--remote-debugging-port=${CDP_PORT}`, `--user-data-dir=${profile}`,
		'--no-first-run', '--no-default-browser-check', '--enable-unsafe-swiftshader', 'about:blank',
	], { stdio: 'ignore' });
	try {
		const target = await waitFor(async () => {
			try { return (await (await fetch(`http://127.0.0.1:${CDP_PORT}/json/list`)).json()).find((t) => t.type === 'page'); }
			catch { return null; }
		}, BOOT_TIMEOUT_MS);
		if (!expect(target !== null, `${name}: ブラウザにつながる`)) return;
		const page = await connect(target.webSocketDebuggerUrl);
		const logs = [];
		const hosts = new Set();
		let bytes = 0;
		page.onEvent((msg) => {
			const p = msg.params;
			if (msg.method === 'Runtime.consoleAPICalled') logs.push({ level: p.type, text: p.args.map((a) => a.value ?? a.description).join(' ') });
			else if (msg.method === 'Runtime.exceptionThrown') logs.push({ level: 'exception', text: p.exceptionDetails.exception?.description ?? p.exceptionDetails.text });
			else if (msg.method === 'Log.entryAdded') logs.push({ level: p.entry.level, text: `${p.entry.text} ${p.entry.url ?? ''}` });
			else if (msg.method === 'Network.requestWillBeSent' && /^https?:/.test(p.request.url)) hosts.add(new URL(p.request.url).host); // data: と blob: は通信ではない
			else if (msg.method === 'Network.loadingFinished') bytes += p.encodedDataLength;
		});
		for (const m of ['Runtime.enable', 'Log.enable', 'Page.enable', 'Network.enable']) await page.send(m);
		await page.send('Network.setCacheDisabled', { cacheDisabled: true });
		await page.send('Emulation.setFocusEmulationEnabled', { enabled: true });
		await page.send('Emulation.setDeviceMetricsOverride', { width: 1280, height: 800, deviceScaleFactor: 1, mobile: false });
		await page.send('Page.navigate', { url });
		const booted = await waitFor(() => logs.some((l) => l.text.startsWith('Godot Engine v')), BOOT_TIMEOUT_MS);
		expect(booted !== null, `${name}: ${url} で Godot が起動した`);
		await sleep(SETTLE_MS);
		const file = path.join(OUT, `${name}.png`);
		writeFileSync(file, Buffer.from((await page.send('Page.captureScreenshot', { format: 'png' })).data, 'base64'));
		console.log(`    画像: ${file}`);
		console.log(`    転送量(キャッシュ無効、encodedDataLength の合計): ${(bytes / 1e6).toFixed(2)} MB`);
		console.log(`    通信先: ${[...hosts].join(', ')}`);
		const errors = logs.filter((l) => ['error', 'exception'].includes(l.level) && !l.text.includes('favicon.ico'));
		errors.forEach((l) => console.log(`    [${l.level}] ${l.text}`));
		expect(errors.length === 0, `${name}: コンソールにエラーが無い`);
		expect(hosts.size === 1, `${name}: 通信先が 1 か所だけ`);
		try { await page.send('Browser.close'); } catch { /* もう閉じた */ }
		page.close();
	} finally {
		await Promise.race([new Promise((ok) => browser.once('exit', ok)), sleep(SETTLE_MS)]);
		browser.kill();
		rmSync(profile, { recursive: true, force: true, maxRetries: 5, retryDelay: 500 });
	}
}

async function main() {
	rmSync(OUT, { recursive: true, force: true });
	mkdirSync(OUT, { recursive: true });
	let url = process.argv[2];
	let server = null;
	let root = null;
	if (!url) {
		if (!expect(existsSync(path.join(WEB, 'index.html')), 'build/web/index.html がある(Web 書き出し済み)')) return;
		root = mkdtempSync(path.join(tmpdir(), 'pb-site-')); // Pages と同じく /packet-bouncer/ の下に置く
		symlinkSync(WEB, path.join(root, 'packet-bouncer'), 'junction');
		server = spawn('python', ['-m', 'http.server', String(HTTP_PORT), '--bind', '127.0.0.1', '--directory', root], { stdio: 'ignore' });
		url = `http://127.0.0.1:${HTTP_PORT}/packet-bouncer/`;
	}
	try {
		for (const [name, exe] of Object.entries(BROWSERS)) {
			if (existsSync(exe)) await shoot(name, exe, url);
			else console.log(`--  ${name}: 入っていない(${exe})`);
		}
	} finally {
		server?.kill();
		if (root) rmSync(path.join(root, 'packet-bouncer')); // ジャンクションだけ消す(build/web は残す)
	}
}

await main();
console.log(failures === 0 ? 'ALL OK' : `${failures} 件 NG`);
process.exitCode = failures === 0 ? 0 : 1;
