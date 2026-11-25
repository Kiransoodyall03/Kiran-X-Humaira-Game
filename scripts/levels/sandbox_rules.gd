class_name SandboxRules
extends Node
## Sandbox-only conveniences: revives the player a moment after they are defeated,
## so sparring with the dummy can continue without restarting the scene.

@export var player: Combatant
@export_range(0, 600, 1, "suffix:frames") var revive_delay_frames: int = 120

var _revive_in: int = -1


func _ready() -> void:
	if player != null:
		player.died.connect(func() -> void: _revive_in = revive_delay_frames)


func _physics_process(_delta: float) -> void:
	if _revive_in < 0:
		return
	_revive_in -= 1
	if _revive_in <= 0:
		_revive_in = -1
		player.revive()
