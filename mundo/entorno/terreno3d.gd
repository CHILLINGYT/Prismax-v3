class_name TerrenoIsla3D
extends Node3D
## =============================================================================
##  TERRENO DE LA ISLA CON TERRAIN 3D
## =============================================================================
##  Construye el terreno del mundo con el complemento **Terrain 3D 1.0.2**
##  (GDExtension) y le encarga TODO el sistema de terreno: relieve, superficie,
##  colisiones y reparto de texturas. No hay ninguna malla propia: la única
##  entrada es el mapa de altura `res://mundo/entorno/altura_isla.res`, generado con las
##  funciones de `Relieve` (bakeado a 2 m por vértice, 1024x1024).
##
##  Por qué se crea por código y no como nodo de la escena: el nodo Terrain3D lo
##  registra la GDExtension del complemento, así que se instancia en `_ready`
##  igual que hace la propia demo del addon (`demo/src/CodeGenerated.gd`). El
##  resultado es el mismo y la escena del juego no depende de tipos externos.
##
##  Piezas:
##    * datos: 16 regiones de 256 vértices con 2 m de separación -> cubren
##      2048x2048 m (la isla completa y 500 m de fondo marino alrededor),
##    * material: reparto de texturas por MAPA DE CONTROL horneado (suelo de
##      bosque en lo llano, roca en pendientes/zonas altas, arena en la costa) más
##      variación macro y doble escala para que no se note la repetición,
##    * colisiones: las del complemento, en la capa 1 (la del mundo, que es la que
##      sondean el personaje y el trazador del velocista),
##    * vegetación baja: la hierba se reparte con el instanciador del complemento.
## =============================================================================

## Mapa de altura horneado (Image FORMAT_RF con las alturas reales en metros).
const ALTURAS := "res://mundo/entorno/altura_isla.res"
## Mapa de control horneado. OJO: NO es un mapa de pesos por canal. El canal R
## guarda un entero empaquetado por bits (bit 0 = autoshader, bits 14-21 = mezcla,
## bits 22-26 = textura de overlay, bits 27-31 = textura base) y se genera con los
## codificadores de `Terrain3DUtil`. Aquí se pinta a mano (autoshader apagado):
##   * ROCA  (textura 0, "Cliff"/rock023) como textura BASE y
##   * SUELO (textura 1, "Grass"/ground037) como textura de overlay,
## con la mezcla calculada punto a punto: suelo de bosque salvo en laderas de
## verdad empinadas (transición 30..55°) o por encima de la línea de árboles
## (68..92 m). Así la roca sólo sale en las paredes y en las cumbres.
##   * ARENA (textura 2) en la playa y el fondo marino.
## Lo hornea `Relieve` igual que el mapa de altura, así que el reparto de
## materiales coincide exactamente con el relieve.
const CONTROL := "res://mundo/entorno/control_isla.res"
## Arena de la playa y del fondo marino. Debe medir lo mismo que las texturas del
## complemento (1024x1024) y estar importada igual (VRAM + mipmaps): Terrain3D
## mete todas las texturas del terreno en un mismo array y exige formatos
## idénticos.
const TEXTURA_ARENA := "res://assets/generated/arena_playa_hd.png"
## Texturas y mallas de vegetación del complemento (pasto, roca y tarjeta de hierba).
const ASSETS := "res://mundo/terreno/terrain3d_demo/data/assets.tres"
## Mata de pasto dibujada para las tarjetas de vegetación baja.
const TEXTURA_PASTO := "res://assets/generated/pasto_mata.png"
## Cobertura del mapa de altura: esquina noroeste y lado en metros.
const ORIGEN := Vector3(-1024.0, 0.0, -1024.0)
const LADO := 2048.0
## Resolución de las regiones del complemento.
const TAMANO_REGION := 512
const SEPARACION_VERTICES := 2.0

# --- Vegetación baja (hierba) ---
## Reparte hierba con el instanciador de Terrain3D.
@export var hierba: bool = true
## Paso de la rejilla de candidatos (m). Más pequeño = más matas.
@export var hierba_paso: float = 2.6
## Proporción de candidatos que se plantan (0-1).
@export var hierba_densidad: float = 0.55

var terreno: Terrain3D
var _rel: Relieve
var _camara_actual: Camera3D
var _rng := RandomNumberGenerator.new()
var _ruido := FastNoiseLite.new()


func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	_rel = Relieve.new()
	_rng.seed = 20240613
	_ruido.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_ruido.seed = 606060
	_ruido.frequency = 0.025

	_crear_terreno()
	_cargar_alturas()
	if not _comprobar_colocacion():
		push_error("[Terreno3D] El mapa de altura no coincide con Relieve")
	_crear_hierba()
	print("[Terreno3D] %d regiones de %d vértices cada una, %.1f m entre vértices, %.0f m de lado, colisión modo %d, en %d ms" % [
			terreno.data.get_region_count(), terreno.region_size, terreno.vertex_spacing,
			LADO, terreno.collision.mode, Time.get_ticks_msec() - t0])


# --- Construcción -------------------------------------------------------------

func _crear_terreno() -> void:
	terreno = Terrain3D.new()
	terreno.name = "Terrain3D"
	add_child(terreno)
	# `region_size` NO se toca: es un enum del complemento y su valor por defecto
	# (512 vértices por región) es justo el que necesita este mundo, como confirma
	# el informe de regiones del final del _ready (4 regiones para 1024x1024 px).
	terreno.vertex_spacing = SEPARACION_VERTICES
	# El terreno es el suelo del mundo: capa 1 (la que usan el personaje y el
	# trazador del velocista) y ninguna capa en la máscara, porque es estático.
	terreno.collision_layer = 1
	terreno.collision_mask = 0
	# Assets del propio complemento: texturas realistas de pasto y roca.
	var assets: Terrain3DAssets = load(ASSETS)
	if assets:
		_tarjeta_pasto(assets)
		_anadir_arena(assets)
		terreno.assets = assets
	else:
		push_error("[Terreno3D] No se pudo cargar %s" % ASSETS)
	_material()


## La tarjeta de vegetación del complemento es BLANCA (en la demo el color se lo
## pone su propio código), así que se sustituye por una con el color del pasto.
func _tarjeta_pasto(assets: Terrain3DAssets) -> void:
	var ma := Terrain3DMeshAsset.new()
	ma.name = "Pasto"
	ma.generated_type = Terrain3DMeshAsset.TYPE_TEXTURE_CARD
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.33, 0.49, 0.21)
	mat.albedo_texture = load(TEXTURA_PASTO)
	mat.roughness = 1.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.45
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mat.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	mat.distance_fade_min_distance = 110.0
	mat.distance_fade_max_distance = 85.0
	ma.material_override = mat
	ma.lod0_range = 110.0
	ma.last_lod = 0
	assets.set_mesh_asset(0, ma)


## Arena: se pinta con el mapa de control en la playa y en el fondo marino, para
## que el agua no se vea sobre una superficie de pasto. La tierra se deja sin
## pintar, así que allí el auto-shader sigue repartiendo pasto y roca.
func _anadir_arena(assets: Terrain3DAssets) -> void:
	# La textura debe venir del sistema de importación del proyecto (el
	# complemento construye con ellas un array de texturas de la GPU). El archivo
	# .import de la arena ya está ajustado para coincidir con las del complemento
	# (1024x1024, VRAM comprimida y con mipmaps): si Godot todavía no la ha
	# reimportado con esos ajustes, aparece un aviso de tamaños/formato que
	# desaparece solo en cuanto el editor la reimporta.
	var ta := Terrain3DTextureAsset.new()
	ta.name = "Arena"
	ta.albedo_texture = load(TEXTURA_ARENA)
	# La normal del terreno del complemento le da a la arena un grano fino en
	# lugar de una superficie lisa.
	ta.normal_texture = load("res://mundo/terreno/terrain3d_demo/assets/textures/ground037_nrm_rgh.png")
	# Propiedades alineadas con las texturas de la demo (rock023, ground037) para que
	# el array de texturas del complemento sea homogéneo.
	ta.normal_depth = 1.0
	ta.ao_strength = 2.0
	ta.uv_scale = 0.18
	ta.detiling_rotation = 0.0
	assets.set_texture(2, ta)


## Material: auto-shader del complemento.
##
## CÓMO SE REPARTEN LAS TEXTURAS EN TERRAIN 3D (la clave de todo el problema):
## el mapa de control NO es un mapa de pesos por canal RGBA, sino que su canal R
## guarda un valor empaquetado por BITS (bits 0 = autoshader, 14-21 = mezcla,
## 22-26 = textura de overlay, 27-31 = textura base). Un mapa con R=0 en tierra
## deja el autoshader APAGADO y usa como textura base la 0, que en
## `demo/data/assets.tres` es **"Cliff" (rock023 = ROCA)**: por eso el bosque
## entero salía de piedra. El reparto correcto se hornea con `Terrain3DUtil`.
##
## Con el autoshader encendido (bit 0), el complemento mezcla solo:
##   * auto_overlay_texture en el terreno LLANO  -> 1 = ground037 (suelo de bosque)
##   * auto_base_texture al EMPINARSE y en cotas altas -> 0 = rock023 (roca)
## `auto_slope` marca cuánto tiene que inclinarse el terreno para que aparezca la
## roca y `auto_height_reduction` cuánto pesa la altura. El resto de parámetros
## copian los de la demo del complemento (variación macro y doble escala contra la
## repetición de la textura).
func _material() -> void:
	var m: Terrain3DMaterial = terreno.material
	m.world_background = Terrain3DMaterial.NONE
	m.auto_shader = false
	m.dual_scaling = true
	m.set_shader_param("auto_base_texture", 0)      # rock023: ROCA (cimas y paredes)
	m.set_shader_param("auto_overlay_texture", 1)   # ground037: SUELO DE BOSQUE (llano)
	m.set_shader_param("auto_slope", 0.8)
	m.set_shader_param("auto_height_reduction", 0.55)
	m.set_shader_param("blend_sharpness", 0.3)
	m.set_shader_param("enable_macro_variation", true)
	m.set_shader_param("macro_variation1", Color(0.855, 0.8625, 0.9, 1.0))
	m.set_shader_param("macro_variation2", Color(0.9, 0.885, 0.81, 1.0))
	m.set_shader_param("macro_variation_slope", 0.333)
	m.set_shader_param("dual_scale_near", 100.0)
	m.set_shader_param("dual_scale_far", 170.0)
	m.set_shader_param("dual_scale_reduction", 0.3)
	m.set_shader_param("dual_scale_texture", 0)
	m.set_shader_param("mipmap_bias", 1.0)
	m.set_shader_param("enable_projection", true)
	m.set_shader_param("projection_threshold", 0.87)
	m.set_shader_param("bias_distance", 512.0)
	m.set_shader_param("world_noise_height", 34.0)
	m.set_shader_param("world_noise_scale", 9.85)
	m.set_shader_param("world_noise_max_octaves", 4)
	m.set_shader_param("world_noise_min_octaves", 2)
	m.set_shader_param("world_noise_region_blend", 0.33)
	m.set_shader_param("world_noise_offset", Vector3(2.17, -1.225, 1.9))
	m.set_shader_param("noise1_scale", 0.04)
	m.set_shader_param("noise2_scale", 0.076)
	m.set_shader_param("noise1_angle", 0.1)
	m.set_shader_param("noise1_offset", Vector2(0.5, 0.5))
	m.set_shader_param("tri_scale_reduction", 0.3)
	m.set_shader_param("depth_blur", 0.0)
	m.set_shader_param("flat_terrain_normals", false)


## Importa el mapa de altura y el de control horneados: coloca todas las regiones
## de una vez y asigna a cada vértice su mezcla de texturas.
func _cargar_alturas() -> void:
	var img: Image = load(ALTURAS)
	if img == null:
		push_error("[Terreno3D] Falta el mapa de altura %s" % ALTURAS)
		return
	var control: Image = load(CONTROL)
	terreno.data.import_images([img, control, null], ORIGEN, 0.0, 1.0)


## Comprueba que Terrain3D colocó el mapa donde corresponde comparando alturas
## del complemento con las de [Relieve] (si el mapa estuviera girado o desplazado
## los árboles y las colisiones no coincidirían con el dibujo).
func _comprobar_colocacion() -> bool:
	var muestras: Array[Vector3] = [
		Vector3(0.0, 0.0, 0.0), Vector3(-90.0, 0.0, -90.0), Vector3(-336.0, 0.0, -336.0),
		Vector3(-400.0, 0.0, -400.0), Vector3(200.0, 0.0, 200.0), Vector3(-600.0, 0.0, -100.0),
	]
	var peor := 0.0
	for p: Vector3 in muestras:
		var h3d := terreno.data.get_height(p)
		var hr := _rel.altura(p.x, p.z)
		peor = maxf(peor, absf(h3d - hr))
	if peor > 0.5:
		print("[Terreno3D] Desviación con el mapa de altura: %.3f m" % peor)
		return false
	return true


## Hierba: matas repartidas con el instanciador del complemento. Se planta sólo
## donde el suelo es transitable (tierra firme, sin ciudades y sin paredes) y con
## densidad variable (manchas y calvas) para que no parezca una alfombra uniforme.
func _crear_hierba() -> void:
	if not hierba:
		return
	var xformas: Array[Transform3D] = []
	var x := -560.0
	while x <= 320.0:
		var z := -560.0
		while z <= 320.0:
			z += hierba_paso
			var jx := x + _rng.randf_range(-hierba_paso, hierba_paso) * 0.5
			var jz := z + _rng.randf_range(-hierba_paso, hierba_paso) * 0.5
			# Ni en la ciudad (meseta plana, SEMI_MESETA) ni en el agua ni en las
			# paredes de roca.
			if maxf(absf(jx), absf(jz)) < Relieve.SEMI_MESETA + 2.0:
				continue
			var h := _rel.altura(jx, jz)
			# La cota de arena de `Relieve` (no un valor a mano): así la hierba
			# nunca se planta sobre la arena si esa cota cambia.
			if h < Relieve.COTA_ARENA or h > 78.0:
				continue
			# Las comprobaciones caras (la pendiente son cuatro muestras de altura)
			# van al final: así sólo se pagan en los candidatos que van a plantarse.
			var manchas := _ruido.get_noise_2d(jx, jz) * 0.5 + 0.5
			if _rng.randf() > hierba_densidad * clampf(manchas * 1.6, 0.0, 1.0):
				continue
			if _rel.pendiente(jx, jz, 3.0) > 38.0:
				continue
			var alto := _rng.randf_range(0.45, 1.05)
			var giro := Basis(Vector3.UP, _rng.randf_range(0.0, TAU))
			xformas.append(Transform3D(giro.scaled(Vector3(alto, alto, alto)),
					Vector3(jx, h, jz)))
		x += hierba_paso
	if xformas.is_empty():
		return
	terreno.instancer.add_transforms(0, xformas)
	print("[Terreno3D] %d matas de hierba" % xformas.size())


## El complemento calcula el nivel de detalle, el reparto de texturas y la
## colisión dinámica alrededor de la cámara activa. Aquí se le va reasignando
## cuando cambia (el juego usa la del jugador; las herramientas de revisión usan
## una libre): si se quedara apuntando a una cámara que ya no se usa, la colisión
## se construiría alrededor de un punto muerto y el personaje caería al vacío.
func _process(_delta: float) -> void:
	if terreno == null:
		return
	var cam := get_viewport().get_camera_3d()
	if cam != null and cam != _camara_actual:
		_camara_actual = cam
		terreno.set_camera(cam)
