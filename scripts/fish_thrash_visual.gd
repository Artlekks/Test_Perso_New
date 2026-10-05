extends Node
class_name FishingThrashVisual

## Screen-space presentation for fish breaches/thrashes.
##
## The authored fish strip is deliberately drawn in CanvasLayer space so it can
## never disappear behind the water mesh or suffer from 3D transparent sorting.
## Its anchor still comes from the REAL 3D fishing-line/water intersection and is
## projected through the active fishing camera at the instant the event starts.
## Gameplay values are never changed here.

@export var encounter: Node
@export var fishing_line_view: Node3D
@export var caster: Node
@export_range(1.0, 2.5, 0.05) var minimum_scale: float = 1.35
@export_range(1.0, 2.5, 0.05) var maximum_scale: float = 1.60
@export_range(8.0, 40.0, 1.0) var jump_height_pixels: float = 22.0
@export_range(0, 250, 5) var retrigger_guard_ms: int = 90
@export var waterline_screen_offset: Vector2 = Vector2(0.0, -2.0)

@onready var animated_sprite: AnimatedSprite2D = $CanvasLayer/AnimatedSprite2D

const ANIMATION_DURATION_SECONDS: float = 8.0 / 12.0

var _last_trigger_ms: int = -1000000
var _jump_elapsed: float = 0.0
var _base_screen_position: Vector2 = Vector2.ZERO
var _jump_active: bool = false


func _ready() -> void:
	set_process(false)
	if animated_sprite != null:
		animated_sprite.visible = false
		animated_sprite.animation_finished.connect(_on_animation_finished)

	if encounter == null:
		return
	if encounter.has_signal("fish_resistance_started"):
		encounter.connect("fish_resistance_started", _on_fish_resistance_started)
	if encounter.has_signal("fish_thrash_started"):
		encounter.connect("fish_thrash_started", _on_fish_thrash_started)
	if encounter.has_signal("fish_aerial_started"):
		encounter.connect("fish_aerial_started", _on_fish_aerial_started)


func _process(delta: float) -> void:
	if not _jump_active or animated_sprite == null:
		return
	_jump_elapsed += delta
	var t: float = clampf(_jump_elapsed / ANIMATION_DURATION_SECONDS, 0.0, 1.0)
	var arc_y: float = -sin(t * PI) * jump_height_pixels
	animated_sprite.position = _base_screen_position + Vector2(0.0, arc_y)


func _on_fish_resistance_started() -> void:
	# This is the exact event that produces the existing "The fish is thrashing
	# about!" message. Every resistance round therefore receives a visible jump.
	_play_surface_jump(0.82)


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

	var world_entry: Vector3 = _get_line_water_entry_position()
	var active_camera: Camera3D = get_viewport().get_camera_3d()
	if active_camera == null:
		return
	if active_camera.is_position_behind(world_entry):
		return

	_last_trigger_ms = now_ms
	_base_screen_position = active_camera.unproject_position(world_entry) + waterline_screen_offset
	_jump_elapsed = 0.0
	_jump_active = true

	var visual_scale: float = lerpf(minimum_scale, maximum_scale, intensity)
	animated_sprite.scale = Vector2.ONE * visual_scale
	animated_sprite.flip_h = _should_flip_from_fight_direction()
	animated_sprite.position = _base_screen_position
	animated_sprite.visible = true
	animated_sprite.frame = 0
	animated_sprite.play(&"thrash_jump")
	set_process(true)


func _get_line_water_entry_position() -> Vector3:
	if (
		is_instance_valid(fishing_line_view)
		and fishing_line_view.has_method("has_surface_entry")
		and bool(fishing_line_view.call("has_surface_entry"))
		and fishing_line_view.has_method("get_surface_entry_position")
	):
		var line_position: Vector3 = fishing_line_view.call("get_surface_entry_position")
		return line_position

	if is_instance_valid(caster) and caster.has_method("get_active_bait_visual_surface_position"):
		var visual_surface_position: Vector3 = caster.call("get_active_bait_visual_surface_position")
		return visual_surface_position

	if is_instance_valid(caster) and caster.has_method("get_active_bait_surface_position"):
		var surface_position: Vector3 = caster.call("get_active_bait_surface_position")
		return surface_position

	return Vector3.ZERO


func _should_flip_from_fight_direction() -> bool:
	if not is_instance_valid(encounter):
		return false
	var lateral_value: Variant = encounter.get("current_fish_lateral")
	if lateral_value is float or lateral_value is int:
		return float(lateral_value) > 0.0
	return false


func _on_animation_finished() -> void:
	_jump_active = false
	set_process(false)
	if animated_sprite != null:
		animated_sprite.visible = false
