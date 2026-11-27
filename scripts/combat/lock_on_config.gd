class_name LockOnConfig
extends Resource
## Tuning for the heroine's lock-on: which points can be picked, when the lock breaks,
## how cycling is triggered, and how the camera tracks and frames the target.
## Edit data/combat/lock_on.tres to tune live. Frames are at 60 fps (combat frames:
## paused during hit-stop).

@export_group("Acquire")
## A point must be this close to the heroine to be picked, in meters.
@export_range(1.0, 100.0, 0.5, "suffix:m") var acquire_range: float = 20.0
## …and within this angle of the camera's view centre, in degrees.
@export_range(1.0, 180.0, 1.0, "suffix:°") var acquire_max_angle_degrees: float = 55.0
## Cycling to another target allows a wider angle than the first pick.
@export_range(1.0, 180.0, 1.0, "suffix:°") var cycle_max_angle_degrees: float = 80.0
## Score weight for distance from the screen centre (angle / acquire_max_angle).
@export_range(0.0, 10.0, 0.05) var screen_weight: float = 1.0
## Score weight for distance from the heroine (distance / acquire_range).
@export_range(0.0, 10.0, 0.05) var distance_weight: float = 0.35
## Score bonus per point of LockOnPoint.priority.
@export_range(0.0, 10.0, 0.05) var priority_weight: float = 0.15
## Physics layers that block line of sight (the world, not characters).
@export_flags_3d_physics var line_of_sight_mask: int = 1
## Height above the heroine's feet the line of sight is checked from, in meters.
@export_range(0.0, 5.0, 0.05, "suffix:m") var eye_height: float = 1.5

@export_group("Break")
## The lock breaks when the point is further than this, in meters.
@export_range(1.0, 200.0, 0.5, "suffix:m") var break_range: float = 25.0
## …or when line of sight has been blocked this many combat frames in a row (it breaks
## on the Nth blocked frame; hit-stop frames don't count).
@export_range(0, 600, 1, "suffix:frames") var lost_sight_frames: int = 45

@export_group("Cycle")
## Right-stick deflection (0–1) that counts as a flick to switch target.
@export_range(0.1, 1.0, 0.05) var flick_threshold: float = 0.7
## The stick has to come back under this before the next flick counts.
@export_range(0.0, 1.0, 0.05) var flick_reset: float = 0.3
## Horizontal mouse motion within one flick that switches target, in pixels. 0 = off.
@export_range(0.0, 2000.0, 10.0, "suffix:px") var mouse_flick_pixels: float = 220.0
## How fast accumulated mouse motion fades, per second (so slow drift never switches).
@export_range(0.0, 60.0, 0.5) var mouse_flick_decay: float = 12.0

@export_group("Camera")
## How fast the camera yaw turns to the target. Higher = snappier. Frame-rate independent.
@export_range(0.0, 60.0, 0.5) var yaw_sharpness: float = 10.0
## Closer than this on the ground plane (target nearly overhead, e.g. a big monster's head)
## the camera holds its yaw instead of spinning round as she passes under the target.
@export_range(0.0, 5.0, 0.05, "suffix:m") var hold_yaw_within: float = 1.2
## How fast the camera pitch follows.
@export_range(0.0, 60.0, 0.5) var pitch_sharpness: float = 6.0
## Added to the pitch that points straight at the target, in degrees. Negative = look down
## on the target a little, keeping the heroine in frame.
@export_range(-60.0, 60.0, 1.0, "suffix:°") var pitch_offset_degrees: float = -12.0
## Pitch limits while locked, in degrees (negative = camera above, looking down).
@export_range(-89.0, 0.0, 1.0, "suffix:°") var min_pitch_degrees: float = -45.0
@export_range(0.0, 89.0, 1.0, "suffix:°") var max_pitch_degrees: float = 35.0
## Targets up to this size (meters) get no extra camera distance.
@export_range(0.0, 50.0, 0.1, "suffix:m") var framing_base_size: float = 2.5
## Extra camera distance per meter of target_size above framing_base_size.
@export_range(0.0, 5.0, 0.05) var pullback_per_meter: float = 0.8
## Never pull back more than this, in meters.
@export_range(0.0, 30.0, 0.1, "suffix:m") var max_pullback: float = 6.0
## How fast the camera distance eases to its framing distance.
@export_range(0.0, 60.0, 0.5) var distance_sharpness: float = 4.0

@export_group("Heroine")
## How fast she turns to face the target while locked, in degrees per second.
@export_range(0.0, 3600.0, 10.0, "suffix:°/s") var face_turn_speed_degrees: float = 900.0
## Sprinting while locked faces the run direction instead of the target (Sekiro-style).
@export var sprint_faces_movement: bool = true


## Extra camera distance for a target of `size` meters.
func pullback_for(size: float) -> float:
	return clampf((size - framing_base_size) * pullback_per_meter, 0.0, max_pullback)
