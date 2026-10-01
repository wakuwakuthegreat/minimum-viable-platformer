shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
uniform vec3 warm_tint : source_color = vec3(1.06, 0.97, 0.86);
uniform float saturation : hint_range(0.0, 2.0) = 1.18;
uniform float lift : hint_range(-0.2, 0.2) = 0.02;
uniform float gamma : hint_range(0.4, 2.0) = 0.96;

void fragment() {
	vec3 col = texture(screen_tex, SCREEN_UV).rgb;
	col = max(col + lift, vec3(0.0));
	col = pow(col, vec3(1.0 / gamma));
	col *= warm_tint;
	float l = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(l), col, saturation);
	COLOR = vec4(col, 1.0);
}
