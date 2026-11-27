class_name Shrine
extends Node3D
## A shrine the heroine rests at (docs/COMBAT_SPEC.md "Shrines: rest and respawn").
## Greybox scene: scenes/world/shrine.tscn. While she stands in the InteractArea an
## on-screen "Rest" prompt shows; pressing interact rests (PlayerRest.rest): full health
## and posture, heals refilled, corruption reset, enemies respawned, and this shrine's
## SpawnPoint becomes her respawn point.
## She can't rest while dead, staggered, attacking, dodging or healing, or while a living
## hostile is within RestConfig.hostile_block_radius of the shrine. The prompt shows only
## when interact would rest her, or says "enemies nearby" when only a hostile is in the way;
## while she is busy, healing or staggered it is hidden.
## A start shrine registers itself as her respawn point when the level starts.
##
## Expected children: InteractArea (Area3D, mask = player layer), SpawnPoint (Marker3D:
## origin on the ground, -Z = the way she faces after a respawn), Prompt/Label (on-screen).

signal rested(rest: PlayerRest)

const GROUP: StringName = &"shrine"
const PROMPT_REST: String = "Rest  ·  E / X"
const PROMPT_BLOCKED: String = "Rest  ·  enemies nearby"

@export var config: RestConfig
## Registers this shrine as the heroine's respawn point when the level starts (the level's
## first shrine). Off: only resting here sets it.
@export var start_shrine: bool = false

@onready var _area: Area3D = $InteractArea
@onready var _spawn: Marker3D = $SpawnPoint
@onready var _prompt: Label = $Prompt/Label

## The heroine while she stands in the interact area, else null.
var _player: PlayerController


func _ready() -> void:
	assert(config != null, "Shrine needs a RestConfig")
	add_to_group(GROUP)
	_prompt.visible = false
	if start_shrine:
		_register_start.call_deferred()


func _physics_process(_delta: float) -> void:
	_player = _find_player()
	_refresh_prompt()
	if _player != null and Input.is_action_just_pressed(&"interact"):
		try_rest()


## Rests the heroine here if can_rest(). Returns true if she rested.
func try_rest() -> bool:
	if not can_rest():
		return false
	var rest: PlayerRest = _rest_of(_player)
	rest.rest(self, spawn_transform())
	rested.emit(rest)
	_refresh_prompt()
	return true


## The heroine is in the area, has a Rest node, can act, isn't busy or healing, and no
## living hostile is near.
func can_rest() -> bool:
	return _player_free() and not hostile_near()


## A living hostile Combatant's body is within RestConfig.hostile_block_radius.
func hostile_near() -> bool:
	if config.hostile_block_radius <= 0.0 or not is_inside_tree():
		return false
	var radius_sq: float = config.hostile_block_radius * config.hostile_block_radius
	for node: Node in get_tree().get_nodes_in_group(CorruptionMeter.HOSTILE_GROUP):
		var hostile: Node3D = node as Node3D
		var c: Combatant = Combatant.find_on(node)
		if hostile == null or c == null or c.is_dead:
			continue
		var offset: Vector3 = hostile.global_position - global_position
		offset.y = 0.0
		if offset.length_squared() <= radius_sq:
			return true
	return false


## The heroine is standing in the interact area.
func player_in_range() -> bool:
	return _player != null


## Where she respawns: SpawnPoint's global transform.
func spawn_transform() -> Transform3D:
	return _spawn.global_transform


func prompt_visible() -> bool:
	return _prompt.visible


func prompt_text() -> String:
	return _prompt.text


## The heroine is in the area, has a Rest node, can act (alive, not staggered) and isn't
## attacking, dodging or healing: everything can_rest() needs except "no hostile near".
func _player_free() -> bool:
	if _player == null or _rest_of(_player) == null:
		return false
	if _player.is_dead():
		return false
	if _player.combatant != null and not _player.combatant.can_act():
		return false
	return not _player.is_busy() and not _player.is_healing()


func _refresh_prompt() -> void:
	var shown: bool = _player_free()
	_prompt.visible = shown
	if shown:
		_prompt.text = PROMPT_BLOCKED if hostile_near() else PROMPT_REST


func _find_player() -> PlayerController:
	if not _area.monitoring:
		return null
	for b: Node3D in _area.get_overlapping_bodies():
		var player: PlayerController = b as PlayerController
		if player != null:
			return player
	return null


func _register_start() -> void:
	var player: PlayerController = get_tree().get_first_node_in_group(&"player") as PlayerController
	var rest: PlayerRest = _rest_of(player)
	if rest != null and not rest.has_respawn_point:
		rest.set_respawn_point(self, spawn_transform())


static func _rest_of(player: Node) -> PlayerRest:
	if player == null:
		return null
	return player.get_node_or_null(^"Rest") as PlayerRest
