class_name PuertaCasaLeo
extends Node3D
## =============================================================================
##  LA PUERTA DE LA CASA DE LEO, EN LA CIUDAD
## =============================================================================
##  Busca una PUERTA DE VERDAD de las que genera la ciudad (el generador deja en
##  `prueba_portales` la posición de cada portal y en `prueba_portales_dir` hacia
##  dónde da) y se queda con la MÁS CERCANA al punto donde aparece Leo. Esa es la
##  puerta de su casa: la que tiene más a mano al empezar.
##
##  La elección se hace UNA sola vez y se recuerda (`EstadoCasaLeo.guardar_portal`):
##  entres y salgas las veces que salgas, la casa tiene SIEMPRE la misma puerta, en
##  el mismo sitio. Si ya venía elegida, no se busca nada: se usa esa.
##
##  La puerta se señala con una FLECHA amarilla que sube y baja, la misma receta
##  (cono + vástago, material sin sombreado) que usan las flechas del juego, para
##  que se vea desde la calle sin tocar la interfaz.
##
##  En cuanto Leo se acerca al radio, el HUD muestra el aviso ("Presiona E para
##  entrar a la casa de Leo") por el MISMO canal que los avisos del agua y de las
##  escaleras (el controlador los publica en `texto_interaccion()` y el HUD los
##  pinta con su fundido de siempre): no hay UI nueva.
##
##  Al pulsar E, la puerta deja el punto de vuelta (delante de ella, mirando a la
##  calle), guarda la HORA del ciclo (para que el interior viva a esa misma hora) y
##  arranca la carga del interior con la pantalla de carga del juego. Al volver,
##  Leo se coloca con `colocar_en` del controlador (que orienta cuerpo y cámara sin
##  girar la raíz del jugador) y la puerta NO vuelve a ofrecerse hasta que se aleje
##  del radio: ni dobles entradas ni bucles.

const RADIO_ENTRADA := 2.4      ## m: hasta aquí se ofrece entrar
const DELANTE := 1.2            ## m desde el portal: dónde se planta Leo al volver
## Texto EXACTO del aviso del HUD en la puerta.
const TEXTO := "Presiona E para entrar a la casa de Leo"
## Flecha de la puerta: altura sobre el portal, vaivén y color (el del juego).
const FLECHA_ALTURA := 2.6
const FLECHA_AMPLITUD := 0.16
const FLECHA_VELOCIDAD := 2.2
const FLECHA_COLOR := Color(1.0, 0.84, 0.05)
## Al volver hay que alejarse este margen (además del radio) para que vuelva a
## ofrecerse la entrada.
const MARGEN_ALEJARSE := 1.2
## Holgura del lateral desde el que se mide el aviso (m).
const LADO_MINIMO := 0.6

## Nodo del generador de ciudad (se leen sus portales reales).
@export var ciudad: Node
## Radio (m) en el que la puerta acepta la E.
@export var radio := RADIO_ENTRADA

var _portal := Vector3.ZERO      ## centro del portal elegido
var _afuera := Vector3.FORWARD   ## normal hacia la calle
var _marcada := false
var _usando := false
var _t := 0.0
## Tras volver de la casa, la puerta no se ofrece hasta alejarse del radio.
var _alejarse := false
var _flecha: Node3D


func _ready() -> void:
	add_to_group("puerta_casa_leo")
	set_process(true)
	# Si venimos de la casa, Leo aparece delante de su puerta (no en el punto de
	# inicio del mundo). Se aplaza un fotograma para que el jugador ya exista.
	if EstadoCasaLeo.hay_vuelta():
		call_deferred("_colocar_jugador_al_volver")


func _process(delta: float) -> void:
	_t += delta
	if _flecha != null:
		_flecha.position.y = FLECHA_ALTURA + sin(_t * FLECHA_VELOCIDAD) * FLECHA_AMPLITUD
	if not _marcada:
		_buscar_puerta()
	# El "hay que alejarse" sólo se decide cuando la puerta ya sabe dónde está: si
	# no, la primera pasada de `_process` mediría desde el origen y lo daría por
	# cumplido (la puerta se marcaría en el mismo fotograma, un paso después).
	if _alejarse and _marcada:
		var j := jugador()
		if j == null or j.global_position.distance_to(global_position) > radio + MARGEN_ALEJARSE:
			_alejarse = false


func jugador() -> Node3D:
	return get_tree().get_first_node_in_group("player") as Node3D


## Elige la puerta real de la ciudad: la GUARDADA si ya hay una, y si no la más
## cercana a donde aparece Leo (que es la que se guarda para siempre).
func _buscar_puerta() -> void:
	var portales: Array = ciudad.get("prueba_portales") if ciudad != null else []
	var dirs: Array = ciudad.get("prueba_portales_dir") if ciudad != null else []
	var est: Dictionary = ciudad.get("_est") if ciudad != null else {}
	if portales == null or dirs == null or portales.is_empty():
		return
	if int(est.get("portales", 0)) <= 0:
		return
	var mejor := EstadoCasaLeo.portal_guardado()
	if mejor < 0 or mejor >= portales.size():
		# Primera vez: la puerta más a mano para Leo (el jugador del mundo).
		var j := jugador()
		var desde := j.global_position if j != null else Vector3.ZERO
		mejor = 0
		var mejor_d := 1e9
		for i in portales.size():
			var p: Vector3 = portales[i]
			var d := p.distance_to(desde)
			if d < mejor_d:
				mejor_d = d
				mejor = i
		EstadoCasaLeo.guardar_portal(mejor)
		print("[casa] puerta de Leo elegida: portal %d (%s) a %.1f m de donde aparece Leo" % [
				mejor, str(portales[mejor]), mejor_d])
	else:
		print("[casa] puerta de Leo: el portal %d de siempre (%s)" % [mejor, str(portales[mejor])])
	_portal = portales[mejor]
	var n: Vector3 = dirs[mejor]
	n.y = 0.0
	_afuera = n.normalized() if n.length() > 0.001 else Vector3.FORWARD
	global_position = _portal + _afuera * 0.35
	# El marcador mira a la calle (para poder orientar avisos o iconos 3D).
	look_at(global_position + _afuera, Vector3.UP)
	_montar_flecha()
	_marcada = true


## La flecha amarilla de la puerta: mismo cono + vástago y mismo material sin
## sombreado que las flechas que ya usa el juego, a un tercio de tamaño.
func _montar_flecha() -> void:
	if _flecha != null:
		return
	_flecha = Node3D.new()
	_flecha.name = "FlechaPuerta"
	add_child(_flecha)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = FLECHA_COLOR
	mat.emission_enabled = true
	mat.emission = FLECHA_COLOR
	mat.emission_energy_multiplier = 0.6
	var cono := CylinderMesh.new()
	cono.top_radius = 0.216
	cono.bottom_radius = 0.0
	cono.height = 0.576
	cono.radial_segments = 20
	var punta := MeshInstance3D.new()
	punta.name = "Punta"
	punta.mesh = cono
	punta.material_override = mat
	punta.position = Vector3(0.0, -0.288, 0.0)
	_flecha.add_child(punta)
	var cilindro := CylinderMesh.new()
	cilindro.top_radius = 0.081
	cilindro.bottom_radius = 0.081
	cilindro.height = 0.72
	cilindro.radial_segments = 12
	var vastago := MeshInstance3D.new()
	vastago.name = "Vastago"
	vastago.mesh = cilindro
	vastago.material_override = mat
	vastago.position = Vector3(0.0, -0.936, 0.0)
	_flecha.add_child(vastago)
	_flecha.position = Vector3(0.0, FLECHA_ALTURA, 0.0)


## --- Contrato de interacción (lo llaman el controlador y el HUD) --------------
func texto_prompt() -> String:
	return TEXTO


## ¿Leo está dentro del radio de la puerta (y del lado de la calle)?
func en_rango() -> bool:
	var j := jugador()
	if j == null:
		return false
	var d := j.global_position - global_position
	d.y = 0.0
	if d.length() > radio:
		return false
	return d.dot(_afuera) > -LADO_MINIMO


## ¿Se puede entrar ahora mismo? (marca puesta, Leo cerca, sin bloqueo, sin doble
## uso y sin que acabe de volver de la casa)
func puede_usar() -> bool:
	return _marcada and not _usando and not _alejarse \
			and not EstadoCasaLeo.bloqueado() and en_rango()


## Punto del portal elegido (para pruebas y depuración).
func portal() -> Vector3:
	return _portal


func portal_indice() -> int:
	return EstadoCasaLeo.portal_guardado()


## A dónde sale Leo al volver de la casa.
func punto_de_salida() -> Vector3:
	return global_position + _afuera * DELANTE


## ¿La puerta está esperando a que Leo se aleje para volver a ofrecerse?
func esperando_alejarse() -> bool:
	return _alejarse


func flecha() -> Node3D:
	return _flecha


## Entra en la casa: deja el punto de vuelta, guarda la hora del ciclo y arranca la
## carga del interior.
func intentar_usar() -> bool:
	if not puede_usar():
		return false
	_usando = true
	EstadoCasaLeo.marcar_vuelta(global_position + _afuera * DELANTE, -_afuera)
	# La hora de la calle viaja al interior: el interior vive a LA MISMA hora, sin
	# crear ningún reloj nuevo (el ciclo de la ciudad sigue siendo el único).
	var fase := EstadoCasaLeo.fase_del_ciclo(self)
	if fase >= 0.0:
		EstadoCasaLeo.guardar_fase(fase)
	print("[casa] entrando a la casa de Leo desde %s (fase %.3f)" % [str(_portal), fase])
	EstadoCasaLeo.entrar(self)
	return true


## Al volver de la casa, Leo aparece delante de su puerta mirando a la calle. Se usa
## la colocación del controlador (`colocar_en`): orienta cuerpo y cámara sin girar
## la raíz del jugador, así el movimiento relativo a la cámara cuadra desde el
## primer fotograma (era justo lo que fallaba al salir de la casa).
func _colocar_jugador_al_volver() -> void:
	# La vuelta se CONSUME aquí (una sola vez): no queda nada colgando esperando.
	if not EstadoCasaLeo.tomar_vuelta():
		return
	var punto := EstadoCasaLeo.punto_de_vuelta()
	var mira := EstadoCasaLeo.mirada_de_vuelta()
	var j := jugador()
	if j == null:
		return
	var objetivo := Vector3(punto.x + mira.x * 10.0, punto.y, punto.z + mira.z * 10.0)
	if j.has_method("colocar_en"):
		j.call("colocar_en", punto + Vector3.UP * 0.05, objetivo)
	else:
		j.global_position = punto + Vector3.UP * 0.2
		j.look_at(Vector3(objetivo.x, j.global_position.y, objetivo.z), Vector3.UP)
	# La hora que dejó el interior vuelve a la calle: el ciclo de la ciudad se
	# coloca en esa fase (la misma cifra, el mismo reloj de siempre).
	var fase := EstadoCasaLeo.fase_guardada()
	var ciclo := get_tree().get_first_node_in_group("ciclo_dia_noche")
	if ciclo != null and ciclo.has_method("poner_fase") and fase >= 0.0:
		ciclo.call("poner_fase", fase)
	# Hasta que Leo no se aleje del radio, la puerta no vuelve a ofrecerse.
	_alejarse = true
	print("[casa] Leo vuelve a la calle delante de su puerta (%s), fase %.3f" % [str(punto), fase])