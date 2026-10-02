class_name HeroFx
extends Object
## M09: the look (and sound) of a hero's actions, playable on any machine.
## The acting hero plays an entry through Player.hero_fx(); in co-op its owner
## also sends it (HERO_FX) and every other client plays the same entry on its
## puppet of that hero. Gameplay never lives here: the projectile and rune a
## puppet shows are visual copies (the owner's real ones deal the damage).
## M10 exception, the ally effects: a Warding Rune and an Aegis barrier are
## built on every machine, and each machine applies them to the heroes it
## simulates itself (its own hero; offline every hero) - an owner takes its
## own hits, so it must also own its own protection.
## M11 targeted ally effects (the druid) name their target with a hero ref
## (ZoneBase.hero_ref): every machine shows the look, only the target's owner
## applies it; offline the authority books the heal's threat right there.


static func play(hero: Player, kind: StringName, a: Array) -> void:
	if hero == null or not hero.is_inside_tree():
		return
	var scene := hero.get_tree().current_scene
	match kind:
		&"dodge":
			VFX.dodge_dust(scene, a[0] as Vector3, a[1] as Vector3)
			Sfx.play("dodge", a[0] as Vector3, -4.0)
		&"slash":
			VFX.melee_slash(scene, a[0] as Vector3, a[1] as Vector3, bool(a[2]))
		&"ember_cast":
			VFX.ember_cast(scene, a[0] as Vector3)
			Sfx.play("ember_cast", a[0] as Vector3, -3.0)
		&"ember_fire":
			Sfx.play("ember_fire", a[0] as Vector3, -2.0, 0.1)
			var ember := hero.ability(&"ember_lance")
			if hero.net_role == Player.NetRole.PUPPET and ember != null:
				var proj := EmberLanceProjectile.new()
				proj.visual_only = true
				proj.setup(ember, a[1] as Vector3, hero)
				proj.position = a[0] as Vector3  # before add_child, like every projectile
				scene.add_child(proj)
		&"rune_bolt":  # [muzzle, dir] M10: puppets fly a visual copy
			Sfx.play("ember_cast", a[0] as Vector3, -12.0, 0.15, 1.6)
			var bolt_data := hero.ability(&"rune_bolt")
			if hero.net_role == Player.NetRole.PUPPET and bolt_data != null:
				var bolt := SpellBolt.new()
				bolt.visual_only = true
				bolt.setup(bolt_data, a[1] as Vector3, hero)
				bolt.position = a[0] as Vector3
				scene.add_child(bolt)
		&"slam":
			VFX.earthbreaker_slam(scene, a[0] as Vector3, float(a[1]))
			Sfx.play("earthbreaker_impact", a[0] as Vector3, 2.0, 0.06)
		&"storm_step":
			VFX.flash(scene, a[0] as Vector3 + Vector3(0, 1.0, 0), Color(0.8, 0.9, 1.0), 1.0, 0.1)
			Sfx.play("storm_step", a[0] as Vector3, -1.0, 0.08)
		&"storm_trail":
			VFX.storm_trail(scene, a[0] as Vector3, a[1] as Vector3)
		&"arc":  # [from, to, color, flash at the end]
			VFX.lightning_arc(scene, a[0] as Vector3, a[1] as Vector3, a[2] as Color)
			if bool(a[3]):
				VFX.flash(scene, a[1] as Vector3, Color(1.0, 1.0, 0.75), 0.6, 0.1)
		&"ring":
			VFX.ground_ring(scene, a[0] as Vector3, a[1] as Color, float(a[2]), float(a[3]))
		&"rune":
			var rune_data := hero.ability(&"fracture_rune")
			if hero.net_role == Player.NetRole.PUPPET and rune_data != null:
				var rune := FractureRune.new()
				rune.visual_only = true
				if a.size() > 2:
					rune.radius = float(a[2])
				rune.setup(rune_data, hero)
				rune.arm_time = float(a[1])
				rune.position = a[0] as Vector3
				scene.add_child(rune)
		&"barrier":
			VFX.player_ring(hero, hero.global_position, 1.1, float(a[0]), ArtKit.color("color_roles.player_accent.hot"))
			VFX.flash(scene, hero.global_position + Vector3(0, 1.1, 0), ArtKit.color("color_roles.player_accent.hot"), 1.0, 0.12)
		&"res_burst":
			var gold := ArtKit.color("color_roles.resonance.body")
			VFX.flash(scene, a[0] as Vector3 + Vector3(0, 1.0, 0), ArtKit.color("color_roles.resonance.hot"), 2.4, 0.18)
			VFX.ground_ring(scene, a[0] as Vector3, gold, float(a[1]), 0.35)
			VFX.burst(scene, a[0] as Vector3 + Vector3(0, 0.8, 0), {"tex": "shard", "amount": 14, "lifetime": 0.5,
				"size": 0.16, "spread": 90.0, "vel_min": 4.0, "vel_max": 8.0,
				"colors": [ArtKit.color("color_roles.resonance.hot"), Color(gold, 0.0)] as Array[Color]})
			Sfx.play("resonance_burst", a[0] as Vector3, 0.0, 0.05)
		&"sfx":
			Sfx.play(str(a[0]), a[1] as Vector3, float(a[2]), 0.1)
		# --- M10 Elementalist ---
		&"frost_nova":  # [pos, radius]
			VFX.frost_burst(scene, a[0] as Vector3, float(a[1]))
			VFX.ground_ring(scene, a[0] as Vector3, ArtKit.color("color_roles.frost.body"), float(a[1]), 0.3)
			Sfx.play("frost_nova", a[0] as Vector3, 0.0, 0.05)
		&"flame_wall":  # [center, axis, length, duration] - a visual copy on puppets
			var wall_data := hero.ability(&"flame_wall")
			if hero.net_role == Player.NetRole.PUPPET and wall_data != null:
				var wall := FlameWall.new()
				wall.visual_only = true
				wall.setup(wall_data, hero)
				wall.axis = a[1] as Vector3
				wall.length = float(a[2])
				wall.duration = float(a[3])
				wall.position = a[0] as Vector3
				scene.add_child(wall)
		&"ball_lightning":  # [muzzle, dir] - a visual copy on puppets
			var ball_data := hero.ability(&"ball_lightning")
			if hero.net_role == Player.NetRole.PUPPET and ball_data != null:
				var ball := BallLightning.new()
				ball.visual_only = true
				ball.setup(ball_data, a[1] as Vector3, hero)
				ball.position = a[0] as Vector3
				scene.add_child(ball)
		&"ember_fall":  # [pos] - a visual copy on puppets
			var fall_data := hero.ability(&"ember_fall")
			if hero.net_role == Player.NetRole.PUPPET and fall_data != null:
				var rock := EmberFall.new()
				rock.visual_only = true
				rock.setup(fall_data, hero)
				rock.position = a[0] as Vector3
				scene.add_child(rock)
		# --- M10 tank ---
		&"challenge":  # [pos, radius] the war cry's ring
			var gold := ArtKit.color("color_roles.resonance.body")
			VFX.ground_ring(scene, a[0] as Vector3, gold, float(a[1]), 0.45)
			VFX.flash(scene, a[0] as Vector3 + Vector3(0, 1.5, 0), ArtKit.color("color_roles.resonance.hot"), 1.8, 0.2)
			Sfx.play("rune_challenge", a[0] as Vector3, 0.0, 0.03)
		&"block":  # [pos] a blow glancing off Rune Wall
			VFX.flash(scene, a[0] as Vector3, ArtKit.color("color_roles.player_accent.hot"), 0.8, 0.08)
			VFX.burst(scene, a[0] as Vector3, {"tex": "spark", "amount": 6, "lifetime": 0.25, "size": 0.08,
				"spread": 60.0, "vel_min": 2.0, "vel_max": 4.5,
				"colors": [ArtKit.color("color_roles.player_accent.hot"), Color(ArtKit.color("color_roles.player_accent.body"), 0.0)] as Array[Color]})
			Sfx.play("block_clang", a[0] as Vector3, -2.0, 0.1)
		&"parry":  # [pos] a perfect parry
			VFX.flash(scene, a[0] as Vector3, ArtKit.color("color_roles.resonance.hot"), 1.5, 0.14)
			VFX.ground_ring(scene, hero.global_position, ArtKit.color("color_roles.resonance.body"), 2.5, 0.25)
			Sfx.play("parry_ring", a[0] as Vector3, 0.0, 0.03)
		&"rune_chain":  # [from, to]
			VFX.rune_chain(scene, a[0] as Vector3, a[1] as Vector3)
			Sfx.play("chain_throw", a[0] as Vector3, -2.0, 0.08)
		&"warding_rune":  # [pos, radius, duration, reduction] - an ally effect (see the header)
			var ward := WardingRune.new()
			ward.radius = float(a[1])
			ward.duration = float(a[2])
			ward.reduction = float(a[3])
			ward.position = a[0] as Vector3
			scene.add_child(ward)
			Sfx.play("ward_place", a[0] as Vector3, -1.0, 0.05)
		&"ally_barrier":  # [pos, amount, duration, radius] - Aegis of Runes, an ally effect
			var zone := ZoneBase.zone_of(hero)
			if zone != null:
				for ally in zone.players:
					if ally == hero or not is_instance_valid(ally) or ally.net_role != Player.NetRole.OWNER \
							or ally.health.is_dead or ally.global_position.distance_to(a[0] as Vector3) > float(a[3]):
						continue
					ally.grant_barrier(float(a[1]), float(a[2]))
		# --- M11 druid: ally effects with a target ref (see the header) ---
		&"ally_heal":  # [ref, amount]
			var target := _ally(hero, a[0])
			if target == null:
				return
			VFX.heal_motes(target, 0.35)
			var shown := minf(float(a[1]), target.health.max_health - target.health.current_health)
			if shown >= 0.5:
				GameFeel.float_text(target.global_position + Vector3(0, 2.1, 0), "+%d" % int(round(shown)),
					ArtKit.color("color_roles.nature.hot", Color("#E4FFC4")))
			Sfx.play("mend", target.global_position, -3.0, 0.08)
			if target.net_role == Player.NetRole.OWNER:
				var healed := target.receive_heal(float(a[1]))
				_book_heal_threat(hero, healed)
		&"ally_hot":  # [ref, id, total, duration]
			var target := _ally(hero, a[0])
			if target == null:
				return
			VFX.heal_motes(target, float(a[3]))
			Sfx.play("mend", target.global_position, -6.0, 0.08, 1.2)
			if target.net_role == Player.NetRole.OWNER:
				_book_heal_threat(hero, minf(float(a[2]), target.health.max_health - target.health.current_health))
				target.add_hot(StringName(str(a[1])), float(a[2]), float(a[3]))
		&"ally_shield":  # [ref, amount, duration] - the target's own grant_barrier shows the ring
			var target := _ally(hero, a[0])
			if target == null:
				return
			Sfx.play("barkskin", target.global_position, -3.0, 0.08)
			if target.net_role == Player.NetRole.OWNER:
				target.grant_barrier(float(a[1]), float(a[2]))
		&"ally_cleanse":  # [ref] - M12 Rootwalk: the target's owner drops its slows
			var target := _ally(hero, a[0])
			if target != null and target.net_role == Player.NetRole.OWNER:
				target.clear_slow()
		&"lodestone_rune":  # [pos, radius, arm] - M12 tome; puppets lay a visual copy
			var lode_data := hero.ability(&"lodestone_rune")
			if hero.net_role == Player.NetRole.PUPPET and lode_data != null:
				var lode := LodestoneRune.new()
				lode.visual_only = true
				lode.setup(lode_data, hero)
				lode.radius = float(a[1])
				lode.arm_time = float(a[2])
				lode.position = a[0] as Vector3
				scene.add_child(lode)
		&"hoarfrost_fan":  # [pos, dir, reach] - M12 tome: rime bursts along the cone
			var from := a[0] as Vector3
			var fan_dir := a[1] as Vector3
			var reach := float(a[2])
			for k in 3:
				var along := reach * (0.3 + 0.3 * float(k))
				VFX.frost_burst(scene, from + fan_dir * along, 0.7 + 0.5 * float(k))
			Sfx.play("frost_nova", from, -3.0, 0.08, 1.25)
		&"rootwalk":  # [from, to, time, radius] - M12 tome: down at one end, up at the other
			var walk_from := a[0] as Vector3
			var walk_to := a[1] as Vector3
			var green := ArtKit.color("color_roles.nature.body", Color("#7ED957"))
			VFX.ground_ring(scene, walk_from, green, float(a[3]), 0.4)
			VFX.dodge_dust(scene, walk_from, Vector3.UP)
			Sfx.play("root_grasp", walk_from, -4.0, 0.08, 1.2)
			hero._visual.visible = false
			hero.get_tree().create_timer(float(a[2])).timeout.connect(func() -> void:
				if not is_instance_valid(hero) or not hero.is_inside_tree():
					return
				hero._visual.visible = true
				VFX.ground_ring(hero.get_tree().current_scene, walk_to, green, float(a[3]), 0.4)
				VFX.dodge_dust(hero.get_tree().current_scene, walk_to, Vector3.UP)
				VFX.heal_motes(hero, 0.4)
				Sfx.play("mend", walk_to, -4.0, 0.08))
		&"ally_buff":  # [pos, radius, key, value, duration]
			var zone := ZoneBase.zone_of(hero)
			if zone != null:
				for ally in zone.players_within(a[0] as Vector3, float(a[1])):
					if ally.net_role == Player.NetRole.OWNER:
						ally.add_buff(StringName(str(a[2])), float(a[3]), float(a[4]))
		&"thorn_volley":  # [muzzle, dirs] - puppets fly visual copies
			Sfx.play("thorn_volley", a[0] as Vector3, -9.0, 0.12)
			var thorn_data := hero.ability(&"thorn_volley")
			if hero.net_role == Player.NetRole.PUPPET and thorn_data != null:
				for dir: Vector3 in a[1] as Array:
					var thorn := SpellBolt.new()
					thorn.visual_only = true
					thorn.color_role = "nature"
					thorn.lifetime = DruidHero.THORN_LIFETIME
					thorn.setup(thorn_data, dir, hero)
					thorn.position = a[0] as Vector3
					scene.add_child(thorn)
		&"root_grasp":  # [pos, radius] roots bursting out of the ground
			var bark := ArtKit.color("palettes.druid.bark.3", Color("#6C4A38"))
			VFX.ground_ring(scene, a[0] as Vector3, ArtKit.color("color_roles.nature.body"), float(a[1]), 0.3)
			VFX.burst(scene, a[0] as Vector3 + Vector3(0, 0.2, 0), {"tex": "shard", "amount": 16, "lifetime": 0.5,
				"size": 0.16, "spread": 35.0, "vel_min": 3.0, "vel_max": 6.0,
				"colors": [bark, Color(bark, 0.0)] as Array[Color]})
			VFX.decal(scene, a[0] as Vector3, "cracks", float(a[1]) * 1.6, Color(bark, 0.8), 3.0)
			Sfx.play("root_grasp", a[0] as Vector3, 0.0, 0.06)
		&"renewal_grove":  # [pos, radius, duration, rate, idol roots, green tide] - an ally effect
			var grove := RenewalGrove.new()
			grove.radius = float(a[1])
			grove.duration = float(a[2])
			grove.rate = float(a[3])
			grove.roots_enemies = bool(a[4])
			grove.green_tide = bool(a[5])
			grove.source = hero
			grove.position = a[0] as Vector3
			scene.add_child(grove)
		&"growth_totem":  # [pos, radius, duration, damage %, heal per pulse] - an ally effect
			var totem := GrowthTotem.new()
			totem.radius = float(a[1])
			totem.duration = float(a[2])
			totem.damage_pct = float(a[3])
			totem.heal = float(a[4])
			totem.position = a[0] as Vector3
			scene.add_child(totem)
		&"thornfield":  # [pos, radius, duration] - a visual copy on puppets
			var field_data := hero.ability(&"thornfield")
			if hero.net_role == Player.NetRole.PUPPET and field_data != null:
				var field := ThornField.new()
				field.visual_only = true
				field.setup(field_data, hero)
				field.radius = float(a[1])
				field.duration = float(a[2])
				field.position = a[0] as Vector3
				scene.add_child(field)
		&"wild_bloom":  # [pos, radius] the great heal opening
			var green := ArtKit.color("color_roles.nature.body")
			var hot := ArtKit.color("color_roles.nature.hot")
			VFX.flash(scene, a[0] as Vector3 + Vector3(0, 1.2, 0), hot, 3.0, 0.25)
			VFX.ground_ring(scene, a[0] as Vector3, green, float(a[1]), 0.5)
			VFX.burst(scene, a[0] as Vector3 + Vector3(0, 1.0, 0), {"tex": "spark", "amount": 24, "lifetime": 0.9,
				"size": 0.14, "spread": 180.0, "vel_min": 2.5, "vel_max": 6.0,
				"colors": [hot, Color(green, 0.0)] as Array[Color]})
			Sfx.play("wild_bloom", a[0] as Vector3, 0.0, 0.03)
		# --- M10b consumables ---
		&"drink":  # [pos, total heal] - a Healing Draught (the heal itself runs on the owner)
			VFX.drink(hero, float(Consumables.def(Consumables.HEALING_DRAUGHT).get("time", 4.0)))
			GameFeel.float_text(hero.global_position + Vector3(0, 2.1, 0), "+%d" % int(round(float(a[1]))),
				ArtKit.color("color_roles.health.hot", Color("#FF9C9C")))
			Sfx.play("potion_drink", a[0] as Vector3, -3.0, 0.05)


## M11: the hero a ref names in the caster's zone (null when gone).
static func _ally(hero: Player, ref: Variant) -> Player:
	var zone := ZoneBase.zone_of(hero)
	return zone.hero_by_ref(int(ref)) if zone != null else null


## M11 offline: the healer's threat (a co-op server books it when it relays).
static func _book_heal_threat(healer: Player, healed: float) -> void:
	if Net.is_online() or healed <= 0.0:
		return
	var zone := ZoneBase.zone_of(healer)
	if zone != null:
		zone.heal_threat(healer, healed)
