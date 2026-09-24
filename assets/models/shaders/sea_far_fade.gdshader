shader_type spatial;
render_mode unshaded, cull_disabled;

// Static sea colour/texture from the beach GLB.
uniform sampler2D sea_texture : source_color, filter_nearest, repeat_disable;

// Current Sea mesh local bounds from beach.glb.
uniform float shore_z = -1.0;
uniform float far_z = -31.0;
uniform float sea_min_x = -13.37757;
uniform float sea_max_x = 13.67757;

// Broad colour shaping. Keep the deep-water band visible for much longer,
// then only fade to black in the final exposed edge strip.
uniform float depth_darkening_start = 0.32;
uniform float depth_darkening_strength = 0.08;
uniform float deep_blue_start = 0.52;
uniform float deep_blue_strength = 0.48;
uniform vec4 deep_blue_tint : source_color = vec4(0.04, 0.16, 0.34, 1.0);

// Exposed geometry-edge feather in LOCAL mesh units.
// The side feather stays subtle. The far feather gives the BOF4-style soft edge.
uniform float side_feather_width = 1.0;
uniform float far_feather_width = 2.25;
uniform float edge_feather_power = 1.2;

// Only the very last band should collapse to black.
uniform float final_black_band_width = 0.42;
uniform float final_black_band_power = 1.45;

// Compatibility with previous material instances.
uniform float edge_fade_start = 0.72;
uniform float edge_fade_power = 1.35;

varying vec2 sea_local_xz;

void vertex() {
    sea_local_xz = VERTEX.xz;
}

void fragment() {
    vec3 base = texture(sea_texture, UV).rgb;

    // 0 at shoreline, 1 at far end.
    float depth_denom = max(abs(shore_z - far_z), 0.0001);
    float depth01 = clamp((shore_z - sea_local_xz.y) / depth_denom, 0.0, 1.0);

    // Gentle broad darkening only.
    float broad_depth_t = smoothstep(depth_darkening_start, 1.0, depth01);
    vec3 shaded = base * (1.0 - broad_depth_t * depth_darkening_strength);

    // Preserve a readable dark-blue zone instead of rushing to black.
    float blue_t = smoothstep(deep_blue_start, 0.96, depth01) * deep_blue_strength;
    vec3 deep_blue_mix = mix(shaded, deep_blue_tint.rgb, blue_t);

    // Distance from the two exposed side edges of the Sea mesh.
    float left_dist = max(sea_local_xz.x - sea_min_x, 0.0);
    float right_dist = max(sea_max_x - sea_local_xz.x, 0.0);
    float side_dist = min(left_dist, right_dist);

    // Distance from the exposed far edge. Shoreline edge is intentionally excluded.
    float far_dist = max(sea_local_xz.y - far_z, 0.0);

    float side_edge = 1.0 - smoothstep(0.0, max(side_feather_width, 0.0001), side_dist);
    float far_soft_edge = 1.0 - smoothstep(0.0, max(far_feather_width, 0.0001), far_dist);

    // First, softly bias the far edge toward the same dark blue instead of black.
    // This keeps the dark-blue band readable, like the original game.
    float soft_edge_mask = clamp(max(side_edge * 0.55, far_soft_edge), 0.0, 1.0);
    soft_edge_mask = pow(soft_edge_mask, max(edge_feather_power, 0.001));
    vec3 softened = mix(deep_blue_mix, deep_blue_tint.rgb, soft_edge_mask * 0.45);

    // Then only the very last narrow strip falls to black.
    float final_black = 1.0 - smoothstep(0.0, max(final_black_band_width, 0.0001), far_dist);
    final_black = pow(final_black, max(final_black_band_power, 0.001));

    ALBEDO = mix(softened, vec3(0.0), final_black);
}
