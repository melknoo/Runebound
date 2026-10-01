class_name PuzzleSwitch
extends Interactable
## M12: a puzzle part used with [E] (turn a monolith, push the boulder): the
## prompt text from the text table and a callback into its puzzle.

var text_key: String = ""
var on_use: Callable = Callable()
## Callable(hero) -> bool; empty = always usable.
var usable: Callable = Callable()


func prompt_text(_hero: Player) -> String:
	return Texts.t(text_key)


func can_interact(hero: Player) -> bool:
	return bool(usable.call(hero)) if usable.is_valid() else true


func interact(hero: Player) -> void:
	if on_use.is_valid():
		on_use.call(hero)
