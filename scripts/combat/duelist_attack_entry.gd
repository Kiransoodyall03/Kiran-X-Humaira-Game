class_name DuelistAttackEntry
extends Resource
## One row of the duelist's attack table: the attack (AttackData: frames, damage, tell)
## plus the AI rules for when it may be chosen (docs/COMBAT_SPEC.md, "Duelist").
## Selection rules live in DuelistBrain and are unit-tested.

@export var attack: AttackData
## Chosen only while the target is at least this far away (ground plane), in meters.
@export_range(0.0, 20.0, 0.05, "suffix:m") var min_range: float = 0.0
## …and at most this far. Include the attack's lunge: reach + lunge_distance is a fair max.
@export_range(0.0, 20.0, 0.05, "suffix:m") var max_range: float = 2.5
## After it starts, this attack can't be chosen again for this many combat frames.
@export_range(0, 1800, 1, "suffix:frames") var cooldown_frames: int = 60
## Relative chance among the attacks valid at the moment. 0 = never chosen.
@export_range(0.0, 100.0, 0.1) var weight: float = 1.0


## Pass as last_used_frame for an attack that was never used.
const NEVER: int = -1_000_000


## True if the attack may be chosen at `distance` on `frame`, given the combat frame it
## was last started on (NEVER if it never was).
func is_available(distance: float, frame: int, last_used_frame: int) -> bool:
	if attack == null or weight <= 0.0:
		return false
	if distance < min_range or distance > max_range:
		return false
	return is_off_cooldown(frame, last_used_frame)


func is_off_cooldown(frame: int, last_used_frame: int) -> bool:
	return frame - last_used_frame >= cooldown_frames
