@tool
class_name NlkWindEmitter
extends NlkWeatherEmitter

const DENSITY_FACTOR: float = 0.1

@export_group("Appearance")

## The color of the wind sways.
@export var color: Color = Color.WHITE:
	set(value):
		color = value
		_is_dirty = true

@export var sway_texture: Texture2D:
	set(value):
		if value == null:
			value = BASE_SWAY_TEXTURE.duplicate()

		sway_texture = value
		_is_dirty = true

@export var sway_thickness: float = 0.25:
	set(value):
		sway_thickness = value
		_is_dirty = true

## The duration of a wind sway (modulates the length of the sway).
@export_range(0, 1, 0.01, "or_greater")
var sway_duration: float = 0.5:
	set(value):
		sway_duration = value
		_is_dirty = true

## The alpha fading of the wind sways over time.
@export var fade_curve: Curve:
	set(value):
		if value == null:
			value = BASE_FADE_CURVE.duplicate()

		fade_curve = value
		_is_dirty = true

@export_group("Dynamics")

@export_subgroup("Speed")

## The minimum speed of a wind sway.
@export_range(1, 100, 0.1, "or_greater")
var min_speed: float = 10:
	set(value):
		min_speed = clamp(value, 1, max_speed)
		_is_dirty = true

## The maximum speed of a wind sway.
@export_range(1, 100, 0.1, "or_greater")
var max_speed: float = 15:
	set(value):
		max_speed = max(value, min_speed)
		_is_dirty = true

@export_subgroup("Turbulence")

## The noise used for the wind turbulence.
@export var turbulence_noise: Noise:
	set(value):
		if value == null:
			value = BASE_TURBULENCE_NOISE.duplicate()

		turbulence_noise = value
		_is_dirty = true

## Scales the noise domain, this is a multiplier of the frequency.
@export var turbulence_domain_scale: float = 0.01:
	set(value):
		turbulence_domain_scale = value
		_is_dirty = true

@export_subgroup("Turbulence/Amplitude")

## The min amplitude of the turbulence.
@export_range(0, 10, 0.1, "or_greater")
var min_turbulence_amplitude: float = 2.0:
	set(value):
		min_turbulence_amplitude = value
		_is_dirty = true

## The max amplitude of the turbulence.
@export_range(0, 10, 0.1, "or_greater")
var max_turbulence_amplitude: float = 5.0:
	set(value):
		max_turbulence_amplitude = value
		_is_dirty = true

var _is_dirty: bool = true
var _gizmo := NlkAreaEmitterGizmo.new()

@onready var _emmiter: GPUParticles3D = %SwayEmitter

var _process_material: ShaderMaterial:
	get():
		return _emmiter.process_material

var _sway_material: BaseMaterial3D:
	get():
		return _emmiter.material_override

var _sway_mesh: RibbonTrailMesh:
	get():
		return _emmiter.draw_pass_1

const BASE_TURBULENCE_NOISE: FastNoiseLite = preload("uid://dm3ionnxtecr7")
const BASE_FADE_CURVE: Curve = preload("uid://bavipechd6dtq")
const BASE_SWAY_TEXTURE: Texture2D = preload("uid://cc2h7786vr7pc")


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
	# Emission
	_process_material.set_shader_parameter(
		&"emission_box",
		Vector3(area.x, area.y, area.z),
	)

	_emmiter.visibility_aabb.size = area
	_emmiter.visibility_aabb.position = -0.5 * area

	_process_material.set_shader_parameter(&"velocity_min", min_speed)
	_process_material.set_shader_parameter(&"velocity_max", max_speed)

	var distance: float = area.z

	_emmiter.lifetime = (
		distance / min_speed
		+ sway_duration * 0.5
	)

	_emmiter.preprocess = distance / max_speed

	# Appearance
	if _emmiter.trail_lifetime != sway_duration:
		_emmiter.trail_lifetime = sway_duration

	_sway_mesh.size = sway_thickness
	_sway_material.albedo_texture = sway_texture
	_sway_material.albedo_color = color

	var fade_texture: CurveTexture = (
		_process_material.get_shader_parameter(&"fade_texture")
	)

	if fade_texture.curve != fade_curve:
		fade_texture.curve = fade_curve

	# Turbulence
	var noise_texture: NoiseTexture2D = (
		_process_material.get_shader_parameter(&"noise_texture")
	)

	if noise_texture.noise != turbulence_noise:
		noise_texture.noise = turbulence_noise

	_process_material.set_shader_parameter(
		&"domain_scale",
		turbulence_domain_scale,
	)

	_process_material.set_shader_parameter(
		&"amplitude_min",
		min_turbulence_amplitude,
	)

	_process_material.set_shader_parameter(
		&"amplitude_max",
		max_turbulence_amplitude,
	)


func _on_emitting_updated() -> void:
	_emmiter.emitting = emitting


func _on_area_updated() -> void:
	_is_dirty = true


func _on_amount_updated() -> void:
	_emmiter.amount = particles_amount


func _on_speed_scale_updated() -> void:
	_emmiter.speed_scale = speed_scale


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
