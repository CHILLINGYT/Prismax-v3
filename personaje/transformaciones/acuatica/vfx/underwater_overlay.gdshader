shader_type canvas_item;
// =============================================================================
//  VISTA SUBACUATICA (capa de pantalla)
// =============================================================================
//  Lo que se ve CUANDO LA CAMARA ESTA BAJO EL AGUA: el color del agua tiñendo la
//  imagen, una ondulacion suave (como mirar a traves del agua en movimiento) y
//  una viñeta que cierra la vista.
//
//  No es un efecto decorativo: es lo que hace que se note que estas DENTRO del
//  agua y no mirando el lago desde fuera. La intensidad (`amount`) la sube el
//  script con la profundidad de la camara, asi que en la superficie apenas se ve
//  y en el fondo esta a tope.
//
//  `amount = 0` deja la pantalla tal cual.
// =============================================================================

// Imagen ya renderizada, para poder ondularla.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
// Color del agua a esa profundidad (se lo pasa el script).
uniform vec3 tint : source_color = vec3(0.05, 0.28, 0.40);
// Cuanto tiñe el agua (0..1), ya escalado por la profundidad.
uniform float tint_strength : hint_range(0.0, 1.0) = 0.55;
// Cuanto ondula la imagen (0 = nada).
uniform float wobble : hint_range(0.0, 1.0) = 1.0;
// Fuerza de la viñeta.
uniform float vignette : hint_range(0.0, 2.0) = 1.0;
// 0 = camara fuera del agua, 1 = completamente dentro.
uniform float amount : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	if (amount <= 0.001) {
		// Fuera del agua: la capa no toca la imagen.
		COLOR = texture(screen_tex, SCREEN_UV);
	} else {
		// --- Ondulacion: dos senos cruzados que desplazan la imagen leidos ---
		vec2 uv = SCREEN_UV;
		float w = wobble * 0.0045 * amount;
		uv += vec2(
			sin(uv.y * 26.0 + TIME * 1.25) + sin(uv.y * 9.0 - TIME * 0.7),
			cos(uv.x * 21.0 + TIME * 1.05) + cos(uv.x * 7.0 + TIME * 0.6)
		) * w * 0.5;
		vec3 col = texture(screen_tex, uv).rgb;

		// --- Absorcion de color: cuanto mas hondo, mas manda el azul ---
		// Se oscurece el rojo mas que el azul, como hace el agua de verdad.
		float a = amount;
		vec3 water = tint;
		col = mix(col, col * vec3(0.62, 0.88, 1.0), a);
		col = mix(col, water, tint_strength * a);

		// --- Viñeta: el agua se cierra alrededor de la vista ---
		vec2 d = SCREEN_UV - vec2(0.5);
		float v = smoothstep(0.30, 0.85, length(d) * 1.35);
		col *= 1.0 - 0.45 * a * v * vignette;

		COLOR = vec4(col, 1.0);
	}
}
