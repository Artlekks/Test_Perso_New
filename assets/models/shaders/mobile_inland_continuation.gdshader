shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D frame_strip : source_color, filter_nearest, repeat_disable;
uniform float frame_count = 7.0;
uniform float animation_fps = 4.0;
uniform float land_edge_z;
varying vec2 local_xz;
varying vec2 world_xz;
void vertex() {
	local_xz = VERTEX.xz;
	world_xz = (MODEL_MATRIX * vec4(VERTEX,1.0)).xz;
}
void fragment() {
	float frame = mod(floor(TIME*animation_fps),frame_count);
	vec2 dimensions = vec2(textureSize(frame_strip,0));
	vec2 patch = vec2(32.0,8.0)+fract(world_xz*2.0)*vec2(64.0,32.0);
	vec2 grain_uv = vec2((frame+patch.x/(dimensions.x/frame_count))/frame_count,patch.y/dimensions.y);
	vec2 half_texel = vec2(0.5)/vec2(dimensions.x/frame_count,dimensions.y);
	vec2 authored_uv = mix(half_texel,vec2(1.0)-half_texel,UV);
	vec2 edge_uv = vec2((frame+authored_uv.x)/frame_count,authored_uv.y);
	ALBEDO = mix(texture(frame_strip,edge_uv).rgb,texture(frame_strip,grain_uv).rgb,smoothstep(0.0,0.7,local_xz.y-land_edge_z));
}
