// 背景: 上は流れる点の格子とまたたき、下は奥へ流れる遠近の床。flash で全体に色を足す。
// Compatibility(WebGL 2.0)で動く canvas_item のシェーダー(仕様書 INV-9、2026-11-10 に解禁)。
shader_type canvas_item;

uniform vec4 base_color : source_color = vec4(0.027, 0.043, 0.078, 1.0);
uniform vec4 grid_color : source_color = vec4(0.18, 0.55, 0.80, 1.0);
uniform vec4 flash_color : source_color = vec4(0.18, 0.9, 0.72, 1.0);
uniform float flash = 0.0;
uniform float speed = 1.0;
uniform vec2 rect_size = vec2(720.0, 1280.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;
	vec2 px = uv * rect_size;
	float t = TIME * speed;
	vec3 col = base_color.rgb + vec3(0.015, 0.025, 0.06) * (1.0 - uv.y);

	// 上: 点の格子(ゆっくり上へ流れる)
	vec2 cell = vec2(px.x, px.y + t * 18.0) / 48.0;
	vec2 f = fract(cell) - 0.5;
	float dotv = smoothstep(0.09, 0.0, length(f));
	float tw = hash(floor(cell));
	float blink = 0.35 + 0.65 * smoothstep(0.92, 1.0, sin(t * (0.6 + tw * 2.0) + tw * 40.0));
	col += grid_color.rgb * dotv * 0.25 * blink * (1.0 - smoothstep(0.55, 0.8, uv.y));

	// 下: 遠近の床(奥へ流れる格子。線の太さは fwidth で画面上そろえる)
	float horizon = 0.62;
	if (uv.y > horizon) {
		float d = (uv.y - horizon) / (1.0 - horizon);
		float z = 1.0 / max(d, 0.002);
		vec2 g = vec2((uv.x - 0.5) * z * (rect_size.x / rect_size.y) * 3.0, z * 0.9 + t * 1.2);
		vec2 w = abs(fract(g - 0.5) - 0.5) / max(fwidth(g), vec2(0.0001));
		float line = 1.0 - min(min(w.x, w.y), 1.0);
		float fade = smoothstep(0.0, 0.35, d);
		vec3 floor_col = mix(grid_color.rgb, vec3(0.75, 0.3, 0.95), 0.35 * (1.0 - d));
		col += floor_col * line * 0.55 * fade;
		col += grid_color.rgb * 0.10 * smoothstep(0.12, 0.0, d);  // 地平線の光
	}

	// 周辺を落とす
	float vig = smoothstep(1.15, 0.35, length((uv - 0.5) * vec2(1.0, 0.8)));
	col *= mix(0.55, 1.0, vig);
	col = mix(col, flash_color.rgb, flash * 0.18);
	COLOR = vec4(col, 1.0);
}
