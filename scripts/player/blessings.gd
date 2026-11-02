class_name Blessings
extends Object
## M12: the rune blessings - permanent and per character, one small stat
## each: three from the trial shrines (one per sub-biome), one for all twelve
## shards of the Shattered Rune. Player.stat() adds them like gear.
## M14b: the core shards of the Rune's anchors give larger ones (the story's
## Act 2: water, fire, the optional storm).

const DEFS := {
	&"ashwick": {"stat": &"max_hp_pct", "value": 3.0},
	&"charwood": {"stat": &"damage_pct", "value": 2.0},
	&"emberfall": {"stat": &"move_pct", "value": 2.0},
	&"shards": {"stat": &"max_hp_pct", "value": 3.0},
	&"core_water": {"stat": &"max_hp_pct", "value": 8.0},
	&"core_fire": {"stat": &"damage_pct", "value": 6.0},
	&"core_storm": {"stat": &"cooldown_pct", "value": 6.0},
}
const ORDER: Array[StringName] = [&"ashwick", &"charwood", &"emberfall", &"shards", &"core_water", &"core_fire", &"core_storm"]


## The sum of `key` over the blessings in `owned`.
static func stat(owned: PackedStringArray, key: StringName) -> float:
	var total := 0.0
	for id in owned:
		var def: Dictionary = DEFS.get(StringName(id), {})
		if StringName(def.get("stat", &"")) == key:
			total += float(def["value"])
	return total


static func title(id: StringName) -> String:
	return Texts.t("blessing.%s" % id)


static func effect(id: StringName) -> String:
	return Texts.t("blessing.%s.effect" % id)
