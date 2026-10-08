extends CharacterBody3D
class_name AutonomousWorldActor

const ACTOR_LAYER := 1 << 4
const OBSTACLE_MASK := 1 | 2 | ACTOR_LAYER
@export_range(0.35, 1.5, 0.05) var player_avoidance_radius: float = 0.48
@export_range(0.5, 2.0, 0.05) var avoidance_sensor_radius: float = 0.85
@export_range(0.2, 2.0, 0.1) var avoidance_decision_cooldown: float = 0.8
var avoidance_sensor: Area3D
var _avoidance_side := 0.0
var _avoidance_cooldown := 0.0

func _ready() -> void:
	avoidance_sensor = Area3D.new()
	avoidance_sensor.name = "PlayerAvoidanceSensor"
	avoidance_sensor.collision_layer = 0
	avoidance_sensor.collision_mask = 3
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = avoidance_sensor_radius
	shape.shape = sphere
	shape.position.y = 0.25
	avoidance_sensor.add_child(shape)
	add_child(avoidance_sensor)

## Keep a chosen passing side until the obstacle clears; never flip every tick.
func avoidance_motion(local_motion: Vector3, delta: float) -> Vector3:
	_avoidance_cooldown = maxf(0.0, _avoidance_cooldown - delta)
	if avoidance_sensor == null or not avoidance_sensor.monitoring or local_motion.is_zero_approx():
		return local_motion
	var parent_basis := Basis.IDENTITY
	if get_parent() is Node3D:
		parent_basis = (get_parent() as Node3D).global_basis
	var desired := parent_basis * local_motion
	var forward := desired.normalized()
	for body in avoidance_sensor.get_overlapping_bodies():
		if not body.is_in_group("fishing_player"):
			continue
		var offset: Vector3 = body.global_position - global_position
		offset.y = 0.0
		var ahead := offset.dot(forward)
		var closest := offset - forward * clampf(ahead, 0.0, avoidance_sensor_radius)
		if ahead <= 0.0 or closest.length() >= player_avoidance_radius:
			continue
		if _avoidance_side == 0.0:
			_avoidance_side = -1.0 if forward.cross(offset).y >= 0.0 else 1.0
			_avoidance_cooldown = avoidance_decision_cooldown
		for angle in [60.0, 90.0, 120.0]:
			var direction := forward.rotated(Vector3.UP, deg_to_rad(angle) * _avoidance_side)
			var probe := direction * 0.2
			if (offset - probe).length() > player_avoidance_radius and not test_move(global_transform, probe):
				return parent_basis.inverse() * (direction * desired.length())
		return Vector3.ZERO
	if _avoidance_cooldown <= 0.0:
		_avoidance_side = 0.0
	return local_motion

func _init() -> void:
	collision_layer = ACTOR_LAYER
	collision_mask = OBSTACLE_MASK
	platform_floor_layers = 0
	platform_wall_layers = 0

## Autonomous locomotion owns only this actor's movement. Never translate a
## blocker through another body or use moving-platform velocity to carry it.
## Callers retain their own patrol/idle/repath logic when a move is blocked.
func try_autonomous_motion(local_motion: Vector3) -> bool:
	if not is_inside_tree() or get_tree().paused:
		return false
	if local_motion.is_zero_approx():
		return true
	var parent_3d := get_parent() as Node3D
	var world_motion := local_motion
	if parent_3d != null:
		world_motion = parent_3d.global_basis * local_motion
	# A collision accepts only safe travel up to contact. Neither velocity nor
	# transforms are written to the contacted player/NPC; the mover stops.
	return move_and_collide(world_motion) == null
