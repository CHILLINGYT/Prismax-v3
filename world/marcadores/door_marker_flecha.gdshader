shader_type spatial;
// Cuerpo de la flecha del marcador de puerta (DoorMarker).
// Sin iluminación de escena (se ve IGUAL de día y de noche), pero con un
// sombreado propio según la cara respecto a la cámara para que se lea el VOLUMEN
// mientras gira, y un brillo de borde (fresnel) que la hace "encenderse".
render_mode unshaded, cull_back, shadows_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.78, 0.0, 1.0);
uniform float brillo : hint_range(0.0, 3.0) = 1.0;

void fragment() {
	// NORMAL y VIEW están en espacio de vista: la cara de frente, más clara.
	float frente = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float arriba = clamp(NORMAL.y * 0.5 + 0.5, 0.0, 1.0);
	float luz = 0.55 + 0.35 * frente + 0.15 * arriba;
	float borde = pow(1.0 - frente, 3.0);
	vec3 c = color.rgb * luz * brillo + vec3(1.0, 0.95, 0.7) * borde * 0.35 * brillo;
	ALBEDO = c;
}
