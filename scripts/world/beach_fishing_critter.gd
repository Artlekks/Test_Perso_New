extends Node3D
class_name BeachFishingCritter

@export_enum("green", "red") var color_variant: String = "green"
@export_range(0.1, 2.0, 0.05) var roam_half_width: float = 0.55
@export_range(0.1, 2.0, 0.05) var roam_half_depth: float = 0.32
@export_range(0.05, 1.0, 0.01) var move_speed: float = 0.22
@export_range(0.0, 0.15, 0.005) var hover_amplitude: float = 0.025
@export_range(0.5, 12.0, 0.25) var hover_frequency: float = 5.0

@onready var animated_sprite: AnimatedSprite3D = $AnimatedSprite3D

var _rng := RandomNumberGenerator.new()
var _home_position := Vector3.ZERO
var _base_y: float = 0.0
var _target := Vector3.ZERO
var _hover_time: float = 0.0
var _hover_phase: float = 0.0


func _ready() -> void:
	_rng.randomize()
	_home_position = position
	_base_y = position.y
	_hover_phase = _rng.randf_range(0.0, TAU)
	_choose_target()
	_update_animation(Vector2(1.0, 0.25))


func _process(delta: float) -> void:
	var tree := get_tree()
	if tree == null or tree.paused:
		return

	_hover_time += delta
	var flat := Vector2(position.x, position.z)
	var flat_target := Vector2(_target.x, _target.z)
	var to_target := flat_target - flat
	var distance := to_target.length()
	if distance <= 0.025:
		_choose_target()
		to_target = Vector2(_target.x - position.x, _target.z - position.z)
		distance = to_target.length()

	if distance > 0.0001:
		var direction := to_target / distance
		var step := minf(move_speed * delta, distance)
		position.x += direction.x * step
		position.z += direction.y * step
		_update_animation(direction)

	position.y = _base_y + sin(_hover_time * hover_frequency + _hover_phase) * hover_amplitude


func _choose_target() -> void:
	_target = _home_position + Vector3(
		_rng.randf_range(-roam_half_width, roam_half_width),
		0.0,
		_rng.randf_range(-roam_half_depth, roam_half_depth)
	)


func _update_animation(direction: Vector2) -> void:
	if animated_sprite == null or animated_sprite.sprite_frames == null:
		return

	var x := direction.x
	var z := direction.y
	var ax := absf(x)
	var az := absf(z)
	var dir_name := "e"
	var mirror := false

	if az > ax * 1.75:
		dir_name = "s" if z >= 0.0 else "n"
	elif ax > az * 1.75:
		dir_name = "e"
		mirror = x < 0.0
	elif z < 0.0:
		dir_name = "ne"
		mirror = x < 0.0
	else:
		dir_name = "se"
		mirror = x < 0.0

	animated_sprite.flip_h = mirror
	var animation_name := StringName("%s_%s" % [color_variant, dir_name])
	if not animated_sprite.sprite_frames.has_animation(animation_name):
		return
	if animated_sprite.animation != animation_name or not animated_sprite.is_playing():
		animated_sprite.play(animation_name)
