shader_type canvas_item;
render_mode unshaded;

// Placeholder "prismax" logo mark: a triangle split into vertical rainbow bands
// with a thin bright outline, fully transparent outside the triangle.
// It is intentionally a shader (not a baked image) so it stays crisp and editable.
// Replace the whole GameLogo scene when the real logo art is ready.

uniform float apex : hint_range(0.0, 1.0) = 0.06;
uniform float base_y : hint_range(0.0, 1.0) = 0.95;
uniform float half_width : hint_range(0.0, 0.5) = 0.42;
uniform float saturation : hint_range(0.0, 1.0) = 0.85;
uniform float outline_width : hint_range(0.0, 0.2) = 0.035;

vec3 hsv2rgb(vec3 c) {
	vec3 rgb = clamp(abs(mod(c.x * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
	return c.z * mix(vec3(1.0), rgb, c.y);
}

void fragment() {
	vec2 uv = UV;
	vec2 a = vec2(0.5, apex);
	vec2 b = vec2(0.5 - half_width, base_y);
	vec2 c = vec2(0.5 + half_width, base_y);

	// Consistent signed edges; all positive inside the triangle.
	vec2 e0 = b - a;
	vec2 e1 = c - b;
	vec2 e2 = a - c;
	float d0 = (uv.x - a.x) * e0.y - (uv.y - a.y) * e0.x;
	float d1 = (uv.x - b.x) * e1.y - (uv.y - b.y) * e1.x;
	float d2 = (uv.x - c.x) * e2.y - (uv.y - c.y) * e2.x;

	float mn = min(min(d0, d1), d2);
	float aa = fwidth(mn) * 1.5 + 0.0015;
	float alpha = smoothstep(0.0, aa, mn);

	if (alpha <= 0.001) {
		COLOR = vec4(0.0);
	} else {
		vec3 col = hsv2rgb(vec3(clamp(uv.x, 0.0, 1.0), saturation, 1.0));
		float outline = 1.0 - smoothstep(0.0, outline_width, mn);
		col = mix(col, vec3(1.0), outline * 0.85);
		COLOR = vec4(col, alpha);
	}
}