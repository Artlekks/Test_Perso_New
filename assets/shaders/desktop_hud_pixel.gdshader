shader_type canvas_item;

uniform bool grayscale = false;

void fragment() {
	vec4 pixel = texture(TEXTURE, UV);
	if (pixel.a < 0.5) {
		discard;
	}
	if (grayscale) {
		float value = dot(pixel.rgb, vec3(0.299, 0.587, 0.114));
		pixel.rgb = vec3(value * 0.68);
	}
	COLOR = pixel;
}
