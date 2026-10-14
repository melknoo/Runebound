class_name HeroLook
extends RefCounted
## Rig v3: a hero's visible gear (WoW style). One base rig per class,
## res://assets/models/chars/hero/<class>/base.glb (skeleton, clips and the
## base look's region meshes rg_helm / rg_chest / rg_gloves / rg_boots /
## rg_weapon), plus per gear slot the region mesh of the look the equipped
## item's rarity names (<class>/<look>.glb, same skeleton), re-parented onto
## the base skeleton so every clip drives it. tools/modelgen/ai_fit.py builds
## the looks (AI bodies fitted onto the legacy skeleton, cut into regions that
## overlap so mixed looks never gap). A missing look falls back to the nearest
## lower one, then upwards. An empty slot shows `bare` (underclothes; an empty
## weapon slot shows no weapon), the start kit shows `base`.

const HERO_DIR := "res://assets/models/chars/hero/"
## Gear look per region; the index is the wire id (HERO_LOOK).
const LOOKS: Array[StringName] = [&"bare", &"base", &"common", &"magic", &"rare", &"legendary"]
const REGIONS: Array[StringName] = [&"helm", &"chest", &"gloves", &"boots", &"weapon"]
const SLOT_REGION := {
	ItemData.Slot.HELM: &"helm", ItemData.Slot.CHEST: &"chest", ItemData.Slot.GLOVES: &"gloves",
	ItemData.Slot.BOOTS: &"boots", ItemData.Slot.WEAPON: &"weapon",
}
const RARITY_LOOK := {
	ItemData.Rarity.COMMON: &"common", ItemData.Rarity.MAGIC: &"magic",
	ItemData.Rarity.RARE: &"rare", ItemData.Rarity.LEGENDARY: &"legendary",
}
const PART_PREFIX := "rg_"

var model: Node3D
var glow: StandardMaterial3D
var class_id: StringName
var tint: Color = Color.WHITE
var _skeleton: Skeleton3D
var _base_parts: Dictionary = {}  # region -> the base rig's own MeshInstance3D
var _parts: Dictionary = {}       # region -> the MeshInstance3D showing now
var _applied: Dictionary = {}     # region -> look shown
var _mats: Dictionary = {}        # look -> body material (atlas hero/<class>_<look>)
var _blade: Material = null       # weapon override (Cindermaw's molten edge)


static func available(cls: StringName) -> bool:
	return ResourceLoader.exists(look_path(cls, &"base"))


static func look_path(cls: StringName, look: StringName) -> String:
	return "%s%s/%s.glb" % [HERO_DIR, cls, look]


## region -> look for an equipment map: Equipment.equipped (slot int ->
## ItemData) or a saved character's "equipped" (slot string -> item dict).
static func looks_for(equipped: Dictionary, hide_helm: bool = false) -> Dictionary:
	var out := {}
	for region: StringName in REGIONS:
		out[region] = &"bare"
	for key: Variant in equipped:
		var slot := int(key)
		if not SLOT_REGION.has(slot):
			continue
		var item: Variant = equipped[key]
		var rarity := 0
		var kit := ""
		if item is ItemData:
			rarity = (item as ItemData).rarity
			kit = String((item as ItemData).kit)
		elif item is Dictionary:
			rarity = int((item as Dictionary).get("rarity", 0))
			kit = String((item as Dictionary).get("kit", ""))
		else:
			continue
		out[SLOT_REGION[slot]] = &"base" if kit != "" else RARITY_LOOK.get(rarity, &"common")
	if hide_helm:
		out[&"helm"] = &"bare"
	return out


## Wire form of a looks dict: one id per REGIONS entry.
static func encode(looks: Dictionary) -> Array:
	var ids := []
	for region: StringName in REGIONS:
		ids.append(maxi(LOOKS.find(looks.get(region, &"base")), 0))
	return ids


static func decode(ids: Array) -> Dictionary:
	var out := {}
	for i in REGIONS.size():
		var id := int(ids[i]) if i < ids.size() else 0  # 0 = bare
		out[REGIONS[i]] = LOOKS[clampi(id, 0, LOOKS.size() - 1)]
	return out


## Builds the base rig under `parent` (null when the class has no Rig v3 yet).
static func create(parent: Node3D, cls: StringName, glow_color: Color, glow_energy: float = 1.2,
		body_tint: Color = Color.WHITE) -> HeroLook:
	var scene := ArtKit.rig_scene(look_path(cls, &"base"))
	if scene == null:
		return null
	var hl := HeroLook.new()
	hl.class_id = cls
	hl.tint = body_tint
	hl.model = scene.instantiate() as Node3D
	hl.model.rotation.y = PI  # Blender front lands at Godot +Z
	parent.add_child(hl.model)
	var skeletons := hl.model.find_children("*", "Skeleton3D", true, false)
	hl._skeleton = skeletons[0] as Skeleton3D if not skeletons.is_empty() else null
	for region: StringName in REGIONS:
		var mi := hl.model.find_child(PART_PREFIX + region, true, false) as MeshInstance3D
		if mi != null:
			hl._base_parts[region] = mi
	hl.glow = ArtKit.glow_material(glow_color, glow_energy)
	hl.apply({})
	return hl


## Shows `looks` (region -> look; missing regions show bare).
func apply(looks: Dictionary) -> void:
	for region: StringName in REGIONS:
		var asked: StringName = looks.get(region, &"bare")
		var want := &"bare" if region == &"weapon" and asked == &"bare" else _resolve(asked)
		if _applied.get(region, &"") == want:
			continue
		_applied[region] = want
		var cur: MeshInstance3D = _parts.get(region)
		var base_mi: MeshInstance3D = _base_parts.get(region)
		if cur != null and cur != base_mi:
			_drop(cur)
		if region == &"weapon" and want == &"bare":  # empty hands: no weapon at all
			if base_mi != null:
				base_mi.visible = false
			_parts[region] = null
			continue
		var part: MeshInstance3D = base_mi
		if want != &"base":
			part = _instance_part(want, region)
			if part == null:
				part = base_mi
				_applied[region] = &"base"
		if base_mi != null:
			base_mi.visible = part == base_mi
		if part != null:
			_dress(part, _applied[region], region)
		_parts[region] = part


## The look a region shows now (tests, the net look).
func look_of(region: StringName) -> StringName:
	return _applied.get(region, &"base")


func part(region: StringName) -> MeshInstance3D:
	return _parts.get(region)


## Weapon blade surfaces get `mat` (null = the look's own atlas).
func set_blade_material(mat: Material) -> void:
	_blade = mat
	var p: MeshInstance3D = _parts.get(&"weapon")
	if p != null:
		_dress(p, _applied.get(&"weapon", &"base"), &"weapon")


func blade_material() -> Material:
	var p: MeshInstance3D = _parts.get(&"weapon")
	if p == null:
		return null
	for s in p.mesh.get_surface_count():
		if _surface_kind(p, s) == &"blade":
			return p.get_surface_override_material(s)
	return null


func body_material(look: StringName) -> StandardMaterial3D:
	if not _mats.has(look):
		var mat := ArtKit.character_material("hero/%s_%s" % [class_id, look])
		if tint != Color.WHITE:
			mat.albedo_color = tint
		_mats[look] = mat
	return _mats[look]


## Every mesh of the hero (dressing passes such as the ghost's transparency).
func meshes() -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for region: StringName in REGIONS:
		var p: MeshInstance3D = _parts.get(region)
		if p != null:
			out.append(p)
	return out


## Drops every material before the rig is freed (an outlined material freed
## under its live instance logs "material is null", gotchas.md).
func release() -> void:
	if model == null:
		return
	for mi: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := mi as MeshInstance3D
		for i in mesh.get_surface_override_material_count():
			mesh.set_surface_override_material(i, null)


func _resolve(look: StringName) -> StringName:
	var i := LOOKS.find(look)
	if i < 0:
		return &"base"
	for j in range(i, -1, -1):
		if ResourceLoader.exists(look_path(class_id, LOOKS[j])):
			return LOOKS[j]
	for j in range(i + 1, LOOKS.size()):
		if ResourceLoader.exists(look_path(class_id, LOOKS[j])):
			return LOOKS[j]
	return &"base"


func _instance_part(look: StringName, region: StringName) -> MeshInstance3D:
	var scene := ArtKit.rig_scene(look_path(class_id, look))
	if scene == null or _skeleton == null:
		return null
	var tmp := scene.instantiate() as Node3D
	var src := tmp.find_child(PART_PREFIX + region, true, false) as MeshInstance3D
	var part: MeshInstance3D = null
	if src != null:
		part = src.duplicate() as MeshInstance3D
		part.name = "%s%s_%s" % [PART_PREFIX, region, look]
		_skeleton.add_child(part)
		part.skeleton = part.get_path_to(_skeleton)
	tmp.free()
	return part


static func _surface_kind(mi: MeshInstance3D, s: int) -> StringName:
	var mat := mi.mesh.surface_get_material(s)
	var mat_name := mat.resource_name if mat != null else ""
	if mat_name.ends_with("_glow") or mat_name.ends_with("_eyes"):
		return &"glow"
	if mat_name.ends_with("_blade"):
		return &"blade"
	return &"body"


func _dress(mi: MeshInstance3D, look: StringName, region: StringName) -> void:
	for s in mi.mesh.get_surface_count():
		match _surface_kind(mi, s):
			&"glow":
				mi.set_surface_override_material(s, glow)
			&"blade":
				mi.set_surface_override_material(s, _blade if _blade != null and region == &"weapon"
					else body_material(look))
			_:
				mi.set_surface_override_material(s, body_material(look))


func _drop(mi: MeshInstance3D) -> void:
	for i in mi.get_surface_override_material_count():
		mi.set_surface_override_material(i, null)
	mi.get_parent().remove_child(mi)
	mi.queue_free()
