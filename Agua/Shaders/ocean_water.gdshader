shader_type spatial;
// =============================================================================
//  SUPERFICIE DEL OCÉANO  (adaptación de res://Agua/Shaders/water_surface.gdshader)
// =============================================================================
//  El shader original NO se modifica: este archivo es su adaptación al tamaño
//  real del mundo. Se conservan tal cual los colores, la transparencia, el
//  fresnel, la reflexión del cielo, el degradado por profundidad, la textura de
//  ondulaciones y sus parámetros.
//
//  Sólo se cambia lo que dependía de las medidas del plano original (592x508 m):
//
//   1) UV de MUNDO. El original usaba UV*22 y UV*38 sobre aquel plano; aquí se
//      toma la posición de mundo multiplicada por las mismas repeticiones POR
//      METRO, de modo que cada ondulación mide lo mismo que antes (unos 27 m y
//      16 m) por mucha que sea la extensión del océano. Sin esto, al agrandar
//      el plano las ondulaciones se estirarían hasta desaparecer.
//
//   2) Mar de fondo de los vértices. La malla del océano tiene cuadros de ~80 m,
//      así que la frecuencia original (ondas de 125 m) quedaría muestreada de
//      forma insuficiente: se usa una ondulación larga (unos 900 m) y suave
//      (15 cm) que sí es representable y no inunda la playa.
//
//   La atenuación de las ondulaciones con la distancia y el degradado por
//   profundidad quedan como estaban: el shader original ya los medía respecto
//   de la cámara (VERTEX en la función fragment está en espacio de vista).
// =============================================================================
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec3 color_shallow : source_color = vec3(0.40, 0.70, 0.79);
uniform vec3 color_deep : source_color = vec3(0.03, 0.20, 0.38);
uniform float alpha_shallow : hint_range(0.0, 1.0) = 0.10;
uniform float alpha_deep : hint_range(0.0, 1.0) = 0.78;
uniform float depth_fade = 16.0;
uniform vec3 sky_reflection : source_color = vec3(0.60, 0.72, 0.84);
uniform float wave_amplitude = 0.15;
uniform float wave_frequency = 0.007;
uniform float wave_speed = 1.0;
uniform sampler2D ripple_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D depth_tex : hint_depth_texture;

// Repeticiones por metro equivalentes al material original: 22 y 38 repeticiones
// sobre el plano de 592x508 m de la escena del asset.
const vec2 UV1_POR_METRO = vec2(0.0371622, 0.0433071);
const vec2 UV2_POR_METRO = vec2(0.0641892, 0.0748031);
// Radio (m) en el que las ondulaciones se desvanecen alrededor de la cámara.
// El asset usaba 220 m sobre un plano de 592x508 m; con un océano abierto ese
// radio dejaba el mar liso a partir de unos cientos de metros, así que se amplía
// para que el agua tenga textura a media distancia (la textura de ondulaciones
// conserva sus mipmaps, de modo que a lo lejos no produce aliasing).
const float RADIO_ONDULACION = 700.0;

varying vec2 uv_mundo;

void vertex() {
	uv_mundo = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
	float w = sin(VERTEX.x * wave_frequency + TIME * wave_speed)
		+ cos(VERTEX.z * wave_frequency * 1.3 - TIME * wave_speed * 0.8);
	VERTEX.y += w * wave_amplitude * 0.5;
}

void fragment() {
	float raw_depth = texture(depth_tex, SCREEN_UV).r;
	vec4 scene_pos = INV_PROJECTION_MATRIX * vec4(vec3(SCREEN_UV * 2.0 - 1.0, raw_depth), 1.0);
	float scene_dist = -(scene_pos.z / scene_pos.w);
	float thickness = clamp((scene_dist + VERTEX.z) / depth_fade, 0.0, 1.0);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	float fade = 1.0 - clamp(length(VERTEX) / RADIO_ONDULACION, 0.0, 1.0);
	vec2 uv1 = uv_mundo * UV1_POR_METRO + vec2(TIME * 0.020, TIME * 0.014);
	vec2 uv2 = uv_mundo * UV2_POR_METRO - vec2(TIME * 0.013, TIME * 0.024);
	vec3 n1 = texture(ripple_tex, uv1).xyz * 2.0 - 1.0;
	vec3 n2 = texture(ripple_tex, uv2).xyz * 2.0 - 1.0;
	vec3 ripple = normalize(vec3(0.0, 0.0, 1.0) + vec3(n1.xy + n2.xy, 0.0) * fade * 0.28);
	NORMAL_MAP = ripple * 0.5 + 0.5;
	vec3 base = mix(color_shallow, color_deep, thickness * 0.92);
	ALBEDO = mix(base, sky_reflection, fres * 0.72);
	ALPHA = clamp(mix(alpha_shallow, alpha_deep, max(thickness, fres * 0.55)), 0.0, 1.0);
	ROUGHNESS = 0.14;
	SPECULAR = 0.45;
	METALLIC = 0.0;
}