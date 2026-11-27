class_name CombatantConfig
extends Resource
## Everything a Combatant needs: health plus its posture and guard tuning, and its
## deathblow rules (docs/COMBAT_SPEC.md, "Deathblow and lives").

@export_range(1.0, 10000.0, 1.0) var max_health: float = 100.0
@export var posture: PostureConfig
@export var guard: GuardConfig

@export_group("Deathblow")
## Lives (phases). Each deathblow takes one; at 0 it dies. With lives left it gets up
## with full health and empty posture for the next phase. Bosses can have 2 or more.
@export_range(1, 9, 1) var lives: int = 1
## A posture break (or 0 health with requires_deathblow) opens a deathblow window. Off
## for the heroine: enemies don't deathblow her.
@export var can_be_deathblown: bool = false
## At 0 health it doesn't die: it stays staggered until a deathblow lands (Sekiro rule).
## Needs can_be_deathblown. Off: 0 health kills outright, whatever lives are left.
@export var requires_deathblow: bool = false
