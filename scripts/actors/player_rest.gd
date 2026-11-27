class_name PlayerRest
extends Node
## Shrine rest and respawn for the heroine. A child of the heroine named "Rest".
## Shrines (scripts/world/shrine.gd) call rest(): full health and posture, healing charges
## refilled, corruption reset (CorruptionMeter.reset_at_shrine), enemies respawned (every
## node in the "respawn_on_rest" group with a respawn() method), and that shrine becomes
## her respawn point.
## When she dies with a respawn point set, she respawns there after
## RestConfig.respawn_delay_frames combat frames (revived; with respawn_rests also a full
## rest). Without one (she never rested and no start shrine registered) nothing happens
## here, so a level's own rule (the sandbox's SandboxRules revive) takes over; SandboxRules
## asks will_respawn() so the two never both fire.
##
## Sibling nodes it uses (all optional): Combatant, Healing, CorruptionMeter, LockOn,
## CameraRig.

signal rested(shrine: Node3D)
signal respawn_point_changed(shrine: Node3D)
signal respawned(shrine: Node3D)

## Enemies (or anything) in this group get respawn() called on a rest.
const RESPAWN_GROUP: StringName = &"respawn_on_rest"
const NOT_PENDING: int = -1

@export var config: RestConfig

var body: PlayerController
var combatant: Combatant
var healing: PlayerHealing
var corruption: CorruptionMeter
var lock_on: LockOn
var camera_rig: ThirdPersonCamera
## The shrine she last rested at (or the level's start shrine), or null.
var respawn_shrine: Node3D
## Where she respawns: origin = feet, -Z (forward) = the way she faces.
var respawn_transform: Transform3D = Transform3D.IDENTITY
var has_respawn_point: bool = false
var _respawn_in: int = NOT_PENDING


func _ready() -> void:
	assert(config != null, "PlayerRest needs a RestConfig")
	body = get_parent() as PlayerController
	var parent: Node = get_parent()
	combatant = Combatant.find_on(parent)
	healing = parent.get_node_or_null(^"Healing") as PlayerHealing
	corruption = parent.get_node_or_null(^"CorruptionMeter") as CorruptionMeter
	lock_on = parent.get_node_or_null(^"LockOn") as LockOn
	camera_rig = parent.get_node_or_null(^"CameraRig") as ThirdPersonCamera
	if combatant != null:
		combatant.died.connect(_on_died)


func _physics_process(_delta: float) -> void:
	if _respawn_in == NOT_PENDING or HitStopService.is_frozen():
		return
	_respawn_in -= 1
	if _respawn_in <= 0:
		respawn()


## Rests at `shrine`: full restore, heals refilled, corruption reset, enemies respawned,
## and `spawn` (feet, facing -Z) becomes her respawn point.
func rest(shrine: Node3D, spawn: Transform3D) -> void:
	set_respawn_point(shrine, spawn)
	_restore()
	rested.emit(shrine)


## Makes `shrine` her respawn point without resting (a level's start shrine).
func set_respawn_point(shrine: Node3D, spawn: Transform3D) -> void:
	respawn_shrine = shrine
	respawn_transform = spawn
	has_respawn_point = true
	respawn_point_changed.emit(shrine)


## True if her death will be handled here (she has a respawn point).
func will_respawn() -> bool:
	return has_respawn_point


func is_respawn_pending() -> bool:
	return _respawn_in != NOT_PENDING


## Combat frames left until the pending respawn (NOT_PENDING if none).
func respawn_frames_left() -> int:
	return _respawn_in


## Puts her at the respawn point now, alive, facing its forward, lock released. With
## RestConfig.respawn_rests it is also a full rest. Does nothing without a respawn point.
func respawn() -> void:
	_respawn_in = NOT_PENDING
	if not has_respawn_point:
		return
	if lock_on != null:
		lock_on.unlock()
	if combatant != null and combatant.is_dead:
		combatant.revive()
	if body != null:
		body.global_position = respawn_transform.origin
		body.velocity = Vector3.ZERO
		var facing: Vector3 = -respawn_transform.basis.z
		facing.y = 0.0
		if facing.length_squared() > 0.0001:
			body.set_facing_direction(facing)
			if camera_rig != null:
				camera_rig.set_view_yaw(atan2(-facing.x, -facing.z))
		body.reset_physics_interpolation()
	if config.respawn_rests:
		_restore()
	elif combatant != null:
		combatant.restore()
	respawned.emit(respawn_shrine)


## Calls respawn() on every node in RESPAWN_GROUP. Returns how many respawned.
static func respawn_enemies(tree: SceneTree) -> int:
	var count: int = 0
	for node: Node in tree.get_nodes_in_group(RESPAWN_GROUP):
		if node.has_method(&"respawn"):
			node.call(&"respawn")
			count += 1
	return count


func _restore() -> void:
	if healing != null:
		healing.interrupt()
	if combatant != null:
		combatant.restore()
	if healing != null:
		healing.refill()
	if corruption != null and corruption.corruption != null:
		corruption.reset_at_shrine()
	if is_inside_tree():
		respawn_enemies(get_tree())


func _on_died() -> void:
	if has_respawn_point:
		_respawn_in = maxi(config.respawn_delay_frames, 1)
