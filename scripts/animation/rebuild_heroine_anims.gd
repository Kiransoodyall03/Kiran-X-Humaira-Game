extends SceneTree
## Rebuilds the heroine's saved animation resources from her current data:
##   data/animation/heroine_anim_tree.tres         (AnimationTree state machine)
##   data/animation/heroine_placeholder_anims.tres (procedural capsule clips)
## Forms, heal and deathblow data are read from scenes/actors/heroine.tscn, timing from
## data/animation/heroine_anim.tres. Existing UIDs are kept. Run after adding or renaming
## an attack, or changing a placeholder pose:
##   godot --headless --path . --script res://scripts/animation/rebuild_heroine_anims.gd

const HEROINE: String = "res://scenes/actors/heroine.tscn"
const CONFIG: String = "res://data/animation/heroine_anim.tres"
const TREE: String = "res://data/animation/heroine_anim_tree.tres"
const LIBRARY: String = "res://data/animation/heroine_placeholder_anims.tres"


func _initialize() -> void:
	var ok: bool = rebuild()
	quit(0 if ok else 1)


static func rebuild() -> bool:
	var config: HeroineAnimConfig = load(CONFIG) as HeroineAnimConfig
	var heroine: Node = (load(HEROINE) as PackedScene).instantiate()
	var combat: PlayerCombat = heroine.get_node(^"PlayerCombat") as PlayerCombat
	var healing: PlayerHealing = heroine.get_node(^"Healing") as PlayerHealing
	var forms: Array[FormConfig] = combat.forms.duplicate()
	var heal: HealConfig = healing.config
	var deathblow_frames: int = combat.deathblow.recovery_frames if combat.deathblow != null else 50
	var dodge_frames: int = 18
	for form: FormConfig in forms:
		if form.can_dodge:
			dodge_frames = form.dodge_duration_frames
			break
	heroine.free()
	var tree: AnimationNodeStateMachine = HeroineAnimTree.build(forms, config, heal.use_frames, deathblow_frames, dodge_frames)
	var library: AnimationLibrary = HeroinePlaceholderAnims.build(forms, config, heal, deathblow_frames)
	return _save(tree, TREE) and _save(library, LIBRARY)


## Saves with the path's existing UID (or a new one): --script mode drops the uid header.
static func _save(resource: Resource, path: String) -> bool:
	var uid: int = _uid_in_file(path)
	if uid == ResourceUID.INVALID_ID:
		uid = ResourceUID.create_id()
	var err: Error = ResourceSaver.save(resource, path)
	if err != OK:
		printerr("could not save %s (%s)" % [path, error_string(err)])
		return false
	ResourceSaver.set_uid(path, uid)
	print("saved ", path)
	return true


## The uid in a saved .tres header (the uid cache may not know files saved from --script).
static func _uid_in_file(path: String) -> int:
	if not FileAccess.file_exists(path):
		return ResourceUID.INVALID_ID
	var header: String = FileAccess.open(path, FileAccess.READ).get_line()
	var at: int = header.find("uid=\"uid://")
	if at < 0:
		return ResourceUID.INVALID_ID
	var start: int = at + 5
	var end: int = header.find("\"", start)
	return ResourceUID.text_to_id(header.substr(start, end - start))
