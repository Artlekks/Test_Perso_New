extends Node3D
class_name FishingCurrentSurfaceView

## Presentation-only current reading. Physics is owned by FishingCurrentService;
## mastery only makes the authored water behavior legible to the player.

const STREAK_COUNT: int = 15
const DRIFT_MARKER_COUNT: int = 6
const CAPABILITY_READ_CURRENT: StringName = &"read_current"
const CAPABILITY_DRIFT_CASTING: StringName = &"current_compensation"

var _current_service: FishingCurrentService = null
var _mastery_service: FishingMasteryService = null
var _swim_bounds: FishSwimBounds = null
var _caster: Node = null
var _water_y: float = 0.0
var _streaks: Array[MeshInstance3D] = []
var _uvs: Array[Vector2] = []
var _drift_markers: Array[MeshInstance3D] = []
var _enabled: bool = false
@export_category("Flow Presentation")
@export_range(0.01, 1.0, 0.01) var flow_speed := 0.18
@export_range(0.0, 0.2, 0.005) var wave_amplitude := 0.035
@export_range(0.1, 2.0, 0.05) var wave_wavelength := 0.4
@export_range(0.0, 4.0, 0.1) var wave_phase_speed := 1.2
var _flows := PackedVector3Array()
const FLOW_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform float amplitude = 0.035;
uniform float wavelength = 0.4;
uniform float phase_speed = 1.2;
uniform float phase_offset = 0.0;
uniform vec4 tint : source_color = vec4(0.78, 0.94, 1.0, 0.3);
void vertex() {
    float envelope = sin(UV.x * 3.14159265);
    VERTEX.z += sin(VERTEX.x * 6.2831853 / wavelength - TIME * phase_speed + phase_offset) * amplitude * envelope;
}
void fragment() {
    ALBEDO = tint.rgb;
    ALPHA = tint.a;
}
"""


func _ready() -> void:
	_build_streaks()
	_build_drift_markers()
	_refresh_visibility()


func configure(
	current_service: FishingCurrentService,
	mastery_service: FishingMasteryService
) -> void:
	_current_service = current_service
	_mastery_service = mastery_service
	if _mastery_service != null:
		var callback := Callable(self, "_on_mastery_changed")
		if not _mastery_service.mastery_changed.is_connected(callback):
			_mastery_service.mastery_changed.connect(callback)
	_refresh_visibility()


func bind_caster(caster: Node) -> void:
	_caster = caster


func bind_zone(zone: Node) -> void:
	_swim_bounds = null
	_water_y = 0.0
	if zone != null:
		if zone.has_method("get_swim_bounds"):
			_swim_bounds = zone.get_swim_bounds() as FishSwimBounds
		if zone.has_method("get_water_y"):
			_water_y = float(zone.get_water_y()) + 0.025
	_refresh_visibility()


func _process(delta: float) -> void:
	if not _enabled or _swim_bounds == null or _current_service == null:
		_hide_drift_markers()
		return
	_update_streaks(delta)
	_update_drift_preview()


func _update_streaks(delta: float = 0.0) -> void:
	var snapshot := _current_service.get_snapshot()
	var reference_speed := maxf(float(snapshot.get("speed", 0.04)), 0.025)
	var visual_strength := clampf(float(snapshot.get("visual_strength", 0.5)), 0.1, 1.0)
	var world_u := _swim_bounds.normalized_uv_to_world(Vector2(1, 0.5), _water_y) - _swim_bounds.normalized_uv_to_world(Vector2(0, 0.5), _water_y)
	var world_v := _swim_bounds.normalized_uv_to_world(Vector2(0.5, 1), _water_y) - _swim_bounds.normalized_uv_to_world(Vector2(0.5, 0), _water_y)
	for index in range(_streaks.size()):
		var streak := _streaks[index]
		if streak == null:
			continue
		var base_uv := _uvs[index]
		var center := _swim_bounds.normalized_uv_to_world(base_uv, _water_y)
		_flows[index] = _current_service.smooth_current_velocity(_flows[index], center, delta)
		var local_flow := _flows[index]
		var speed := local_flow.length()
		if speed <= 0.002:
			streak.visible = false
			continue
		var direction := local_flow.normalized()
		var speed_ratio := clampf(speed / reference_speed, 0.25, 2.4)
		streak.visible = true
		var travel := direction * flow_speed * speed_ratio * delta
		var uv := base_uv + Vector2(travel.dot(world_u) / maxf(world_u.length_squared(), 0.001), travel.dot(world_v) / maxf(world_v.length_squared(), 0.001))
		uv = Vector2(wrapf(uv.x, 0.0, 1.0), wrapf(uv.y, 0.0, 1.0))
		_uvs[index] = uv
		streak.global_position = _swim_bounds.normalized_uv_to_world(uv, _water_y)
		# The shared current filter already smooths heading: do not introduce a
		# second visual lag that could point against the physical drift.
		streak.rotation.y = -atan2(direction.z, direction.x)
		streak.scale = Vector3(clampf(0.72 + speed_ratio * 0.28, 0.7, 1.45), 1.0, 1.0)
		var material := streak.material_override as ShaderMaterial
		if material != null:
			var alpha := clampf((0.20 + speed_ratio * 0.13) * visual_strength, 0.12, 0.62)
			var edge_fade := clampf(minf(minf(uv.x, 1.0 - uv.x), minf(uv.y, 1.0 - uv.y)) / 0.06, 0.0, 1.0)
			material.set_shader_parameter("tint", Color(0.78, 0.94, 1.0, alpha * edge_fade))
			material.set_shader_parameter("amplitude", wave_amplitude)
			material.set_shader_parameter("wavelength", wave_wavelength)
			material.set_shader_parameter("phase_speed", wave_phase_speed)


func _update_drift_preview() -> void:
	if (
		_mastery_service == null
		or not _mastery_service.has_capability(CAPABILITY_DRIFT_CASTING)
		or _caster == null
		or not _caster.has_method("is_active_bait_in_water")
		or not bool(_caster.call("is_active_bait_in_water"))
		or not _caster.has_method("get_active_bait_world_position")
	):
		_hide_drift_markers()
		return

	var start: Vector3 = _caster.call("get_active_bait_world_position")
	var path := _current_service.project_drift_path(start, 2.4, 0.4)
	for index in range(_drift_markers.size()):
		var marker := _drift_markers[index]
		var path_index := index + 1
		if marker == null or path_index >= path.size():
			if marker != null:
				marker.visible = false
			continue
		var point := path[path_index]
		point.y = _water_y + 0.012
		marker.global_position = point
		marker.visible = true


func _build_streaks() -> void:
	if not _streaks.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 918273
	var shader := Shader.new()
	shader.code = FLOW_SHADER
	for index in range(STREAK_COUNT):
		var streak := MeshInstance3D.new()
		streak.name = "CurrentStreak%02d" % index
		var mesh := PlaneMesh.new()
		mesh.size = Vector2(0.6, 0.014)
		mesh.subdivide_width = 12
		var material := ShaderMaterial.new()
		material.shader = shader
		material.set_shader_parameter("phase_offset", rng.randf_range(0.0, TAU))
		streak.mesh = mesh
		streak.material_override = material
		add_child(streak)
		_streaks.append(streak)
		_uvs.append(Vector2(rng.randf_range(0.08, 0.92), rng.randf_range(0.07, 0.90)))
		_flows.append(Vector3.ZERO)


func _build_drift_markers() -> void:
	if not _drift_markers.is_empty():
		return
	for index in range(DRIFT_MARKER_COUNT):
		var marker := MeshInstance3D.new()
		marker.name = "DriftPrediction%02d" % index
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.045, 0.004, 0.045)
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color = Color(1.0, 0.86, 0.45, 0.48 - float(index) * 0.045)
		marker.mesh = mesh
		marker.material_override = material
		marker.visible = false
		add_child(marker)
		_drift_markers.append(marker)


func _hide_drift_markers() -> void:
	for marker in _drift_markers:
		if marker != null:
			marker.visible = false


func _refresh_visibility() -> void:
	_enabled = (
		_swim_bounds != null
		and _current_service != null
		and bool(_current_service.get_snapshot().get("active", false))
		and _mastery_service != null
		and _mastery_service.has_capability(CAPABILITY_READ_CURRENT)
	)
	set_process(_enabled)
	if not _enabled:
		for streak in _streaks:
			if streak != null:
				streak.visible = false
		_hide_drift_markers()


func _on_mastery_changed(_snapshot: Dictionary) -> void:
	_refresh_visibility()
