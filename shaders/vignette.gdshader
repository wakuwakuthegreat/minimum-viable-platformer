shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
uniform float intensity : hint_range(0.0, 1.0) = 0.55;
uniform float inner : hint_range(0.0, 1.0) = 0.45;
uniform float outer : hint_range(0.0, 1.5) = 1.05;

void fragment() {
	vec3 col = texture(screen_tex, SCREEN_UV).rgb;
	vec2 c = UV - 0.5;
	float d = length(c) * 1.4142;
	float v = smoothstep(inner, outer, d);
	col = mix(col, vec3(0.0), v * intensity);
	COLOR = vec4(col, 1.0);
}
