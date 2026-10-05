extends Node
class_name FishingThrashVisual

## Screen-space fish breach presentation.
##
## The fish starts from the bait head's projected surface position, because that
## is the point the player actually reads as the hooked fish/lure location in the
## fishing camera. The procedural line/water split remains a fallback only.
## Entry/landing splashes are presentation only and do not alter fight logic.

@export var encounter: Node
@export var fishing_line_view: Node3D
@export var caster: Node
@export_range(0.75, 2.5, 0.05) var minimum_scale: float = 1.45
@export_range(0.75, 2.5, 0.05) var maximum_scale: float = 1.65
@export_range(8.0, 64.0, 1.0) var jump_height_pixels: float = 30.0
@export_range(0.0, 48.0, 1.0) var horizontal_travel_pixels: float = 15.0
@export_range(0, 250, 5) var retrigger_guard_ms: int = 90
@export var waterline_screen_offset: Vector2 = Vector2(0.0, -1.0)

@onready var canvas_layer: CanvasLayer = $CanvasLayer
@onready var animated_sprite: AnimatedSprite2D = $CanvasLayer/AnimatedSprite2D

const ANIMATION_DURATION_SECONDS: float = 8.0 / 12.0
const SCREEN_MARGIN_PIXELS: float = 12.0
const ENTRY_ROTATION_DEGREES: float = -28.0
const LANDING_ROTATION_DEGREES: float = 62.0

var _last_trigger_ms: int = -1000000
var _jump_elapsed: float = 0.0
var _base_screen_position: Vector2 = Vector2.ZERO
var _landing_screen_position: Vector2 = Vector2.ZERO
var _jump_direction: float = 1.0
var _base_visual_scale: float = 1.0
var _jump_active: bool = false


func _ready() -> void:
	set_process(false)
	if animated_sprite != null:
		animated_sprite.visible = false
		animated_sprite.animation_finished.connect(_on_animation_finished)

	if encounter == null:
		return
	# Normal resistance rounds are fired explicitly by FishingInfoController from
	# the same code path that prints "The fish is thrashing about!".
	if encounter.has_signal("fish_thrash_started"):
		encounter.connect("fish_thrash_started", _on_fish_thrash_started)
	if encounter.has_signal("fish_aerial_started"):
		encounter.connect("fish_aerial_started", _on_fish_aerial_started)


func _process(delta: float) -> void:
	if not _jump_active or animated_sprite == null:
		return

	_jump_elapsed += delta
	var t: float = clampf(_jump_elapsed / ANIMATION_DURATION_SECONDS, 0.0, 1.0)
	var smooth_t: float = t * t * (3.0 - 2.0 * t)
	var arc_y: float = -sin(t * PI) * jump_height_pixels
	var travel_x: float = horizontal_travel_pixels * _jump_direction * smooth_t

	animated_sprite.position = _base_screen_position + Vector2(travel_x, arc_y)
	animated_sprite.rotation_degrees = lerpf(
		ENTRY_ROTATION_DEGREES,
		LANDING_ROTATION_DEGREES,
		smooth_t
	) * _jump_direction
	var scale_pulse: float = 1.0 + sin(t * PI) * 0.045
	animated_sprite.scale = Vector2.ONE * _base_visual_scale * scale_pulse


func play_resistance_jump() -> void:
	_play_surface_jump(0.90)


func _on_fish_thrash_started(intensity: float) -> void:
	_play_surface_jump(clampf(intensity, 0.0, 1.0))


func _on_fish_aerial_started(snapshot: Dictionary) -> void:
	var intensity: float = clampf(float(snapshot.get("intensity", 0.75)), 0.0, 1.0)
	_play_surface_jump(intensity)


func _play_surface_jump(intensity: float) -> void:
	if animated_sprite == null or animated_sprite.sprite_frames == null:
		return

	var now_ms: int = Time.get_ticks_msec()
	if now_ms - _last_trigger_ms < retrigger_guard_ms:
		return

	var active_camera: Camera3D = get_viewport().get_camera_3d()
	if active_camera == null:
		return

	var anchor_result: Dictionary = _resolve_screen_anchor(active_camera)
	if not bool(anchor_result.get("valid", false)):
		return

	_last_trigger_ms = now_ms
	_base_screen_position = Vector2(anchor_result.get("position", Vector2.ZERO)) + waterline_screen_offset
	_jump_elapsed = 0.0
	_jump_active = true

	var flip_fish: bool = _should_flip_from_fight_direction()
	_jump_direction = -1.0 if flip_fish else 1.0
	_base_visual_scale = lerpf(
		minimum_scale,
		maximum_scale,
		clampf(intensity, 0.0, 1.0)
	)
	_landing_screen_position = _base_screen_position + Vector2(
		horizontal_travel_pixels * _jump_direction,
		0.0
	)

	_spawn_pixel_splash(_base_screen_position, 0.72)

	animated_sprite.stop()
	animated_sprite.scale = Vector2.ONE * _base_visual_scale
	animated_sprite.flip_h = flip_fish
	animated_sprite.position = _base_screen_position
	animated_sprite.rotation_degrees = ENTRY_ROTATION_DEGREES * _jump_direction
	animated_sprite.frame = 0
	animated_sprite.visible = true
	animated_sprite.play(&"thrash_jump")
	set_process(true)


func _resolve_screen_anchor(active_camera: Camera3D) -> Dictionary:
	var candidates: Array[Vector3] = []

	# First choice: exact bait-head screen alignment projected onto the surface.
	if is_instance_valid(caster) and caster.has_method("get_active_bait_visual_surface_position"):
		var bait_visual_surface: Vector3 = caster.call("get_active_bait_visual_surface_position")
		candidates.append(bait_visual_surface)

	# Fallback: physical line/water split.
	if (
		is_instance_valid(fishing_line_view)
		and fishing_line_view.has_method("has_surface_entry")
		and bool(fishing_line_view.call("has_surface_entry"))
		and fishing_line_view.has_method("get_surface_entry_position")
	):
		var line_position: Vector3 = fishing_line_view.call("get_surface_entry_position")
		candidates.append(line_position)

	if is_instance_valid(caster) and caster.has_method("get_active_bait_surface_position"):
		var surface_position: Vector3 = caster.call("get_active_bait_surface_position")
		candidates.append(surface_position)

	if is_instance_valid(caster) and caster.has_method("get_active_bait_world_position"):
		var bait_position: Vector3 = caster.call("get_active_bait_world_position")
		candidates.append(bait_position)

	var visible_rect: Rect2 = get_viewport().get_visible_rect()
	var expanded_rect: Rect2 = visible_rect.grow(24.0)

	for candidate: Vector3 in candidates:
		if active_camera.is_position_behind(candidate):
			continue
		var projected: Vector2 = active_camera.unproject_position(candidate)
		if expanded_rect.has_point(projected):
			return {
				"valid": true,
				"position": _clamp_to_visible_rect(projected, visible_rect),
			}

	for candidate: Vector3 in candidates:
		if active_camera.is_position_behind(candidate):
			continue
		var projected: Vector2 = active_camera.unproject_position(candidate)
		return {
			"valid": true,
			"position": _clamp_to_visible_rect(projected, visible_rect),
		}

	return {
		"valid": false,
		"position": Vector2.ZERO,
	}


func _clamp_to_visible_rect(point: Vector2, visible_rect: Rect2) -> Vector2:
	var min_x: float = visible_rect.position.x + SCREEN_MARGIN_PIXELS
	var max_x: float = visible_rect.position.x + visible_rect.size.x - SCREEN_MARGIN_PIXELS
	var min_y: float = visible_rect.position.y + SCREEN_MARGIN_PIXELS
	var max_y: float = visible_rect.position.y + visible_rect.size.y - SCREEN_MARGIN_PIXELS
	return Vector2(
		clampf(point.x, min_x, max_x),
		clampf(point.y, min_y, max_y)
	)


func _should_flip_from_fight_direction() -> bool:
	if not is_instance_valid(encounter):
		return false
	var lateral_value: Variant = encounter.get("current_fish_lateral")
	if lateral_value is float or lateral_value is int:
		return float(lateral_value) > 0.0
	return false


func _spawn_pixel_splash(screen_position: Vector2, strength: float) -> void:
	if canvas_layer == null:
		return

	var root := Node2D.new()
	root.position = screen_position
	root.z_index = 90
	canvas_layer.add_child(root)

	var ripple := Line2D.new()
	ripple.width = 1.0
	ripple.default_color = Color(0.84, 0.96, 1.0, 0.90)
	ripple.points = PackedVector2Array([
		Vector2(-5.0, 0.0),
		Vector2(5.0, 0.0),
	])
	root.add_child(ripple)

	var ripple_tween := ripple.create_tween()
	ripple.scale = Vector2(0.45, 1.0)
	ripple_tween.set_parallel(true)
	ripple_tween.tween_property(ripple, "scale", Vector2(1.8, 1.0), 0.28)
	ripple_tween.tween_property(ripple, "modulate:a", 0.0, 0.28)

	var directions: Array[Vector2] = [
		Vector2(-7.0, -8.0),
		Vector2(-3.0, -11.0),
		Vector2(0.0, -13.0),
		Vector2(4.0, -10.0),
		Vector2(8.0, -7.0),
	]
	for index in range(directions.size()):
		var droplet := Polygon2D.new()
		var droplet_size: float = 1.2 + float(index % 2) * 0.5
		droplet.polygon = PackedVector2Array([
			Vector2(0.0, -droplet_size),
			Vector2(droplet_size, 0.0),
			Vector2(0.0, droplet_size),
			Vector2(-droplet_size, 0.0),
		])
		droplet.color = Color(0.86, 0.97, 1.0, 0.94)
		root.add_child(droplet)
		var destination: Vector2 = directions[index] * clampf(strength, 0.4, 1.2)
		var droplet_tween := droplet.create_tween()
		droplet_tween.set_parallel(true)
		droplet_tween.tween_property(droplet, "position", destination, 0.22)
		droplet_tween.tween_property(droplet, "modulate:a", 0.0, 0.26)

	var cleanup := root.create_tween()
	cleanup.tween_interval(0.31)
	cleanup.tween_callback(Callable(root, "queue_free"))


func _on_animation_finished() -> void:
	if _jump_active:
		_spawn_pixel_splash(_landing_screen_position, 1.0)
	_jump_active = false
	set_process(false)
	if animated_sprite != null:
		animated_sprite.visible = false
		animated_sprite.rotation = 0.0
