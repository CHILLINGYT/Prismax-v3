class_name Bosque
extends Node3D
## =============================================================================
##  BOSQUE DE LA ISLA
## =============================================================================
##  Siembra los árboles del sector norte/noroeste/oeste de la isla al cargar el
##  mapa, igual que el generador de ciudad siembra los suyos.
##
##  La vegetación es la MISMA que la de la ciudad: las tarjetas cruzadas de
##  `res://world/vegetacion.gd`, con los dibujos de árbol y arbusto que ya tiene el
##  proyecto. Así el bosque y los árboles de las calles se ven del mismo tipo y no
##  hay que importar ningún modelo nuevo.
##
##  ¿Por qué se siembra al cargar y no se guarda en una escena?  Porque el
##  búfer de una MultiMesh (las matrices de sus instancias) NO se guarda en los
##  archivos de escena de Godot: al reabrir la escena las instancias vuelven a
##  ser la identidad. Generarlo aquí cuesta ~100 ms y es el mismo camino que ya
##  usa la ciudad.
##
##  Detalles pensados para el rendimiento y el aspecto:
##    * Cada árbol se apoya en la altura real del terreno (Relieve.altura), con
##      un pequeño hundimiento para que nunca quede flotando ni enterrado.
##    * La densidad se modula con un ruido (claros y espesuras), con el sector
##      del bosque, con la distancia a la ciudad y con la altura sobre el mar:
##      el bosque se aclara hacia la costa y no invade calles ni playa.
##    * Se reparte en TROZOS de 200 m, cada uno con una MultiMeshInstance3D por
##      especie, para que el motor pueda descartar los trozos que no se ven (si
##      fuese una sola pieza, se dibujaría entera siempre).
## =============================================================================

# --- Región donde puede haber bosque (m): cubre la isla al norte/noroeste/oeste.
const X0 := -620.0
const X1 := 320.0
const Z0 := -620.0
const Z1 := 320.0

# --- Ajustes (editables desde el inspector) ---
## Semilla del reparto: cambiarla da otro bosque distinto.
@export var semilla: int = 424242
## Paso de la rejilla de candidatos (m). Cada candidato lleva un desplazamiento
## al azar, así que las plantas no quedan alineadas.
@export var paso: float = 5.5
## Lado de cada trozo (m).
@export var lado_trozo: float = 200.0
## Densidad media del bosque (1 = una planta por cada celda de la rejilla).
@export var densidad: float = 2.4
## Distancia (m) al borde de la ciudad donde empieza a aparecer vegetación y
## donde el bosque alcanza su densidad plena. La ciudad termina a 126 m: el
## bosque arranca 6 m más allá y se cierra en 49 m, así que desde la última calle
## ya se entra en el paisaje natural, sin franja vacía de por medio.
@export var borde_ciudad: float = 132.0
@export var borde_ciudad_lleno: float = 175.0
## Altura de los árboles (m). El abanico es amplio a propósito: en un mismo
## bosque conviven ejemplares jóvenes y árboles altos.
@export var alto_min: float = 4.0
@export var alto_max: float = 17.0
## Corrimiento hacia abajo (m) para que el tronco nunca quede al aire.
@export var hundir: float = 0.18
## Color base de las hojas: verde oscuro y verde claro del muestreo aleatorio.
@export var hoja_oscura: Color = Color(0.13, 0.30, 0.11)
@export var hoja_clara: Color = Color(0.34, 0.52, 0.20)

var _rel: Relieve
var _rng := RandomNumberGenerator.new()
var _ruido := FastNoiseLite.new()
var _ruido_agrupacion := FastNoiseLite.new()
var _ruido_claros := FastNoiseLite.new()
## Reparto por TROZO (Vector2i) y, dentro de cada trozo, por TEXTURA de especie:
## las matrices de las tarjetas cruzadas y el tono de cada ejemplar. Lo gestiona
## `Vegetacion` (misma vegetación que la de la ciudad).
var _pistas := {}
var _tintes := {}
var _arboles := 0
var _arbustos := 0


func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	_preparar()
	_esparcir()
	_volcar()
	print("[Bosque] %d árboles y %d arbustos en %d trozos (%d ms)" % [
			_arboles, _arbustos, _pistas.size(), Time.get_ticks_msec() - t0])


func _preparar() -> void:
	_rel = Relieve.new()
	_rng.seed = semilla
	_ruido.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_ruido.seed = 90001
	_ruido.frequency = 0.006
	_ruido.fractal_octaves = 2
	# Agrupaciones (rodales) de ~120 m: dan al bosque un reparto en manchas.
	_ruido_agrupacion.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_ruido_agrupacion.seed = 313131
	_ruido_agrupacion.frequency = 0.008
	_ruido_agrupacion.fractal_octaves = 2
	# Claros (~250 m): manchas amplias sin árboles donde el bosque respira.
	_ruido_claros.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_ruido_claros.seed = 717171
	_ruido_claros.frequency = 0.004
	_ruido_claros.fractal_octaves = 2


# --- Reparto de las plantas ---------------------------------------------------

func _esparcir() -> void:
	var columnas := int(round((X1 - X0) / paso))
	var filas := int(round((Z1 - Z0) / paso))
	for cx: int in range(columnas):
		for cz: int in range(filas):
			var x := X0 + (float(cx) + _rng.randf()) * paso
			var z := Z0 + (float(cz) + _rng.randf()) * paso
			var dc := maxf(absf(x), absf(z))          # distancia al borde de la ciudad
			if dc < borde_ciudad:
				continue                                  # entorno de la ciudad
			var w := _rel.peso_bosque(x, z)
			if w < 0.05:
				continue                                  # fuera del sector
			var h := _rel.altura(x, z)
			if h < -0.65:
				continue                                  # playa y mar
			if _rel.pendiente(x, z, 4.0) > 42.0:
				continue                                  # paredes de roca
			var p := _probabilidad(x, z, dc, h)
			if _rng.randf() > p:
				continue
			if _rng.randf() < 0.08:
				continue                                  # claro suelto
			var pos := Vector3(x, h - hundir, z)
			if _rng.randf() < 0.84:
				_poner_arbol(pos, _altura_arbol(x, z, h))
			else:
				_poner_arbusto(pos, _rng.randf_range(1.0, 2.6))


## Probabilidad de que crezca algo en un punto: combina el espesor del bosque
## (ruido), el sector, la distancia a la ciudad y la altura sobre el mar.
func _probabilidad(x: float, z: float, dc: float, h: float) -> float:
	var n := _ruido.get_noise_2d(x, z) * 0.5 + 0.5
	var espesor := clampf((n - 0.02) / 0.65, 0.0, 1.0)
	# Agrupaciones: dentro del bosque hay rodales más cerrados y más abiertos.
	var agrupacion := 0.55 + 0.85 * (_ruido_agrupacion.get_noise_2d(x, z) * 0.5 + 0.5)
	# Claros: manchas redondeadas sin árboles, para que el bosque respire y queden
	# zonas transitables de pasto.
	var claro := smoothstep(-0.35, -0.05, _ruido_claros.get_noise_2d(x, z))
	var cerca_ciudad := smoothstep(borde_ciudad, borde_ciudad_lleno, dc)
	var sobre_el_mar := smoothstep(-0.65, 0.45, h)
	# Línea de árboles: por encima de ~70 m las laderas altas son de roca y pasto.
	var altura := 1.0 - smoothstep(62.0, 88.0, h)
	return espesor * agrupacion * claro * _rel.peso_bosque(x, z) * cerca_ciudad * sobre_el_mar * altura * densidad


## Altura de un árbol (m): los rodales cerrados crían árboles más altos y los
## bordes más bajos, así que la silueta del bosque va en capas en lugar de ser un
## techo plano de alturas parecidas.
func _altura_arbol(x: float, z: float, h: float) -> float:
	var n := _ruido_agrupacion.get_noise_2d(x, z) * 0.5 + 0.5
	var t := clampf((n - 0.20 + _rng.randf() * 0.45) * 1.4, 0.0, 1.0)
	var alto := lerpf(alto_min, alto_max, t)
	# Cerca de la línea de árboles (cotas altas) los ejemplares son más pequeños.
	return alto * lerpf(0.72, 1.0, clampf((60.0 - h) / 25.0, 0.0, 1.0))


# --- Piezas: especies ---------------------------------------------------------
#
# El proyecto no tiene modelos de árbol importados (las escenas LODExample del
# complemento son primitivas de prueba), así que el bosque se construye con
# primitivas, igual que la vegetación de la ciudad. Lo que cambia respecto de la
# versión anterior es que ya NO hay una sola receta de árbol: hay cuatro ESPECIES
# con silueta, tronco, proporción de copa y color distintos, y además variación de
# tamaño, forma de la copa y tono en cada ejemplar. Eso es lo que evita el aspecto
# de "copias idénticas colocadas a intervalos regulares".

## Elige especie y coloca el ejemplar.
##
## Cada árbol es una TARJETA CRUZADA con el dibujo de una de las especies del
## proyecto (ver `Vegetacion`): la variedad del bosque sale del TAMAÑO, del GIRO,
## del TONO y de la especie elegida, no de piezas geométricas.
func _poner_arbol(pos: Vector3, alto: float) -> void:
	var ruta: String = Vegetacion.ARBOLES[_rng.randi_range(0, Vegetacion.ARBOLES.size() - 1)]
	_anadir_planta(ruta, Vegetacion.matriz(pos, ruta, alto, _rng.randf_range(0.0, TAU)), _color_hoja())
	_arboles += 1


## Arbusto: tarjeta cruzada con el dibujo del arbusto del proyecto.
func _poner_arbusto(pos: Vector3, alto: float) -> void:
	_anadir_planta(Vegetacion.ARBUSTO,
			Vegetacion.matriz(pos, Vegetacion.ARBUSTO, alto, _rng.randf_range(0.0, TAU)), _color_hoja())
	_arbustos += 1


## Color de hoja: verde con variación de tono, saturación y luz por ejemplar, para
## que el bosque no sea una masa de un solo verde.
func _color_hoja() -> Color:
	var base := hoja_oscura.lerp(hoja_clara, _rng.randf())
	var h := fposmod(base.h + _rng.randf_range(-0.022, 0.022), 1.0)
	var s := clampf(base.s + _rng.randf_range(-0.07, 0.07), 0.0, 1.0)
	var v := clampf(base.v + _rng.randf_range(-0.05, 0.10), 0.0, 1.0)
	return Color.from_hsv(h, s, v)


# --- Reparto en trozos --------------------------------------------------------

func _clave(x: float, z: float) -> Vector2i:
	return Vector2i(int(floor((x - X0) / lado_trozo)), int(floor((z - Z0) / lado_trozo)))


## Guarda una planta en el trozo que le toca y en el grupo de su textura.
func _anadir_planta(ruta: String, xf: Transform3D, color: Color) -> void:
	var k := _clave(xf.origin.x, xf.origin.z)
	if not _pistas.has(k):
		_pistas[k] = {}
		_tintes[k] = {}
	var grupo: Dictionary = _pistas[k]
	var grupo_tinte: Dictionary = _tintes[k]
	if not grupo.has(ruta):
		grupo[ruta] = []
		grupo_tinte[ruta] = []
	(grupo[ruta] as Array).append(xf)
	(grupo_tinte[ruta] as Array).append(color)


# --- Volcado a MultiMeshInstance3D --------------------------------------------

func _volcar() -> void:
	var claves: Array = _pistas.keys()
	claves.sort()
	for k: Vector2i in claves:
		var trozo := Node3D.new()
		trozo.name = "Trozo_%d_%d" % [k.x, k.y]
		trozo.position = Vector3(X0 + float(k.x) * lado_trozo, 0.0, Z0 + float(k.y) * lado_trozo)
		add_child(trozo)
		# Las matrices se guardan en coordenadas de mundo: se pasan a locales del
		# trozo para que la MultiMesh (y su caja envolvente) sean correctas.
		var desplazamiento := Transform3D(Basis(), trozo.position)
		var inv := desplazamiento.affine_inverse()
		var grupo: Dictionary = _pistas[k]
		var grupo_tinte: Dictionary = _tintes[k]
		# Una MultiMesh por ESPECIE: cada trozo lleva sólo las que le tocan.
		var rutas: Array = grupo.keys()
		rutas.sort()
		for ruta: String in rutas:
			_trozo_multi(trozo, Vegetacion.malla(), Vegetacion.material(ruta),
					_a_local(grupo[ruta] as Array, inv), grupo_tinte[ruta],
					ruta.get_file().get_basename())


func _a_local(pistas: Array, inv: Transform3D) -> Array:
	var salida: Array = []
	salida.resize(pistas.size())
	for i: int in range(pistas.size()):
		salida[i] = inv * (pistas[i] as Transform3D)
	return salida


func _trozo_multi(trozo: Node3D, malla: Mesh, material: Material,
		pistas: Array, colores: Array, nombre: String) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = malla
	if not colores.is_empty():
		mm.use_colors = true
	mm.instance_count = pistas.size()
	for i: int in range(pistas.size()):
		mm.set_instance_transform(i, pistas[i] as Transform3D)
		if not colores.is_empty():
			mm.set_instance_color(i, colores[i] as Color)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "%s_x%d" % [nombre, pistas.size()]
	mmi.multimesh = mm
	mmi.material_override = material
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	trozo.add_child(mmi)


## Las MALLAS y los MATERIALES de las plantas ya no se construyen aquí: los pone
## `res://world/vegetacion.gd` (tarjetas cruzadas con recorte de alfa), compartidos
## con la vegetación de la ciudad.