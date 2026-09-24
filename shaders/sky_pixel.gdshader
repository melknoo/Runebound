shader_type sky;
// RUNEBOUND pixel sky (M06): banded gradient designed WITH the post-process
// posterizer (explicit bands instead of accidental ones), hard pixel sun disc,
// slow three-level pixel clouds, and layered distant silhouettes (ridges,
// peaks, a volcano, an optional landmark spire) computed from the view
// azimuth — backdrop for any outdoor zone without placing meshes.
// Ambient light and reflections do NOT come from this sky (ZoneLook sets an
// ambient color and disables sky reflections), so animating it never forces a
// radiance-cubemap update.

uniform vec4 top_color : source_color = vec4(0.11, 0.07, 0.19, 1.0);
uniform vec4 mid_color : source_color = vec4(0.29, 0.14, 0.27, 1.0);
uniform vec4 horizon_color : source_color = vec4(0.72, 0.31, 0.23, 1.0);
uniform vec4 sun_color : source_color = vec4(1.0, 0.85, 0.66, 1.0);
uniform float bands = 7.0;
uniform float sun_size = 0.035;
uniform sampler2D clouds : filter_nearest, repeat_enable;
uniform vec4 cloud_color : source_color = vec4(0.55, 0.28, 0.33, 1.0);
uniform vec4 cloud_lit_color : source_color = vec4(0.86, 0.48, 0.38, 1.0);
uniform float cloud_amount : hint_range(0.0, 1.0) = 0.55;
uniform float cloud_speed = 0.004;
// Silhouette layers (far -> near): color, base height, amplitude, frequency.
uniform vec4 far_color : source_color = vec4(0.30, 0.16, 0.24, 1.0);
uniform vec4 near_color : source_color = vec4(0.19, 0.11, 0.16, 1.0);
uniform float far_height = 0.07;
uniform float near_height = 0.035;
// Landmarks: azimuth (radians, 0 = -Z/north), width, height.
uniform vec3 volcano = vec3(0.9, 0.22, 0.13);
uniform vec3 spire = vec3(0.12, 0.018, 0.24);
uniform vec4 spire_glow : source_color = vec4(0.62, 0.40, 0.95, 1.0);
uniform float pixel_step = 0.004;   // quantizes the silhouette edges into pixel steps
// Azimuth lookup baked once per zone (ZoneBase): R far ridge + volcano, G near
// ridge, B landmark spire, heights / 0.4. One fetch instead of ~10 noise calls.
uniform sampler2D silhouettes : filter_linear, repeat_enable;

void sky() {
	vec3 dir = EYEDIR;
	float el = dir.y;
	float az = atan(dir.x, -dir.z);

	// Banded gradient: horizon -> mid -> top, quantized into explicit bands.
	float t = clamp(el, 0.0, 1.0);
	float bt = floor(pow(t, 0.55) * bands) / bands;
	vec3 col = bt < 0.5 ? mix(horizon_color.rgb, mid_color.rgb, bt * 2.0)
		: mix(mid_color.rgb, top_color.rgb, (bt - 0.5) * 2.0);

	// Clouds: a thin band of long streaks low over the horizon (they frame the
	// silhouettes instead of filling the view overhead), slow drift.
	if (el > 0.02 && el < 0.42) {
		vec2 cuv = vec2(az * 1.6 + TIME * cloud_speed, el * 5.5);
		float c = texture(clouds, cuv).r;
		float band = smoothstep(0.02, 0.1, el) * (1.0 - smoothstep(0.22, 0.42, el));
		if (c > 1.0 - cloud_amount && band > 0.25) {
			col = mix(col, c > 0.9 ? cloud_lit_color.rgb : cloud_color.rgb, band);
		}
	}

	// Sun: hard-edged pixel disc with one halo band.
	float sd = distance(dir, normalize(LIGHT0_DIRECTION));
	if (LIGHT0_ENABLED) {
		if (sd < sun_size) {
			col = sun_color.rgb;
		} else if (sd < sun_size * 2.2) {
			col = mix(col, sun_color.rgb, 0.35);
		}
	}

	// Distant silhouettes (stepped edges read as pixel art after posterize).
	vec3 sil = texture(silhouettes, vec2(az / 6.2831853 + 0.5, 0.5)).rgb * 0.4;
	float far_h = sil.r;
	float near_h = sil.g;
	float spire_h = sil.b;
	far_h = floor(far_h / pixel_step) * pixel_step;
	near_h = floor(near_h / pixel_step) * pixel_step;
	if (el < max(far_h, spire_h)) {
		col = far_color.rgb;
		if (spire_h > far_h && el < spire_h && el > spire_h - 0.015) {
			col = spire_glow.rgb;   // the Spire's crown catches violet light
		}
	}
	if (el < near_h) {
		col = near_color.rgb;
	}
	if (el < 0.0) {
		col = near_color.rgb * 0.8;
	}
	COLOR = col;
}
