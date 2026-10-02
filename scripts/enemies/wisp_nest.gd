class_name WispNest
extends EnemyNest
## M12 burnt forest: the smoulder wisps' nest, a hollow stump glowing inside.


func _init() -> void:
	super()
	display_name = Texts.t("enemy.wisp_nest")
	brood_id = "smoulder_wisp"
	prop_name = "wisp_nest"
	smoke = Color(0.32, 0.27, 0.25)
