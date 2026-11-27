class_name HealConfig
extends Resource
## Healing charges tuning (docs/COMBAT_SPEC.md "Healing charges"). Tuning file:
## data/combat/heals.tres. Frames are at 60 fps.

## Charges she carries. A shrine rest (or a shrine respawn) refills them all.
@export_range(0, 20, 1) var max_charges: int = 3
## Health one charge restores (clamped to max health).
@export_range(0.0, 1000.0, 1.0) var heal_amount: float = 40.0

@export_group("Timing")
## Frames the heal takes from the press to getting control back. No attacks, dodges,
## guard, form switches or jumps until it ends; she can still walk slowly.
@export_range(1, 600, 1, "suffix:frames") var use_frames: int = 54
## Frames after the press when the health comes back and the charge is spent. Must be
## at most use_frames.
@export_range(1, 600, 1, "suffix:frames") var apply_frame: int = 30
## Walk speed while healing, as a fraction of normal (no sprint).
@export_range(0.0, 1.0, 0.05) var move_speed_multiplier: float = 0.35

@export_group("Rules")
## A hit that lands (outcome HIT or GUARD_BROKEN) cancels the heal. Before apply_frame
## that means no health and the charge is kept; after it, only the rest of the
## recovery is cancelled. A posture break or death always cancels it.
@export var interrupted_by_hits: bool = true
## Off: the heal button does nothing at full health (so a charge can't be wasted).
@export var allow_at_full_health: bool = false
