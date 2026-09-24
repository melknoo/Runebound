shader_type canvas_item;
// Fullscreen pixel-fantasy post: color grading + posterization + ordered
// (Bayer) dither. Draws on a transparent ColorRect above the 3D view, below
// the HUD. Grading defaults are neutral, so zones without a ZoneLook render
// exactly as before (M06: grading lives here — no extra pass).

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float levels : hint_range(2.0, 32.0) = 10.0;
uniform float dither_strength : hint_range(0.0, 0.2) = 0.035;
uniform float saturation_boost : hint_range(0.5, 1.6) = 1.08;
uniform vec3 lift = vec3(0.0);
uniform vec3 gain = vec3(1.0);
uniform vec3 split_shadows = vec3(0.5);
uniform vec3 split_highlights = vec3(0.5);
uniform float split_amount : hint_range(0.0, 1.0) = 0.0;
uniform float vignette : hint_range(0.0, 1.0) = 0.0;
// M06: quantize luma in `levels` steps but chroma finer (YCoCg). Per-channel
// RGB rounding flips dark browns between olive and red at 14 levels; luma
// banding keeps the pixel look without hue jumps. Off = original RGB posterize.
uniform bool luma_quantize = false;
uniform float chroma_levels = 32.0;

const mat4 BAYER = mat4(
	vec4( 0.0,  8.0,  2.0, 10.0),
	vec4(12.0,  4.0, 14.0,  6.0),
	vec4( 3.0, 11.0,  1.0,  9.0),
	vec4(15.0,  7.0, 13.0,  5.0));

void fragment() {
	vec3 col = texture(screen_tex, SCREEN_UV).rgb;

	// Lift/gain grade, then split-tone shadows vs highlights by luminance.
	col = lift + col * (gain - lift);
	float luma = dot(col, vec3(0.299, 0.587, 0.114));
	vec3 tone = mix(split_shadows, split_highlights, smoothstep(0.15, 0.7, luma));
	col = mix(col, col * (tone * 2.0), split_amount);

	// Saturation nudge keeps the posterized palette lively.
	float grey = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(grey), col, saturation_boost);

	if (vignette > 0.0) {
		vec2 d = SCREEN_UV - 0.5;
		col *= 1.0 - vignette * smoothstep(0.35, 0.85, length(d * vec2(1.25, 1.0)));
	}

	// Ordered dither before quantization: smooth gradients become pixel steps.
	int bx = int(mod(FRAGCOORD.x, 4.0));
	int by = int(mod(FRAGCOORD.y, 4.0));
	float threshold = (BAYER[by][bx] / 16.0 - 0.5) * dither_strength;
	if (luma_quantize) {
		float y = dot(col, vec3(0.25, 0.5, 0.25));
		float co = dot(col, vec3(0.5, 0.0, -0.5));
		float cg = dot(col, vec3(-0.25, 0.5, -0.25));
		y = floor((y + threshold) * levels + 0.5) / levels;
		co = floor(co * chroma_levels + 0.5) / chroma_levels;
		cg = floor(cg * chroma_levels + 0.5) / chroma_levels;
		col = vec3(y + co - cg, y + cg, y - co - cg);
	} else {
		col += threshold;
		col = floor(col * levels + 0.5) / levels;
	}
	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
