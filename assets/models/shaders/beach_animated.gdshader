shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D frame_strip :
    source_color,
    filter_nearest,
    repeat_disable;

// The scene owns the actual animation count. The current beach is authored
// as 7 frames, but the shader intentionally supports any horizontal strip.
uniform float frame_count = 7.0;
uniform float animation_fps = 4.0;

void fragment() {
    float safe_frame_count = max(frame_count, 1.0);
    float frame = mod(floor(TIME * animation_fps), safe_frame_count);

    // Derive the frame dimensions from the actual imported texture instead
    // of hard-coding the old sprite-sheet size. Sampling half a texel inside
    // each frame prevents neighbouring frames from bleeding at the borders.
    vec2 strip_size = vec2(textureSize(frame_strip, 0));
    vec2 frame_size = vec2(strip_size.x / safe_frame_count, strip_size.y);
    vec2 half_texel = vec2(0.5) / max(frame_size, vec2(1.0));
    vec2 local_uv = mix(half_texel, vec2(1.0) - half_texel, UV);

    vec2 strip_uv = vec2(
        (frame + local_uv.x) / safe_frame_count,
        local_uv.y
    );

    vec4 tex = texture(frame_strip, strip_uv);
    ALBEDO = tex.rgb;

    // Beach.png is fully opaque. Do not write ALPHA here: doing so would move
    // the beach into Godot's transparent render queue, where it can sort over
    // the transparent AnimatedSprite3D character even when the geometry says
    // the character is in front.
}
