class_name RestConfig
extends Resource
## Shrine rest and respawn tuning (docs/COMBAT_SPEC.md "Shrines: rest and respawn").
## Tuning file: data/world/shrine.tres. Frames are at 60 fps.

## Frames from her death to the respawn at the last shrine she rested at.
@export_range(0, 1200, 1, "suffix:frames") var respawn_delay_frames: int = 150
## A respawn also counts as a rest: heals refilled, corruption reset, enemies respawned.
## (Health and posture are always full after a respawn.)
@export var respawn_rests: bool = true

@export_group("Resting")
## No resting while a living hostile (a Combatant body in the "hostile" group) is this
## close to the shrine (ground plane). 0 = never blocked.
@export_range(0.0, 100.0, 0.5, "suffix:m") var hostile_block_radius: float = 8.0
