class_name CorruptionConfig
extends Resource
## Corruption meter tuning (docs/COMBAT_SPEC.md "Corruption v0"). Tuning file:
## data/combat/corruption.tres. The per-form rates (rise in katana, drain in greatsword,
## out-of-combat multiplier) live on each FormConfig in data/forms/*.tres.
## Frames are at 60 fps.

## The meter runs 0 to this.
@export_range(1.0, 1000.0, 1.0) var max_corruption: float = 100.0

@export_group("In combat")
## A living Combatant in the "hostile" group within this distance (ground plane) of her
## means she is in combat.
@export_range(0.0, 100.0, 0.5, "suffix:m") var combat_radius: float = 12.0
## She stays in combat for this many frames after dealing or taking an attack (or a
## deathblow), even with no hostile in range.
@export_range(0, 3600, 1, "suffix:frames") var combat_linger_frames: int = 300

@export_group("Thresholds")
## threshold_reached fires when the meter rises to each of these; threshold_dropped when
## it falls back below. In ascending order.
@export var thresholds: Array[float] = [50.0, 75.0, 100.0]

@export_group("Input hijack (stub)")
## No hijack below this much corruption.
@export_range(0.0, 1000.0, 1.0) var hijack_start: float = 50.0
## Chance per should_hijack_input() check at full corruption.
@export_range(0.0, 1.0, 0.01) var hijack_chance_at_max: float = 0.25
## Shape of the rise from hijack_start to full: 1 = linear, 2 = slow then steep.
@export_range(0.1, 8.0, 0.1) var hijack_curve_exponent: float = 2.0

@export_group("Rampage")
## Reaching full corruption starts a rampage. It ends when the meter drains to this…
@export_range(0.0, 1000.0, 1.0) var rampage_exit_corruption: float = 50.0
## …or when her health falls to this fraction of max or lower (critical health).
@export_range(0.0, 1.0, 0.01) var rampage_exit_health_ratio: float = 0.25
## No katana dodge during a rampage.
@export var rampage_locks_dodge: bool = true
