class_name MonsterAttackEntry
extends Resource
## One row of a large monster's attack table: the attack (AttackData: frames, damage, tell)
## plus the AI rules for when it may be chosen — where the target stands relative to the
## body (front / side / rear) and how far — and the box it hits (docs/COMBAT_SPEC.md,
## "Large monsters"). Selection rules live in MonsterBrain and are unit-tested.

## Pass as last_used_frame for an attack that was never used.
const NEVER: int = -1_000_000

@export var attack: AttackData

@export_group("When")
## Chosen while the target is in front of the body (MonsterBrain.Zone.FRONT)…
@export var from_front: bool = true
## …beside it (SIDE)…
@export var from_side: bool = false
## …behind it (REAR).
@export var from_rear: bool = false
## Chosen only while the target is at least this far from the monster's origin (ground
## plane), in meters…
@export_range(0.0, 50.0, 0.05, "suffix:m") var min_range: float = 0.0
## …and at most this far.
@export_range(0.0, 50.0, 0.05, "suffix:m") var max_range: float = 8.0
## After it starts, it can't be chosen again for this many combat frames.
@export_range(0, 3600, 1, "suffix:frames") var cooldown_frames: int = 120
## Relative chance among the attacks valid at the moment. 0 = never chosen.
@export_range(0.0, 100.0, 0.1) var weight: float = 1.0

@export_group("Hit")
## Centre of the hit box in the monster's own frame (z = forward, y = up), in meters. It is
## queried every active frame and moves with any lunge.
@export var hit_center: Vector3 = Vector3(0.0, 1.0, 4.0)
## Size of the hit box, in meters.
@export var hit_size: Vector3 = Vector3(5.0, 2.0, 4.0)
## Keeps turning toward the target during the wind-up (front attacks). Off for attacks
## aimed round the body (tail sweep, stomp), which would otherwise turn away from her.
@export var tracks_target: bool = true


## True if the row covers `zone` (a MonsterBrain.Zone value: 0 front, 1 side, 2 rear).
func covers_zone(zone: int) -> bool:
	match zone:
		0:
			return from_front
		1:
			return from_side
		2:
			return from_rear
	return false


## True if the attack may be chosen with the target in `zone` at `distance` on `frame`,
## given the combat frame it was last started on (NEVER if it never was).
func is_available(zone: int, distance: float, frame: int, last_used_frame: int) -> bool:
	if attack == null or weight <= 0.0 or not covers_zone(zone):
		return false
	if distance < min_range or distance > max_range:
		return false
	return frame - last_used_frame >= cooldown_frames
