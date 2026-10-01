shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
uniform float scan_intensity : hint_range(0.0, 1.0) = 0.22;
uniform float curvature : hint_range(0.0, 0.4) = 0.08;
uniform float scanline_count : hint_range(120.0, 1200.0) = 700.0;
uniform float overscan : hint_range(1.0, 1.2) = 1.06;

void fragment() {
	vec2 cuv = UV * 2.0 - 1.0;
	cuv += cuv * curvature * (cuv.yx * cuv.yx);
	vec2 uv = (cuv + 1.0) * 0.5;
	// Zoom the sampled image so the curved black bezel is hidden off-screen.
	uv = (uv - 0.5) / overscan + 0.5;

	vec3 col = vec3(0.0);
	if (uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0) {
		col = texture(screen_tex, uv).rgb;
		float scan = 0.5 + 0.5 * sin(uv.y * scanline_count * 3.14159);
		col *= mix(1.0, scan, scan_intensity);
	}
	COLOR = vec4(col, 1.0);
}
