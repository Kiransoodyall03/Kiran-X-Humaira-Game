class_name HeroineAnimConfig
extends Resource
## Visual-only tuning for the heroine's AnimationTree (docs/ANIMATION_CLIPS.md). Nothing
## here changes gameplay: the gameplay timings (attack frames, dodge, heal, deathblow) come
## from their own data files and the clips are stretched to them. Frames are at 60 fps.
## Tuning file: data/animation/heroine_anim.tres.

@export_group("Locomotion blend (m/s)")
## Blend position of the walk clip in the locomotion BlendSpace1D (ground speed, m/s).
@export_range(0.1, 20.0, 0.1, "suffix:m/s") var walk_blend_speed: float = 1.5
## Blend position of the run clip (her normal top speed, PlayerMovementConfig.walk_speed).
@export_range(0.1, 20.0, 0.1, "suffix:m/s") var run_blend_speed: float = 4.5
## Blend position of the sprint clip (PlayerMovementConfig.sprint_speed).
@export_range(0.1, 30.0, 0.1, "suffix:m/s") var sprint_blend_speed: float = 7.5

@export_group("Air")
## Rising faster than this (m/s) shows the jump clip; slower or falling shows fall.
@export_range(0.0, 20.0, 0.1, "suffix:m/s") var jump_min_rise_speed: float = 0.5
## A landing after falling at least this fast (m/s) plays the land clip.
@export_range(0.0, 50.0, 0.1, "suffix:m/s") var land_min_fall_speed: float = 3.0
@export_range(1, 120, 1, "suffix:frames") var land_frames: int = 10

@export_group("Reactions")
## Clip lengths of the event reactions. They hold their state for exactly this long
## unless a higher-priority state (death, stagger, deathblow, dodge, attack, heal) takes over.
@export_range(1, 120, 1, "suffix:frames") var hit_react_frames: int = 18
@export_range(1, 120, 1, "suffix:frames") var guard_hit_frames: int = 12
@export_range(1, 120, 1, "suffix:frames") var parry_frames: int = 14
@export_range(1, 600, 1, "suffix:frames") var rest_frames: int = 90
@export_range(1, 600, 1, "suffix:frames") var death_frames: int = 60
## Moving faster than this (m/s) cuts the soft one-shots (land, rest) short.
@export_range(0.0, 10.0, 0.05, "suffix:m/s") var soft_cancel_speed: float = 0.6

@export_group("Cross-fades")
## Cross-fade into and out of the looping states (locomotion, guard, fall, stagger).
@export_range(0, 60, 1, "suffix:frames") var loop_xfade_frames: int = 8
## Cross-fade into one-shots (attacks, dodge, reactions). Short, so the pose reads at once.
@export_range(0, 60, 1, "suffix:frames") var action_xfade_frames: int = 3

@export_group("Placeholder clips")
## Loop lengths of the procedural placeholder clips (not used by real clips).
@export_range(1, 600, 1, "suffix:frames") var idle_loop_frames: int = 120
@export_range(1, 600, 1, "suffix:frames") var walk_loop_frames: int = 40
@export_range(1, 600, 1, "suffix:frames") var run_loop_frames: int = 30
@export_range(1, 600, 1, "suffix:frames") var sprint_loop_frames: int = 24
@export_range(1, 600, 1, "suffix:frames") var jump_frames: int = 12
@export_range(1, 600, 1, "suffix:frames") var fall_loop_frames: int = 30
@export_range(1, 600, 1, "suffix:frames") var guard_loop_frames: int = 60
@export_range(1, 600, 1, "suffix:frames") var stagger_loop_frames: int = 60


static func seconds(frames: int) -> float:
	return float(frames) / 60.0
