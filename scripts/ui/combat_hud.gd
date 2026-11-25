class_name CombatHud
extends CanvasLayer
## Debug combat HUD for the sandbox: player health and posture at the bottom, the
## opponent's at the top, a big label naming each defence outcome, and a line with the
## parry timing of the last hit so the window can be tuned by feel.
## Builds its controls in code, so the .tscn is just this node.

@export var player: Combatant
@export var opponent: Combatant
## Seconds an outcome label stays on screen.
@export_range(0.1, 5.0, 0.1) var flash_seconds: float = 0.8

var _player_health: ProgressBar
var _player_posture: ProgressBar
var _opponent_health: ProgressBar
var _opponent_posture: ProgressBar
var _outcome_label: Label
var _timing_label: Label
var _flash_left: float = 0.0

const COLOR_HEALTH: Color = Color(0.78, 0.2, 0.18)
const COLOR_POSTURE: Color = Color(0.95, 0.68, 0.2)
const OUTCOME_COLORS: Dictionary[HitResult.Outcome, Color] = {
	HitResult.Outcome.PARRIED: Color(1.0, 0.92, 0.55),
	HitResult.Outcome.BLOCKED: Color(0.75, 0.8, 0.9),
	HitResult.Outcome.HIT: Color(0.95, 0.35, 0.3),
	HitResult.Outcome.GUARD_BROKEN: Color(1.0, 0.5, 0.2),
	HitResult.Outcome.MISSED: Color(0.6, 0.6, 0.6),
}


func _ready() -> void:
	_build()
	if player != null:
		_bind(player, _player_health, _player_posture)
		player.attack_resolved.connect(_on_player_defended)
		player.posture_broken.connect(func() -> void: _flash("POSTURE BROKEN", Color(1.0, 0.45, 0.2)))
		player.died.connect(func() -> void: _flash("DEFEATED", Color(0.9, 0.2, 0.2), 2.0))
	if opponent != null:
		_bind(opponent, _opponent_health, _opponent_posture)
		opponent.posture_broken.connect(func() -> void: _flash("POSTURE BREAK — OPENING", Color(0.55, 0.8, 1.0), 1.5))


func _process(delta: float) -> void:
	if _flash_left > 0.0:
		_flash_left -= delta
		_outcome_label.modulate.a = clampf(_flash_left / 0.3, 0.0, 1.0)


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

	var top: VBoxContainer = _bar_stack(root, Control.PRESET_CENTER_TOP, 24.0)
	_opponent_health = _bar(top, COLOR_HEALTH, 8.0)
	_opponent_posture = _bar(top, COLOR_POSTURE, 6.0)

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
	_timing_label.text = "Block: right mouse / LB. Tap just before a hit lands to parry."
	root.add_child(_timing_label)


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
