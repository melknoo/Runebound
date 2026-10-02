class_name JackalDen
extends EnemyNest
## M12 bone field: the ash jackals' den, a mound of dust and bones.


func _init() -> void:
	super()
	display_name = Texts.t("enemy.jackal_den")
	brood_id = "ash_jackal"
	prop_name = "jackal_den"
	smoke = Color(0.42, 0.38, 0.32)
