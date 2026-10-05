extends Node3D
class_name FishingThrashVisual

## Presentation-only fish breach/thrash sprite.
## It listens to Encounter's existing authored fight events and positions the
## one-shot animation at the fishing line's actual water-plane entry point.
## No fight values are changed here.

@export var encounter: Node
@export var fishing_line_view: Node3D
@export var caster: Node
@export_range(0.0, 0.25, 0.005) var surface_height_offset: float = 0.035
@export_range(0.5, 2.0, 0.05) var minimum_scale: float = 0.90
@export_range(0.5, 2.0, 0.05) var maximum_scale: float = 1.10
@export_range(0, 250, 5) var retrigger_guard_ms: int = 80

@onready var animated_sprite: AnimatedSprite3D = $AnimatedSprite3D

var _last_trigger_ms: int = -1000000


func _ready() -> void:
	if animated_sprite != null:
		animated_sprite.visible = false
		animated_sprite.animation_finished.connect(_on_animation_finished)

	if encounter == null:
		return

	if encounter.has_signal("fish_thrash_started"):
		encounter.connect("fish_thrash_started", _on_fish_thrash_started)

	# Aerial Fish Control previously had only splash feedback because there was
	# no authored fish art. The supplied jump strip now gives those genuine
	# breaches a fish visual too.
	if encounter.has_signal("fish_aerial_started"):
		encounter.connect("fish_aerial_started", _on_fish_aerial_started)


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
	_last_trigger_ms = now_ms

	global_position = _get_line_water_entry_position()
	global_position.y += surface_height_offset

	var visual_scale: float = lerpf(minimum_scale, maximum_scale, intensity)
	animated_sprite.scale = Vector3.ONE * visual_scale
	animated_sprite.flip_h = _should_flip_from_fight_direction()
	animated_sprite.visible = true
	animated_sprite.frame = 0
	animated_sprite.play(&"thrash_jump")


func _get_line_water_entry_position() -> Vector3:
	if (
		is_instance_valid(fishing_line_view)
		and fishing_line_view.has_method("has_surface_entry")
		and bool(fishing_line_view.call("has_surface_entry"))
		and fishing_line_view.has_method("get_surface_entry_position")
	):
		var line_position: Vector3 = fishing_line_view.call("get_surface_entry_position")
		return line_position

	if (
		is_instance_valid(caster)
		and caster.has_method("get_active_bait_visual_surface_position")
	):
		var visual_surface_position: Vector3 = caster.call(
			"get_active_bait_visual_surface_position"
		)
		return visual_surface_position

	if is_instance_valid(caster) and caster.has_method("get_active_bait_surface_position"):
		var surface_position: Vector3 = caster.call("get_active_bait_surface_position")
		return surface_position

	return global_position


func _should_flip_from_fight_direction() -> bool:
	if not is_instance_valid(encounter):
		return false

	var lateral_value: Variant = encounter.get("current_fish_lateral")
	if lateral_value is float or lateral_value is int:
		return float(lateral_value) > 0.0
	return false


func _on_animation_finished() -> void:
	if animated_sprite != null:
		animated_sprite.visible = false
