extends Control
class_name FishingSnagRiskView

@export_category("References")
@export var caster: Node
@export var screen_transition: Node

@export_category("Risk Display")
@export_range(0.0, 1.0, 0.01) var show_threshold: float = 0.15
@export_range(0.0, 1.0, 0.01) var danger_threshold: float = 0.60
@export_range(0.0, 1.0, 0.01) var critical_threshold: float = 0.85
@export var display_smoothing_speed: float = 10.0
@export var hide_delay: float = 0.18

@export_category("Snagged Flash")
@export var snagged_hold_time: float = 0.65

@onready var root: Control = $Root
@onready var label: Label = $Root/Label
@onready var risk_bar: ProgressBar = $Root/RiskBar

var _target_risk: float = 0.0
var _display_risk: float = 0.0
var _hide_timer: float = 0.0
var _snagged_timer: float = 0.0
var _snagged_flash_active: bool = false
var _fill_style: StyleBoxFlat = null

const SAFE_COLOR := Color(0.95, 0.85, 0.28, 1.0)
const DANGER_COLOR := Color(1.0, 0.48, 0.16, 1.0)
const CRITICAL_COLOR := Color(0.95, 0.16, 0.12, 1.0)


func _ready() -> void:
	root.visible = false
	risk_bar.min_value = 0.0
	risk_bar.max_value = 1.0
	risk_bar.value = 0.0

	var style := risk_bar.get_theme_stylebox("fill")
	if style is StyleBoxFlat:
		_fill_style = style as StyleBoxFlat

	if caster == null:
		push_warning("FishingSnagRiskView: Caster is not assigned.")
		return

	caster.bait_snag_risk_changed.connect(_on_snag_risk_changed)
	caster.bait_snagged.connect(_on_snagged)
	caster.bait_returned.connect(_on_bait_returned)

	if screen_transition != null:
		screen_transition.covered.connect(clear)


func _process(delta: float) -> void:
	if _snagged_flash_active:
		_snagged_timer -= delta
		if _snagged_timer <= 0.0:
			_snagged_flash_active = false
			clear()
		return

	_display_risk = move_toward(
		_display_risk,
		_target_risk,
		maxf(display_smoothing_speed, 0.0) * delta
	)

	risk_bar.value = _display_risk
	_update_visual_state(_display_risk)

	if _target_risk >= show_threshold:
		_hide_timer = maxf(hide_delay, 0.0)
		root.visible = true
	elif root.visible:
		_hide_timer -= delta
		if _hide_timer <= 0.0 and _display_risk <= show_threshold:
			root.visible = false


func _on_snag_risk_changed(value: float) -> void:
	if _snagged_flash_active:
		return

	_target_risk = clampf(value, 0.0, 1.0)

	if _target_risk >= show_threshold:
		root.visible = true


func _on_snagged(_reason: StringName) -> void:
	_target_risk = 1.0
	_display_risk = 1.0
	risk_bar.value = 1.0
	_update_visual_state(1.0)
	label.text = "SNAGGED!"
	root.visible = true
	_snagged_flash_active = true
	_snagged_timer = maxf(snagged_hold_time, 0.0)


func _on_bait_returned() -> void:
	_target_risk = 0.0

	# A real snag emits snagged immediately before returned. Keep that final
	# feedback visible long enough to be readable instead of clearing it here.
	if _snagged_flash_active:
		return

	clear()


func _update_visual_state(value: float) -> void:
	if value >= critical_threshold:
		label.text = "SNAG!"
		_set_fill_color(CRITICAL_COLOR)
	elif value >= danger_threshold:
		label.text = "SNAG"
		_set_fill_color(DANGER_COLOR)
	else:
		label.text = "SNAG"
		_set_fill_color(SAFE_COLOR)


func _set_fill_color(color: Color) -> void:
	if _fill_style != null:
		_fill_style.bg_color = color


func clear() -> void:
	_target_risk = 0.0
	_display_risk = 0.0
	_hide_timer = 0.0
	_snagged_timer = 0.0
	_snagged_flash_active = false

	if is_instance_valid(risk_bar):
		risk_bar.value = 0.0

	if is_instance_valid(label):
		label.text = "SNAG"

	if is_instance_valid(root):
		root.visible = false
