class_name PostureConfig
extends Resource
## Posture tuning (docs/COMBAT_SPEC.md). Posture only, no stamina: it fills from blocked,
## parried and unguarded hits. Full posture = broken = staggered. All timings are frames at 60 fps.

## Posture value at which it breaks.
@export_range(1.0, 1000.0, 1.0) var max_posture: float = 100.0
## Posture recovered per second once recovery has started.
@export_range(0.0, 500.0, 0.5, "suffix:/s") var regen_per_second: float = 20.0
## Frames after the last posture damage before recovery starts.
@export_range(0, 600, 1, "suffix:frames") var regen_delay_frames: int = 45
## Recovery multiplier while guarding (guarding recovers posture faster, as in Sekiro).
@export_range(0.0, 5.0, 0.05) var guard_regen_multiplier: float = 1.5
## Recovery multiplier at 0 health. Scales linearly up to 1.0 at full health.
@export_range(0.0, 1.0, 0.05) var low_health_regen_multiplier: float = 0.3
## Frames spent staggered after posture breaks.
@export_range(0, 600, 1, "suffix:frames") var break_stagger_frames: int = 90
## Empty posture when the stagger ends. If off, posture keeps its value.
@export var reset_after_break: bool = true
