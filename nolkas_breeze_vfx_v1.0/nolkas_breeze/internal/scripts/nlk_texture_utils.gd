@tool
class_name NlkTextureUtils
extends RefCounted

static func setup_noise_texture(
		material: ShaderMaterial,
		noise: Noise,
		default_noise: Noise,
) -> void:
	var noise_texture: NoiseTexture2D = (
		material.get_shader_parameter(&"noise_texture")
	)

	if noise_texture == null:
		noise_texture = NoiseTexture2D.new()
		noise_texture.seamless = true
		noise_texture.seamless_blend_skirt = 0.3

		material.set_shader_parameter(
			&"noise_texture",
			noise_texture,
		)

	if noise_texture.noise != noise:
		if noise == null:
			noise = default_noise.duplicate()

		noise_texture.noise = noise


static func setup_curve_texture(
		material: ShaderMaterial,
		curve: Curve,
		default_curve: Curve,
) -> void:
	var fade_texture: CurveTexture = (
		material.get_shader_parameter(&"fade_texture")
	)

	if fade_texture == null:
		fade_texture = CurveTexture.new()

		material.set_shader_parameter(
			&"fade_texture",
			fade_texture,
		)

	if fade_texture.curve != curve:
		if curve == null:
			curve = default_curve.duplicate()

		fade_texture.curve = curve
