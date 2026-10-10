shader_type spatial;
// =============================================================================
//  shockwave.gdshader — anillo de energía que se abre desde el punto de impacto
// =============================================================================
//  Se aplica a un QuadMesh tumbado en el suelo. El uniform "progreso" va de 0
//  (nace) a 1 (se apaga): el anillo se abre del centro al borde y se desvanece.
//  Suma luz (blend_add), así que parece energía y no un objeto sólido.
// =============================================================================
render_mode blend_add, cull_disabled, unshaded, shadows_disabled;

uniform float progreso : hint_range(0.0, 1.0) = 0.0;
uniform vec3 color : source_color = vec3(1.0, 0.72, 0.35);
uniform float grosor : hint_range(0.01, 0.6) = 0.13;
uniform float intensidad : hint_range(0.0, 12.0) = 4.0;

void fragment() {
	// Distancia al centro del cuadro: 0 en el centro, 1 en el borde.
	float d = length(UV - vec2(0.5)) * 2.0;

	// El aro se abre del centro al borde conforme avanza el impacto.
	float radio = mix(0.04, 1.0, progreso);
	float anillo = 1.0 - smoothstep(0.0, grosor, abs(d - radio));

	// Se apaga al final, y de golpe: un golpe seco, no una niebla.
	float vida = 1.0 - progreso;
	float a = anillo * vida * vida;

	ALBEDO = color;
	EMISSION = color * a * intensidad;
	ALPHA = a;
}
