shader_type particles;
render_mode disable_velocity;

group_uniforms Spawn;
uniform vec3 emission_box;

group_uniforms Velocity;
uniform float velocity_min = 10.0;
uniform float velocity_max = 15.0;

group_uniforms Turbulence;
uniform sampler2D noise_texture : repeat_enable;
uniform float domain_scale = 0.01;

group_uniforms Turbulence.Amplitude;
uniform float amplitude_min = 2.0;
uniform float amplitude_max = 4.0;

group_uniforms Spin;
uniform float scale = 1.0;
uniform float spin_speed = 1.0;

group_uniforms Fading;
uniform sampler2D fade_texture : repeat_disable;
uniform float fade_range = 1.0;
uniform float alpha_min : hint_range(0.0, 1.0) = 0.5;
uniform float alpha_max : hint_range(0.0, 1.0) = 0.5;

#include "random.gdshaderinc"

mat3 random_rotation_matrix(inout uint seed) {
	vec3 x_mapping = random_direction(seed);
	vec3 auxiliary = random_direction(seed);
	vec3 y_mapping = cross(x_mapping, auxiliary);
	vec3 z_mapping = cross(x_mapping, y_mapping);

	return mat3(x_mapping, y_mapping, z_mapping);
}

mat3 axis_angle_rotation(vec3 axis, float angle) {
	const vec3 DIAGONAL = vec3(1, 1, 1);
	vec3 auxiliary = normalize(cross(axis, axis + DIAGONAL));
	vec3 y = cross(axis, auxiliary);
	vec3 z = cross(axis, y);

	mat3 rotation_space_transform = mat3(axis, y, z);
	mat3 inv_rotation_space_transform = transpose(rotation_space_transform);

	mat3 rotation = mat3(
		vec3(1, 0, 0),
		vec3(0, cos(angle), sin(angle)),
		vec3(0, -sin(angle), cos(angle))
	);

	return rotation_space_transform * rotation * inv_rotation_space_transform;
}


void start() {
	uint seed = hash(NUMBER + RANDOM_SEED);

	float rx = (random(seed) - 0.5) * emission_box.x;
	float ry = (random(seed) - 0.5) * emission_box.y;

	mat3 random_rotation = mat3(EMISSION_TRANSFORM) * random_rotation_matrix(seed);

	TRANSFORM = mat4(random_rotation) * mat4(scale);
	TRANSFORM[3].xyz = vec3(rx, ry, -0.5 * emission_box.z);

	// Wind frame (world space)
	USERDATA3.xyz = mat3(EMISSION_TRANSFORM) * vec3(1.0, 0.0, 0.0);
	USERDATA4.xyz = mat3(EMISSION_TRANSFORM) * vec3(0.0, 1.0, 0.0);

	// Base position (world)
	USERDATA5.xyz = EMISSION_TRANSFORM[3].xyz;

	// Spawn position (local)
	USERDATA1 = TRANSFORM[3];
	// Current position (local)
	USERDATA2 = USERDATA1;
}

void process() {
	uint seed = hash(NUMBER + uint(1) + RANDOM_SEED);

	float velocity = random_range(seed, velocity_min, velocity_max);
	float amplitude = random_range(seed, amplitude_min, amplitude_max);

	vec3 new_position = vec3(
		USERDATA1.x + (texture(noise_texture, USERDATA2.yz * domain_scale).x - 0.5) * amplitude,
		USERDATA1.y + (texture(noise_texture, USERDATA2.xz * domain_scale).x - 0.5) * amplitude,
		USERDATA2.z + velocity * DELTA
	);

	USERDATA2.xyz = new_position;

	float spin_speed_multiplier = (texture(noise_texture, USERDATA2.xz * domain_scale).x - 0.5) * 2.0;

	vec3 spin_axis = random_direction(seed);
	TRANSFORM = mat4(axis_angle_rotation(spin_axis, DELTA * spin_speed * spin_speed_multiplier * PI)) * TRANSFORM;

	mat3 wind_transform = mat3(USERDATA3.xyz, USERDATA4.xyz, cross(USERDATA3.xyz, USERDATA4.xyz));
	TRANSFORM[3].xyz = USERDATA5.xyz + wind_transform * USERDATA2.xyz;

	float progress = (USERDATA2.z + emission_box.z * 0.5) / emission_box.z;
	COLOR.rgb = vec3(1.0);
	COLOR.a = texture(fade_texture, vec2(progress, 0.0)).x;
}