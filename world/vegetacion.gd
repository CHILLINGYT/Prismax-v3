class_name Vegetacion
extends RefCounted
## =============================================================================
##  VEGETACIÓN EN TARJETAS CRUZADAS (árboles y arbustos)
## =============================================================================
##  Los dos generadores de vegetación del juego (el BOSQUE de la isla y la
##  vegetación del generador de CIUDAD) comparten aquí el modelo de las plantas.
##
##  Antes cada planta se construía con primitivas (cilindros, esferas y conos), lo
##  que daba siluetas de "círculos y triángulos". Ahora cada planta es una TARJETA
##  CRUZADA: la silueta real de un árbol/arbusto dibujada sobre un plano, repetida
##  en tres planos girados 60° entre sí. Es la técnica habitual para follaje
##  (mismo coste de dibujado que una primitiva, aspecto mucho más natural) y no
##  hay que importar ningún modelo nuevo: se reutilizan los dibujos que ya hay en
##  `res://assets/generated/`.
##
##  Claves del montaje:
##    * **Nada de billboard**: los planos están quietos, girados al azar, así que
##      la planta no gira mirando a la cámara (eso es lo que delata el cartón).
##    * **Tres planos cruzados**, no uno: desde cualquier ángulo se ve volumen.
##    * **Normal hacia arriba**: la luz incide igual en toda la copa y el follaje
##      no se ve "partido" en dos mitades (una iluminada y otra negra).
##    * **Recorte de alfa (alpha scissor)**: sin transparencias con ordenación, y
##      las plantas siguen proyectando sombra.
##    * **Mipmaps + anisotrópico**: sin eso las hojas parpadean y ensucian a
##      distancia.
##    * **Color por instancia**: cada ejemplar lleva su propio tono (y en el
##      bosque también su tamaño y su giro), así no hay dos iguales.
##
##  Es una clase de utilidades (RefCounted): se usan sus funciones estáticas y no
##  hace falta instanciar nada.
## =============================================================================

## Nº de planos de cada tarjeta cruzada.
const PLANOS := 3

## Las tres especies de que dispone el proyecto, con su proporción real
## (ancho/alto de la imagen) para que la tarjeta no deforme el dibujo.
## `res://assets/generated/` contiene los tres dibujos de vegetación del proyecto.
const ARBOL_A := "res://assets/generated/parque_arbol_a.png"
const ARBOL_B := "res://assets/generated/parque_arbol_b.png"
const ARBUSTO := "res://assets/generated/parque_arbusto.png"

## Especies de árbol que se reparten al azar (el bosque y la ciudad eligen de aquí).
const ARBOLES: Array = [ARBOL_A, ARBOL_B]

## Caché de materiales: una tarjeta por textura (se reutiliza en todos los trozos,
## de modo que no se crean cientos de materiales iguales).
static var _materiales: Dictionary = {}
static var _mallas: Dictionary = {}


## Material de follaje para una textura concreta de las anteriores.
static func material(ruta: String) -> StandardMaterial3D:
	if _materiales.has(ruta):
		return _materiales[ruta]
	var tex: Texture2D = load(ruta)
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.albedo_color = Color.WHITE
	m.roughness = 0.92
	# Recorte duro del alfa: nada de transparencias que ordenar y las plantas
	# siguen proyectando sombra como las demás geometrías.
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.45
	# Se ven los dos lados de cada plano.
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	# El tono de cada ejemplar llega por el color de instancia de la MultiMesh.
	m.vertex_color_use_as_albedo = true
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	# Muestreo de alfa por separado (evita el halo gris en los bordes).
	m.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_OFF
	# Algo de translucidez: las hojas a contraluz no quedan negras.
	m.backlight_enabled = true
	m.backlight = Color(1.0, 1.0, 0.9)
	# Un plano NO es una billboard: nada de girar mirando a la cámara.
	m.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	_materiales[ruta] = m
	return m


## Proporción (ancho/alto) del dibujo de una especie: la tarjeta mide lo mismo que
## la figura para no estirarla.
static func proporcion(ruta: String) -> float:
	if _mallas.has("prop:" + ruta):
		return _mallas["prop:" + ruta]
	var tex: Texture2D = load(ruta)
	var p := 1.0
	if tex != null:
		var s := tex.get_size()
		if s.y > 0.0:
			p = s.x / s.y
	_mallas["prop:" + ruta] = p
	return p


## Malla de tarjeta cruzada: `PLANOS` planos de 1x1 girados alrededor del eje
## vertical, con el pivote en el CENTRO DE LA BASE (así basta con colocar la
## planta sobre el suelo y escalarla por su altura). Las normales apuntan hacia
## arriba a propósito (ver la cabecera).
static func malla() -> ArrayMesh:
	if _mallas.has("malla"):
		return _mallas["malla"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i: int in range(PLANOS):
		var ang := PI * float(i) / float(PLANOS)
		var dx := cos(ang) * 0.5
		var dz := sin(ang) * 0.5
		# Dos triángulos del plano, con la base en y=0 y la punta en y=1.
		_cara(st, Vector3(-dx, 0.0, -dz), Vector3(dx, 0.0, dz))
	st.generate_normals()
	st.generate_tangents()
	var cruzada := st.commit()
	_mallas["malla"] = cruzada
	return cruzada


static func _cara(st: SurfaceTool, a: Vector3, b: Vector3) -> void:
	var arriba := Vector3.UP
	var uv0 := Vector2(0.0, 1.0)
	var uv1 := Vector2(1.0, 1.0)
	var uv2 := Vector2(1.0, 0.0)
	var uv3 := Vector2(0.0, 0.0)
	# Normales hacia arriba: la luz no parte la copa en dos.
	var n := Vector3.UP
	st.set_normal(n)
	st.set_uv(uv0)
	st.add_vertex(a)
	st.set_normal(n)
	st.set_uv(uv1)
	st.add_vertex(b)
	st.set_normal(n)
	st.set_uv(uv2)
	st.add_vertex(b + arriba)
	st.set_normal(n)
	st.set_uv(uv0)
	st.add_vertex(a)
	st.set_normal(n)
	st.set_uv(uv2)
	st.add_vertex(b + arriba)
	st.set_normal(n)
	st.set_uv(uv3)
	st.add_vertex(a + arriba)


## Matriz de una planta: la coloca en [param pos] (que ya es la base), con la
## altura pedida, un giro al azar (los planos nunca quedan todos alineados) y el
## ancho tomado de la proporción del dibujo.
static func matriz(pos: Vector3, ruta: String, alto: float, giro: float) -> Transform3D:
	var ancho := alto * proporcion(ruta)
	var b := Basis(Vector3.UP, giro).scaled(Vector3(ancho, alto, ancho))
	return Transform3D(b, pos)


## Tono de una planta: variación de tono, saturación y luz sobre el verde base,
## para que no haya dos ejemplares del mismo color.
static func tinte(oscuro: Color, claro: Color, rng: RandomNumberGenerator) -> Color:
	var base := oscuro.lerp(claro, rng.randf())
	var h := fposmod(base.h + rng.randf_range(-0.020, 0.020), 1.0)
	var s := clampf(base.s + rng.randf_range(-0.06, 0.06), 0.0, 1.0)
	var v := clampf(base.v + rng.randf_range(-0.05, 0.10), 0.0, 1.0)
	return Color.from_hsv(h, s, v)