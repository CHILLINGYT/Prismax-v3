shader_type canvas_item;
render_mode unshaded;

// Desenfoque de pantalla para el menu de pausa.
// No modifica modelos ni materiales del mundo: solo difumina la imagen que ya
// se renderizo antes que esta capa (el mundo actual + HUD). A "cantidad" 0 el
// resultado es identico al mundo sin desenfocar, lo que permite la transicion
// suave abriendo el parametro de 0 a 1.

uniform float cantidad : hint_range(0.0, 1.0) = 0.0;
uniform sampler2D pantalla : hint_screen_texture, filter_linear_mipmap;

void fragment() {
	vec2 uv = SCREEN_UV;

	// Desenfoque por niveles de mip, mezclando dos niveles adyacentes para que
	// el borde no quede "blocado". 4.5 niveles sobre 1280x720 es un borroso
	// claramente visible pero todavia reconocible.
	float nivel = cantidad * 3.0;
	float bajo = floor(nivel);
	float mezcla = fract(nivel);
	vec3 col = textureLod(pantalla, uv, bajo).rgb * (1.0 - mezcla)
			+ textureLod(pantalla, uv, bajo + 1.0).rgb * mezcla;

	// Dos tomas desplazadas para suavizar aun mas sin coste apreciable.
	float r = cantidad * 0.004;
	col += textureLod(pantalla, uv + vec2(r, r), bajo).rgb;
	col += textureLod(pantalla, uv - vec2(r, r), bajo).rgb;
	col /= 3.0;

	COLOR = vec4(col, 1.0);
}