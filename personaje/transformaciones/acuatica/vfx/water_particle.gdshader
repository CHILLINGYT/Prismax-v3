shader_type spatial;
// =============================================================================
//  PARTICULA DE AGUA  (gota / espuma / gotitas)  -  shader propio, sin texturas
// =============================================================================
//  La forma de la gota NO es una imagen: es un degradado radial calculado en el
//  fragmento con la UV de la quad. Asi no hace falta ninguna textura externa.
//
//  Se usa desde GPUParticles3D (draw_pass_1 = QuadMesh con este material).
//
//  En vertex() se orienta la quad hacia la camara ("billboard" a mano): Godot 4
//  NO tiene un render_mode de billboard para shaders espaciales, la forma
//  oficial es reescribir MODELVIEW_MATRIX con la inversa de la vista.
// =============================================================================
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled, fog_disabled;

// Color de la particula. El alfa es la opacidad maxima.
uniform vec4 color : source_color = vec4(0.62, 0.86, 1.0, 0.9);
// Que proporcion del radio es "degradado". Mas alto = borde mas suave.
uniform float softness = 0.8;
// Cuanto se aclara el borde de la gota (le da volumen de esfera).
uniform float rim_strength = 0.6;
// 1 = la particula se desvanece segun su vida (solo para GPUParticles3D).
uniform float lifetime_fade = 1.0;

// INSTANCE_CUSTOM solo existe en vertex(), asi que la fase de vida se pasa al
// fragmento por un varying.
varying float life_phase;

void vertex() {
	// Billboard manual: la quad mira siempre a la camara y conserva su tamano.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0],
		INV_VIEW_MATRIX[1],
		INV_VIEW_MATRIX[2],
		MODEL_MATRIX[3]);
	life_phase = INSTANCE_CUSTOM.y;
}

void fragment() {
	// d = 0 en el centro de la quad, 1 en el borde del circulo inscrito.
	float d = length(UV - vec2(0.5)) * 2.0;
	float body = 1.0 - smoothstep(1.0 - softness, 1.0, d);
	// Anillo del borde: aclara la gota para que no parezca una mancha plana.
	float rim = smoothstep(1.0 - softness, 1.0 - softness * 0.3, d)
		* (1.0 - smoothstep(1.0 - softness * 0.3, 1.02, d));
	vec3 c = mix(color.rgb, color.rgb * 1.45 + vec3(0.05), rim * rim_strength);
	ALBEDO = c;
	float a = body * color.a;
	if (lifetime_fade > 0.5) {
		// La particula entra y sale suave en vez de aparecer y desaparecer a
		// golpe: es la mitad de que una salpicadura se vea bien.
		a *= smoothstep(0.0, 0.12, life_phase) * (1.0 - smoothstep(0.55, 1.0, life_phase));
	}
	ALPHA = clamp(a, 0.0, 1.0);
}
