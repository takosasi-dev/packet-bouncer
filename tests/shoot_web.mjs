// Web 書き出しを、窓なし・消音の Chrome と Edge(使い捨てのプロフィール)で開いて撮る(仕様書 §8.1・AC-3・AC-19〜21)。
// URL を渡さなければ build/web を /packet-bouncer/ の下に置いて手元で配信する。--play を付けると、Chrome で 1 ラン遊んで各画面を撮る。
// 起動したか・転送量(キャッシュ無効)・通信先のホスト・コンソールのエラーを出す。画像は build/web_shots/
// --mobile はスマホのエミュレーション(タッチ)で遊んで撮る。--perfect は今日の検問を正しく答えて 80 枚を通し(1 回だけわざとミス)、README 用の画像を撮る(答えは tests/answer_key.mjs)。
// --loading は転送を絞って読み込み中の画面(FR-28)を撮り、WebGL 2 が無いときの知らせも撮る。
// --progress はスマホのエミュレーションで、タイトルから実績の一覧と図鑑を開き、図鑑を指で送って撮る(--perfect の最後にも一覧と図鑑を撮る)。
// --learn ははじめての案内の各段・ミスの振り返り(わざとミスと時間切れ)・練習の HUD と結果を撮る。
// --gif はタイトル → ルール更新 → ステージ 1 の 10 枚(1 回だけわざとミス)を録って docs/images/play.gif に書く(ffmpeg を使う)。
//   node tests/shoot_web.mjs [https://takosasi-dev.github.io/packet-bouncer/] [--play | --perfect | --mobile | --loading | --progress | --learn | --gif]
// 使い捨てのプロフィールは毎回初めて遊ぶ扱いなので、ステージ 1 の 1 枚目で、はじめての案内(FR-23)が出る。どの流れも Space か タップで閉じてから進む
import { spawn, spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, rmSync, statSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { setTimeout as sleep } from 'node:timers/promises';
import { fileURLToPath } from 'node:url';
import { dailyAnswers, localDate, selfCheck } from './answer_key.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const WEB = path.join(ROOT, 'build', 'web');
const OUT = path.join(ROOT, 'build', 'web_shots');
// 何人かで同時に撮るときは、環境変数 SHOOT_HTTP_PORT・SHOOT_CDP_PORT で番号をずらす
const HTTP_PORT = Number(process.env.SHOOT_HTTP_PORT || 8771);
const CDP_PORT = Number(process.env.SHOOT_CDP_PORT || 9771);
const BOOT_TIMEOUT_MS = 60000;
const SETTLE_MS = 3000;
const RELOAD_WAIT_MS = 20000; // 読み込み直して、登場の動きが終わるまで // 起動の知らせの後、画面が描かれるまで
const BROWSERS = {
	chrome: 'C:/Program Files/Google/Chrome/Application/chrome.exe',
	edge: 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',
};
const GIF = path.join(ROOT, 'docs', 'images', 'play.gif');
const GIF_FRAMES = path.join(OUT, 'gif_frames');
const GIF_MAX_BYTES = 4e6;
const FFMPEG = process.env.FFMPEG || 'ffmpeg'; // PATH に無ければ環境変数 FFMPEG に ffmpeg の実行ファイルの場所を入れる
const DESKTOP = { width: 1280, height: 800 };
const PHONE = { width: 540, height: 960 }; // 720 × 1280 の 0.75 倍
const MOBILE = { width: 390, height: 844, deviceScaleFactor: 3, mobile: true }; // iPhone くらいの縦長
const PRACTICE_BTN = { x: 497, y: 750 }; // タイトルの「練習」(ui/title.gd の並び。720 × 1280 の座標)
const KEYS = {
	Enter: { key: 'Enter', code: 'Enter', windowsVirtualKeyCode: 13, text: '\r' },
	Space: { key: ' ', code: 'Space', windowsVirtualKeyCode: 32, text: ' ' },
	ArrowLeft: { key: 'ArrowLeft', code: 'ArrowLeft', windowsVirtualKeyCode: 37 },
	ArrowRight: { key: 'ArrowRight', code: 'ArrowRight', windowsVirtualKeyCode: 39 },
	Escape: { key: 'Escape', code: 'Escape', windowsVirtualKeyCode: 27 },
	Digit1: { key: '1', code: 'Digit1', windowsVirtualKeyCode: 49, text: '1' },
	Digit2: { key: '2', code: 'Digit2', windowsVirtualKeyCode: 50, text: '2' },
	KeyD: { key: 'd', code: 'KeyD', windowsVirtualKeyCode: 68, text: 'd' },
};

const TUT_STEPS = 3; // はじめての案内の段の数(core/strings.gd の TUT_STEPS)
const GRID = { x: (720 - (38 * 10 + 4 * 9)) / 2, y: 464, step: 42 }; // 結果の格子(ui/result.gd の CELL・CELL_GAP)

// はじめての案内を Space で 1 段ずつ閉じる。shot を渡すと各段を撮る。閉じた後の余分な Space はカードの間は何も起こさない
async function closeTutorial(press, shot) {
	for (let i = 1; i <= TUT_STEPS; i++) {
		if (shot) await shot(`tutorial_${i}`);
		await press('Space');
		await sleep(350);
	}
}

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
	await closeTutorial(press);
	await shot('03_card');
	// 技の解析(2 キー)と一時停止(Esc → Space で再開)
	await press('Digit2');
	await sleep(500);
	await shot('03_skill_scan');
	await press('Escape');
	await sleep(500);
	await shot('03_pause');
	await press('Space');
	await sleep(500);
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
		if (i === 2) { // 3 枚目(制限時間あり)で凍結(1 キー)
			await press('Digit1');
			await sleep(500);
			await shot('10_skill_freeze');
		}
		await press('ArrowRight');
		await sleep(260);
		await shot(`10_key_${String(i).padStart(2, '0')}`);
		await gray(`10_key_${String(i).padStart(2, '0')}_gray`);
		await sleep(1500);
	}
	await sleep(1500);
	await shot('20_result');
	await gray('20_result_gray');
	// 「結果を送る」: 差し込んだ偽の navigator.share に結果の文字が渡るか(本物の共有シートは実機で見る)
	await page.send('Input.dispatchMouseEvent', { type: 'mousePressed', x: 531 * scale, y: 1034 * scale, button: 'left', buttons: 1, clickCount: 1 });
	await page.send('Input.dispatchMouseEvent', { type: 'mouseReleased', x: 531 * scale, y: 1034 * scale, button: 'left', buttons: 0, clickCount: 1 });
	await sleep(800);
	const shared = (await page.send('Runtime.evaluate', { expression: 'window.__shared ? window.__shared.text : null', returnByValue: true })).result.value;
	expect(typeof shared === 'string' && shared.startsWith('PacketBouncer ') && shared.includes('https://takosasi-dev.github.io/packet-bouncer/'), `「結果を送る」で共有に渡った文字: ${JSON.stringify(shared)}`);
	await checkSharedImage(page, async () => {
		await page.send('Input.dispatchMouseEvent', { type: 'mousePressed', x: 531 * scale, y: 1034 * scale, button: 'left', buttons: 1, clickCount: 1 });
		await page.send('Input.dispatchMouseEvent', { type: 'mouseReleased', x: 531 * scale, y: 1034 * scale, button: 'left', buttons: 0, clickCount: 1 });
		await sleep(800);
	});
}

// 画像の共有(FR-29): 偽の canShare が files を受けると言えば、PNG が 1 つ文字と一緒に渡る。canShare が無ければ files なしで文字だけ
async function checkSharedImage(page, clickSend) {
	const file = (await page.send('Runtime.evaluate', {
		expression: `(async () => {
			const f = window.__shared && window.__shared.files;
			if (!Array.isArray(f) || f.length !== 1) return { count: Array.isArray(f) ? f.length : -1 };
			const bytes = new Uint8Array(await f[0].arrayBuffer());
			let bin = '';
			for (let i = 0; i < bytes.length; i++) bin += String.fromCharCode(bytes[i]);
			return { count: 1, name: f[0].name, type: f[0].type, size: bytes.length, b64: btoa(bin) };
		})()`,
		awaitPromise: true, returnByValue: true,
	})).result.value;
	const png = file.b64 ? Buffer.from(file.b64, 'base64') : Buffer.alloc(0);
	if (png.length > 0) writeFileSync(path.join(OUT, 'shared_image.png'), png);
	expect(file.count === 1 && file.type === 'image/png' && png.length > 1000 && png.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])),
		`「結果を送る」で PNG が 1 つ渡った(${file.count} 個、${file.type}、${png.length} バイト、build/web_shots/shared_image.png)`);
	await page.send('Runtime.evaluate', { expression: 'window.__shared = null; navigator.canShare = undefined;' });
	await clickSend();
	const plain = (await page.send('Runtime.evaluate', { expression: 'window.__shared ? { text: typeof window.__shared.text, files: window.__shared.files === undefined } : null', returnByValue: true })).result.value;
	expect(plain !== null && plain.text === 'string' && plain.files, `canShare が無いときは文字だけ渡る: ${JSON.stringify(plain)}`);
}

// 読み込み中の画面(FR-28): 転送を絞り、進み具合のバーが途中まで来たら撮る。題名は ::before の文字
async function loadingScenario(page, shot, logs) {
	const progress = async () => (await page.send('Runtime.evaluate', { expression: "(() => { const p = document.getElementById('status-progress'); return p && p.max > 1 ? p.value / p.max : -1; })()", returnByValue: true })).result.value;
	const mid = await waitFor(async () => { const v = await progress(); return v > 0.3 && v < 0.9 ? v : null; }, BOOT_TIMEOUT_MS);
	expect(mid !== null, `読み込み中: 進み具合のバーが途中まで進んだ(${mid})`);
	await shot('00_loading');
	const title = (await page.send('Runtime.evaluate', { expression: "getComputedStyle(document.getElementById('status'), '::before').content", returnByValue: true })).result.value;
	expect(title === '"パケット検問"', `読み込み中: 題名 ${title}`);
	await page.send('Network.emulateNetworkConditions', { offline: false, latency: 0, downloadThroughput: -1, uploadThroughput: -1 });
	// WebGL 2 が無い端末: 知らせが出る(console.error は Godot のシェルが出す物なので、エラーの数からは外す)
	await waitFor(() => logs.some((l) => l.text.startsWith('Godot Engine v')), BOOT_TIMEOUT_MS);
	await page.send('Page.addScriptToEvaluateOnNewDocument', { source: "const g = HTMLCanvasElement.prototype.getContext; HTMLCanvasElement.prototype.getContext = function (t, ...a) { return t === 'webgl2' ? null : g.call(this, t, ...a); };" });
	await page.send('Page.reload', { ignoreCache: true });
	await sleep(4000);
	await shot('00_no_webgl');
	const notice = (await page.send('Runtime.evaluate', { expression: "(() => { const n = document.getElementById('status-notice'); return n && getComputedStyle(n).display !== 'none' ? n.textContent : null; })()", returnByValue: true })).result.value;
	expect(typeof notice === 'string' && notice.includes('WebGL2'), `WebGL 2 が無いと知らせが出る: ${JSON.stringify(notice)}`);
	for (let i = logs.length - 1; i >= 0; i--) if (logs[i].text.includes('features required to run Godot')) logs.splice(i, 1);
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
	const SHOTS = { '1-3': 'stage1', '2-7': 'combo', '4-3': 'stage4', '5-4': 'stage5', '7-3': 'stage7', '8-3': 'stage8' };
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
		if (s === 1) await closeTutorial(press);
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
	// 「音 入」はタイトルの一番下の列の左(ui/title.gd の並び。舞台の座標でおよそ x 188・y 1155)
	await page.send('Input.dispatchMouseEvent', { type: 'mousePressed', x: 188 * scale, y: 1155 * scale, button: 'left', buttons: 1, clickCount: 1 });
	await page.send('Input.dispatchMouseEvent', { type: 'mouseReleased', x: 188 * scale, y: 1155 * scale, button: 'left', buttons: 0, clickCount: 1 });
	await sleep(800);
	await shot('sound_clicked');
	await reload();
	await shot('sound_after_reload');
	await progressShots(page, shot, PHONE.width / 720, 0, false);
}

// 担当 2: タイトルから実績の一覧と図鑑を重ねて撮る(ボタンは ui/title.gd の「実績・図鑑・あそびかた」の行)。
// touch なら指で図鑑を送る(スマホで動かせるか)。送る前後の画像が違えば動いた
async function progressShots(page, shot, s, top, touch) {
	const at = (x, y) => ({ x: x * s, y: top + y * s });
	const press = async (name) => {
		await page.send('Input.dispatchKeyEvent', { type: 'keyDown', ...KEYS[name] });
		await page.send('Input.dispatchKeyEvent', { type: 'keyUp', ...KEYS[name] });
	};
	const tap = async (x, y) => {
		const p = at(x, y);
		if (touch) {
			await page.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ ...p, id: 0 }] });
			await page.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
		} else {
			await page.send('Input.dispatchMouseEvent', { type: 'mousePressed', ...p, button: 'left', buttons: 1, clickCount: 1 });
			await page.send('Input.dispatchMouseEvent', { type: 'mouseReleased', ...p, button: 'left', buttons: 0, clickCount: 1 });
		}
	};
	const capture = async () => (await page.send('Page.captureScreenshot', { format: 'png' })).data;
	await tap(188, 1067); // 実績
	await sleep(800);
	await shot('p_achievements');
	await press('Escape');
	await sleep(500);
	await tap(360, 1067); // 図鑑
	await sleep(800);
	await shot('p_dex');
	const before = await capture();
	if (touch) {
		const c = at(360, 800);
		await page.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ ...c, id: 0 }] });
		for (let dy = 0; dy <= 500; dy += 25) await page.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: [{ x: c.x, y: c.y - dy * s, id: 0 }] });
		await page.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
	} else {
		const c = at(360, 600);
		await page.send('Input.dispatchMouseEvent', { type: 'mouseWheel', ...c, deltaX: 0, deltaY: 600 });
	}
	await sleep(800);
	await shot('p_dex_scrolled');
	expect(before !== await capture(), `図鑑を${touch ? '指' : 'ホイール'}で送ると画面が動く`);
	await press('Space'); // フォーカスのある「閉じる」
	await sleep(600);
	await shot('p_closed');
}

// はじめての案内(FR-23)・ミスの振り返り(FR-24)・練習(FR-25)を撮る。今日の検問のステージ 1 で、
// 1 枚目をわざと間違え、3 枚目(制限時間あり)は時間切れにし、4 枚目もわざと間違えてライフを切らす
async function learnScenario(page, shot) {
	const press = async (name) => {
		await page.send('Input.dispatchKeyEvent', { type: 'keyDown', ...KEYS[name] });
		await page.send('Input.dispatchKeyEvent', { type: 'keyUp', ...KEYS[name] });
	};
	const scale = PHONE.width / 720;
	const click = async (x, y) => {
		for (const type of ['mousePressed', 'mouseReleased']) {
			await page.send('Input.dispatchMouseEvent', { type, x: x * scale, y: y * scale, button: 'left', buttons: type === 'mousePressed' ? 1 : 0, clickCount: 1 });
		}
	};
	const { answers } = dailyAnswers(localDate());
	const wrong = (k) => (answers[0][k - 1].action === 'allow' ? 'ArrowLeft' : 'ArrowRight');
	const right = (k) => (answers[0][k - 1].action === 'allow' ? 'ArrowRight' : 'ArrowLeft');
	await press('Enter');
	await sleep(1500);
	await press('Space');
	await sleep(900);
	await press('ArrowLeft'); // 案内の間は答えにならない
	await sleep(300);
	await closeTutorial(press, (n) => shot(`30_${n}`));
	await shot('31_card_after_tutorial');
	await press(wrong(1));
	await sleep(1800);
	await press(right(2));
	await sleep(600);
	await sleep(9000); // 3 枚目は時間切れ(ステージ 1 は 8 秒)
	await press(wrong(4));
	await sleep(3500);
	await shot('32_result');
	await click(GRID.x + 0 * GRID.step + 19, GRID.y + 19); // ステージ 1 の 1 枚目の x
	await sleep(600);
	await shot('33_review_1');
	await press('ArrowRight');
	await sleep(500);
	await shot('34_review_2_timeout');
	await press('Space'); // 閉じる(「もう一度」は押さない)
	await sleep(600);
	await shot('35_review_closed');
	await click(531, 1188); // タイトルへ
	await sleep(1500);
	await click(PRACTICE_BTN.x, PRACTICE_BTN.y);
	await sleep(1500);
	await press('Space');
	await sleep(900);
	await shot('36_practice_card');
	// 練習は時間もライフも無いので、通す(D キー)を押し続けて 80 枚を終える(落とすカードはミスになる)。パネルはタップで閉じる。
	// 結果画面に着いても何も押さないよう、Space・矢印は使わない(フォーカスのボタンが動く)。
	// 窓なしの描画は遅く、1 コマに進む時間に上限がある(INV-3)ので、ミスの止まりが実時間より長い
	const end = Date.now() + 300000;
	while (Date.now() < end) {
		await press('KeyD');
		await sleep(200);
		await click(360, 900);
		await sleep(150);
	}
	await sleep(3000);
	await shot('37_practice_result');
}

// README の動く画像: タイトル → 今日の検問 → ルール更新のパネル → ステージ 1 の 10 枚を正しく答える(6 枚目だけわざとミス)。
// 画面の位置ではなくキーで動かすので、ボタンが増えても動く。コマ送りは Page.startScreencast で、各コマの長さは metadata.timestamp の差
async function gifScenario(page) {
	const press = async (name) => {
		await page.send('Input.dispatchKeyEvent', { type: 'keyDown', ...KEYS[name] });
		await page.send('Input.dispatchKeyEvent', { type: 'keyUp', ...KEYS[name] });
	};
	const { answers } = dailyAnswers(localDate());
	const MISS = 6;
	const frames = [];
	rmSync(GIF_FRAMES, { recursive: true, force: true });
	mkdirSync(GIF_FRAMES, { recursive: true });
	page.onEvent((msg) => {
		if (msg.method !== 'Page.screencastFrame') return;
		const p = msg.params;
		const file = `f${String(frames.length).padStart(5, '0')}.jpg`;
		writeFileSync(path.join(GIF_FRAMES, file), Buffer.from(p.data, 'base64'));
		frames.push({ file, t: p.metadata.timestamp });
		page.send('Page.screencastFrameAck', { sessionId: p.sessionId }).catch(() => { /* 閉じた後 */ });
	});
	await page.send('Page.startScreencast', { format: 'jpeg', quality: 90, maxWidth: PHONE.width, maxHeight: PHONE.height, everyNthFrame: 1 });
	await sleep(1200); // タイトル
	await press('Enter'); // 「今日の検問」にフォーカスがある
	await sleep(1500); // ルール更新のパネル(PANEL_GUARD_SEC より長く)
	await press('Space');
	await sleep(700);
	await closeTutorial(press);
	for (let k = 1; k <= 10; k++) {
		const right = answers[0][k - 1].action;
		const give = k === MISS ? (right === 'allow' ? 'drop' : 'allow') : right;
		if (k === 2 || k === 4) { // 技も見せる: 2 枚目で解析、4 枚目(制限時間あり)で凍結
			await press(k === 2 ? 'Digit2' : 'Digit1');
			await sleep(700);
		}
		await press(give === 'allow' ? 'ArrowRight' : 'ArrowLeft');
		await sleep(k === MISS ? 1800 : 700); // ミスは赤い光と理由の文字が読めるまで(FEEDBACK_SEC より長く)
	}
	await sleep(700);
	await page.send('Page.stopScreencast');
	await sleep(300); // 最後のコマが届くまで
	expect(frames.length >= 20, `gif: コマが集まった(${frames.length} コマ)`);
	if (frames.length >= 2) {
		encodeGif(frames);
		console.log(`    録画の長さ: ${(frames.at(-1).t - frames[0].t).toFixed(1)} 秒`);
	}
	rmSync(GIF_FRAMES, { recursive: true, force: true });
}

// コマと長さを ffmpeg の concat の一覧に書き、GIF にする。4 MB を超えたらコマ数・幅・色数を落として作り直す
function encodeGif(frames) {
	const ffmpeg = FFMPEG;
	// 最後のコマの duration は concat が使わない(同じ file を足すと逆に 2 秒ほど延びる)。終わりの止まりは録画側の待ちで作る
	const lines = frames.slice(0, -1).flatMap((f, i) => [`file '${f.file}'`, `duration ${(frames[i + 1].t - f.t).toFixed(3)}`]);
	lines.push(`file '${frames.at(-1).file}'`);
	const list = path.join(GIF_FRAMES, 'list.txt');
	writeFileSync(list, `${lines.join('\n')}\n`);
	mkdirSync(path.dirname(GIF), { recursive: true });
	for (const [fps, width, colors] of [[12, 360, 256], [12, 360, 128], [10, 360, 128], [10, 320, 96], [8, 300, 64]]) {
		const vf = `fps=${fps},scale=${width}:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=${colors}:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle`;
		const r = spawnSync(ffmpeg, ['-y', '-loglevel', 'error', '-f', 'concat', '-safe', '0', '-i', list, '-vf', vf, '-loop', '0', GIF], { encoding: 'utf8' });
		if (!expect(r.status === 0, `gif: ffmpeg(${fps} fps・幅 ${width}・${colors} 色)`)) {
			console.log(r.error?.message ?? r.stderr);
			return;
		}
		const size = statSync(GIF).size;
		console.log(`    ${path.relative(ROOT, GIF)}: ${(size / 1e6).toFixed(2)} MB(${fps} fps・幅 ${width}・${colors} 色)`);
		if (size <= GIF_MAX_BYTES) return;
	}
	expect(false, 'gif: 4 MB 以下に収まった');
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
	await shot('m03_tutorial');
	for (let i = 0; i < TUT_STEPS; i++) { // 案内はどこをタップしても次へ。カードを掴まないよう HUD の位置を押す
		await tap(360, 80);
		await sleep(350);
	}
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
		if (play === 'mobile' || play === 'progress') {
			await page.send('Emulation.setTouchEmulationEnabled', { enabled: true, maxTouchPoints: 5 });
			await page.send('Emulation.setDeviceMetricsOverride', MOBILE);
		} else {
			await page.send('Emulation.setDeviceMetricsOverride', { ...(play ? PHONE : DESKTOP), deviceScaleFactor: 1, mobile: false });
		}
		if (play === 'play') await page.send('Page.addScriptToEvaluateOnNewDocument', { source: 'navigator.share = async (d) => { window.__shared = d; }; navigator.canShare = (d) => !!(d && Array.isArray(d.files) && d.files.length > 0);' }); // 「結果を送る」を出させる。画像も受ける
		const shot = async (label) => {
			const file = path.join(OUT, `${name}_${label}.png`);
			writeFileSync(file, Buffer.from((await page.send('Page.captureScreenshot', { format: 'png' })).data, 'base64'));
		};
		if (play === 'loading') await page.send('Network.emulateNetworkConditions', { offline: false, latency: 0, downloadThroughput: 4e6, uploadThroughput: -1 });
		await page.send('Page.navigate', { url });
		if (play === 'loading') await loadingScenario(page, shot, logs);
		const booted = await waitFor(() => logs.some((l) => l.text.startsWith('Godot Engine v')), BOOT_TIMEOUT_MS);
		expect(booted !== null, `${name}: ${url} で Godot が起動した`);
		await sleep(SETTLE_MS);
		if (play) await sleep(SETTLE_MS * 2); // 最初の数秒はシェーダーのコンパイルで遅く、登場の動きが終わっていない
		await shot('01_title');
		console.log(`    転送量(キャッシュ無効、encodedDataLength の合計): ${(bytes / 1e6).toFixed(2)} MB`);
		console.log(`    通信先: ${[...hosts].join(', ')}`);
		if (play === 'play') await playScenario(page, shot);
		else if (play === 'perfect') await perfectScenario(page, shot);
		else if (play === 'mobile') await mobileScenario(page, shot);
		else if (play === 'progress') await progressShots(page, shot, MOBILE.width / 720, (MOBILE.height - 1280 * MOBILE.width / 720) / 2, true);
		else if (play === 'learn') await learnScenario(page, shot);
		else if (play === 'gif') await gifScenario(page);
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
	const play = ['play', 'perfect', 'mobile', 'loading', 'gif', 'progress', 'learn'].find((m) => process.argv.includes(`--${m}`)) ?? '';
	if (['perfect', 'mobile', 'learn', 'gif'].includes(play) && !expect(selfCheck(), 'tests/answer_key.mjs が仕様書の固定値と合う')) return;
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
