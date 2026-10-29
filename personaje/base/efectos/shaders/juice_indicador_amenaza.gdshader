shader_type spatial;
// INDICADOR DE AMENAZA sobre el enemigo que está atacando (JuiceCombate),
// inspirado en el aviso de contraataque de Arkham: tres trazos en abanico sobre
// la cabeza, con halo, que laten. Siempre mira a cámara y se ve a través de los
// cuerpos (no_depth_test) para no perder el aviso en una melé.
render_mode unshaded, blend_add, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(0.45, 0.85, 1.0, 1.0);
uniform float intensidad : hint_range(0.0, 2.0) = 1.0;
uniform float latido : hint_range(0.0, 1.0) = 0.0;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0] * length(MODEL_MATRIX[0].xyz),
		INV_VIEW_MATRIX[1] * length(MODEL_MATRIX[1].xyz),
		INV_VIEW_MATRIX[2] * length(MODEL_MATRIX[2].xyz),
		MODEL_MATRIX[3]);
}

// Distancia de p al segmento a-b.
float seg(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h);
}

void fragment() {
	vec2 p = vec2(UV.x * 2.0 - 1.0, 1.0 - UV.y * 2.0);   // y hacia arriba
	float d = 1e3;
	// Tres trazos en abanico (centro más largo), con un quiebro de "rayo".
	d = min(d, seg(p, vec2(0.0, -0.55), vec2(0.06, 0.05)));
	d = min(d, seg(p, vec2(0.06, 0.05), vec2(-0.04, 0.12)));
	d = min(d, seg(p, vec2(-0.04, 0.12), vec2(0.02, 0.78)));
	d = min(d, seg(p, vec2(-0.30, -0.45), vec2(-0.55, 0.42)));
	d = min(d, seg(p, vec2(0.30, -0.45), vec2(0.55, 0.42)));
	float trazo = smoothstep(0.075, 0.03, d);
	float halo = smoothstep(0.42, 0.0, d) * 0.45;
	float pulso = 0.75 + 0.25 * latido;
	float a = (trazo * 1.3 + halo) * intensidad * pulso;
	ALBEDO = mix(color.rgb, vec3(1.0), trazo * 0.6) * a;
}
