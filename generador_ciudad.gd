@tool
class_name GeneradorCiudad3D
extends Node3D
## =============================================================================
##  GENERADOR PROCEDURAL DE CIUDAD 3D
##  Usa exclusivamente los modelos .gltf/.glb de la carpeta indicada (por
##  defecto el kit "Downtown" exportado a res://Exports/glTF (Godot)/).
## -----------------------------------------------------------------------------
##  Qué hace:
##   1. ESCANEA la carpeta y clasifica cada modelo por nombre y por su firma
##      geométrica medida (edificios, calles, aceras, vegetación, props,
##      marcas viales y módulos de fachada).
##   2. TRAZA la ciudad en cuadrícula: manzanas edificables separadas por
##      calles de 12 m (calzada de 6 m + 2 aceras de 3 m). El reparto es
##      disjunto: cada región del plano se cubre una sola vez, así que no hay
##      solapamientos entre piezas.
##   3. DA VARIACIÓN: los edificios giran en pasos de 90°, tienen altura variable,
##      posibilidad de torre (prob_torre) y **una sola familia de fachada** cada
##      uno (ladrillo / metal / molduras). Las piezas de una familia se agrupan
##      por nombre en _construir_familias(), así que un edificio nunca mezcla
##      texturas: elige familia (muros, planta baja, ventanas, remate, esquinas y
##      cornisa) y la usa entera. Las ventanas se alinean en la misma vertical
##      (patrón fijo por edificio), no sorteadas celda a celda.
##   4. CIERRA LAS MANZANAS Y LOS EDIFICIOS: cada edificio ocupa su parcela
##      completa, así que los vecinos se tocan y no quedan callejones. Los muros
##      se colocan CENTRADOS en su celda (el módulo va de x = -1 a +1), así cada
##      cara cubre de esquina a esquina: sin rendijas al empezar (que dejaban ver
##      el interior, los "parches negros" de las esquinas) ni paños colgando al
##      terminar. Cada tramo va adelantado unos milímetros para que el canto del
##      muro no quede coplanar con la fachada perpendicular (evita el parpadeo
##      blanco/negro en las esquinas). El portal va centrado en su celda, con
##      marco de la MISMA familia que el edificio (madera con ladrillo, moldura
##      con moldura, metal con metal) y DOS hojas de 1 m que cierran el vano de
##      2 m, con el fondo medido contra la caja real del marco: nunca se cruzan
##      con la textura de la fachada ni dejan media puerta abierta.
##      Los edificios llevan colisión envolvente: no se puede entrar.
##   5. VEGETACIÓN Y PARQUES: algunas manzanas (céntricas) se convierten en
##      parque: césped texturizado, senderos en cruz, árboles 3D, arbustos,
##      jardineras del kit y bolardos. Además hay árboles de alineación en las
##      aceras y vegetación en los solares vacíos. Los árboles y arbustos son
##      geometría 3D real (tronco + masas de hoja) apoyada en el suelo.
##   6. ORGANIZA la escena en contenedores: Suelo, Calles, Aceras, Edificios
##      (Prefabricados / Modulares), Vegetacion, Props y MarcasViales. Las
##      piezas muy repetidas (pavimentos, muros, azoteas, árboles...) se agrupan
##      en MultiMeshInstance3D para que la ciudad sea barata de dibujar.
##   7. COLISIONES: comprueba si cada modelo ya trae cuerpo físico y, si no,
##      añade StaticBody3D + CollisionShape3D a suelo, aceras, manzanas y
##      edificios (y opcionalmente a los props).
##
##  TAMAÑO: por defecto 6x6 manzanas de 24 m con AVENIDAS de 12 m (cuatro
##  carriles) = 252 x 252 m (unas 16 hectáreas) con 3 parques, pensado para
##  recorrerse a pie. Para más ciudad, sube manzanas_x / manzanas_z (hasta 10)
##  en el Inspector: 8x8 son unos 20.000 nodos y ~2 s de generación.
##
##  ACABADO: la calzada se tesela con planchas planas de asfalto y se pinta con
##  raya doble amarilla en el eje, discontinuas por carril y pasos de peatones
##  anchos en los cruces. Cada azotea es una losa propia con membrana de grava
##  (res://assets/generated/techo_grava.png) repetida cada 4 m; no se usan las
##  planchas de tejado del kit, que dejaban parches beige y gris a la misma cota. Los canteros con reja del kit no se colocan: el
##  suelo de plazas y parques queda liso y continuo, y la vegetación la ponen
##  los árboles y arbustos 3D. Los edificios completos del kit (Building_*) van
##  apagados porque traen la puerta abierta de fábrica.
##
##  Cómo usarlo:
##   · Adjunta este script a un Node3D raíz.
##   · En el EDITOR: botones "Generar ciudad" / "Limpiar ciudad" en el Inspector
##     (quedan en la escena y se guardan al salvar el .tscn).
##   · En RUNTIME: con "generar_al_iniciar" activo la ciudad se crea al pulsar
##     Play; también puedes llamar a generar_ciudad() desde tu propio código.
##   · CÁMARA LIBRE (si "camara_libre" está activo): ratón para mirar,
##     W/A/S/D para volar, E/Q para subir/bajar, Shift para ir rápido,
##     R para volver a la vista inicial y Esc para liberar el ratón.
##
##  Convenciones métricas del kit (medidas sobre los .gltf reales):
##   · y =  0.00  -> superficie peatonal: acera, plaza y base de los edificios.
##   · y = -0.15  -> superficie de la calzada (las planchas de asfalto son
##                   planos justo a esa altura).
##   · Piezas de fachada: 2.00 m de ancho x 3.00 m de alto, con la cara
##     exterior en z = 0 y el volumen hacia -z (por eso "giran" con múltiplos
##     de 90° para formar el perímetro del edificio).
## =============================================================================

# --- Medidas del kit (metros) -------------------------------------------------
const MODULO_ANCHO := 2.0      ## ancho de un módulo de fachada
const PLANTA_ALTO := 3.0       ## altura de una planta / de un módulo de muro
const Y_ACERA := 0.0           ## cota de aceras, plazas y base de edificios
const Y_CALZADA := -0.15       ## cota de la calzada
const Y_LOSA := -0.002         ## cara superior de las plataformas de manzana
const Y_SUELO := -0.16         ## cara inferior de las losas / del terreno
const Y_TERRENO := -0.155      ## cara superior del terreno (5 mm bajo la calzada)
const COLOR_SUELO := Color(0.20, 0.20, 0.21)
const COLOR_LOSA := Color(0.56, 0.55, 0.52)
const NODO_CIUDAD := "CiudadGenerada"

# --- Vegetación propia (césped, árboles y arbustos generados) ------------------
const Y_PARQUE := -0.15         ## cota del césped de los parques (nivel de calzada)
const RUTA_CESPED := "res://assets/generated/parque_cesped.png"
## Membrana de grava de las azoteas (textura generada, teselable).
const RUTA_TECHO := "res://assets/generated/techo_grava.png"

# --- Configuración expuesta en el Inspector -----------------------------------
@export_group("1. Recursos")
## Carpeta con los modelos .gltf/.glb. Si no existe se busca automáticamente.
@export_dir var carpeta_modelos: String = "res://Exports/glTF (Godot)/"
## Semilla del azar. 0 = distinta en cada generación.
@export var semilla: int = 0

@export_group("2. Trazado")
@export_range(1, 10) var manzanas_x: int = 6     ## manzanas en el eje X
@export_range(1, 10) var manzanas_z: int = 6     ## manzanas en el eje Z
## Lado de la manzana edificable (se ajusta a múltiplo de 6 m).
@export_range(12.0, 60.0, 6.0) var tamano_manzana: float = 24.0
## Ancho de la calzada (múltiplo de 6 m: plancha de asfalto). Con 12 m sale una
## avenida de cuatro carriles: raya doble amarilla en el eje y discontinuas.
@export_range(6.0, 18.0, 6.0) var ancho_calzada: float = 12.0
## Ancho de cada acera (múltiplo de 3 m: loseta de acera).
@export_range(3.0, 9.0, 3.0) var ancho_acera: float = 3.0

@export_group("3. Edificios")
## Coloca los edificios completos del kit (Building_*). Van apagados por
## defecto: esos modelos traen la puerta de entrada abierta de fábrica y su
## volumen no encaja con la retícula de 2 m, así que los solares se resuelven
## con el edificio modular (fachada coherente y portal cerrado de verdad).
@export var usar_prefabricados: bool = false
## Compone edificios con módulos del kit (muros, ventanas, cornisas, azotea).
@export var usar_modulares: bool = true
@export_range(2, 8) var pisos_min: int = 2
@export_range(2, 10) var pisos_max: int = 7
## Probabilidad de que una parcela salga mucho más alta (torre del skyline).
@export_range(0.0, 0.6) var prob_torre: float = 0.18
## Variación aleatoria máxima de escala (uniforme) de los edificios.
@export_range(0.0, 0.4) var variacion_escala: float = 0.10
## Probabilidad de que un solar quede libre (plaza con vegetación).
@export_range(0.0, 0.6) var prob_solar_vacio: float = 0.12

@export_group("4. Detalle")
## Pavimenta el interior de las manzanas con losas de acera sin bordillo.
@export var pavimentar_manzanas: bool = true
@export var generar_props: bool = true
@export var generar_vegetacion: bool = true
@export var generar_marcas_viales: bool = true
## Aparatos de aire acondicionado sobre las azoteas modulares.
@export var props_en_azotea: bool = true

@export_group("5. Rendimiento")
## Agrupa las piezas repetidas en MultiMeshInstance3D (recomendado).
@export var usar_multimesh: bool = true

@export_group("6. Parques y vegetación")
## Manzanas que se convierten en parque (césped, senderos en cruz y árboles).
@export var manzanas_parque: int = 3
## Árboles por parque, además de arbustos y jardineras del kit.
@export var arboles_por_parque: int = 18
## Separación media entre árboles de calle, en metros (0 = sin árboles de calle).
@export var arboles_calle: float = 14.0
## Usa la vegetación propia: césped generado y árboles/arbustos en 3D.
@export var usar_vegetacion_propia: bool = true

@export_group("7. Colisiones")
@export var colisiones_suelo: bool = true
@export var colisiones_edificios: bool = true
@export var colisiones_props: bool = false

@export_group("8. Ejecución")
## Genera la ciudad automáticamente al arrancar el juego (no en el editor).
@export var generar_al_iniciar: bool = true
## Genera la ciudad al ABRIR la escena en el editor, para poder verla en el visor
## 3D sin pulsar Play (tarda unos segundos, avisa a la barra de estado). Es una
## vista de trabajo: esos nodos no se guardan al salvar la escena (para guardarla
## de verdad, usa "Generar ciudad" y salva tú la escena).
@export var generar_en_editor: bool = true
## Crea cámara, luz solar y entorno (cielo) si la escena no los tiene, para
## poder ver la ciudad al pulsar Play. Nodos: CamaraCiudad, Sol, Entorno.
@export var crear_camara_y_luz: bool = true
## Convierte la cámara en cámara libre de vuelo (ratón + WASD + E/Q, Esc libera).
@export var camara_libre: bool = true
@warning_ignore("unused_private_class_variable")
@export_tool_button("Generar ciudad", "Reload") var _btn_generar: Callable = generar_ciudad
@warning_ignore("unused_private_class_variable")
@export_tool_button("Limpiar ciudad", "Remove") var _btn_limpiar: Callable = limpiar_ciudad

# --- Estado interno -----------------------------------------------------------
var _rng := RandomNumberGenerator.new()
var _vista_editor := false   ## true mientras se genera sólo para el visor 3D
var _carpeta := ""
var _modelos := {}          ## nombre -> {escena: PackedScene, caja: AABB, categoria: String}
var _categorias := {}       ## categoria -> PackedStringArray con los nombres encontrados
var _lotes := {}            ## nombre -> Array[Transform3D] pendientes de MultiMesh
var _lote_padre := {}       ## nombre -> Node3D que alojará su MultiMeshInstance3D
var _mm_cache := {}         ## nombre -> bool (¿se puede agrupar en MultiMesh?)
var _cont := {}             ## nombre -> Node3D contenedor
var _trazado := {}          ## parámetros calculados de la trama urbana
var _est := {}              ## contadores para el informe

# Listas funcionales construidas al clasificar los modelos
var _prefabs: Array[String] = []
var _paredes: Array[String] = []
var _paredes_bajas: Array[String] = []
var _paredes_top: Array[String] = []
var _ventanas: Array[String] = []
var _esquinas_muro: Array[String] = []
var _marcos_puerta: Array[String] = []
var _hojas_puerta: Array[String] = []
var _cornisas: Array[String] = []
var _techos := {}                       ## lado (int) -> Array[String]
## Familias de fachada coherentes: familia -> {muros, bajas, ventanas, top,
## esquinas, cornisas}. Cada edificio usa UNA sola familia, así sus texturas
## nunca se mezclan (ladrillo con metal con molduras en el mismo muro).
var _familias: Dictionary = {}
var _mat_relleno: StandardMaterial3D = null
var _tramo_calle: Array[String] = []
var _plancha_asfalto: Array[String] = []
var _acera_recta: Array[String] = []
var _acera_pavimento: Array[String] = []
var _esquinas_acera: Array[String] = []
var _esquina_dir := {}                  ## nombre -> Vector2i (esquina redondeada del modelo)
var _con_decal := {}                    ## nombre -> bool (trae capa de pintura "MI_StreetDecals")
var _mallas_limpias := {}               ## malla original -> copia sin capas de pintura
var _linea_discontinua: Array[String] = []
var _linea_central: Array[String] = []      ## raya doble amarilla del eje
var _pasos_peatones: Array[String] = []
var _pasos_anchos: Array[String] = []       ## pasos que cubren la calzada entera
var _pintura_esquinas: Array[String] = []
var _tex_cesped: Texture2D = null          ## césped de los parques (si existe)
var _tex_techo: Texture2D = null           ## membrana de grava de las azoteas
var _mat_techo := {}                       ## lado de la plancha -> material de membrana
var _pistas_tronco: Array[Transform3D] = []      ## matrices de troncos (3D)
var _pistas_esfera: Array[Transform3D] = []      ## matrices de masas redondas
var _colores_esfera: Array[Color] = []           ## color por masa redonda
var _pistas_cono: Array[Transform3D] = []        ## matrices de masas cónicas
var _colores_cono: Array[Color] = []             ## color por masa cónica
var _mat_tronco: StandardMaterial3D = null       ## material de los troncos
var _mat_hoja: StandardMaterial3D = null         ## material del follaje
var _alcantarillas: Array[String] = []
var _sumideros: Array[String] = []
var _bolardos: Array[String] = []
var _aires: Array[String] = []
var _vegetacion: Array[String] = []
## Para pruebas visuales (escena prueba_puerta.tscn): centro y normal hacia la
## calle de cada portal, y esquina noreste exterior de cada edificio modular.
var prueba_portales: Array[Vector3] = []
var prueba_portales_dir: Array[Vector3] = []
var prueba_esquinas: Array[Vector3] = []
var prueba_esquinas_dir: Array[Vector3] = []


func _ready() -> void:
	if Engine.is_editor_hint():
		# Vista de trabajo en el editor: se genera la ciudad para poder verla en
		# el visor 3D sin pulsar Play. Sin "owner" (no se guarda al salvar) y con
		# la vista del editor enfocada en ella. Si ya hay ciudad (por ejemplo,
		# generada con el botón del Inspector), se respeta la que haya.
		if generar_en_editor and is_inside_tree() and get_node_or_null(NODO_CIUDAD) == null:
			_vista_editor = true
			generar_ciudad()
			_vista_editor = false
		return
	# Si una ejecución anterior guardó la cámara temporalmente en la escena,
	# devolverla al encuadre aéreo predeterminado de la ciudad.
	var cam_inicial := get_node_or_null("CamaraCiudad") as Camera3D
	if cam_inicial != null:
		cam_inicial.position = Vector3(168.0, 124.0, 168.0)
		cam_inicial.rotation_degrees = Vector3(-27.5, 45.0, 0.0)
	if generar_al_iniciar:
		generar_ciudad()


# =============================================================================
#  API pública
# =============================================================================

## Borra la ciudad anterior (si existe) y genera una nueva con la semilla actual.
func generar_ciudad() -> void:
	var t0 := Time.get_ticks_msec()
	limpiar_ciudad()

	_rng = RandomNumberGenerator.new()
	_rng.seed = semilla if semilla != 0 else randi()
	prueba_portales.clear()
	prueba_portales_dir.clear()
	prueba_esquinas.clear()
	prueba_esquinas_dir.clear()

	# 1) Localizar e inspeccionar los modelos -------------------------------
	_carpeta = _resolver_carpeta()
	if _carpeta == "":
		push_error("[GeneradorCiudad] No se encontró ninguna carpeta con modelos .gltf/.glb.")
		return
	_escanear(_carpeta)
	if _modelos.is_empty():
		push_error("[GeneradorCiudad] La carpeta %s no contiene modelos utilizables." % _carpeta)
		return
	_construir_listas()
	_cargar_vegetacion_extra()

	# 2) Trazado y contenedores --------------------------------------------
	_preparar_trazado()
	_crear_contenedores()
	_est = {"prefabs": 0, "modulares": 0, "props": 0, "vegetacion": 0, "arboles": 0,
			"parques": 0, "marcas": 0, "suelos": 0, "tramos": 0, "portales": 0}

	# 3) Construcción de la ciudad -----------------------------------------
	_configurar_escena()
	_generar_suelo()
	_generar_calles()
	_generar_manzanas()
	_generar_mobiliario()
	_volcar_vegetacion()
	_volcar_lotes()

	# 4) Cierre -------------------------------------------------------------
	if Engine.is_editor_hint():
		_marcar_owner(get_node_or_null(NODO_CIUDAD))
		# En el editor, deja la vista 3D mirando la ciudad recién generada.
		_enfocar_vista_editor()
	var ms := Time.get_ticks_msec() - t0
	_informe(ms)


## Elimina los nodos de la ciudad generada y limpia las cachés.
func limpiar_ciudad() -> void:
	var anterior := get_node_or_null(NODO_CIUDAD)
	if anterior != null:
		anterior.free()          # liberación inmediata: permite regenerar en el acto
	_lotes.clear()
	_lote_padre.clear()
	_mm_cache.clear()
	_cont.clear()
	_con_decal.clear()
	_mallas_limpias.clear()
	_pistas_tronco.clear()
	_pistas_esfera.clear()
	_colores_esfera.clear()
	_pistas_cono.clear()
	_colores_cono.clear()


# =============================================================================
#  Paso 1: lectura y clasificación de recursos
# =============================================================================

func _resolver_carpeta() -> String:
	# Se prueban la ruta configurada y las variantes habituales; si ninguna
	# existe, se busca cualquier carpeta con "gltf" en el nombre del proyecto.
	var candidatos: Array[String] = [
		carpeta_modelos,
		"res://Exports/glTF (Godot)/",
		"res://glTF (Godot)/",
		"res://models/glTF (Godot)/",
	]
	for c in candidatos:
		if c != "" and DirAccess.dir_exists_absolute(c):
			return c
	var encontradas: Array[String] = []
	_buscar_carpetas_gltf("res://", 2, encontradas)
	return encontradas[0] if not encontradas.is_empty() else ""


func _buscar_carpetas_gltf(ruta: String, profundidad: int, salida: Array[String]) -> void:
	if profundidad < 0:
		return
	var d := DirAccess.open(ruta)
	if d == null:
		return
	for sub in d.get_directories():
		if sub.begins_with(".") or sub == "addons":
			continue
		var completa := ruta.path_join(sub)
		if sub.to_lower().contains("gltf"):
			salida.append(completa)
		else:
			_buscar_carpetas_gltf(completa, profundidad - 1, salida)


## Carga el césped propio de los parques (si existe). Los árboles y arbustos son
## geometría 3D que compone el propio script, así que no necesitan texturas.
func _cargar_vegetacion_extra() -> void:
	_tex_cesped = null
	if usar_vegetacion_propia:
		_tex_cesped = _cargar_textura(RUTA_CESPED)
	# Membrana de las azoteas: se carga siempre, porque la textura de tejado del
	# kit trae manchas oscuras y un patrón muy ruidoso (parches negros pixelados).
	_tex_techo = _cargar_textura(RUTA_TECHO)


## Carga una textura del disco: primero como recurso importado y, si aún no lo
## está, leyendo el PNG directamente.
func _cargar_textura(ruta: String) -> Texture2D:
	if ResourceLoader.exists(ruta):
		var recurso := ResourceLoader.load(ruta)
		if recurso is Texture2D:
			return recurso as Texture2D
	var imagen := Image.new()
	if imagen.load(ruta) == OK:
		imagen.generate_mipmaps()
		return ImageTexture.create_from_image(imagen)
	return null


## ¿La pieza es una plancha de azotea del kit (Roof_2x2 / Roof_4x4)?
func _es_plancha_techo(pieza: String) -> bool:
	for lado in _techos.keys():
		if (_techos[lado] as Array).has(pieza):
			return true
	return false


## Material de membrana para las planchas de azotea, con una losa de textura
## cada 4 m. Sustituye la textura original del kit, que trae manchas oscuras.
func _material_techo(pieza: String) -> Material:
	if _tex_techo == null:
		return null
	var datos: Dictionary = _modelos.get(pieza, {})
	var caja: AABB = datos.get("caja", AABB())
	var lado := maxf(1.0, caja.size.x)
	if _mat_techo.has(lado):
		return _mat_techo[lado] as Material
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _tex_techo
	var rep := maxf(1.0, lado / 4.0)
	mat.uv1_scale = Vector3(rep, rep, 1.0)
	mat.roughness = 1.0
	mat.metallic = 0.0
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_mat_techo[lado] = mat
	return mat


## Material de la losa de azotea: la membrana se repite cada 4 m tanto a lo
## ancho como a lo largo, así el grano de la grava se ve igual de fino en
## edificios grandes y pequeños.
func _material_azotea(ancho: float, fondo: float) -> Material:
	if _tex_techo == null:
		return null
	var clave := Vector2(ancho, fondo)
	if _mat_techo.has(clave):
		return _mat_techo[clave] as Material
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _tex_techo
	mat.albedo_color = Color(0.78, 0.78, 0.80)   # grava un poco más apagada
	mat.uv1_scale = Vector3(maxf(1.0, ancho / 4.0), maxf(1.0, fondo / 4.0), 1.0)
	mat.roughness = 1.0
	mat.metallic = 0.0
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_mat_techo[clave] = mat
	return mat


## Recorre la carpeta, carga cada .gltf/.glb, mide su caja envolvente y lo clasifica.
func _escanear(carpeta: String) -> void:
	_modelos.clear()
	_categorias.clear()
	_con_decal.clear()
	_mallas_limpias.clear()
	var d := DirAccess.open(carpeta)
	if d == null:
		return
	var nombres: Array[String] = []
	for f in d.get_files():
		if f.get_extension().to_lower() in ["gltf", "glb"]:
			nombres.append(f)
	nombres.sort()

	for archivo in nombres:
		var ruta := carpeta.path_join(archivo)
		var recurso := ResourceLoader.load(ruta)
		if not (recurso is PackedScene):
			push_warning("[GeneradorCiudad] No se pudo cargar %s" % ruta)
			continue
		var escena := recurso as PackedScene
		var plantilla := escena.instantiate() as Node3D
		if plantilla == null:
			continue
		var caja := _aabb_vertices(plantilla)
		var decal := _tiene_capa_decal(plantilla)
		plantilla.free()
		var nombre := archivo.get_basename()
		var categoria := _clasificar(nombre)
		_modelos[nombre] = {"escena": escena, "caja": caja, "categoria": categoria}
		_con_decal[nombre] = decal
		if not _categorias.has(categoria):
			_categorias[categoria] = []
		(_categorias[categoria] as Array).append(nombre)


## Clasificación por nombre/función (las categorías que pidió el proyecto).
## Se compara por "palabras" del nombre (tokens), no por subcadenas, para que
## "Street" no cuente como "tree".
func _clasificar(nombre: String) -> String:
	var n := nombre.to_lower()
	var tokens := n.replace("-", "_").split("_")
	# La vegetación se comprueba antes que "sidewalk"/"prop": Prop_Planter_Single
	# y Sidewalk_Planter son mobiliario verde.
	var palabras_vegetacion := ["tree", "trees", "plant", "plants", "planter", "planters", "bush",
			"bushes", "grass", "vegetation", "veget", "arbol", "árbol", "planta", "plantas",
			"maceta", "macetas", "jardinera", "flower", "flowers", "flowerpot", "pot"]
	for t in tokens:
		if t in palabras_vegetacion:
			return "vegetacion"
	if n.begins_with("building") or n.begins_with("edificio"):
		return "edificios"
	if n.begins_with("street") or n.begins_with("road") or n.begins_with("calle") or n.begins_with("asphalt"):
		return "calles"
	if n.begins_with("sidewalk") or n.begins_with("acera") or n.begins_with("curb"):
		return "aceras"
	if n.begins_with("decal") or n.contains("marking") or n.contains("crosswalk"):
		return "marcas_viales"
	if n.begins_with("prop") or n.contains("bollard") or n.contains("lamp") or n.contains("bench") \
			or n.contains("farola") or n.contains("banco") or n.contains("bin"):
		return "props"
	if n.begins_with("brick") or n.begins_with("metal") or n.begins_with("trim") or n.begins_with("cornice") \
			or n.begins_with("roof") or n.begins_with("floor") or n.begins_with("door") \
			or n.begins_with("entrance") or n.begins_with("stairs") or n.begins_with("column"):
		return "modulos_edificio"
	return "otros"


## Construye las listas de trabajo a partir de nombre + firma geométrica medida.
func _construir_listas() -> void:
	_prefabs.clear() ; _paredes.clear() ; _paredes_bajas.clear() ; _paredes_top.clear()
	_ventanas.clear() ; _esquinas_muro.clear()
	_marcos_puerta.clear() ; _hojas_puerta.clear() ; _cornisas.clear() ; _techos.clear()
	_tramo_calle.clear() ; _plancha_asfalto.clear() ; _acera_recta.clear()
	_acera_pavimento.clear() ; _esquinas_acera.clear() ; _esquina_dir.clear()
	_linea_discontinua.clear() ; _pasos_peatones.clear() ; _pintura_esquinas.clear()
	_alcantarillas.clear()
	_sumideros.clear() ; _bolardos.clear() ; _aires.clear() ; _vegetacion.clear()

	for clave in _modelos.keys():
		var nombre := String(clave)
		var ln := nombre.to_lower()
		var caja: AABB = _modelos[clave]["caja"]
		var s := caja.size

		# --- Edificios completos del kit ---
		if _modelos[clave]["categoria"] == "edificios" and s.y > 6.0:
			_prefabs.append(nombre)

		# --- Calzadas ---
		# Tramos de 6 m de ancho (calzada + bordillos) por 12 m de largo, que es
		# la sección completa de un vial: 3 m de acera + 6 de calzada + 3 de acera.
		if ln.begins_with("street") and absf(s.x - 6.0) < 0.1 and absf(s.z - 12.0) < 0.1 and s.y > 0.1:
			_tramo_calle.append(nombre)
		# Planchas planas 6x6 m para los cruces.
		elif ln.begins_with("street") and absf(s.y) < 0.02 and absf(s.x - 6.0) < 0.1 and absf(s.z - 6.0) < 0.1:
			_plancha_asfalto.append(nombre)

		# --- Aceras ---
		# Piezas macizas (de la calzada a cota de acera) frente a las variantes
		# "Stripe", que son planos de pintura a cota de calzada.
		if ln.contains("sidewalk_straight") and s.y > 0.1:
			_acera_recta.append(nombre)
		if ln.contains("sidewalk_nocurb"):
			_acera_pavimento.append(nombre)
		if ln.contains("sidewalk_corner"):
			_esquina_dir[nombre] = _medir_esquina_redondeada(caja, _modelos[clave]["escena"])
			if s.y > 0.1:
				_esquinas_acera.append(nombre)
			elif s.y < 0.04:
				_pintura_esquinas.append(nombre)

		# --- Marcas viales ---
		if ln.contains("brokenline"):
			_linea_discontinua.append(nombre)
		# Raya doble amarilla del eje de la calzada (avenidas de varios carriles).
		if ln.contains("doubleyellow"):
			_linea_central.append(nombre)
		# Pasos de peatones: el normal (4.5 x 5.4 m) y el ancho (3.1 x 11.4 m),
		# que es el que cubre la calzada entera en las avenidas.
		if ln.contains("crosswalk"):
			if s.z < 7.0:
				_pasos_peatones.append(nombre)
			else:
				_pasos_anchos.append(nombre)

		# --- Mobiliario de calle ---
		if ln.contains("manhole"):
			_alcantarillas.append(nombre)
		if ln.contains("drain"):
			_sumideros.append(nombre)
		if ln.contains("bollard"):
			_bolardos.append(nombre)
		if ln.contains("acunit") or ln.contains("ac_unit"):
			_aires.append(nombre)
		# Vegetación del kit: las jardineras con reja (Prop_Planter_Single,
		# Sidewalk_Planter) se descartan a propósito: dejan el suelo liso y
		# continuo, y la vegetación la ponen los árboles y arbustos 3D.
		if _modelos[clave]["categoria"] == "vegetacion" and not ln.contains("planter"):
			_vegetacion.append(nombre)

		# --- Módulos de fachada (firma 2.00 x 3.00 m, poco fondo) ---
		var es_muro := absf(s.x - MODULO_ANCHO) < 0.06 and absf(s.y - PLANTA_ALTO) < 0.06 \
				and s.z > 0.05 and s.z < 0.7 and caja.position.y > -0.05
		if es_muro:
			if ln.contains("doorframe") or ln.contains("door_frame"):
				_marcos_puerta.append(nombre)
			else:
				_paredes.append(nombre)
				if ln.contains("window"):
					_ventanas.append(nombre)
				if ln.contains("firstfloor") or ln.contains("first_floor") or ln.contains("bottom"):
					_paredes_bajas.append(nombre)
				if ln.contains("toptrim") or ln.contains("top_trim"):
					_paredes_top.append(nombre)
		# Bloque de esquina del perímetro: 2.00 x 3.00 x 2.00 m
		if ln.contains("corner") and absf(s.x - 2.0) < 0.1 and absf(s.y - PLANTA_ALTO) < 0.1 \
				and absf(s.z - 2.0) < 0.1 and not ln.contains("roof") and not ln.contains("slate") \
				and not ln.contains("sidewalk") and not ln.contains("decal") and not ln.contains("ribbon"):
			_esquinas_muro.append(nombre)
		# Hoja de puerta: ~1.00 x 2.20 m
		if ln.begins_with("door_") and absf(s.x - 1.0) < 0.1 and s.y > 2.0 and s.y < 2.5:
			_hojas_puerta.append(nombre)

		# --- Cornisas: banda de 2 x 1 m que sobresale de la fachada ---
		# (sólo piezas "Cornice_": Entrance/Stairs son zócalos, no cornisas)
		if ln.begins_with("cornice") and absf(s.x - MODULO_ANCHO) < 0.06 and absf(s.y - 1.0) < 0.06 \
				and s.z > 0.3 and (caja.position.z + s.z) > 0.3 and not ln.contains("90angle"):
			_cornisas.append(nombre)

		# --- Azoteas planas: 2x2 m o 4x4 m, sin grosor ---
		if absf(s.y) < 0.02 and absf(s.x - s.z) < 0.06 and not ln.contains("90angle") \
				and ln.contains("roof"):
			var lado := int(round(s.x))
			if lado == 2 or lado == 4:
				if not _techos.has(lado):
					_techos[lado] = []
				(_techos[lado] as Array).append(nombre)

	# Si el kit trae esquinas redondeadas se usan ésas (las de esquina recta
	# quedan sin chaflán que orientar).
	var redondas: Array[String] = []
	for n in _esquinas_acera:
		if n.to_lower().contains("round"):
			redondas.append(n)
	if not redondas.is_empty():
		_esquinas_acera = redondas

	# Orden estable de las listas (una semilla fija da siempre la misma ciudad).
	_marcos_puerta.sort()
	_hojas_puerta.sort()

	_construir_familias()


## Agrupa las piezas del kit en familias de fachada coherentes (brick / metal /
## trim). Cada familia se completa con lo que tenga a mano, de modo que un
## edificio entero (planta baja, plantas, remate, esquinas y cornisa) pueda
## levantarse con una sola familia y nunca quede una celda sin cerrar.
func _construir_familias() -> void:
	_familias.clear()
	for fam: String in ["brick", "metal", "trim"]:
		var f := {
			"muros": _por_familia(_paredes, fam, true),
			"bajas": _por_familia(_paredes_bajas, fam, true),
			"ventanas": _por_familia(_ventanas, fam, true),
			"top": _por_familia(_paredes_top, fam, true),
			"esquinas": _por_familia(_esquinas_muro, fam),
			"cornisas": _por_familia(_cornisas, fam),
		}
		# Rellenos: si la familia no tiene pieza para una planta se repite una
		# pared lisa de la MISMA familia, antes que mezclar texturas.
		if (f["bajas"] as Array).is_empty():
			f["bajas"] = f["muros"]
		if (f["ventanas"] as Array).is_empty():
			f["ventanas"] = f["muros"]
		if (f["top"] as Array).is_empty():
			f["top"] = f["muros"]
		_familias[fam] = f


## Piezas de 'lista' cuyo nombre contiene 'fam'. Con 'solo_fachada' se descartan
## las piezas de borde (ángulos de 90°, tapas, guardas, semicolumnas y paredes de
## interior): son remates que, puestos en medio de un muro, dejan aletas y
## paneles a medio terminar. Nunca se usan como muro normal.
func _por_familia(lista: Array, fam: String, solo_fachada: bool = false) -> Array[String]:
	var salida: Array[String] = []
	if fam == "":
		return salida
	var descartes := ["90angle", "topcover", "guard", "interiorwall", "interior_wall",
			"halfcolumn", "halftrim", "corner", "inset_window", "wall_guard"]
	for n in lista:
		var ln := String(n).to_lower()
		if ln.contains("interiorwall") or ln.contains("interior_wall"):
			continue
		var borde := false
		if solo_fachada:
			for d: String in descartes:
				if ln.contains(d):
					borde = true
					break
		if borde:
			continue
		if ln.contains(fam):
			salida.append(String(n))
	return salida


## Deduce en qué esquina del modelo (en planta) está el chaflán redondeado:
## la esquina redondeada es la que queda más lejos de cualquier vértice.
## Devuelve (0,0) si el modelo no tiene una esquina realmente recortada.
func _medir_esquina_redondeada(caja: AABB, escena: PackedScene) -> Vector2i:
	var plantilla := escena.instantiate() as Node3D
	if plantilla == null:
		return Vector2i(0, 0)
	var verts := PackedVector3Array()
	_vertices(plantilla, verts)
	plantilla.free()
	if verts.is_empty():
		return Vector2i(0, 0)
	var esquinas: Array[Vector2] = [
		Vector2(caja.position.x, caja.position.z),
		Vector2(caja.end.x, caja.position.z),
		Vector2(caja.position.x, caja.end.z),
		Vector2(caja.end.x, caja.end.z),
	]
	var direcciones: Array[Vector2i] = [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]
	var mejor := 0
	var mejor_dist := -1.0
	for k in 4:
		var d := INF
		for v in verts:
			d = minf(d, Vector2(v.x, v.z).distance_to(esquinas[k]))
		if d > mejor_dist:
			mejor_dist = d
			mejor = k
	# Un chaflán real deja la esquina original a más de 40 cm de cualquier vértice.
	if mejor_dist < 0.4:
		return Vector2i(0, 0)
	return direcciones[mejor]


# =============================================================================
#  Utilidades de medición
# =============================================================================

## AABB exacta de un modelo, leyendo sus vértices (más fiable que get_aabb()).
func _aabb_vertices(nodo: Node) -> AABB:
	var verts := PackedVector3Array()
	_vertices(nodo, verts)
	if verts.is_empty():
		return AABB()
	var caja := AABB(verts[0], Vector3.ZERO)
	for v in verts:
		caja = caja.expand(v)
	return caja


## Acumula en 'salida' los vértices de todas las mallas, en el espacio de 'nodo'.
func _vertices(nodo: Node, salida: PackedVector3Array) -> void:
	var pila: Array[Node] = [nodo]
	while not pila.is_empty():
		var n: Node = pila.pop_back()
		for c in n.get_children():
			pila.append(c)
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			if mi.mesh == null:
				continue
			var t := _transform_relativo(nodo, mi)
			for sup in mi.mesh.get_surface_count():
				var matriz := mi.mesh.surface_get_arrays(sup)
				if matriz.is_empty():
					continue
				var datos: Variant = matriz[Mesh.ARRAY_VERTEX]
				if datos == null:
					continue
				for v in (datos as PackedVector3Array):
					salida.append(t * v)


## Transformación de 'nodo' al espacio de su antepasado 'raiz'.
func _transform_relativo(raiz: Node, nodo: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var actual: Node = nodo
	while actual != null and actual != raiz:
		if actual is Node3D:
			t = (actual as Node3D).transform * t
		actual = actual.get_parent()
	return t


## Devuelve {malla, local} si el modelo es un único MeshInstance3D (agrupable
## en MultiMesh, ya que los materiales viven en las superficies de la malla).
func _malla_unica(escena: PackedScene) -> Dictionary:
	var raiz := escena.instantiate()
	var mallas: Array[Node] = []
	var pila: Array[Node] = [raiz]
	while not pila.is_empty():
		var n: Node = pila.pop_back()
		for c in n.get_children():
			pila.append(c)
		if n is MeshInstance3D:
			mallas.append(n)
	var datos := {}
	# Sólo es agrupable si tiene UNA malla de UN solo material (las mallas con
	# varias capas — calzada + pintura — se instancian una a una).
	if mallas.size() == 1:
		var mi := mallas[0] as MeshInstance3D
		if mi.mesh != null and mi.mesh.get_surface_count() == 1:
			datos = {"malla": mi.mesh, "local": _transform_relativo(raiz, mi)}
	raiz.free()
	return datos


func _es_multimesh(nombre: String) -> bool:
	if not _mm_cache.has(nombre):
		var datos := _malla_unica(_modelos[nombre]["escena"])
		_mm_cache[nombre] = not datos.is_empty()
	return bool(_mm_cache[nombre])


## ¿Es esta capa la pintura del kit? (material "MI_StreetDecals", con blending).
func _es_capa_decal(mat: Material) -> bool:
	if mat is BaseMaterial3D:
		var m := mat as BaseMaterial3D
		if m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			return true
	return String(mat.resource_name).to_lower().contains("decal") if mat != null else false


## ¿El modelo trae capas de pintura propietarias? (tramos y planchas de asfalto
## las traen pintadas; el generador prefiere colocar sus propias marcas).
func _tiene_capa_decal(raiz: Node) -> bool:
	var pila: Array[Node] = [raiz]
	while not pila.is_empty():
		var n: Node = pila.pop_back()
		for c in n.get_children():
			pila.append(c)
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var malla: Mesh = (n as MeshInstance3D).mesh
			for i in malla.get_surface_count():
				if _es_capa_decal(malla.surface_get_material(i)):
					return true
	return false


## Sustituye las mallas del nodo por copias sin la capa de pintura.
func _quitar_capas_decal(nodo: Node) -> void:
	if nodo is MeshInstance3D and (nodo as MeshInstance3D).mesh != null:
		var mi := nodo as MeshInstance3D
		mi.mesh = _malla_sin_decal(mi.mesh)
	for c in nodo.get_children():
		_quitar_capas_decal(c)


## Copia de una malla sin sus superficies de pintura (se cachea por malla).
func _malla_sin_decal(malla: Mesh) -> Mesh:
	if _mallas_limpias.has(malla):
		return _mallas_limpias[malla] as Mesh
	var limpia := ArrayMesh.new()
	for i in malla.get_surface_count():
		var mat: Material = malla.surface_get_material(i)
		if _es_capa_decal(mat):
			continue
		var capas: Array = malla.surface_get_arrays(i)
		if capas.is_empty():
			continue
		limpia.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, capas)
		limpia.surface_set_material(limpia.get_surface_count() - 1, mat)
	if limpia.get_surface_count() == 0:
		limpia = null        # no quedaba nada sólido: se deja la malla original
		_mallas_limpias[malla] = malla
		return malla
	_mallas_limpias[malla] = limpia
	return limpia


# =============================================================================
#  Paso 2: trazado y contenedores
# =============================================================================

func _preparar_trazado() -> void:
	var calzada := maxf(6.0, roundf(ancho_calzada / 6.0) * 6.0)      # múltiplo de 6 m
	var acera := maxf(3.0, roundf(ancho_acera / 3.0) * 3.0)           # múltiplo de 3 m
	var manzana := maxf(12.0, roundf(tamano_manzana / 6.0) * 6.0)     # múltiplo de 6 m
	var hw := calzada * 0.5 + acera                                   # semiancho del vial
	var paso := manzana + 2.0 * hw                                    # distancia entre líneas de calle
	var ext := Vector2(float(manzanas_x) * paso, float(manzanas_z) * paso)
	_trazado = {
		"calzada": calzada,
		"acera": acera,
		"manzana": manzana,
		"hw": hw,
		"paso": paso,
		"ext": ext,
		"off": -ext * 0.5,
	}


func _crear_contenedores() -> void:
	var raiz := Node3D.new()
	raiz.name = NODO_CIUDAD
	add_child(raiz)
	var nombres: Array[String] = ["Suelo", "Calles", "Aceras", "Edificios", "Vegetacion", "Props", "MarcasViales"]
	for n in nombres:
		var c := Node3D.new()
		c.name = n
		raiz.add_child(c)
		_cont[n] = c
	# Subcontenedor para los edificios completos (los modulares van a MultiMesh).
	var pref := Node3D.new()
	pref.name = "Prefabricados"
	(_cont["Edificios"] as Node3D).add_child(pref)
	_cont["Prefabricados"] = pref
	# Subcontenedor de los edificios modulares (piezas sueltas + su colisión).
	var mods := Node3D.new()
	mods.name = "Modulares"
	(_cont["Edificios"] as Node3D).add_child(mods)
	_cont["Modulares"] = mods


# =============================================================================
#  Paso 3: colocación de piezas
# =============================================================================

## Transformación de colocación: posición + giro en Y + escala uniforme.
func _t(pos: Vector3, giro: float = 0.0, escala: float = 1.0) -> Transform3D:
	var base := Basis(Vector3.UP, giro)
	if not is_equal_approx(escala, 1.0):
		base = base.scaled(Vector3.ONE * escala)
	return Transform3D(base, pos)


## Giro en Y (múltiplo de 90°) que lleva 'dir_modelo' sobre 'dir_deseada'.
func _rot_para_dir(dir_modelo: Vector2i, dir_deseada: Vector2i) -> float:
	var modelo := Vector2(dir_modelo).normalized()
	var deseada := Vector2(dir_deseada).normalized()
	for k in 4:
		var giro := PI * 0.5 * float(k)
		var rotado := Vector2(modelo.x * cos(giro) + modelo.y * sin(giro),
				-modelo.x * sin(giro) + modelo.y * cos(giro))
		if rotado.dot(deseada) > 0.9:
			return giro
	return 0.0


func _elegir(lista: Array) -> String:
	if lista.is_empty():
		return ""
	return String(lista[_rng.randi_range(0, lista.size() - 1)])


## Coloca una pieza: agrupada en MultiMesh si es posible, si no instanciada.
## Con 'limpiar_decal' se instancia suelta y sin su capa de pintura.
func _colocar(pieza: String, xf: Transform3D, padre: Node3D, limpiar_decal: bool = false) -> void:
	if pieza == "":
		# Cualquier celda sin pieza sería un hueco en la fachada: se cuenta para
		# que el informe final avise si alguna vez pasara.
		_est["piezas_vacias"] = int(_est.get("piezas_vacias", 0)) + 1
		return
	var agrupable := usar_multimesh and not (limpiar_decal and bool(_con_decal.get(pieza, false)))
	if agrupable and _es_multimesh(pieza):
		if not _lotes.has(pieza):
			_lotes[pieza] = []
			_lote_padre[pieza] = padre
		(_lotes[pieza] as Array).append(xf)
	else:
		_instanciar_pieza(pieza, xf, padre, pieza, limpiar_decal)


func _instanciar_pieza(pieza: String, xf: Transform3D, padre: Node3D, nombre: String,
		limpiar_decal: bool = false) -> Node3D:
	var escena := _modelos[pieza]["escena"] as PackedScene
	var nodo := escena.instantiate() as Node3D
	nodo.name = nombre
	nodo.transform = xf
	if limpiar_decal:
		_quitar_capas_decal(nodo)
	if _es_plancha_techo(pieza):
		# Azotea suelta: misma membrana de grava que las agrupadas.
		var mat_techo := _material_techo(pieza)
		if mat_techo != null:
			for n in nodo.find_children("*", "MeshInstance3D", true, false):
				(n as MeshInstance3D).material_override = mat_techo
	padre.add_child(nodo)
	return nodo


## Losa horizontal (rect en XZ) con la cara superior en 'techo' (por defecto
## Y_LOSA, cota de acera) y la inferior en Y_SUELO.
func _losa(rect: Rect2, color: Color, con_malla: bool, con_colision: bool, padre: Node3D,
		nombre: String, techo: float = Y_LOSA) -> void:
	var alto := techo - Y_SUELO
	var tam := Vector3(rect.size.x, alto, rect.size.y)
	var cuerpo := StaticBody3D.new()
	cuerpo.name = nombre
	cuerpo.position = Vector3(rect.get_center().x, Y_SUELO + alto * 0.5, rect.get_center().y)
	if con_malla:
		var caja := BoxMesh.new()
		caja.size = tam
		var mi := MeshInstance3D.new()
		mi.mesh = caja
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.roughness = 0.95
		mi.material_override = mat
		cuerpo.add_child(mi)
	if con_colision:
		var forma := CollisionShape3D.new()
		var caja_col := BoxShape3D.new()
		caja_col.size = tam
		forma.shape = caja_col
		cuerpo.add_child(forma)
	padre.add_child(cuerpo)


## Añade colisión envolvente a un nodo, sólo si el modelo no trae ya una.
func _anadir_colision_caja(nodo: Node3D, caja: AABB) -> void:
	if _tiene_colision(nodo):
		return
	var cuerpo := StaticBody3D.new()
	cuerpo.name = "Colision"
	var forma := CollisionShape3D.new()
	var caja_col := BoxShape3D.new()
	caja_col.size = caja.size
	forma.shape = caja_col
	forma.position = caja.get_center()
	cuerpo.add_child(forma)
	nodo.add_child(cuerpo)


func _tiene_colision(nodo: Node) -> bool:
	var pila: Array[Node] = [nodo]
	while not pila.is_empty():
		var n: Node = pila.pop_back()
		if n is CollisionShape3D or n is StaticBody3D or n is Area3D:
			return true
		for c in n.get_children():
			pila.append(c)
	return false


# =============================================================================
#  Terreno y viario
# =============================================================================

# =============================================================================
#  Cámara, luz y entorno (opcional: sólo si la escena no los tiene)
# =============================================================================

## Añade Cámara + Sol + Entorno para que la ciudad se vea al pulsar Play.
## No toca nada si esos nodos ya existen (así respeta escenas con su propia cámara).
func _configurar_escena() -> void:
	if not crear_camara_y_luz:
		return
	var raiz: Node = null
	if is_inside_tree():
		var arbol := get_tree()
		raiz = arbol.edited_scene_root if Engine.is_editor_hint() else arbol.current_scene
	if raiz == null:
		raiz = self

	if raiz.get_node_or_null("Entorno") == null:
		var entorno := WorldEnvironment.new()
		entorno.name = "Entorno"
		var env := Environment.new()
		env.background_mode = Environment.BG_SKY
		var cielo := Sky.new()
		var mat := ProceduralSkyMaterial.new()
		mat.sky_top_color = Color(0.30, 0.47, 0.76)
		mat.sky_horizon_color = Color(0.76, 0.81, 0.87)
		mat.ground_bottom_color = Color(0.21, 0.21, 0.22)
		mat.ground_horizon_color = Color(0.58, 0.59, 0.58)
		cielo.sky_material = mat
		env.sky = cielo
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		env.ambient_light_sky_contribution = 0.6
		env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		env.ssao_enabled = true
		env.fog_enabled = true
		env.fog_light_color = Color(0.73, 0.76, 0.81)
		env.fog_density = 0.00035
		entorno.environment = env
		raiz.add_child(entorno)
		_preparar_para_guardar(entorno, raiz)

	if raiz.get_node_or_null("Sol") == null:
		var sol := DirectionalLight3D.new()
		sol.name = "Sol"
		sol.rotation_degrees = Vector3(-52.0, 15.0, 0.0)
		sol.light_energy = 1.25
		sol.shadow_enabled = true
		# Sombras: distancia ajustada al tamaño de la ciudad y sesgo alto. Es lo
		# que quita el "acné" de sombra: los parches oscuros y pixelados que
		# salían sobre las azoteas y las aceras.
		sol.directional_shadow_max_distance = 260.0
		sol.shadow_bias = 0.04
		sol.shadow_normal_bias = 2.0
		sol.shadow_blur = 1.2
		sol.directional_shadow_blend_splits = true
		raiz.add_child(sol)
		_preparar_para_guardar(sol, raiz)

	if raiz.get_node_or_null("CamaraCiudad") == null:
		var cam := Camera3D.new()
		cam.name = "CamaraCiudad"
		cam.position = Vector3(168.0, 124.0, 168.0)
		cam.rotation_degrees = Vector3(-27.5, 45.0, 0.0)
		cam.current = true
		if camara_libre and ResourceLoader.exists("res://camara_libre.gd"):
			cam.set_script(ResourceLoader.load("res://camara_libre.gd"))
		raiz.add_child(cam)
		_preparar_para_guardar(cam, raiz)


## En el editor marca el owner para que el nodo se guarde con la escena.
func _preparar_para_guardar(nodo: Node, raiz: Node) -> void:
	if _vista_editor:
		return
	if Engine.is_editor_hint() and is_inside_tree() and raiz == get_tree().edited_scene_root:
		nodo.owner = raiz


## Enfoca la vista 3D del editor en la ciudad recién generada (sólo editor).
func _enfocar_vista_editor() -> void:
	if not Engine.is_editor_hint():
		return
	var vista := EditorInterface.get_editor_viewport_3d()
	if vista == null:
		return
	var cam := vista.get_camera_3d()
	if cam == null:
		return
	cam.look_at_from_position(Vector3(168.0, 124.0, 168.0), Vector3(0.0, 6.0, 0.0), Vector3.UP)


func _generar_suelo() -> void:
	var off: Vector2 = _trazado.off
	var ext: Vector2 = _trazado.ext
	var hw: float = _trazado.hw
	var margen := 2.0
	var rect := Rect2(off.x - hw - margen, off.y - hw - margen,
			ext.x + 2.0 * (hw + margen), ext.y + 2.0 * (hw + margen))
	_losa(rect, COLOR_SUELO, true, colisiones_suelo, _cont["Suelo"], "Terreno", Y_TERRENO)
	_est["suelos"] = int(_est.get("suelos", 0)) + 1


func _generar_calles() -> void:
	var off: Vector2 = _trazado.off
	var ext: Vector2 = _trazado.ext
	var paso: float = _trazado.paso
	# Calles verticales (discurren en Z) y horizontales (en X)
	for i in manzanas_x + 1:
		_corredor(true, off.x + i * paso, off.y, off.y + ext.y)
	for j in manzanas_z + 1:
		_corredor(false, off.y + j * paso, off.x, off.x + ext.x)
	# Cruces
	for i in manzanas_x + 1:
		for j in manzanas_z + 1:
			_interseccion(off.x + i * paso, off.y + j * paso, i, j)


## Corredor viario: p = línea de calle, d0..d1 = extensión del núcleo urbano.
## Sección: acera + calzada + acera. La acera se compone con piezas macizas de
## 3x3 m (su bordillo mira a la calzada) y la calzada con planchas planas de
## asfalto de 6x6 m teseladas a lo largo y a lo ancho (avenidas de 12 m), sin la
## pintura propia del kit.
func _corredor(vertical: bool, p: float, d0: float, d1: float) -> void:
	var calzada: float = _trazado.calzada
	var acera: float = _trazado.acera
	var hw: float = _trazado.hw
	var paso: float = _trazado.paso
	var n_lineas: int = (manzanas_z + 1) if vertical else (manzanas_x + 1)
	var cont_calles: Node3D = _cont["Calles"]
	var cont_marcas: Node3D = _cont["MarcasViales"]
	var cont_acera: Node3D = _cont["Aceras"]

	# Aceras: superficie peatonal y colisión a ambos lados del vial.
	for lado: float in [-1.0, 1.0]:
		_banda_acera(vertical, p, lado, d0 - hw, d1 + hw)

	# Tramos entre cruces consecutivos: calzada y aceras.
	for k in n_lineas - 1:
		var ini: float = d0 + k * paso + calzada * 0.5
		var fin: float = d0 + (k + 1) * paso - calzada * 0.5
		var largo := fin - ini
		if largo < 6.0:
			continue
		var n := maxi(1, int(round(largo / 6.0)))
		# Planchas de asfalto: se teselan a lo largo y, si la calzada es más ancha
		# que una plancha (avenida de varios carriles), también a lo ancho.
		var n_ancho := maxi(1, int(round(calzada / 6.0)))
		for t in n:
			var c: float = ini + largo * (float(t) + 0.5) / float(n)
			for a in n_ancho:
				var lat: float = p - calzada * 0.5 + 6.0 * (float(a) + 0.5)
				var pos := Vector3(lat, Y_ACERA, c) if vertical else Vector3(c, Y_ACERA, lat)
				# Calzada: planchas planas (sin bordillo ni pintura propias).
				if not _plancha_asfalto.is_empty():
					_colocar(_elegir(_plancha_asfalto), _t(pos), cont_calles, true)
				elif not _tramo_calle.is_empty():
					# Reserva: tramos con aceras incorporadas, alineados con el vial.
					_colocar(_elegir(_tramo_calle), _t(pos, 0.0 if vertical else PI * 0.5),
							cont_calles, true)
				_est["tramos"] = int(_est.get("tramos", 0)) + 1
			# Marcas viales: doble amarilla en el eje y una discontinua por cada
			# separación de carriles. OJO: las rayas del kit corren en X, así que
			# en las calles que van en Z hay que girarlas 90°.
			if generar_marcas_viales:
				var giro_m := PI * 0.5 if vertical else 0.0
				var ejes: Array[float] = [0.0]
				if calzada >= 9.0:
					ejes.append(-calzada * 0.25)
					ejes.append(calzada * 0.25)
				for e: float in ejes:
					var lista_m: Array = _linea_discontinua
					if is_zero_approx(e) and not _linea_central.is_empty():
						lista_m = _linea_central
					if lista_m.is_empty():
						continue
					var lat_m: float = p + e
					var pos_m := Vector3(lat_m, Y_ACERA, c) if vertical else Vector3(c, Y_ACERA, lat_m)
					_colocar(_elegir(lista_m), _t(pos_m, giro_m), cont_marcas)
					_est["marcas"] = int(_est.get("marcas", 0)) + 1
		# Aceras del tramo: piezas de 3x3 m, 1 cm metidas bajo el bordillo de la
		# calzada y 1 cm antes del borde de la manzana (evita caras coplanares).
		if _acera_recta.is_empty():
			continue
		var pieza_acera: String = _elegir(_acera_recta)
		var m := maxi(1, int(round(largo / 3.0)))
		for t in m:
			var c: float = ini + largo * (float(t) + 0.5) / float(m)
			for lado: float in [-1.0, 1.0]:
				var centro := p + lado * (calzada * 0.5 + acera * 0.5 - 0.01)
				var pos := Vector3(centro, Y_ACERA, c) if vertical else Vector3(c, Y_ACERA, centro)
				_colocar(pieza_acera, _t(pos, _giro_acera(vertical, lado)), cont_acera)


## Giro que deja el bordillo de las piezas de acera mirando a la calzada.
## En el kit, el módulo de acera tiene la calzada hacia su -X local.
func _giro_acera(vertical: bool, lado: float) -> float:
	if vertical:
		return PI if lado < 0.0 else 0.0
	return PI * 0.5 if lado < 0.0 else -PI * 0.5


func _banda_acera(vertical: bool, p: float, lado: float, d0: float, d1: float) -> void:
	var calzada: float = _trazado.calzada
	var acera: float = _trazado.acera
	var centro_lat := p + lado * (calzada * 0.5 + acera * 0.5)
	var rect: Rect2
	if vertical:
		rect = Rect2(centro_lat - acera * 0.5, d0, acera, d1 - d0)
	else:
		rect = Rect2(d0, centro_lat - acera * 0.5, d1 - d0, acera)
	_losa(rect, COLOR_LOSA, false, colisiones_suelo, _cont["Aceras"], "Acera")


## Cruce: calzada completa + 4 esquinas de acera + pasos de peatones.
func _interseccion(px: float, pz: float, i: int, j: int) -> void:
	var calzada: float = _trazado.calzada
	var acera: float = _trazado.acera
	var cont_calles: Node3D = _cont["Calles"]
	var cont_acera: Node3D = _cont["Aceras"]
	var cont_marcas: Node3D = _cont["MarcasViales"]

	# Calzada del cruce: planchas cuadradas que cubren todo el cuadrado.
	var lado_pl := 6.0
	var n := maxi(1, int(round(calzada / lado_pl)))
	for a in n:
		for b in n:
			var x := px - calzada * 0.5 + lado_pl * (float(a) + 0.5)
			var z := pz - calzada * 0.5 + lado_pl * (float(b) + 0.5)
			_colocar(_elegir(_plancha_asfalto), _t(Vector3(x, Y_ACERA, z)), cont_calles, true)

	# Esquinas de acera: el chaflán redondeado mira al centro del cruce. Sobre
	# cada losa se pinta además la marca curva del chaflán (piezas "Stripe",
	# planas y a cota de calzada) para rematar el bordillo como en el kit.
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			if _esquinas_acera.is_empty():
				continue
			var x := px + sx * (calzada * 0.5 + acera * 0.5)
			var z := pz + sz * (calzada * 0.5 + acera * 0.5)
			var dir_deseada := Vector2i(-int(sx), -int(sz))
			var pieza := _elegir(_esquinas_acera)
			var giro := _rot_para_dir(_esquina_dir.get(pieza, Vector2i(1, 1)), dir_deseada)
			_colocar(pieza, _t(Vector3(x, Y_ACERA, z), giro), cont_acera)
			if not _pintura_esquinas.is_empty():
				# La pieza de pintura es la banda del bordillo: su hueco queda
				# al lado contrario del chaflán, así que apunta hacia fuera del
				# cruce para dejar la curva sobre la calzada.
				var pintura := _elegir(_pintura_esquinas)
				var giro_p := _rot_para_dir(_esquina_dir.get(pintura, Vector2i(1, 1)), Vector2i(int(sx), int(sz)))
				_colocar(pintura, _t(Vector3(x, Y_ACERA, z), giro_p), cont_marcas)
				_est["marcas"] = int(_est.get("marcas", 0)) + 1

	# Pasos de peatones en los cuatro brazos (no se pintan si el brazo da al vacío).
	# En avenidas se usa el paso ancho, que cruza la calzada de 12 m entera.
	var pasos: Array = _pasos_peatones
	if calzada >= 9.0 and not _pasos_anchos.is_empty():
		pasos = _pasos_anchos
	if generar_marcas_viales and not pasos.is_empty():
		var paso_pieza := _elegir(pasos)
		for sz: float in [-1.0, 1.0]:
			if j + int(sz) < 0 or j + int(sz) > manzanas_z:
				continue
			if _rng.randf() <= 0.85:
				var z := pz + sz * (calzada * 0.5 + 2.27)
				_colocar(paso_pieza, _t(Vector3(px, Y_ACERA, z), PI * 0.5), cont_marcas)
				_est["marcas"] = int(_est.get("marcas", 0)) + 1
		for sx: float in [-1.0, 1.0]:
			if i + int(sx) < 0 or i + int(sx) > manzanas_x:
				continue
			if _rng.randf() <= 0.85:
				var x := px + sx * (calzada * 0.5 + 2.27)
				_colocar(paso_pieza, _t(Vector3(x, Y_ACERA, pz), 0.0), cont_marcas)
				_est["marcas"] = int(_est.get("marcas", 0)) + 1


# =============================================================================
#  Manzanas y edificios
# =============================================================================

func _generar_manzanas() -> void:
	var off: Vector2 = _trazado.off
	var paso: float = _trazado.paso
	var manzana: float = _trazado.manzana
	var hw: float = _trazado.hw
	var parques := _elegir_parques()
	for i in manzanas_x:
		for j in manzanas_z:
			var rect := Rect2(off.x + i * paso + hw, off.y + j * paso + hw, manzana, manzana)
			# Manzana-parque: césped y jardines en lugar de solares edificados.
			if parques.has(Vector2i(i, j)):
				_parque(rect)
				continue
			# Losa de manzana: plataforma a cota de acera, 2 mm por debajo del
			# pavimento del kit (así nunca queda un hueco a la vista y tampoco
			# hay caras coplanares). Se retranquea 2 cm del borde.
			var losa := rect.grow(-0.02)
			_losa(losa, COLOR_LOSA, true, colisiones_suelo, _cont["Suelo"], "Manzana_%d_%d" % [i, j])
			_est["suelos"] = int(_est.get("suelos", 0)) + 1
			# El pavimento lo pone cada plaza: los solares edificados quedan
			# tapados por el propio edificio, que ocupa la parcela entera.
			_poblar_manzana(rect, i, j)


## Reparte la manzana en solares (1x1, 2x1, 1x2 o 2x2) y edifica cada uno.
func _poblar_manzana(rect: Rect2, _i: int, _j: int) -> void:
	var div_x := 2
	var div_z := 2
	if rect.size.x >= 18.0 and rect.size.y >= 18.0:
		var r := _rng.randf()
		if r < 0.30:
			div_x = 1 ; div_z = 1       # manzana entera: solar para edificio grande
		elif r < 0.50:
			div_x = 2 ; div_z = 1
		elif r < 0.70:
			div_x = 1 ; div_z = 2
		else:
			div_x = 2 ; div_z = 2       # cuatro solares medianos
	for a in div_x:
		for b in div_z:
			var origen := Vector2(rect.position.x + rect.size.x * float(a) / float(div_x),
					rect.position.y + rect.size.y * float(b) / float(div_z))
			var parcela := Rect2(origen, Vector2(rect.size.x / float(div_x), rect.size.y / float(div_z)))
			if _rng.randf() < prob_solar_vacio:
				_plaza(parcela)
			else:
				_poner_edificio(parcela)


## Elige las manzanas que serán parque: se prefieren las céntricas (las más
## visibles) con un poco de azar, para que no salgan siempre en el mismo sitio.
func _elegir_parques() -> Array[Vector2i]:
	var elegidas: Array[Vector2i] = []
	var total := manzanas_x * manzanas_z
	var cuantos := clampi(manzanas_parque, 0, maxi(total - 1, 0))
	if cuantos == 0:
		return elegidas
	var centro := Vector2(float(manzanas_x - 1) * 0.5, float(manzanas_z - 1) * 0.5)
	var candidatas: Array = []
	for i in manzanas_x:
		for j in manzanas_z:
			var d := Vector2(float(i), float(j)).distance_to(centro)
			candidatas.append({"celda": Vector2i(i, j), "peso": d + _rng.randf_range(0.0, 1.6)})
	candidatas.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["peso"]) < float(b["peso"]))
	for k in cuantos:
		elegidas.append(candidatas[k]["celda"] as Vector2i)
	return elegidas


## Material del césped: repite la textura cada 2 m sobre la cara superior.
func _material_cesped(tam: Vector2) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	if _tex_cesped != null:
		mat.albedo_texture = _tex_cesped
		mat.uv1_scale = Vector3(maxf(tam.x, 1.0) / 2.0, maxf(tam.y, 1.0) / 2.0, 1.0)
	else:
		mat.albedo_color = Color(0.24, 0.36, 0.18)
	mat.roughness = 1.0
	return mat


## Manzana-parque: césped a cota de calzada, senderos en cruz a cota de acera,
## vegetación por los cuatro cuadrantes y bolardos en las bocas de los senderos.
func _parque(rect: Rect2) -> void:
	var centro := rect.get_center()
	var cont_aceras: Node3D = _cont["Aceras"]
	_est["parques"] = int(_est.get("parques", 0)) + 1

	# --- Césped: losa con colisión, 15 cm por debajo de la acera -------------
	var alto := Y_PARQUE - Y_SUELO
	var tam := Vector3(rect.size.x, alto, rect.size.y)
	var cuerpo := StaticBody3D.new()
	cuerpo.name = "Parque_%d" % int(_est["parques"])
	cuerpo.position = Vector3(centro.x, Y_SUELO + alto * 0.5, centro.y)
	var caja := BoxMesh.new()
	caja.size = tam
	var malla := MeshInstance3D.new()
	malla.mesh = caja
	malla.material_override = _material_cesped(rect.size)
	cuerpo.add_child(malla)
	if colisiones_suelo:
		var forma := CollisionShape3D.new()
		var caja_col := BoxShape3D.new()
		caja_col.size = tam
		forma.shape = caja_col
		cuerpo.add_child(forma)
	_cont["Suelo"].add_child(cuerpo)

	# --- Senderos en cruz de 3 m con las losas sin bordillo del kit ----------
	if not _acera_pavimento.is_empty():
		var n := maxi(2, int(round(rect.size.x / 3.0)))
		@warning_ignore("integer_division")
		var central := n / 2
		for a in n:
			var x := rect.position.x + 1.5 + 3.0 * float(a)
			var z := rect.position.y + 1.5 + 3.0 * float(a)
			# Sendero este-oeste (fila central completa).
			_colocar(_elegir(_acera_pavimento), _t(Vector3(x, Y_ACERA, centro.y)), cont_aceras)
			# Sendero norte-sur (la losa central ya está puesta).
			if a != central:
				_colocar(_elegir(_acera_pavimento), _t(Vector3(centro.x, Y_ACERA, z), PI * 0.5),
						cont_aceras)

	# --- Árboles: por el césped, sin pisar los senderos ----------------------
	var puestos := 0
	var intentos := 0
	while puestos < arboles_por_parque and intentos < arboles_por_parque * 25:
		intentos += 1
		var x := _rng.randf_range(rect.position.x + 2.2, rect.end.x - 2.2)
		var z := _rng.randf_range(rect.position.y + 2.2, rect.end.y - 2.2)
		if absf(x - centro.x) < 2.1 or absf(z - centro.y) < 2.1:
			continue
		if _colocar_arbol(Vector3(x, Y_PARQUE, z), 5.0, 7.5):
			puestos += 1

	# --- Arbustos junto a los dos senderos -----------------------------------
	for k in 4:
		var c := rect.position.x + 3.0 + 6.0 * float(k)
		for s: float in [-1.0, 1.0]:
			_colocar_arbusto(Vector3(c + _rng.randf_range(-0.6, 0.6), Y_PARQUE,
					centro.y + s * 2.3), 0.7, 1.1)
	for k in 3:
		var c2 := rect.position.y + 4.5 + 7.0 * float(k)
		for s: float in [-1.0, 1.0]:
			_colocar_arbusto(Vector3(centro.x + s * 2.3, Y_PARQUE,
					c2 + _rng.randf_range(-0.6, 0.6)), 0.7, 1.1)

	# --- Jardineras del propio kit repartidas por el césped ------------------
	if not _vegetacion.is_empty():
		for k in 5:
			var x2 := _rng.randf_range(rect.position.x + 2.5, rect.end.x - 2.5)
			var z2 := _rng.randf_range(rect.position.y + 2.5, rect.end.y - 2.5)
			if absf(x2 - centro.x) < 2.1 or absf(z2 - centro.y) < 2.1:
				continue
			_colocar_vegetacion(Vector3(x2, Y_PARQUE, z2), _rng.randf_range(0.9, 1.1), Y_PARQUE)

	# --- Bolardos en las cuatro bocas de los senderos ------------------------
	if generar_props and not _bolardos.is_empty():
		var pieza := _elegir(_bolardos)
		for s: float in [-1.0, 1.0]:
			for t: float in [-1.0, 1.0]:
				var boca_x := Vector3(centro.x + s * 1.8, Y_ACERA,
						centro.y + t * (rect.size.y * 0.5 - 1.0))
				var boca_z := Vector3(centro.x + t * (rect.size.x * 0.5 - 1.0), Y_ACERA,
						centro.y + s * 1.8)
				_colocar_prop(pieza, boca_x, true, 1.0)
				_colocar_prop(pieza, boca_z, true, 1.0)


## Solar vacío: plaza pavimentada y con vegetación. Al estar rodeada de
## edificios que ocupan su parcela entera, tampoco deja huecos ocultos.
func _plaza(rect: Rect2) -> void:
	# Pavimento a cota de acera con las losas sin bordillo del kit.
	if pavimentar_manzanas and not _acera_pavimento.is_empty():
		var n_x := maxi(1, int(round(rect.size.x / 3.0)))
		var n_z := maxi(1, int(round(rect.size.y / 3.0)))
		for a in n_x:
			for b in n_z:
				var x := rect.position.x + 1.5 + 3.0 * float(a)
				var z := rect.position.y + 1.5 + 3.0 * float(b)
				_colocar(_elegir(_acera_pavimento),
						_t(Vector3(x, Y_ACERA, z), PI * 0.5 * float(_rng.randi_range(0, 3))),
						_cont["Aceras"])
	var margen := 2.5
	if generar_vegetacion and not _vegetacion.is_empty():
		for k in _rng.randi_range(1, 3):
			var x := _rng.randf_range(rect.position.x + margen, rect.end.x - margen)
			var z := _rng.randf_range(rect.position.y + margen, rect.end.y - margen)
			_colocar_vegetacion(Vector3(x, Y_ACERA, z), _rng.randf_range(0.85, 1.05))
	# Algún árbol y algún arbusto para que el hueco no quede pelado.
	for k in _rng.randi_range(1, 2):
		var xa := _rng.randf_range(rect.position.x + margen, rect.end.x - margen)
		var za := _rng.randf_range(rect.position.y + margen, rect.end.y - margen)
		_colocar_arbol(Vector3(xa, Y_ACERA, za), 4.5, 6.5)
	if _rng.randf() < 0.7:
		var xb := _rng.randf_range(rect.position.x + margen, rect.end.x - margen)
		var zb := _rng.randf_range(rect.position.y + margen, rect.end.y - margen)
		_colocar_arbusto(Vector3(xb, Y_ACERA, zb), 0.8, 1.2)


func _poner_edificio(rect: Rect2) -> void:
	var cabe_prefab := minf(rect.size.x, rect.size.y) >= 13.0
	# En solares grandes se intenta siempre el edificio completo del kit; si no
	# encaja (o están desactivados) se cae al edificio modular.
	var poner_prefab := usar_prefabricados and cabe_prefab
	if poner_prefab and _poner_prefab(rect):
		return
	if usar_modulares:
		_poner_modular(rect)
	elif usar_prefabricados:
		_poner_prefab(rect)


## Coloca uno de los edificios completos del kit (Building_*). Se estira en
## planta para llenar la parcela entera, de modo que el solar queda cerrado y
## el edificio se pega a los vecinos: no quedan rendijas por las que colarse.
## Si el estirón deformaría demasiado el modelo, se descarta y el solar se
## resuelve con el edificio modular (que encaja exacto en la retícula de 2 m).
func _poner_prefab(rect: Rect2) -> bool:
	var disponible := rect.size
	var opciones: Array = []
	for nombre in _prefabs:
		var caja: AABB = _modelos[nombre]["caja"]
		if caja.size.x < 0.5 or caja.size.z < 0.5:
			continue
		for giro: float in [0.0, PI * 0.5]:
			# Escalas en los ejes LOCALES del modelo: con el giro de 90° el eje
			# x local acaba apuntando al z del mundo y al revés.
			var girado := not is_zero_approx(giro)
			var esc_local_x := (disponible.x / caja.size.z) if girado else (disponible.x / caja.size.x)
			var esc_local_z := (disponible.y / caja.size.x) if girado else (disponible.y / caja.size.z)
			var deforme := maxf(esc_local_x, esc_local_z) / maxf(minf(esc_local_x, esc_local_z), 0.001)
			if esc_local_x < 0.8 or esc_local_z < 0.8 or esc_local_x > 2.2 or esc_local_z > 2.2 or deforme > 1.35:
				continue
			# La altura crece con el menor de los dos estirones (nunca se
			# deforma más de la cuenta en vertical).
			opciones.append({"nombre": nombre, "giro": giro,
					"esc": Vector3(esc_local_x, minf(esc_local_x, esc_local_z), esc_local_z)})
	if opciones.is_empty():
		return false
	var op: Dictionary = opciones[_rng.randi_range(0, opciones.size() - 1)]
	var nombre_op: String = op.nombre
	var caja_op: AABB = _modelos[nombre_op]["caja"]
	var giro_op: float = op.giro
	var esc_op: Vector3 = op.esc
	var base := Basis(Vector3.UP, giro_op).scaled(esc_op)
	var centro := Vector3(caja_op.get_center().x, 0.0, caja_op.get_center().z)
	var origen := Vector3(rect.get_center().x, 0.0, rect.get_center().y) - base * centro
	origen.y = -caja_op.position.y * esc_op.y   # apoyo exacto sobre la acera
	var nodo := _instanciar_pieza(nombre_op, Transform3D(base, origen), _cont["Prefabricados"], nombre_op)
	if colisiones_edificios and not _tiene_colision(nodo):
		# Caja de colisión como hermana del edificio: así no hereda la escala no
		# uniforme (que Jolt no admite) y mide exactamente la parcela, que es
		# justo lo que ocupa el edificio.
		var alto_mundo := caja_op.size.y * esc_op.y
		var cuerpo := StaticBody3D.new()
		cuerpo.name = "Colision"
		cuerpo.position = Vector3(rect.get_center().x, alto_mundo * 0.5, rect.get_center().y)
		var forma := CollisionShape3D.new()
		var caja_col := BoxShape3D.new()
		caja_col.size = Vector3(disponible.x, alto_mundo, disponible.y)
		forma.shape = caja_col
		cuerpo.add_child(forma)
		_cont["Prefabricados"].add_child(cuerpo)
	_est["prefabs"] = int(_est.get("prefabs", 0)) + 1
	return true


## Compone un edificio con módulos del kit: perímetro de muros (2x3 m) con
## ventanas, marco y hoja de puerta, cornisa perimetral y azotea plana.
func _poner_modular(rect: Rect2) -> void:
	if _paredes.is_empty():
		return
	# El edificio ocupa TODA la parcela: así los edificios vecinos se tocan y la
	# manzana queda cerrada, sin callejones por los que colarse dentro.
	var ancho := floorf(rect.size.x / MODULO_ANCHO) * MODULO_ANCHO
	var fondo := floorf(rect.size.y / MODULO_ANCHO) * MODULO_ANCHO
	if minf(ancho, fondo) < 6.0:
		return
	var fam := _familia_aleatoria()
	# Evitamos bloques de esquina decorativos: algunos son columnas abiertas y
	# dejan un hueco oscuro en el encuentro. Los paños rectos de la misma familia
	# llegan hasta cada vértice y se encuentran allí, cerrando la fachada.
	var con_esquinas: bool = false
	var pisos := _rng.randi_range(pisos_min, pisos_max)
	if _rng.randf() < prob_torre:
		pisos += _rng.randi_range(1, 4)      # torre: rompe la línea del skyline
	var centro := Vector3(rect.get_center().x, 0.0, rect.get_center().y)
	var alto := float(pisos) * PLANTA_ALTO

	# --- Perímetro: muros de 2x3 m (y bloques de esquina, si la familia los trae)
	var modulos := _fachadas(ancho, fondo, false)
	# Portal: nunca en una celda pegada a la esquina (los marcos sobresalen del
	# plano de fachada y quedarían colgando fuera del edificio).
	var candidatos: Array[int] = []
	for i in modulos.size():
		var mp: Dictionary = modulos[i]
		var en_esquina := false
		if is_zero_approx(float(mp.giro)) or is_equal_approx(absf(float(mp.giro)), PI):
			en_esquina = mp.pos.x >= ancho * 0.5 - 1.01 or mp.pos.x <= -ancho * 0.5 + 1.01
		else:
			en_esquina = mp.pos.z >= fondo * 0.5 - 1.01 or mp.pos.z <= -fondo * 0.5 + 1.01
		if not en_esquina:
			candidatos.append(i)
	var idx_puerta := _rng.randi_range(0, modulos.size() - 1)
	if not candidatos.is_empty():
		idx_puerta = candidatos[_rng.randi_range(0, candidatos.size() - 1)]
	# Patrón de huecos fijo por edificio: las ventanas se apilan en la misma
	# vertical en todas las plantas, como en un edificio de verdad (antes se
	# sorteaban celda a celda y la fachada salía moteada).
	var desfase := _rng.randi_range(0, 1)
	var m_plano := _pieza_familia(fam, "muros")
	var m_baja := _pieza_familia(fam, "bajas", ["muros"])
	var m_alto := _pieza_familia(fam, "top", ["muros"])
	var m_ventana := _pieza_familia(fam, "ventanas", ["muros"])
	var m_esquina := _pieza_familia(fam, "esquinas", ["muros"])
	var marco := _marco_puerta(fam)
	for piso in pisos:
		var y := float(piso) * PLANTA_ALTO
		var es_top := piso == pisos - 1
		for idx in modulos.size():
			var m: Dictionary = modulos[idx]
			var pos := centro + Vector3(m.pos.x, y, m.pos.z)
			var giro: float = m.giro
			if piso == 0 and idx == idx_puerta and not marco.is_empty():
				# Portal CERRADO: el marco va en el centro de la celda (igual que
				# los muros) y el vano de 2 m se cierra con DOS hojas de 1 m, una
				# por mitad (la hoja va de -1 a 0 respecto de su origen, así que
				# las mitades van en x local 0.0 y +1.0). Con una sola hoja
				# quedaba media puerta abierta hacia el interior.
				var b := Basis(Vector3.UP, giro)
				var p_marco := pos
				_colocar(marco, _t(p_marco, giro), _cont["Modulares"])
				if not _hojas_puerta.is_empty():
					var hoja := _elegir(_hojas_puerta)
					var caja_marco: AABB = _modelos[marco]["caja"]
					var caja_hoja: AABB = _modelos[hoja]["caja"]
					# El fondo se mide con las cajas reales de los modelos: la
					# hoja queda 2 cm por detrás del frente del marco, sin
					# cruzarse con el muro ni con el propio marco.
					var z_hoja: float = caja_marco.end.z - caja_hoja.end.z - 0.02
					for mitad in 2:
						var pos_hoja: Vector3 = p_marco + b * Vector3(float(mitad), 0.0, z_hoja)
						_colocar(hoja, _t(pos_hoja, giro), _cont["Modulares"])
					prueba_portales.append(_t(p_marco, giro).origin)
					prueba_portales_dir.append(b * Vector3(0.0, 0.0, 1.0))
					_est["portales"] = int(_est.get("portales", 0)) + 1
				else:
					_colocar(m_baja, _t(pos, giro), _cont["Modulares"])
			elif piso == 0:
				_colocar(m_baja, _t(pos, giro), _cont["Modulares"])
			elif es_top:
				_colocar(m_alto, _t(pos, giro), _cont["Modulares"])
			elif (idx % 2) == desfase:
				_colocar(m_ventana, _t(pos, giro), _cont["Modulares"])
			else:
				_colocar(m_plano, _t(pos, giro), _cont["Modulares"])

		# Esquinas: bloque de 2x2 m, sólo si la familia trae piezas propias.
		# Si no, las propias paredes de los lados ya llegan hasta la esquina.
		if con_esquinas:
			for c in _esquinas_modulares(ancho, fondo, centro, y):
				_colocar(m_esquina, _t(c.pos, c.giro), _cont["Modulares"])

	# --- Cornisa perimetral (banda de 1 m rematando la fachada) ---
	if not _cornisas.is_empty():
		# Cornisa de la familia si el kit la trae; si no, la genérica del kit.
		var lista_c := _por_familia(_cornisas, fam)
		if lista_c.is_empty():
			lista_c = _cornisas
		var cornisas := _elegir(lista_c)
		var yc := alto - 1.0
		# Lados norte/sur: ancho completo (incluyen el remate de las esquinas).
		var n_c := int(round(ancho / MODULO_ANCHO))
		for k in n_c:
			var x := -ancho * 0.5 + MODULO_ANCHO * (float(k) + 0.5)
			# Mismo voladizo de 6 mm que los muros: la cornisa queda a ras del
			# frente del muro, sin caras coplanares en la esquina.
			_colocar(cornisas, _t(centro + Vector3(x, yc, fondo * 0.5 + 0.006), 0.0), _cont["Modulares"])
			_colocar(cornisas, _t(centro + Vector3(x, yc, -fondo * 0.5 - 0.006), PI), _cont["Modulares"])
		# Lados este/oeste: profundidad completa, 2 cm más afuera para no
		# encontrarse cara con cara con los tramos anteriores en las esquinas.
		var m_c := int(round(fondo / MODULO_ANCHO))
		for k in m_c:
			# La cornisa ocupa x local -2..0: ajustar origen por separado según
			# el sentido del giro, igual que en los muros laterales.
			var z_derecha := -fondo * 0.5 + MODULO_ANCHO * float(k)
			var z_izquierda := -fondo * 0.5 + MODULO_ANCHO * (float(k) + 1.0)
			_colocar(cornisas, _t(centro + Vector3(ancho * 0.5 + 0.02, yc, z_derecha), PI * 0.5), _cont["Modulares"])
			_colocar(cornisas, _t(centro + Vector3(-ancho * 0.5 - 0.02, yc, z_izquierda), -PI * 0.5), _cont["Modulares"])

	# --- Azotea: plancha de tejado a ras del último forjado ---
	_colocar_techos(centro, ancho, fondo, alto)

	# --- Mobiliario de azotea ---
	if props_en_azotea and not _aires.is_empty():
		for k in _rng.randi_range(1, 3):
			var x := centro.x + _rng.randf_range(-ancho * 0.5 + 1.5, ancho * 0.5 - 1.5)
			var z := centro.z + _rng.randf_range(-fondo * 0.5 + 1.5, fondo * 0.5 - 1.5)
			_instanciar_pieza(_elegir(_aires),
					_t(Vector3(x, alto + 0.2, z), _rng.randf_range(0.0, TAU)), _cont["Props"], "AireAcondicionado")

	# --- Colisión envolvente del edificio ---
	if colisiones_edificios:
		var cuerpo := StaticBody3D.new()
		cuerpo.name = "Edificio_modular_%d" % int(_est.get("modulares", 0))
		cuerpo.position = Vector3(centro.x, Y_ACERA + alto * 0.5, centro.z)
		var forma := CollisionShape3D.new()
		var caja_col := BoxShape3D.new()
		caja_col.size = Vector3(ancho, alto, fondo)
		forma.shape = caja_col
		cuerpo.add_child(forma)
		_cont["Modulares"].add_child(cuerpo)

	prueba_esquinas.append(centro + Vector3(ancho * 0.5, 0.0, fondo * 0.5))
	prueba_esquinas_dir.append(Vector3(0.7071068, 0.0, 0.7071068))

	# --- Relleno interior: suficientemente retraído para que no cruce el vano
	# de la puerta ni se vea desde los laterales/esquinas de la fachada, y con
	# el techo 0.5 m por debajo de la losa para no asomar por la azotea ---
	_relleno_interior(_cont["Modulares"], centro, ancho, fondo, alto - 0.5, 1.25)
	_est["modulares"] = int(_est.get("modulares", 0)) + 1


## Muros del perímetro: {pos: Vector3, giro: float}. El módulo va CENTRADO en
## su celda (el modelo ocupa x = -1..+1), así que el run cubre de esquina a
## esquina sin rendijas ni paños colgando. Con 'con_esquinas' los lados dejan
## libres las esquinas (2x2 m) para los bloques de esquina del kit.
func _fachadas(ancho: float, fondo: float, con_esquinas: bool = true) -> Array:
	var modulos: Array = []
	var libre := 2.0 * MODULO_ANCHO if con_esquinas else 0.0
	# IMPORTANTE: el módulo de muro está CENTRADO en su origen (x = -1..+1), así
	# que cada celda se rellena colocándolo en su CENTRO y los paños contiguos
	# se tocan en el borde. Antes se colocaba en el borde derecho de la celda:
	# eso dejaba 1 m sin fachada en la esquina inicial (por ahí se veía el
	# interior, los "parches negros") y 1 m de paño colgando fuera en la final,
	# además de descuadrar el portal 1 m (la puerta "cortada" con un hueco al
	# lado). Cada tramo se adelanta además unos milímetros hacia la calle para
	# que el canto del muro no quede coplanar con la fachada perpendicular y no
	# parpadee en las esquinas.
	var voladizo := 0.006       # lados norte/sur
	var voladizo_lat := 0.012   # lados este/oeste
	var n := int(round((ancho - libre) / MODULO_ANCHO))
	for k in n:
		var x := -ancho * 0.5 + libre * 0.5 + MODULO_ANCHO * (float(k) + 0.5)
		modulos.append({"pos": Vector3(x, 0.0, fondo * 0.5 + voladizo), "giro": 0.0})
		modulos.append({"pos": Vector3(x, 0.0, -fondo * 0.5 - voladizo), "giro": PI})
	var m := int(round((fondo - libre) / MODULO_ANCHO))
	for k in m:
		# Módulo centrado: el mismo centro sirve para los dos lados; el giro
		# opuesto solo cambia hacia dónde mira la cara exterior.
		var z_c := -fondo * 0.5 + libre * 0.5 + MODULO_ANCHO * (float(k) + 0.5)
		modulos.append({"pos": Vector3(ancho * 0.5 + voladizo_lat, 0.0, z_c), "giro": PI * 0.5})
		modulos.append({"pos": Vector3(-ancho * 0.5 - voladizo_lat, 0.0, z_c), "giro": -PI * 0.5})
	return modulos


## Posición y giro de los cuatro bloques de esquina (2x2x3 m). El modelo tiene
## sus caras exteriores en z = 0 y x = +1 (esquina noreste), así que cada
## cuadrante se resuelve con un giro de 90° y su origen 1 m hacia -x local.
func _esquinas_modulares(ancho: float, fondo: float, centro: Vector3, y: float) -> Array:
	var lista: Array = []
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var giro := 0.0
			if sx > 0.0 and sz < 0.0:
				giro = PI * 0.5              # noreste -> sureste
			elif sx < 0.0 and sz < 0.0:
				giro = PI                    # -> suroeste
			elif sx < 0.0 and sz > 0.0:
				giro = PI * 1.5              # -> noroeste
			var base := Basis(Vector3.UP, giro)
			var pos := centro + Vector3(sx * ancho * 0.5, y, sz * fondo * 0.5) + base * Vector3(-1.0, 0.0, 0.0)
			lista.append({"pos": pos, "giro": giro})
	return lista


## Azotea: losa propia de membrana de grava, UNA sola capa por edificio. Antes
## se usaban las planchas del kit (Roof_2x2 / Roof_4x4): a la misma cota que el
## remate del edificio peleaban entre capas y dejaban esos parches beige y gris
## con bordes irregulares.
func _colocar_techos(centro: Vector3, ancho: float, fondo: float, alto: float) -> void:
	if _tex_techo == null:
		return
	var caja := BoxMesh.new()
	caja.size = Vector3(ancho, 0.24, fondo)
	var mi := MeshInstance3D.new()
	mi.name = "Azotea"
	mi.mesh = caja
	mi.material_override = _material_azotea(ancho, fondo)
	mi.position = Vector3(centro.x, alto + 0.08, centro.z)   # cara superior en alto + 0.20
	_cont["Modulares"].add_child(mi)


## Pieza de una categoría de la familia elegida (muros / bajas / ventanas / top /
## esquinas). Si la familia no tiene nada en esa categoría se prueban las
## alternativas y, como último recurso, cualquier muro del kit: así nunca queda
## una celda de fachada sin cerrar.
func _pieza_familia(fam: String, categoria: String, alternativas: Array = []) -> String:
	var f: Dictionary = _familias.get(fam, {})
	var lista: Array = f.get(categoria, []) as Array
	if lista.is_empty():
		for alt: String in alternativas:
			var otra: Array = f.get(alt, []) as Array
			if not otra.is_empty():
				lista = otra
				break
	if lista.is_empty():
		lista = _paredes
	return _elegir(lista)


## Familia de fachada al azar entre las que tienen muros utilizables.
func _familia_aleatoria() -> String:
	var opciones: Array[String] = []
	for fam: String in _familias.keys():
		var f: Dictionary = _familias[fam]
		if not (f.get("muros", []) as Array).is_empty():
			opciones.append(String(fam))
	if opciones.is_empty():
		return ""
	return opciones[_rng.randi_range(0, opciones.size() - 1)]


## Marco de puerta del edificio. La pareja familia -> marco es fija (ladrillo
## con madera, molduras con moldura, metal con metal), así que el portal nunca
## mezcla materiales con la fachada y no cambia de marco entre llamadas.
func _marco_puerta(fam: String) -> String:
	if _marcos_puerta.is_empty():
		return ""
	var quiere := {"brick": "wooden", "trim": "trim", "metal": "metal"}
	var busca := String(quiere.get(fam, ""))
	if busca != "":
		for n in _marcos_puerta:
			if String(n).to_lower().contains(busca):
				return String(n)
	return _marcos_puerta[0]


## ¿La familia trae bloques de esquina propios (2x2x3 m)?
func _familia_con_esquinas(fam: String) -> bool:
	var f: Dictionary = _familias.get(fam, {})
	return not (f.get("esquinas", []) as Array).is_empty()


## Relleno interior retraído para cerrar el volumen sin invadir entradas ni
## quedar a la vista desde las esquinas de la fachada.
func _relleno_interior(padre: Node3D, centro: Vector3, ancho: float, fondo: float,
		alto: float, margen: float) -> void:
	var tam := Vector3(ancho - margen * 2.0, alto, fondo - margen * 2.0)
	if minf(tam.x, tam.z) < 0.5 or alto < 0.5:
		return
	if _mat_relleno == null:
		_mat_relleno = StandardMaterial3D.new()
		_mat_relleno.albedo_color = Color(0.58, 0.53, 0.45)
		_mat_relleno.roughness = 0.95
	var caja := BoxMesh.new()
	caja.size = tam
	var mi := MeshInstance3D.new()
	mi.name = "Relleno_interior"
	mi.mesh = caja
	mi.material_override = _mat_relleno
	mi.position = Vector3(centro.x, alto * 0.5, centro.z)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	padre.add_child(mi)


# =============================================================================
#  Mobiliario urbano y vegetación
# =============================================================================

## Jardinera o maceta con rotación libre y escala variable.
func _colocar_vegetacion(pos: Vector3, escala: float, base_y: float = Y_ACERA) -> void:
	if not generar_vegetacion or _vegetacion.is_empty():
		return
	var pieza := _elegir(_vegetacion)
	var caja: AABB = _modelos[pieza]["caja"]
	# Se limita la escala para que la pieza quepa en la acera de 3 m, incluso girada.
	var maxima := 1.4 / maxf(maxf(caja.size.x, caja.size.z) * 0.5, 0.001)
	var esc := clampf(escala, 0.8, minf(maxima, 1.1))
	var p := pos
	p.y = base_y - caja.position.y * esc
	_instanciar_pieza(pieza, _t(p, _rng.randf_range(0.0, TAU), esc), _cont["Vegetacion"], "Vegetacion")
	_est["vegetacion"] = int(_est.get("vegetacion", 0)) + 1


## Árbol en 3D: tronco cilíndrico y masas de hoja (esferas o conos), apoyado
## sobre el terreno, con altura, giro, inclinación y color aleatorios.
func _colocar_arbol(pos: Vector3, alto_min: float, alto_max: float) -> bool:
	if not generar_vegetacion or not usar_vegetacion_propia:
		return false
	var alto := _rng.randf_range(alto_min, alto_max)
	var grosor := _rng.randf_range(0.09, 0.14)
	if _rng.randf() < 0.3:
		# --- Conífera: tronco corto y tres conos apilados --------------------
		var alto_tronco := alto * 0.34
		_pistas_tronco.append(_matriz_tronco(pos, grosor, alto_tronco))
		var verde := _color_hoja()
		var tramos: Array = [
			[0.26, 0.42, 0.26],     # [radio, alto, arranque] en fracciones de 'alto'
			[0.20, 0.36, 0.48],
			[0.13, 0.30, 0.70],
		]
		for t: Array in tramos:
			var r := alto * float(t[0])
			var h := alto * float(t[1])
			var y0 := pos.y + alto * float(t[2])
			_pistas_cono.append(Transform3D(Basis().scaled(Vector3(r, h, r)),
					Vector3(pos.x, y0 + h * 0.5, pos.z)))
			_colores_cono.append(verde)
	else:
		# --- Frondoso: tronco alto y 3-5 masas redondeadas -------------------
		var alto_tronco2 := alto * _rng.randf_range(0.48, 0.60)
		_pistas_tronco.append(_matriz_tronco(pos, grosor, alto_tronco2))
		var centro := Vector3(pos.x, pos.y + alto * 0.70, pos.z)
		for k in _rng.randi_range(3, 5):
			var r2 := alto * _rng.randf_range(0.20, 0.28)
			var des := Vector3(_rng.randf_range(-0.16, 0.16) * alto,
					_rng.randf_range(-0.07, 0.07) * alto,
					_rng.randf_range(-0.16, 0.16) * alto)
			_pistas_esfera.append(Transform3D(Basis().scaled(Vector3(r2, r2 * 0.85, r2)),
					centro + des))
			_colores_esfera.append(_color_hoja())
	_est["arboles"] = int(_est.get("arboles", 0)) + 1
	return true


## Matriz de un tronco: cilindro unitario con la base apoyada en 'pos' y una
## inclinación leve para que no salgan todos tiesos.
func _matriz_tronco(pos: Vector3, grosor: float, alto: float) -> Transform3D:
	var eje := Vector3(_rng.randf_range(-1.0, 1.0), 0.0, _rng.randf_range(-1.0, 1.0)).normalized()
	var base := Basis(eje, deg_to_rad(_rng.randf_range(0.0, 4.0)))
	var xf := Transform3D(base.scaled(Vector3(grosor, alto, grosor)), Vector3.ZERO)
	xf.origin = pos + base * Vector3(0.0, alto * 0.5, 0.0)
	return xf


## Color de hoja: verde con variación por árbol.
func _color_hoja() -> Color:
	var oscuro := Color(0.13, 0.30, 0.11)
	var claro := Color(0.34, 0.52, 0.20)
	return oscuro.lerp(claro, _rng.randf()).lightened(_rng.randf_range(0.0, 0.05))


## Arbusto en 3D: dos o tres masas de hoja aplastadas, apoyadas en el suelo.
func _colocar_arbusto(pos: Vector3, alto_min: float, alto_max: float) -> bool:
	if not generar_vegetacion or not usar_vegetacion_propia:
		return false
	var alto := _rng.randf_range(alto_min, alto_max)
	var verde := _color_hoja()
	for k in _rng.randi_range(2, 3):
		var r := alto * _rng.randf_range(0.42, 0.58)
		var des := Vector3(_rng.randf_range(-0.30, 0.30) * alto, 0.0,
				_rng.randf_range(-0.30, 0.30) * alto)
		_pistas_esfera.append(Transform3D(Basis().scaled(Vector3(r, r * 0.78, r)),
				pos + des + Vector3(0.0, r * 0.78, 0.0)))
		_colores_esfera.append(verde.lightened(_rng.randf_range(0.0, 0.06)))
	_est["vegetacion"] = int(_est.get("vegetacion", 0)) + 1
	return true


## Vuelca toda la vegetación en tres MultiMeshInstance3D: troncos, masas
## redondas y masas cónicas, con un color por instancia. Es lo más barato de
## dibujar con cientos de árboles y, al ser geometría real, tiene volumen.
func _volcar_vegetacion() -> void:
	if _pistas_tronco.is_empty() and _pistas_esfera.is_empty() and _pistas_cono.is_empty():
		return
	var cont: Node3D = _cont["Vegetacion"]
	if _mat_tronco == null:
		_mat_tronco = StandardMaterial3D.new()
		_mat_tronco.albedo_color = Color(0.30, 0.23, 0.17)
		_mat_tronco.roughness = 1.0
	if _mat_hoja == null:
		_mat_hoja = StandardMaterial3D.new()
		_mat_hoja.albedo_color = Color(1.0, 1.0, 1.0)
		_mat_hoja.roughness = 0.9
		_mat_hoja.vertex_color_use_as_albedo = true      # color por instancia
	if not _pistas_tronco.is_empty():
		var tronco := CylinderMesh.new()
		tronco.top_radius = 0.75
		tronco.bottom_radius = 1.0
		tronco.height = 1.0
		tronco.radial_segments = 6
		tronco.rings = 1
		cont.add_child(_crear_multi(tronco, _pistas_tronco, [], _mat_tronco, "Arboles_troncos"))
	if not _pistas_esfera.is_empty():
		var esfera := SphereMesh.new()
		esfera.radius = 1.0
		esfera.height = 2.0
		esfera.radial_segments = 8
		esfera.rings = 4
		cont.add_child(_crear_multi(esfera, _pistas_esfera, _colores_esfera, _mat_hoja, "Arboles_hoja"))
	if not _pistas_cono.is_empty():
		var cono := CylinderMesh.new()
		cono.top_radius = 0.0
		cono.bottom_radius = 1.0
		cono.height = 1.0
		cono.radial_segments = 8
		cono.rings = 1
		cont.add_child(_crear_multi(cono, _pistas_cono, _colores_cono, _mat_hoja, "Arboles_pino"))


## MultiMeshInstance3D a partir de una lista de matrices (y colores opcionales).
func _crear_multi(malla: Mesh, pistas: Array[Transform3D], colores: Array[Color],
		material: Material, nombre: String) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = malla
	if not colores.is_empty():
		mm.use_colors = true
	mm.set_instance_count(pistas.size())
	for k in pistas.size():
		mm.set_instance_transform(k, pistas[k])
		if not colores.is_empty():
			mm.set_instance_color(k, colores[k])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "%s_x%d" % [nombre, pistas.size()]
	mmi.multimesh = mm
	mmi.material_override = material
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return mmi


func _generar_mobiliario() -> void:
	if not generar_props and not generar_vegetacion:
		return
	var calzada: float = _trazado.calzada
	var acera: float = _trazado.acera
	var hw: float = _trazado.hw
	var paso: float = _trazado.paso
	var ext: Vector2 = _trazado.ext
	var off: Vector2 = _trazado.off
	# Árboles de calle: uno cada 'arboles_calle' metros de acera (0 = ninguno).
	var prob_arbol := 0.0
	if usar_vegetacion_propia and generar_vegetacion and arboles_calle > 0.0:
		prob_arbol = clampf(6.0 / arboles_calle, 0.0, 1.0)

	for vertical: bool in [true, false]:
		var n_lineas: int = (manzanas_x + 1) if vertical else (manzanas_z + 1)
		var n_cruces: int = (manzanas_z + 1) if vertical else (manzanas_x + 1)
		var d0: float = off.y if vertical else off.x
		var largo: float = ext.y if vertical else ext.x
		for i in n_lineas:
			var p: float = (off.x + float(i) * paso) if vertical else (off.y + float(i) * paso)

			# --- Mobiliario y vegetación sobre las aceras ---
			for lado: float in [-1.0, 1.0]:
				var centro_lat := p + lado * (calzada * 0.5 + acera * 0.5)
				var n_slots := int(round(largo / 6.0))
				for s in n_slots:
					var c := d0 + 3.0 + 6.0 * float(s)
					var en_cruce := false
					for b in n_cruces:
						if absf(c - (d0 + paso * float(b))) < hw + 1.5:
							en_cruce = true
							break
					if en_cruce:
						continue
					var pos := Vector3(centro_lat, Y_ACERA, c) if vertical else Vector3(c, Y_ACERA, centro_lat)
					if prob_arbol > 0.0 and _rng.randf() < prob_arbol:
						# Árbol de alineación, arrimado al bordillo.
						var lat_a := centro_lat - lado * (acera * 0.5 - 0.8)
						var pos_a := Vector3(lat_a, Y_ACERA, c) if vertical else Vector3(c, Y_ACERA, lat_a)
						_colocar_arbol(pos_a, 4.5, 6.5)
					elif _rng.randf() < 0.28:
						_colocar_vegetacion(pos, _rng.randf_range(0.85, 1.05))
					elif _rng.randf() < 0.35 and generar_props and not _bolardos.is_empty():
						# Bolardos junto al bordillo, desplazados hacia la calzada.
						var lat := centro_lat - lado * (acera * 0.5 - 0.5)
						var pos_b := Vector3(lat, 0.0, c) if vertical else Vector3(c, 0.0, lat)
						_colocar_prop(_elegir(_bolardos), pos_b, true, _rng.randf_range(0.9, 1.1))

			# --- Sumideros y registros sobre la calzada ---
			if generar_props:
				for k in manzanas_z if vertical else manzanas_x:
					var ini := d0 + paso * float(k) + hw
					var fin := d0 + paso * float(k + 1) - hw
					if fin - ini < 6.0:
						continue
					for lado: float in [-1.0, 1.0]:
						if not _sumideros.is_empty() and _rng.randf() < 0.6:
							var c := _rng.randf_range(ini + 1.5, fin - 1.5)
							var lat := p + lado * (calzada * 0.5 - 0.5)
							var pos := Vector3(lat, 0.0, c) if vertical else Vector3(c, 0.0, lat)
							_colocar_prop(_elegir(_sumideros), pos, false, 1.0)
						if not _alcantarillas.is_empty() and _rng.randf() < 0.35:
							var c2 := _rng.randf_range(ini + 1.5, fin - 1.5)
							var lat2 := p + _rng.randf_range(-1.0, 1.0) * (calzada * 0.5 - 0.8)
							var pos2 := Vector3(lat2, 0.0, c2) if vertical else Vector3(c2, 0.0, lat2)
							_colocar_prop(_elegir(_alcantarillas), pos2, false, 1.0)


## Coloca un prop apoyado exactamente en su superficie (acera o calzada).
func _colocar_prop(pieza: String, pos: Vector3, en_acera: bool, escala: float) -> void:
	if pieza == "":
		return
	var caja: AABB = _modelos[pieza]["caja"]
	var p := pos
	# La pieza se apoya sobre la superficie: se compensa el mínimo de su caja.
	p.y = (Y_ACERA if en_acera else Y_CALZADA) - caja.position.y * escala
	var nodo := _instanciar_pieza(pieza, _t(p, _rng.randf_range(0.0, TAU), escala), _cont["Props"], pieza)
	if colisiones_props:
		_anadir_colision_caja(nodo, caja)
	_est["props"] = int(_est.get("props", 0)) + 1


# =============================================================================
#  Volcado de lotes (MultiMesh) y cierre
# =============================================================================

## Convierte cada lote en un MultiMeshInstance3D bajo su contenedor.
func _volcar_lotes() -> void:
	for clave in _lotes.keys():
		var pieza := String(clave)
		var lista: Array = _lotes[pieza]
		if lista.is_empty():
			continue
		var padre: Node3D = _lote_padre[pieza]
		var datos := _malla_unica(_modelos[pieza]["escena"])
		if datos.is_empty():
			# No agrupable (varias mallas): se instancian una a una.
			for xf in lista:
				_instanciar_pieza(pieza, xf, padre, pieza)
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = datos["malla"]
		mm.set_instance_count(lista.size())
		var local: Transform3D = datos["local"]
		for k in lista.size():
			mm.set_instance_transform(k, (lista[k] as Transform3D) * local)
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "%s_x%d" % [pieza, lista.size()]
		mmi.multimesh = mm
		if _es_plancha_techo(pieza):
			mmi.material_override = _material_techo(pieza)
		padre.add_child(mmi)
	_lotes.clear()
	_lote_padre.clear()


## En el editor, marca la propiedad "owner" para que los nodos se guarden.
func _marcar_owner(nodo: Node) -> void:
	if nodo == null or _vista_editor:
		return
	var raiz := get_tree().edited_scene_root
	if raiz != null and nodo != raiz:
		nodo.owner = raiz
	for c in nodo.get_children():
		_marcar_owner(c)


func _informe(ms: int) -> void:
	print("[GeneradorCiudad] ------------------------------------------------")
	print("[GeneradorCiudad] Carpeta: %s  (semilla %d)" % [_carpeta, _rng.seed])
	print("[GeneradorCiudad] Modelos escaneados: %d" % _modelos.size())
	for cat in _categorias.keys():
		var nombres: Array = _categorias[cat]
		var ordenados := PackedStringArray(nombres)
		var muestra := ", ".join(ordenados) if ordenados.size() <= 8 else "%s ... (%d)" % [", ".join(ordenados.slice(0, 8)), ordenados.size()]
		print("[GeneradorCiudad]   %-14s %3d  | %s" % [cat, ordenados.size(), muestra])
	var calzada: float = _trazado.calzada
	var acera: float = _trazado.acera
	var manzana: float = _trazado.manzana
	print("[GeneradorCiudad] Trama: %dx%d manzanas de %.0f m | calle %.0f m (calzada %.0f + aceras %.0f/%.0f)"
			% [manzanas_x, manzanas_z, manzana, calzada + 2.0 * acera, calzada, acera, acera])
	print("[GeneradorCiudad] Suelos: %d | tramos de calle: %d | marcas: %d"
			% [_est.get("suelos", 0), _est.get("tramos", 0), _est.get("marcas", 0)])
	print("[GeneradorCiudad] Parques: %d | árboles: %d | arbustos y jardineras: %d"
			% [_est.get("parques", 0), _est.get("arboles", 0), _est.get("vegetacion", 0)])
	print("[GeneradorCiudad] Edificios: %d (%d prefabricados + %d modulares) | props: %d | vegetación: %d"
			% [int(_est.get("prefabs", 0)) + int(_est.get("modulares", 0)), _est.get("prefabs", 0),
			_est.get("modulares", 0), _est.get("props", 0), _est.get("vegetacion", 0)])
	print("[GeneradorCiudad] Portales: %d | puertas colocadas: %d"
			% [_est.get("portales", 0), prueba_portales.size()])
	# Cierre de fachadas: si aparecen piezas vacías sería que alguna celda se
	# quedó sin muro (un hueco por el que se vería el interior del edificio).
	var familias := ""
	for fam: String in _familias.keys():
		var f: Dictionary = _familias[fam]
		familias += "%s%d " % [fam.substr(0, 1).to_upper(), (f.get("muros", []) as Array).size()]
	var vacias := int(_est.get("piezas_vacias", 0))
	print("[GeneradorCiudad] Fachadas: familias %s| piezas sin modelo: %d %s"
			% [familias, vacias, "OK (todo cerrado)" if vacias == 0 else "OJO: hay huecos"])
	var multi := 0
	var sueltos := 0
	var raiz := get_node_or_null(NODO_CIUDAD)
	if raiz != null:
		var conteo := _contar_nodos(raiz, [0], [0])
		multi = conteo[0]
		sueltos = conteo[1]
	print("[GeneradorCiudad] MultiMeshInstance3D: %d | nodos instanciados: %d | tiempo: %.2f s"
			% [multi, sueltos, float(ms) / 1000.0])
	print("[GeneradorCiudad] Contenedores en nodo '%s'." % NODO_CIUDAD)


## Cuenta [MultiMeshInstance3D, piezas instanciadas] bajo un nodo.
func _contar_nodos(nodo: Node, multi: Array, sueltos: Array) -> Array:
	if nodo is MultiMeshInstance3D:
		multi[0] = int(multi[0]) + 1
	elif _modelos.has(nodo.name):
		sueltos[0] = int(sueltos[0]) + 1
	for c in nodo.get_children():
		_contar_nodos(c, multi, sueltos)
	return [int(multi[0]), int(sueltos[0])]