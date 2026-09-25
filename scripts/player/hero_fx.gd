class_name HeroFx
extends Object
## M09: the look (and sound) of a hero's actions, playable on any machine.
## The acting hero plays an entry through Player.hero_fx(); in co-op its owner
## also sends it (HERO_FX) and every other client plays the same entry on its
## puppet of that hero. Gameplay never lives here: the projectile and rune a
## puppet shows are visual copies (the owner's real ones deal the damage).


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
			if hero.net_role == Player.NetRole.PUPPET and hero.ember != null:
				var proj := EmberLanceProjectile.new()
				proj.visual_only = true
				proj.setup(hero.ember, a[1] as Vector3, hero)
				proj.position = a[0] as Vector3  # before add_child, like every projectile
				scene.add_child(proj)
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
			if hero.net_role == Player.NetRole.PUPPET and hero.fracture_rune != null:
				var rune := FractureRune.new()
				rune.visual_only = true
				rune.setup(hero.fracture_rune, hero)
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
