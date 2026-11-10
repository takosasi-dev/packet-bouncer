// 背景: 上は流れる点の格子とまたたき、下は奥へ流れる遠近の床。flash で全体に色を足す。
// Compatibility(WebGL 2.0)で動く canvas_item のシェーダー(仕様書 INV-9、2026-11-10 に解禁)。
// ステージごとの演出(FR-27): grid_color・glow・floor_offset(床の上乗せの進み)・alarm(警報の赤)・pulse(赤の脈打ち)を app.gd が変える。
shader_type canvas_item;

uniform vec4 base_color : source_color = vec4(0.027, 0.043, 0.078, 1.0);
uniform vec4 grid_color : source_color = vec4(0.18, 0.55, 0.80, 1.0);
uniform vec4 flash_color : source_color = vec4(0.18, 0.9, 0.72, 1.0);
uniform float flash = 0.0;
uniform float speed = 1.0;
uniform vec2 rect_size = vec2(720.0, 1280.0);
uniform float glow = 1.0;  // 点と床の線の明るさ
uniform float floor_offset = 0.0;  // 床の進みの上乗せ(1 で一周。速さを変えても飛ばないよう app.gd が積み上げる)
uniform float alarm = 0.0;  // 0〜1。床の線・地平線・周辺を赤くする
uniform float pulse = 0.0;  // 0〜1。赤の脈打ちの強さ(「演出 弱」では 0)

const vec3 ALARM_RED = vec3(1.0, 0.18, 0.26);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;
	vec2 px = uv * rect_size;
	float t = TIME * speed;
	float beat = pulse * (0.5 + 0.5 * sin(TIME * 5.0));  // 1 秒に 0.8 回くらい
	vec3 col = base_color.rgb + vec3(0.015, 0.025, 0.06) * (1.0 - uv.y);
	col = mix(col, vec3(0.06, 0.01, 0.02), alarm * 0.5);

	// 上: 点の格子(ゆっくり上へ流れる)
	vec2 cell = vec2(px.x, px.y + t * 18.0) / 48.0;
	vec2 f = fract(cell) - 0.5;
	float dotv = smoothstep(0.09, 0.0, length(f));
	float tw = hash(floor(cell));
	float blink = 0.35 + 0.65 * smoothstep(0.92, 1.0, sin(t * (0.6 + tw * 2.0) + tw * 40.0));
	col += grid_color.rgb * dotv * 0.25 * glow * blink * (1.0 - smoothstep(0.55, 0.8, uv.y));

	// 下: 遠近の床(奥へ流れる格子。線の太さは fwidth で画面上そろえる)
	float horizon = 0.62;
	if (uv.y > horizon) {
		float d = (uv.y - horizon) / (1.0 - horizon);
		float z = 1.0 / max(d, 0.002);
		vec2 g = vec2((uv.x - 0.5) * z * (rect_size.x / rect_size.y) * 3.0, z * 0.9 + t * 1.2 + floor_offset);
		vec2 w = abs(fract(g - 0.5) - 0.5) / max(fwidth(g), vec2(0.0001));
		float line = 1.0 - min(min(w.x, w.y), 1.0);
		float fade = smoothstep(0.0, 0.35, d);
		vec3 floor_col = mix(grid_color.rgb, vec3(0.75, 0.3, 0.95), 0.35 * (1.0 - d));
		floor_col = mix(floor_col, ALARM_RED, alarm * 0.85);
		col += floor_col * line * 0.55 * glow * (1.0 + 0.7 * beat) * fade;
		col += mix(grid_color.rgb, ALARM_RED, alarm) * (0.10 + 0.14 * beat) * glow * smoothstep(0.12, 0.0, d);  // 地平線の光
	}

	// 周辺を落とす(警報では周辺が赤く脈打つ)
	float vig = smoothstep(1.15, 0.35, length((uv - 0.5) * vec2(1.0, 0.8)));
	col *= mix(0.55, 1.0, vig);
	col += ALARM_RED * alarm * (0.04 + 0.12 * beat) * (1.0 - vig);
	col = mix(col, flash_color.rgb, flash * 0.18);
	COLOR = vec4(col, 1.0);
}
