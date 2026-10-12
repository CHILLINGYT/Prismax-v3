shader_type canvas_item;
render_mode unshaded;

// Escala de grises para una tarjeta del menú de transformaciones.
// Se aplica SÓLO al TextureRect de la entrada "DEMO" (Águila/Vuelo); el resto
// de transformaciones no llevan este material. Conserva el alfa y respeta el
// "modulate" del nodo (hover/selección) al multiplicar por COLOR de entrada.

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	float gris = dot(tex.rgb, vec3(0.299, 0.587, 0.114));
	COLOR = vec4(vec3(gris), tex.a) * COLOR;
}