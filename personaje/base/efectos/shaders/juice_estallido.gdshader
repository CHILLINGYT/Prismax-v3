shader_type spatial;
// ESTALLIDO de luz en el punto de contacto (JuiceCombate). Un quad que siempre
// mira a cámara, aditivo y sin luz:
//   forma 0 = destello: núcleo + estrella de 4 puntas (golpe normal)
//   forma 1 = anillo de onda expansiva (golpes pesados y remates)
// `vida` va de 1 (nace) a 0 (desaparece); el tamaño lo anima el script.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.85, 0.55, 1.0);
uniform float vida : hint_range(0.0, 1.0) = 1.0;
uniform int forma = 0;

void vertex() {
	// Billboard: conserva la escala del nodo y orienta el quad a la cámara.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0] * length(MODEL_MATRIX[0].xyz),
		INV_VIEW_MATRIX[1] * length(MODEL_MATRIX[1].xyz),
		INV_VIEW_MATRIX[2] * length(MODEL_MATRIX[2].xyz),
		MODEL_MATRIX[3]);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = 0.0;
	if (forma == 0) {
		float nucleo = smoothstep(0.45, 0.0, r);
		float estrella = max(smoothstep(0.09, 0.0, abs(p.x)) * smoothstep(1.0, 0.1, abs(p.y)),
				smoothstep(0.09, 0.0, abs(p.y)) * smoothstep(1.0, 0.1, abs(p.x)));
		a = nucleo * 1.4 + estrella;
	} else {
		float radio = mix(0.35, 0.92, 1.0 - vida);
		a = smoothstep(0.10, 0.0, abs(r - radio)) * 1.2;
	}
	a *= vida * smoothstep(1.0, 0.85, r);
	ALBEDO = color.rgb * a;
}
