shader_type spatial;
// =============================================================================
//  VENTANAS ENCENDIDAS DE NOCHE
// =============================================================================
//  Paño pequeño que se coloca delante del vidrio de algunas ventanas de los
//  edificios y se ve como una luz interior cálida. Lo actualiza
//  `world/luces_ventanas.gd`, que le pasa el factor noche del ciclo de día y
//  noche del juego (0 de día -> invisible; 1 de noche -> encendido).
//
//  Sin sombras y SIN DEPENDER DEL BRILLO (glow): el color del paño ya es un
//  amarillo cálido visible a cualquier distancia; el brillo del entorno (si el
//  mapa lo tuviera activado) sólo lo realzaría de forma suave.
//
//  Por instancia (datos de INSTANCE_CUSTOM de la MultiMesh):
//    x = brillo relativo (0.45..1.35): ventanas más tenues y más vivas
//    y = calidez (0..1): de naranja doméstico a amarillo pálido de oficina
// =============================================================================

render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

// Factor noche (0 = día, 1 = noche cerrada). Lo mueve `luces_ventanas.gd`.
uniform float noche : hint_range(0.0, 1.0) = 0.0;
// Intensidad global del color (subirla/ bajarla regula todas las ventanas).
uniform float intensidad : hint_range(0.0, 3.0) = 1.12;

varying vec4 datos;

void vertex() {
	datos = INSTANCE_CUSTOM;
}

void fragment() {
	float brillo = clamp(datos.x, 0.0, 1.6);
	float calidez = clamp(datos.y, 0.0, 1.0);
	// Dos extremos de luz doméstica: naranja cálida y amarillo claro.
	vec3 color_calido = mix(vec3(1.0, 0.60, 0.24), vec3(1.0, 0.87, 0.55), calidez);
	ALBEDO = color_calido * intensidad * brillo;
	// Alfa por noche: durante el día (noche=0) el paño no se ve.
	ALPHA = noche * (0.74 + 0.26 * clamp(brillo, 0.0, 1.0));
}