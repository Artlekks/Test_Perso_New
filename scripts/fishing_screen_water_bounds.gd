extends Node

## Late presentation constraint, after camera yaw and physical bait movement.
## Camera still owns horizontal framing; this component protects the top HUD.
@export_range(0.0, 0.5, 0.01) var top_safe_ratio := 0.18
@export_range(0.0, 0.1, 0.005) var info_margin_ratio := 0.05
var fishing: Node
var info_view: Node
var _water_phase: int
var _fight_phase: int

func _ready() -> void:
	# Presentation may report a safe screen band, but never directly move
	# the physical bait. Keep the helper available for legacy QA/preview.
	set_process(false)
	process_priority = 100
	var phases: Dictionary = fishing.get_script().get_script_constant_map().Phase
	_water_phase = phases.IN_WATER
	_fight_phase = phases.FIGHT

func _process(_delta: float) -> void:
	# Intentionally does not operate on bait.global_position. The static
	# constrain_position() geometry helper remains for older QA/visual tools.
	pass

static func constrain_position(camera: Camera3D, position: Vector3, top: float) -> Vector3:
	if not is_instance_valid(camera) or camera.is_position_behind(position):
		return position
	var size := camera.get_viewport().get_visible_rect().size
	if size.y <= 0.0:
		return position
	var screen := camera.unproject_position(position)
	var safe_y := maxf(screen.y, size.y * top)
	if is_equal_approx(safe_y, screen.y):
		return position
	# Intersect the safe screen pixel with the bait's current depth plane.
	# This preserves screen X and lure depth, rather than clamping world Y.
	var pixel := Vector2(screen.x, safe_y)
	var origin := camera.project_ray_origin(pixel)
	var direction := camera.project_ray_normal(pixel)
	var resolved = Plane(Vector3.UP, position.y).intersects_ray(origin, direction)
	return resolved if resolved is Vector3 else position
