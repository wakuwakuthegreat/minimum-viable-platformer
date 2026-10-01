shader_type canvas_item;

// Dark fog that swallows the lower portion of the screen. Gives a sense of a
// bottomless pit under the level. Bottom fades to near-black; upper portion
// is untouched. Uses a simple alpha-over approach so it works on all renderers.

uniform float intensity : hint_range(0.0, 1.0) = 0.88;
uniform float start_y   : hint_range(0.0, 1.0) = 0.50;  // where fog starts fading in
uniform float end_y     : hint_range(0.0, 1.0) = 1.00;  // fully dark below here
uniform vec4  fog_color : source_color = vec4(0.03, 0.02, 0.06, 1.0);

void fragment() {
	float t = smoothstep(start_y, end_y, UV.y);
	// Use the smoothstep directly as alpha so it reaches a solid 1.0 at the bottom,
	// fading completely to black rather than plateauing at 88% opacity.
	float alpha = t;
	COLOR = vec4(fog_color.rgb, alpha);
}
