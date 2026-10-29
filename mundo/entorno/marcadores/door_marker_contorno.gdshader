shader_type spatial;
// Contorno oscuro de la flecha (casco invertido): legibilidad de día sobre
// fondos claros (cielo, fachadas blancas). Se dibuja sólo por las caras traseras.
render_mode unshaded, cull_front, shadows_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(0.12, 0.07, 0.0, 1.0);

void fragment() {
	ALBEDO = color.rgb;
}
