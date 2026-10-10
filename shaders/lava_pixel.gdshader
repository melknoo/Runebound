shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled;
// M13: dungeon lava - opaque like the water (no SCREEN or DEPTH reads), a
// dark crust broken into world-mapped pixel plates that drift slowly, hot
// light glowing in the cracks between them and pulsing in a few spots. The
// colours come from the zone's palette (WaterChannel / CollapsingFloor).

uniform vec4 crust : source_color = vec4(0.16, 0.07, 0.05, 1.0);
uniform vec4 hot : source_color = vec4(0.72, 0.25, 0.1, 1.0);
uniform vec4 glow : source_color = vec4(1.0, 0.69, 0.25, 1.0);
uniform float px_per_m = 12.0;
uniform float speed = 0.08;
uniform float glow_energy = 2.4;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

vec2 hash2(vec2 p) {
	return fract(sin(vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash2(i).x;
	float b = hash2(i + vec2(1.0, 0.0)).x;
	float c = hash2(i + vec2(0.0, 1.0)).x;
	float d = hash2(i + vec2(1.0, 1.0)).x;
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// distance to the nearest crack between crust plates (Voronoi edges)
float cracks(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = hash2(i + g);
			float d = length(g + o - f);
			if (d < d1) {
				d2 = d1;
				d1 = d;
			} else if (d < d2) {
				d2 = d;
			}
		}
	}
	return d2 - d1;
}

void fragment() {
	vec2 p = floor(world_pos.xz * px_per_m) / px_per_m;  // snap to the pixel grid
	float t = TIME * speed;
	vec2 flow = p * 0.9 + vec2(t, t * 0.4);
	float edge = cracks(flow);
	float pulse = noise(p * 0.6 - vec2(t * 2.0, t)) * 0.5 + 0.5 * sin(TIME * 1.3 + noise(p * 0.3) * 6.28);
	float molten = step(edge, 0.12 + 0.08 * pulse);
	float warm = step(edge, 0.24) * (1.0 - molten);
	vec3 col = crust.rgb;
	col = mix(col, hot.rgb, warm * 0.85);
	col = mix(col, glow.rgb, molten);
	ALBEDO = col * 0.35;
	ROUGHNESS = 0.9;
	EMISSION = (hot.rgb * warm * 0.6 + glow.rgb * molten + crust.rgb * 0.15) * glow_energy;
}
