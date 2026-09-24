shader_type spatial;
// M06 player-side ground marker (ART_BIBLE VFX rule): a BROKEN ring of dashes,
// never a filled disc, so nothing the player casts (or any shockwave) can be
// read as an enemy telegraph. Procedural and snapped to the VFX pixel grid, so
// dashes stay crisp and equally thick at any radius.
//   lit     lights the dashes one by one (Fracture Rune arming)
//   ring_m  current ring radius (shockwaves expand it; <= radius_m)
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 color : source_color = vec4(0.5, 0.85, 1.0, 0.6);
uniform float lit : hint_range(0.0, 1.0) = 1.0;
uniform float segments = 8.0;
uniform float gap = 0.35;              // fraction of each segment left open
uniform float width_m = 0.12;
uniform float radius_m = 1.0;          // plane half-size in metres
uniform float ring_m = 1.0;
uniform float px_per_m = 32.0;

void fragment() {
	vec2 grid = vec2(radius_m * 2.0 * px_per_m);
	vec2 uv = (floor(UV * grid) + 0.5) / grid;
	vec2 p = uv * 2.0 - 1.0;
	float d = length(p) * radius_m;                    // metres from the centre
	float band = step(ring_m - width_m, d) * step(d, ring_m);
	float a = (atan(p.y, p.x) / 6.2831853) + 0.5;      // 0..1 around the ring
	float seg = fract(a * segments);
	float dash = step(gap * 0.5, seg) * step(seg, 1.0 - gap * 0.5);
	float on = step(floor(a * segments) / segments, lit - 0.0001);
	ALBEDO = color.rgb;
	ALPHA = color.a * band * dash * mix(0.25, 1.0, on);  // unlit dashes stay faint
}
