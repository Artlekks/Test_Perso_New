extends Node3D
class_name FishingCurrentSurfaceView

## Presentation adapter only. Existing current, tide, mastery, and lure physics
## continue to belong to their existing services. Purchased assets are local.

const CurrentWorldVfxScene = preload("res://actors/FishingCurrentVFX.tscn")
const EnvironmentFxOverlayScript = preload("res://scripts/environment_fx/environment_overlay.gd")
const CAPABILITY_READ_CURRENT: StringName = &"read_current"
const CAPABILITY_DRIFT_CASTING: StringName = &"current_compensation"
const DRIFT_MARKER_COUNT: int = 6
const FLOW_UPDATE_INTERVAL: float = 1.0 / 15.0

var _current_service: FishingCurrentService = null
var _mastery_service: FishingMasteryService = null
var _swim_bounds: FishSwimBounds = null
var _caster: Node = null
var _water_y: float = 0.0
var _drift_markers: Array[MeshInstance3D] = []
var _enabled: bool = false
var _flow_update_accumulator: float = 0.0
var _nolka_visual: Node3D = null
var _environment_canvas: CanvasLayer = null
var _environment_overlay: Control = null

func _ready() -> void:
	# Bootstrap the independent World-owned current effect once. Unlike the
	# fishing HUD, this world effect stays alive during exploration. Also works
	# if the user has already instanced it manually in the editor scene.
	_ensure_world_current_vfx()
	_build_drift_markers()
	_build_environment_overlay()
	_refresh_visibility()

func _ensure_world_current_vfx() -> void:
	# The canonical scene hierarchy is root/World and root/Game/Fishing.
	# Do NOT edit or replace the main scene (it may contain local camera edits).
	var world: Node3D = get_node_or_null("../../../World") as Node3D
	if world == null or world.has_node("FishingCurrentVFX"):
		return
	var visual: Node3D = CurrentWorldVfxScene.instantiate() as Node3D
	if visual == null:
		push_error("Nolka world-current scene could not be instantiated.")
		return
	visual.name = "FishingCurrentVFX"
	world.add_child(visual)

func configure(current_service: FishingCurrentService, mastery_service: FishingMasteryService) -> void:
	_current_service = current_service
	_mastery_service = mastery_service
	if _mastery_service != null:
		var callback: Callable = Callable(self, "_on_mastery_changed")
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
			_swim_bounds = zone.call("get_swim_bounds") as FishSwimBounds
		if zone.has_method("get_water_y"):
			_water_y = float(zone.call("get_water_y"))
	_refresh_visibility()

func _process(delta: float) -> void:
	if not _enabled or _swim_bounds == null or _current_service == null:
		_hide_drift_markers()
		return
	_flow_update_accumulator += delta
	if _flow_update_accumulator >= FLOW_UPDATE_INTERVAL:
		if is_instance_valid(_nolka_visual):
			_nolka_visual.call("update_environment", _current_service, _swim_bounds, _water_y, _flow_update_accumulator)
		_flow_update_accumulator = 0.0
	_update_drift_preview()

func _build_environment_overlay() -> void:
	if is_instance_valid(_environment_canvas):
		return
	_environment_canvas = CanvasLayer.new()
	_environment_canvas.name = "EnvironmentFxCanvas"
	_environment_canvas.layer = 8
	add_child(_environment_canvas)
	_environment_overlay = EnvironmentFxOverlayScript.new() as Control
	_environment_overlay.name = "WindAndWeather"
	_environment_canvas.add_child(_environment_overlay)
	var controller: Node = get_parent()
	if controller != null and controller.has_method("request_cast_confirm"):
		_environment_overlay.call("bind_fishing", controller)

func _build_drift_markers() -> void:
	if not _drift_markers.is_empty():
		return
	for index in range(DRIFT_MARKER_COUNT):
		var marker: MeshInstance3D = MeshInstance3D.new()
		marker.name = "DriftPrediction%02d" % index
		var mesh: BoxMesh = BoxMesh.new()
		mesh.size = Vector3(0.045, 0.004, 0.045)
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color = Color(1.0, 0.86, 0.45, 0.48 - float(index) * 0.045)
		marker.mesh = mesh
		marker.material_override = material
		marker.visible = false
		add_child(marker)
		_drift_markers.append(marker)

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
	var path: PackedVector3Array = _current_service.project_drift_path(start, 2.4, 0.4)
	for index in range(_drift_markers.size()):
		var marker: MeshInstance3D = _drift_markers[index]
		var path_index: int = index + 1
		if marker == null or path_index >= path.size():
			if marker != null:
				marker.visible = false
			continue
		var point: Vector3 = path[path_index]
		point.y = _water_y + 0.012
		marker.global_position = point
		marker.visible = true

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
	if is_instance_valid(_nolka_visual):
		_nolka_visual.call("set_active", _enabled)
	if not _enabled:
		_hide_drift_markers()

func _on_mastery_changed(_snapshot: Dictionary) -> void:
	_refresh_visibility()
