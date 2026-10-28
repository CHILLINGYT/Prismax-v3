shader_type spatial;
// Halo y anillo de suelo del marcador de puerta (DoorMarker), aditivos.
//   modo 0 = halo: resplandor redondo que mira a cámara (detrás de la flecha)
//   modo 1 = anillo de suelo: aro + ondas que se expanden (plano horizontal)
// `intensidad` la sube el script al acercarse el jugador.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.78, 0.0, 1.0);
uniform float intensidad : hint_range(0.0, 2.0) = 0.5;
uniform int modo = 0;

void vertex() {
	if (modo == 0) {
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
			INV_VIEW_MATRIX[0] * length(MODEL_MATRIX[0].xyz),
			INV_VIEW_MATRIX[1] * length(MODEL_MATRIX[1].xyz),
			INV_VIEW_MATRIX[2] * length(MODEL_MATRIX[2].xyz),
			MODEL_MATRIX[3]);
	}
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a;
	if (modo == 0) {
		a = pow(clamp(1.0 - r, 0.0, 1.0), 2.2) * 0.9;
	} else {
		float aro = smoothstep(0.08, 0.0, abs(r - 0.82));
		float onda_r = fract(TIME * 0.45);
		float onda = smoothstep(0.07, 0.0, abs(r - mix(0.25, 0.95, onda_r))) * (1.0 - onda_r);
		float relleno = smoothstep(0.85, 0.0, r) * 0.12;
		a = (aro * 0.9 + onda * 0.8 + relleno) * smoothstep(1.0, 0.9, r);
	}
	ALBEDO = color.rgb * a * intensidad;
}
