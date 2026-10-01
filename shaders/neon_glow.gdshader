shader_type canvas_item;

// Neon glow — bright areas of the screen bleed into surrounding pixels with a
// soft additive halo. Creates a synthwave / neon-lit feel.

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
uniform float intensity : hint_range(0.0, 2.0) = 0.65;
uniform float threshold : hint_range(0.0, 1.0) = 0.55;
uniform float radius    : hint_range(0.0, 8.0)  = 3.0;
uniform vec2  pixel_size = vec2(0.00078125, 0.001388889);

float glow_contrib(vec3 s) {
	float lum = dot(s, vec3(0.299, 0.587, 0.114));
	return max(0.0, lum - threshold);
}

void fragment() {
	vec4 base = texture(screen_tex, SCREEN_UV);

	vec2 off = radius * pixel_size;

	vec3 s0 = texture(screen_tex, SCREEN_UV + vec2( off.x,  0.0)).rgb;
	vec3 s1 = texture(screen_tex, SCREEN_UV + vec2(-off.x,  0.0)).rgb;
	vec3 s2 = texture(screen_tex, SCREEN_UV + vec2( 0.0,  off.y)).rgb;
	vec3 s3 = texture(screen_tex, SCREEN_UV + vec2( 0.0, -off.y)).rgb;

	vec3 glow = s0 * glow_contrib(s0)
	          + s1 * glow_contrib(s1)
	          + s2 * glow_contrib(s2)
	          + s3 * glow_contrib(s3);
	glow *= 0.25;

	vec3 result = base.rgb + glow * intensity;
	COLOR = vec4(result, base.a);
}
