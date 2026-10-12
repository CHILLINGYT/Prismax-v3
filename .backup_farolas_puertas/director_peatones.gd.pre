class_name DirectorPeatones
extends Node3D

## =============================================================================
##  DIRECTOR DE PEATONES — la ciudad habitada
## =============================================================================
##  Coloca ciudadanos REALES (NPC_Citizen.tscn + modelos PSX de NPCs/Characters)
##  sobre la RED PEATONAL del mapa generado y les reparte la vida cotidiana:
##
##    · pasear por las veredas (nunca por la calzada) y cruzar por los pasos
##      de peatones pintados que el generador ha registrado,
##    · pasear por plazas y parques, sentarse en sus bancos y seguir,
##    · recorrer el paseo costero y la arena y, durante el DÍA, tumbarse en una
##      reposera libre y tomar el sol (llega, se tumba, espera y se levanta),
##    · al acercarse la noche, retirada escalonada: se levantan todos ANTES de
##      que el ciclo día/noche entre en el período nocturno.
##
##  El estado del mundo es el del juego: se lee `_fase` del `CicloDiaNoche`
##  (0.25 amanecer · 0.5 mediodía · 0.75 atardecer · 0/1 medianoche) y esta
##  misma fase es la que usan las farolas y las ventanas encendidas, así que no
##  hay ningún reloj paralelo que pueda desincronizarse.
##
##  Configuración: TODO se ajusta desde el generador de ciudad (grupo "7.
##  Peatones") que es quien crea este nodo; aquí los exports son el respaldo.
## =============================================================================

# --- Ventanas del ciclo (en fase del CicloDiaNoche) ---------------------------
const SOL_DESDE := 0.30       ## desde aquí (amanecer 0.25) puede empezar a tomarse el sol
const SOL_LLENO := 0.38       ## a partir de aquí la entrada de bañistas es plena
const SOL_HASTA := 0.55       ## desde aquí no se aceptan más "tomar el sol" (retirada)
const RETIRADA_FIN := 0.68    ## hora tope: a esta fase ya no queda NADIE tomando el sol
const NOCHE := 0.70           ## fase a partir de la cual es de noche (también < 0.22)
const NOCHE_ABS := 0.68

@export_group("Cantidad")
## Ciudadanos totales que recorren la ciudad.
@export_range(0, 200) var cantidad_total := 52
## Fracción de ciudadanos cuyo destino son plazas y parques (los demás, la ciudad).
@export_range(0.0, 1.0) var proporcion_plaza := 0.28
## Peatones del frente costero (paseo, arena; algunos se tumban en reposeras).
@export_range(0, 60) var cantidad_playa := 12
## Asientos de banco que como mucho están ocupados a la vez (los bancos quedan libres).
@export_range(0, 100) var max_sentados := 14
## Reposeras que como mucho están ocupadas a la vez (siempre quedan reposeras vacías).
@export_range(0, 100) var max_tumbados := 9
## Descanso mínimo y máximo en un banco (segundos).
@export var duracion_banco := Vector2(25.0, 110.0)
## Descanso mínimo y máximo tumbado al sol (segundos).
@export var duracion_sol := Vector2(70.0, 260.0)
## Separación mínima entre ciudadanos al aparecer (metros).
@export var separacion_inicial := 4.5
## Radio alrededor del punto de aparición del jugador donde no nace nadie (metros).
@export var radio_inicio_jugador := 28.0
## Evitación local: radio en el que se tienen en cuenta otros peatones y el mobiliario.
@export var radio_evitacion := 3.0
## Distancia a la que un peatón de delante obliga a frenar el paso.
@export var frenado_delante := 1.15

@export_group("Rendimiento")
@export var intervaloLOD := 1.0         ## cada cuánto se reparte el nivel de actividad
@export var distancia_media := 30.0     ## NEAR por debajo de esta distancia al jugador
@export var distancia_lejana := 70.0    ## FAR por encima de esta distancia
## Auditoría de seguridad: comprueba cada segundo que nadie esté sobre el asfalto
## fuera de un paso de peatones y lo deja en el registro. Se apaga para jugar.
@export var auditoria := false

var red: RedPeatonal = null
var peatones: Array[NPCCitizen] = []
var _ciclo: Node = null
var _zona_jugador: Node3D = null
var _modelos: Array[PackedScene] = []

# --- Reservas --------------------------------------------------------------
var _asientos: Array[Dictionary] = []      ## {pos, ini, yaw, libre}
var _reposeras: Array[Dictionary] = []     ## {pos, ini, yaw, tilt, libre}
var _reservas: Dictionary = {}             ## NPCCitizen -> {"tipo", "indice"}
var _limites := {}                         ## NPCCitizen -> momento (ticks) para levantarse
var _bloqueo_desde := {}                   ## NPCCitizen -> momento en que empezó a esperar a otro

# --- Evitación compartida (mobiliario) --------------------------------------
## Obstáculos sólidos del mapa (troncos, canteros, bancos, reposeras, postes de sombrilla)
## como círculos en planta: {x, z, r}. La evitación local los consulta con una rejilla
## espacial, así que cada peatón mira sólo lo que tiene cerca (no hay sensores por NPC).
var _obstaculos: Array = []
var _rejilla: Dictionary = {}              ## Vector2i -> Array[int] (índices de _obstaculos)
const CELDA := 2.0
# --- Sectores de población ---------------------------------------------------
## Ciudadanos que han nacido en cada sector (para repartir sin acumulaciones).
var _sector_censo: Dictionary = {}
var _nodos_por_sector: Dictionary = {}     ## clave de sector -> Array[int] de vértices

# --- Reloj -----------------------------------------------------------------
var _t_lod := 0.0
var _t_avisos := 0.0
var _t_ciclo := 0.0
var _t_auditoria := 0.0
var _fase := 0.4
var _retirada := false
var _sol_aceptado := 1.0
var _violaciones := 0
var _cursor_lod := 0
var _rng := RandomNumberGenerator.new()
var _instalado := false
var _despejado := false        ## ya se despejó el entorno del inicio del jugador
var _auditorias := 0


# =============================================================================
#  Instalación (la llama el generador de ciudad)
# =============================================================================

## Recibe los datos del mapa generado: trazado, plazas, parques, cruces pintados,
## cadenas del paseo y de la arena, bancos y reposeras reales. Monta la red,
## reparte ciudadanos y los engancha al ciclo día/noche del juego.
func instalar(datos: Dictionary) -> void:
	_rng.randomize()
	red = RedPeatonal.new()
	red.construir(datos)
	_preparar_asientos(datos)
	_preparar_reposeras(datos)
	_preparar_obstaculos(datos)
	_preparar_sectores()
	_cargar_modelos()
	_buscar_ciclo()
	_sembrar(datos)
	_instalado = true
	var res := red.resumen()
	print("[Peatones] red: %d vértices %s | %d ciudadanos (playa %d) | bancos %d asientos libres %d | reposeras %d libres %d | obstáculos %d" % [
		res["nodos"], res["por_tipo"], peatones.size(), _cuantos_perfil("costa"),
		_asientos.size(), max_sentados, _reposeras.size(), max_tumbados, _obstaculos.size()])
	print("[Peatones] reparto por sectores: ", _sector_censo)


func _preparar_asientos(datos: Dictionary) -> void:
	_asientos.clear()
	for banco: Dictionary in datos.get("bancos", []):
		var pos: Vector3 = banco["pos"]
		var giro := float(banco["giro"])
		var base := Basis(Vector3.UP, giro)
		# Dos plazas por banco (izquierda y derecha). Las medidas salen de la pose real del clip
		# "sit_idle" horneado para ESTOS modelos (cadera del clip a 0,590 m de alto y 0,278 m por
		# detrás del origen del ciudadano): con el banco mirando a −Z, la cadera queda a
		# +0,101 m del centro del asiento (8 cm por delante del respaldo) y 8 cm sobre la tabla,
		# que es donde apoya la pelvis de una persona sentada.
		for sx: float in [-0.5, 0.5]:
			var p := pos + base * Vector3(sx, 0.0, -0.177)
			_asientos.append({
				"pos": Vector3(p.x, pos.y - 0.045, p.z),
				"yaw": giro + PI,
				"libre": true,
			})


func _preparar_reposeras(datos: Dictionary) -> void:
	_reposeras.clear()
	for lug: Dictionary in datos.get("reposeras", []):
		# Sólo las tumbadas (20°): en las muy reclinadas (40°) el respaldo es demasiado
		# vertical para la pose de tumbado de los clips (se ve atravesado), así que no
		# se ofrecen como cama: quedan libres.
		if int(lug.get("variante", 0)) != 0:
			continue
		var pos: Vector3 = lug["pos"]
		var yaw := float(lug["yaw"])
		var base := Basis(Vector3.UP, yaw)
		# Cuerpo tumbado sobre el lecho: el clip acaba con la cadera a 0,112 m de alto y 0,184 m por
		# detrás del origen (medido sobre la pose horneada para estos modelos). Con el ancla de
		# abajo la cadera cae en (y +0,489 · z −0,065) del origen de la reposera: sobre la lona
		# (0,363) y justo donde empieza el lecho, con la cabeza en el cabezal y una inclinación
		# suave de 5° que la acompaña.
		var fin := pos + base * Vector3(0.0, 0.377, 0.119)
		var ini := pos + base * Vector3(0.0, 0.02, 1.918)
		_reposeras.append({
			"pos": fin,
			"ini": ini,
			"yaw": yaw,
			"tilt": deg_to_rad(5.0),
			"libre": true,
		})


## Prepara la rejilla espacial de obstáculos sólidos (mobiliario y vegetación) que usa la
## evitación local. Los círculos en planta ya vienen calculados del generador de ciudad
## (troncos, canteros, bancos, reposeras y postes de sombrilla): así ningún peatón necesita
## sensores propios, basta con mirar las celdas que tiene alrededor.
func _preparar_obstaculos(datos: Dictionary) -> void:
	_obstaculos.clear()
	_rejilla.clear()
	for o: Dictionary in datos.get("mobiliario", []):
		var r := float(o.get("r", 0.5))
		if r <= 0.0:
			continue
		_obstaculos.append({"x": float(o.get("x", 0.0)), "z": float(o.get("z", 0.0)), "r": r})
		var c := _celda(float(o.get("x", 0.0)), float(o.get("z", 0.0)))
		if not _rejilla.has(c):
			_rejilla[c] = []
		(_rejilla[c] as Array).append(_obstaculos.size() - 1)


func _celda(x: float, z: float) -> Vector2i:
	return Vector2i(floori(x / CELDA), floori(z / CELDA))


## Empuje lateral (en metros de apartado) para no meterse en el mobiliario que se tiene
## delante. Recorre sólo las celdas de alrededor del peatón: es barato y vale para todos.
func _empuje_mobiliario(p: Vector3, adelante: Vector3, lateral: Vector3, lado_pref: float) -> float:
	var c := _celda(p.x, p.z)
	var n := int(ceil(radio_evitacion / CELDA))
	var empuje := 0.0
	for dx in range(-n, n + 1):
		for dz in range(-n, n + 1):
			var celda := Vector2i(c.x + dx, c.y + dz)
			if not _rejilla.has(celda):
				continue
			for idx: int in (_rejilla[celda] as Array):
				var o: Dictionary = _obstaculos[idx]
				var relx := float(o["x"]) - p.x
				var relz := float(o["z"]) - p.z
				var d := sqrt(relx * relx + relz * relz)
				var libre := d - float(o["r"]) - 0.35      # 0,35 m = radio del cuerpo del peatón
				if libre > radio_evitacion:
					continue
				if relx * adelante.x + relz * adelante.z < -0.35:
					continue                               # lo tiene detrás: no molesta
				var lado := relx * lateral.x + relz * lateral.z
				var fuerza := clampf(1.0 - maxf(libre, 0.0) / maxf(radio_evitacion, 0.01), 0.0, 1.0)
				empuje += (signf(lado) if absf(lado) > 0.05 else lado_pref) * fuerza
	return clampf(empuje, -1.0, 1.0)


## Reparte los vértices de la red en sectores de población: rejilla 3x3 sobre el núcleo
## urbano, un sector propio para la franja costera (paseo y arena) y un sector por plaza o
## parque. Los ciudadanos nacen en los sectores menos poblados de su perfil, así que la
## gente queda repartida por todo el mapa y no se apila en un mismo sitio.
func _preparar_sectores() -> void:
	_nodos_por_sector.clear()
	_sector_censo.clear()
	var urbanos: Array[int] = []
	var costa: Array[int] = []
	for i in red.nodos.size():
		var t := red.tipo(i)
		if t == "paseo" or t == "arena":
			costa.append(i)
		elif t == "acera":
			urbanos.append(i)
	if not urbanos.is_empty():
		var x0 := INF
		var x1 := -INF
		var z0 := INF
		var z1 := -INF
		for i: int in urbanos:
			var p := red.pos(i)
			x0 = minf(x0, p.x)
			x1 = maxf(x1, p.x)
			z0 = minf(z0, p.z)
			z1 = maxf(z1, p.z)
		for i2: int in urbanos:
			var p2 := red.pos(i2)
			var sx := clampi(int((p2.x - x0) / maxf(x1 - x0, 1.0) * 3.0), 0, 2)
			var sz := clampi(int((p2.z - z0) / maxf(z1 - z0, 1.0) * 3.0), 0, 2)
			_apuntar_sector("B%d%d" % [sx, sz], i2)
	if not costa.is_empty():
		_nodos_por_sector["costa"] = costa
	for i3 in red.nodos.size():
		var t3 := red.tipo(i3)
		if t3 == "plaza" or t3 == "parque":
			var p3 := red.pos(i3)
			_apuntar_sector("P%d_%d" % [int(round(p3.x / 24.0)), int(round(p3.z / 24.0))], i3)
	for clave: String in _nodos_por_sector:
		_sector_censo[clave] = 0


func _apuntar_sector(clave: String, idx: int) -> void:
	if not _nodos_por_sector.has(clave):
		_nodos_por_sector[clave] = []
	(_nodos_por_sector[clave] as Array).append(idx)


## Vértices candidatos para un perfil, agrupados por sector.
func _candidatos_por_perfil(perfil_buscado: String) -> Dictionary:
	var grupos := {}
	for clave: String in _nodos_por_sector:
		var filtrados: Array = []
		for i: int in (_nodos_por_sector[clave] as Array):
			var t := red.tipo(i)
			var vale := false
			match perfil_buscado:
				"costa": vale = t == "paseo" or t == "arena"
				"plaza": vale = t == "plaza" or t == "parque"
				_: vale = t == "acera"
			if vale:
				filtrados.append(i)
		if not filtrados.is_empty():
			grupos[clave] = filtrados
	return grupos


## Los sectores menos poblados del perfil (hasta 3): entre ellos se sortea cada aparición.
func _sectores_menos_poblados(grupos: Dictionary) -> Array:
	var claves: Array = grupos.keys()
	claves.sort_custom(func(a: String, b: String) -> bool:
		return int(_sector_censo.get(a, 0)) < int(_sector_censo.get(b, 0)))
	return claves.slice(0, mini(3, claves.size()))


## ¿Cae en el entorno del punto de aparición del jugador? Ahí no nace nadie: no se vería un
## corrillo justo delante de la cámara al empezar la partida.
func _cerca_del_inicio_jugador(p: Vector3) -> bool:
	if _zona_jugador == null or not is_instance_valid(_zona_jugador):
		_zona_jugador = get_tree().get_first_node_in_group("player") as Node3D
		if _zona_jugador == null:
			return false
	return Vector2(p.x, p.z).distance_to(Vector2(_zona_jugador.global_position.x,
			_zona_jugador.global_position.z)) < radio_inicio_jugador


## Modelos de los ciudadanos: personajes de MIXAMO. Viven en "res://modelos 3d npcs/" (dentro del
## proyecto, ya importados con sus texturas). Se conservan los modelos PSX antiguos como RESPALDO:
## si un Mixamo no cargara, se usa el paquete anterior en vez de dejar la ciudad sin gente.
const DIR_MIXAMO := "res://modelos 3d npcs/"
## Orden de carga (variedad: 4 hombres y 3 mujeres).
const MODELOS_MIXAMO: Array[String] = ["Ch01_nonPBR.fbx", "Ch02_nonPBR.fbx", "Ch12_nonPBR.fbx",
		"Ch13_nonPBR.fbx", "Ch17_nonPBR.fbx", "Ch26_nonPBR.fbx", "Ch33_nonPBR.fbx"]
## Repertorio de clips de cada personaje (idle/walk/jog/giro son distintos por sexo).
## Comprobado en captura de la parrilla de modelos (ver informe).
const MIXAMO_SEXO := {
	"Ch01_nonPBR.fbx": "male",
	"Ch02_nonPBR.fbx": "female",
	"Ch12_nonPBR.fbx": "female",
	"Ch13_nonPBR.fbx": "female",
	"Ch17_nonPBR.fbx": "male",
	"Ch26_nonPBR.fbx": "female",
	"Ch33_nonPBR.fbx": "male",
}
## Sexo de cada modelo cargado, en el mismo orden que `_modelos` (para el sembrado).
var _sexos: Array[String] = []


func _cargar_modelos() -> void:
	_modelos.clear()
	_sexos.clear()
	var fallos: Array[String] = []
	for f: String in MODELOS_MIXAMO:
		var res: Resource = load(DIR_MIXAMO + f)
		if res is PackedScene:
			_modelos.append(res)
			_sexos.append(String(MIXAMO_SEXO.get(f, "male")))
		else:
			fallos.append(f)
	if not fallos.is_empty():
		push_warning("[Peatones] no se pudieron cargar %d modelos de Mixamo: %s" % [fallos.size(), str(fallos)])
	print("[Peatones] modelos Mixamo cargados: %d%s" % [_modelos.size(),
			"" if fallos.is_empty() else " (fallos: %s)" % str(fallos)])
	if _modelos.is_empty():
		print("[Peatones] ningún modelo nuevo disponible: se usa el paquete PSX de respaldo")
		_cargar_modelos_psx()


func _cargar_modelos_psx() -> void:
	var carpetas: Array = [
		["res://NPCs/Characters/PSX/Male/", "male"],
		["res://NPCs/Characters/PSX/Female/", "female"],
	]
	# Modelos con el rig en una pose de reposo NO estándar: la librería compartida de clips se
	# hornea alineando la DIRECCIÓN de cada hueso con el reposo del modelo de referencia, y en
	# estos el resultado es visiblemente incorrecto (se midió: andan de LADO, con el cuerpo a unos
	# 100° del rumbo y la espalda encorvada). Se descartan en vez de dejar peatones rotos.
	# Medición: sonda _medir_modelos (columna "pies" ~100° frente a ~13° del resto del paquete).
	var excluidos: Array = ["Character_Female_01.fbx",   # sin textura en el paquete
			"Character_Male_33.fbx", "Character_Male_34.fbx",
			"Character_Male_35.fbx", "Character_Male_36.fbx", "Character_Sheriff_N.fbx"]
	for par: Array in carpetas:
		var dir: String = par[0]
		var sexo: String = par[1]
		var archivos := DirAccess.get_files_at(dir)
		var nombres: Array[String] = []
		for f in archivos:
			if f.ends_with(".fbx") and not excluidos.has(f):
				nombres.append(f)
		nombres.sort()
		for f in nombres:
			var res: Resource = load(dir + f)
			if res is PackedScene:
				_modelos.append(res)
				_sexos.append(sexo)
	print("[Peatones] modelos PSX de respaldo cargados: %d" % _modelos.size())


## Sexo del modelo en la posición `indice` de `_modelos` (para elegir el repertorio de clips).
func sexo_de(indice: int) -> String:
	return _sexos[indice] if indice >= 0 and indice < _sexos.size() else "male"


func _buscar_ciclo() -> void:
	_ciclo = null
	var pila: Array[Node] = [get_tree().root]
	while not pila.is_empty():
		var n: Node = pila.pop_back()
		if n.get_script() != null and String(n.get_script().resource_path).ends_with("ciclo_dia_noche.gd"):
			_ciclo = n
			break
		for c in n.get_children():
			pila.append(c)
	if _ciclo == null:
		push_warning("[Peatones] no hay CicloDiaNoche: se asume de día")


# =============================================================================
#  Siembra de ciudadanos
# =============================================================================

func _sembrar(_datos: Dictionary) -> int:
	var escena: PackedScene = load("res://NPCs/Scenes/NPC_Citizen.tscn")
	if escena == null or red == null:
		return 0
	var nuevos := 0
	var usados: Array[Vector2] = []
	# Los candidatos se agrupan por sector: cada ciudadano nace en uno de los tres sectores
	# menos poblados de su perfil, así queda gente repartida por todo el mapa.
	var grupos := {
		"costa": _candidatos_por_perfil("costa"),
		"plaza": _candidatos_por_perfil("plaza"),
		"paseo": _candidatos_por_perfil("paseo"),
	}
	for i in cantidad_total:
		var perfil := "paseo"
		if i < cantidad_playa:
			perfil = "costa"
		elif _rng.randf() < proporcion_plaza:
			perfil = "plaza"
		var por_sector: Dictionary = grupos[perfil]
		if por_sector.is_empty():
			por_sector = grupos["paseo"]
			if por_sector.is_empty():
				continue
		var sectores := _sectores_menos_poblados(por_sector)
		if sectores.is_empty():
			continue
		var clave := String(sectores[_rng.randi() % sectores.size()])
		var candidatos: Array = por_sector[clave]
		var punto := _punto_libre(candidatos, usados)
		if punto == Vector3.INF:
			continue
		var c := escena.instantiate() as NPCCitizen
		if c == null:
			continue
		var idx_modelo := (_rng.randi() % _modelos.size()) if not _modelos.is_empty() else -1
		c.model_scene = _modelos[idx_modelo] if idx_modelo >= 0 else null
		c.body_type = sexo_de(idx_modelo)
		c.position = punto
		c.rotation.y = _rng.randf_range(0.0, TAU)
		# La franja costera camina por el paseo y, de día, también por la arena; la mayoría
		# de ellos puede tumbarse en una reposera. Los de ciudad y plaza usan bancos.
		var recostarse := perfil == "costa" and _rng.randf() < 0.7
		var sentarse := perfil != "costa" and _rng.randf() < 0.62
		add_child(c)
		c.activar_red(red, self, perfil, sentarse, recostarse)
		peatones.append(c)
		usados.append(Vector2(punto.x, punto.z))
		_sector_censo[clave] = int(_sector_censo.get(clave, 0)) + 1
		nuevos += 1
	return nuevos


## Punto de aparición sobre la red: intenta hasta 24 veces separado del resto (y fuera del
## entorno del jugador, para que no aparezca un corrillo delante de la cámara al empezar).
func _punto_libre(candidatos: Array, usados: Array[Vector2]) -> Vector3:
	for _intento in 24:
		var idx: int = candidatos[_rng.randi() % candidatos.size()]
		var p: Vector3 = red.pos(idx)
		if _cerca_del_inicio_jugador(p):
			continue
		var v := Vector2(p.x, p.z)
		var choque := false
		for u: Vector2 in usados:
			if u.distance_to(v) < separacion_inicial:
				choque = true
				break
		if not choque:
			return Vector3(p.x, p.y + 0.05, p.z)
	return Vector3.INF


func _cuantos_perfil(p: String) -> int:
	var n := 0
	for c in peatones:
		if is_instance_valid(c) and c.perfil == p:
			n += 1
	return n


# =============================================================================
#  Actividades: bancos y reposeras (reservas)
# =============================================================================

## El ciudadano pregunta qué hacer. Devuelve {} para pasear, o la orden con el
## asiento/reposera reservada (nunca la misma plaza para dos personas).
func pedir_actividad(c: NPCCitizen) -> Dictionary:
	if c.puede_recostarse and _puede_tomar_sol() and _libres(_reposeras) > 0 \
			and _rng.randf() < 0.62:
		var ocupadas := _count_libres_false(_reposeras)
		if ocupadas < max_tumbados:
			var idx := _elegir_agujero(_reposeras, c.global_position, 5)
			if idx >= 0:
				var r: Dictionary = _reposeras[idx]
				_reposeras[idx]["libre"] = false
				_reservas[c] = {"tipo": "reposera", "indice": idx}
				return {
					"tipo": "reposera",
					"punto": r["pos"],
					"punto_ini": r["ini"],
					"yaw": r["yaw"],
					"tilt": r["tilt"],
					"ref": idx,
					"espera": _rng.randf_range(duracion_sol.x, duracion_sol.y),
				}
	if c.puede_sentarse and _count_libres_false(_asientos) < max_sentados:
		var idx2 := _elegir_agujero(_asientos, c.global_position, 6)
		if idx2 >= 0:
			var a: Dictionary = _asientos[idx2]
			_asientos[idx2]["libre"] = false
			_reservas[c] = {"tipo": "banco", "indice": idx2}
			return {
				"tipo": "banco",
				"punto": a["pos"],
				"yaw": a["yaw"],
				"ref": idx2,
				"espera": _rng.randf_range(duracion_banco.x, duracion_banco.y),
			}
	return {}


## Suelta la reserva que tenga este ciudadano (al levantarse, atascarse o cancelar).
func liberar(c: NPCCitizen) -> void:
	if not _reservas.has(c):
		return
	var r: Dictionary = _reservas[c]
	_reservas.erase(c)
	var idx := int(r["indice"])
	if String(r["tipo"]) == "reposera":
		if idx >= 0 and idx < _reposeras.size():
			_reposeras[idx]["libre"] = true
	else:
		if idx >= 0 and idx < _asientos.size():
			_asientos[idx]["libre"] = true


func _libres(lista: Array) -> int:
	return lista.size() - _count_libres_false(lista)


func _count_libres_false(lista: Array) -> int:
	var n := 0
	for e: Dictionary in lista:
		if not bool(e["libre"]):
			n += 1
	return n


## Uno de los `k` huecos libres más cercanos al ciudadano (para no cruzar la ciudad).
func _elegir_agujero(lista: Array, desde: Vector3, k: int) -> int:
	var libres: Array = []
	for i in lista.size():
		if bool(lista[i]["libre"]):
			var p: Vector3 = lista[i]["pos"]
			libres.append({"i": i, "d": Vector2(p.x, p.z).distance_to(Vector2(desde.x, desde.z))})
	if libres.is_empty():
		return -1
	libres.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["d"]) < float(b["d"]))
	var corte: int = mini(k, libres.size())
	return int(libres[_rng.randi() % corte]["i"])


# =============================================================================
#  Ciclo día/noche y retirada de la playa
# =============================================================================

## ¿Se puede TOMAR EL SOL ahora? (sale de la fase real del ciclo: sube al
## amanecer, se corta a media tarde y de noche no hay nada)
func _puede_tomar_sol() -> bool:
	if _fase >= SOL_HASTA or _fase <= SOL_DESDE:
		return false
	_sol_aceptado = clampf((_fase - SOL_DESDE) / (SOL_LLENO - SOL_DESDE), 0.0, 1.0)
	return _rng.randf() < _sol_aceptado


func es_noche() -> bool:
	return _fase >= NOCHE_ABS or _fase <= 0.22


func hay_luz() -> bool:
	return not es_noche()


func _leer_fase() -> void:
	if _ciclo == null:
		_fase = 0.4
		return
	_fase = float(_ciclo.get("_fase"))


func _gestionar_ciclo() -> void:
	_leer_fase()
	var en_retirada := _fase >= SOL_HASTA and _fase < RETIRADA_FIN
	var nocturno := es_noche()
	# La arena se cierra de noche: los costeros sólo usan el paseo.
	for c in peatones:
		if is_instance_valid(c):
			c.puede_arena = not nocturno
	if en_retirada and not _retirada:
		_retirada = true
		_repartir_limites()
	elif not en_retirada:
		_retirada = false
		_limites.clear()
	if nocturno:
		# Regla absoluta: de noche NO queda nadie tumbado al sol.
		for c in peatones:
			if is_instance_valid(c) and c.en_postura() and c.postura_actual() == "recostarse":
				c.levantar_ya()
		_limites.clear()
	elif _retirada:
		var ahora := Time.get_ticks_msec() * 0.001
		for c in _limites.keys():
			if not is_instance_valid(c):
				continue
			if ahora >= float(_limites[c]):
				if c.en_postura() and c.postura_actual() == "recostarse":
					c.levantar_ya()
				_limites.erase(c)


## Reparte el momento de levantarse de cada bañista a lo largo de la ventana que
## queda hasta RETIRADA_FIN, para que la retirada sea escalonada pero termine a tiempo.
func _repartir_limites() -> void:
	var duracion_ciclo := _duracion_ciclo()
	var restante := (RETIRADA_FIN - _fase) * duracion_ciclo
	var ahora := Time.get_ticks_msec() * 0.001
	for c in peatones:
		if not is_instance_valid(c):
			continue
		if c.en_postura() and c.postura_actual() == "recostarse":
			_limites[c] = ahora + _rng.randf_range(0.5, maxf(restante - 4.0, 2.0))


func _duracion_ciclo() -> float:
	if _ciclo == null:
		return 1800.0
	var dia := float(_ciclo.get("duracion_dia_segundos"))
	var noche := float(_ciclo.get("duracion_noche_segundos"))
	return maxf(dia + noche, 60.0)


# =============================================================================
#  Niveles de actividad y avisos entre peatones
# =============================================================================

func _repasar_lod() -> void:
	if peatones.is_empty():
		return
	if _zona_jugador == null or not is_instance_valid(_zona_jugador):
		_zona_jugador = get_tree().get_first_node_in_group("player") as Node3D
	var rebanada := maxi(1, ceili(peatones.size() / 4.0))
	for i in rebanada:
		_cursor_lod = (_cursor_lod + 1) % peatones.size()
		var c := peatones[_cursor_lod]
		if not is_instance_valid(c):
			continue
		var d := 0.0 if _zona_jugador == null else c.global_position.distance_to(_zona_jugador.global_position)
		var nivel := NPCCitizen.Activity.NEAR
		if d > distancia_lejana:
			nivel = NPCCitizen.Activity.FAR
		elif d > distancia_media:
			nivel = NPCCitizen.Activity.MID
		c.set_activity(nivel)


## Evitación compartida: en UNA pasada cada 0,2 s el director mira quién tiene delante cada
## peatón que circula (otros peatones y el mobiliario sólido) y le pide un apartado lateral,
## un frenado o una espera corta. No hay sensores por personaje, y todo lo que se pide queda
## DENTRO de la superficie de su tramo: la red manda; si no hay sitio seguro, el peatón
## espera o recalcula (nunca se sale a la calzada para esquivar).
func _avisar_peatones() -> void:
	var n := peatones.size()
	var ahora := Time.get_ticks_msec() * 0.001
	for i in n:
		var a := peatones[i]
		if not is_instance_valid(a) or not _circula(a):
			continue
		var pa := a.global_position
		var adelante := Vector3(sin(a.rotation.y), 0.0, cos(a.rotation.y))
		var lateral := Vector3(adelante.z, 0.0, -adelante.x)
		var desvio := 0.0
		var factor := 1.0
		var bloqueado := false
		for j in n:
			if i == j:
				continue
			var b := peatones[j]
			if not is_instance_valid(b):
				continue
			var rel := b.global_position - pa
			rel.y = 0.0
			var d := rel.length()
			if d > radio_evitacion or d < 0.001:
				continue
			var de_frente := rel.dot(adelante)
			if de_frente < -0.15:
				continue                       # va por detrás: no molesta
			var de_lado := rel.dot(lateral)
			var lado := signf(de_lado) if absf(de_lado) > 0.05 else a.lado_preferido()
			# Apartado suave y proporcional: cada peatón con SU medida y SU lado preferido,
			# así dos que se cruzan no eligen siempre lo mismo ni se empujan de frente.
			if absf(de_lado) < 1.0:
				desvio += lado * a.apartado_pref() * (1.0 - d / radio_evitacion)
			# Alguien justo delante: se frena un poco y, si es un enfrentamiento entre dos
			# que van andando, cede SÓLO UNO (desempate estable por índice) y por poco tiempo.
			var circula_b := b.state == NPCCitizen.State.WALK or b.state == NPCCitizen.State.PAUSE
			if de_frente > 0.0 and d < frenado_delante and absf(de_lado) < 0.5:
				if circula_b:
					factor = minf(factor, 0.6)
					if d < 0.6 and absf(de_lado) < 0.35 and i < j:
						bloqueado = true
				else:
					# Gente sentada, tumbada o parada: NO se espera, se RODEA. Son como
					# mobiliario: si se esperase a que se aparten, nadie avanzaría nunca.
					desvio += lado * (a.apartado_pref() + 0.25)
		# Mobiliario: no meterse en la trayectoria de un banco, una reposera o un tronco.
		desvio += _empuje_mobiliario(pa, adelante, lateral, a.lado_preferido()) * a.apartado_pref()
		# La espera tiene PRESUPUESTO: si este peatón lleva más de 1,5 s esperando a otro, deja
		# de esperar y se aparta a su lado. Así ningún enfrentamiento se eterniza.
		if bloqueado:
			if not _bloqueo_desde.has(a):
				_bloqueo_desde[a] = ahora
			elif ahora - float(_bloqueo_desde[a]) > 1.5:
				bloqueado = false
				desvio += a.lado_preferido() * maxf(a.apartado_pref(), 0.65)
		else:
			_bloqueo_desde.erase(a)
		a.aviso_peaton(desvio, bloqueado, factor)


## ¿Este peatón está circulando (y por tanto le toca apartarse)? Los que están sentados,
## tumbados, parados o reaccionando no necesitan avisos.
func _circula(c: NPCCitizen) -> bool:
	return c.state == NPCCitizen.State.WALK or c.state == NPCCitizen.State.PAUSE \
			or (c.en_postura() and (c.fase_postura() == "camino" or c.fase_postura() == "acercarse"))


## El reparto se hace antes de que el jugador esté disponible en su grupo, así que la exclusión
## del entorno del inicio no siempre puede aplicarse al sembrar. En cuanto se conoce al jugador,
## a quien haya quedado dentro del radio se le busca un nodo libre lejos y se le reengancha a la
## red (nunca se teletransporta a quien ya va andando ni a quien ya está sentado o tumbado).
func _despejar_inicio_jugador() -> void:
	_despejado = true
	if _zona_jugador == null:
		return
	var pj := Vector2(_zona_jugador.global_position.x, _zona_jugador.global_position.z)
	var movidos := 0
	var usados: Array[Vector2] = []
	for c in peatones:
		if not is_instance_valid(c):
			continue
		usados.append(Vector2(c.global_position.x, c.global_position.z))
	for c in peatones:
		if not is_instance_valid(c):
			continue
		var p: Vector3 = c.global_position
		if Vector2(p.x, p.z).distance_to(pj) >= radio_inicio_jugador:
			continue
		if c.is_walking() or c.en_postura():
			continue
		var tipos: Array = ["arena"] if c.perfil == "costa" else ["acera", "plaza", "parque", "paseo"]
		var nodos: Array = red.nodos_de_tipo(tipos)
		var destino := Vector3.INF
		for _intento in 24:
			if nodos.is_empty():
				break
			var idx: int = nodos[_rng.randi() % nodos.size()]
			var p2: Vector3 = red.pos(idx)
			if Vector2(p2.x, p2.z).distance_to(pj) < radio_inicio_jugador * 1.15:
				continue
			var choque := false
			for u: Vector2 in usados:
				if u.distance_to(Vector2(p2.x, p2.z)) < separacion_inicial:
					choque = true
					break
			if not choque:
				destino = p2
				break
		if destino == Vector3.INF:
			continue
		c.global_position = destino
		c.activar_red(red, self, c.perfil, c.puede_sentarse, c.puede_recostarse)
		usados.append(Vector2(destino.x, destino.z))
		movidos += 1
	if movidos > 0:
		print("[Peatones] inicio del jugador despejado: %d ciudadanos recolocados" % movidos)


# =============================================================================
#  Bucle
# =============================================================================

func _process(delta: float) -> void:
	if not _instalado:
		return
	_t_lod += delta
	_t_avisos += delta
	_t_ciclo += delta
	if _t_lod >= intervaloLOD:
		_t_lod = 0.0
		_repasar_lod()
	if _t_avisos >= 0.2:
		_t_avisos = 0.0
		_avisar_peatones()
	if _t_ciclo >= 0.5:
		_t_ciclo = 0.0
		_gestionar_ciclo()
	# El jugador puede aparecer DESPUÉS del reparto (su nodo se une al grupo más tarde): en cuanto
	# se le localiza, se despeja su entorno de una vez.
	if not _despejado:
		if _zona_jugador == null or not is_instance_valid(_zona_jugador):
			_zona_jugador = get_tree().get_first_node_in_group("player") as Node3D
		if _zona_jugador != null:
			_despejar_inicio_jugador()
	if auditoria:
		_t_auditoria += delta
		if _t_auditoria >= 1.0:
			_t_auditoria = 0.0
			_auditar()


# =============================================================================
#  Auditoría y resumen (pruebas)
# =============================================================================

## Comprueba que ningún peatón esté sobre la calzada fuera de un paso de peatones
## (la calzada NO es superficie válida: si esto canta, hay un fallo de la red).
func _auditar() -> void:
	_auditorias += 1
	var malos := 0
	for c in peatones:
		if not is_instance_valid(c):
			continue
		if c.state == NPCCitizen.State.POSTURA:
			var fase := c.fase_postura()
			if fase == "reposar" or fase == "entrar" or fase == "salir":
				continue                # está en el banco o en la reposera
		var t := c.tramo_red()
		var clase := String(t[2]) if t.size() >= 3 else ""
		if red.es_calzada(c.global_position) and clase != "cruce":
			malos += 1
			_violaciones += 1
			if _violaciones <= 8:
				print("[Peatones][AUDITORÍA] peatón FUERA de la red: ", c.global_position,
						" (tramo: ", clase, ")")
	if _auditorias % 10 == 0 or malos > 0:
		print("[Peatones][AUDITORÍA] t=%.0fs  peatones=%d  en_calzada_fuera_de_paso=%d  acumulado=%d" % [
				Time.get_ticks_msec() / 1000.0, peatones.size(), malos, _violaciones])


## Foto del estado del peatonal (para las pruebas en ejecución).
func resumen() -> Dictionary:
	var r := {"total": 0, "caminando": 0, "quietos": 0, "sentados": 0, "tumbados": 0,
			"yendo_a_postura": 0, "banco_libre": 0, "reposera_libre": 0, "reservas": 0,
			"clavados": 0, "bloqueados": 0}
	for c in peatones:
		if not is_instance_valid(c):
			continue
		r["total"] += 1
		if c.en_postura():
			match c.fase_postura():
				"reposar":
					if c.postura_actual() == "recostarse":
						r["tumbados"] += 1
					else:
						r["sentados"] += 1
				_:
					r["yendo_a_postura"] += 1
		elif c.is_walking():
			r["caminando"] += 1
			# "Clavado" = con la animación de caminar puesta y sin moverse de verdad: es
			# exactamente el fallo de "correr en el sitio" que se persigue en esta pasada.
			if c.velocidad_real() < c.walk_speed * 0.2:
				r["clavados"] += 1
		else:
			r["quietos"] += 1
		if c.bloqueado():
			r["bloqueados"] += 1
	r["banco_libre"] = _libres(_asientos)
	r["reposera_libre"] = _libres(_reposeras)
	r["reservas"] = _reservas.size()
	r["fase"] = _fase
	r["noche"] = es_noche()
	r["retirada"] = _retirada
	r["violaciones"] = _violaciones
	r["sectores"] = _sector_censo.duplicate()
	return r


## Vuelca el resumen a la consola con una etiqueta (para las pruebas).
func informar(etiqueta := "") -> void:
	var r := resumen()
	print("[Peatones] %s fase=%.3f noche=%s retirada=%s | caminando=%d quietos=%d sentados=%d tumbados=%d yendo=%d | corridos_en_el_sitio=%d bloqueados=%d | bancos libres=%d reposeras libres=%d | violaciones=%d" % [
		etiqueta, r["fase"], str(r["noche"]), str(r["retirada"]),
		r["caminando"], r["quietos"], r["sentados"], r["tumbados"], r["yendo_a_postura"],
		r["clavados"], r["bloqueados"],
		r["banco_libre"], r["reposera_libre"], r["violaciones"]])