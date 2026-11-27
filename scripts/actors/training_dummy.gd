class_name TrainingDummy
extends CharacterBody3D
## Sandbox sparring dummy for practising block and parry before the real duelist AI.
## It turns to face the player and cycles through its attack list. Each attack has a
## visible tell: the body flashes the attack's tell colour during startup.
## Hits use a simple reach + facing check (real hitboxes come with the duelist).
## The heroine's attacks land on its Hurtbox. It has no guard AI, so every hit lands.
## A posture break (or 0 health, since its config requires a deathblow) staggers it and
## opens a deathblow; a deathblow with lives left gets it back up for the next life, the
## last one makes it go dark until revived (SandboxRules does that).
## Resting at a shrine respawns it (group "respawn_on_rest"): back at its start position,
## revived with all lives, attack list from the top.
##
## Expected children: Visual/BodyMesh (MeshInstance3D), CollisionShape3D, Combatant, Hurtbox

enum Phase { IDLE, STARTUP, ACTIVE, RECOVERY, STAGGERED, DEAD }

signal phase_changed(phase: Phase, attack: AttackData)

## Attacks in the order the dummy uses them; it loops.
@export var attacks: Array[AttackData] = []
## Frames to wait between attacks.
@export_range(0, 600, 1, "suffix:frames") var idle_frames: int = 45
## Only attacks while the target is closer than this, in meters.
@export_range(0.0, 50.0, 0.5, "suffix:m") var engage_distance: float = 6.0
## How fast it turns toward the target (it stops turning once a swing is active).
@export_range(0.0, 2000.0, 10.0, "suffix:°/s") var turn_speed_degrees: float = 240.0
## A hit only lands if the target is within this angle of where the dummy faces.
@export_range(0.0, 180.0, 1.0, "suffix:°") var hit_half_angle_degrees: float = 60.0
@export var attacking_enabled: bool = true
## What it fights. If unset, it uses the first node in the "player" group.
@export var target: Node3D

@onready var _combatant: Combatant = $Combatant
@onready var _body_mesh: MeshInstance3D = $Visual/BodyMesh
@onready var _visual: Node3D = $Visual

var phase: Phase = Phase.IDLE
var current_attack: AttackData
var _frames_in_phase: int = 0
var _attack_index: int = 0
var _hit_landed: bool = false
var _material: StandardMaterial3D
var _base_color: Color = Color(0.55, 0.5, 0.48)
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity") as float
## Where it stands at level start; respawn() puts it back here.
var home: Vector3


func _ready() -> void:
	add_to_group(CorruptionMeter.HOSTILE_GROUP) # counts as "in combat" for her corruption
	add_to_group(PlayerRest.RESPAWN_GROUP) # a shrine rest respawns it
	home = global_position
	var source: Material = _body_mesh.get_active_material(0)
	_material = (source.duplicate() as StandardMaterial3D) if source is StandardMaterial3D else StandardMaterial3D.new()
	_base_color = _material.albedo_color
	_body_mesh.material_override = _material
	_combatant.posture_broken.connect(_on_posture_broken)
	_combatant.stagger_ended.connect(_on_stagger_ended)
	_combatant.died.connect(_on_died)
	_combatant.revived.connect(_on_revived)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = 0.0
	move_and_slide()
	if target == null:
		target = get_tree().get_first_node_in_group(&"player") as Node3D
	if HitStopService.is_frozen():
		return # hit-stop: phases are counted in combat frames
	if phase == Phase.IDLE or phase == Phase.STARTUP:
		_turn_toward_target(delta)
	_step_phase()


## The direction the dummy faces (its Visual's +Z), on the ground plane.
func get_forward() -> Vector3:
	var f: Vector3 = _visual.global_basis.z
	f.y = 0.0
	return f.normalized()


func get_combatant() -> Combatant:
	return _combatant


## Shrine rest: back at home, revived (full health, all lives, empty posture), idle, and
## its attack list starts over.
func respawn() -> void:
	global_position = home
	velocity = Vector3.ZERO
	reset_physics_interpolation()
	_attack_index = 0
	_hit_landed = false
	_combatant.revive() # -> _on_revived: base colour, IDLE


func _step_phase() -> void:
	_frames_in_phase += 1
	match phase:
		Phase.IDLE:
			if attacking_enabled and not attacks.is_empty() and _frames_in_phase >= idle_frames and _target_in_range(engage_distance):
				current_attack = attacks[_attack_index % attacks.size()]
				_attack_index += 1
				_enter(Phase.STARTUP)
		Phase.STARTUP:
			var t: float = float(_frames_in_phase) / float(maxi(current_attack.startup_frames, 1))
			_material.albedo_color = _base_color.lerp(current_attack.tell_color, clampf(t, 0.0, 1.0))
			if _frames_in_phase >= current_attack.startup_frames:
				_hit_landed = false
				_enter(Phase.ACTIVE)
				_try_hit() # the first active frame can hit
		Phase.ACTIVE:
			_try_hit()
			if _frames_in_phase >= current_attack.active_frames:
				_material.albedo_color = _base_color
				_enter(Phase.RECOVERY)
		Phase.RECOVERY:
			if _frames_in_phase >= current_attack.recovery_frames:
				_enter(Phase.IDLE)
		Phase.STAGGERED:
			pass # left by stagger_ended
		Phase.DEAD:
			pass # left by revived


func _enter(new_phase: Phase) -> void:
	phase = new_phase
	_frames_in_phase = 0
	phase_changed.emit(phase, current_attack)


func _try_hit() -> void:
	if _hit_landed or target == null:
		return
	var defender: Combatant = Combatant.find_on(target)
	if defender == null or not _target_in_reach(current_attack.reach):
		return
	if current_attack.misses_airborne and target is CharacterBody3D and not (target as CharacterBody3D).is_on_floor():
		return # jumped over it — keep checking for the rest of the active frames
	_hit_landed = true
	defender.receive_attack(current_attack, _combatant)


func _target_in_range(distance: float) -> bool:
	if target == null:
		return false
	var defender: Combatant = Combatant.find_on(target)
	if defender != null and defender.is_dead:
		return false # don't keep swinging at a defeated player
	return _flat_offset_to_target().length() <= distance


func _target_in_reach(reach: float) -> bool:
	var offset: Vector3 = _flat_offset_to_target()
	if offset.length() > reach:
		return false
	if offset.length_squared() < 0.0001:
		return true
	return get_forward().angle_to(offset.normalized()) <= deg_to_rad(hit_half_angle_degrees)


func _flat_offset_to_target() -> Vector3:
	var offset: Vector3 = target.global_position - global_position
	offset.y = 0.0
	return offset


func _turn_toward_target(delta: float) -> void:
	if target == null:
		return
	var offset: Vector3 = _flat_offset_to_target()
	if offset.length_squared() < 0.0001:
		return
	var target_yaw: float = atan2(offset.x, offset.z)
	_visual.global_rotation.y = rotate_toward(_visual.global_rotation.y, target_yaw, deg_to_rad(turn_speed_degrees) * delta)


func _on_posture_broken() -> void:
	if phase == Phase.DEAD:
		return
	_material.albedo_color = Color(0.35, 0.55, 0.95)
	_enter(Phase.STAGGERED)


func _on_stagger_ended() -> void:
	if phase == Phase.DEAD:
		return
	_material.albedo_color = _base_color
	_enter(Phase.IDLE)


func _on_died() -> void:
	_material.albedo_color = Color(0.18, 0.17, 0.17)
	_enter(Phase.DEAD)


func _on_revived() -> void:
	_material.albedo_color = _base_color
	_enter(Phase.IDLE)
