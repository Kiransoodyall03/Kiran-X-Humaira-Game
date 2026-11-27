class_name CombatHud
extends CanvasLayer
## Debug combat HUD for the sandbox: player health and posture at the bottom, the
## opponent's at the top, a big label naming each defence outcome, and a line with the
## parry timing of the last hit so the window can be tuned by feel. Bottom left: the
## heroine's current sword form and whether her dodge is ready. Under the opponent's bars,
## one pip per life (filled = left). While the opponent's deathblow window is open, a big
## DEATHBLOW prompt shows (with "press Attack" once she is in reach and facing it) and a
## red marker floats over the opponent. Above the form line: the heroine's corruption bar
## and a line with its percentage, whether she is in combat and RAMPAGE.
## While the heroine is locked on, a ring marker (with the part name) sits over the locked
## point, projected from the camera. Locked on a large monster's breakable part, that
## part's own posture bar shows under the opponent's bars ("LEFT FORELIMB", "· BROKEN").
## The opponent bars follow whichever enemy is locked on, else the nearest enemy (any body
## in the "hostile" group, alive or not), else `opponent`; the opponent's name shows above
## them.
## Above the corruption bar: the heroine's healing charges ("Heals ◆◆◇ 2/3", "· healing"
## while a heal runs). Flashes on a shrine rest and a shrine respawn.
## Builds its controls in code, so the .tscn is just this node.

## Emitted at the end of every _process, once every widget shows the current state. Tests
## await it before reading the HUD: physics waits don't promise a _process ran since.
signal refreshed

@export var player: Combatant
## The opponent shown first, and whenever no enemy is locked or found.
@export var opponent: Combatant
## Off: the opponent bars always show `opponent`.
@export var follow_enemies: bool = true
## The heroine's attacks/forms/dodge. Form and dodge lines are hidden if unset.
@export var player_combat: PlayerCombat
## The heroine's corruption meter. If unset, the "CorruptionMeter" sibling of
## player_combat. The corruption bar and line are hidden without one.
@export var corruption: CorruptionMeter
## The heroine's lock-on. If unset, the "LockOn" sibling of player_combat. No lock marker
## without one.
@export var lock_on: LockOn
## The heroine's healing charges. If unset, the "Healing" sibling of player_combat. The
## heals line is hidden without one.
@export var healing: PlayerHealing
## The heroine's shrine rest/respawn. If unset, the "Rest" sibling of player_combat.
@export var rest: PlayerRest
## Seconds an outcome label stays on screen.
@export_range(0.1, 5.0, 0.1) var flash_seconds: float = 0.8

var _player_health: ProgressBar
var _player_posture: ProgressBar
var _opponent_health: ProgressBar
var _opponent_name: Label
## The Combatant the opponent bars are connected to.
var _bound_opponent: Combatant
var _bound_once: bool = false
var _opponent_posture: ProgressBar
var _outcome_label: Label
var _timing_label: Label
var _form_label: Label
var _dodge_label: Label
var _corruption_bar: ProgressBar
var _corruption_label: Label
var _heal_label: Label
var _life_pips: HBoxContainer
var _deathblow_prompt: Label
var _deathblow_marker: Label
var _lock_marker: Control
var _lock_label: Label
var _part_label: Label
var _part_posture: ProgressBar
var _flash_left: float = 0.0
var _pulse_time: float = 0.0

const COLOR_HEALTH: Color = Color(0.78, 0.2, 0.18)
const COLOR_POSTURE: Color = Color(0.95, 0.68, 0.2)
const COLOR_DEATHBLOW: Color = Color(1.0, 0.16, 0.12)
const COLOR_LIFE: Color = Color(0.95, 0.85, 0.5)
const COLOR_LIFE_LOST: Color = Color(0.2, 0.2, 0.2, 0.7)
const COLOR_CORRUPTION: Color = Color(0.62, 0.22, 0.78)
const COLOR_RAMPAGE: Color = Color(0.95, 0.15, 0.45)
const COLOR_LOCK: Color = Color(1.0, 0.95, 0.8)
const COLOR_HEAL: Color = Color(0.5, 0.95, 0.6)
const COLOR_REST: Color = Color(0.95, 0.9, 0.6)
const COLOR_PART_POSTURE: Color = Color(0.95, 0.85, 0.45)
const COLOR_PART_BROKEN: Color = Color(0.85, 0.3, 0.25)
## Radius of the lock-on ring, in pixels.
const LOCK_RING_RADIUS: float = 14.0
## Height above the opponent's origin where the deathblow marker floats, in meters.
const MARKER_HEIGHT: float = 2.7
const OUTCOME_COLORS: Dictionary[HitResult.Outcome, Color] = {
	HitResult.Outcome.PARRIED: Color(1.0, 0.92, 0.55),
	HitResult.Outcome.BLOCKED: Color(0.75, 0.8, 0.9),
	HitResult.Outcome.HIT: Color(0.95, 0.35, 0.3),
	HitResult.Outcome.GUARD_BROKEN: Color(1.0, 0.5, 0.2),
	HitResult.Outcome.MISSED: Color(0.6, 0.6, 0.6),
	HitResult.Outcome.DODGED: Color(0.55, 0.95, 0.85),
}


func _ready() -> void:
	_build()
	if player != null:
		_bind(player, _player_health, _player_posture)
		player.attack_resolved.connect(_on_player_defended)
		player.posture_broken.connect(func() -> void: _flash("POSTURE BROKEN", Color(1.0, 0.45, 0.2)))
		player.died.connect(func() -> void: _flash("DEFEATED", Color(0.9, 0.2, 0.2), 2.0))
	_bind_opponent(opponent)
	if player_combat != null:
		player_combat.form_changed.connect(func(_f: FormConfig) -> void: _refresh_form())
		if corruption == null:
			corruption = player_combat.get_parent().get_node_or_null(^"CorruptionMeter") as CorruptionMeter
		if lock_on == null:
			lock_on = player_combat.get_parent().get_node_or_null(^"LockOn") as LockOn
		if healing == null:
			healing = player_combat.get_parent().get_node_or_null(^"Healing") as PlayerHealing
		if rest == null:
			rest = player_combat.get_parent().get_node_or_null(^"Rest") as PlayerRest
	if healing != null:
		# Event-driven too, so the line never lags a physics tick behind the charges.
		healing.charges_changed.connect(func(_c: int, _m: int) -> void: _refresh_heals())
	if corruption != null:
		corruption.rampage_started.connect(func() -> void: _flash("RAMPAGE", COLOR_RAMPAGE, 1.5))
	if rest != null:
		rest.rested.connect(func(_s: Node3D) -> void: _flash("RESTED  ·  heals refilled", COLOR_REST, 2.0))
		rest.respawned.connect(func(_s: Node3D) -> void: _flash("RETURNED TO SHRINE", COLOR_REST, 2.0))
	_refresh_form()
	_refresh_lives()
	_refresh_deathblow()


func _process(delta: float) -> void:
	if _flash_left > 0.0:
		_flash_left -= delta
		_outcome_label.modulate.a = clampf(_flash_left / 0.3, 0.0, 1.0)
	_pulse_time += delta
	if follow_enemies:
		_bind_opponent(_pick_opponent())
	_refresh_dodge()
	_refresh_deathblow()
	_refresh_corruption()
	_refresh_heals()
	_refresh_lock()
	_refresh_part()
	refreshed.emit()


## The Combatant the opponent bars show (null if none).
func current_opponent() -> Combatant:
	return opponent


## Text above the opponent bars: the opponent's name.
func opponent_name_text() -> String:
	return _opponent_name.text


## Locked target, else the nearest body in the "hostile" group (by ground distance from
## the heroine), else the current opponent.
func _pick_opponent() -> Combatant:
	if lock_on != null and lock_on.is_locked() and lock_on.current_target() != null:
		return lock_on.current_target()
	var me: Node3D = player.get_parent() as Node3D if player != null else null
	if me == null:
		return opponent
	var best: Combatant = null
	var best_distance: float = INF
	for node: Node in get_tree().get_nodes_in_group(CorruptionMeter.HOSTILE_GROUP):
		var body: Node3D = node as Node3D
		var c: Combatant = Combatant.find_on(node)
		if body == null or c == null or c == player:
			continue
		var offset: Vector3 = body.global_position - me.global_position
		offset.y = 0.0
		if offset.length() < best_distance:
			best_distance = offset.length()
			best = c
	if best != null:
		return best
	return opponent if is_instance_valid(opponent) else null


## Points the opponent bars, life pips and deathblow prompt at `c`.
func _bind_opponent(c: Combatant) -> void:
	if _bound_once and c == _bound_opponent and c == opponent:
		return
	_bound_once = true
	if _bound_opponent != null and is_instance_valid(_bound_opponent):
		_bound_opponent.health_changed.disconnect(_on_opponent_health)
		_bound_opponent.posture_changed.disconnect(_on_opponent_posture)
		_bound_opponent.revived.disconnect(_on_opponent_revived)
		_bound_opponent.posture_broken.disconnect(_on_opponent_posture_broken)
		_bound_opponent.died.disconnect(_on_opponent_died)
		_bound_opponent.lives_changed.disconnect(_on_opponent_lives)
		_bound_opponent.deathblow_landed.disconnect(_on_opponent_deathblow)
	opponent = c
	_bound_opponent = c
	_opponent_health.visible = c != null
	_opponent_posture.visible = c != null
	_opponent_name.visible = c != null
	if c != null:
		c.health_changed.connect(_on_opponent_health)
		c.posture_changed.connect(_on_opponent_posture)
		c.revived.connect(_on_opponent_revived)
		c.posture_broken.connect(_on_opponent_posture_broken)
		c.died.connect(_on_opponent_died)
		c.lives_changed.connect(_on_opponent_lives)
		c.deathblow_landed.connect(_on_opponent_deathblow)
		_on_opponent_revived()
		var body: Node = c.get_parent()
		_opponent_name.text = String(body.name).to_snake_case().replace("_", " ").to_upper() if body != null else ""
	_refresh_lives()


func _on_opponent_health(v: float, m: float) -> void:
	_opponent_health.max_value = m
	_opponent_health.value = v


func _on_opponent_posture(v: float, m: float) -> void:
	_opponent_posture.max_value = m
	_opponent_posture.value = v


func _on_opponent_revived() -> void:
	_on_opponent_health(opponent.health, opponent.config.max_health)
	_on_opponent_posture(opponent.posture.value, opponent.config.posture.max_posture)


func _on_opponent_posture_broken() -> void:
	_flash("POSTURE BREAK — OPENING", Color(0.55, 0.8, 1.0), 1.5)


func _on_opponent_died() -> void:
	_flash("OPPONENT DOWN", Color(0.95, 0.85, 0.5), 2.0)


func _on_opponent_lives(_left: int, _max: int) -> void:
	_refresh_lives()


func _on_opponent_deathblow(lives_left: int) -> void:
	_flash("DEATHBLOW" if lives_left <= 0 else "DEATHBLOW — %d LIFE LEFT" % lives_left, COLOR_DEATHBLOW, 1.5)


## True while the lock-on marker is on screen.
func lock_marker_visible() -> bool:
	return _lock_marker.visible


## Screen position of the lock-on marker's centre, in pixels.
func lock_marker_screen_position() -> Vector2:
	return _lock_marker.position + _lock_marker.size * 0.5


## Text under the lock marker: the locked part, e.g. "body".
func lock_marker_text() -> String:
	return _lock_label.text


func _refresh_lock() -> void:
	_lock_marker.visible = false
	_lock_label.visible = false
	if lock_on == null or not lock_on.is_locked():
		return
	var camera: Camera3D = get_viewport().get_camera_3d()
	var point: Vector3 = lock_on.target_position()
	if camera == null or camera.is_position_behind(point):
		return
	var screen: Vector2 = camera.unproject_position(point)
	_lock_marker.visible = true
	_lock_marker.position = screen - _lock_marker.size * 0.5
	_lock_marker.queue_redraw()
	var part: LockOnPoint = lock_on.current_point()
	_lock_label.text = String(part.part_id) if part != null else ""
	_lock_label.visible = not _lock_label.text.is_empty()
	_lock_label.position = screen + Vector2(-_lock_label.size.x * 0.5, LOCK_RING_RADIUS + 4.0)


## True while the locked part's posture bar is on screen.
func part_bar_visible() -> bool:
	return _part_posture.visible


## Text over the locked part's posture bar, e.g. "LEFT FORELIMB" or "TAIL  ·  BROKEN".
func part_bar_text() -> String:
	return _part_label.text


## Fill of the locked part's posture bar, 0–1.
func part_bar_ratio() -> float:
	return _part_posture.value / _part_posture.max_value if _part_posture.max_value > 0.0 else 0.0


## Shows the locked point's part posture bar when it is a breakable MonsterPart.
func _refresh_part() -> void:
	var point: LockOnPoint = lock_on.current_point() if lock_on != null else null
	var part: MonsterPart = point.get_parent() as MonsterPart if point != null else null
	var shown: bool = part != null and part.state != null and part.is_breakable()
	_part_label.visible = shown
	_part_posture.visible = shown
	if not shown:
		return
	var broken: bool = part.is_broken()
	_part_label.text = String(part.part_id()).replace("_", " ").to_upper() + ("  ·  BROKEN" if broken else "")
	_part_posture.max_value = part.posture_max()
	_part_posture.value = part.posture_value()
	(_part_posture.get_theme_stylebox(&"fill") as StyleBoxFlat).bg_color = COLOR_PART_BROKEN if broken else COLOR_PART_POSTURE


## True while the DEATHBLOW prompt is on screen.
func deathblow_prompt_visible() -> bool:
	return _deathblow_prompt.visible


## Text of the deathblow prompt, e.g. "DEATHBLOW  ·  press Attack".
func deathblow_prompt_text() -> String:
	return _deathblow_prompt.text


## Opponent life pips: [filled, total].
func opponent_life_pips() -> Vector2i:
	var filled: int = 0
	for pip: Node in _life_pips.get_children():
		if (pip as ColorRect).color == COLOR_LIFE:
			filled += 1
	return Vector2i(filled, _life_pips.get_child_count())


## Text of the form line, e.g. "GREATSWORD".
func form_text() -> String:
	return _form_label.text


## Text of the dodge line, e.g. "Dodge: ready".
func dodge_text() -> String:
	return _dodge_label.text


## Value shown on the corruption bar (0–max), or -1 when the bar is hidden.
func corruption_bar_value() -> float:
	return _corruption_bar.value if _corruption_bar.visible else -1.0


## Text of the corruption line, e.g. "Corruption 42% · in combat".
func corruption_text() -> String:
	return _corruption_label.text


## Text of the heals line, e.g. "Heals ◆◆◇  2/3", or "" when it is hidden.
func heal_text() -> String:
	return _heal_label.text if _heal_label.visible else ""


func _refresh_heals() -> void:
	var shown: bool = healing != null and healing.charges != null
	_heal_label.visible = shown
	if not shown:
		return
	var left: int = healing.charges_left()
	var total: int = healing.max_charges()
	var text: String = "Heals " + "◆".repeat(left) + "◇".repeat(maxi(total - left, 0)) + "  %d/%d" % [left, total]
	if healing.is_healing():
		text += "  ·  healing"
	_heal_label.text = text
	_heal_label.add_theme_color_override(&"font_color", COLOR_HEAL if left > 0 else Color(0.6, 0.6, 0.6))


func _refresh_corruption() -> void:
	var shown: bool = corruption != null and corruption.corruption != null
	_corruption_bar.visible = shown
	_corruption_label.visible = shown
	if not shown:
		return
	_corruption_bar.max_value = corruption.max_value()
	_corruption_bar.value = corruption.value()
	var text: String = "Corruption %d%%" % roundi(corruption.ratio() * 100.0)
	text += "  ·  in combat" if corruption.in_combat else "  ·  out of combat"
	var color: Color = COLOR_CORRUPTION.lightened(0.35)
	if corruption.is_rampaging():
		text += "  ·  RAMPAGE (no dodge)"
		color = COLOR_RAMPAGE
		color.a = 0.75 + 0.25 * sin(_pulse_time * 8.0)
	_corruption_label.text = text
	_corruption_label.add_theme_color_override(&"font_color", color)


func _refresh_lives() -> void:
	_life_pips.visible = opponent != null
	if opponent == null:
		return
	var total: int = maxi(opponent.config.lives, 1)
	while _life_pips.get_child_count() < total:
		var pip: ColorRect = ColorRect.new()
		pip.custom_minimum_size = Vector2(14.0, 14.0)
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_life_pips.add_child(pip)
	while _life_pips.get_child_count() > total:
		var extra: Node = _life_pips.get_child(_life_pips.get_child_count() - 1)
		_life_pips.remove_child(extra)
		extra.queue_free()
	for i: int in total:
		(_life_pips.get_child(i) as ColorRect).color = COLOR_LIFE if i < opponent.lives_left else COLOR_LIFE_LOST


func _refresh_deathblow() -> void:
	var available: bool = opponent != null and opponent.is_deathblow_available()
	_deathblow_prompt.visible = available
	_deathblow_marker.visible = false
	if not available:
		return
	var in_reach: bool = player_combat != null and player_combat.deathblow_target() == opponent
	_deathblow_prompt.text = "DEATHBLOW  ·  press Attack" if in_reach else "DEATHBLOW  ·  get close"
	_deathblow_prompt.modulate.a = 0.75 + 0.25 * sin(_pulse_time * 10.0)
	var target: Node3D = opponent.get_parent() as Node3D
	var camera: Camera3D = get_viewport().get_camera_3d()
	if target == null or camera == null:
		return
	var point: Vector3 = target.global_position + Vector3.UP * MARKER_HEIGHT
	if camera.is_position_behind(point):
		return
	_deathblow_marker.visible = true
	_deathblow_marker.position = camera.unproject_position(point) - _deathblow_marker.size * 0.5


func _refresh_form() -> void:
	_form_label.visible = player_combat != null
	if player_combat == null:
		return
	var form: FormConfig = player_combat.current_form()
	_form_label.text = form.display_name.to_upper()
	_form_label.add_theme_color_override(&"font_color", form.hud_color)
	_refresh_dodge()


func _refresh_dodge() -> void:
	_dodge_label.visible = player_combat != null
	if player_combat == null:
		return
	if not player_combat.current_form().can_dodge:
		_dodge_label.text = "Dodge: — (katana only)"
		_dodge_label.modulate = Color(1, 1, 1, 0.5)
	elif player_combat.is_dodge_locked():
		_dodge_label.text = "Dodge: locked (rampage)"
		_dodge_label.modulate = COLOR_RAMPAGE
	elif player_combat.dodge_ready():
		_dodge_label.text = "Dodge: ready"
		_dodge_label.modulate = Color(0.55, 0.95, 0.85)
	else:
		_dodge_label.text = "Dodge: %d%%" % roundi((1.0 - player_combat.dodge_cooldown_ratio()) * 100.0)
		_dodge_label.modulate = Color(1, 1, 1, 0.7)


func _bind(c: Combatant, health_bar: ProgressBar, posture_bar: ProgressBar) -> void:
	health_bar.max_value = c.config.max_health
	health_bar.value = c.health
	posture_bar.max_value = c.config.posture.max_posture
	posture_bar.value = c.posture.value
	c.health_changed.connect(func(v: float, m: float) -> void:
		health_bar.max_value = m
		health_bar.value = v)
	c.posture_changed.connect(func(v: float, m: float) -> void:
		posture_bar.max_value = m
		posture_bar.value = v)
	c.revived.connect(func() -> void:
		health_bar.value = c.health
		posture_bar.value = c.posture.value)


func _on_player_defended(result: HitResult, _attacker: Combatant) -> void:
	var text: String = result.outcome_name().replace("_", " ")
	if result.attack != null and result.attack.perilous != AttackData.Perilous.NONE:
		text += "  (%s)" % (AttackData.Perilous.keys()[result.attack.perilous] as String)
	_flash(text, OUTCOME_COLORS.get(result.outcome, Color.WHITE) as Color)
	var since: int = player.guard.frames_since_press(Combatant.current_frame())
	var press_text: String = "never pressed" if since < 0 else "pressed %d frames before the hit" % since
	_timing_label.text = "Guard %s · parry window %d frames · %s" % [press_text, player.guard.current_window(), result.attack.id if result.attack != null else &""]


func _flash(text: String, color: Color, seconds: float = -1.0) -> void:
	_outcome_label.text = text
	_outcome_label.add_theme_color_override(&"font_color", color)
	_flash_left = seconds if seconds > 0.0 else flash_seconds
	_outcome_label.modulate.a = 1.0


func _build() -> void:
	var root: Control = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var top: VBoxContainer = _bar_stack(root, Control.PRESET_CENTER_TOP, 8.0)
	_opponent_name = Label.new()
	_opponent_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_opponent_name.add_theme_font_size_override(&"font_size", 14)
	_opponent_name.add_theme_constant_override(&"outline_size", 4)
	_opponent_name.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.8))
	_opponent_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(_opponent_name)
	_opponent_health = _bar(top, COLOR_HEALTH, 8.0)
	_opponent_posture = _bar(top, COLOR_POSTURE, 6.0)
	_life_pips = HBoxContainer.new()
	_life_pips.alignment = BoxContainer.ALIGNMENT_CENTER
	_life_pips.add_theme_constant_override(&"separation", 6)
	_life_pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(_life_pips)
	_part_label = Label.new()
	_part_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_part_label.add_theme_font_size_override(&"font_size", 12)
	_part_label.add_theme_constant_override(&"outline_size", 4)
	_part_label.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.8))
	_part_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_part_label.visible = false
	top.add_child(_part_label)
	_part_posture = _bar(top, COLOR_PART_POSTURE, 5.0)
	_part_posture.visible = false

	_deathblow_prompt = Label.new()
	_deathblow_prompt.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_deathblow_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_deathblow_prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_deathblow_prompt.position.y = 96.0
	_deathblow_prompt.add_theme_font_size_override(&"font_size", 40)
	_deathblow_prompt.add_theme_color_override(&"font_color", COLOR_DEATHBLOW)
	_deathblow_prompt.add_theme_constant_override(&"outline_size", 8)
	_deathblow_prompt.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.9))
	_deathblow_prompt.visible = false
	root.add_child(_deathblow_prompt)

	_deathblow_marker = Label.new()
	_deathblow_marker.text = "◆"
	_deathblow_marker.add_theme_font_size_override(&"font_size", 36)
	_deathblow_marker.add_theme_color_override(&"font_color", COLOR_DEATHBLOW)
	_deathblow_marker.add_theme_constant_override(&"outline_size", 6)
	_deathblow_marker.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.9))
	_deathblow_marker.visible = false
	root.add_child(_deathblow_marker)

	_lock_marker = Control.new()
	_lock_marker.size = Vector2.ONE * (LOCK_RING_RADIUS * 2.0 + 4.0)
	_lock_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lock_marker.visible = false
	_lock_marker.draw.connect(_draw_lock_marker)
	root.add_child(_lock_marker)

	_lock_label = Label.new()
	_lock_label.add_theme_font_size_override(&"font_size", 13)
	_lock_label.add_theme_color_override(&"font_color", COLOR_LOCK)
	_lock_label.add_theme_constant_override(&"outline_size", 4)
	_lock_label.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.8))
	_lock_label.visible = false
	root.add_child(_lock_label)

	var bottom: VBoxContainer = _bar_stack(root, Control.PRESET_CENTER_BOTTOM, -64.0)
	_player_posture = _bar(bottom, COLOR_POSTURE, 6.0)
	_player_health = _bar(bottom, COLOR_HEALTH, 8.0)

	_outcome_label = Label.new()
	_outcome_label.set_anchors_preset(Control.PRESET_CENTER)
	_outcome_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_outcome_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_outcome_label.position.y = 60.0
	_outcome_label.add_theme_font_size_override(&"font_size", 34)
	_outcome_label.add_theme_constant_override(&"outline_size", 6)
	_outcome_label.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.8))
	_outcome_label.modulate.a = 0.0
	root.add_child(_outcome_label)

	_timing_label = Label.new()
	_timing_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_timing_label.position = Vector2(16.0, -32.0)
	_timing_label.add_theme_font_size_override(&"font_size", 14)
	_timing_label.text = "Attack: left mouse / RB · Block: right mouse / LB (tap to parry) · Form: Q / Y · Dodge (katana): C or Alt / B · Deathblow: attack a staggered opponent · Lock-on: middle mouse / R3 (switch: wheel / flick right stick or mouse) · Heal: R / D-pad up · Rest at a shrine: E / X"
	root.add_child(_timing_label)

	_form_label = Label.new()
	_form_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_form_label.position = Vector2(16.0, -100.0)
	_form_label.add_theme_font_size_override(&"font_size", 24)
	_form_label.add_theme_constant_override(&"outline_size", 5)
	_form_label.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.8))
	root.add_child(_form_label)

	_dodge_label = Label.new()
	_dodge_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_dodge_label.position = Vector2(16.0, -66.0)
	_dodge_label.add_theme_font_size_override(&"font_size", 16)
	_dodge_label.add_theme_constant_override(&"outline_size", 4)
	_dodge_label.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.8))
	root.add_child(_dodge_label)

	_corruption_label = Label.new()
	_corruption_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_corruption_label.position = Vector2(16.0, -150.0)
	_corruption_label.add_theme_font_size_override(&"font_size", 16)
	_corruption_label.add_theme_constant_override(&"outline_size", 4)
	_corruption_label.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.8))
	root.add_child(_corruption_label)

	_heal_label = Label.new()
	_heal_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_heal_label.position = Vector2(16.0, -178.0)
	_heal_label.add_theme_font_size_override(&"font_size", 18)
	_heal_label.add_theme_constant_override(&"outline_size", 4)
	_heal_label.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.8))
	root.add_child(_heal_label)

	var corruption_holder: Control = Control.new()
	corruption_holder.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	corruption_holder.position = Vector2(16.0, -124.0)
	corruption_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(corruption_holder)
	_corruption_bar = _bar(corruption_holder, COLOR_CORRUPTION, 10.0)
	_corruption_bar.step = 0.01
	_corruption_bar.custom_minimum_size = Vector2(260.0, 10.0)
	_corruption_bar.size = Vector2(260.0, 10.0)


func _draw_lock_marker() -> void:
	var center: Vector2 = _lock_marker.size * 0.5
	_lock_marker.draw_arc(center, LOCK_RING_RADIUS + 1.0, 0.0, TAU, 32, Color(0, 0, 0, 0.7), 4.0, true)
	_lock_marker.draw_arc(center, LOCK_RING_RADIUS, 0.0, TAU, 32, COLOR_LOCK, 2.0, true)
	_lock_marker.draw_circle(center, 3.0, COLOR_LOCK)


func _bar_stack(parent: Control, preset: Control.LayoutPreset, y: float) -> VBoxContainer:
	var stack: VBoxContainer = VBoxContainer.new()
	stack.set_anchors_preset(preset)
	stack.custom_minimum_size = Vector2(420.0, 0.0)
	stack.position = Vector2(-210.0, y)
	stack.add_theme_constant_override(&"separation", 3)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(stack)
	return stack


func _bar(parent: Control, color: Color, height: float) -> ProgressBar:
	var bar: ProgressBar = ProgressBar.new()
	bar.custom_minimum_size = Vector2(420.0, height)
	bar.show_percentage = false
	var fill: StyleBoxFlat = StyleBoxFlat.new()
	fill.bg_color = color
	var back: StyleBoxFlat = StyleBoxFlat.new()
	back.bg_color = Color(0.0, 0.0, 0.0, 0.45)
	bar.add_theme_stylebox_override(&"fill", fill)
	bar.add_theme_stylebox_override(&"background", back)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(bar)
	return bar
