// 撮影用の答え合わせ表: core/ の出題の手順(仕様書 §9.2・§9.4〜§9.6)を JS に写した物。ゲームには入らない。
// shoot_web.mjs が、ゲームと同じ日替わりの列を作って正しく答え、後半のステージまで撮るのに使う。
// 写し間違えると、撮影の途中で正解のはずの答えがミスになるので、画像でずれが分かる。
const B = {
	PROTO: [['tcp', 65], ['udp', 35]],
	PORT: [['focus', 60], ['trap', 40]],
	TRAP_PORTS: [8443, 21, 23, 25, 3389],
	NO_RANGE: 8080,
	SRC: [[3, [['EXT', 100], ['NETB', 0], ['INT', 0], ['NEAR', 0]]], [4, [['EXT', 40], ['NETB', 45], ['INT', 15], ['NEAR', 0]]],
		[6, [['EXT', 30], ['NETB', 30], ['INT', 25], ['NEAR', 15]]], [8, [['EXT', 25], ['NETB', 45], ['INT', 20], ['NEAR', 10]]]],
	NETB_4_6: [['exact', 60], ['adjacent', 40]],
	NETB_7_8: [['exact', 35], ['adjacent', 20], ['any', 45]],
	TRIES: 2000,
};
const TABLES = [['WEB1'], ['WEB2'], ['WEB', 'DNS'], ['BLK', 'WEB', 'DNS'], ['BLK', 'WEB', 'DNS', 'SSH'], ['BLK', 'WEB', 'DNS', 'SSH', 'HIGH'],
	['EXC', 'BLKNET', 'WEB', 'DNS', 'SSH', 'HIGH'], ['EXC', 'BLKNET', 'WEB', 'DNS', 'SSH', 'HIGH']];
const NEW_ROWS = [['WEB1'], ['WEB2'], ['WEB', 'DNS'], ['BLK'], ['SSH'], ['HIGH'], ['EXC', 'BLKNET'], []];

export function fnv1a(text) {
	let h = 2166136261;
	for (const b of new TextEncoder().encode(text)) h = Math.imul((h ^ b) >>> 0, 16777619) >>> 0;
	return h;
}

class Rng {
	constructor(seed) { this.x = seed >>> 0 || 1; }
	next() {
		let x = this.x;
		x = (x ^ (x << 13)) >>> 0;
		x = (x ^ (x >>> 17)) >>> 0;
		x = (x ^ (x << 5)) >>> 0;
		return (this.x = x);
	}
	int(n) { return this.next() % n; }
	pick(pairs) {
		let r = this.int(pairs.reduce((a, [, w]) => a + w, 0));
		for (const [k, w] of pairs) { r -= w; if (r < 0) return k; }
		return pairs[pairs.length - 1][0];
	}
}

const ip = (a, b, c, d) => ((a << 24) >>> 0) + (b << 16) + (c << 8) + d;

function rollParams(rng) {
	const P = [80, 443][rng.int(2)];
	const b = 2 + rng.int(253);
	const n = 1 + rng.int(254);
	let v = 2 + rng.int(253);
	while (v === b) v = 2 + rng.int(253);
	return { P, b, n, v };
}

function rule(id, p) {
	const any = { kind: 'any' };
	const list = (...values) => ({ kind: 'list', values });
	return {
		WEB1: { action: 'allow', proto: 'any', net: 0, prefix: 0, ports: list(p.P) },
		WEB2: { action: 'allow', proto: 'any', net: 0, prefix: 0, ports: list(80, 443) },
		WEB: { action: 'allow', proto: 'tcp', net: 0, prefix: 0, ports: list(80, 443) },
		DNS: { action: 'allow', proto: 'udp', net: 0, prefix: 0, ports: list(53) },
		BLK: { action: 'drop', proto: 'any', net: ip(203, 0, 113, p.b), prefix: 32, ports: any },
		SSH: { action: 'allow', proto: 'tcp', net: ip(192, 168, p.n, 0), prefix: 24, ports: list(22) },
		HIGH: { action: 'allow', proto: 'tcp', net: 0, prefix: 0, ports: { kind: 'range', lo: 8000, hi: 8099 } },
		EXC: { action: 'allow', proto: 'tcp', net: ip(203, 0, 113, p.v), prefix: 32, ports: list(443) },
		BLKNET: { action: 'drop', proto: 'any', net: ip(203, 0, 113, 0), prefix: 24, ports: any },
	}[id];
}

function matches(r, c) {
	if (r.proto !== 'any' && r.proto !== c.proto) return false;
	if (r.prefix !== 0) {
		const s = 32 - r.prefix;
		if (Math.floor(c.src / 2 ** s) !== Math.floor(r.net / 2 ** s)) return false;
	}
	if (r.ports.kind === 'list') return r.ports.values.includes(c.dport);
	if (r.ports.kind === 'range') return r.ports.lo <= c.dport && c.dport <= r.ports.hi;
	return true;
}

export function evaluate(rules, c) {
	const i = rules.findIndex((r) => matches(r, c));
	return i < 0 ? { action: 'drop', index: -1 } : { action: rules[i].action, index: i };
}

function isTrap(rules, c) {
	const e = evaluate(rules, c);
	return e.index >= 0 && rules.slice(e.index + 1).some((r) => r.action !== e.action && matches(r, c));
}

function neighbor(c, lo, hi, rng) {
	const d = rng.int(2) === 0 ? -1 : 1;
	return lo <= c + d && c + d <= hi ? c + d : c - d;
}

function pickSrc(stage, p, rng) {
	const weights = B.SRC.find(([upto]) => stage <= upto)[1];
	switch (rng.pick(weights)) {
		case 'EXT': { const c = [ip(198, 51, 100, 0), ip(192, 0, 2, 0)][rng.int(2)]; return c + 1 + rng.int(254); }
		case 'NETB': {
			const early = stage <= 6;
			const center = early ? p.b : p.v;
			const k = rng.pick(early ? B.NETB_4_6 : B.NETB_7_8);
			if (k === 'exact') return ip(203, 0, 113, center);
			if (k === 'adjacent') return ip(203, 0, 113, neighbor(center, 2, 254, rng));
			return ip(203, 0, 113, 1 + rng.int(254));
		}
		case 'INT': return ip(192, 168, p.n, 1 + rng.int(254));
		default: { const third = neighbor(p.n, 1, 254, rng); return ip(192, 168, third, 1 + rng.int(254)); }
	}
}

function pickPort(rules, rng) {
	const ports = [];
	if (rng.pick(B.PORT) === 'focus') {
		for (const r of rules) {
			if (r.ports.kind === 'list') ports.push(...r.ports.values);
			else if (r.ports.kind === 'range') ports.push(r.ports.lo, r.ports.hi, r.ports.lo + 1 + rng.int(r.ports.hi - r.ports.lo - 1));
		}
	} else {
		ports.push(...B.TRAP_PORTS);
		const ranges = rules.filter((r) => r.ports.kind === 'range');
		for (const r of ranges) ports.push(r.ports.lo - 1, r.ports.hi + 1);
		if (ranges.length === 0) ports.push(B.NO_RANGE);
	}
	const unique = [...new Set(ports)].sort((a, b) => a - b);
	return unique[rng.int(unique.length)];
}

function stageCards(stage, p, rng) {
	const ids = TABLES[stage - 1];
	const rules = ids.map((id) => rule(id, p));
	const fresh = NEW_ROWS[stage - 1].map((id) => ids.indexOf(id));
	const cards = [];
	const take = (cond) => {
		for (let t = 0; t < B.TRIES; t++) {
			const proto = stage <= 2 ? 'tcp' : rng.pick(B.PROTO);
			const src = pickSrc(stage, p, rng);
			const dport = pickPort(rules, rng);
			const c = { proto, src, dport };
			if (cond(c) && !cards.some((o) => o.proto === proto && o.src === src && o.dport === dport)) { cards.push(c); return; }
		}
		throw new Error(`stage ${stage}: 生成できない`);
	};
	if (stage >= 4) for (let i = 0; i < 2; i++) take((c) => isTrap(rules, c));
	if (fresh.length) for (let i = 0; i < 2; i++) take((c) => fresh.includes(evaluate(rules, c).index));
	while (cards.length < 10) {
		const need = cards.filter((c) => evaluate(rules, c).action === 'allow').length < 5 ? 'allow' : 'drop';
		take((c) => evaluate(rules, c).action === need);
	}
	for (let i = 9; i > 0; i--) { const j = rng.int(i + 1); [cards[i], cards[j]] = [cards[j], cards[i]]; }
	return { rules, cards };
}

// 日替わりの列(8 ステージ × 10 枚)と、それぞれの正解
export function dailyAnswers(date) {
	const rng = new Rng(fnv1a(`PB1:${date}`));
	const params = rollParams(rng);
	const stages = [];
	for (let s = 1; s <= 8; s++) stages.push(stageCards(s, params, rng));
	return { params, stages, answers: stages.map((st) => st.cards.map((c) => evaluate(st.rules, c))) };
}

export function localDate() {
	const d = new Date();
	return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}

// 仕様書 §9.2・§9.5 の固定値と合うか(写し間違いの早期発見)
export function selfCheck() {
	const ok = fnv1a('PB1:2026-11-10') === 1665684503
		&& JSON.stringify(dailyAnswers('2026-11-10').params) === JSON.stringify({ P: 80, b: 70, n: 161, v: 155 })
		&& JSON.stringify(dailyAnswers('2027-01-01').params) === JSON.stringify({ P: 443, b: 229, n: 125, v: 191 });
	const r = new Rng(1);
	return ok && [270369, 67634689, 2647435461, 307599695, 2398689233].every((v) => r.next() === v);
}
