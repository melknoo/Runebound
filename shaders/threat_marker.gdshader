shader_type spatial;
// M06 enemy threat marker (ART_BIBLE colour roles): a filled crimson area with
// a near-white rim and visible fill progress, fog-exempt and snapped to the
// VFX pixel grid. shape 0 = disc (PlaneMesh UV centred); shape 1 = lane
// (rectangle; the fill runs from its start edge, UV.y = 1, to the far end);
// shape 2 = expanding band (boss shockwaves): filled between ring_r +- ring_w
// with a rim on both edges, the growing radius is its progress.
// Red is reserved for this: nothing the player casts may look like it.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

uniform vec4 base_color : source_color = vec4(0.91, 0.157, 0.235, 0.2);
uniform vec4 fill_color : source_color = vec4(0.91, 0.157, 0.235, 0.55);
uniform vec4 rim_color : source_color = vec4(1.0, 0.957, 0.941, 1.0);
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform int shape = 0;
uniform vec2 size_m = vec2(2.0, 2.0);   // world size of the plane
uniform float px_per_m = 32.0;          // art_spec texel_density.vfx_px_per_m
uniform float rim_m = 0.12;
uniform float ring_r = 1.0;             // shape 2: band centre radius (m)
uniform float ring_w = 0.8;             // shape 2: band half-width (m)

void fragment() {
	vec2 grid = size_m * px_per_m;
	vec2 uv = (floor(UV * grid) + 0.5) / grid;  // pixel snap: chunky edges
	float inside = 1.0;
	float rim;
	float filled;
	if (shape == 0) {
		float r = length(uv * 2.0 - 1.0);
		inside = step(r, 1.0);
		rim = step(1.0 - rim_m * 2.0 / size_m.x, r) * inside;
		filled = step(r, progress);
	} else if (shape == 2) {
		float d = abs(length((uv - 0.5) * size_m) - ring_r);
		inside = step(d, ring_w);
		rim = step(ring_w - rim_m * 1.5, d) * inside;
		filled = 1.0;
	} else {
		vec2 edge_m = min(uv, 1.0 - uv) * size_m;
		rim = step(min(edge_m.x, edge_m.y), rim_m);
		filled = step(1.0 - progress, uv.y);
	}
	vec4 c = mix(base_color, fill_color, filled);
	c = mix(c, rim_color, rim);
	ALBEDO = c.rgb;
	ALPHA = c.a * inside;
}
