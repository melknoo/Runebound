class_name WardingRune
extends Node3D
## M10 tank: Warding Rune - a ward on the ground; every hero standing inside
## takes `reduction` less damage while it lasts. It exists on every machine
## (HeroFx "warding_rune"): each one applies it to the heroes it simulates -
## in co-op that is its own hero, the hybrid authority rule (an owner takes its
## own hits, Player.damage_taken_mult asks reduction_at).

static var active: Array[WardingRune] = []

var radius: float = 4.0
var duration: float = 8.0
var reduction: float = 0.25
var _age: float = 0.0


## The strongest ward covering `hero` (0 when none).
static func reduction_at(hero: Node3D) -> float:
	var best := 0.0
	for w in active:
		if not is_instance_valid(w) or not w.is_inside_tree():
			continue
		var d := hero.global_position - w.global_position
		d.y = 0.0
		if d.length() <= w.radius and absf(hero.global_position.y - w.global_position.y) < 3.0:
			best = maxf(best, w.reduction)
	return best


func _enter_tree() -> void:
	active.append(self)


func _exit_tree() -> void:
	active.erase(self)


func _ready() -> void:
	if not Net.has_view():
		return  # the dedicated server keeps the ward (its proxies ask nothing) without drawing it
	var glyph := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(radius * 0.9, radius * 0.9)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.3
	if ResourceLoader.exists("res://assets/vfx/glyph.png"):
		mat.albedo_texture = load("res://assets/vfx/glyph.png")
	mat.albedo_color = ArtKit.color("color_roles.player_accent.hot", Color(0.62, 0.95, 0.9))
	mat.emission_enabled = true
	mat.emission = ArtKit.color("color_roles.player_accent.body", Color(0.24, 0.75, 0.7))
	mat.emission_energy_multiplier = 1.4
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.disable_receive_shadows = true
	plane.material = mat
	glyph.mesh = plane
	glyph.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glyph.position.y = 0.04
	add_child(glyph)
	# a player mark (broken ring), never the enemies' red disc; it fills over the ward's life
	VFX.player_ring(self, global_position, radius, duration, ArtKit.color("color_roles.player_accent.body"))
	var spin := glyph.create_tween().set_loops()
	spin.tween_property(glyph, "rotation:y", TAU, 9.0).from(0.0)


func _process(delta: float) -> void:
	_age += delta
	if _age >= duration:
		queue_free()
