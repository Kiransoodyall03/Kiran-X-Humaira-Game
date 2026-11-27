class_name HeroinePlaceholderAnims
extends RefCounted
## Builds the procedural placeholder AnimationLibrary for the capsule heroine: squash,
## lean, tilt and turn keys on Visual/BodyMesh, one clip per name in HeroineClips, so the
## AnimationTree visibly works before Humaira's rig exists. Saved as
## data/animation/heroine_placeholder_anims.tres. The real glb AnimationLibrary replaces
## it without code changes (docs/ANIMATION_CLIPS.md).
##
## Tracks are relative to the AnimationTree's root node (the Heroine body). Only BodyMesh
## is animated, never Visual (code turns Visual to face her movement) or the body itself.
## Poses pivot at her feet: lean = rotation about X (+ = forward), tilt = about Z
## (+ = to her right), turn = about Y.

const MESH_PATH: String = "Visual/BodyMesh"
## BodyMesh's rest position: the capsule's centre, 0.85 m above her feet.
const CENTER: Vector3 = Vector3(0.0, 0.85, 0.0)


## Builds the library: every clip in HeroineClips.all_clips(forms), plus RESET.
static func build(forms: Array[FormConfig], config: HeroineAnimConfig, heal: HealConfig,
		deathblow_frames: int) -> AnimationLibrary:
	var lib: AnimationLibrary = AnimationLibrary.new()
	lib.add_animation(&"RESET", _clip(1, [_k(0, Pose.new())]))

	# Locomotion loops: breathing, bob and forward lean growing with speed.
	lib.add_animation(HeroineClips.IDLE_CLIP, _loop(config.idle_loop_frames, [
		_k(0.0, Pose.new()), _k(0.5, Pose.new().squash(1.03)), _k(1.0, Pose.new())]))
	lib.add_animation(HeroineClips.WALK_CLIP, _gait(config.walk_loop_frames, 4.0, 3.0, 0.03))
	lib.add_animation(HeroineClips.RUN_CLIP, _gait(config.run_loop_frames, 10.0, 4.0, 0.05))
	lib.add_animation(HeroineClips.SPRINT_CLIP, _gait(config.sprint_loop_frames, 18.0, 5.0, 0.07))

	# Air.
	lib.add_animation(HeroineClips.JUMP_CLIP, _clip(config.jump_frames, [
		_k(0.0, Pose.new().squash(0.8)), _k(0.4, Pose.new().squash(1.15)), _k(1.0, Pose.new().squash(1.08))]))
	lib.add_animation(HeroineClips.FALL_CLIP, _loop(config.fall_loop_frames, [
		_k(0.0, Pose.new().squash(1.08).lean(-4.0)), _k(0.5, Pose.new().squash(1.1).lean(-6.0)),
		_k(1.0, Pose.new().squash(1.08).lean(-4.0))]))
	lib.add_animation(HeroineClips.LAND_CLIP, _clip(config.land_frames, [
		_k(0.0, Pose.new().squash(0.72)), _k(0.5, Pose.new().squash(0.9)), _k(1.0, Pose.new())]))

	# Guard: lean back, sideways stance.
	var guard: Pose = Pose.new().lean(-6.0).turn(-25.0).squash(0.95)
	lib.add_animation(HeroineClips.GUARD_CLIP, _loop(config.guard_loop_frames, [
		_k(0.0, guard), _k(0.5, guard.copy().squash(0.93)), _k(1.0, guard)]))
	lib.add_animation(HeroineClips.GUARD_HIT_CLIP, _clip(config.guard_hit_frames, [
		_k(0.0, guard), _k(0.25, guard.copy().lean(-16.0).squash(0.88)), _k(1.0, guard)]))
	lib.add_animation(HeroineClips.PARRY_CLIP, _clip(config.parry_frames, [
		_k(0.0, guard), _k(0.2, guard.copy().turn(55.0).lean(8.0)), _k(1.0, guard)]))

	# Attacks: wind up over startup, strike over active, settle over recovery.
	for form: FormConfig in forms:
		if form == null:
			continue
		var heavy: float = 1.0 if form.can_guard else 0.6 # greatsword swings bigger than katana
		for step: int in form.light_combo.size():
			var attack: AttackData = form.light_combo[step]
			if attack == null or lib.has_animation(HeroineClips.attack_clip(attack)):
				continue
			lib.add_animation(HeroineClips.attack_clip(attack), _attack(attack, step, heavy))

	# Dodge: lean into the dash direction, crouched.
	var dodge_frames: int = _dodge_frames(forms)
	lib.add_animation(HeroineClips.DODGE_FORWARD_CLIP, _dodge(dodge_frames, Pose.new().lean(25.0)))
	lib.add_animation(HeroineClips.DODGE_BACK_CLIP, _dodge(dodge_frames, Pose.new().lean(-25.0)))
	lib.add_animation(HeroineClips.DODGE_LEFT_CLIP, _dodge(dodge_frames, Pose.new().tilt(-25.0)))
	lib.add_animation(HeroineClips.DODGE_RIGHT_CLIP, _dodge(dodge_frames, Pose.new().tilt(25.0)))

	# Reactions.
	lib.add_animation(HeroineClips.HIT_REACT_CLIP, _clip(config.hit_react_frames, [
		_k(0.0, Pose.new()), _k(0.2, Pose.new().lean(-22.0).squash(0.92)), _k(1.0, Pose.new())]))
	var reel: Pose = Pose.new().lean(-12.0).squash(0.88)
	lib.add_animation(HeroineClips.STAGGER_CLIP, _loop(config.stagger_loop_frames, [
		_k(0.0, reel.copy().tilt(-9.0)), _k(0.5, reel.copy().tilt(9.0)), _k(1.0, reel.copy().tilt(-9.0))]))
	lib.add_animation(HeroineClips.DEATHBLOW_CLIP, _clip(deathblow_frames, [
		_k(0.0, Pose.new()), _k(0.3, Pose.new().lean(-10.0).turn(-40.0)), _k(0.45, Pose.new().lean(30.0).turn(10.0).squash(0.9)),
		_k(0.75, Pose.new().lean(30.0).turn(10.0).squash(0.9)), _k(1.0, Pose.new())]))
	var apply: float = clampf(float(heal.apply_frame) / float(maxi(heal.use_frames, 1)), 0.1, 0.9)
	lib.add_animation(HeroineClips.HEAL_CLIP, _clip(heal.use_frames, [
		_k(0.0, Pose.new()), _k(apply * 0.7, Pose.new().squash(0.85).lean(10.0)), _k(apply, Pose.new().squash(1.12)),
		_k(1.0, Pose.new())]))
	lib.add_animation(HeroineClips.REST_CLIP, _clip(config.rest_frames, [
		_k(0.0, Pose.new()), _k(0.25, Pose.new().squash(0.6).lean(8.0)), _k(0.75, Pose.new().squash(0.6).lean(8.0)),
		_k(1.0, Pose.new())]))
	lib.add_animation(HeroineClips.DEATH_CLIP, _clip(config.death_frames, [
		_k(0.0, Pose.new()), _k(0.3, Pose.new().lean(-20.0).squash(0.9)), _k(0.8, Pose.new().lean(-85.0)),
		_k(1.0, Pose.new().lean(-85.0))]))
	return lib


## The dodge length of the first form that can dodge (18 frames by default).
static func _dodge_frames(forms: Array[FormConfig]) -> int:
	for form: FormConfig in forms:
		if form != null and form.can_dodge:
			return form.dodge_duration_frames
	return 18


static func _attack(attack: AttackData, step: int, heavy: float) -> Animation:
	var total: float = float(maxi(attack.total_frames(), 1))
	var wound: float = float(attack.startup_frames) / total
	var struck: float = float(attack.startup_frames + attack.active_frames) / total
	var side: float = -1.0 if step % 2 == 0 else 1.0 # alternate swing sides through the combo
	var size: float = heavy * (1.0 + 0.35 * float(step))
	var windup: Pose = Pose.new().lean(-10.0 * size).turn(35.0 * side * size).squash(0.95)
	var strike: Pose = Pose.new().lean(18.0 * size).turn(-35.0 * side * size).squash(1.04)
	return _clip(attack.total_frames(), [
		_k(0.0, Pose.new()), _k(wound, windup), _k(struck, strike),
		_k(struck + (1.0 - struck) * 0.4, strike.copy().lean(-6.0 * size)), _k(1.0, Pose.new())])


static func _dodge(frames: int, dash: Pose) -> Animation:
	return _clip(frames, [_k(0.0, Pose.new()), _k(0.15, dash.copy().squash(0.82)), _k(0.7, dash.copy().squash(0.85)),
		_k(1.0, Pose.new())])


static func _gait(frames: int, lean_deg: float, tilt_deg: float, bob: float) -> Animation:
	var base: Pose = Pose.new().lean(lean_deg)
	return _loop(frames, [
		_k(0.0, base.copy().tilt(-tilt_deg)), _k(0.25, base.copy().rise(bob)), _k(0.5, base.copy().tilt(tilt_deg)),
		_k(0.75, base.copy().rise(bob)), _k(1.0, base.copy().tilt(-tilt_deg))])


static func _loop(frames: int, keys: Array[Array]) -> Animation:
	var anim: Animation = _clip(frames, keys)
	anim.loop_mode = Animation.LOOP_LINEAR
	return anim


## A clip `frames` long; `keys` are [time 0–1, Pose] pairs.
static func _clip(frames: int, keys: Array[Array]) -> Animation:
	var anim: Animation = Animation.new()
	anim.length = HeroineAnimConfig.seconds(maxi(frames, 1))
	anim.step = 1.0 / 60.0
	var pos: int = anim.add_track(Animation.TYPE_POSITION_3D)
	var rot: int = anim.add_track(Animation.TYPE_ROTATION_3D)
	var scl: int = anim.add_track(Animation.TYPE_SCALE_3D)
	for track: int in [pos, rot, scl]:
		anim.track_set_path(track, NodePath(MESH_PATH))
		anim.track_set_interpolation_type(track, Animation.INTERPOLATION_CUBIC)
	for key: Array in keys:
		var t: float = clampf(key[0] as float, 0.0, 1.0) * anim.length
		var pose: Pose = key[1] as Pose
		anim.position_track_insert_key(pos, t, pose.position())
		anim.rotation_track_insert_key(rot, t, pose.basis().get_rotation_quaternion())
		anim.scale_track_insert_key(scl, t, pose.scale())
	return anim


static func _k(t: float, pose: Pose) -> Array:
	return [t, pose]


## A capsule pose: lean / tilt / turn in degrees, squash (height factor; width keeps the
## volume), rise in meters. The rotation pivots at her feet.
class Pose:
	extends RefCounted
	var lean_deg: float = 0.0
	var tilt_deg: float = 0.0
	var turn_deg: float = 0.0
	var squash_y: float = 1.0
	var rise_m: float = 0.0

	func lean(deg: float) -> Pose:
		lean_deg += deg
		return self

	func tilt(deg: float) -> Pose:
		tilt_deg += deg
		return self

	func turn(deg: float) -> Pose:
		turn_deg += deg
		return self

	func squash(factor: float) -> Pose:
		squash_y *= factor
		return self

	func rise(meters: float) -> Pose:
		rise_m += meters
		return self

	func copy() -> Pose:
		var p: Pose = Pose.new()
		p.lean_deg = lean_deg
		p.tilt_deg = tilt_deg
		p.turn_deg = turn_deg
		p.squash_y = squash_y
		p.rise_m = rise_m
		return p

	func basis() -> Basis:
		# She faces +Z, so her right is -X. Lean forward (top toward +Z) = + rotation about X;
		# tilt right (top toward -X) = + rotation about Z.
		return Basis.from_euler(Vector3(deg_to_rad(lean_deg), deg_to_rad(turn_deg), deg_to_rad(tilt_deg)))

	func scale() -> Vector3:
		var width: float = 1.0 / sqrt(maxf(squash_y, 0.05))
		return Vector3(width, squash_y, width)

	func position() -> Vector3:
		# Pivot at the feet: the centre sits CENTER.y × squash up the leaned axis.
		return basis() * (CENTER * squash_y) + Vector3.UP * rise_m
