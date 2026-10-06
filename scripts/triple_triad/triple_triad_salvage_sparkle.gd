extends Node3D
class_name TripleTriadSalvageSparkle

const SALVAGE_BOTTLE_TEXTURE: Texture2D = preload(
	"res://assets/sprites/triple_triad/salvage_bottle_orange.png"
)

## Lightweight prototype marker for an authored fishing-salvage target.
## It owns presentation only. The fishing salvage bridge decides when it appears
## and whether the player's cast is close enough to arm the recovery.

@export var trigger_radius: float = 1.0
@export var bob_height: float = 0.08
@export var bob_speed: float = 3.0
@export var pulse_speed: float = 4.0

var _base_position: Vector3 = Vector3.ZERO
var _elapsed: float = 0.0
var _visual_root: Node3D = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_visual()
	_base_position = position
	set_process(true)


func configure(world_position: Vector3, radius: float = 1.0) -> void:
	trigger_radius = maxf(0.25, radius)
	global_position = world_position
	_base_position = position


func is_cast_near(world_point: Vector3) -> bool:
	var marker_flat := Vector2(global_position.x, global_position.z)
	var cast_flat := Vector2(world_point.x, world_point.z)
	return marker_flat.distance_to(cast_flat) <= trigger_radius


func get_debug_snapshot() -> Dictionary:
	return {
		"world_position": global_position,
		"trigger_radius": trigger_radius,
		"visible": visible,
	}


func _process(delta: float) -> void:
	_elapsed += delta
	position.y = _base_position.y + sin(_elapsed * bob_speed) * bob_height
	rotation.y += delta * 1.4
	if is_instance_valid(_visual_root):
		var pulse := 1.0 + sin(_elapsed * pulse_speed) * 0.16
		_visual_root.scale = Vector3.ONE * pulse


func _build_visual() -> void:
	if is_instance_valid(_visual_root):
		return

	_visual_root = Node3D.new()
	_visual_root.name = "SalvageBottleVisual"
	add_child(_visual_root)

	var bottle := Sprite3D.new()
	bottle.name = "OrangeSalvageBottle"
	bottle.texture = SALVAGE_BOTTLE_TEXTURE
	bottle.pixel_size = 0.009
	bottle.billboard = 1
	bottle.texture_filter = 0
	bottle.alpha_cut = 1
	bottle.alpha_scissor_threshold = 0.5
	bottle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bottle.position = Vector3(0.0, 0.035, 0.0)
	_visual_root.add_child(bottle)

	# Keep a restrained warm glint so the bottle still reads as the intentional
	# fishing-salvage target from a distance without reverting to placeholder
	# geometry.
	var light := OmniLight3D.new()
	light.name = "BottleGlint"
	light.light_color = Color(1.0, 0.72, 0.34, 1.0)
	light.light_energy = 0.85
	light.omni_range = 1.15
	light.shadow_enabled = false
	_visual_root.add_child(light)
