shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_schlick_ggx;
// M13: dungeon water - opaque (no SCREEN or DEPTH reads: cheap on the iGPU),
// world-mapped pixel ripples drifting slowly, a few cold glints. The colours
// come from the zone's palette (WaterChannel sets them).

uniform vec4 deep : source_color = vec4(0.07, 0.2, 0.24, 1.0);
uniform vec4 shallow : source_color = vec4(0.11, 0.29, 0.32, 1.0);
uniform vec4 glint : source_color = vec4(0.36, 0.62, 0.64, 1.0);
uniform float px_per_m = 16.0;
uniform float speed = 0.3;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	vec2 p = floor(world_pos.xz * px_per_m) / px_per_m;  // snap to the pixel grid
	float t = TIME * speed;
	float n = noise(p * 0.8 + vec2(t, t * 0.6)) * 0.6 + noise(p * 2.1 - vec2(t * 0.7, t * 1.1)) * 0.4;
	vec3 col = mix(deep.rgb, shallow.rgb, step(0.55, n) * 0.6 + step(0.72, n) * 0.4);
	float g = step(0.86, noise(p * 3.3 + vec2(-t * 1.4, t)));
	col = mix(col, glint.rgb, g * 0.7);
	ALBEDO = col;
	ROUGHNESS = 0.25;
	EMISSION = col * 0.22;
}
