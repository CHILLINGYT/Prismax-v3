shader_type spatial;
// =============================================================================
//  TERRENO DE LA ISLA
// =============================================================================
//  Color por ALTURA y PENDIENTE: fondo marino, arena de playa, pasto, pasto
//  oscuro de las zonas altas y roca en las pendientes fuertes.
//
//  Detalles deliberados:
//    * cull_disabled: la malla polar del terreno se dibuja siempre, sea cual sea
//      el sentido de sus triángulos.
//    * La normal se toma del vértice en ESPACIO DE MUNDO y se fuerza hacia
//      arriba (el relieve nunca tiene caras boca abajo), así que el sombreado no
//      depende del sentido de los triángulos.
//    * No usa texturas: es barato a cualquier distancia y no hace falta
//      importar recursos nuevos.
// =============================================================================
render_mode cull_disabled, diffuse_burley, specular_disabled;

uniform vec3 color_fondo : source_color = vec3(0.055, 0.10, 0.145);
uniform vec3 color_arena : source_color = vec3(0.78, 0.72, 0.55);
uniform vec3 color_pasto : source_color = vec3(0.22, 0.38, 0.16);
uniform vec3 color_pasto_alto : source_color = vec3(0.15, 0.26, 0.13);
uniform vec3 color_roca : source_color = vec3(0.36, 0.34, 0.31);
uniform float nivel_mar = -2.0;
uniform float arena_hasta = -0.55;
uniform float pasto_alto_desde = 9.0;
uniform float pasto_alto_hasta = 22.0;
uniform float pendiente_desde = 0.30;
uniform float pendiente_hasta = 0.62;

varying vec3 n_mundo;
varying float h_mundo;

void vertex() {
	vec4 p = MODEL_MATRIX * vec4(VERTEX, 1.0);
	h_mundo = p.y;
	vec3 n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	n_mundo = n.y < 0.0 ? -n : n;
}

void fragment() {
	// Normal en espacio de vista a partir de la de mundo (siempre hacia arriba).
	NORMAL = normalize((VIEW_MATRIX * vec4(n_mundo, 0.0)).xyz);
	float pendiente = 1.0 - clamp(n_mundo.y, 0.0, 1.0);

	vec3 col = mix(color_arena, color_pasto, smoothstep(nivel_mar, arena_hasta, h_mundo));
	col = mix(col, color_pasto_alto, smoothstep(pasto_alto_desde, pasto_alto_hasta, h_mundo));
	col = mix(col, color_roca, smoothstep(pendiente_desde, pendiente_hasta, pendiente));
	// Bajo la superficie del mar, fondo marino oscuro.
	float bajo = 1.0 - smoothstep(nivel_mar - 1.5, nivel_mar, h_mundo);
	col = mix(col, color_fondo, bajo);

	ALBEDO = col;
	ROUGHNESS = 0.95;
	SPECULAR = 0.1;
}