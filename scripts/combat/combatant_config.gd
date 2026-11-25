class_name CombatantConfig
extends Resource
## Everything a Combatant needs: health plus its posture and guard tuning.

@export_range(1.0, 10000.0, 1.0) var max_health: float = 100.0
@export var posture: PostureConfig
@export var guard: GuardConfig
