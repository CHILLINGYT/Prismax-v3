shader_type spatial;
// DESTELLO DE IMPACTO sobre el enemigo golpeado (JuiceCombate).
// Se aplica como `material_overlay` de sus mallas durante ~0,1 s: vuelve a pintar
// la misma geometría ENCIMA, en modo aditivo, sin tocar sus materiales ni el
// modelo. Más intenso en el contorno (fresnel) para que la silueta "estalle".
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.94, 0.82, 1.0);
uniform float fuerza : hint_range(0.0, 1.0) = 0.0;
uniform float borde = 2.0;

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), borde);
	ALBEDO = color.rgb * fuerza * (0.45 + 1.4 * fres);
}
