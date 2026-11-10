// 画面全体に重ねる仕上げ: 走査線・周辺減光・色ずれ(不正解のときに glitch を上げる)・色の閃光。
// 画面の絵(hint_screen_texture)を読む canvas_item のシェーダー。Compatibility(WebGL 2.0)で動く物だけを使う。
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float glitch = 0.0;
uniform float scan = 0.10;
uniform float vignette = 0.30;
uniform float flash = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0, 0.3, 0.42, 1.0);

float hash(float n) {
	return fract(sin(n) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float g = glitch;
	// 横の帯ごとに少しずらす
	float band = floor(uv.y * 36.0) + floor(TIME * 24.0) * 7.0;
	float shift = (hash(band) - 0.5) * g * 0.06 * step(0.55, hash(band + 3.0));
	uv.x += shift;
	float a = g * 0.012 + 0.0008;
	vec3 c;
	c.r = texture(screen_tex, uv + vec2(a, 0.0)).r;
	c.g = texture(screen_tex, uv).g;
	c.b = texture(screen_tex, uv - vec2(a, 0.0)).b;
	float line = 0.5 + 0.5 * sin(FRAGCOORD.y * 3.14159);
	c *= 1.0 - scan * line;
	float v = length(SCREEN_UV - 0.5);
	c *= 1.0 - vignette * smoothstep(0.35, 0.85, v);
	c = mix(c, flash_color.rgb, flash * 0.22);
	COLOR = vec4(c, 1.0);
}
