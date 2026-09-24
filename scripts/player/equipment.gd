class_name Equipment
extends Node
## The player's gear: 7 slots (ItemData.Slot) + inventory. Aggregates affix stats and
## legendary powers; Player reads them at its ability hook points.

signal changed  # equipment or inventory contents changed

const INVENTORY_CAP := 24
const BASE_MAX_HP := 100.0

var player: Player
var inventory: Array[ItemData] = []
var equipped: Dictionary = {}  # ItemData.Slot -> ItemData

var _stats: Dictionary = {}          # StringName -> float (summed)
var _powers: Array[StringName] = []


func add_item(item: ItemData) -> bool:
	if inventory.size() >= INVENTORY_CAP:
		return false
	inventory.append(item)
	changed.emit()
	return true


func equip(item: ItemData) -> void:
	if not inventory.has(item):
		return
	inventory.erase(item)
	var previous: ItemData = equipped.get(item.slot)
	if previous != null:
		inventory.append(previous)
	equipped[item.slot] = item
	_recompute()
	changed.emit()


func unequip(slot: ItemData.Slot) -> void:
	var item: ItemData = equipped.get(slot)
	if item == null or inventory.size() >= INVENTORY_CAP:
		return
	equipped.erase(slot)
	inventory.append(item)
	_recompute()
	changed.emit()


func discard(item: ItemData) -> void:
	inventory.erase(item)
	changed.emit()


## Summed affix value across equipped items (0 when absent).
func stat(key: StringName) -> float:
	return _stats.get(key, 0.0)


func has_power(id: StringName) -> bool:
	return _powers.has(id)


func _recompute() -> void:
	_stats.clear()
	_powers.clear()
	for item: ItemData in equipped.values():
		for affix in item.affixes:
			var key: StringName = affix["stat"]
			_stats[key] = _stats.get(key, 0.0) + float(affix["value"])
		if item.legendary_id != &"":
			_powers.append(item.legendary_id)
	_apply_max_hp()


func _apply_max_hp() -> void:
	if player == null or player.health == null:
		return
	var health := player.health
	var fraction := 1.0
	if health.max_health > 0.0:
		fraction = clampf(health.current_health / health.max_health, 0.0, 1.0)
	health.max_health = BASE_MAX_HP + player.stat(&"max_hp")  # gear + levels + talents
	health.current_health = health.max_health * fraction
	health.health_changed.emit(health.current_health, health.max_health)
