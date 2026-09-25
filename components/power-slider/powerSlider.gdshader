shader_type canvas_item;

uniform vec4 top_color : source_color = vec4(0.027, 0.976, 0.980, 1.0);
uniform vec4 bottom_color : source_color = vec4(0.506, 0.110, 0.886, 1.0);

void fragment() {
	float t = UV.y;

	COLOR = mix(top_color, bottom_color, t);
}