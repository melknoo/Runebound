class_name CursedGround
extends PoiPuzzle
## M12 Ashwick's cursed graveyard. While its three curse lanterns burn, every
## heal a hero receives on this ground heals HEAL_MULT as much (each owner
## judges its own hero: the curse is world state every machine has), and the
## dead rise out of the graves around the heroes (buried shamblers, at most
## RISEN_MAX). Break the lanterns - a camp of three that never comes back -
## and the curse lifts for good: the mist goes, the risen fall, and the
## priest's ghost appears to tell what happened here.

const RADIUS := 13.0
const HEAL_MULT := 0.7
const RISE_EVERY := 6.0
const RISEN_MAX := 3
const RISE_NEAR := 18.0
const LANTERN_RING := 6.0
const CLEANSE_XP := 120
const CURSE := Color("#C8D86A")

var spawner: EncounterSpawner
var ghost: Ghost
var graves: Array[Vector3] = []
var risen: Array[EnemyBase] = []
var _rise_left: float = 2.0
var _cursed_hero: Player = null
var _mist: GPUParticles3D
var _glow: OmniLight3D


static func build(zone: ZoneBase, poi: Dictionary, grave_spots: Array[Vector3]) -> CursedGround:
	var g := CursedGround.new()
	g.id = String(poi.get("id", ""))
	g.name = "Cursed_" + g.id
	g.act_range = RADIUS
	g.graves = grave_spots
	var centre := ZoneLayout.pos_of(poi)
	centre.y = zone.ground_y(centre)
	zone.world.add_child(g)
	g.global_position = centre
	var sp := EncounterSpawner.new()  # the lanterns: a camp of three that never re-arms
	sp.name = "Lanterns_" + g.id
	sp.composition = ["curse_lantern", "curse_lantern", "curse_lantern"]
	sp.trigger_radius = 26.0
	sp.camp_id = g.id
	sp.respawn_minutes = 0.0
	sp.leash = 0.0
	for k in 3:
		var a := PoiBuilder.yaw_of(poi) + TAU * float(k) / 3.0 + 0.5
		sp.spots.append(centre + Vector3(cos(a), 0.0, sin(a)) * LANTERN_RING)
	sp.set_meta(&"poi_id", g.id)
	zone.world.add_child(sp)
	sp.global_position = centre
	g.spawner = sp
	sp.cleared.connect(g._on_lanterns_broken)  # only the authority's camp ever clears
	g.ghost = Ghost.build(zone, {"id": "ghost_priest", "text": "lore.ghost.priest", "rig": "druid",
		"pos": [centre.x + 1.5, centre.z - 1.0], "yaw": PoiBuilder.yaw_of(poi) + PI})
	g._build_looks()
	g.apply_state(g.state)
	return g


func _build_looks() -> void:
	if not Net.has_view():
		return
	_glow = OmniLight3D.new()
	_glow.light_color = CURSE
	_glow.light_energy = 0.9
	_glow.omni_range = RADIUS
	_glow.position = Vector3(0, 2.5, 0)
	add_child(_glow)
	_mist = GPUParticles3D.new()
	_mist.amount = 40
	_mist.lifetime = 4.0
	_mist.position = Vector3(0, 0.3, 0)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = RADIUS * 0.8
	pm.direction = Vector3.UP
	pm.spread = 30.0
	pm.initial_velocity_min = 0.05
	pm.initial_velocity_max = 0.25
	pm.gravity = Vector3(0, 0.05, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	var ramp := Gradient.new()
	ramp.set_color(0, Color(CURSE, 0.0))
	ramp.add_point(0.3, Color(CURSE, 0.14))
	ramp.set_color(ramp.get_point_count() - 1, Color(CURSE, 0.0))
	var ramp_tex := GradientTexture1D.new()
	ramp_tex.gradient = ramp
	pm.color_ramp = ramp_tex
	_mist.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(2.4, 1.0)
	var puff := Gradient.new()  # a soft round puff, not a card
	puff.set_color(0, Color(1, 1, 1, 1))
	puff.set_color(1, Color(1, 1, 1, 0))
	var puff_tex := GradientTexture2D.new()
	puff_tex.gradient = puff
	puff_tex.fill = GradientTexture2D.FILL_RADIAL
	puff_tex.fill_from = Vector2(0.5, 0.5)
	puff_tex.fill_to = Vector2(1.0, 0.5)
	puff_tex.width = 32
	puff_tex.height = 32
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = puff_tex
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	quad.material = mat
	_mist.draw_pass_1 = quad
	add_child(_mist)


func _present() -> void:
	var cursed := not is_solved()
	if _mist != null:
		_mist.emitting = cursed
	if _glow != null:
		_glow.visible = cursed
	if ghost != null:
		ghost.visible = not cursed


func _on_solved() -> void:
	_release_hero()
	var zone := ZoneBase.zone_of(self)
	if zone == null or zone.player == null or not is_instance_valid(zone.player):
		return
	if zone.player.global_position.distance_to(global_position) <= RADIUS + 12.0 and zone.hud != null:
		zone.hud.toast(Texts.t("ui.cursed.lifted"), CURSE)
		VFX.ground_ring(zone, global_position, CURSE, RADIUS, 0.8)
		Sfx.play_ui("ability_learned", -8.0)


## Authority: the third lantern broke.
func _on_lanterns_broken() -> void:
	if is_solved():
		return
	state["solved"] = true
	commit()
	reward_party(CLEANSE_XP, "ui.cursed.lifted")
	for e in risen:
		if is_instance_valid(e):
			e.dismiss()
	risen.clear()


## Every machine with a view: the curse on the local hero's heals.
func _process(_delta: float) -> void:
	var zone := ZoneBase.zone_of(self)
	var hero: Player = zone.player if zone != null else null
	var inside := not is_solved() and hero != null and is_instance_valid(hero) \
		and Vector2(hero.global_position.x - global_position.x, hero.global_position.z - global_position.z).length() <= RADIUS
	if inside and _cursed_hero != hero:
		_release_hero()
		_cursed_hero = hero
		hero.health.heal_mult = HEAL_MULT
		if zone.hud != null:
			zone.hud.toast(Texts.t("ui.cursed.enter"), CURSE)
	elif not inside and _cursed_hero != null:
		_release_hero()


func _release_hero() -> void:
	if _cursed_hero != null and is_instance_valid(_cursed_hero):
		_cursed_hero.health.heal_mult = 1.0
	_cursed_hero = null


## Authority: the dead rise near the heroes while a lantern burns.
func _physics_process(delta: float) -> void:
	if Net.is_client() or is_solved() or spawner == null or spawner.state != EncounterSpawner.State.ACTIVE:
		return
	var zone := ZoneBase.zone_of(self)
	if zone == null:
		return
	var live: Array[EnemyBase] = []
	for e in risen:
		if is_instance_valid(e) and e.ai_state != EnemyBase.AIState.DEAD:
			live.append(e)
	risen = live
	_rise_left -= delta
	var near := zone.players_within(global_position, RISE_NEAR)
	if _rise_left > 0.0 or risen.size() >= RISEN_MAX or near.is_empty() or graves.is_empty():
		return
	_rise_left = RISE_EVERY
	var hero: Player = near[randi() % near.size()]
	var best := graves[0]
	var best_d := INF
	for spot in graves:  # a grave a few steps from that hero
		var d := absf(spot.distance_to(hero.global_position) - 5.0) + randf() * 2.0
		if d < best_d:
			best_d = d
			best = spot
	var e := zone.spawn_by_id("grave_shambler", zone.ground_point(best + Vector3(0.0, 0.0, 0.8), 0.2))
	e.home = global_position
	e.leash = 24.0
	risen.append(e)


func _exit_tree() -> void:
	_release_hero()
