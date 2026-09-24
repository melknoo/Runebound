shader_type spatial;
// M06 kit: environment parts that move in the wind (dead-grass tufts, hide
// banners). Same look as ArtKit.prop_material (toon, no specular, nearest
// atlas). The sway weight runs from 0 at anchor_y to 1 at full_y (local
// height; full_y < anchor_y hangs from the top, e.g. banners) and each
// instance is phase-shifted by its world position so neighbours never march
// in lockstep. MultiMesh-safe: everything per instance comes from MODEL_MATRIX.
render_mode diffuse_toon, specular_disabled;

uniform sampler2D atlas : source_color, filter_nearest_mipmap_anisotropic;
uniform float amplitude = 0.05;   // metres at full weight
uniform float speed = 1.6;
uniform float anchor_y = 0.0;
uniform float full_y = 0.3;
uniform vec2 wind_dir = vec2(0.8, 0.6);

void vertex() {
	float w = clamp((VERTEX.y - anchor_y) / (full_y - anchor_y), 0.0, 1.0);
	w *= w;
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float phase = TIME * speed + dot(origin.xz, vec2(0.37, 0.61));
	float gust = sin(phase) + 0.35 * sin(phase * 2.3 + 1.7);
	vec3 offset = vec3(wind_dir.x, 0.0, wind_dir.y) * gust * amplitude * w;
	VERTEX += inverse(mat3(MODEL_MATRIX)) * offset;  // world offset -> local
}

void fragment() {
	ALBEDO = texture(atlas, UV).rgb;
	ROUGHNESS = 0.75;
}
