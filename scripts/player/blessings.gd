class_name Blessings
extends Object
## M12: the rune blessings - permanent and per character, one small stat
## each: three from the trial shrines (one per sub-biome), one for all twelve
## shards of the Shattered Rune. Player.stat() adds them like gear.

const DEFS := {
	&"ashwick": {"stat": &"max_hp_pct", "value": 3.0},
	&"charwood": {"stat": &"damage_pct", "value": 2.0},
	&"emberfall": {"stat": &"move_pct", "value": 2.0},
	&"shards": {"stat": &"max_hp_pct", "value": 3.0},
}
const ORDER: Array[StringName] = [&"ashwick", &"charwood", &"emberfall", &"shards"]


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
