shader_type canvas_item;
render_mode unshaded;

// Recorta la imagen del minimapa a las MISMAS esquinas redondeadas que el marco,
// para que imagen y borde parezcan un único componente. Es un efecto local barato
// (unos pocos cálculos por píxel), NO un posprocesado de pantalla completa.

uniform float radio : hint_range(0.0, 400.0) = 20.0;
uniform vec2 tam = vec2(170.0, 170.0);

void fragment() {
	// Distancia (SDF) al rectángulo redondeado; alfa 0 fuera de él.
	vec2 media = tam * 0.5;
	vec2 q = abs(UV * tam - media) - (media - vec2(radio));
	float d = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radio;
	float a = 1.0 - smoothstep(-1.0, 1.0, d);
	// IMPORTANTE: NO multiplicar la textura por COLOR. En Godot 4, el `COLOR` de
	// entrada del fragmento ya lleva la textura (y el modulate); volver a
	// multiplicarla la elevaba al cuadrado y oscurecía el minimapa (parecía de
	// noche a plena luz del día). Se escribe el color tal cual y sólo se recorta
	// el alfa a la forma redondeada.
	COLOR = texture(TEXTURE, UV);
	COLOR.a *= a;
}