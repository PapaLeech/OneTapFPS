shader_type canvas_item;

uniform float threshold : hint_range(0.0, 1.0) = 0.18;

void fragment() {
	vec4 col = texture(TEXTURE, UV);
	float brightness = dot(col.rgb, vec3(0.299, 0.587, 0.114));
	float alpha = smoothstep(threshold - 0.05, threshold + 0.05, brightness);
	COLOR = vec4(col.rgb, col.a * alpha);
}
