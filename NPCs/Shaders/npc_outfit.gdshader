shader_type spatial;
// Recoloreado de ropa de los ciudadanos (City Folks / Urban Man).
//
// POR QUÉ UN SHADER: en los paquetes, cada prenda trae el color pintado en su textura y no hay
// variantes de color (se comprobó: hay un único *_AlstraInfinite1024_Main.png por pieza). Para
// tener "la misma camiseta en blanco, negro, azul, rojo y gris" hay que recolorear en tiempo de
// ejecución. Multiplicar por un color sólo puede OSCURECER (nunca da blanco), así que aquí se
// REEMPLAZA el color de la tela conservando su luminancia: el claro/oscuro de la textura sigue
// modulando el resultado, de modo que las costuras y los pliegues se siguen viendo, pero el color
// pasa a ser el de la variante.
//
// Se aplica SÓLO a las piezas medidas sin piel (ver NPCCitizenModel: "cap" y "ref" de cada pieza).
// Aun así, los píxeles con tono de piel se dejan intactos: una pieza con el cuello o los brazos al
// aire nunca acaba con la piel teñida.
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
// Color de la prenda y cuánto se impone sobre la textura (0 = original, 1 = sólo el color nuevo).
uniform vec3 outfit_color : source_color = vec3(1.0);
uniform float outfit_amount : hint_range(0.0, 1.0) = 0.85;
// Brillo medio de la prenda en su textura original (medido, en espacio lineal): hace que una tela
// oscura se recoloree con la misma viveza que una clara, en vez de salir apagada.
uniform float outfit_reference : hint_range(0.01, 1.0) = 0.1;
// Cuánto del claro/oscuro original se conserva al recolorear.
uniform float outfit_detail : hint_range(0.0, 1.0) = 0.8;
// Mismo acabado que el resto de las mallas (brillo suave y perfilado del contorno).
uniform float surface_roughness : hint_range(0.0, 1.0) = 0.6;
uniform float rim_amount : hint_range(0.0, 1.0) = 0.22;

void fragment() {
	vec3 base = texture(albedo_texture, UV).rgb;

	// Color de la tela: se parte del color de la variante y se le devuelve el claro/oscuro original.
	float lum = dot(base, vec3(0.2126, 0.7152, 0.0722));
	vec3 cloth = clamp(
		outfit_color * mix(1.0, lum / outfit_reference, outfit_detail), vec3(0.0), vec3(1.0)
	);

	// Protección de la piel: el tono se mide en espacio de pantalla (pow 1/2.2), que es donde los
	// valores son comparables con los medidos (piel ~(0,67 0,47 0,36), saturación 0,46).
	vec3 srgb = pow(base, vec3(0.4545));
	float mx = max(max(srgb.r, srgb.g), srgb.b);
	float mn = min(min(srgb.r, srgb.g), srgb.b);
	float sat = (mx - mn) / max(mx, 0.0001);
	bool skin_like = (srgb.r - srgb.g) > 0.05 && (srgb.g - srgb.b) > 0.05 && mx > 0.35 && sat < 0.55;

	ALBEDO = mix(base, cloth, skin_like ? 0.0 : outfit_amount);
	ROUGHNESS = surface_roughness;
	METALLIC = 0.0;
	RIM = rim_amount;
	// Godot colorea el contorno con un rosa por defecto (RIM_TINT), que en una prenda clara se
	// nota como si la tela fuese malva. 0.0 = blanco: sólo levanta el borde, sin teñir.
	RIM_TINT = 0.0;
}