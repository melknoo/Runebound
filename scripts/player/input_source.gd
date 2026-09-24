class_name InputSource
extends RefCounted
## M07b: fills a PlayerIntent once per physics tick. LocalInputSource reads
## the keyboard and mouse; tests script one; a network peer will send one.


func poll(_intent: PlayerIntent, _player: Player) -> void:
	pass
