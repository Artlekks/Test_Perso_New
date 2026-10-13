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
uniform float amplitude_min = 3.0;
uniform float amplitude_max = 3.0;

group_uniforms Fading;
uniform sampler2D fade_texture : repeat_disable;
uniform float fade_range = 1.0;
uniform float alpha_min : hint_range(0.0, 1.0) = 0.5;
uniform float alpha_max : hint_range(0.0, 1.0) = 0.5;

#include "random.gdshaderinc"

void start() {
	uint seed = hash(NUMBER + RANDOM_SEED);
	
	float rx = (random(seed)  - 0.5) * emission_box.x;
	float ry = (random(seed) - 0.5) * emission_box.y;
	
	TRANSFORM[3].xyz = vec3(rx, ry, -0.5 * emission_box.z);
	
	float random_angle = random_range(seed, -PI, PI);
	TRANSFORM[0].xyz = vec3(cos(random_angle), sin(random_angle), 0);
	TRANSFORM[1].xyz = vec3(-sin(random_angle), cos(random_angle), 0);
	TRANSFORM[2].xyz = vec3(0, 0, 1);
	
	TRANSFORM = EMISSION_TRANSFORM * TRANSFORM;
	
	// Spawn position (world space)
	USERDATA1 = TRANSFORM[3];
	USERDATA2.x = 0.0;
}

void process() {
	uint seed = hash(NUMBER + uint(1) + RANDOM_SEED);

	float velocity = random_range(seed, velocity_min, velocity_max);
	float amplitude = random_range(seed, amplitude_min , amplitude_max);
	float offset_0 = random_range(seed, 0.0 , 1.0);
	float offset_1 = random_range(seed, 0.0 , 1.0);
	
	vec4 spawn_position = USERDATA1;
	vec3 spawn_relative_position = (TRANSFORM[3] - spawn_position).xyz;
	mat3 inverse_transform = transpose(mat3(TRANSFORM));
	vec3 spawn_space_position = inverse_transform * spawn_relative_position;

	vec3 new_position_spawn_space = vec3(
		(texture(noise_texture, spawn_space_position.yz * domain_scale + offset_0).x - 0.5) * amplitude,
		(texture(noise_texture, spawn_space_position.xz * domain_scale + offset_1 ).x - 0.5) * amplitude,
		spawn_space_position.z + velocity * DELTA
	);
	
	TRANSFORM[3].xyz = spawn_position.xyz + mat3(TRANSFORM) * new_position_spawn_space;

	float progress = spawn_space_position.z / emission_box.z;

	float random_alpha = random_range(seed, alpha_min, alpha_max);
	COLOR.rgb = vec3(1.0);
	COLOR.a = clamp(texture(fade_texture, vec2(progress, 0.0)).x, -1.0, 1.0);
	COLOR.a = COLOR.a < 0.01 ? 0.0 : COLOR.a;
}
