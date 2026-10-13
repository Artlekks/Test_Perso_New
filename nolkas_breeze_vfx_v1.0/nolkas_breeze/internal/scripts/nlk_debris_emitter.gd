@tool
class_name NlkDebrisEmitter
extends NlkWeatherEmitter

@export_group("Appearance")

@export var mesh: Mesh:
	set(value):
		mesh = value
		_is_dirty = true

@export var particle_scale: float = 1.0:
	set(value):
		particle_scale = value
		_is_dirty = true

@export var fade_curve: Curve:
	set(value):
		if value == null:
			value = BASE_FADE_CURVE.duplicate()

		fade_curve = value
		_is_dirty = true

@export_group("Dynamics")

@export_subgroup("Speed")

## The minimum speed of a leaf particle.
@export_range(1, 100, 0.1, "or_greater")
var min_speed: float = 10.0:
	set(value):
		min_speed = maxf(1.0, value)
		_is_dirty = true

## The maximum speed of a leaf particle.
@export_range(1, 100, 0.1, "or_greater")
var max_speed: float = 15.0:
	set(value):
		max_speed = maxf(1.0, value)
		_is_dirty = true

@export_subgroup("Turbulence")

## The noise used for leaf turbulence.
@export var turbulence_noise: Noise:
	set(value):
		if value == null:
			value = BASE_TURBULENCE_NOISE.duplicate()

		turbulence_noise = value
		_is_dirty = true

@export_subgroup("Turbulence/Amplitude")

## The minimum amplitude of the turbulence.
@export_range(0, 10, 0.1, "or_greater")
var min_turbulence_amplitude: float = 2.0:
	set(value):
		min_turbulence_amplitude = value
		_is_dirty = true

## The maximum amplitude of the turbulence.
@export_range(0, 10, 0.1, "or_greater")
var max_turbulence_amplitude: float = 5.0:
	set(value):
		max_turbulence_amplitude = value
		_is_dirty = true

var _is_dirty := true
var _gizmo := NlkAreaEmitterGizmo.new()

@onready var _emitter: GPUParticles3D = %Emitter

@onready var _process_material: ShaderMaterial:
	get:
		return _emitter.process_material

const BASE_TURBULENCE_NOISE: FastNoiseLite = preload("uid://dm3ionnxtecr7")
const BASE_FADE_CURVE: Curve = preload("uid://bavipechd6dtq")


func _ready() -> void:
	_setup_textures()


func _process(_delta: float) -> void:
	if _is_dirty:
		update_parameters()
		_is_dirty = false

	if Engine.is_editor_hint():
		_gizmo.update(self)


func _exit_tree() -> void:
	_gizmo.dispose()


func update_parameters() -> void:
	# Spawn
	_process_material.set_shader_parameter(&"emission_box", area)

	_emitter.visibility_aabb.size = area
	_emitter.visibility_aabb.position = -0.5 * area

	# Velocity
	_process_material.set_shader_parameter(&"velocity_min", min_speed)
	_process_material.set_shader_parameter(&"velocity_max", max_speed)

	var distance := area.z
	var lifetime := distance / min_speed

	_emitter.lifetime = lifetime
	_emitter.preprocess = lifetime

	# Appearance
	_emitter.draw_pass_1 = mesh

	_process_material.set_shader_parameter(
		&"scale",
		particle_scale,
	)

	var fade_texture: CurveTexture = (
		_process_material.get_shader_parameter(&"fade_texture")
	)

	if fade_texture.curve != fade_curve:
		fade_texture.curve = fade_curve

	# Turbulence
	var noise_texture := (
		_process_material.get_shader_parameter(&"noise_texture") as NoiseTexture2D
	)

	if noise_texture != null and noise_texture.noise != turbulence_noise:
		noise_texture.noise = turbulence_noise

	_process_material.set_shader_parameter(
		&"amplitude_min",
		min_turbulence_amplitude,
	)

	_process_material.set_shader_parameter(
		&"amplitude_max",
		max_turbulence_amplitude,
	)


func _on_emitting_updated() -> void:
	_emitter.emitting = emitting


func _on_area_updated() -> void:
	_is_dirty = true


func _on_amount_updated() -> void:
	_emitter.amount = particles_amount


func _on_speed_scale_updated() -> void:
	_emitter.speed_scale = speed_scale


func _setup_textures() -> void:
	NlkTextureUtils.setup_noise_texture(
		_process_material,
		turbulence_noise,
		BASE_TURBULENCE_NOISE,
	)

	NlkTextureUtils.setup_curve_texture(
		_process_material,
		fade_curve,
		BASE_FADE_CURVE,
	)
