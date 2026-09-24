shader_type spatial;
// RUNEBOUND terrain/rock surface (M06): one material family for flat ground,
// dressing hulls and — unchanged — the M08 heightmap terrain.
//  * World-space mapping at a fixed texel density: tops/floors project on XZ,
//    sides on XY/ZY picked by the dominant axis (hard, pixel-crisp), V = height
//    so basalt columns stay vertical.
//  * Slope blend: normal.y decides top vs side layer, dithered per texel so the
//    transition is a pixel edge, not a smear.
//  * Two top layers (A/B) mixed by a low-frequency macro noise, decided per
//    texel for crisp pixel boundaries.
//  * Optional sparse ember specks on layer B (dim, below the glow threshold,
//    slow flicker) — environment emissive, never threat-red.
//  * Optional paving (plazas, roads): circles and segments in world XZ switch
//    top texels to a third texture, with a ragged dithered edge. Off when
//    both counts are 0 (the loops never run).
//  * Optional rune inlays: thin emissive channels along line segments with a
//    cross-bar glyph every few metres (Spire floors). Straight lines only —
//    rings stay the player's ground-VFX shape.
//  * Vertex color multiplies albedo (baked AO / strata on hulls; white on
//    plain meshes).
render_mode diffuse_toon, specular_disabled;

uniform sampler2D top_a : source_color, filter_nearest_mipmap_anisotropic, repeat_enable;
uniform sampler2D top_b : source_color, filter_nearest_mipmap_anisotropic, repeat_enable;
uniform sampler2D side_tex : source_color, filter_nearest_mipmap_anisotropic, repeat_enable;
uniform sampler2D macro_noise : filter_linear, repeat_enable;
uniform float px_per_m = 32.0;
uniform float tile_px = 64.0;
uniform float macro_scale = 0.035;      // noise repeats per metre
uniform float layer_b_amount : hint_range(0.0, 1.0) = 0.35;
uniform float slope_top = 0.72;         // normal.y above this = top layer
uniform float ember_density : hint_range(0.0, 0.02) = 0.004;
uniform vec4 ember_color : source_color = vec4(0.66, 0.27, 0.11, 1.0);
uniform float ember_energy = 0.7;
uniform vec4 tint : source_color = vec4(1.0);
uniform sampler2D paving : source_color, filter_nearest_mipmap_anisotropic, repeat_enable;
uniform int paved_circles = 0;   // circles[i] = (x, z, radius, 0)
uniform vec4 circles[4];
uniform int paved_paths = 0;     // paths[i] = (x0, z0, x1, z1)
uniform vec4 paths[8];
uniform float path_width = 1.8;
uniform float paving_ragged = 0.45;  // metres of edge noise
uniform int use_mask = 0;            // M08: baked trail mask instead of / on top of segments
uniform sampler2D path_mask : hint_default_black, filter_linear, repeat_disable;
uniform vec4 mask_bounds = vec4(0.0, 0.0, 1.0, 1.0);  // world x, z, width, depth of the mask
uniform int rune_lines = 0;      // lines[i] = (x0, z0, x1, z1)
uniform vec4 lines[16];
uniform float rune_width = 0.1;
uniform float rune_glyph_every = 1.6;
uniform vec4 rune_color : source_color = vec4(0.37, 0.88, 0.91, 1.0);
uniform float rune_energy = 0.7;
uniform float roughness_toon : hint_range(0.0, 1.0) = 0.6;

varying vec3 world_pos;
varying vec3 world_normal;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// 4x4 ordered-dither threshold without a local array (arrays spill to
// memory on some iGPUs): bit-interleaved Bayer from the cell coordinates.
float bayer4(vec2 cell) {
	vec2 c = mod(cell, 4.0);
	vec2 a = mod(c, 2.0);
	vec2 b = floor(c * 0.5);
	// M2 = [[0, 2], [3, 1]]; M4 = 4 * M2(low bits) + M2(high bits)
	float v = 4.0 * (2.0 * a.x * (1.0 - a.y) + a.x * a.y + 3.0 * (1.0 - a.x) * a.y)
		+ (2.0 * b.x * (1.0 - b.y) + b.x * b.y + 3.0 * (1.0 - b.x) * b.y);
	return v / 16.0;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float uv_per_m = px_per_m / tile_px;
	vec3 n = normalize(world_normal);
	vec2 texel = floor(world_pos.xz * px_per_m);

	// Top vs side decision first (dithered per texel so the edge is stepped),
	// then fetch only what this pixel shows: flat ground never samples sides.
	vec2 side_uv = abs(n.x) > abs(n.z) ? vec2(world_pos.z, -world_pos.y) : vec2(world_pos.x, -world_pos.y);
	vec2 side_texel = floor(side_uv * px_per_m);
	float edge_dither = (bayer4(n.y > 0.5 ? texel : side_texel) - 0.5) * 0.14;
	bool is_top = n.y + edge_dither > slope_top;

	vec3 col;
	bool use_b = false;
	if (is_top) {
		float macro = texture(macro_noise, (texel / px_per_m) * macro_scale).r;
		use_b = macro + (bayer4(texel) - 0.5) * 0.12 < layer_b_amount;
		vec2 top_uv = world_pos.xz * uv_per_m;
		// each top layer at its own tile size (64 px = 2 m, 128 px = 4 m, ...)
		col = use_b ? texture(top_b, world_pos.xz * px_per_m / float(textureSize(top_b, 0).x)).rgb
			: texture(top_a, world_pos.xz * px_per_m / float(textureSize(top_a, 0).x)).rgb;
		if (paved_circles + paved_paths > 0) {
			vec2 p = (texel + 0.5) / px_per_m;
			float d = 1e4;
			for (int i = 0; i < paved_circles; i++) {
				d = min(d, length(p - circles[i].xy) - circles[i].z);
			}
			for (int i = 0; i < paved_paths; i++) {
				vec2 a = paths[i].xy;
				vec2 ab = paths[i].zw - a;
				float t = clamp(dot(p - a, ab) / max(dot(ab, ab), 1e-4), 0.0, 1.0);
				d = min(d, length(p - a - ab * t) - path_width * 0.5);
			}
			float ragged = (texture(macro_noise, p * 0.3).r - 0.5) * 2.0 * paving_ragged
				+ (bayer4(texel) - 0.5) * 0.2;
			if (d + ragged < 0.0) {
				// own tile size (paving tiles are larger: big plazas hide the repeat)
				col = texture(paving, world_pos.xz * px_per_m / float(textureSize(paving, 0).x)).rgb;
				use_b = false;  // no ember specks on paving
			}
		}
		if (use_mask == 1) {
			vec2 p = (texel + 0.5) / px_per_m;
			float m = texture(path_mask, (p - mask_bounds.xy) / mask_bounds.zw).r;
			if (m + (bayer4(texel) - 0.5) * 0.5 > 0.5) {
				col = texture(paving, world_pos.xz * px_per_m / float(textureSize(paving, 0).x)).rgb;
				use_b = false;
			}
		}
	} else {
		col = texture(side_tex, side_uv * uv_per_m).rgb;
	}

	float inlay = 0.0;
	if (is_top && rune_lines > 0) {
		vec2 p = (texel + 0.5) / px_per_m;
		for (int i = 0; i < rune_lines; i++) {
			vec2 a = lines[i].xy;
			vec2 ab = lines[i].zw - a;
			float len = max(length(ab), 1e-4);
			float t = clamp(dot(p - a, ab) / (len * len), 0.0, 1.0);
			float d = length(p - a - ab * t);
			float s = t * len;
			float glyph = step(abs(fract(s / rune_glyph_every) - 0.5), 0.045);
			if (d < rune_width * (0.5 + 1.8 * glyph)) {
				inlay = 1.0;
			}
		}
		if (inlay > 0.0) {
			col *= 0.35;  // carved channel
		}
	}

	ALBEDO = col * tint.rgb * COLOR.rgb;
	ROUGHNESS = roughness_toon;
	if (inlay > 0.0) {
		float pulse = 0.8 + 0.2 * sin(TIME * 0.9 + world_pos.x * 0.21 + world_pos.z * 0.13);
		EMISSION = rune_color.rgb * rune_energy * pulse;
	}

	// Ember specks: only on scorched top texels, dim and slowly breathing.
	if (use_b && ember_density > 0.0) {
		float h = hash12(texel);
		if (h < ember_density) {
			float flicker = 0.55 + 0.45 * sin(TIME * (0.8 + h * 90.0) + h * 6283.0);
			EMISSION = ember_color.rgb * ember_energy * flicker;
		}
	}
}
