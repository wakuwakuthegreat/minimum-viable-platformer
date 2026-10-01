shader_type canvas_item;

// Air-warp / falling wobble. Runs as the last post-process pass, sampling the
// screen texture and lens-distorting UVs by two low-frequency sine waves. The
// output is a linear blend between the original screen and the distorted one
// so intensity=0 is a perfect identity — this avoids the "screen turns white"
// artefact that showed up when the previous version's early-return branch and
// chromatic sub-samples interacted badly with the screen-texture chain on some
// drivers.

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float time_sec : hint_range(0.0, 1000.0) = 0.0;

void fragment() {
	vec2 uv = SCREEN_UV;
	// Cap intensity in-shader as a safety net in case the caller feeds a bogus
	// value. Amplitude scales with the CAPPED value, so a spike can't blow out
	// the sample coordinates.
	float k = clamp(intensity, 0.0, 1.0);
	float amp_x = k * 0.014;
	float amp_y = k * 0.009;
	float wave_x = sin(uv.y * 12.0 + time_sec * 5.5) * amp_x;
	float wave_y = cos(uv.x * 9.0  + time_sec * 3.7) * amp_y;
	vec2 sample_uv = clamp(uv + vec2(wave_x, wave_y), vec2(0.001), vec2(0.999));
	vec3 distorted = texture(screen_tex, sample_uv).rgb;
	// Output only the distorted sample with alpha=k so the ColorRect alpha-
	// blends onto the underlying frame. At k=0 the pass is a no-op (alpha=0),
	// which prevents the "screen goes white" flash if screen_tex is temporarily
	// unavailable — the previous mix()-with-alpha-1 approach would overwrite the
	// whole frame with white in that case.
	COLOR = vec4(distorted, k);
}
