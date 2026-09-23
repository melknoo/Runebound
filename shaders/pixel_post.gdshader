shader_type canvas_item;
// Fullscreen pixel-fantasy post: color posterization + ordered (Bayer) dither.
// Draws on a transparent ColorRect above the 3D view, below the HUD.

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float levels : hint_range(2.0, 32.0) = 10.0;
uniform float dither_strength : hint_range(0.0, 0.2) = 0.035;
uniform float saturation_boost : hint_range(0.5, 1.6) = 1.08;

const mat4 BAYER = mat4(
	vec4( 0.0,  8.0,  2.0, 10.0),
	vec4(12.0,  4.0, 14.0,  6.0),
	vec4( 3.0, 11.0,  1.0,  9.0),
	vec4(15.0,  7.0, 13.0,  5.0));

void fragment() {
	vec3 col = texture(screen_tex, SCREEN_UV).rgb;

	// Saturation nudge keeps the posterized palette lively.
	float grey = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(grey), col, saturation_boost);

	// Ordered dither before quantization: smooth gradients become pixel steps.
	int bx = int(mod(FRAGCOORD.x, 4.0));
	int by = int(mod(FRAGCOORD.y, 4.0));
	float threshold = (BAYER[by][bx] / 16.0 - 0.5) * dither_strength;
	col += threshold;

	col = floor(col * levels + 0.5) / levels;
	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
