shader_type canvas_item;
render_mode blend_mix;

// Viñeta de daño del jugador de la partida principal.
//
// Oscurece y tiñe los BORDES de la pantalla dejando el centro despejado para no
// tapar la visibilidad del combate. La intensidad total (estado sostenido +
// pulso del golpe) y el COLOR los calcula hud_circular.gd a partir del estado
// REAL del escudo (EstadisticasJugador):
//   · con resistencia  -> tinte rojo azulado (el escudo amortiguó el golpe),
//   · escudo roto (0)  -> rojo puro, persistente, sin componente azul.
// Vive en la cámara/HUD compartidos, así que sigue funcionando con cualquier
// representación del personaje (humano, velocista, pes, tanque o combate).

// Tinte del borde. Lo fija el script según el estado del escudo.
uniform vec4 color : source_color = vec4(0.78, 0.2, 0.52, 1.0);
// Intensidad total ya calculada en GDScript (0 = sin efecto, 1 = borde lleno).
uniform float intensidad : hint_range(0.0, 1.0) = 0.0;
// Radio (normalizado al borde de la pantalla) donde arranca el efecto y donde
// llega al máximo: en medio queda "despejado" para leer el combate.
uniform float radio_despejado : hint_range(0.0, 1.5) = 0.62;
uniform float radio_borde : hint_range(0.05, 2.0) = 1.3;
// Cuánto se oscurece el tinte en el borde (0 = color puro, 1 = casi negro).
uniform float oscuridad : hint_range(0.0, 1.0) = 0.35;

void fragment() {
	// Coordenadas centradas: la viñeta sigue la forma de la ventana (elipse
	// inscrita), así que el tinte abraza los bordes sea cual sea la relación de
	// aspecto y el centro queda libre para el combate.
	vec2 c = UV * 2.0 - vec2(1.0);
	float d = length(c); // 0 en el centro, 1 en el medio de cada borde, 1.41 en las esquinas
	float mascara = smoothstep(radio_despejado, radio_borde, d);
	float a = clamp(mascara * intensidad, 0.0, 1.0);
	vec3 rgb = mix(color.rgb, color.rgb * 0.35, oscuridad);
	COLOR = vec4(rgb, a * color.a);
}