shader_type spatial;
// =============================================================================
//  ONDA / ANILLO DE AGUA  -  shader propio, sin texturas
// =============================================================================
//  Una quad PLANA (PlaneMesh) tumbada sobre el agua o sobre el suelo, con un
//  anillo dibujado por matematicas: sirve para la salpicadura de entrar al agua,
//  el golpe de un proyectil, la explosion de la esfera o la estela al nadar.
//
//  El anillo se abre solo: [member progress] va de 0 a 1 y con el crece el radio
//  y se desvanece. Lo mueve el script (WaterEffects).
// =============================================================================
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(0.88, 0.96, 1.0, 1.0);
// 0 = anillo cerrado en el centro, 1 = anillo en el borde de la quad.
uniform float progress = 0.0;
// Grosor del anillo (en fraccion del radio de la quad).
uniform float thickness = 0.22;
// Opacidad global. La baja el script mientras la onda se abre.
uniform float strength = 1.0;
// Ondulacion del anillo, para que no sea un circulo perfecto.
uniform float waviness = 0.06;

void fragment() {
	vec2 p = (UV - vec2(0.5)) * 2.0;
	float d = length(p);
	// El radio crece con el progreso.
	float r = mix(0.05, 0.98, progress);
	// El anillo no es perfecto: se ondula con el angulo.
	float ang = atan(p.y, p.x);
	r += sin(ang * 7.0) * waviness * progress;
	float ring = 1.0 - smoothstep(0.0, thickness * (1.0 - progress * 0.55), abs(d - r));
	// Se desvanece al final del recorrido.
	float fade = (1.0 - progress) * (1.0 - progress);
	ALBEDO = color.rgb;
	ALPHA = clamp(ring * fade * strength * color.a, 0.0, 1.0);
}
