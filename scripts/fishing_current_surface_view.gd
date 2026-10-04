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
var _phases: PackedFloat32Array = PackedFloat32Array()
var _drift_markers: Array[MeshInstance3D] = []
var _clock: float = 0.0
var _enabled: bool = false


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
	_clock += delta
	_update_streaks()
	_update_drift_preview()


func _update_streaks() -> void:
	var snapshot := _current_service.get_snapshot()
	var reference_speed := maxf(float(snapshot.get("speed", 0.04)), 0.025)
	var visual_strength := clampf(float(snapshot.get("visual_strength", 0.5)), 0.1, 1.0)
	for index in range(_streaks.size()):
		var streak := _streaks[index]
		if streak == null:
			continue
		var base_uv := _uvs[index]
		var local_flow := _current_service.sample_current_at_uv(base_uv, _clock)
		var speed := local_flow.length()
		if speed <= 0.002:
			streak.visible = false
			continue
		var direction := local_flow.normalized()
		var speed_ratio := clampf(speed / reference_speed, 0.25, 2.4)
		var cycle_speed := 0.42 + speed_ratio * 0.22
		var phase := fmod(_clock * cycle_speed + float(_phases[index]), 2.7)
		var active_window := clampf(0.48 + speed_ratio * 0.16, 0.45, 0.92)
		var active := phase < active_window
		streak.visible = active
		if not active:
			continue

		var travel := phase / active_window
		var uv := base_uv + Vector2(direction.x, -direction.y) * ((travel - 0.5) * 0.12 * speed_ratio)
		uv.x = wrapf(uv.x, 0.03, 0.97)
		uv.y = wrapf(uv.y, 0.03, 0.97)
		streak.global_position = _swim_bounds.normalized_uv_to_world(uv, _water_y)
		streak.rotation = Vector3(0.0, -atan2(direction.y, direction.x), 0.0)
		streak.scale = Vector3(clampf(0.72 + speed_ratio * 0.28, 0.7, 1.45), 1.0, 1.0)
		var material := streak.material_override as StandardMaterial3D
		if material != null:
			var alpha := clampf((0.20 + speed_ratio * 0.13) * visual_strength, 0.12, 0.62)
			var streak_color := material.albedo_color
			streak_color.a = alpha
			material.albedo_color = streak_color


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
	var path := _current_service.project_drift_path(start, 2.4, 0.4, _clock)
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
	for index in range(STREAK_COUNT):
		var streak := MeshInstance3D.new()
		streak.name = "CurrentStreak%02d" % index
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.34 + rng.randf_range(0.0, 0.18), 0.004, 0.014)
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color = Color(0.78, 0.94, 1.0, 0.42)
		streak.mesh = mesh
		streak.material_override = material
		add_child(streak)
		_streaks.append(streak)
		_uvs.append(Vector2(rng.randf_range(0.08, 0.92), rng.randf_range(0.07, 0.90)))
		_phases.append(rng.randf_range(0.0, 2.7))


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
