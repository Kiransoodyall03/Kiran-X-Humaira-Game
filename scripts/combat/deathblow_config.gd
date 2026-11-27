class_name DeathblowConfig
extends Resource
## The heroine's deathblow (docs/COMBAT_SPEC.md, "Deathblow and lives"). Attack pressed
## while an enemy's deathblow window is open, within reach and roughly in front of her,
## does a deathblow instead of a swing. It lands on the press frame; she is then locked
## (and optionally invulnerable) for recovery_frames. Frames are at 60 fps.

## Farthest the target's origin may be from hers, on the ground plane, in meters.
@export_range(0.5, 10.0, 0.05, "suffix:m") var reach: float = 2.6
## The target must be within this angle of where she faces ("roughly facing").
@export_range(0.0, 180.0, 1.0, "suffix:°") var facing_half_angle_degrees: float = 75.0
## Frames after the deathblow before she can act again.
@export_range(0, 300, 1, "suffix:frames") var recovery_frames: int = 50
## Hits on her during those frames come back DODGED (Sekiro-style safe finisher).
@export var invulnerable: bool = true
