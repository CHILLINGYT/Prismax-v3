shader_type canvas_item;

// Viñeta de daño del jugador: sombreado en los bordes IZQUIERDO y DERECHO, con
// el centro de la pantalla despejado para no tapar al personaje ni al combate.
// La mezcla va de rojo a azul oscuro concentrándose hacia el borde exterior.
// Todo lo maneja efecto_danio_pantalla.gd por uniforms (una sola capa: nunca se
// instancia nada por impacto).

uniform float intensidad : hint_range(0.0, 1.0) = 0.0;
uniform float mezcla_azul : hint_range(0.0, 1.0) = 0.45;
uniform vec4 color_rojo : source_color = vec4(0.82, 0.10, 0.09, 1.0);
uniform vec4 color_azul : source_color = vec4(0.10, 0.12, 0.32, 1.0);
// Exponente de la caída lateral: más alto = el sombreado se concentra más en el borde.
uniform float caida_lateral : hint_range(0.5, 8.0) = 2.6;

void fragment() {
	// 0 en el centro, 1 en los extremos izquierdo/derecho.
	float lateral = pow(clamp(abs(UV.x - 0.5) * 2.0, 0.0, 1.0), caida_lateral);
	// El azul oscuro solo aparece hacia el borde exterior: rojo dominante.
	vec3 col = mix(color_rojo.rgb, color_azul.rgb, mezcla_azul * lateral);
	COLOR = vec4(col, lateral * intensidad);
}