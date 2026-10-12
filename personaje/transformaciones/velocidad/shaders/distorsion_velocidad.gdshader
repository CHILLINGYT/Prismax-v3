shader_type canvas_item;

// Post-proceso de supervelocidad: distorsion radial + estelas + chromatic aberration + speed lines.
// intensidad 0 = imagen sin cambios. Se controla desde ziba/scripts/capa_velocidad.gd
uniform float intensidad : hint_range(0.0, 1.0) = 0.0;
uniform float tiempo = 0.0;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 centro = vec2(0.5);
	vec2 d = uv - centro;
	float r = length(d);
	vec2 dir = normalize(d + vec2(1e-5));
	float f = intensidad;

	// Chromatic aberration radial
	float off = f * 0.006 * (0.25 + r);
	vec3 col;
	col.r = texture(screen_tex, uv + dir * off).r;
	col.g = texture(screen_tex, uv).g;
	col.b = texture(screen_tex, uv - dir * off).b;

	// Radial blur / estelas hacia el centro
	const int N = 6;
	vec3 blur = vec3(0.0);
	float total = 0.0;
	for (int i = 1; i <= N; i++) {
		float ti = float(i) / float(N);
		float w = 1.0 - ti;
		blur += texture(screen_tex, uv + dir * ti * f * 0.045).rgb * w;
		total += w;
	}
	blur /= total;
	col = mix(col, blur, f * 0.45);

	// Speed lines radiales animadas
	float ang = atan(d.y, d.x);
	float lines = sin(ang * 44.0 + tiempo * 8.0) * 0.5 + 0.5;
	lines = pow(lines, 12.0) * smoothstep(0.18, 0.8, r);
	col += vec3(0.55, 0.85, 1.0) * lines * f * 0.22;

	// Vignette
	col *= 1.0 - r * f * 0.22;

	COLOR = vec4(col, 1.0);
}