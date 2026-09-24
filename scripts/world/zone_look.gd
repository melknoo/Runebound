class_name ZoneLook
extends Resource
## Data-driven zone presentation (M06): sky, light, fog, glow, tonemap and
## post grading in one resource. A zone that returns one from _zone_look()
## gets the new environment path; zones without one keep their legacy
## _build_environment untouched (opt-in until the Style Gate passes).

## Routes the zone's greybox materials through ArtKit (world-mapped pixel
## textures at the spec texel density).
@export var art_pass: bool = true

## Interior (Spire): flat background colour, no sky, no sun disc; the key
## light becomes a faint cold top light, the rim light is skipped at energy 0.
@export var interior: bool = false
@export var background: Color = Color(0.05, 0.035, 0.07)

@export_group("Sky")
@export var sky_top: Color = Color(0.11, 0.07, 0.19)
@export var sky_mid: Color = Color(0.29, 0.14, 0.27)
@export var sky_horizon: Color = Color(0.72, 0.31, 0.23)
@export var sun_disc: Color = Color(1.0, 0.85, 0.66)
@export var sky_bands: float = 7.0
@export var cloud_color: Color = Color(0.55, 0.28, 0.33)
@export var cloud_lit_color: Color = Color(0.86, 0.48, 0.38)
@export var cloud_amount: float = 0.55
@export var silhouette_far: Color = Color(0.30, 0.16, 0.24)
@export var silhouette_near: Color = Color(0.19, 0.11, 0.16)
## Landmark peaks on the horizon: (azimuth rad, half-width rad, height).
@export var volcano: Vector3 = Vector3(0.9, 0.22, 0.13)
@export var spire: Vector3 = Vector3(0.12, 0.018, 0.24)

@export_group("Light")
@export var sun_rotation_deg: Vector3 = Vector3(-42, 125, 0)
@export var sun_color: Color = Color(1.0, 0.78, 0.58)
@export var sun_energy: float = 1.25
@export var rim_rotation_deg: Vector3 = Vector3(-25, -55, 0)
@export var rim_color: Color = Color(0.45, 0.4, 0.8)
@export var rim_energy: float = 0.45
@export var ambient_color: Color = Color(0.29, 0.23, 0.32)
@export var ambient_energy: float = 1.0

@export_group("Fog")
@export var fog_color: Color = Color(0.37, 0.25, 0.27)
@export var fog_density: float = 0.014
@export var fog_height: float = 0.5
@export var fog_height_density: float = 0.06
## Keep 0: aerial perspective samples the sky radiance map, which ZoneLook
## deliberately never builds (reflections off) â€” it tinted near ground olive.
@export var fog_aerial: float = 0.0
@export var fog_sky_affect: float = 0.0
## Camera-attached falling ash (0 = none, 1 = 180 flakes around the camera).
@export var ash_fall: float = 0.0

@export_group("Glow & tonemap")
@export var glow_intensity: float = 0.7
@export var glow_bloom: float = 0.05
@export var glow_threshold: float = 1.1
@export var tonemap: Environment.ToneMapper = Environment.TONE_MAPPER_LINEAR
@export var exposure: float = 1.0

@export_group("Post grading")
@export var post_levels: float = 14.0
@export var post_dither: float = 0.02
@export var post_saturation: float = 1.06
@export var lift: Color = Color(0.0, 0.0, 0.0)
@export var gain: Color = Color(1.0, 1.0, 1.0)
@export var split_shadows: Color = Color(0.5, 0.5, 0.5)
@export var split_highlights: Color = Color(0.5, 0.5, 0.5)
@export var split_amount: float = 0.0
@export var vignette: float = 0.0
## Posterize luma in bands but chroma finer (no olive/red hue flips in darks).
@export var luma_quantize: bool = true


## Runehold (hub + training grounds): the Highlands' twilight family, but a
## warm low dawn sun from the east-southeast, lighter haze, more ambient â€”
## the safe place reads brighter and greener than anything outside.
static func runehold() -> ZoneLook:
	var l := ZoneLook.new()
	l.sky_top = ArtKit.color("palettes.runehold.sky.top")
	l.sky_mid = ArtKit.color("palettes.runehold.sky.mid")
	l.sky_horizon = ArtKit.color("palettes.runehold.sky.horizon")
	l.sun_disc = ArtKit.color("palettes.runehold.sky.sun")
	l.fog_color = ArtKit.color("palettes.runehold.fog")
	l.ambient_color = ArtKit.color("palettes.runehold.ambient")
	l.ambient_energy = 1.45
	l.sun_rotation_deg = Vector3(-32, 67.5, 0)
	l.sun_color = Color(1.0, 0.84, 0.64)
	l.sun_energy = 1.35
	l.rim_rotation_deg = Vector3(-25, -112.5, 0)
	l.rim_color = Color(0.46, 0.42, 0.78)
	l.rim_energy = 0.45
	l.fog_density = 0.011
	l.silhouette_far = Color(0.33, 0.2, 0.28)
	l.silhouette_near = Color(0.21, 0.14, 0.18)
	l.volcano = Vector3(0.9, 0.22, 0.0)  # the ash peak is out of sight here
	l.spire = Vector3(0.12, 0.018, 0.2)
	l.cloud_color = Color(0.4, 0.22, 0.3)
	l.cloud_lit_color = Color(0.76, 0.46, 0.38)
	l.cloud_amount = 0.3
	l.split_shadows = Color(0.46, 0.46, 0.56)
	l.split_highlights = Color(0.58, 0.52, 0.44)
	l.split_amount = 0.3
	l.vignette = 0.15
	return l


## Shattered Spire interior: near-black violet, cold top light, dense low
## haze; crystals, beacons and telegraphs carry the light.
static func spire_interior() -> ZoneLook:
	var l := ZoneLook.new()
	l.interior = true
	l.background = ArtKit.color("palettes.spire.background")
	l.ambient_color = ArtKit.color("palettes.spire.ambient")
	l.ambient_energy = 1.6
	l.fog_color = ArtKit.color("palettes.spire.fog")
	l.fog_density = 0.024
	l.fog_height = 0.2
	l.fog_height_density = 0.04
	l.sun_rotation_deg = Vector3(-70, 20, 0)
	l.sun_color = Color(0.55, 0.5, 0.86)
	l.sun_energy = 0.7
	l.rim_energy = 0.0
	l.glow_intensity = 0.8
	l.glow_bloom = 0.08
	l.glow_threshold = 1.0
	l.exposure = 1.2
	l.split_shadows = Color(0.47, 0.44, 0.6)
	l.split_highlights = Color(0.48, 0.56, 0.58)
	l.split_amount = 0.35
	l.vignette = 0.25
	return l
