shader_type spatial;
// M06 C5 portal gate: an upright pixel-snapped oval of swirling rune light
// between the floating arch stones. Teal = ancient rune magic (monoliths,
// lintels); the shape (a standing oval, never a ground ring) keeps it apart
// from the player's ground VFX. lit = 0: sealed (dim, still, grey).
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled;

uniform vec4 core_color : source_color = vec4(0.37, 0.88, 0.82, 1.0);
uniform vec4 edge_color : source_color = vec4(0.18, 0.32, 0.62, 1.0);
uniform vec4 sealed_color : source_color = vec4(0.36, 0.36, 0.42, 1.0);
uniform float lit : hint_range(0.0, 1.0) = 1.0;
uniform vec2 size_m = vec2(2.5, 3.1);
uniform float px_per_m = 16.0;

void fragment() {
	vec2 grid = size_m * px_per_m;
	vec2 uv = (floor(UV * grid) + 0.5) / grid;
	vec2 p = (uv - 0.5) * 2.0;
	float r = length(p);
	if (r > 1.0) {
		discard;
	}
	float a = atan(p.y, p.x);
	float swirl = sin(a * 3.0 + r * 8.0 - TIME * 2.4 * lit);
	float band = step(0.15, swirl);
	vec3 col = mix(edge_color.rgb, core_color.rgb, band * (1.0 - r * 0.45));
	float rim = step(0.9, r);
	col = mix(col, vec3(0.88, 1.0, 0.97), rim);
	col = mix(sealed_color.rgb * (0.6 + 0.4 * rim), col, lit);
	ALBEDO = col;
	ALPHA = mix(0.28 + 0.3 * rim, 0.55 + 0.35 * band + 0.1 * rim, lit);
}
