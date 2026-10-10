shader_type spatial;
// =============================================================================
//  SUPERFICIE DE AGUA  (shader propio, 100% nativo de Godot)
// =============================================================================
//  NO es el addon "Stylized Water Shader": esto es un .gdshader escrito a mano
//  que solo usa lo que Godot trae de serie. No necesita ninguna textura ni
//  ningun recurso externo: las olas, la espuma y el oleaje son funciones
//  matematicas, no imagenes.
//
//  Que hace, y por que cada cosa:
//
//   * OLAS EN EL VERTICE: desplaza la superficie con una suma de senos. Es lo
//     que hace que el agua no sea un cristal plano. El desplazamiento se calcula
//     con la posicion en el MUNDO, asi que la ola "viaja" por el lago y no se
//     queda pegada al objeto.
//
//   * NORMAL ANALITICA: la normal se saca derivando la misma funcion de olas por
//     diferencias finitas en el fragmento. Es lo que hace que el brillo del sol
//     (specular) se mueva con las olas en vez de ser un punto fijo.
//
//   * PROFUNDIDAD: se lee la profundidad de la escena con hint_depth_texture y
//     se compara con la del propio agua. La diferencia es el ESPESOR de agua que
//     hay entre el ojo y el fondo. Con eso:
//       - el color va de claro (orilla) a oscuro (fondo),
//       - la transparencia tambien (en la orilla se ve el fondo, en el centro no),
//       - y sale GRATIS el borde de espuma: donde el agua es muy fina, es espuma.
//
//   * REFRACCION: se vuelve a leer la pantalla ya dibujada con hint_screen_texture
//     y se desplaza un poco segun la normal. Es lo que hace que el fondo se vea
//     "doblado" al mirar a traves del agua.
//
//   * BRILLO ESPECULAR Y FRESNEL: en angulo rasante el agua refleja mas (fresnel)
//     y con rugosidad baja el sol deja un brillo duro encima. Es lo que la hace
//     parecer liquida.
// =============================================================================

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;

uniform vec4 shallow_color : source_color = vec4(0.10, 0.34, 0.40, 1.0);
uniform vec4 deep_color : source_color = vec4(0.004, 0.026, 0.085, 1.0);
uniform vec4 foam_color : source_color = vec4(0.88, 0.96, 1.0, 1.0);
// Color del cielo que "refleja" el agua en angulo rasante (fresnel). Un poco mas
// claro y mas azul que el horizonte real, para que el lago no se funda con el.
uniform vec4 sky_reflection : source_color = vec4(0.44, 0.62, 0.88, 1.0);

// Metros de agua que hacen falta para que el color llegue al "fondo".
uniform float depth_scale = 3.0;
// Opacidad maxima (en el centro del lago).
uniform float max_opacity = 0.95;
// Altura de la ola en metros (de pico).
uniform float wave_height = 0.08;
// Velocidad de la ola.
uniform float wave_speed = 0.9;
// Cuanto dobla la imagen lo que se ve a traves del agua.
uniform float refraction_strength = 0.25;
// Exponente del fresnel. ALTO a proposito: asi el reflejo solo aparece en
// angulos muy rasantes y el agua no se ve gris y lavada de frente.
uniform float fresnel_power = 5.5;
// Cuanto se exagera la normal de las olas. Las olas GEOMETRICAS son bajas (para
// que la superficie no se vea como un mar picado), pero la normal se exagera
// para que la luz del sol si se mueva por encima.
uniform float normal_strength = 2.1;
// Ancho (m) de la banda de espuma de la orilla.
uniform float foam_width = 0.5;
uniform float specular_shine = 0.55;
// Oclusion ambiental. El agua se ilumina sobre todo con su PROPIO color y con el
// sol: si se le deja el ambiente entero, un cielo claro y plano la deja gris y
// lavada (el agua acaba pareciendo el cielo). Bajando el ambiente el color del
// agua manda y el brillo del sol sigue ahi.
uniform float ambient_occlusion = 0.55;

varying vec3 wpos;

// --- Olas ---------------------------------------------------------------------
// Suma de senos en direcciones distintas. Se usa LA MISMA funcion en el vertice
// (para mover) y en el fragmento (para la normal y la espuma), o la luz no
// cuadraria con la forma.
float water_wave(vec2 p, float t) {
	float h = sin(p.x * 0.62 + t * 1.15) * 0.50;
	h += sin(p.y * 0.83 - t * 0.97) * 0.34;
	h += sin((p.x + p.y) * 0.45 + t * 1.63) * 0.28;
	h += sin((p.x - p.y) * 1.21 - t * 0.71) * 0.16;
	// Dos terminos de frecuencia alta: casi no mueven la forma, pero son los que
	// dan el "hormigueo" de la luz sobre el agua.
	h += sin(p.x * 1.9 + p.y * 0.7 + t * 2.30) * 0.11;
	h += sin(p.x * -0.9 + p.y * 2.4 - t * 2.90) * 0.08;
	return h * 0.5;
}

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME * wave_speed;
	float h = water_wave(world.xz, t) * wave_height;
	// El lago se coloca sin rotar, asi que subir la Y del mundo es lo mismo que
	// subir la Y local. Si algun dia se rota el plano, hay que cambiar esto.
	VERTEX.y += h;
	wpos = world + vec3(0.0, h, 0.0);
}

void fragment() {
	float t = TIME * wave_speed;

	// --- Normal a partir de las olas (diferencias finitas) ---
	float e = 0.22;
	float h0 = water_wave(wpos.xz, t) * wave_height;
	float hx = water_wave(wpos.xz + vec2(e, 0.0), t) * wave_height;
	float hz = water_wave(wpos.xz + vec2(0.0, e), t) * wave_height;
	vec3 n = normalize(vec3((h0 - hx) / e * normal_strength, 1.0, (h0 - hz) / e * normal_strength));
	// Visto desde abajo (buceando) la cara es la de atras: se le da la vuelta a
	// la normal para que se ilumine igual.
	if (!FRONT_FACING) {
		n = -n;
	}
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);

	// --- Espesor de agua entre la camara y el fondo ---
	float scene_raw = texture(depth_tex, SCREEN_UV).x;
	vec4 vpos = INV_PROJECTION_MATRIX * vec4(vec3(SCREEN_UV * 2.0 - 1.0, scene_raw), 1.0);
	float scene_dist = -(vpos.z / vpos.w);
	// En el fragmento, VERTEX es la posicion en el espacio de la camara.
	float water_dist = -VERTEX.z;
	float thickness = max(scene_dist - water_dist, 0.0);
	float depth_factor = clamp(thickness / depth_scale, 0.0, 1.0);

	// --- Refraccion: se mira la pantalla con un pequeno desplazamiento ---
	vec2 offset = n.xz * refraction_strength * depth_factor / max(water_dist, 1.0);
	vec3 behind = texture(screen_tex, SCREEN_UV + offset).rgb;

	// --- Color y transparencia ---
	// Lo que hay DETRAS (el fondo) se tiñe con el color del agua, y cuanto mas
	// espesor de agua hay, menos fondo se ve. En la orilla manda el fondo; en el
	// centro del lago manda el color del agua.
	//
	// Ojo con hacerlo al reves (mezclar el color del agua "encima" del fondo con
	// un factor menor que 1): el fondo claro se cuela como gris y el lago entero
	// acaba viendose gris y lavado en vez de azul.
	vec3 tint = mix(shallow_color.rgb, deep_color.rgb, depth_factor);
	vec3 albedo = mix(behind, tint, mix(0.55, 1.0, depth_factor));

	// Fresnel: en angulo rasante el agua refleja el cielo. Se le da un tono azul
	// propio en vez del color del cielo, o el lago se confunde con el horizonte.
	//
	// El fresnel solo manda de verdad a ras de agua (mirando de pie desde la
	// orilla, por ejemplo), que es justo cuando un lago real se ve casi blanco de
	// puro reflejo. De frente vale 0, asi que subirlo NO lava el color del centro:
	// solo cambia como se ve el agua desde muy bajo.
	float fresnel = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), fresnel_power);
	albedo = mix(albedo, sky_reflection.rgb, fresnel * 0.85);

	// --- Espuma de la orilla ---
	float shore = 1.0 - smoothstep(0.0, foam_width, thickness);
	// El borde de la espuma ondula para que no sea una linea recta.
	float ripple = water_wave(wpos.xz * 2.7, t * 1.8) * 0.5 + 0.5;
	shore *= clamp(ripple * 1.35, 0.0, 1.0);

	float alpha = mix(0.12, max_opacity, depth_factor);
	alpha = mix(alpha, 0.97, fresnel * 0.7);
	albedo = mix(albedo, foam_color.rgb, shore);
	alpha = mix(alpha, 0.92, shore);

	// --- Visto desde DENTRO del agua (buceando por debajo) ---
	// Desde abajo la superficie deja de ser un cristal y pasa a ser un ESPEJO:
	// es la reflexion total interna. Se ve una techumbre oscura y lisa, con la luz
	// del sol estirada por las crestas, en vez del techo transparente de arriba.
	// Se sabe si la camara esta por debajo comparando su altura en el mundo con la
	// del fragmento: si la camara esta mas baja, se mira desde dentro.
	vec3 cam_world = INV_VIEW_MATRIX[3].xyz;
	float from_below = clamp((wpos.y - cam_world.y) * 3.0, 0.0, 1.0);
	if (from_below > 0.001) {
		vec3 mirror = mix(deep_color.rgb * 2.4, sky_reflection.rgb, 0.30);
		albedo = mix(albedo, mirror, from_below * 0.72);
		alpha = mix(alpha, 1.0, from_below);
		AO = mix(AO, 1.0, from_below);
		ROUGHNESS = mix(ROUGHNESS, 0.02, from_below);
	}

	ALBEDO = albedo;
	ALPHA = clamp(alpha, 0.0, 1.0);
	// Rugosidad muy baja: asi el sol deja un brillo duro y movil sobre las olas.
	ROUGHNESS = 0.06;
	METALLIC = 0.0;
	SPECULAR = specular_shine;

	if (from_below <= 0.001) {
		AO = ambient_occlusion;
	}
}
