class_name DirectorEventos
extends Node3D

## =============================================================================
##  DIRECTOR DE EVENTOS DE ENEMIGOS  (etapas 1 a 4)
## =============================================================================
##  Mantiene 12 PUNTOS DE EVENTO fijos: 10 TERRESTRES y 2 sobre la CUBIERTA del
##  barco. Al empezar la partida NO hay tubos ni enemigos: los tubos aparecen
##  PROGRESIVAMENTE (uno por vez, en intervalos aleatorios de tiempo de juego).
##
##  Cuando el jugador entra en la zona de un tubo, éste desaparece y se crean
##  SÓLO los enemigos de ESE evento, con la API `crear_enemigo_en()` del gerente:
##  se reutilizan las escenas, el registro de combate y el contrato de daño que ya
##  existen. Los enemigos de evento NO entran en los cajones de G/H/J.
##
##  CICLO DE VIDA (por evento, totalmente independiente):
##    ESPERANDO    -> todavía no apareció.
##    DISPONIBLE   -> tubo visible, activable.
##    COMBATE      -> tubo retirado; viven los enemigos de ESE evento.
##    ENFRIAMIENTO -> murió el último enemigo; corren 240 s de tiempo de juego.
##                    Al terminar, el tubo reaparece (vuelve a DISPONIBLE).
##
##  El seguimiento de bajas usa SÓLO la lista de enemigos del propio evento y la
##  señal de muerte existente (`murio`). Una poda periódica barata retira
##  referencias liberadas sin señal (enemigo retirado/liberado de forma
##  inesperada) para que ningún evento quede bloqueado. El enfriamiento NO usa
##  temporizadores por evento: es un único contador `restante` por evento,
##  descontado en `_process` (que respeta la pausa del juego).
##
##  RENDIMIENTO: no se instancia ningún enemigo ni tubo por adelantado; no se
##  escanea la ciudad ni se buscan enemigos globales.

signal evento_aparecido(id: StringName)
signal evento_activado(id: StringName)
signal evento_terminado(id: StringName)

const ESCENA_TUBO := preload("res://eventos/tubo_evento.tscn")

## Tipos del gerente (GerenteEnemigosPrueba.Tipo).
const TIPO_MELEE := 1
const TIPO_TIRADOR := 2

## Nodos del mundo que necesita este director (hermanos en ziba_prototipo.tscn).
const RUTA_GERENTE := ^"../EnemigosPrueba"
const RUTA_BARCO := ^"../Barco"
const RUTA_TERRENO := ^"../Terreno"

## Definición de los 12 eventos: 10 TERRESTRES + 2 sobre el barco.
##   · "terrestre": posición GLOBAL (x,z); la y se ajusta al suelo con un rayo.
##   · "barco": posición LOCAL sobre la cubierta; se resuelve con la
##     transformación real del Barco, así el tubo sigue al barco.
## Las x/z de ciudad caen sobre las LÍNEAS DE CALLE (rejilla de paso 42 m:
## x,z ∈ {-126,-84,-42,0,42,84,126}), que son pasillos libres de edificios.
const EVENTOS := [
	# --- 8 puntos terrestres ---
	{"id": &"E1", "terrestre": Vector3(42.0, 0.0, -210.0), "melee": 3, "tirador": 1},
	{"id": &"E2", "terrestre": Vector3(0.0, 0.0, -260.0), "melee": 2, "tirador": 2},
	{"id": &"E3", "terrestre": Vector3(-300.0, 0.0, -42.0), "melee": 3, "tirador": 0},
	{"id": &"E4", "terrestre": Vector3(42.0, 0.0, -126.0), "melee": 2, "tirador": 1},
	{"id": &"E5", "terrestre": Vector3(84.0, 0.0, -42.0), "melee": 2, "tirador": 2},
	{"id": &"E6", "terrestre": Vector3(-84.0, 0.0, 0.0), "melee": 3, "tirador": 0},
	{"id": &"E7", "terrestre": Vector3(0.0, 0.0, 126.0), "melee": 2, "tirador": 2},
	{"id": &"E8", "terrestre": Vector3(126.0, 0.0, 42.0), "melee": 3, "tirador": 1},
	# --- 2 puntos urbanos NUEVOS (cruces transitables de la cuadrícula) ---
	{"id": &"E9", "terrestre": Vector3(-42.0, 0.0, 84.0), "melee": 2, "tirador": 2},
	{"id": &"E10", "terrestre": Vector3(84.0, 0.0, 84.0), "melee": 3, "tirador": 1},
	# --- 2 puntos sobre la cubierta del barco ---
	{"id": &"B1", "barco": Vector3(0.0, 3.9, 4.0), "melee": 2, "tirador": 1},
	{"id": &"B2", "barco": Vector3(0.0, 3.9, 14.0), "melee": 2, "tirador": 1},
]

@export_group("Aparición progresiva (tiempo de juego)")
## Retardo (s) antes de que pueda aparecer el primer tubo.
@export var retardo_inicial: float = 12.0
## Intervalo aleatorio (s) entre una aparición y la siguiente.
@export var intervalo_min: float = 16.0
@export var intervalo_max: float = 30.0
## Orden de aparición aleatorio (true) o el orden de la lista (false).
@export var orden_aleatorio: bool = true

@export_group("Generación de enemigos")
## Radio (m) del anillo de aparición de enemigos alrededor del tubo (terrestres).
@export var radio_generacion: float = 5.0
## Radio (m) para los eventos del barco (la cubierta es más angosta).
@export var radio_generacion_barco: float = 3.0

@export_group("Enfriamiento")
## Enfriamiento (s de TIEMPO DE JUEGO) por evento antes de que su tubo reaparezca.
## El juego usa 240 s; las pruebas automatizadas lo reducen a propósito para no
## esperar 4 minutos (la duración real del juego no cambia).
@export var duracion_enfriamiento: float = 240.0
## Cada cuánto (s) se revisa, de forma barata, que las referencias de enemigos
## sigan siendo válidas (red de seguridad ante desapariciones inesperadas).
@export var intervalo_poda: float = 0.25
## Si un tubo NO puede reaparecer (p. ej. sin suelo en ese instante), cuánto se
## reintenta después (s de tiempo de juego).
@export var reintento_reaparicion: float = 2.0

enum Est { ESPERANDO, DISPONIBLE, COMBATE, ENFRIAMIENTO }

var _eventos: Dictionary = {}                    # id -> { def, estado, tubo, enemigos, ancla }
var _pendientes: Array[StringName] = []
var _temporizador: Timer
var _gerente: Node = null
var _barco: Node3D = null
var _terrain3d: Object = null
var _t_poda: float = 0.0


func _resolver_referencias() -> void:
	if _gerente == null or not is_instance_valid(_gerente):
		_gerente = get_node_or_null(RUTA_GERENTE)
	if _barco == null or not is_instance_valid(_barco):
		_barco = get_node_or_null(RUTA_BARCO) as Node3D
	if _terrain3d == null or not is_instance_valid(_terrain3d):
		var terreno := get_node_or_null(RUTA_TERRENO)
		if terreno != null:
			_terrain3d = terreno.get("terreno")


func _ready() -> void:
	for def in EVENTOS:
		var id: StringName = def["id"]
		_eventos[id] = {
			"def": def,
			"estado": Est.ESPERANDO,
			"tubo": null,
			"enemigos": [],
			"ancla": Vector3.ZERO,
			"restante": 0.0,
			"contador": null,
		}
		_pendientes.append(id)
	if orden_aleatorio:
		_pendientes.shuffle()
	_temporizador = Timer.new()
	_temporizador.one_shot = true
	_temporizador.timeout.connect(_al_vencer_temporizador)
	add_child(_temporizador)
	_temporizador.start(maxf(0.1, retardo_inicial))
	_resolver_referencias.call_deferred()


func _process(delta: float) -> void:
	# El juego en pausa no descuenta enfriamiento (ni tiempo de aparición).
	if get_tree().paused:
		return
	if _eventos.is_empty():
		return
	_actualizar_enfriamientos(delta)
	_t_poda += delta
	if _t_poda >= intervalo_poda:
		_t_poda = 0.0
		_podar_combates()


# =============================================================== Aparición
func _al_vencer_temporizador() -> void:
	_soltar_siguiente()
	if not _pendientes.is_empty():
		_programar_siguiente()


func _programar_siguiente() -> void:
	if _temporizador == null:
		return
	_temporizador.start(randf_range(minf(intervalo_min, intervalo_max), maxf(intervalo_min, intervalo_max)))


## Hace aparecer el próximo tubo pendiente. Si su ancla no es válida en el mapa
## actual, ese evento queda sin tubo y se prueba el siguiente (así un punto
## desafortunado no bloquea la cadena).
func _soltar_siguiente() -> void:
	var intentos := _pendientes.size()
	for _i in intentos:
		if _pendientes.is_empty():
			return
		var id: StringName = _pendientes.pop_front()
		if _intentar_aparecer(id):
			return
		push_warning("[Eventos] El punto del evento %s no es válido en este mapa: se omite." % str(id))


## Primera aparición de un evento (estado ESPERANDO). Calcula el ancla una vez.
func _intentar_aparecer(id: StringName) -> bool:
	_resolver_referencias()
	var est: Dictionary = _eventos.get(id, {})
	if est.is_empty() or est.get("estado") != Est.ESPERANDO:
		return false
	var ancla: Variant = _ancla_global(est["def"])
	if ancla == null:
		return false
	est["ancla"] = ancla
	return _crear_tubo(id, est)


## Crea e instancia el tubo de un evento y lo deja DISPONIBLE. Devuelve false si
## no se pudo instanciar. Reutilizado por la primera aparición y la reaparición,
## de modo que el tubo vuelve a la MISMA posición y con el MISMO padre:
##  · barco  -> hijo del nodo Barco (posición local de cubierta),
##  · tierra -> hijo del director (posición global guardada).
func _crear_tubo(id: StringName, est: Dictionary) -> bool:
	var tubo := ESCENA_TUBO.instantiate() as Node3D
	if tubo == null:
		push_warning("[Eventos] No se pudo instanciar el tubo del evento %s." % str(id))
		return false
	var def: Dictionary = est["def"]
	if def.has("barco") and _barco != null and is_instance_valid(_barco):
		_barco.add_child(tubo)
		tubo.position = def["barco"]
	else:
		add_child(tubo)
		tubo.global_position = est["ancla"]
	est["estado"] = Est.DISPONIBLE
	est["tubo"] = tubo
	tubo.set_meta(&"evento_id", id)
	tubo.activado.connect(_al_activar_tubo.bind(id))
	evento_aparecido.emit(id)
	return true


## Posición global del ancla de un evento, o null si no hay suelo/válido.
func _ancla_global(def: Dictionary) -> Variant:
	if def.has("barco"):
		if _barco == null or not is_instance_valid(_barco):
			return null
		return _barco.to_global(def["barco"])
	return _suelo_de(def["terrestre"])


## Punto de suelo bajo (x,z), o null si no hay. Primero un rayo (usa la colisión
## estática: ciudad, barco y el terreno CERCANO a la cámara). Si no hay colisión
## ahí —el Terrain3D solo genera colisión DINÁMICA alrededor de la cámara, así que
## en montañas lejanas no existe—, se recurre a la ALTURA ANALÍTICA del terreno,
## que está disponible en todo el mapa.
func _suelo_de(pos: Vector3) -> Variant:
	if not is_inside_tree():
		return null
	var espacio := get_world_3d().direct_space_state
	var rayo := PhysicsRayQueryParameters3D.create(
			Vector3(pos.x, 400.0, pos.z), Vector3(pos.x, -120.0, pos.z), 1)
	var golpe := espacio.intersect_ray(rayo)
	if not golpe.is_empty():
		var p: Vector3 = golpe.get("position", Vector3.ZERO)
		return p + Vector3.UP * 0.03
	var h: Variant = _altura_terreno(pos.x, pos.z)
	if h == null:
		return null
	return Vector3(pos.x, float(h) + 0.03, pos.z)


## Altura del terreno en (x,z) vía Terrain3D.data.get_height, o null si no hay
## terreno (fuera del mapa). No depende de la colisión dinámica.
func _altura_terreno(x: float, z: float) -> Variant:
	_resolver_referencias()
	if _terrain3d == null or not is_instance_valid(_terrain3d):
		return null
	var datos: Variant = _terrain3d.get("data")
	if datos == null:
		return null
	var h: Variant = datos.call("get_height", Vector3(x, 0.0, z))
	if h == null:
		return null
	var y := float(h)
	if not is_finite(y) or y < -100.0:
		return null
	return y


# =============================================================== Activación
func _al_activar_tubo(tubo: Node3D, id: StringName) -> void:
	var est: Dictionary = _eventos.get(id, {})
	if est.is_empty() or est.get("estado") != Est.DISPONIBLE:
		return
	est["estado"] = Est.COMBATE
	# Ciclo nuevo: la lista de enemigos arranca limpia (nada del ciclo anterior).
	est["enemigos"] = []
	est["restante"] = 0.0
	if tubo != null and is_instance_valid(tubo):
		tubo.queue_free()
	est["tubo"] = null
	var creados: int = _generar_enemigos(id, est["ancla"], est["def"])
	evento_activado.emit(id)
	# Si NINGÚN enemigo pudo crearse, el evento no debe quedar bloqueado en
	# COMBATE: se cierra igual (pasa a enfriamiento y su tubo volverá más tarde).
	if creados <= 0:
		push_warning("[Eventos] El evento %s no creó ningún enemigo: se cierra sin combate." % str(id))
		_terminar_evento(id)


## Crea SÓLO los enemigos de este evento, reutilizando la API del gerente.
## Devuelve cuántos se crearon de verdad.
func _generar_enemigos(id: StringName, ancla: Vector3, def: Dictionary) -> int:
	if _gerente == null or not is_instance_valid(_gerente):
		push_warning("[Eventos] Sin gerente de enemigos: el evento %s no genera nada." % str(id))
		return 0
	var es_barco: bool = def.has("barco")
	var radio: float = radio_generacion_barco if es_barco else radio_generacion
	var plan: Array[int] = []
	for _i in int(def.get("melee", 0)):
		plan.append(TIPO_MELEE)
	for _i in int(def.get("tirador", 0)):
		plan.append(TIPO_TIRADOR)
	var n := plan.size()
	if n == 0:
		return 0
	var lista: Array = _eventos[id]["enemigos"]
	var base_ang := randf() * TAU
	for i in n:
		var ang := base_ang + TAU * float(i) / float(n)
		var cand := ancla + Vector3(cos(ang), 0.0, sin(ang)) * radio
		var apoyo: Variant = _gerente.call("posicion_valida_en", cand)
		if apoyo == null:
			continue
		# En el barco, no aceptar un punto que haya caído fuera de la cubierta
		# (al agua): el suelo del mar está decenas de metros por debajo.
		if es_barco and absf((apoyo as Vector3).y - ancla.y) > 2.0:
			continue
		var e: Node3D = _gerente.call("crear_enemigo_en", apoyo, plan[i])
		if e == null:
			continue
		lista.append(e)
		e.murio.connect(_al_morir_enemigo_evento.bind(id))
	return lista.size()


# =============================================================== Bajas y fin
## Un enemigo del evento murió (señal `murio`). Deja de contarse como vivo. SÓLO
## cuando cae el último el evento se cierra y arranca su enfriamiento. La guarda
## de estado impide contar dos veces la misma muerte.
func _al_morir_enemigo_evento(e: Node, id: StringName) -> void:
	var est: Dictionary = _eventos.get(id, {})
	if est.is_empty() or est.get("estado") != Est.COMBATE:
		return
	var lista: Array = est["enemigos"]
	lista.erase(e)
	if lista.is_empty():
		_terminar_evento(id)


## Cierra el encuentro de un evento e inicia su enfriamiento independiente.
func _terminar_evento(id: StringName) -> void:
	var est: Dictionary = _eventos.get(id, {})
	if est.is_empty():
		return
	est["enemigos"] = []
	est["estado"] = Est.ENFRIAMIENTO
	est["restante"] = maxf(0.0, duracion_enfriamiento)
	# Contador visual de ESTE evento (mismo `restante` que el enfriamiento real).
	_crear_contador(id, est)
	evento_terminado.emit(id)


# =============================================================== Enfriamiento
func _actualizar_enfriamientos(delta: float) -> void:
	for id in _eventos.keys():
		var est: Dictionary = _eventos[id]
		if est.get("estado") != Est.ENFRIAMIENTO:
			continue
		est["restante"] = float(est.get("restante", 0.0)) - delta
		if float(est["restante"]) <= 0.0:
			# A cero: el contador de ESE evento desaparece y reaparece su tubo.
			_quitar_contador(est)
			_reaparecer(id)
		else:
			_actualizar_contador(est)


## Terminado el enfriamiento: reaparece el tubo del evento (MISMA posición, MISMO
## padre). NO se generan enemigos: sólo al volver a activarlo. Si el tubo no puede
## reaparecer ahora, se reintenta en `reintento_reaparicion` s.
func _reaparecer(id: StringName) -> void:
	var est: Dictionary = _eventos.get(id, {})
	if est.is_empty() or est.get("estado") != Est.ENFRIAMIENTO:
		return
	_resolver_referencias()
	if _crear_tubo(id, est):
		return
	est["restante"] = maxf(0.1, reintento_reaparicion)


## Red de seguridad: retira de la lista de un evento los enemigos liberados o
## muertos SIN haber emitido la señal (p. ej. retirados de forma inesperada), de
## modo que el evento nunca quede bloqueado. Sólo toca la lista del propio evento.
func _podar_combates() -> void:
	for id in _eventos.keys():
		var est: Dictionary = _eventos[id]
		if est.get("estado") != Est.COMBATE:
			continue
		var lista: Array = est["enemigos"]
		var vivos: Array = []
		var cambio := false
		for e in lista:
			var vivo := is_instance_valid(e) and (not (e as Node).has_method("is_alive") or bool((e as Node).call("is_alive")))
			if vivo:
				vivos.append(e)
			else:
				cambio = true
		if cambio:
			est["enemigos"] = vivos
			if vivos.is_empty():
				_terminar_evento(id)


# =============================================================== Contador visual
## Crea el CONTADOR del evento: una etiqueta 3D que mira a la cámara, situada en
## la posición del evento. Muestra el MISMO `restante` que el enfriamiento real
## (no hay un segundo temporizador que pueda desincronizarse). En el barco cuelga
## del propio Barco (sigue su transformación).
func _crear_contador(id: StringName, est: Dictionary) -> void:
	_quitar_contador(est)
	var lbl := Label3D.new()
	lbl.name = "Contador" + String(id)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.font_size = 96
	lbl.pixel_size = 0.012
	lbl.outline_size = 22
	lbl.modulate = Color(1.0, 0.93, 0.28, 1.0)
	lbl.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
	lbl.shaded = false
	lbl.double_sided = true
	lbl.visibility_range_end = 170.0
	lbl.visibility_range_end_margin = 25.0
	lbl.text = _formato_tiempo(float(est.get("restante", 0.0)))
	var def: Dictionary = est["def"]
	if def.has("barco") and _barco != null and is_instance_valid(_barco):
		_barco.add_child(lbl)
		lbl.position = (def["barco"] as Vector3) + Vector3(0.0, 3.0, 0.0)
	else:
		add_child(lbl)
		lbl.global_position = (est["ancla"] as Vector3) + Vector3(0.0, 4.8, 0.0)
	est["contador"] = lbl


func _actualizar_contador(est: Dictionary) -> void:
	var c: Variant = est.get("contador")
	if c != null and is_instance_valid(c):
		(c as Label3D).text = _formato_tiempo(float(est.get("restante", 0.0)))


func _quitar_contador(est: Dictionary) -> void:
	var c: Variant = est.get("contador")
	if c != null and is_instance_valid(c):
		(c as Node).queue_free()
	est["contador"] = null


## MM:SS, nunca negativo (redondeo hacia arriba: 240 -> "04:00", 0 -> "00:00").
static func _formato_tiempo(seg: float) -> String:
	var total := int(ceil(maxf(0.0, seg)))
	var m := int(floor(float(total) / 60.0))
	var s := total % 60
	return "%02d:%02d" % [m, s]


# =============================================================== API de consulta / pruebas
func eventos_definidos() -> int:
	return EVENTOS.size()


## Copia de las definiciones de los eventos (para pruebas y herramientas).
func definiciones() -> Array:
	return EVENTOS.duplicate(true)


func estado_de(id: StringName) -> int:
	var est: Dictionary = _eventos.get(id, {})
	return int(est.get("estado", -1))


func enemigos_de(id: StringName) -> Array:
	var est: Dictionary = _eventos.get(id, {})
	return est.get("enemigos", [])


## Cuántos enemigos del evento siguen vivos AHORA (ignora referencias liberadas).
func enemigos_vivos_de(id: StringName) -> int:
	var est: Dictionary = _eventos.get(id, {})
	var n := 0
	for e in est.get("enemigos", []):
		if is_instance_valid(e) and (not (e as Node).has_method("is_alive") or bool((e as Node).call("is_alive"))):
			n += 1
	return n


## Segundos de enfriamiento que le quedan al evento (0 si no está enfriando).
func restante_enfriamiento(id: StringName) -> float:
	var est: Dictionary = _eventos.get(id, {})
	if est.get("estado") != Est.ENFRIAMIENTO:
		return 0.0
	return float(est.get("restante", 0.0))


## Texto del contador de un evento ("MM:SS"), o "" si no hay contador.
func texto_contador(id: StringName) -> String:
	var est: Dictionary = _eventos.get(id, {})
	var c: Variant = est.get("contador")
	if c != null and is_instance_valid(c):
		return String((c as Label3D).text)
	return ""


func contador_visible(id: StringName) -> bool:
	var est: Dictionary = _eventos.get(id, {})
	var c: Variant = est.get("contador")
	return c != null and is_instance_valid(c)


func tubos_visibles() -> int:
	var n := 0
	for id in _eventos.keys():
		if _eventos[id].get("estado") == Est.DISPONIBLE:
			n += 1
	return n


func pendientes() -> int:
	return _pendientes.size()


## Fuerza la aparición de un tubo concreto (para pruebas). true si apareció.
func forzar_aparicion(id: StringName) -> bool:
	_pendientes.erase(id)
	return _intentar_aparecer(id)


## Termina ya el enfriamiento de un evento (para pruebas): el tubo reaparecerá en
## el siguiente fotograma de proceso.
func forzar_fin_enfriamiento(id: StringName) -> void:
	var est: Dictionary = _eventos.get(id, {})
	if not est.is_empty() and est.get("estado") == Est.ENFRIAMIENTO:
		est["restante"] = 0.0