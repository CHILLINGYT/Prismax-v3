shader_type canvas_item;

uniform float amount : hint_range(0.0, 1.0) = 0.0;
uniform vec3 tint : source_color = vec3(0.09, 0.36, 0.55);

void fragment() {
	float d = distance(UV, vec2(0.5));
	float vig = smoothstep(0.30, 0.82, d);
	vec3 c = mix(tint, tint * 0.70, vig);
	COLOR = vec4(c, amount);
}