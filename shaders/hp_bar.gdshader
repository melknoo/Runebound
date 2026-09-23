shader_type spatial;
// World-space enemy HP bar: billboard quad, pixel border, fill fraction.
render_mode unshaded, depth_test_disabled, shadows_disabled;

uniform float fill : hint_range(0.0, 1.0) = 1.0;
uniform vec3 fill_color : source_color = vec3(0.88, 0.25, 0.2);
uniform vec3 back_color : source_color = vec3(0.12, 0.07, 0.1);
uniform vec3 border_color : source_color = vec3(0.02, 0.02, 0.04);

void vertex() {
	// Billboard: keep world position, take orientation from the camera.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
	// Stepped fill edge so the bar drains in chunky pixel increments.
	float stepped = floor(fill * 24.0) / 24.0;
	vec3 col = UV.x <= stepped ? fill_color : back_color;
	if (UV.x < 0.025 || UV.x > 0.975 || UV.y < 0.14 || UV.y > 0.86) {
		col = border_color;
	}
	ALBEDO = col;
}
