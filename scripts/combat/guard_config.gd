class_name GuardConfig
extends Resource
## Block and parry tuning (docs/COMBAT_SPEC.md). All timings are frames at 60 fps.

@export_group("Parry")
## A hit counts as a parry if guard was pressed at most this many frames before it landed.
## Start generous (10–12) and tighten after playtests.
@export_range(1, 60, 1, "suffix:frames") var parry_window_frames: int = 12
## Pressing guard again within this many frames of the last press counts as mashing.
@export_range(0, 120, 1, "suffix:frames") var mash_frames: int = 20
## Each mashed press shrinks the parry window by this many frames…
@export_range(0, 30, 1, "suffix:frames") var mash_penalty_frames: int = 4
## …but never below this.
@export_range(1, 60, 1, "suffix:frames") var min_parry_window_frames: int = 4
## Share of the attack's posture damage the parrier still takes.
@export_range(0.0, 2.0, 0.05) var parry_self_posture_multiplier: float = 0.25
## Share of the attack's posture damage dealt back to the attacker.
@export_range(0.0, 5.0, 0.05) var parry_attacker_posture_multiplier: float = 1.0
## If off, a parry can fill your posture to just below max but never break it (Sekiro rule).
@export var parry_can_break_posture: bool = false

@export_group("Block")
## Share of the attack's posture damage taken when blocking.
@export_range(0.0, 5.0, 0.05) var block_posture_multiplier: float = 1.0
## Share of the attack's health damage that gets through a block ("chip").
@export_range(0.0, 1.0, 0.05) var block_health_multiplier: float = 0.0

@export_group("Unguarded")
## Share of the attack's posture damage taken when hit without guarding.
@export_range(0.0, 2.0, 0.05) var hit_posture_multiplier: float = 0.5
