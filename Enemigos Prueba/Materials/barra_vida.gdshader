shader_type spatial;
render_mode unshaded, cull_disabled;

// Barra de vida de un enemigo de prueba, en UNA sola pieza (un quad).
//
// Antes eran dos quads superpuestos (fondo + relleno) con un pequeño
// desplazamiento en Z, y el relleno quedaba oculto tras el fondo según hacia
// dónde mirase el enemigo, porque el desplazamiento gira con él: ahora el
// fondo, el relleno y su color se pintan en el mismo quad y no pueden taparse.
//
// El material lo controla enemigo_prueba.gd con el uniforme `fraccion`
// (vida actual / vida máxima); el color del relleno pasa de rojo a verde con
// la vida, igual que antes.

// Vida restante normalizada (0 = vacío, 1 = lleno).
uniform float fraccion : hint_range(0.0, 1.0) = 1.0;
uniform vec4 color_fondo : source_color = vec4(0.16, 0.14, 0.17, 1.0);
uniform vec4 color_bajo : source_color = vec4(0.9, 0.25, 0.2, 1.0);
uniform vec4 color_lleno : source_color = vec4(0.28, 0.85, 0.32, 1.0);
// Margen del relleno dentro del fondo, en UV (arriba, abajo e izquierda).
uniform float marco : hint_range(0.0, 0.5) = 0.18;

void vertex() {
	// Billboard: la barra mira siempre a la cámara y no hereda la rotación del
	// enemigo (que gira para encarar al jugador).
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
			INV_VIEW_MATRIX[0],
			INV_VIEW_MATRIX[1],
			INV_VIEW_MATRIX[2],
			MODEL_MATRIX[3]);
}

void fragment() {
	float dentro = step(marco, UV.y) * step(UV.y, 1.0 - marco);
	dentro *= step(marco * 0.5, UV.x) * step(UV.x, 1.0 - marco * 0.5);
	float relleno = dentro * step(UV.x, fraccion);
	vec3 color_relleno = mix(color_bajo.rgb, color_lleno.rgb, fraccion);
	ALBEDO = mix(color_fondo.rgb, color_relleno, relleno);
}