extends Node3D
## Visual-only world wind built from the purchased Nolka Breeze preset.
## Direction and strength are read from /root/GameWind. This node never writes
## wind state or changes the player's camera, fishing physics, or UI.

@export_category("World Binding")
@export var sea_mesh_path: NodePath = ^"../beach/Sea"
@export var display_wind: bool = true

@export_category("Nolka Air Wind")
@export_range(0.01, 1.0, 0.01) var opacity: float = 0.18
@export_range(8, 120, 1) var particles: int = 35
@export_range(0.02, 1.0, 0.01) var line_width: float = 0.14
@export_range(0.1, 2.5, 0.05) var trail_duration: float = 0.65
@export_range(1.0, 20.0, 0.5) var min_line_speed: float = 5.0
@export_range(1.0, 25.0, 0.5) var max_line_speed: float = 10.0
@export_range(0.0, 10.0, 0.1) var min_turbulence: float = 1.5
@export_range(0.0, 15.0, 0.1) var max_turbulence: float = 3.0

@export_category("Wind Response")
@export_range(0.0, 2.0, 0.05) var calm_cutoff_mps: float = 0.20
@export_range(0.05, 2.0, 0.05) var low_wind_playback: float = 0.20
@export_range(0.05, 2.0, 0.05) var high_wind_playback: float = 0.85
@export_range(1.0, 20.0, 0.5) var wind_at_full_speed_mps: float = 7.0

@export_category("Air Volume")
@export_range(0.25, 8.0, 0.25) var height_above_sea: float = 2.5
@export_range(0.5, 12.0, 0.25) var air_height: float = 3.5
@export_range(0.0, 10.0, 0.5) var shore_margin: float = 4.0

const POLL_SECONDS: float = 0.25

var _poll_elapsed: float = 0.0
var _emitter: Node3D = null
var _sea: MeshInstance3D = null
var _last_appearance: Array = []

func _ready() -> void:
	_emitter = get_node_or_null("NolkaWindLines") as Node3D
	if _emitter == null or not _emitter.has_method("update_parameters"):
		push_error("FishingWindVFX: the purchased Nolka Breeze emitter is missing.")
		set_process(false)
		return
	_apply_appearance()
	_set_emitting(false)
	set_process(true)

func _process(delta: float) -> void:
	_poll_elapsed += delta
	if _poll_elapsed < POLL_SECONDS:
		return
	_poll_elapsed = 0.0
	var wind: Node = get_tree().root.get_node_or_null("GameWind")
	if wind == null or not wind.has_method("get_snapshot"):
		_set_emitting(false)
		return
	var snapshot: Dictionary = wind.call("get_snapshot") as Dictionary
	_update_from_snapshot(snapshot)

func _update_from_snapshot(snapshot: Dictionary) -> void:
	if _emitter == null or not display_wind or not bool(snapshot.get("available", false)):
		_set_emitting(false)
		return
	var speed: float = maxf(0.0, float(snapshot.get("speed_mps", 0.0)))
	var velocity: Vector2 = snapshot.get("velocity_xz", Vector2.ZERO)
	if speed < calm_cutoff_mps or velocity.length_squared() < 0.000001:
		_set_emitting(false)
		return

	var heading: Vector3 = Vector3(velocity.x, 0.0, velocity.y).normalized()
	var volume: Dictionary = _get_air_volume(heading)
	_emitter.global_position = volume["center"] as Vector3
	# Nolka's shader sends its trails along LOCAL +Z, not camera -Z.
	_emitter.global_basis = Basis.looking_at(-heading, Vector3.UP)
	var area: Vector3 = volume["area"] as Vector3
	var previous: Vector3 = _emitter.get("area") as Vector3
	if not previous.is_equal_approx(area):
		_emitter.set("area", area)

	_apply_appearance()
	var strength: float = clampf(speed / maxf(wind_at_full_speed_mps, 0.1), 0.0, 1.0)
	var playback: float = lerpf(low_wind_playback, high_wind_playback, strength)
	if absf(float(_emitter.get("speed_scale")) - playback) > 0.015:
		_emitter.set("speed_scale", playback)
	_set_emitting(true)

func _get_air_volume(heading: Vector3) -> Dictionary:
	if not is_instance_valid(_sea):
		_sea = get_node_or_null(sea_mesh_path) as MeshInstance3D
	if _sea == null or _sea.mesh == null:
		return {"center": global_position + Vector3.UP * height_above_sea, "area": Vector3(18.0, air_height, 18.0)}
	var bounds: AABB = _sea.get_aabb()
	var across: Vector3 = Vector3(-heading.z, 0.0, heading.x)
	var first: bool = true
	var min_side: float = 0.0
	var max_side: float = 0.0
	var min_forward: float = 0.0
	var max_forward: float = 0.0
	var mean_y: float = 0.0
	for x in [bounds.position.x, bounds.end.x]:
		for z in [bounds.position.z, bounds.end.z]:
			var world_point: Vector3 = _sea.to_global(Vector3(x, bounds.get_center().y, z))
			mean_y += world_point.y * 0.25
			var side: float = world_point.dot(across)
			var forward: float = world_point.dot(heading)
			if first:
				min_side = side
				max_side = side
				min_forward = forward
				max_forward = forward
				first = false
			else:
				min_side = minf(min_side, side)
				max_side = maxf(max_side, side)
				min_forward = minf(min_forward, forward)
				max_forward = maxf(max_forward, forward)
	var center: Vector3 = across * ((min_side + max_side) * 0.5) + heading * ((min_forward + max_forward) * 0.5)
	center.y = mean_y + height_above_sea
	return {
		"center": center,
		"area": Vector3(maxf(max_side - min_side + shore_margin * 2.0, 6.0), air_height, maxf(max_forward - min_forward + shore_margin * 2.0, 6.0))
	}

func _apply_appearance() -> void:
	if _emitter == null:
		return
	var values: Array = [opacity, particles, line_width, trail_duration, min_line_speed, max_line_speed, min_turbulence, max_turbulence]
	if values == _last_appearance:
		return
	_last_appearance = values.duplicate()
	_emitter.set("color", Color(0.78, 0.87, 0.90, opacity))
	_emitter.set("particles_amount", particles)
	_emitter.set("sway_thickness", line_width)
	_emitter.set("sway_duration", trail_duration)
	# Set the lower bound first to avoid the vendor's setter clamping it to
	# a stale maximum during live Inspector edits.
	_emitter.set("min_speed", min_line_speed)
	_emitter.set("max_speed", maxf(max_line_speed, min_line_speed))
	_emitter.set("min_turbulence_amplitude", min_turbulence)
	_emitter.set("max_turbulence_amplitude", maxf(max_turbulence, min_turbulence))
	var gpu: GPUParticles3D = _emitter.get_node_or_null("SwayEmitter") as GPUParticles3D
	if gpu != null:
		gpu.extra_cull_margin = 3.0

func _set_emitting(active: bool) -> void:
	if _emitter == null:
		return
	_emitter.visible = active
	if bool(_emitter.get("emitting")) != active:
		_emitter.set("emitting", active)

func is_wind_display_running() -> bool:
	return _emitter != null and _emitter.visible and bool(_emitter.get("emitting"))
