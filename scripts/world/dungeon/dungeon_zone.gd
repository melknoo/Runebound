class_name DungeonZone
extends ZoneBase
## M13: the base of the dungeons behind the Highlands' gates (WORLD_DESIGN
## "Dungeons"). Built from a baked DungeonLayout (tools/worldgen/
## dungeon_bake.py): DungeonBuilder raises floors, walls and roofs, the POIs
## become portals, camps and chests. The layout's floor heights are the
## ground seam here (`ground_y`); the map is the baked image, rooms announce
## their names, POIs are discovered room by room. Subclasses name their
## dungeon (`_dungeon_id`), look, materials and light colour.

const DISCOVER_INTERVAL := 0.5
const COMPASS_CAMP_RANGE := 60.0

var layout: DungeonLayout
var builder: DungeonBuilder
var info: Dictionary = {}
## Camp spawners, chests and portals by POI id.
var camps: Dictionary = {}
var chests: Dictionary = {}
var portals: Dictionary = {}
var _map_texture: Texture2D
var _discover_left: float = 0.0
var _room_seen: Dictionary = {}


## The DungeonRegistry id of this dungeon (override).
func _dungeon_id() -> String:
	return ""


## Material roles of floors and walls (ArtKit; the legacy look falls back
## to the Spire's tiled textures).
func _floor_role() -> StringName:
	return &"spire_floor"


func _wall_role() -> StringName:
	return &"spire_wall"


func _light_color() -> Color:
	return Color(0.45, 0.85, 0.8)


func _zone_music() -> String:
	return "spire"  # M13: no new tracks (user, 2026-10-09); the Spire's dark interior pair


func zone_title() -> String:
	return DungeonRegistry.title(_dungeon_id()).to_upper()


func _enemy_level(enemy: EnemyBase, _pos: Vector3) -> int:
	if enemy != null and enemy.has_signal(&"boss_health_changed"):
		return int(info.get("boss_level", 4))
	return int(info.get("level", 3))


## Every enemy type the layout's camps field (their rigs warm up on arrival).
func _warm_up_ids() -> Array[String]:
	var out: Array[String] = []
	if layout == null:
		return ["rusher", "caster"]
	for poi in layout.pois.by_type("camp"):
		for id in PoiBuilder.composition_of(poi):
			var key := "rusher" if id == "elite" else id
			if not key in out:
				out.append(key)
	return out


func _build_zone() -> void:
	info = DungeonRegistry.info(_dungeon_id())
	layout = DungeonLayout.load_from(String(info.get("layout", "")))
	var art := look != null and look.art_pass
	var floor_mat: Material = ArtKit.material(_floor_role()) if art else \
		_material_from_texture("res://assets/textures/spire_floor.png", Color(0.16, 0.13, 0.22), 16.0)
	var wall_mat: Material = ArtKit.material(_wall_role()) if art else \
		_material_from_texture("res://assets/textures/spire_wall.png", Color(0.22, 0.18, 0.32), 2.5)
	builder = DungeonBuilder.build(self, layout, floor_mat, wall_mat, _light_color())
	for poi in layout.pois.pois:
		var made := DungeonBuilder.build_poi(self, poi)
		var id := String(poi.get("id", ""))
		if made.has("spawner"):
			camps[id] = made["spawner"]
		if made.has("chest"):
			chests[id] = made["chest"]
		if made.has("portal"):
			portals[id] = made["portal"]
	var map_path := String(info.get("layout", "")).path_join("map.png")
	if ResourceLoader.exists(map_path):
		_map_texture = load(map_path) as Texture2D
	_build_dungeon()


## Subclass content after the shell (dressing, ambience, set pieces).
func _build_dungeon() -> void:
	pass


# ---------------------------------------------------------------------------
# Ground seam, spawn, arrival
# ---------------------------------------------------------------------------

func ground_y(pos: Vector3) -> float:
	return layout.floor_at(pos.x, pos.z, 0.0) if layout != null else 0.0


## A late joiner's spot beside a hero may lie in a wall: into the nearest room.
func safe_spawn(pos: Vector3) -> Vector3:
	return layout.clamp_inside(pos) if layout != null else pos


func poi_position(id: String) -> Vector3:
	if layout == null:
		return Vector3.INF
	var poi := layout.pois.find(id)
	return ZoneLayout.pos_of(poi) if not poi.is_empty() else Vector3.INF


## The entry: a step in front of the exit gate (the dungeon's "spawn").
func _player_spawn_point() -> Vector3:
	var exit_id := String(info.get("exit", ""))
	var poi := layout.pois.find(exit_id) if layout != null else {}
	if poi.is_empty():
		return Vector3(0, 0.2, 0)
	var yaw := float(poi.get("yaw", 0.0))
	return ZoneLayout.pos_of(poi) + Vector3(sin(yaw), 0.0, cos(yaw)) * 2.2 + Vector3(0, 0.2, 0)


# ---------------------------------------------------------------------------
# Map, compass, discovery
# ---------------------------------------------------------------------------

func map_texture() -> Texture2D:
	return _map_texture


func map_bounds() -> Rect2:
	return layout.bounds() if layout != null else Rect2(-96, -96, 192, 192)


static func marker_icon(poi: Dictionary) -> String:
	match String(poi.get("type", "")):
		"portal": return "portal"
		"camp": return "camp"
		"chest": return "chest"
		"lore": return "lore"
		_: return ""


static func marker_label(poi: Dictionary) -> String:
	match String(poi.get("type", "")):
		"portal": return "Gate: " + String(poi.get("label", "")).capitalize()
		"camp": return Texts.t("map.dungeon.enemies")
		"chest": return "Treasure"
		"lore": return Texts.t(String(poi.get("text", "")) + ".title")
		_: return ""


## What the local hero has seen: POIs are found room by room; the exit is
## always known.
func map_markers() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if layout == null or player == null or not is_instance_valid(player):
		return out
	var exit_id := String(info.get("exit", ""))
	for poi in layout.pois.pois:
		var icon := marker_icon(poi)
		if icon == "":
			continue
		var id := String(poi.get("id", ""))
		if not (player.map_discovered.has(id) or id == exit_id):
			continue
		var type := String(poi.get("type", ""))
		if type == "camp" and camps.has(id) and (camps[id] as EncounterSpawner).state == EncounterSpawner.State.CLEARED:
			icon = "camp_cleared"
		out.append({"id": id, "pos": ZoneLayout.pos_of(poi), "icon": icon, "label": marker_label(poi), "kind": type})
	return out


## The compass: the way out and armed camps close by.
func compass_markers() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var origin := player.global_position if player != null and is_instance_valid(player) else Vector3.ZERO
	for m in map_markers():
		var kind := String(m["kind"])
		if kind == "portal":
			out.append(m)
		elif kind == "camp" and String(m["icon"]) != "camp_cleared" \
				and (m["pos"] as Vector3).distance_to(origin) <= COMPASS_CAMP_RANGE:
			m["max_dist"] = COMPASS_CAMP_RANGE
			out.append(m)
	return out


## The room a point stands in ("" in a doorway or outside).
func room_id_at(pos: Vector3) -> String:
	var r := layout.room_at(pos.x, pos.z) if layout != null else {}
	return String(r.get("id", ""))


func _physics_process(delta: float) -> void:
	_discover_left -= delta
	if _discover_left <= 0.0:
		_discover_left = DISCOVER_INTERVAL
		_discover_tick()


## Every hero finds the POIs of the room it stands in; the local hero's
## room shows its name once per visit.
func _discover_tick() -> void:
	if layout == null or players.is_empty():
		return
	for p in players:
		if p != null and is_instance_valid(p):
			var rid := room_id_at(p.global_position)
			if rid != "":
				for poi in layout.pois.pois:
					if String(poi.get("room", "")) == rid and marker_icon(poi) != "":
						p.discover_poi(String(poi.get("id", "")))
	if player == null or not is_instance_valid(player) or hud == null:
		return
	var here := room_id_at(player.global_position)
	if here == "" or _room_seen.has(here):
		return
	_room_seen[here] = true
	var key := String(layout.room(here).get("name_key", ""))
	if key != "":
		hud.area_name(Texts.t(key))
