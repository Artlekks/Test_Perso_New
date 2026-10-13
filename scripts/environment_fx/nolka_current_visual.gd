extends Node3D
## Visual-only bridge to the locally installed Nolka's Breeze pack.
## Deliberately no preload/class-name dependency on third-party scripts.
## Fish and lure movement still come exclusively from FishingCurrentService.

const LEAVES_SCENE_PATH: String = "res://nolkas_breeze_vfx_v1.0/nolkas_breeze/vfx/premade/leaves_in_wind.tscn"

@export_category("Underwater Current Appearance")
@export_range(0.05, 1.0, 0.01) var visual_opacity: float = 0.24
@export_range(0.05, 0.5, 0.01) var visual_speed_scale: float = 0.15
@export_range(8, 160, 1) var particle_count: int = 46
@export_range(0.04, 0.35, 0.01) var line_thickness: float = 0.13
@export_range(0.1, 1.0, 0.05) var coverage_ratio: float = 0.82
## Godot -Z is forward. If the vendor preset's lines move the opposite
## way in your scene, toggle this without modifying the source pack.
@export var reverse_direction: bool = false

var _effect: Node3D = null
var _wind: Node = null
var _active: bool = false
var _warned_missing: bool = false
var _last_heading: Vector3 = Vector3(1.0, 0.0, 0.0)

func is_installed() -> bool:
	return ResourceLoader.exists(LEAVES_SCENE_PATH, "PackedScene")

func has_effect() -> bool:
	return is_instance_valid(_effect) and is_instance_valid(_wind)

func _ready() -> void:
	_mount()

func _mount() -> void:
	if has_effect():
		return
	if not is_installed():
		if not _warned_missing:
			push_warning("Nolka current effect not installed at: " + LEAVES_SCENE_PATH + ". Copy the entire purchased pack into the project; no other current trails will be drawn.")
			_warned_missing = true
		return
	var resource: Resource = load(LEAVES_SCENE_PATH)
	var scene: PackedScene = resource as PackedScene
	if scene == null:
		push_error("Nolka LeavesInWind is not a PackedScene: " + LEAVES_SCENE_PATH)
		return
	var instance: Node = scene.instantiate()
	var effect: Node3D = instance as Node3D
	if effect == null:
		instance.free()
		push_error("Nolka LeavesInWind root must be Node3D")
		return
	# Delete debris nodes BEFORE entering the SceneTree. The original wind
	# controller and its original procedural GPU emitter remain untouched.
	for leaf_name in ["OrangeLeaves", "GreenLeaves", "RedLeaves"]:
		var debris: Node = effect.get_node_or_null(NodePath(leaf_name))
		if debris != null:
			effect.remove_child(debris)
			debris.free()
	var line_emitter: Node = effect.get_node_or_null("Wind")
	if line_emitter == null:
		effect.free()
		push_error("Nolka LeavesInWind has no Wind child")
		return
	_effect = effect
	_wind = line_emitter
	effect.name = "NolkaCurrentLines"
	add_child(effect)
	# Apply after _ready: vendor composite discovers its children there.
	_wind.set("color", Color(0.70, 0.89, 0.91, visual_opacity))
	_wind.set("sway_thickness", line_thickness)
	_wind.set("sway_duration", 0.75)
	_wind.set("min_speed", 5.0)
	_wind.set("max_speed", 12.0)
	_wind.set("min_turbulence_amplitude", 0.02)
	_wind.set("max_turbulence_amplitude", 0.08)
	_wind.set("particles_amount", particle_count)
	# Do not set amount_ratio: the composite would reset our chosen count to its demo default.
	_effect.set("speed_scale", visual_speed_scale)
	set_active(_active)

func set_active(value: bool) -> void:
	_active = value
	if not has_effect():
		return
	_effect.visible = value
	_effect.set("emitting", value)
	_wind.set("emitting", value)

func update_environment(current_service: FishingCurrentService, bounds: FishSwimBounds, water_y: float, _delta: float) -> void:
	if not has_effect() or current_service == null or bounds == null:
		return
	var center: Vector3 = bounds.normalized_uv_to_world(Vector2(0.5, 0.5), water_y)
	var flow: Vector3 = current_service.sample_current_velocity(center)
	flow.y = 0.0
	var strength: float = flow.length()
	if strength <= 0.001:
		set_active(false)
		return
	var direction: Vector3 = flow / strength
	_last_heading = direction
	if reverse_direction:
		direction = -direction
	# Project the authored rectangular swim area onto flow and cross-flow
	# axes, so rotated beaches and different-sized zones remain supported.
	var world_u: Vector3 = bounds.normalized_uv_to_world(Vector2(1.0, 0.5), water_y) - bounds.normalized_uv_to_world(Vector2(0.0, 0.5), water_y)
	var world_v: Vector3 = bounds.normalized_uv_to_world(Vector2(0.5, 1.0), water_y) - bounds.normalized_uv_to_world(Vector2(0.5, 0.0), water_y)
	var across: Vector3 = Vector3(-direction.z, 0.0, direction.x)
	var width: float = (absf(world_u.dot(across)) + absf(world_v.dot(across))) * coverage_ratio
	var length: float = (absf(world_u.dot(direction)) + absf(world_v.dot(direction))) * coverage_ratio
	var area: Vector3 = Vector3(maxf(width, 1.0), 0.06, maxf(length, 1.0))
	# The beach sea is opaque. Place an extremely shallow particle layer just
	# above its surface to READ as submerged. Truly underwater particles would
	# be completely hidden by the opaque sea material.
	_effect.global_position = Vector3(center.x, water_y + 0.055, center.z)
	_effect.global_basis = Basis.looking_at(direction, Vector3.UP)
	_effect.set("area", area)
	# Stronger water movement raises the visual travel rate; the current
	# simulation itself remains authoritative and untouched.
	var target_speed: float = clampf(visual_speed_scale * clampf(strength / 0.25, 0.50, 1.80), 0.05, 0.40)
	if absf(float(_effect.get("speed_scale")) - target_speed) > 0.012:
		_effect.set("speed_scale", target_speed)
	# Never write to current_service, fish encounters or the bait.
	if _active:
		_effect.visible = true
		_effect.set("emitting", true)
		_wind.set("emitting", true)
