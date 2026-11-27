class_name HitStopConfig
extends Resource
## Hit-stop tuning (docs/COMBAT_SPEC.md). Durations are in real milliseconds: the freeze
## is timed with a timer that ignores Engine.time_scale. 0 ms turns that event off.

## Master switch.
@export var enabled: bool = true
## Engine.time_scale during the freeze. Combat frame counters stop completely whatever
## this is; it only decides how much bodies, the camera and effects still drift.
@export_range(0.0, 1.0, 0.01) var time_scale: float = 0.05
## The heroine (or anyone) parries an attack.
@export_range(0, 1000, 1, "suffix:ms") var parry_ms: int = 90
## One of the heroine's swings connects (hit, block or guard break).
@export_range(0, 1000, 1, "suffix:ms") var hit_ms: int = 50
## Any combatant's posture breaks (or an enemy runs out of health and waits for a deathblow).
@export_range(0, 1000, 1, "suffix:ms") var posture_break_ms: int = 150
## A deathblow lands.
@export_range(0, 1000, 1, "suffix:ms") var deathblow_ms: int = 250


## Duration in milliseconds for an event kind.
func duration_ms(kind: HitStopService.Kind) -> int:
	match kind:
		HitStopService.Kind.PARRY:
			return parry_ms
		HitStopService.Kind.HIT:
			return hit_ms
		HitStopService.Kind.POSTURE_BREAK:
			return posture_break_ms
		HitStopService.Kind.DEATHBLOW:
			return deathblow_ms
	return 0
