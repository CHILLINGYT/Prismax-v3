shader_type canvas_item;
// EFECTO DE PANTALLA del combate (JuiceCombate), en una CanvasLayer por DEBAJO
// del HUD (la interfaz nunca se emborrona):
//  · blur RADIAL que nace en el punto del impacto (golpes pesados / remates);
//  · aberración cromática (separa rojo y azul hacia los bordes), en los mismos
//    golpes y, sola, al RECIBIR daño.
// El centro de la pantalla queda nítido (máscara radial) para no perder lectura.
uniform sampler2D pantalla : hint_screen_texture, filter_linear_mipmap;
uniform vec2 centro = vec2(0.5, 0.5);
uniform float blur : hint_range(0.0, 0.2) = 0.0;
uniform float aberracion : hint_range(0.0, 0.03) = 0.0;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 d = uv - centro;
	float mascara = smoothstep(0.06, 0.55, length(d));
	vec3 acum = vec3(0.0);
	const int N = 10;
	for (int i = 0; i < N; i++) {
		float t = float(i) / float(N - 1);
		vec2 o = -d * blur * mascara * t;
		vec2 ca = d * aberracion * mascara;
		acum.r += texture(pantalla, uv + o + ca).r;
		acum.g += texture(pantalla, uv + o).g;
		acum.b += texture(pantalla, uv + o - ca).b;
	}
	COLOR = vec4(acum / float(N), 1.0);
}
