// 最大倍率の間、画面の縁を脈打つ光で囲む(Compatibility で動く canvas_item。INV-9)。strength 0 で消える
shader_type canvas_item;

uniform vec4 glow_color : source_color = vec4(1.0, 0.82, 0.4, 1.0);
uniform float strength = 0.0;
uniform vec2 rect_size = vec2(720.0, 1280.0);

void fragment() {
	vec2 px = UV * rect_size;
	float edge = min(min(px.x, rect_size.x - px.x), min(px.y, rect_size.y - px.y));
	float g = exp(-edge / 26.0) + 0.35 * exp(-edge / 90.0);
	float pulse = 0.7 + 0.3 * sin(TIME * 5.0);
	COLOR = vec4(glow_color.rgb, clamp(g * strength * pulse, 0.0, 1.0));
}
