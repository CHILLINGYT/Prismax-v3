shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec3 color_shallow : source_color = vec3(0.40, 0.70, 0.79);
uniform vec3 color_deep : source_color = vec3(0.03, 0.20, 0.38);
uniform float alpha_shallow : hint_range(0.0, 1.0) = 0.10;
uniform float alpha_deep : hint_range(0.0, 1.0) = 0.78;
uniform float depth_fade = 16.0;
uniform vec3 sky_reflection : source_color = vec3(0.60, 0.72, 0.84);
uniform float wave_amplitude = 0.13;
uniform float wave_frequency = 0.05;
uniform float wave_speed = 1.0;
uniform sampler2D ripple_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D depth_tex : hint_depth_texture;

void vertex() {
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
	float dist = length(VERTEX);
	float fade = 1.0 - clamp(dist / 220.0, 0.0, 1.0);
	vec2 uv1 = UV * 22.0 + vec2(TIME * 0.020, TIME * 0.014);
	vec2 uv2 = UV * 38.0 - vec2(TIME * 0.013, TIME * 0.024);
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