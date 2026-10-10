shader_type canvas_item;
render_mode unshaded;

// Triángulo del logo de carga (inspirado en la referencia de "prismax"):
// una silueta oscura que se rellena con un degradado arcoíris de IZQUIERDA a
// DERECHA según 'progress' (0..1). Fuera del triángulo el alfa es 0, así que
// nunca aparece un rectángulo de color por detrás de la geometría.
//
// Todo se calcula en PÍXELES usando 'tam' (el tamaño real del Control), de modo
// que el borde y el frente de relleno tienen el mismo grosor en todo el borde y
// no se deforman con la relación de aspecto.

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec2 tam = vec2(140.0, 121.0);

// Extremos del espectro a lo ancho del triángulo, en matiz HSV: el izquierdo es
// amarillo-verdoso y el derecho, violeta-magenta, como en la referencia. La
// mezcla pasa por verde, cian y azul.
uniform float hue_ini = 0.18;
uniform float hue_fin = 0.92;
uniform float saturacion : hint_range(0.0, 1.0) = 0.85;
uniform float valor : hint_range(0.0, 1.0) = 1.0;

// Estado apagado (antes de rellenar) y borde fino que deja ver la silueta.
uniform vec3 color_apagado = vec3(0.045, 0.050, 0.060);
uniform vec3 color_borde = vec3(0.200, 0.210, 0.240);
uniform float grosor_borde = 1.4;
uniform float suavidad = 0.05;   // ancho del frente de relleno (en UV.x)

vec3 hsv2rgb(vec3 c) {
	vec3 rgb = clamp(abs(mod(c.x * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
	return c.z * mix(vec3(1.0), rgb, c.y);
}

void fragment() {
	vec2 p = UV * tam;
	vec2 a = vec2(tam.x * 0.5, 0.0);   // punta (arriba)
	vec2 b = vec2(0.0, tam.y);         // base izquierda
	vec2 c = vec2(tam.x, tam.y);       // base derecha

	// Distancia con signo a cada arista (normales hacia el interior): para un
	// polígono convexo, el mínimo es la distancia con signo (positiva dentro).
	float d0 = dot(p - a, normalize(vec2((b - a).y, -(b - a).x)));
	float d1 = dot(p - b, normalize(vec2((c - b).y, -(c - b).x)));
	float d2 = dot(p - c, normalize(vec2((a - c).y, -(a - c).x)));
	float sd = min(d0, min(d1, d2));

	// Máscara del triángulo (con suavizado de un píxel en el canto).
	float mask = smoothstep(-0.75, 0.75, sd);

	// Frente de relleno: se desplaza de fuera-izquierda a fuera-derecha, así con
	// progress = 0 no hay color y con progress = 1 el triángulo queda entero. El
	// límite se suaviza con smoothstep (nada de saltos bruscos).
	float corte = mix(-suavidad, 1.0 + suavidad, clamp(progress, 0.0, 1.0));
	float relleno = 1.0 - smoothstep(corte - suavidad, corte, UV.x);

	float hue = mix(hue_ini, hue_fin, clamp(UV.x, 0.0, 1.0));
	vec3 arcoiris = hsv2rgb(vec3(hue, saturacion, valor));

	vec3 col = mix(color_apagado, arcoiris, relleno);
	// Borde fino sólo en la zona todavía sin color: la silueta se distingue al
	// principio y desaparece a medida que el degradado la va cubriendo.
	float borde = (1.0 - relleno) * (1.0 - smoothstep(grosor_borde, grosor_borde + 1.0, sd));
	col = mix(col, color_borde, borde);

	COLOR = vec4(col, mask);
}