@tool
extends AutonomousWorldActor
class_name CatalogueNPCActor
@export var visual_profile: NPCVisualProfile
@export var patrol_enabled := false
@export var patrol_distance := 1.0
@export var patrol_speed := 0.4
var _home := Vector3.ZERO
var _sign := 1.0

func _ready() -> void:
	set_meta("profile_owned_collision", true)
	if not Engine.is_editor_hint(): super._ready()
	_home = position
	apply_visual_profile()

func apply_visual_profile() -> void:
	if visual_profile == null: return
	var presentation := $GroundPresentation as GroundPresentation
	var sprite := $GroundPresentation/VisualAnchor/AnimatedSprite3D as AnimatedSprite3D
	presentation.profile = visual_profile
	sprite.sprite_frames = visual_profile.sprite_frames
	sprite.speed_scale = visual_profile.animation_speed
	if sprite.sprite_frames.has_animation(visual_profile.default_animation): sprite.play(visual_profile.default_animation)
	presentation.apply_profile()
	var collider := visual_profile.collider_profile
	if collider != null:
		$CollisionShape3D.shape = collider.make_shape()
		$CollisionShape3D.position.y = collider.height * 0.5
		$CollisionShape3D.disabled = not collider.hard_blocking
		collision_layer = ACTOR_LAYER if collider.hard_blocking else 0
		collision_mask = OBSTACLE_MASK if collider.hard_blocking else 0

func set_preview_pose(pose: String) -> void:
	if visual_profile == null: return
	var presentation := $GroundPresentation as GroundPresentation
	if visual_profile.directional_animation_prefixes.has(pose):
		presentation.set_directional_pose(pose, Vector3.BACK)
	else:
		var sprite := presentation.sprite as AnimatedSprite3D
		if sprite != null: sprite.play(visual_profile.default_animation)

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or not patrol_enabled or visual_profile == null or not visual_profile.movement_capability: return
	# The shared non-pushing actor policy owns all physical motion.
	var motion := Vector3(_sign * patrol_speed * delta, 0, 0)
	motion = avoidance_motion(motion, delta)
	if not try_autonomous_motion(motion) or absf(position.x - _home.x) >= patrol_distance: _sign *= -1.0
	$GroundPresentation.set_local_directional_pose("walk", Vector3(_sign, 0, 0))

