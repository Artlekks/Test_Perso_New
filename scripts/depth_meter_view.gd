extends Control

@export_category("References")
@export var caster: Node

@export_category("Depth Display")
@export var max_display_depth: float = 4.0

# Where the water/ground boundary exists inside DepthStrip.
# 0.5 means exactly halfway down the long texture.
@export_range(0.0, 1.0, 0.01)
var ground_line_ratio: float = 0.5

@export_category("Fish Radar")
@export var fish_zone: Node

@export_range(0.05, 1.0, 0.05)
var radar_refresh_interval: float = 0.15

@export_range(1, 24, 1)
var radar_max_dots: int = 14

@export var radar_dot_size: Vector2 = Vector2(4.0, 4.0)

@export_category("Transition")
@export var slide_time: float = 0.55
@export var slide_padding: float = 20.0

@onready var depth_window: Control = $DepthWindow
@onready var depth_strip: Control = $DepthWindow/DepthStrip
@onready var arrow: Control = $Arrow

var rest_position: Vector2
var slide_tween: Tween
var is_shown: bool = false

var _radar_layer: Control = null
var _radar_dots: Array[ColorRect] = []
var _last_radar_refresh_seconds: float = -999.0

func _ready() -> void:
	if caster == null:
		push_warning("DepthMeter: Caster is not assigned.")
		return

	caster.bait_depth_changed.connect(_on_depth_changed)
	caster.bait_returned.connect(_on_bait_returned)

	depth_window.clip_contents = true
	_ensure_radar_layer()

	rest_position = position
	visible = false


func _on_depth_changed(
	current_depth: float,
	total_depth: float
) -> void:
	if not is_shown:
		_slide_in()

	current_depth = maxf(current_depth, 0.0)
	total_depth = maxf(total_depth, 0.0)

	_update_depth_strip(total_depth)
	_update_arrow(current_depth, total_depth)
	_update_fish_radar_if_due(total_depth)


func _update_depth_strip(total_depth: float) -> void:
	var depth_ratio := clampf(
		total_depth / max_display_depth,
		0.0,
		1.0
	)

	# Pixel position of the water/ground boundary
	# inside the long DepthStrip image.
	var ground_line_y := (
		depth_strip.size.y
		* ground_line_ratio
	)

	# Where that boundary should appear inside
	# the visible DepthWindow.
	var target_ground_y := (
		depth_window.size.y
		* depth_ratio
	)

	depth_strip.position.y = (
		target_ground_y
		- ground_line_y
	)


func _update_arrow(
	current_depth: float,
	total_depth: float
) -> void:
	var bait_ratio := 0.0

	if total_depth > 0.0:
		bait_ratio = clampf(
			current_depth / total_depth,
			0.0,
			1.0
		)

	var ground_ratio := clampf(
		total_depth / max_display_depth,
		0.0,
		1.0
	)

	var arrow_half_height := arrow.size.y * 0.5

	var water_top_y := (
		depth_window.position.y
		- arrow_half_height
	)

	var water_bottom_y := (
		depth_window.position.y
		+ depth_window.size.y * ground_ratio
		- arrow_half_height
	)

	arrow.position.y = lerpf(
		water_top_y,
		water_bottom_y,
		bait_ratio
	)


func _on_bait_returned() -> void:
	_clear_fish_radar()
	_slide_out()

func _slide_in() -> void:
	if slide_tween != null and slide_tween.is_valid():
		slide_tween.kill()

	is_shown = true
	visible = true

	var viewport_width := get_viewport_rect().size.x
	position = Vector2(
		viewport_width + slide_padding,
		rest_position.y
	)

	slide_tween = create_tween()
	slide_tween.set_trans(Tween.TRANS_SINE)
	slide_tween.set_ease(Tween.EASE_OUT)

	slide_tween.tween_property(
		self,
		"position",
		rest_position,
		slide_time
	)


func _slide_out() -> void:
	if not is_shown:
		return

	if slide_tween != null and slide_tween.is_valid():
		slide_tween.kill()

	is_shown = false

	var viewport_width := get_viewport_rect().size.x
	var offscreen_position := Vector2(
		viewport_width + slide_padding,
		rest_position.y
	)

	slide_tween = create_tween()
	slide_tween.set_trans(Tween.TRANS_SINE)
	slide_tween.set_ease(Tween.EASE_IN)

	slide_tween.tween_property(
		self,
		"position",
		offscreen_position,
		slide_time
	)

	slide_tween.tween_callback(_finish_slide_out)


func _finish_slide_out() -> void:
	visible = false
	position = rest_position

func reset_to_aim() -> void:
	_clear_fish_radar()

	if slide_tween != null and slide_tween.is_valid():
		slide_tween.kill()

	slide_tween = null
	is_shown = false
	visible = false
	position = rest_position



func set_fish_zone(new_zone: Node) -> void:
	fish_zone = new_zone
	_last_radar_refresh_seconds = -999.0
	_clear_fish_radar()


func _ensure_radar_layer() -> void:
	if _radar_layer != null:
		return

	_radar_layer = Control.new()
	_radar_layer.name = "FishRadarLayer"
	_radar_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_radar_layer.z_index = 4
	depth_window.add_child(_radar_layer)
	_radar_layer.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)

	for _index in range(radar_max_dots):
		var dot := ColorRect.new()
		dot.name = "RadarDot"
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dot.color = Color(1.0, 1.0, 1.0, 0.86)
		dot.size = radar_dot_size
		dot.visible = false
		_radar_layer.add_child(dot)
		_radar_dots.append(dot)


func _update_fish_radar_if_due(
	total_depth: float
) -> void:
	if (
		fish_zone == null
		or caster == null
		or not caster.has_method(
			"get_active_bait_world_position"
		)
		or not fish_zone.has_method(
			"get_fish_radar_snapshot"
		)
	):
		_clear_fish_radar()
		return

	var now_seconds: float = (
		Time.get_ticks_msec()
		/ 1000.0
	)

	if (
		now_seconds
		- _last_radar_refresh_seconds
		< radar_refresh_interval
	):
		return

	_last_radar_refresh_seconds = now_seconds

	var snapshot: Dictionary = (
		fish_zone.get_fish_radar_snapshot(
			caster.get_active_bait_world_position()
		)
	)
	var dots: Array = snapshot.get(
		"dots",
		[]
	)
	var visible_count: int = mini(
		dots.size(),
		_radar_dots.size()
	)

	var ground_ratio: float = clampf(
		total_depth / maxf(max_display_depth, 0.001),
		0.0,
		1.0
	)
	var water_height: float = (
		depth_window.size.y
		* ground_ratio
	)
	var usable_width: float = maxf(
		depth_window.size.x
		- radar_dot_size.x
		- 4.0,
		1.0
	)

	for index in range(_radar_dots.size()):
		var dot: ColorRect = _radar_dots[index]

		if index >= visible_count:
			dot.visible = false
			continue

		var item: Dictionary = (
			dots[index] as Dictionary
		)
		var x_ratio: float = clampf(
			float(item.get("x_ratio", 0.5)),
			0.0,
			1.0
		)
		var depth_ratio: float = clampf(
			float(
				item.get(
					"depth_ratio",
					0.5
				)
			),
			0.0,
			1.0
		)

		dot.position = Vector2(
			2.0 + usable_width * x_ratio,
			maxf(
				water_height * depth_ratio
				- radar_dot_size.y * 0.5,
				0.0
			)
		)
		dot.visible = true


func _clear_fish_radar() -> void:
	for dot in _radar_dots:
		if dot != null:
			dot.visible = false
