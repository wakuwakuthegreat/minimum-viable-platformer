shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
uniform float amount : hint_range(0.0, 0.04) = 0.006;

void fragment() {
	vec2 dir = (UV - 0.5);
	float d = length(dir);
	vec2 offset = dir * amount * (1.0 + d * 1.5);
	float r = texture(screen_tex, SCREEN_UV + offset).r;
	float g = texture(screen_tex, SCREEN_UV).g;
	float b = texture(screen_tex, SCREEN_UV - offset).b;
	COLOR = vec4(r, g, b, 1.0);
}
