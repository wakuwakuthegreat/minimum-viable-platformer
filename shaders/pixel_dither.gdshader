shader_type canvas_item;

// Retro pixel dithering — reduces the color palette using a Bayer 4x4 ordered
// dither pattern. Gives the game a lo-fi handheld aesthetic.

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_nearest;
uniform float strength : hint_range(0.0, 1.0) = 0.55;
uniform float palette_levels : hint_range(2.0, 16.0) = 6.0;

// 4×4 Bayer ordered dither matrix lookup — static if/else avoids dynamic indexing.
float bayer4(vec2 pos) {
	int x = int(mod(pos.x, 4.0));
	int y = int(mod(pos.y, 4.0));
	int idx = y * 4 + x;
	if (idx ==  0) return  0.0/16.0;
	if (idx ==  1) return  8.0/16.0;
	if (idx ==  2) return  2.0/16.0;
	if (idx ==  3) return 10.0/16.0;
	if (idx ==  4) return 12.0/16.0;
	if (idx ==  5) return  4.0/16.0;
	if (idx ==  6) return 14.0/16.0;
	if (idx ==  7) return  6.0/16.0;
	if (idx ==  8) return  3.0/16.0;
	if (idx ==  9) return 11.0/16.0;
	if (idx == 10) return  1.0/16.0;
	if (idx == 11) return  9.0/16.0;
	if (idx == 12) return 15.0/16.0;
	if (idx == 13) return  7.0/16.0;
	if (idx == 14) return 13.0/16.0;
	return 5.0/16.0; // idx == 15
}

void fragment() {
	vec4 col = texture(screen_tex, SCREEN_UV);
	vec2 px = floor(FRAGCOORD.xy);
	float threshold = bayer4(px) - 0.5;
	float levels = palette_levels - 1.0;
	vec3 dithered = floor(col.rgb * levels + threshold * strength + 0.5) / levels;
	COLOR = vec4(mix(col.rgb, dithered, strength), col.a);
}
