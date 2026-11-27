class_name SandboxRules
extends Node
## Sandbox-only conveniences: revives the player, the training dummy, the duelist and the
## large monster a moment after they are defeated, so sparring can continue without
## restarting the scene. (The duelist and the monster are put back at home when revived.)
## Once the heroine has a shrine respawn point (she rested at a shrine, or a start shrine
## registered), her death is left to her PlayerRest (respawn at the shrine) and this
## doesn't revive her in place.

@export var player: Combatant
@export_range(0, 600, 1, "suffix:frames") var revive_delay_frames: int = 120
## The sparring opponent. Revived after dummy_revive_delay_frames when it dies.
@export var dummy: Combatant
@export_range(0, 600, 1, "suffix:frames") var dummy_revive_delay_frames: int = 180
## The capsule duelist. Revived after duelist_revive_delay_frames when it dies.
@export var duelist: Combatant
@export_range(0, 1200, 1, "suffix:frames") var duelist_revive_delay_frames: int = 240
## The large monster (monster #1). Revived after monster_revive_delay_frames when it dies.
@export var monster: Combatant
@export_range(0, 1200, 1, "suffix:frames") var monster_revive_delay_frames: int = 300

## Frames left until each pending revive, by Combatant.
var _revive_in: Dictionary[Combatant, int] = {}


func _ready() -> void:
	if player != null:
		player.died.connect(_on_player_died)
	if dummy != null:
		dummy.died.connect(func() -> void: _revive_in[dummy] = dummy_revive_delay_frames)
	if duelist != null:
		duelist.died.connect(func() -> void: _revive_in[duelist] = duelist_revive_delay_frames)
	if monster != null:
		monster.died.connect(func() -> void: _revive_in[monster] = monster_revive_delay_frames)


## True when the heroine's death is handled by a shrine respawn instead of this revive.
func player_respawns_at_shrine() -> bool:
	if player == null or player.get_parent() == null:
		return false
	var rest: PlayerRest = player.get_parent().get_node_or_null(^"Rest") as PlayerRest
	return rest != null and rest.will_respawn()


## Frames left until `c` is revived, or -1 when no revive is pending for it.
func frames_until_revive(c: Combatant) -> int:
	return _revive_in.get(c, -1)


func _on_player_died() -> void:
	if not player_respawns_at_shrine():
		_revive_in[player] = revive_delay_frames


func _physics_process(_delta: float) -> void:
	if HitStopService.is_frozen():
		return
	for c: Combatant in _revive_in.keys():
		_revive_in[c] -= 1
		if _revive_in[c] <= 0:
			_revive_in.erase(c)
			if c.is_dead:
				c.revive()
