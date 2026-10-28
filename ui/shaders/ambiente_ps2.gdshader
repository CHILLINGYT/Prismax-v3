shader_type canvas_item;
// MODO DE AMBIENTE "PS2" — post-proceso sobre la imagen 3D (CanvasLayer por
// DEBAJO del HUD: la interfaz queda nítida).
//
// Lo que hace la firma visual de la PS2 (no la de la PS1):
//  · rejilla de baja resolución (~640x448): cada "píxel" de la consola se lee en
//    su centro, y se mezcla un poco con la imagen suave → píxel visible pero
//    blando, como en un televisor de la época, nunca "8 bits";
//  · framebuffer de 16 bits (5 bits por canal) con DITHERING ordenado 4x4 sobre
//    esa misma rejilla: la trama fina que se ve en la referencia;
//  · leve viñeta/scanline opcionales (por defecto casi nulos).
// La PS2 corregía la perspectiva de las texturas y no tenía el "temblor" de
// vértices de la PS1: por eso este modo NO los imita.

uniform sampler2D pantalla : hint_screen_texture, filter_linear;
uniform vec2 resolucion_baja = vec2(640.0, 448.0);
uniform float suavizado : hint_range(0.0, 1.0) = 0.35;
uniform float bits : hint_range(2.0, 8.0) = 5.0;
uniform float fuerza_dither : hint_range(0.0, 2.0) = 1.0;
uniform float scanlines : hint_range(0.0, 0.5) = 0.04;
uniform float vineta : hint_range(0.0, 1.0) = 0.18;

const float BAYER[16] = float[16](
	0.0, 8.0, 2.0, 10.0,
	12.0, 4.0, 14.0, 6.0,
	3.0, 11.0, 1.0, 9.0,
	15.0, 7.0, 13.0, 5.0);

void fragment() {
	vec2 px = SCREEN_UV * resolucion_baja;
	vec2 celda = floor(px);
	vec3 nitido = texture(pantalla, (celda + 0.5) / resolucion_baja).rgb;
	vec3 suave = texture(pantalla, SCREEN_UV).rgb;
	vec3 c = mix(nitido, suave, suavizado);
	// Cuantización a `bits` por canal con dithering ordenado en la rejilla baja.
	int i = int(mod(celda.y, 4.0)) * 4 + int(mod(celda.x, 4.0));
	float umbral = (BAYER[i] + 0.5) / 16.0 - 0.5;
	float niveles = exp2(bits) - 1.0;
	c = floor(c * niveles + 0.5 + umbral * fuerza_dither) / niveles;
	// Scanline muy suave (una por línea de la rejilla baja).
	c *= 1.0 - scanlines * (0.5 + 0.5 * cos(fract(px.y) * 6.2831853));
	// Viñeta leve de televisor.
	vec2 d = SCREEN_UV - 0.5;
	c *= 1.0 - vineta * smoothstep(0.35, 0.85, length(d * vec2(1.0, 0.85)));
	COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
}
