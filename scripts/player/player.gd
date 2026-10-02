class_name Player
extends CharacterBody3D
## The hero chassis every class shares (M10): movement, dodge, damage intake,
## barrier, cooldowns, the class resource, stats, the loadout, the network
## roles and presentation hooks. A class extends it (scripts/player/classes/)
## with its ability code: `_load_abilities`, `_register_actions`,
## `_anim_profile` and `_process_class_state`. Make heroes with
## `Player.create(class_data)`, never `Player.new()` directly.

## M12: lore read or a collectible taken (the chronicle refreshes).
signal chronicle_changed
signal health_changed(current: float, maximum: float)
## The class resource (Runebreaker: Resonance, Elementalist: Aether). The name
## stays "resonance" in code; ClassData.resource_label is what players read.
signal resonance_changed(current: float, maximum: float)
signal cooldowns_changed
signal player_died
## Presentation hook (M06 CharacterAnimator): an ability just started.
signal action_started(action: StringName)
## M07b: the set of known abilities changed (learned at the trainer, restored
## from the save, or a talent unlock toggled).
signal abilities_changed
signal ability_learned(id: StringName)
signal gold_changed(total: int, delta: int)
## M08: a waypoint shrine was attuned ("<zone>:<id>").
signal waypoint_discovered(id: String)
## M10: the four free slots (RMB, 1, 2, 3) changed.
signal loadout_changed
## M10b: a consumable was added, used or restored from the save.
signal consumables_changed

## One enum for every class: the network sends the state as an int.
enum State { MOVE, DODGE, MELEE, CAST, SLAM, STORM_STEP, BLOCK, LEAP, ROOTWALK }

const MAX_SPEED := 6.8
const ACCEL := 60.0
const DECEL := 55.0
const ROTATION_SPEED := 14.0
const GRAVITY := 24.0

const DODGE_SPEED := 15.0
const DODGE_DURATION := 0.24
const DODGE_RECOVERY := 0.08
const DODGE_COOLDOWN := 0.55
const DODGE_THREAT_RANGE := 6.0  # a direction-less dodge leaves enemies this close
## M08 notes (user 2026-09-28): Shift sprints, free, but only out of combat -
## no hit taken or thrown for SPRINT_COMBAT_LOCK seconds. For crossing the
## open world; in a fight the dodge is the answer. M10: the same rule locks
## the loadout.
const SPRINT_MULT := 1.45
const SPRINT_COMBAT_LOCK := 3.0
const DODGE_IFRAMES := 0.26  # user-tuned: a touch past the dash itself

## Default class resource cap; the live value is max_resource() (ClassData).
const MAX_RESONANCE := 100.0
const INPUT_BUFFER := 0.22
## M10 loadout: RMB, 1, 2, 3 (InputSetup.SLOT_ACTIONS); LMB and dodge are fixed.
const LOADOUT_SIZE := 4
## Casting at the aim keeps the hero facing it this long while it moves on
## (strafing casters instead of snapping back to the run direction).
const AIM_HOLD_MSEC := 450

## Per-ability stat keys the generic hooks read (items and talents add them).
const ABILITY_CD_STATS := {&"dodge": &"dodge_cd_pct", &"storm_step": &"storm_cd_pct", &"rune_chain": &"tether_cd_pct"}
const ABILITY_DAMAGE_STATS := {&"ember_lance": &"ember_dmg_pct", &"rune_cleave": &"cleave_dmg_pct",
	&"thorn_volley": &"thorn_dmg_pct"}
## The most damage reduction all sources together may give (M10).
const MAX_DAMAGE_REDUCTION := 0.7

var state: State = State.MOVE
var resonance: float = 0.0
var god_mode: bool = false
## Set by InventoryUI while its panel is open: combat input ignored.
var input_locked: bool = false

var camera_rig: CameraRig = null
var targeting: TargetingSystem = null
var health: HealthComponent
var equipment: Equipment
var progression: Progression

## M07b class as data. Player.create() sets it before add_child; a bare
## chassis gets the default class in _ready (no abilities of its own).
var class_data: ClassData = null
## id -> AbilityData for every ability of the class (HUD order in class_data).
var abilities: Dictionary = {}
## Ability ids this character has learned (START + trainer). TALENT abilities
## are known through their power instead; dodge is always known. See knows().
var known_abilities: Array[StringName] = []
## M10: the four free slots, &"" = empty. Only these (plus the basic attack
## and dodge) fire. Saved per character.
var loadout: Array[StringName] = []
var gold: int = 0
## M10b: consumable id -> count in the bag (Consumables.DEFS; saved per character).
var consumables: Dictionary = {}
## M10b: health a draught still has to restore, and how fast (owner only).
var _heal_left: float = 0.0
var _heal_rate: float = 0.0
## M11: heals over time from allies (the druid's Regrowth): id -> [left, rate].
## The same id refreshes; separate from the draught.
var _hots: Dictionary = {}
## M12: the heal-over-time id of a meal (separate from ally heals).
const FOOD_HOT := &"food"
## M12: a slow on this hero (the strongest one wins; the druid's Rootwalk
## clears it): share of the speed taken away, and how long it still lasts.
const CHILL_SLOW := 0.4
const CHILL_SLOW_TIME := 3.0
var slow_pct: float = 0.0
var _slow_left: float = 0.0
## M11: timed stat bonuses (a Growth Totem): key -> [value, seconds left].
## stat() adds them.
var _buffs: Dictionary = {}
## M11: a POOL resource (Sap) refills only while a fight is on near the hero.
var _fight_near: bool = false
var _fight_check_left: float = 0.0
## M08: attuned waypoint shrines and map points seen (per character, saved).
var discovered_waypoints: PackedStringArray = PackedStringArray()
var map_discovered: PackedStringArray = PackedStringArray()
## M09 (save v5): zones this character has discovered (their discovery XP).
var discovered_zones: PackedStringArray = PackedStringArray()
## M12 (per character): lore read (its chronicle), collectibles taken (rune
## shards), gather nodes used (key -> unix time; they grow back).
var lore_read: PackedStringArray = PackedStringArray()
var collected: PackedStringArray = PackedStringArray()
## M12 phase 6: the rune blessings this character carries (Blessings ids).
var blessings: PackedStringArray = PackedStringArray()
var gathered: Dictionary = {}
## action id -> Callable that tries to start it (built in _register_actions).
var _actions: Dictionary = {}
## M07b input seam: Player reads only `intent`, which `input_source` fills
## once per physics tick (LocalInputSource = this machine's keyboard/mouse;
## a scripted or network source drives the same code).
var input_source: InputSource = null
var intent: PlayerIntent = PlayerIntent.new()
## M07b: this machine's hero. Presentation that belongs to *a* player (camera
## shake, impulses, denied clicks, pickup toasts) checks it; world presentation
## (boss slams, positional SFX) does not. Remote heroes will be spawned false.
var is_local: bool = true
## Reserved for co-op (Godot's high-level multiplayer: 1 = server / local).
var peer_id: int = 1

## M09: who drives this Player instance.
##   OWNER   this machine plays it (the local hero; bots in tests)
##   PUPPET  another player's hero on a client: pose, state, animation and HP
##           come from the network (NetWorld); no input, physics or death here
##   PROXY   a client's hero on the dedicated server: position and HP from its
##           owner, a hurtbox so enemies can find and hit it, no visuals
## Set before add_child.
enum NetRole { OWNER, PUPPET, PROXY }
var net_role: NetRole = NetRole.OWNER


## The hero of `cls` (its class script, else the bare chassis); set the net
## role and the rest before add_child.
static func create(cls: ClassData = null) -> Player:
	if cls == null:
		cls = ClassData.default_class()
	var p: Player = (cls.hero_script.new() as Player) if cls.hero_script != null else Player.new()
	p.class_data = cls
	return p


## M09: an action's look the other players must see too (HeroFx): plays here
## and, for this machine's hero in co-op, goes to the others, whose puppet of
## this hero plays the same entry.
func hero_fx(kind: StringName, args: Array) -> void:
	HeroFx.play(self, kind, args)
	if Net.is_client() and net_role == NetRole.OWNER:
		var zone := ZoneBase.zone_of(self)
		if zone != null and zone.net_world != null:
			zone.net_world.send_hero_fx(kind, args)


## M09: bumped whenever this hero jumps instead of walking (respawn, travel);
## puppets snap instead of sliding across the map when it changes.
var teleports: int = 0

## M07 barrier (Runic Guard, Unbroken): absorbs damage before health.
var barrier: float = 0.0
var _barrier_time: float = 0.0
const UNBROKEN_BARRIER := 15.0
const UNBROKEN_COOLDOWN := 8.0

var _cooldowns: Dictionary = {}  # id -> seconds remaining
var _state_timer: float = 0.0
var _dodge_dir: Vector3 = Vector3.ZERO
var _buffered_action: StringName = &""
var _buffer_timer: float = 0.0
var _footstep_accum: float = 0.0
var _knockback_velocity: Vector3 = Vector3.ZERO
var _hitstop_left: float = 0.0
var _aim_hold_until: int = 0
## Pool abilities known at the last loadout sync (newly known ones fill a slot).
var _synced_pool: Array[StringName] = []

var _visual: Node3D
var _weapon_pivot: Node3D


func _ready() -> void:
	collision_layer = 0b10 if net_role == NetRole.OWNER else 0  # M09: remote heroes never block anyone
	collision_mask = 0b1000101  # world, enemies, M12 foliage (forest trunks)
	var col := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.42
	capsule.height = 1.7
	col.shape = capsule
	col.position = Vector3(0, 0.85, 0)
	add_child(col)

	if class_data == null:
		class_data = ClassData.default_class()
	health = HealthComponent.new()
	health.max_health = class_data.base_max_hp
	add_child(health)
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)
	health.health_changed.connect(func(c: float, m: float) -> void: health_changed.emit(c, m))

	equipment = Equipment.new()
	equipment.name = "Equipment"
	equipment.player = self
	add_child(equipment)
	progression = Progression.new()
	progression.name = "Progression"
	progression.class_id = class_data.id
	add_child(progression)
	progression.talents_changed.connect(equipment._apply_max_hp)  # levels + Runic Plate
	progression.talents_changed.connect(_sync_loadout)  # talent unlocks join / leave the slots
	abilities_changed.connect(_sync_loadout)

	# A puppet is never hit on a client (enemies attack on the server).
	Hurtbox.create(self, 0b1000 if net_role != NetRole.PUPPET else 0, 0.5, 1.75, 0.85)

	if input_source == null:
		# M09: only the hero this machine plays may read its keyboard.
		input_source = LocalInputSource.new() if net_role == NetRole.OWNER and is_local else InputSource.new()
	_load_abilities()
	_register_actions()
	if known_abilities.is_empty():
		known_abilities = class_data.starting_abilities.duplicate()
	if loadout.size() != LOADOUT_SIZE:
		restore_loadout([])
	if class_data.resource_mode == ClassData.ResourceMode.POOL:
		resonance = max_resource()  # M11: a pool starts full (the save may lower it)
	_build_visual()
	floor_snap_length = 0.4


## Fills `abilities` from the class. A class caches its own by name on top.
func _load_abilities() -> void:
	abilities.clear()
	for data in class_data.abilities:
		if data != null:
			abilities[data.id] = data


## The action table: ability id -> Callable that tries to start it. The
## chassis knows the dodge; each class adds its abilities.
func _register_actions() -> void:
	_actions = {&"dodge": try_dodge}


func ability(id: StringName) -> AbilityData:
	return abilities.get(id) as AbilityData


func max_resource() -> float:
	return class_data.max_resource if class_data != null else MAX_RESONANCE


# ---------------------------------------------------------------------------
# M07b: known abilities and gold
# ---------------------------------------------------------------------------

## Does this character know `id` (ignoring cooldown, state and the loadout)?
## Dodge always; TALENT abilities while their power is held; the rest once
## learned (start kit or trainer).
func knows(id: StringName) -> bool:
	if id == &"dodge":
		return true
	var data := ability(id)
	if data == null:
		return false
	if data.unlock == AbilityData.Unlock.TALENT:
		return data.unlock_power != &"" and has_power(data.unlock_power)
	return known_abilities.has(id)


## Learn a START/TRAINER ability of this class. False if unknown id, a TALENT
## ability, or already known.
func learn_ability(id: StringName) -> bool:
	var data := ability(id)
	if data == null or data.unlock == AbilityData.Unlock.TALENT or known_abilities.has(id):
		return false
	known_abilities.append(id)
	abilities_changed.emit()
	ability_learned.emit(id)
	return true


## Tests, captures and the debug overlay: know the whole trainer kit at once.
func debug_learn_all() -> void:
	var changed := false
	var kit := class_data.trainer_abilities()
	for data in class_data.abilities:  # M12: the tome's ability too
		if data != null and data.unlock == AbilityData.Unlock.TOME:
			kit.append(data)
	for data in kit:
		if not known_abilities.has(data.id):
			known_abilities.append(data.id)
			changed = true
	if changed:
		abilities_changed.emit()


# ---------------------------------------------------------------------------
# M10: the loadout (LMB basic attack + dodge fixed, four free slots)
# ---------------------------------------------------------------------------

## The class's basic attack on LMB (&"" for the bare chassis).
func basic_attack() -> StringName:
	return class_data.basic_attack if class_data != null else &""


## Abilities that can go into a free slot (the class kit without the basic
## attack), in class order.
func pool() -> Array[AbilityData]:
	var out: Array[AbilityData] = []
	for data in class_data.abilities:
		if data != null and data.id != basic_attack():
			out.append(data)
	return out


## May `id` fire right now as far as the kit goes: dodge, the basic attack
## once known, anything else only from a slot.
func can_use(id: StringName) -> bool:
	if not knows(id):
		return false
	return id == &"dodge" or id == basic_attack() or loadout.has(id)


## Slot index of `id` (-1 when not slotted).
func slot_of(id: StringName) -> int:
	return loadout.find(id) if id != &"" else -1


## Why the loadout can't change right now ("" when it can).
func loadout_locked_reason() -> String:
	if in_combat():
		return "Not in combat"
	return ""


## Puts `id` (&"" = clear) into `slot`; an ability already slotted elsewhere
## swaps places. Returns "" or the reason it was refused.
func set_loadout_slot(slot: int, id: StringName) -> String:
	if slot < 0 or slot >= LOADOUT_SIZE:
		return "No such slot"
	var locked := loadout_locked_reason()
	if locked != "":
		return locked
	if id != &"":
		var data := ability(id)
		if data == null or id == basic_attack() or not knows(id):
			return "Not learned"
		var old := loadout.find(id)
		if old >= 0:
			loadout[old] = loadout[slot]
	loadout[slot] = id
	loadout_changed.emit()
	return ""


## Loadout from a save (ids in slot order); abilities the character doesn't
## know stay empty. An empty list fills the slots from the known pool in class
## order (fresh characters and saves from before M10).
func restore_loadout(ids: Array) -> void:
	loadout.clear()
	for i in LOADOUT_SIZE:
		loadout.append(&"")
	if ids.is_empty():
		for data in pool():
			if knows(data.id):
				var free := loadout.find(&"")
				if free < 0:
					break
				loadout[free] = data.id
	else:
		for i in mini(ids.size(), LOADOUT_SIZE):
			var sid := StringName(str(ids[i]))
			if sid != &"" and knows(sid) and sid != basic_attack() and not loadout.has(sid):
				loadout[i] = sid
	_synced_pool = _known_pool()
	loadout_changed.emit()


func _known_pool() -> Array[StringName]:
	var out: Array[StringName] = []
	for data in pool():
		if knows(data.id):
			out.append(data.id)
	return out


## After learning or a talent change: forgotten abilities leave their slot,
## newly known ones take the first free slot (never pushing one out).
func _sync_loadout() -> void:
	if loadout.size() != LOADOUT_SIZE:
		return
	var known := _known_pool()
	var changed := false
	for i in LOADOUT_SIZE:
		if loadout[i] != &"" and not known.has(loadout[i]):
			loadout[i] = &""
			changed = true
	for id in known:
		if _synced_pool.has(id) or loadout.has(id):
			continue
		var free := loadout.find(&"")
		if free < 0:
			break
		loadout[free] = id
		changed = true
	_synced_pool = known
	if changed:
		loadout_changed.emit()


## Key label of `id` as its slot shows it ("LMB", "RMB", "1", "SPC"; "" when
## it sits in no slot).
func key_label_for(id: StringName) -> String:
	if id == &"dodge":
		return InputSetup.key_label(&"dodge")  # M17a: rebindable
	if id == basic_attack():
		return InputSetup.key_label(&"primary_attack")
	var slot := slot_of(id)
	return InputSetup.slot_label(slot) if slot >= 0 else ""


# ---------------------------------------------------------------------------
# M07b: presentation that belongs to this player only
# ---------------------------------------------------------------------------

func feel_shake(amount: float) -> void:
	if is_local:
		GameFeel.camera_shake(amount)


func feel_impulse(dir: Vector3, strength: float) -> void:
	if is_local:
		GameFeel.camera_impulse(dir, strength)


func ui_denied() -> void:
	if is_local:
		Sfx.play_ui("ui_denied", -8.0)


func knows_waypoint(id: String) -> bool:
	return discovered_waypoints.has(id)


## Attune a shrine: remembered per character, a little XP, a toast for the
## local hero. False when it was known already.
func discover_waypoint(id: String, display_name: String) -> bool:
	if id == "" or discovered_waypoints.has(id):
		return false
	discovered_waypoints.append(id)
	progression.add_xp(Waypoint.DISCOVER_XP)
	waypoint_discovered.emit(id)
	if is_local:
		var zone := ZoneBase.zone_of(self)
		if zone != null and zone.hud != null:
			zone.hud.toast("Waypoint attuned: %s  +%d XP" % [display_name, Waypoint.DISCOVER_XP],
				ArtKit.color("color_roles.player_accent.body", Color(0.37, 0.88, 0.91)))
		Sfx.play_ui("waypoint_attune", -3.0)
	SaveGame.request_save()
	return true


## A point of interest seen (map + compass). False when known already.
func discover_poi(id: String) -> bool:
	if id == "" or map_discovered.has(id):
		return false
	map_discovered.append(id)
	SaveGame.request_save()
	return true


## M12: true the first time this character reads lore `id` (the chronicle).
func read_lore(id: String) -> bool:
	if id == "" or lore_read.has(id):
		return false
	lore_read.append(id)
	chronicle_changed.emit()
	SaveGame.request_save()
	return true


## M12: true the first time this character takes collectible `id`.
func collect(id: String) -> bool:
	if id == "" or collected.has(id):
		return false
	collected.append(id)
	chronicle_changed.emit()
	SaveGame.request_save()
	return true


## M12: when this character last used gather node `key` (unix s, 0 = never).
func gathered_at(key: String) -> float:
	return float(gathered.get(key, 0.0))


## M12: a rune blessing for good (owner side: a trial or the shards judged it).
func grant_blessing(id: StringName) -> bool:
	if not Blessings.DEFS.has(id) or blessings.has(String(id)):
		return false
	blessings.append(String(id))
	equipment._recompute()  # maximum health follows at once
	chronicle_changed.emit()
	SaveGame.request_save()
	return true


func mark_gathered(key: String) -> void:
	gathered[key] = Time.get_unix_time_from_system()


func add_gold(amount: int) -> void:
	if amount == 0:
		return
	gold = maxi(gold + amount, 0)
	gold_changed.emit(gold, amount)


func spend_gold(amount: int) -> bool:
	if amount < 0 or gold < amount:
		return false
	gold -= amount
	gold_changed.emit(gold, -amount)
	return true


# ---------------------------------------------------------------------------
# M10b: consumables (Consumables.DEFS) - counted in the bag, used from the
# inventory. No regeneration out of combat (user, 2026-09-30).
# ---------------------------------------------------------------------------

func consumable_count(id: StringName) -> int:
	return int(consumables.get(id, 0))


## Adds up to `amount` (the bag holds Consumables.cap(id)); returns how many
## it took.
func add_consumable(id: StringName, amount: int = 1) -> int:
	if not Consumables.has(id) or amount <= 0:
		return 0
	var taken := mini(amount, Consumables.cap(id) - consumable_count(id))
	if taken <= 0:
		return 0
	consumables[id] = consumable_count(id) + taken
	consumables_changed.emit()
	return taken


## Why `id` can't be used right now; "" when it can.
func consumable_deny_reason(id: StringName) -> String:
	if consumable_count(id) <= 0:
		return "None left"
	if health.is_dead:
		return "Dead"
	if Consumables.is_food(id):
		# M12 food: a rest out of combat (user decision 2026-10-01)
		if in_combat():
			return Texts.t("ui.food.in_combat")
		if _hots.has(FOOD_HOT):
			return Texts.t("ui.food.eating")
	elif _heal_left > 0.0:
		return "Still drinking"
	if health.current_health >= health.max_health:
		return "Health is full"
	return ""


## Drinks one: heal_pct of the maximum health over its time. One at a time.
func use_consumable(id: StringName) -> bool:
	if consumable_deny_reason(id) != "":
		return false
	var d := Consumables.def(id)
	consumables[id] = consumable_count(id) - 1
	var total := health.max_health * float(d.get("heal_pct", 0.0))
	var time := maxf(float(d.get("time", 1.0)), 0.1)
	if Consumables.is_food(id):
		add_hot(FOOD_HOT, total, time)  # a fight (dealt or taken) breaks it: mark_combat
		Sfx.play_ui("pickup", -6.0)
	else:
		_heal_left = total
		_heal_rate = total / time
		hero_fx(&"drink", [global_position, total])
	consumables_changed.emit()
	SaveGame.request_save()
	return true


## M12: true while food is still healing (a rest out of combat).
func is_eating() -> bool:
	return _hots.has(FOOD_HOT)


## Health a running draught has still to give (0 when none).
func healing_left() -> float:
	return _heal_left


# ---------------------------------------------------------------------------
# M11: support from allies (heals, heals over time, timed buffs) and the POOL
# resource. Everything here runs on the hero's owner (ally effects arrive
# through HeroFx, which applies them only to heroes this machine simulates).
# ---------------------------------------------------------------------------

## How far a healer reaches its allies (targeted heals, the lowest-health pick).
const ALLY_RANGE := 30.0
## Enemies this close that are after someone keep a POOL refilling.
const FIGHT_NEAR_RANGE := 30.0


## Heals this hero (owner only) and returns what it actually healed.
func receive_heal(amount: float) -> float:
	if net_role != NetRole.OWNER or amount <= 0.0:
		return 0.0
	return health.heal(amount)


## A heal over time (the same id refreshes it): `total` over `duration` s.
func add_hot(id: StringName, total: float, duration: float) -> void:
	if net_role != NetRole.OWNER or total <= 0.0 or health.is_dead:
		return
	_hots[id] = [total, total / maxf(duration, 0.1)]


## Health a heal over time `id` has still to give (0 when none runs).
func hot_left(id: StringName) -> float:
	var h: Variant = _hots.get(id)
	return float((h as Array)[0]) if h is Array else 0.0


## A timed stat bonus (added to stat(key)); the same key keeps the larger
## value and the longer time.
func add_buff(key: StringName, value: float, duration: float) -> void:
	if net_role != NetRole.OWNER or duration <= 0.0:
		return
	var old: Variant = _buffs.get(key)
	if old is Array:
		value = maxf(value, float((old as Array)[0]))
		duration = maxf(duration, float((old as Array)[1]))
	_buffs[key] = [value, duration]


func buff_stat(key: StringName) -> float:
	var b: Variant = _buffs.get(key)
	return float((b as Array)[0]) if b is Array else 0.0


func buff_time(key: StringName) -> float:
	var b: Variant = _buffs.get(key)
	return float((b as Array)[1]) if b is Array else 0.0


## M12: slows this hero by `pct` for `seconds` (the stronger slow wins).
func apply_slow(pct: float, seconds: float) -> void:
	if pct >= slow_pct or _slow_left <= 0.0:
		slow_pct = clampf(pct, 0.0, 0.9)
	_slow_left = maxf(_slow_left, seconds)


func clear_slow() -> void:
	slow_pct = 0.0
	_slow_left = 0.0


func _tick_support(delta: float) -> void:
	if _slow_left > 0.0:
		_slow_left -= delta
		if _slow_left <= 0.0:
			slow_pct = 0.0
	for id: StringName in _hots.keys():
		var h: Array = _hots[id]
		if health.is_dead:
			_hots.erase(id)
			continue
		var step := minf(float(h[1]) * delta, float(h[0]))
		h[0] = float(h[0]) - step
		health.heal(step)
		if float(h[0]) <= 0.001:
			_hots.erase(id)
	for key: StringName in _buffs.keys():
		var b: Array = _buffs[key]
		b[1] = float(b[1]) - delta
		if float(b[1]) <= 0.0:
			_buffs.erase(key)
	if class_data.resource_mode == ClassData.ResourceMode.POOL and resonance < max_resource():
		_fight_check_left -= delta
		if _fight_check_left <= 0.0:
			_fight_check_left = 0.5
			_fight_near = fight_near()
		if in_combat() or _fight_near:
			var rate := class_data.resource_regen * (1.0 + stat(&"sap_regen_pct") / 100.0)
			resonance = minf(resonance + rate * delta, max_resource())
			resonance_changed.emit(resonance, max_resource())


## M11: is a fight going on around this hero - an enemy within
## FIGHT_NEAR_RANGE hunting someone? A healer who only heals is never hit
## nor hitting, yet its party is fighting.
func fight_near() -> bool:
	for e in EnemyBase.all_enemies:
		if not is_instance_valid(e) or e.ai_state in [EnemyBase.AIState.DEAD, EnemyBase.AIState.IDLE, EnemyBase.AIState.RETURN] \
				or not e.targetable:
			continue
		if (e.target == null or not is_instance_valid(e.target)) and e.target_peer == 0:
			continue
		if e.global_position.distance_to(global_position) <= FIGHT_NEAR_RANGE:
			return true
	return false


## M11: the ally a targeted heal goes to - the one under the crosshair, else
## the one with the lowest health share (that misses some) within ALLY_RANGE,
## else this hero. Bots and heroes without a camera skip the crosshair.
func pick_heal_target() -> Player:
	if targeting != null and camera_rig != null:
		var aimed := targeting.ally_under_aim(ALLY_RANGE)
		if aimed != null:
			return aimed
	var zone := ZoneBase.zone_of(self)
	var best: Player = self
	var best_frac := health.current_health / maxf(health.max_health, 1.0)
	if zone == null:
		return best
	for ally in zone.players_within(global_position, ALLY_RANGE):
		var frac := ally.health.current_health / maxf(ally.health.max_health, 1.0)
		if frac < best_frac - 0.001:
			best_frac = frac
			best = ally
	return best


## M11: does this hero show where its heal would go (a healer with a heal slotted)?
func shows_heal_target() -> bool:
	return false


## M11: current and saved vitals: health, and a POOL resource (a BUILD one
## starts empty in every zone). Kept across travel and in the save (user
## 2026-09-30: travelling no longer heals).
func vitals() -> Dictionary:
	var v := {"hp": health.current_health}
	if class_data.resource_mode == ClassData.ResourceMode.POOL:
		v["resource"] = resonance
	return v


func restore_vitals(v: Dictionary) -> void:
	if v.has("hp"):
		health.current_health = clampf(float(v["hp"]), 1.0, health.max_health)
		health.health_changed.emit(health.current_health, health.max_health)
	if class_data.resource_mode == ClassData.ResourceMode.POOL and v.has("resource"):
		resonance = clampf(float(v["resource"]), 0.0, max_resource())
		resonance_changed.emit(resonance, max_resource())


# ---------------------------------------------------------------------------
# Visuals
# ---------------------------------------------------------------------------

func _build_visual() -> void:
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)
	if not Net.has_view():  # M09 dedicated server: facing and the ability pivot, nothing drawn
		_weapon_pivot = Node3D.new()
		_weapon_pivot.name = "WeaponPivotStandIn"
		_visual.add_child(_weapon_pivot)
		return
	if _build_rigged_visual():
		return

	const MODEL_PATH := "res://assets/models/player_runebreaker.glb"
	if ResourceLoader.exists(MODEL_PATH):
		var model := (load(MODEL_PATH) as PackedScene).instantiate() as Node3D
		model.rotation.y = PI  # Blender -Y front → Godot +Z; we face -Z
		_visual.add_child(model)
		_build_weapon()
		return

	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.32, 0.34, 0.44)
	iron.roughness = 0.7
	var accent := StandardMaterial3D.new()
	accent.albedo_color = Color(0.16, 0.55, 0.55)
	accent.roughness = 0.5
	var rune_glow := StandardMaterial3D.new()
	rune_glow.albedo_color = Color(1.0, 0.6, 0.25)
	rune_glow.emission_enabled = true
	rune_glow.emission = Color(1.0, 0.55, 0.2)
	rune_glow.emission_energy_multiplier = 1.6
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.85, 0.68, 0.55)

	# Chunky armored silhouette: wide torso, big pauldrons, small head.
	var torso := MeshInstance3D.new()
	var torso_mesh := BoxMesh.new()
	torso_mesh.size = Vector3(0.72, 0.62, 0.44)
	torso_mesh.material = iron
	torso.mesh = torso_mesh
	torso.position = Vector3(0, 1.05, 0)
	_visual.add_child(torso)

	var belt := MeshInstance3D.new()
	var belt_mesh := BoxMesh.new()
	belt_mesh.size = Vector3(0.5, 0.28, 0.36)
	belt_mesh.material = accent
	belt.mesh = belt_mesh
	belt.position = Vector3(0, 0.68, 0)
	_visual.add_child(belt)

	var legs := MeshInstance3D.new()
	var legs_mesh := BoxMesh.new()
	legs_mesh.size = Vector3(0.44, 0.55, 0.3)
	legs_mesh.material = iron
	legs.mesh = legs_mesh
	legs.position = Vector3(0, 0.3, 0)
	_visual.add_child(legs)

	for side: float in [-1.0, 1.0]:
		var pauldron := MeshInstance3D.new()
		var pmesh := BoxMesh.new()
		pmesh.size = Vector3(0.28, 0.24, 0.34)
		pmesh.material = accent
		pauldron.mesh = pmesh
		pauldron.position = Vector3(side * 0.48, 1.32, 0)
		_visual.add_child(pauldron)

	var head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.17
	head_mesh.height = 0.34
	head_mesh.material = skin
	head.mesh = head_mesh
	head.position = Vector3(0, 1.56, 0)
	_visual.add_child(head)

	# Rune sigil on the chest — the class identity glow.
	var sigil := MeshInstance3D.new()
	var sigil_mesh := BoxMesh.new()
	sigil_mesh.size = Vector3(0.16, 0.22, 0.05)
	sigil_mesh.material = rune_glow
	sigil.mesh = sigil_mesh
	sigil.position = Vector3(0, 1.08, -0.23)
	_visual.add_child(sigil)
	_build_weapon()


## Legacy alias; the live rig comes from class_data.rig_path.
const RIG_PATH := "res://assets/models/chars/runebreaker.glb"
var animator: CharacterAnimator = null
var _rune_glow: StandardMaterial3D


## M06 rigged hero (the weapon is part of the skinned mesh on hand.R). The
## rig sits on a RigRoot below `_visual` — flinches go there, never on
## `_visual`, whose yaw is the gameplay facing. `_weapon_pivot` becomes an
## invisible stand-in so the legacy ability tweens stay untouched. Returns
## false when the GLB is missing (legacy visuals then).
func _build_rigged_visual() -> bool:
	var scene := ArtKit.rig_scene(class_data.rig_path if class_data.rig_path != "" else RIG_PATH)
	if scene == null:
		return false
	var model := scene.instantiate() as Node3D
	model.rotation.y = PI
	var rig_root := Node3D.new()
	rig_root.name = "RigRoot"
	_visual.add_child(rig_root)
	rig_root.add_child(model)
	var mesh := model.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	_body_mat = ArtKit.character_material(class_data.material_id if class_data.material_id != "" else "runebreaker")
	if class_data.body_tint != Color.WHITE:  # M10: a class borrowing another rig until its own exists
		_body_mat = _body_mat.duplicate() as StandardMaterial3D
		_body_mat.albedo_color = class_data.body_tint
	mesh.set_surface_override_material(0, _body_mat)
	_rune_glow = ArtKit.glow_material(ArtKit.color("color_roles.%s.body" % class_data.resource_color_role), 1.2)
	mesh.set_surface_override_material(1, _rune_glow)
	if mesh.mesh.get_surface_count() > 2:
		_rig_mesh = mesh
		equipment.changed.connect(_refresh_blade)
		_refresh_blade()
	resonance_changed.connect(_on_resonance_glow)
	animator = CharacterAnimator.create(self, model, _anim_profile())
	if animator != null:
		animator.full_rate = true  # the hero never drops animation rate
		health.damaged.connect(func(_hit: HitInfo) -> void: animator.flinch())
	_weapon_pivot = Node3D.new()
	_weapon_pivot.name = "WeaponPivotStandIn"
	_visual.add_child(_weapon_pivot)
	return true


## CharacterAnimator profile of this class's rig: action_started names -> clips.
## The chassis maps locomotion, dodge and flinch; a class adds its actions.
func _anim_profile() -> Dictionary:
	return {
		"idle": &"idle", "run": &"run", "run_speed": MAX_SPEED, "layered": true,
		"actions": {&"dodge": &"dodge"},
		"upper": {},
		"flinch": &"flinch",
		# back in MOVE and moving: the run takes over an action's follow-through
		"free": func() -> bool: return state == State.MOVE,
	}


var _body_mat: StandardMaterial3D
var _rig_mesh: MeshInstance3D
var _cindermaw_mat: StandardMaterial3D


## M06 C6: the weapon surface shows the equipped legendary weapon — Cindermaw's
## basalt with a molten, breathing edge; any other weapon the class's steel.
func _refresh_blade() -> void:
	if _rig_mesh == null:
		return
	var weapon: ItemData = equipment.equipped.get(ItemData.Slot.WEAPON)
	if weapon != null and weapon.legendary_id == &"cindermaw":
		if _cindermaw_mat == null:
			_cindermaw_mat = StandardMaterial3D.new()
			_cindermaw_mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
			_cindermaw_mat.albedo_color = ArtKit.color("palettes.highlands.basalt.2")
			_cindermaw_mat.emission_enabled = true
			_cindermaw_mat.emission = ArtKit.color("color_roles.fire.body")
			_cindermaw_mat.emission_energy_multiplier = 0.9
			_cindermaw_mat.set_meta(ArtKit.KEEP_EMISSION, true)
			var breathe := create_tween().set_loops()
			breathe.tween_property(_cindermaw_mat, "emission_energy_multiplier", 1.5, 0.8).set_trans(Tween.TRANS_SINE)
			breathe.tween_property(_cindermaw_mat, "emission_energy_multiplier", 0.7, 0.9).set_trans(Tween.TRANS_SINE)
		_rig_mesh.set_surface_override_material(2, _cindermaw_mat)
	else:
		_rig_mesh.set_surface_override_material(2, _body_mat)


## The armor runes are the in-world resource meter: dim when empty, bright
## when full.
func _on_resonance_glow(current: float, maximum: float) -> void:
	if _rune_glow != null:
		_rune_glow.emission_energy_multiplier = lerpf(0.9, 3.2, clampf(current / maximum, 0.0, 1.0))


## Broad rune blade on the right hand (legacy visuals only), swung via pivot
## tweens. Always code-built: abilities animate this pivot directly.
func _build_weapon() -> void:
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.32, 0.34, 0.44)
	iron.roughness = 0.7
	var rune_glow := StandardMaterial3D.new()
	rune_glow.albedo_color = Color(1.0, 0.6, 0.25)
	rune_glow.emission_enabled = true
	rune_glow.emission = Color(1.0, 0.55, 0.2)
	rune_glow.emission_energy_multiplier = 1.6

	_weapon_pivot = Node3D.new()
	_weapon_pivot.name = "WeaponPivot"
	_weapon_pivot.position = Vector3(0.45, 1.15, 0)
	_visual.add_child(_weapon_pivot)

	var blade := MeshInstance3D.new()
	var blade_mesh := BoxMesh.new()
	blade_mesh.size = Vector3(0.1, 0.05, 1.15)
	blade_mesh.material = iron
	blade.mesh = blade_mesh
	blade.position = Vector3(0, 0, -0.65)
	_weapon_pivot.add_child(blade)
	var edge := MeshInstance3D.new()
	var edge_mesh := BoxMesh.new()
	edge_mesh.size = Vector3(0.04, 0.06, 0.9)
	edge_mesh.material = rune_glow
	edge.mesh = edge_mesh
	edge.position = Vector3(0, 0, -0.7)
	_weapon_pivot.add_child(edge)
	_weapon_pivot.rotation_degrees = Vector3(-25, 15, 0)


## A quick weapon gesture on the legacy pivot (instant casts).
func _flourish(to: Vector3, out_time: float, back_time: float) -> void:
	var tw := _weapon_pivot.create_tween()
	tw.tween_property(_weapon_pivot, "rotation_degrees", to, out_time)
	tw.tween_property(_weapon_pivot, "rotation_degrees", Vector3(-25, 15, 0), back_time) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func apply_hitstop(duration: float) -> void:
	_hitstop_left = maxf(_hitstop_left, duration)


func _physics_process(delta: float) -> void:
	if net_role != NetRole.OWNER:
		return  # M09: NetWorld poses puppets and proxies from the network
	if _hitstop_left > 0.0:
		_hitstop_left -= delta
		_poll_during_hitstop()
		return
	for key: StringName in _cooldowns.keys():
		_cooldowns[key] = maxf(_cooldowns[key] - delta, 0.0)
	if _barrier_time > 0.0:
		_barrier_time -= delta
		if _barrier_time <= 0.0:
			barrier = 0.0
	if _heal_left > 0.0:  # M10b: a draught at work
		if health.is_dead:
			_heal_left = 0.0
		else:
			var step := minf(_heal_rate * delta, _heal_left)
			_heal_left -= step
			health.heal(step)
	_tick_support(delta)
	if _buffer_timer > 0.0:
		_buffer_timer -= delta
		if _buffer_timer <= 0.0:
			_buffered_action = &""

	intent.clear()
	if input_source != null:
		input_source.poll(intent, self)
	_read_action_input()

	match state:
		State.MOVE:
			# M08 notes: a dodge pressed a moment too early (cooldown, a hit
			# freeze) goes off the tick it can, instead of being dropped.
			if _buffered_action == &"dodge" and try_dodge():
				_buffered_action = &""
				_buffer_timer = 0.0
			else:
				_process_move(delta)
		State.DODGE:
			_process_dodge(delta)
		_:
			_process_class_state(delta)

	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	velocity += _knockback_velocity
	move_and_slide()
	velocity -= _knockback_velocity
	_knockback_velocity = _knockback_velocity.lerp(Vector3.ZERO, minf(8.0 * delta, 1.0))


## A class's own states (melee, casts, dashes). The chassis has none: back to MOVE.
func _process_class_state(_delta: float) -> void:
	state = State.MOVE


## Summed value of a stat key from equipment and progression (level bonuses,
## talents). Every ability hook reads stats through here.
func stat(key: StringName) -> float:
	return equipment.stat(key) + (progression.stat(key) if progression != null else 0.0) + buff_stat(key) \
		+ Blessings.stat(blessings, key)


## Legendary power (equipment) or behavior talent (progression).
func has_power(id: StringName) -> bool:
	return equipment.has_power(id) or (progression != null and progression.has_power(id))


## Central ability hit roll: applies equipment damage and crit bonuses.
func roll_ability_hit(data: AbilityData) -> HitInfo:
	var damage_mult := 1.0 + stat(&"damage_pct") / 100.0
	var bonus_crit := stat(&"crit_pct") / 100.0
	var hit := data.roll_hit(global_position, damage_mult, bonus_crit)
	mark_combat()  # swinging at something ends a sprint
	hit.from_player = true
	hit.attacker_id = get_instance_id()  # M07b: talent mults, XP and loot follow the attacker
	hit.ability = data.id
	hit.burn_mult = 1.0 + stat(&"burn_pct") / 100.0
	hit.chill_bonus = stat(&"chill_duration")  # M10 Cold Snap
	return hit


## M07 conditional talent damage, applied when a player hit lands.
func talent_damage_mult(hit: HitInfo, enemy: EnemyBase) -> float:
	var pct := 0.0
	if enemy.status.has_shock():
		pct += stat(&"shocked_dmg_pct")
	if enemy.status.has_burn():
		pct += stat(&"burning_dmg_pct")
	if enemy.status.has_chill():
		pct += stat(&"chilled_dmg_pct")  # M10 Shatter
	if enemy.target == self:
		pct += stat(&"aggro_dmg_pct")  # M10 Hold the Line: the tank hits what it holds
	if enemy.status.is_rooted():
		pct += stat(&"rooted_dmg_pct")  # M11 Grasping Briars
	if ABILITY_DAMAGE_STATS.has(hit.ability):
		pct += stat(ABILITY_DAMAGE_STATS[hit.ability])
	return 1.0 + pct / 100.0


## Effective cooldown of `id` with a base of `base` seconds: global reduction,
## plus the ability's own one (ABILITY_CD_STATS), clamped to 35-100 %. Pure,
## so the character sheet shows the same number the game uses.
func cooldown_for(id: StringName, base: float) -> float:
	var mult := 1.0 - stat(&"cooldown_pct") / 100.0
	if ABILITY_CD_STATS.has(id):
		mult *= 1.0 - stat(ABILITY_CD_STATS[id]) / 100.0
	return base * clampf(mult, 0.35, 1.0)


## Central cooldown setter.
func _set_cooldown(id: StringName, base: float) -> void:
	_cooldowns[id] = cooldown_for(id, base)


func _on_cooldown(id: StringName) -> bool:
	return float(_cooldowns.get(id, 0.0)) > 0.0


## Class resource an ability costs right now (talents and gear may lower it).
func resource_cost(id: StringName) -> float:
	var data := ability(id)
	return data.resonance_cost if data != null else 0.0


## This tick's pressed actions (from the intent) -> try or buffer. Unknown or
## unslotted abilities never reach the buffer, so a locked key can't queue an
## action. Held repeat abilities (auto-fire) try again every tick they're held.
func _read_action_input() -> void:
	if input_locked:
		return
	for action in intent.pressed:
		_try_or_buffer(action)
	for action in intent.held:
		if intent.pressed.has(action):
			continue
		var data := ability(action)
		if data != null and data.repeat_while_held and can_use(action):
			_try_action(action)


func _try_or_buffer(action: StringName) -> void:
	if not can_use(action):
		return
	if not _try_action(action):
		_buffered_action = action
		_buffer_timer = INPUT_BUFFER


## Presses during a hit freeze are kept (M08 notes: a dodge right after a hit
## got lost): they go to the buffer and fire as soon as the state allows.
func _poll_during_hitstop() -> void:
	if input_source == null or input_locked:
		return
	intent.clear()
	input_source.poll(intent, self)
	for action in intent.pressed:
		if can_use(action):
			_buffered_action = action
			_buffer_timer = INPUT_BUFFER


func _consume_buffer() -> void:
	if _buffered_action != &"":
		var action := _buffered_action
		_buffered_action = &""
		_buffer_timer = 0.0
		_try_action(action)


func _try_action(action: StringName) -> bool:
	if not can_use(action) or not _actions.has(action):
		return false
	return (_actions[action] as Callable).call()


## Tests, captures and bots-by-script: start ability `id` of this class right
## now, slotted or not (it must still be known; cooldown and state apply).
func try_ability(id: StringName) -> bool:
	if not _actions.has(id):
		return false
	return (_actions[id] as Callable).call()


# ---------------------------------------------------------------------------
# Movement
# ---------------------------------------------------------------------------

## Movement direction of the current tick (world-space, flat), as polled
## into the intent by the input source.
func _move_input_dir() -> Vector3:
	return intent.move_dir


## Last time this hero hit or was hit (msec), for the sprint's combat lock.
var _last_combat_msec: int = -1000000
var _sprint_note_at: int = -1000000


func mark_combat() -> void:
	_last_combat_msec = Time.get_ticks_msec()
	if _hots.has(FOOD_HOT):  # M12: a hit, dealt or taken, ends the meal
		_hots.erase(FOOD_HOT)
		if is_local:
			var zone := ZoneBase.zone_of(self)
			if zone != null and zone.hud != null:
				zone.hud.toast(Texts.t("ui.food.interrupted"), UiTheme.MUTED)


func in_combat() -> bool:
	return Time.get_ticks_msec() - _last_combat_msec < int(SPRINT_COMBAT_LOCK * 1000.0)


## Sprinting right now: Shift held while moving, out of combat.
func is_sprinting() -> bool:
	return state == State.MOVE and intent.sprint and intent.move_dir != Vector3.ZERO and not in_combat()


func _process_move(delta: float) -> void:
	var dir := _move_input_dir()
	var target_vel := dir * MAX_SPEED * (1.0 + stat(&"move_pct") / 100.0) * (1.0 - slow_pct)
	if is_sprinting():
		target_vel *= SPRINT_MULT
	elif intent.sprint and dir != Vector3.ZERO and is_local \
			and Time.get_ticks_msec() - _sprint_note_at > 4000:
		_sprint_note_at = Time.get_ticks_msec()  # held in a fight: say why once in a while
		var zone := ZoneBase.zone_of(self)
		if zone != null and zone.hud != null:
			zone.hud.toast("No sprinting in combat", UiTheme.MUTED)
	var rate := ACCEL if dir != Vector3.ZERO else DECEL
	velocity.x = move_toward(velocity.x, target_vel.x, rate * delta)
	velocity.z = move_toward(velocity.z, target_vel.z, rate * delta)
	if Time.get_ticks_msec() < _aim_hold_until:
		_face_aim_instant()  # a caster keeps facing its aim while it strafes
	elif dir != Vector3.ZERO:
		_face_direction(dir, delta)
	if dir != Vector3.ZERO:
		_footsteps(delta)


func _face_direction(dir: Vector3, delta: float) -> void:
	var target_yaw := atan2(-dir.x, -dir.z)
	_visual.rotation.y = lerp_angle(_visual.rotation.y, target_yaw, minf(ROTATION_SPEED * delta, 1.0))


func _face_aim_instant() -> void:
	var aim := aim_direction()
	_visual.rotation.y = atan2(-aim.x, -aim.z)


## Face the aim now and keep facing it for AIM_HOLD_MSEC (casts on the move).
func _hold_aim() -> void:
	_face_aim_instant()
	_aim_hold_until = Time.get_ticks_msec() + AIM_HOLD_MSEC


func facing() -> Vector3:
	return -_visual.global_transform.basis.z


func aim_direction() -> Vector3:
	if camera_rig == null:
		return intent.aim_dir.normalized() if intent.aim_dir != Vector3.ZERO else facing()
	var exclude: Array[RID] = [get_rid()]
	var aim_point := camera_rig.get_aim_point(exclude)
	# The camera looks down at the hero, so its ray meets the floor a few
	# metres ahead: aim at muzzle height above that spot instead of into it
	# (user feedback 2026-09-24). Level on flat ground, follows slopes.
	if camera_rig.last_aim_on_floor:
		aim_point.y += MUZZLE_HEIGHT
	var from := muzzle_position()
	var dir := aim_point - from
	if dir.length() < 1.0:
		dir = -camera_rig.camera.global_transform.basis.z
	dir.y = clampf(dir.y / maxf(dir.length(), 0.01), -0.6, 0.6) * dir.length()
	return dir.normalized()


const MUZZLE_HEIGHT := 1.2


func muzzle_position() -> Vector3:
	return global_position + Vector3(0, MUZZLE_HEIGHT, 0) + facing() * 0.5


func _footsteps(delta: float) -> void:
	_footstep_accum += delta * velocity.length()
	if _footstep_accum >= 2.6:
		_footstep_accum = 0.0
		Sfx.play("footstep", global_position, -12.0, 0.15)


# ---------------------------------------------------------------------------
# Dodge
# ---------------------------------------------------------------------------

func try_dodge() -> bool:
	if state == State.DODGE or _on_cooldown(&"dodge"):
		return false
	# Dodge cancels melee recovery and cast startup — the trust rule. A class
	# may refuse it in a committed moment and must end what the dodge cuts off.
	if not _dodge_allowed():
		return false
	_on_dodge_cancel()
	var dir := _move_input_dir()
	if dir == Vector3.ZERO:
		dir = _dodge_away_dir()
	_dodge_dir = dir
	state = State.DODGE
	_state_timer = 0.0
	_set_cooldown(&"dodge", DODGE_COOLDOWN)
	health.invulnerable = true
	_visual.rotation.y = atan2(-dir.x, -dir.z)
	hero_fx(&"dodge", [global_position, dir])
	cooldowns_changed.emit()
	action_started.emit(&"dodge")
	return true


## False while the class is in a moment the dodge must not cut (a slam).
func _dodge_allowed() -> bool:
	return true


## The dodge is about to cut the current state off: end it properly (a class
## resolves its dash, for example).
func _on_dodge_cancel() -> void:
	pass


## Space without a direction: away from the closest threat (the soft target,
## else the nearest enemy within DODGE_THREAT_RANGE) - M08 notes: it used to
## dash along the facing, which after a swing points into the enemy. Forward
## when nothing is near.
func _dodge_away_dir() -> Vector3:
	var threat: Node3D = null
	var t: EnemyBase = targeting.current if targeting != null else null
	if t != null and is_instance_valid(t) and t.ai_state != EnemyBase.AIState.DEAD \
			and t.global_position.distance_to(global_position) <= DODGE_THREAT_RANGE:
		threat = t
	else:
		var best := DODGE_THREAT_RANGE
		for e in EnemyBase.all_enemies:
			if not is_instance_valid(e) or e.ai_state == EnemyBase.AIState.DEAD:
				continue
			var d := e.global_position.distance_to(global_position)
			if d < best:
				best = d
				threat = e
	if threat == null:
		return facing()
	var away := global_position - threat.global_position
	away.y = 0.0
	return away.normalized() if away.length() > 0.05 else -facing()


func _process_dodge(delta: float) -> void:
	_state_timer += delta
	if _state_timer >= DODGE_IFRAMES:
		health.invulnerable = god_mode
	if _state_timer < DODGE_DURATION:
		# Ease-out dash: strong start, soft landing.
		var t := _state_timer / DODGE_DURATION
		var speed := DODGE_SPEED * (1.0 - t * t * 0.7)
		velocity.x = _dodge_dir.x * speed
		velocity.z = _dodge_dir.z * speed
	elif _state_timer < DODGE_DURATION + DODGE_RECOVERY:
		velocity.x = move_toward(velocity.x, 0, DECEL * delta)
		velocity.z = move_toward(velocity.z, 0, DECEL * delta)
	else:
		state = State.MOVE
		_consume_buffer()


## Enemies whose hurtbox overlaps a sphere (each once).
func _query_hurtboxes(center: Vector3, radius: float) -> Array[Node]:
	var space := get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis(), center)
	query.collision_mask = 0b10000  # enemy hurtboxes
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var found: Array[Node] = []
	for result: Dictionary in space.intersect_shape(query, 16):
		var hb := result["collider"] as Hurtbox
		if hb != null and hb.owner_entity != null and not found.has(hb.owner_entity):
			found.append(hb.owner_entity)
	return found


# ---------------------------------------------------------------------------
# Class resource / damage intake
# ---------------------------------------------------------------------------

func gain_resonance(amount: float, lightning: bool = false) -> void:
	amount *= 1.0 + (stat(&"resonance_pct") + (stat(&"lightning_res_pct") if lightning else 0.0)) / 100.0
	resonance = minf(resonance + amount, max_resource())
	resonance_changed.emit(resonance, max_resource())


func spend_resonance(amount: float) -> void:
	resonance = maxf(resonance - amount, 0.0)
	resonance_changed.emit(resonance, max_resource())


func take_hit(hit: HitInfo) -> bool:
	if god_mode or net_role == NetRole.PUPPET:
		return false
	mark_combat()  # attacked (even a dodged attack): no sprinting for a moment
	if net_role == NetRole.PROXY:
		# M09: the owner decides (its i-frames, whether it still stands in the area).
		var zone := ZoneBase.zone_of(self)
		if zone == null or zone.net_world == null or health.is_dead:
			return false
		zone.net_world.forward_hurt(self, hit)
		return true
	# M07 Unbroken: an attack met inside the dodge's i-frames grants a barrier.
	if health.invulnerable and not health.is_dead and has_power(&"unbroken") \
			and float(_cooldowns.get(&"unbroken", 0.0)) <= 0.0:
		_cooldowns[&"unbroken"] = UNBROKEN_COOLDOWN
		grant_barrier(UNBROKEN_BARRIER, 3.0)
	if not health.invulnerable and not health.is_dead and _guard_hit(hit):
		return false  # M10: a class stance took the whole hit (the tank's parry)
	hit.damage *= damage_taken_mult()
	if barrier > 0.0 and not health.invulnerable and not health.is_dead:
		var absorbed := minf(barrier, hit.damage)
		barrier -= absorbed
		hit.damage -= absorbed
		_on_barrier_absorbed(absorbed)
		if hit.damage <= 0.01:
			return false
	if not health.apply_hit(hit):
		return false
	if hit.applies_chill and not hit.from_player:
		apply_slow(CHILL_SLOW, CHILL_SLOW_TIME)  # M12: the mourner's scream
	var push := (global_position - hit.source_position)
	push.y = 0
	_knockback_velocity += push.normalized() * hit.knockback
	Sfx.play("player_hurt", global_position, -2.0)
	feel_shake(0.25)
	return true


## M10: the share of an enemy hit this hero still takes: talents and gear
## (`dr_pct`), a Warding Rune it stands in, the class's own (the tank's
## Unyielding). Never below 1 - MAX_DAMAGE_REDUCTION. A block comes on top.
func damage_taken_mult() -> float:
	var reduction := stat(&"dr_pct") / 100.0 + WardingRune.reduction_at(self) + _class_damage_reduction()
	return clampf(1.0 - reduction, 1.0 - MAX_DAMAGE_REDUCTION, 1.0)


## A class's own damage reduction right now (0-1).
func _class_damage_reduction() -> float:
	return 0.0


## A class stance meeting an enemy hit before damage reduction (the tank's
## block shrinks `hit.damage`); true = the whole hit is taken care of.
func _guard_hit(_hit: HitInfo) -> bool:
	return false


## M10 threat: how much the enemies mind this hero's damage (the class's
## factor; the tank threatens double).
func threat_mult() -> float:
	return class_data.threat_mult if class_data != null else 1.0


func _on_damaged(hit: HitInfo) -> void:
	GameFeel.damage_number(global_position + Vector3(0, 1.9, 0), hit.damage, Color(1.0, 0.3, 0.25))


func _on_died() -> void:
	if net_role != NetRole.OWNER:
		return  # remote heroes die on their owner's machine, never here
	player_died.emit()


## M09: pose and vitals of a remote hero from the network (NetWorld). Never
## emits `player_died`: the owner handles its own death and respawn.
func apply_net_state(pos: Vector3, yaw: float, vel: Vector3, net_state: int, hp: float, hp_max: float,
		net_barrier: float = 0.0) -> void:
	global_position = pos
	_visual.rotation.y = yaw
	velocity = vel
	state = clampi(net_state, 0, State.size() - 1) as State
	health.max_health = maxf(hp_max, 1.0)
	health.current_health = clampf(hp, 0.0, health.max_health)
	health.is_dead = hp <= 0.0
	barrier = maxf(net_barrier, 0.0)  # M11: shown in the party frames (the owner absorbs)


## Facing yaw (the network sends it; `_visual` holds the gameplay facing).
func facing_yaw() -> float:
	return _visual.rotation.y


# ---------------------------------------------------------------------------
# M07 barrier
# ---------------------------------------------------------------------------

const BULWARK_RADIUS := 3.0


## Absorbs damage before health for `duration` s (the larger barrier wins).
func grant_barrier(amount: float, duration: float) -> void:
	barrier = maxf(barrier, amount)
	_barrier_time = maxf(_barrier_time, duration)
	hero_fx(&"barrier", [duration])


func _on_barrier_absorbed(amount: float) -> void:
	var scene := get_tree().current_scene
	VFX.flash(scene, global_position + Vector3(0, 1.1, 0), ArtKit.color("color_roles.player_accent.body"), 0.8, 0.08)
	Sfx.play("bolt_impact", global_position, -6.0, 0.1, 1.4)
	GameFeel.damage_number(global_position + Vector3(0, 2.0, 0), amount, ArtKit.color("color_roles.player_accent.hot"))
	# M07 Glacial Bulwark: whoever struck the guard up close is Chilled.
	if has_power(&"glacial_bulwark"):
		for enemy in EnemyBase.all_enemies:
			if is_instance_valid(enemy) and enemy.ai_state != EnemyBase.AIState.DEAD \
					and enemy.global_position.distance_to(global_position) <= BULWARK_RADIUS:
				enemy.status.apply_chill()


func cooldown_fraction(id: StringName) -> float:
	var total: float = DODGE_COOLDOWN if id == &"dodge" else 1.0
	var data := ability(id)
	if data != null and data.cooldown > 0.0:
		total = data.cooldown
	return clampf(_cooldowns.get(id, 0.0) / total, 0.0, 1.0)


func reset_cooldowns() -> void:
	_cooldowns.clear()
	cooldowns_changed.emit()
