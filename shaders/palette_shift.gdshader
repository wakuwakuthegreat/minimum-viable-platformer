shader_type canvas_item;

// Full-screen palette recolour. Unlike a plain hue-rotate (which leaves greys
// and whites untouched because they have no hue), this maps EVERY pixel's
// luminance into the active palette colour, so the whole screen visibly turns a
// different colour. Driven by screen_fx.gd from Global.palette_shift_color();
// the "default" palette sets strength 0 so this pass is a no-op.
uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
uniform vec3 tint_color = vec3(1.0, 1.0, 1.0);
uniform float strength : hint_range(0.0, 1.0) = 0.0;
uniform float hue_shift : hint_range(0.0, 1.0) = 0.0;

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c) {
	vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
	return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

void fragment() {
	vec3 col = texture(screen_tex, SCREEN_UV).rgb;

	// 1) Map luminance into the palette colour — recolours greys/whites too.
	float luma = dot(col, vec3(0.299, 0.587, 0.114));
	vec3 tinted = tint_color * (0.25 + luma * 1.15);

	// 2) Rotate hue of already-coloured pixels so they shift as well.
	vec3 hsv = rgb2hsv(col);
	hsv.x = fract(hsv.x + hue_shift);
	vec3 rotated = hsv2rgb(hsv);

	// Blend the two recolour paths, then cross-fade from the original by strength.
	vec3 recolored = mix(rotated, tinted, 0.65);
	col = mix(col, recolored, strength);
	COLOR = vec4(col, 1.0);
}
