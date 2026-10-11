extends CanvasLayer

@onready var root: Control = $Root
@onready var fill: Sprite2D = $Root/PowerBarFill
@onready var tension_meter: Sprite2D = $Root/TensionMeter
@onready var distance_value: Control = $Root/DistanceValue
@onready var distance_decimal: Control = $Root/DistanceDecimal

@export var power: Node
@export var encounter: Node
@export var caster: Node

@export_category("Bar Textures")
@export var bar_green: Texture2D

@export_category("Transitions")
@export var slide_time: float = 0.25
@export var slide_padding_px: float = 12.0
@export_category("Tension Colors")
@export var slack_color: Color = Color(0.20, 0.55, 1.0)
@export var safe_color: Color = Color(0.20, 1.0, 0.30)
@export var overload_color: Color = Color(1.0, 0.20, 0.10)

@export_range(0.0, 1.0, 0.01)
var safe_color_min: float = 0.35

@export_range(0.0, 1.0, 0.01)
var safe_color_max: float = 0.55

@export_range(0.01, 0.5, 0.01)
var slack_color_transition: float = 0.12

@export_range(0.01, 0.5, 0.01)
var overload_color_transition: float = 0.12

var full_scale_x: float = 1.0
var showing_tension: bool = false

var _rest_position: Vector2 = Vector2.ZERO
var _slide_tween: Tween = null
var _cancel_to_aim_pending: bool = false
var fight_tension_active: bool = false
const REFERENCE_VIEWPORT := Vector2(640.0,480.0)
var _authored_rest := Vector2.ZERO
var _authored_depth_rest := Vector2.ZERO
var _layout_size := Vector2.ZERO
var _slide_progress := 0.0
@export_category("Responsive Fishing Composition")
## Character-to-bar clearance, expressed in power-bar heights. Independent
## of shell/breakpoint and animation-frame padding or rod pose.
@export_range(0.1,1.0,0.05) var character_to_bar_gap_ratio := 0.25
var _stance_actor: Node3D
var _stance_pixels := Vector2.ZERO
var _last_stance_right := -INF

func _ready() -> void:
	full_scale_x = fill.scale.x
	_authored_rest = Vector2(root.offset_left,root.offset_top) + Vector2(root.anchor_left,root.anchor_top)*REFERENCE_VIEWPORT
	root.set_anchors_preset(Control.PRESET_TOP_LEFT,true)
	var depth := get_node_or_null("DepthMeter") as Control
	if depth != null: _authored_depth_rest = depth.position
	_update_viewport_layout()

	power.power_changed.connect(_on_power_changed)
	power.started.connect(_on_power_started)
	power.stopped.connect(_on_power_stopped)

	encounter.tension_changed.connect(_on_tension_changed)

	caster.bait_returned.connect(_on_bait_returned)
	caster.bait_distance_changed.connect(_on_bait_distance_changed)
	
	root.visible = false
	tension_meter.visible = false
	encounter.fish_hooked.connect(_on_fish_hooked)
	
func _on_bait_distance_changed(distance_meters: float) -> void:
	var scaled_distance := maxi(
		int(round(maxf(distance_meters, 0.0) * 10.0)),
		0
	)

	var whole := int(scaled_distance / 10.0)
	var decimal := scaled_distance % 10

	distance_value.set_text(str(whole))
	distance_decimal.set_text(str(decimal))

func _process(_delta: float) -> void:
	_update_viewport_layout()

func _update_viewport_layout() -> void:
	var viewport := custom_viewport as Viewport
	if viewport == null: viewport = get_viewport()
	var dimensions := viewport.get_visible_rect().size
	var stance_right := fishing_stance_right_pixels()
	if dimensions == _layout_size and absf(stance_right-_last_stance_right)<.01: return
	_layout_size = dimensions
	_last_stance_right = stance_right
	# Both gauges share a player-relative translation. The 640 reference only
	# supplies authored artwork spacing and Y; it never anchors X to a screen edge.
	var background := $Root/PowerBarBG as Sprite2D
	var bar_height := background.get_rect().size.y*root.scale.y*background.scale.y
	var wanted_x := stance_right+bar_height*character_to_bar_gap_ratio
	var group_right := _authored_rest.x+background.get_rect().end.x*root.scale.x
	var depth := get_node_or_null("DepthMeter")
	if depth != null:
		var frame := depth.get_node("Frame") as Control
		group_right = maxf(group_right,_authored_depth_rest.x+frame.get_rect().end.x*depth.scale.x)
	# Constrain the intact group only when space is physically unavailable.
	var margin := bar_height*character_to_bar_gap_ratio
	var shift_x := clampf(wanted_x-_authored_rest.x,-_authored_rest.x+margin,dimensions.x-margin-group_right)
	_rest_position = Vector2(_authored_rest.x+shift_x,_authored_rest.y*dimensions.y/REFERENCE_VIEWPORT.y)
	_set_slide_progress(_slide_progress)
	if depth != null and depth.has_method("set_layout_rest"):
		depth.set_layout_rest(Vector2(_authored_depth_rest.x+shift_x,_authored_depth_rest.y*dimensions.y/REFERENCE_VIEWPORT.y),dimensions)

func fishing_stance_right_pixels() -> float:
	if not is_instance_valid(caster) or not is_instance_valid(caster.reel_target): return _authored_rest.x
	var actor := caster.reel_target as Node3D
	# ReelEndPoint is a physical child, not the visual actor root.
	while actor != null and not actor.has_node("GroundPresentation"):
		actor=actor.get_parent() as Node3D
	if actor == null: return _authored_rest.x
	var camera := caster.get_viewport().get_camera_3d() as Camera3D
	var presentation := actor.get_node_or_null("GroundPresentation")
	if camera == null or presentation == null: return _authored_rest.x
	var sprite := presentation.sprite as AnimatedSprite3D
	if sprite == null or sprite.sprite_frames == null or not sprite.sprite_frames.has_animation(&"Fishing_Idle"): return _authored_rest.x
	if actor != _stance_actor:
		# Sample the reference stance's lower body once, excluding rod/hair and
		# transparent sheet padding. Never follow a bite/reel animation's bounds.
		var image := sprite.sprite_frames.get_frame_texture(&"Fishing_Idle",0).get_image()
		if image == null: return _authored_rest.x
		if image.is_compressed() and image.decompress()!=OK: return _authored_rest.x
		var feet_y: float = image.get_height()-presentation.profile.feet_from_bottom_px
		var feet_x: float = presentation.profile.feet_from_left_px
		if feet_x<0.0: feet_x=image.get_width()*.5
		var body_top := maxi(0,int(feet_y-image.get_height()*.25))
		var right := feet_x
		for y in range(body_top,mini(image.get_height(),int(feet_y)+1)):
			for x in range(image.get_width()):
				if image.get_pixel(x,y).a>.1: right=maxf(right,x+1.0)
		_stance_pixels=Vector2(right-feet_x,(feet_y-body_top)*.5)
		_stance_actor = actor
	var scale_xy := sprite.global_basis.get_scale()
	var stance := sprite.global_position+camera.global_basis.x*_stance_pixels.x*sprite.pixel_size*scale_xy.x+camera.global_basis.y*_stance_pixels.y*sprite.pixel_size*scale_xy.y
	return camera.unproject_position(stance).x

func _set_slide_progress(value: float) -> void:
	_slide_progress = value
	root.position = _rest_position.lerp(_get_offscreen_bottom_position(),value)

func _on_power_started() -> void:
	distance_value.set_text("0")
	distance_decimal.set_text("0")
	_cancel_to_aim_pending = false
	showing_tension = false
	fight_tension_active = false
	
	tension_meter.visible = false
	fill.texture = bar_green
	_set_tension_color(
		(safe_color_min + safe_color_max) * 0.5
	)
	_set_fill(0.0)

	_slide_in_from_bottom()


func _on_power_stopped() -> void:
	# A cancel also stops the power mechanic, but it must NOT switch
	# the HUD into tension mode.
	if _cancel_to_aim_pending:
		return

	# The cast has been confirmed.
	# The same gauge now becomes the fishing/tension gauge.
	showing_tension = true
	fight_tension_active = false

	root.visible = true
	tension_meter.visible = true

	_set_fill(0.0)


func cancel_to_aim() -> void:
	_cancel_to_aim_pending = true
	showing_tension = false
	fight_tension_active = false
	
	tension_meter.visible = false
	fill.texture = bar_green
	_set_fill(0.0)

	_slide_out_to_bottom()


func _on_power_changed(value: float) -> void:
	if showing_tension:
		return

	_set_fill(value)


func _on_tension_changed(value: float) -> void:
	if not showing_tension:
		return

	_set_fill(value)

	if fight_tension_active:
		_set_tension_color(value)
	else:
		# No fish yet: always visually green.
		_set_tension_color(
			(safe_color_min + safe_color_max) * 0.5
		)

func _set_tension_color(value: float) -> void:
	var color: Color = safe_color

	# SAFE ZONE:
	# Stay completely green.
	if value >= safe_color_min and value <= safe_color_max:
		color = safe_color

	# LOW TENSION:
	# Quickly transition green -> blue after leaving SAFE.
	elif value < safe_color_min:
		var t := clampf(
			(safe_color_min - value)
			/ slack_color_transition,
			0.0,
			1.0
		)

		color = safe_color.lerp(
			slack_color,
			t
		)

	# HIGH TENSION:
	# Quickly transition green -> red after leaving SAFE.
	else:
		var t := clampf(
			(value - safe_color_max)
			/ overload_color_transition,
			0.0,
			1.0
		)

		color = safe_color.lerp(
			overload_color,
			t
		)

	var material := fill.material as ShaderMaterial

	if material != null:
		material.set_shader_parameter(
			"tint_color",
			color
		)
		
func _on_bait_returned() -> void:
	_cancel_to_aim_pending = false
	showing_tension = false
	fight_tension_active = false
	
	_set_fill(0.0)

	tension_meter.visible = false
	_slide_out_to_bottom()


func _set_fill(value: float) -> void:
	fill.scale.x = full_scale_x * clampf(value, 0.0, 1.0)


func _slide_in_from_bottom() -> void:
	_kill_slide_tween()

	_set_slide_progress(1.0)
	root.visible = true

	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_method(
		_set_slide_progress,
		1.0,
		0.0,
		slide_time
	)

	_slide_tween = tween


func _slide_out_to_bottom() -> void:
	_kill_slide_tween()

	if not root.visible:
		_cancel_to_aim_pending = false
		_set_slide_progress(0.0)
		return

	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN)
	tween.tween_method(
		_set_slide_progress,
		_slide_progress,
		1.0,
		slide_time
	)
	tween.tween_callback(_finish_cancel_slide_out)

	_slide_tween = tween


func _finish_cancel_slide_out() -> void:
	root.visible = false
	_set_slide_progress(0.0)
	_cancel_to_aim_pending = false
	_slide_tween = null


func _hide_immediate() -> void:
	_kill_slide_tween()
	root.visible = false
	_set_slide_progress(0.0)


func _kill_slide_tween() -> void:
	if _slide_tween != null and _slide_tween.is_valid():
		_slide_tween.kill()

	_slide_tween = null


func _get_offscreen_bottom_position() -> Vector2:
	# Work from the approved resting position, even if a tween is
	# currently part-way through.
	var rest_global_y := _rest_position.y
	var viewport_bottom := _layout_size.y

	var visual_height := maxf(root.size.y, 1.0)
	var shift_y := (
		viewport_bottom
		- rest_global_y
		+ visual_height
		+ slide_padding_px
	)

	return _rest_position + Vector2(
		0.0,
		maxf(shift_y, slide_padding_px)
	)

func reset_to_aim() -> void:
	_cancel_to_aim_pending = false
	showing_tension = false

	fill.texture = bar_green
	_set_fill(0.0)

	distance_value.set_text("0")
	distance_decimal.set_text("0")

	tension_meter.visible = false

	_hide_immediate()

func _on_fish_hooked() -> void:
	fight_tension_active = true
	_set_tension_color(
		(safe_color_min + safe_color_max) * 0.5
	)
