shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform float opacity : hint_range(0.0, 1.0) = 0.65;
void fragment() {
	float radius = length((UV - vec2(0.5)) * 2.0);
	ALBEDO = vec3(0.0);
	ALPHA = opacity * (1.0 - smoothstep(0.25, 1.0, radius));
}
