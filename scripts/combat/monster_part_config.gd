class_name MonsterPartConfig
extends Resource
## Tuning for one body part of a large monster (docs/COMBAT_SPEC.md, "Large monsters").
## Each part has its own hurtbox multipliers and, if breakable, its own part posture bar.
## Breaking it staggers the whole monster, adds whole-body posture, makes the part take
## more damage, and can disable or weaken attacks. Frames are combat frames at 60 fps.

## Which part this is, e.g. &"head", &"left_forelimb". Also its hurtbox and lock-on part id.
@export var part_id: StringName = &"body"
## Its own posture bar. Leave empty for a part that can't break (the body).
@export var posture: PostureConfig

@export_group("Hurtbox")
## Health damage taken through this part = attack damage × this.
@export_range(0.0, 10.0, 0.05) var damage_multiplier: float = 1.0
## Whole-body posture damage taken through this part = attack posture damage × this.
@export_range(0.0, 10.0, 0.05) var posture_multiplier: float = 1.0
## Part posture gained per hit = the whole-body posture damage the hit dealt × this.
@export_range(0.0, 10.0, 0.05) var part_posture_multiplier: float = 2.0

@export_group("Lock-on")
## LockOnPoint.priority of this part (higher = preferred when landing on the monster).
@export_range(-10, 10, 1) var lock_priority: int = 0

@export_group("Break")
## Once broken, damage_multiplier is multiplied by this (a broken part is a weak point).
@export_range(1.0, 10.0, 0.05) var broken_damage_multiplier: float = 1.5
## Whole-body stagger when it breaks (no deathblow window), in combat frames.
@export_range(0, 600, 1, "suffix:frames") var break_stagger_frames: int = 120
## Whole-body posture damage dealt when it breaks (can break the whole body's posture).
@export_range(0.0, 1000.0, 0.5) var body_posture_on_break: float = 60.0
## Attack ids (AttackData.id) it can't use once this part is broken.
@export var disables_attacks: Array[StringName] = []
## Attack ids that get weaker once this part is broken…
@export var weakens_attacks: Array[StringName] = []
## …their damage and posture damage × this.
@export_range(0.0, 1.0, 0.05) var weakened_scale: float = 0.5


## True if it has a part posture bar and can break.
func is_breakable() -> bool:
	return posture != null
