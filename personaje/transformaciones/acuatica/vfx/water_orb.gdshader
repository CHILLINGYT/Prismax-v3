shader_type spatial;
// =============================================================================
//  ESFERA DE AGUA TRANSLUCIDA  -  shader propio, sin texturas
// =============================================================================
//  La usan el proyectil, la esfera de area (AoE) y la prision de agua.
//
//  Tres cosas la hacen parecer agua y no una bola de cristal:
//    * FRESNEL: el borde se ve mucho mas que el centro (como una pompa).
//    * REFRACCION: el fondo se dobla con hint_screen_texture.
//    * ONDULACION: la superficie se mueve (dos senos cruzados en el espacio).
//
//  El script le sube [member pulse] al liberar la habilidad para que de un
//  latigazo de brillo.
// =============================================================================
render_mode blend_mix, depth_draw_never, cull_disabled, specular_schlick_ggx, shadows_disabled;

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear_mipmap;

uniform vec4 core_color : source_color = vec4(0.10, 0.45, 0.72, 1.0);
uniform vec4 edge_color : source_color = vec4(0.70, 0.94, 1.0, 1.0);
// Opacidad base del centro (el borde siempre se ve mas por el fresnel).
uniform float opacity = 0.3;
uniform float fresnel_power = 2.4;
// Cuanto dobla la imagen del fondo.
uniform float refraction_strength = 0.05;
// Escala y velocidad de la ondulacion de la superficie.
uniform float ripple_scale = 6.0;
uniform float ripple_speed = 2.2;
// 0..1, latigazo de brillo al liberar.
uniform float pulse = 0.0;

void fragment() {
	float f = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), fresnel_power);
	// Dos senos cruzados sobre la posicion del vertice: la superficie "hierve".
	float ripple = sin((VERTEX.x + VERTEX.y * 1.3) * ripple_scale + TIME * ripple_speed) * 0.5
		+ sin((VERTEX.z - VERTEX.y) * ripple_scale * 1.27 - TIME * ripple_speed * 1.6) * 0.5;
	vec2 offset = normalize(NORMAL).xz * refraction_strength * (0.5 + ripple * 0.5);
	vec3 behind = texture(screen_tex, SCREEN_UV + offset * 0.1).rgb;
	vec3 c = mix(core_color.rgb, edge_color.rgb, clamp(f + ripple * 0.12, 0.0, 1.0));
	ALBEDO = mix(c, behind, 0.25);
	ALPHA = clamp(opacity + f * 0.55 + max(ripple, 0.0) * 0.06, 0.0, 0.92);
	ROUGHNESS = 0.05;
	METALLIC = 0.0;
	// Brillo propio: el agua de una habilidad tiene que leerse con poca luz.
	EMISSION = c * (0.10 + pulse * 0.6) * (0.35 + f);
}
