// Web 書き出しを、窓なし・消音の Chrome と Edge(使い捨てのプロフィール)で開いて撮る(仕様書 §8.1・AC-3・AC-19〜21)。
// URL を渡さなければ build/web を /packet-bouncer/ の下に置いて手元で配信する。--play を付けると、Chrome で 1 ラン遊んで各画面を撮る。
// 起動したか・転送量(キャッシュ無効)・通信先のホスト・コンソールのエラーを出す。画像は build/web_shots/
// --mobile はスマホのエミュレーション(タッチ)で遊んで撮る。--perfect は今日の検問を正しく答えて 80 枚を通し(1 回だけわざとミス)、README 用の画像を撮る(答えは tests/answer_key.mjs)。
//   node tests/shoot_web.mjs [https://takosasi-dev.github.io/packet-bouncer/] [--play | --perfect | --mobile]
import { spawn } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { setTimeout as sleep } from 'node:timers/promises';
import { fileURLToPath } from 'node:url';
import { dailyAnswers, localDate, selfCheck } from './answer_key.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const WEB = path.join(ROOT, 'build', 'web');
const OUT = path.join(ROOT, 'build', 'web_shots');
const HTTP_PORT = 8771;
const CDP_PORT = 9771;
const BOOT_TIMEOUT_MS = 60000;
const SETTLE_MS = 3000;
const RELOAD_WAIT_MS = 20000; // 読み込み直して、登場の動きが終わるまで // 起動の知らせの後、画面が描かれるまで
const BROWSERS = {
	chrome: 'C:/Program Files/Google/Chrome/Application/chrome.exe',
	edge: 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',
};
const DESKTOP = { width: 1280, height: 800 };
const PHONE = { width: 540, height: 960 }; // 720 × 1280 の 0.75 倍
const MOBILE = { width: 390, height: 844, deviceScaleFactor: 3, mobile: true }; // iPhone くらいの縦長
const KEYS = {
	Enter: { key: 'Enter', code: 'Enter', windowsVirtualKeyCode: 13, text: '\r' },
	Space: { key: ' ', code: 'Space', windowsVirtualKeyCode: 32, text: ' ' },
	ArrowLeft: { key: 'ArrowLeft', code: 'ArrowLeft', windowsVirtualKeyCode: 37 },
	ArrowRight: { key: 'ArrowRight', code: 'ArrowRight', windowsVirtualKeyCode: 39 },
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

// 1 ラン遊んで撮る(AC-19〜21 の画像)。答えは常に「通す」なので、落とすカードでミスが出て、3 回でライフが尽きる
async function playScenario(page, shot) {
	const press = async (name) => {
		await page.send('Input.dispatchKeyEvent', { type: 'keyDown', ...KEYS[name] });
		await page.send('Input.dispatchKeyEvent', { type: 'keyUp', ...KEYS[name] });
	};
	const mouse = (type, x, y) => page.send('Input.dispatchMouseEvent', { type, x, y, button: 'left', buttons: type === 'mouseReleased' ? 0 : 1, clickCount: 1 });
	const gray = async (name) => {
		await page.send('Runtime.evaluate', { expression: "document.documentElement.style.filter='grayscale(1)'" });
		await shot(name);
		await page.send('Runtime.evaluate', { expression: "document.documentElement.style.filter=''" });
	};
	const scale = PHONE.width / 720;
	const card = { x: 360 * scale, y: (640 + 125) * scale }; // カードの中心(ui/play.gd の CARD_Y と card.gd の HEIGHT)
	await press('Enter'); // タイトルの「今日の検問」にフォーカスがある
	await sleep(1200);
	await shot('02_panel');
	await press('Space');
	await sleep(900);
	await shot('03_card');
	// ドラッグ: 少し動かして戻す → 大きく動かして離す(通す)
	await mouse('mousePressed', card.x, card.y);
	for (let dx = 0; dx <= 60; dx += 15) await mouse('mouseMoved', card.x + dx * scale, card.y);
	await mouse('mouseReleased', card.x + 60 * scale, card.y);
	await sleep(400);
	await shot('04_drag_back');
	await mouse('mousePressed', card.x, card.y);
	for (let dx = 0; dx <= 200; dx += 20) await mouse('mouseMoved', card.x + dx * scale, card.y);
	await sleep(150);
	await shot('05_dragging');
	await mouse('mouseReleased', card.x + 200 * scale, card.y);
	await sleep(120);
	await shot('06_after_drag');
	await sleep(1600);
	for (let i = 1; i <= 10; i++) {
		await press('ArrowRight');
		await sleep(260);
		await shot(`10_key_${String(i).padStart(2, '0')}`);
		await gray(`10_key_${String(i).padStart(2, '0')}_gray`);
		await sleep(1500);
	}
	await sleep(1500);
	await shot('20_result');
	await gray('20_result_gray');
}

// 今日の検問を正しく答えて通す。ステージ 7 の 6 枚目だけわざと間違えて、順序のひっかけのミスを撮る
async function perfectScenario(page, shot) {
	const press = async (name) => {
		await page.send('Input.dispatchKeyEvent', { type: 'keyDown', ...KEYS[name] });
		await page.send('Input.dispatchKeyEvent', { type: 'keyUp', ...KEYS[name] });
	};
	const gray = async (name) => {
		await page.send('Runtime.evaluate', { expression: "document.documentElement.style.filter='grayscale(1)'" });
		await shot(name);
		await page.send('Runtime.evaluate', { expression: "document.documentElement.style.filter=''" });
	};
	const { answers } = dailyAnswers(localDate());
	const SHOTS = { '2-7': 'combo', '5-4': 'stage5', '7-3': 'stage7' };
	const MISS = '7-6';
	await press('Enter');
	await sleep(1500);
	await shot('readme_panel1');
	for (let s = 1; s <= 8; s++) {
		if (s > 1) {
			await sleep(1600); // パネルが出て、PANEL_GUARD_SEC が過ぎるまで
			if (s === 4 || s === 7) await shot(`readme_panel${s}`);
		}
		await press('Space');
		await sleep(700);
		for (let k = 1; k <= 10; k++) {
			const key = `${s}-${k}`;
			if (SHOTS[key]) await shot(`readme_${SHOTS[key]}`);
			const right = answers[s - 1][k - 1].action;
			const give = key === MISS ? (right === 'allow' ? 'drop' : 'allow') : right;
			await press(give === 'allow' ? 'ArrowRight' : 'ArrowLeft');
			if (key === MISS) {
				await sleep(350);
				await shot('readme_miss');
				await gray('readme_miss_gray');
				await sleep(2200);
			} else {
				await sleep(k === 10 ? 200 : 450);
			}
		}
	}
	await sleep(3500);
	await shot('readme_result');
	// 保存(FR-15・AC-22): 読み込み直すと自己ベストと今日の回数が残り、音を切にして読み込み直すと切のまま
	const reload = async () => { await page.send('Page.reload', { ignoreCache: true }); await sleep(RELOAD_WAIT_MS); };
	await reload();
	await shot('saved_after_reload');
	const scale = PHONE.width / 720;
	await page.send('Input.dispatchMouseEvent', { type: 'mousePressed', x: 230 * scale, y: 1008 * scale, button: 'left', buttons: 1, clickCount: 1 }); // 「音 入」
	await page.send('Input.dispatchMouseEvent', { type: 'mouseReleased', x: 230 * scale, y: 1008 * scale, button: 'left', buttons: 0, clickCount: 1 });
	await sleep(800);
	await shot('sound_clicked');
	await reload();
	await shot('sound_after_reload');
}

// スマホのエミュレーション(390 × 844、3 倍密度、タッチ)で、タップ・指でのスワイプ・2 本目の指・横向きを撮る
async function mobileScenario(page, shot) {
	const s = MOBILE.width / 720;
	const top = (MOBILE.height - 1280 * s) / 2; // 縦に余る分は上下に分かれる(aspect expand)
	const at = (x, y) => ({ x: x * s, y: top + y * s });
	const touch = (type, points) => page.send('Input.dispatchTouchEvent', { type, touchPoints: points });
	const tap = async (x, y) => {
		const p = at(x, y);
		await touch('touchStart', [{ ...p, id: 0 }]);
		await touch('touchEnd', []);
	};
	const { answers } = dailyAnswers(localDate());
	await tap(360, 666); // 今日の検問
	await sleep(1600);
	await shot('m02_panel');
	await tap(360, 900); // パネルを閉じる
	await sleep(900);
	await shot('m03_card');
	// 1 枚目: 指で右へスワイプ。途中で 2 本目の指が左へ動いても、最初の指だけを追う(E-4)
	const c = at(360, 765);
	await touch('touchStart', [{ ...c, id: 0 }]);
	for (let dx = 0; dx <= 120; dx += 20) await touch('touchMove', [{ x: c.x + dx * s, y: c.y, id: 0 }]);
	await touch('touchStart', [{ x: c.x + 120 * s, y: c.y, id: 0 }, { x: c.x, y: c.y + 100, id: 1 }]);
	for (let dx = 0; dx <= 300; dx += 50) await touch('touchMove', [{ x: c.x + (120 + dx * 0.3) * s, y: c.y, id: 0 }, { x: c.x - dx * s, y: c.y + 100, id: 1 }]);
	await shot('m04_two_fingers');
	await touch('touchEnd', [{ x: c.x + 210 * s, y: c.y, id: 0 }]);
	await touch('touchEnd', []);
	await sleep(answers[0][0].action === 'allow' ? 600 : 2200);
	// 2〜10 枚目とステージ 2 の前半を、ボタンのタップで正しく答える
	for (let k = 2; k <= 10; k++) {
		await tap(answers[0][k - 1].action === 'allow' ? 533 : 187, 1094);
		await sleep(500);
	}
	await sleep(1500);
	await tap(360, 900);
	await sleep(800);
	for (let k = 1; k <= 6; k++) {
		await tap(answers[1][k - 1].action === 'allow' ? 533 : 187, 1094);
		await sleep(500);
	}
	await shot('m05_stage2');
	await page.send('Emulation.setDeviceMetricsOverride', { width: MOBILE.height, height: MOBILE.width, deviceScaleFactor: MOBILE.deviceScaleFactor, mobile: true });
	await sleep(1500);
	await shot('m06_landscape');
	await page.send('Emulation.setDeviceMetricsOverride', MOBILE);
	await sleep(1500);
	await shot('m07_back_portrait');
}

async function shoot(name, exe, url, play) {
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
		if (play === 'mobile') {
			await page.send('Emulation.setTouchEmulationEnabled', { enabled: true, maxTouchPoints: 5 });
			await page.send('Emulation.setDeviceMetricsOverride', MOBILE);
		} else {
			await page.send('Emulation.setDeviceMetricsOverride', { ...(play ? PHONE : DESKTOP), deviceScaleFactor: 1, mobile: false });
		}
		await page.send('Page.navigate', { url });
		const booted = await waitFor(() => logs.some((l) => l.text.startsWith('Godot Engine v')), BOOT_TIMEOUT_MS);
		expect(booted !== null, `${name}: ${url} で Godot が起動した`);
		await sleep(SETTLE_MS);
		const shot = async (label) => {
			const file = path.join(OUT, `${name}_${label}.png`);
			writeFileSync(file, Buffer.from((await page.send('Page.captureScreenshot', { format: 'png' })).data, 'base64'));
		};
		if (play) await sleep(SETTLE_MS * 2); // 最初の数秒はシェーダーのコンパイルで遅く、登場の動きが終わっていない
		await shot('01_title');
		console.log(`    転送量(キャッシュ無効、encodedDataLength の合計): ${(bytes / 1e6).toFixed(2)} MB`);
		console.log(`    通信先: ${[...hosts].join(', ')}`);
		if (play === 'play') await playScenario(page, shot);
		else if (play === 'perfect') await perfectScenario(page, shot);
		else if (play === 'mobile') await mobileScenario(page, shot);
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
	const play = ['play', 'perfect', 'mobile'].find((m) => process.argv.includes(`--${m}`)) ?? '';
	if (['perfect', 'mobile'].includes(play) && !expect(selfCheck(), 'tests/answer_key.mjs が仕様書の固定値と合う')) return;
	let url = process.argv.slice(2).find((a) => !a.startsWith('--'));
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
			if (play && name !== 'chrome') continue;
			if (existsSync(exe)) await shoot(name, exe, url, play);
			else console.log(`--  ${name}: 入っていない(${exe})`);
		}
		if (play === 'play' && existsSync(BROWSERS.chrome)) await shoot('chrome_desktop', BROWSERS.chrome, url, ''); // 横長の窓で、余白が背景で埋まるか(E-12)
	} finally {
		server?.kill();
		if (root) rmSync(path.join(root, 'packet-bouncer')); // ジャンクションだけ消す(build/web は残す)
	}
	console.log(`画像: ${OUT}`);
}

await main();
console.log(failures === 0 ? 'ALL OK' : `${failures} 件 NG`);
process.exitCode = failures === 0 ? 0 : 1;
