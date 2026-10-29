extends Node3D
## PRUEBAS de los AVISOS del mapa (Tarea 6) y de la TRANSICIÓN ANIMADA
## minimapa <-> mapa ampliado (Tarea 7), sobre el HUD REAL del jugador:
##  1. el minimapa construye su capa de avisos por encima de la imagen del mapa;
##  2. un enemigo cercano sale como punto y uno LEJANO no sale en el minimapa;
##  3. un enemigo que está ATACANDO sale como amenaza (latido de advertencia);
##  4. una misión ACTIVA con ancla sale como marcador (y pegado al borde si cae
##     fuera del encuadre);
##  5. un evento con tubo DISPONIBLE y un evento en COMBATE salen marcados;
##  6. la tecla M ya no salta: la transición está EN CURSO (marco, zoom y viaje de
##     cámara interpolados) y termina en el mapa ampliado; volver a pulsar la
##     invierte y vuelve al minimapa;
##  7. en el mapa ampliado aparece lo que no cabía en el minimapa (el enemigo
##     lejano) con los mismos avisos.
##
##   godot --headless --path <proyecto> res://pruebas/prueba_mapa_avisos.tscn

const JUGADOR := "res://personaje/base/escenas/leo_jugador.tscn"
const GestorCombate := preload("res://personaje/transformaciones/transformacion ataque/scripts/combat/combat_manager.gd")
const ConfigCombate := preload("res://personaje/transformaciones/transformacion ataque/resources/combat_config.tres")
const GerenteScript := preload("res://enemigos/Scripts/gerente_enemigos_prueba.gd")
const DirectorScript := preload("res://sistemas/eventos/director_eventos.gd")
const ScriptMinimapa := preload("res://personaje/hud_transformacion/scripts/minimapa.gd")
const Avisos := preload("res://personaje/hud_transformacion/scripts/minimapa_avisos.gd")

## Distancias de la prueba (m).
const CERCA := 35.0
const AMENAZA := -35.0
## Dentro del radio de avisos (90 m) pero FUERA del encuadre del minimapa
## normal (140 m de lado = 70 m de radio): en el minimapa se pega al borde y en
## el mapa ampliado aparece en su sitio real.
const BORDE := 80.0
const LEJANO := 200.0
const ANCLA_MISION := 300.0

var _ok := 0
var _fallos := 0
var _jug: Node3D
var _mapa: Control
var _avisos: Control
var _gerente: Node3D
var _mgr: Node
var _director: Node3D
var _e_cerca: Node3D
var _e_amenaza: Node3D
var _e_borde: Node3D
var _e_lejano: Node3D

func _ready() -> void:
	_piso()
	# El gestor del encuentro: el mismo del módulo.
	_mgr = Node.new()
	_mgr.name = "CombatManager"
	_mgr.set_script(GestorCombate)
	_mgr.set("config", ConfigCombate)
	add_child(_mgr)
	_jug = (load(JUGADOR) as PackedScene).instantiate() as Node3D
	_jug.position = Vector3(0, 0.1, 0)
	add_child(_jug)
	# Gerente de enemigos y director de eventos: hermanos con los MISMOS nombres
	# que en el mundo real (el director los busca por ruta relativa).
	_gerente = Node3D.new()
	_gerente.name = "EnemigosPrueba"
	_gerente.set_script(GerenteScript)
	_gerente.set("cantidad", 0)
	add_child(_gerente)
	_director = Node3D.new()
	_director.name = "Eventos"
	_director.set_script(DirectorScript)
	_director.set("retardo_inicial", 600.0)   # la aparición progresiva no estorba
	add_child(_director)
	await get_tree().create_timer(1.0).timeout

	_mapa = _buscar_minimapa()
	_check(_mapa != null, "el HUD del jugador tiene minimapa")
	if _mapa == null:
		_fin()
		return
	_check(bool(_mapa.get("activo")) and _mapa.visible, "el minimapa está activo y visible")
	_avisos = _mapa.get("_avisos") as Control
	_check(_avisos != null, "el minimapa construye su capa de avisos (Tarea 6)")
	if _avisos == null:
		_fin()
		return
	_check(_avisos.get_index() > _mapa.get_node("Vista").get_index(),
			"los avisos se dibujan POR ENCIMA de la imagen del mapa")
	_check(bool(_mapa.get("avisos_activos")), "los avisos están activados")
	# El zoom arranca en el minimapa normal.
	_check(is_equal_approx(float(_mapa.get("_p")), 0.0), "arranca en modo minimapa (progreso 0)")

	# --- 2 y 3. Enemigos: punto cercano, amenaza y lejano -------------------
	_e_cerca = await _crear_enemigo(Vector3(CERCA, 0, 0))
	_e_amenaza = await _crear_enemigo(Vector3(AMENAZA, 0, 0))
	_e_borde = await _crear_enemigo(Vector3(BORDE, 0, 0))
	_e_lejano = await _crear_enemigo(Vector3(LEJANO, 0, 0))
	# Congelados: se mide su posición, no su persecución.
	for e in [_e_cerca, _e_amenaza, _e_borde, _e_lejano]:
		if e != null:
			e.set("velocidad", 0.0)
			e.set("_velocidad_propia", 0.0)
	# El de la izquierda está ATACANDO (amenaza con latido): se registra en el
	# sistema de amenazas del gestor con una ventana larga.
	if _e_amenaza != null:
		_mgr.get("threats").call("register", _e_amenaza, "melee", 60.0, true)
	await get_tree().create_timer(0.5).timeout
	var punto_cerca := _pixel_esperado(Vector3(CERCA, 0, 0))
	var m_cerca := _marca_en(Avisos.T_ENEMIGO, punto_cerca, 10.0)
	_check(m_cerca >= 0, "el enemigo cercano sale como punto en el minimapa (px %.0f,%.0f)" % [punto_cerca.x, punto_cerca.y])
	var m_amenaza := _marca_en(Avisos.T_AMENAZA, _pixel_esperado(Vector3(AMENAZA, 0, 0)), 10.0)
	_check(m_amenaza >= 0, "el enemigo que ATACA sale como AMENAZA (marcador de advertencia)")
	_check(not _en_fuente(_e_lejano),
			"el enemigo lejano queda FUERA de las fuentes de aviso (no satura el minimapa)")
	_check(_en_fuente(_e_cerca) and _en_fuente(_e_amenaza) and _en_fuente(_e_borde),
			"los enemigos relevantes sí entran en las fuentes de aviso")
	_check(_marca_en(Avisos.T_AMENAZA, _pixel_esperado(Vector3(CERCA, 0, 0)), 10.0) < 0,
			"sólo el que ataca es amenaza (no se marcan todos)")
	# El de 80 m está dentro del radio (es relevante) pero fuera del encuadre del
	# minimapa normal: se pega al borde en vez de desaparecer.
	var m_borde_norm := _marca_detalle(Avisos.T_ENEMIGO, _pixel_esperado(Vector3(BORDE, 0, 0)), 40.0)
	_check(not m_borde_norm.is_empty() and not bool(m_borde_norm.get("dentro", true)),
			"el enemigo fuera del encuadre se pega al borde del minimapa (indica su dirección)")

	# --- 4. Misión activa con ancla (fuera del encuadre: pegada al borde) ----
	var misiones := get_node_or_null("/root/Misiones")
	_check(misiones != null, "el gestor de misiones (autoload) está disponible")
	var activada := bool(misiones.call("activar_mision", &"derrotar_profugos", Vector3(ANCLA_MISION, 0, 0)))
	_check(activada, "la misión se activa con su objetivo en el mundo (ancla)")
	await get_tree().create_timer(0.4).timeout
	var marcas := _marcas_de(Avisos.T_MISION)
	_check(not marcas.is_empty(), "la misión activa tiene su marcador en el mapa")
	if not marcas.is_empty():
		var m: Dictionary = marcas[0]
		_check(not bool(m["dentro"]), "el objetivo de misión fuera del encuadre se pega al borde")
		var borde := float(_mapa.size.x) - float(_mapa.get("aviso_margen_px"))
		_check(absf((m["punto"] as Vector2).x - borde) <= 3.0,
				"el marcador pegado queda en el borde derecho (px %.0f ≈ %.0f)" % [(m["punto"] as Vector2).x, borde])

	# --- 5. Eventos: tubo DISPONIBLE y evento en COMBATE --------------------
	var hay := bool(_director.call("forzar_aparicion", &"E1"))
	_check(hay, "el director de eventos deja su tubo disponible (evento E1)")
	await get_tree().create_timer(0.4).timeout
	var m_ev := _marcas_de(Avisos.T_EVENTO)
	_check(not m_ev.is_empty(), "el evento disponible sale marcado (naranja)")
	if not m_ev.is_empty():
		_check(not bool((m_ev[0] as Dictionary)["dentro"]),
				"el evento lejano también se pega al borde (indica hacia dónde ir)")
	# Activación del tubo: el evento pasa a COMBATE con sus enemigos reales.
	var eventos: Dictionary = _director.get("_eventos")
	var tubo: Node3D = null
	if eventos.has(&"E1"):
		tubo = (eventos[&"E1"] as Dictionary).get("tubo") as Node3D
	if tubo != null:
		_director.call("_al_activar_tubo", tubo, &"E1")
	await get_tree().create_timer(0.5).timeout
	_check(int(_director.call("estado_de", &"E1")) == DirectorEventos.Est.COMBATE,
			"el evento pasa a COMBATE (estado %d)" % int(_director.call("estado_de", &"E1")))
	_check(_marcas_de(Avisos.T_EVENTO_COMBATE).size() >= 1,
			"el evento en COMBATE sale con su aviso fuerte (rojo)")

	# --- 5b. Un enemigo que MUERE entre dos refrescos no rompe los avisos -----
	var antes_muerte := _marcas_de(Avisos.T_ENEMIGO).size() + _marcas_de(Avisos.T_AMENAZA).size()
	if _e_amenaza != null:
		_e_amenaza.queue_free()
		_e_amenaza = null
	await get_tree().create_timer(0.5).timeout
	var despues_muerte := _marcas_de(Avisos.T_ENEMIGO).size() + _marcas_de(Avisos.T_AMENAZA).size()
	_check(despues_muerte < antes_muerte and despues_muerte >= 1,
			"un enemigo liberado desaparece de los avisos sin romper nada (%d → %d marcadores)" % [antes_muerte, despues_muerte])

	# --- 6 y 7. Transición animada y mapa ampliado ---------------------------
	var lado_ampliado := maxf(120.0, minf(get_viewport().get_visible_rect().size.x,
			get_viewport().get_visible_rect().size.y) * float(_mapa.get("factor_ampliado")))
	await _pulsar_m()
	var p_medio := float(_mapa.get("_p"))
	var cob_medio := float((_mapa.get("_cam") as Camera3D).size)
	var lado_medio := float(_mapa.size.x)
	_check(p_medio > 0.0 and p_medio < 1.0,
			"pulsar M deja la transición EN CURSO (progreso %.2f, ni 0 ni 1)" % p_medio)
	_check(cob_medio > float(_mapa.get("metros_visibles")) and cob_medio < float(_mapa.get("metros_isla")),
			"el zoom se interpola durante la transición (cobertura %.0f m)" % cob_medio)
	_check(lado_medio > float(_mapa.get("tamano_px")) and lado_medio < lado_ampliado,
			"el marco crece de forma continua (px %.0f)" % lado_medio)
	await get_tree().create_timer(0.9).timeout
	_check(is_equal_approx(float(_mapa.get("_p")), 1.0), "la transición TERMINA en el mapa ampliado")
	_check(is_equal_approx(float((_mapa.get("_cam") as Camera3D).size), float(_mapa.get("metros_isla"))),
			"el mapa ampliado cubre la isla (%.0f m)" % float((_mapa.get("_cam") as Camera3D).size))
	_check(absf(float(_mapa.size.x) - lado_ampliado) <= 1.0,
			"el marco acaba en el tamaño ampliado (px %.0f ≈ %.0f)" % [float(_mapa.size.x), lado_ampliado])
	# 7: el enemigo que en el minimapa se pegaba al borde, aquí aparece EN SU SITIO.
	var m_borde := _marca_detalle(Avisos.T_ENEMIGO, _pixel_esperado(Vector3(BORDE, 0, 0)), 14.0)
	_check(not m_borde.is_empty() and bool(m_borde.get("dentro", false)),
			"en el mapa ampliado el enemigo del borde aparece en su sitio real (no pegado)")
	_check(_marcas_de(Avisos.T_ENEMIGO).all(func(m: Variant) -> bool: return bool((m as Dictionary)["dentro"])),
			"en el mapa ampliado ningún enemigo queda pegado al borde (todos entran)")
	_check(_marcas_de(Avisos.T_MISION).size() >= 1 and _marcas_de(Avisos.T_ENEMIGO).size() >= 1,
			"el mapa ampliado conserva los avisos (misión y enemigos)")
	_check(float(_mapa.size.x) <= get_viewport().get_visible_rect().size.x
			and float(_mapa.size.x) <= get_viewport().get_visible_rect().size.y,
			"el mapa ampliado cabe en la pantalla (px %.0f)" % float(_mapa.size.x))

	# Reversible: otra pulsación a mitad de camino invierte la transición.
	await _pulsar_m()
	var p_bajando := float(_mapa.get("_p"))
	_check(p_bajando > 0.0 and p_bajando <= 1.0, "pulsar otra vez inicia la vuelta al minimapa (progreso %.2f)" % p_bajando)
	await get_tree().create_timer(0.9).timeout
	_check(is_equal_approx(float(_mapa.get("_p")), 0.0), "la vuelta TERMINA en el minimapa normal")
	_check(is_equal_approx(float((_mapa.get("_cam") as Camera3D).size), float(_mapa.get("metros_visibles"))),
			"el minimapa recupera su cobertura (%.0f m)" % float((_mapa.get("_cam") as Camera3D).size))
	_check(absf(float(_mapa.size.x) - float(_mapa.get("tamano_px"))) <= 1.0,
			"el minimapa recupera su tamaño (px %.0f)" % float(_mapa.size.x))

	# Estado final para la captura: mapa ampliado con todos los avisos.
	await _pulsar_m()
	await get_tree().create_timer(0.9).timeout
	_check(is_equal_approx(float(_mapa.get("_p")), 1.0), "mapa ampliado listo para la captura")
	_fin()


# ------------------------------------------------------------------ auxiliares
func _fin() -> void:
	print("==================== MAPA/AVISOS: %d OK / %d FALLO ====================" % [_ok, _fallos])


func _buscar_minimapa() -> Control:
	for n in _jug.find_children("*", "Control", true, false):
		if n.get_script() == ScriptMinimapa:
			return n as Control
	return null


func _crear_enemigo(pos: Vector3) -> Node3D:
	var e := _gerente.call("crear_enemigo_en", pos, GerenteScript.Tipo.MELEE) as Node3D
	await get_tree().physics_frame
	return e


## Píxeles donde DEBE caer un punto del mundo en el mapa actual (misma matemática
## que el minimapa: cámara cenital ortográfica, metros → píxeles 1:1, norte arriba).
func _pixel_esperado(pos: Vector3) -> Vector2:
	var cam := _mapa.get("_cam") as Camera3D
	var cob := maxf(0.001, cam.size)
	var u := (pos.x - cam.global_position.x) / cob + 0.5
	var v := (pos.z - cam.global_position.z) / cob + 0.5
	return Vector2(clampf(u, 0.0, 1.0) * float(_mapa.size.x), clampf(v, 0.0, 1.0) * float(_mapa.size.y))


func _marcas_de(tipo: int) -> Array:
	var salida: Array = []
	for m in (_avisos.get("marcadores") as Array):
		if int((m as Dictionary)["tipo"]) == tipo:
			salida.append(m)
	return salida


## Índice del marcador de ese tipo más cercano al píxel dado (o -1 si no hay).
func _marca_en(tipo: int, punto: Vector2, tolerancia: float) -> int:
	var encontrado := -1
	var mejor := tolerancia
	for m in (_avisos.get("marcadores") as Array):
		var d := m as Dictionary
		if int(d["tipo"]) != tipo:
			continue
		var dist := ((d["punto"] as Vector2) - punto).length()
		if dist <= mejor:
			mejor = dist
			encontrado = 1
	return encontrado


## ¿Ese nodo está entre las fuentes de aviso de enemigos del minimapa? Es la
## comprobación exacta del filtro por radio (más fiable que comparar píxeles).
func _en_fuente(nodo: Node) -> bool:
	if nodo == null:
		return false
	for f in (_mapa.get("_fuente_enemigos") as Array):
		if (f as Dictionary).get("nodo") == nodo:
			return true
	return false


## Marcador de ese tipo más cercano al píxel dado (Dictionary vacío si no hay).
func _marca_detalle(tipo: int, punto: Vector2, tolerancia: float) -> Dictionary:
	var encontrado: Dictionary = {}
	var mejor := tolerancia
	for m in (_avisos.get("marcadores") as Array):
		var d := m as Dictionary
		if int(d["tipo"]) != tipo:
			continue
		var dist := ((d["punto"] as Vector2) - punto).length()
		if dist <= mejor:
			mejor = dist
			encontrado = d
	return encontrado


## Pulsa la tecla M de verdad (pasa por `_unhandled_input`, como el juego) y deja
## que la transición avance unos fotogramas.
func _pulsar_m() -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_M
	ev.pressed = true
	Input.parse_input_event(ev)
	for _i in 3:
		await get_tree().physics_frame
	var suelta := InputEventKey.new()
	suelta.physical_keycode = KEY_M
	suelta.pressed = false
	Input.parse_input_event(suelta)
	for _i in 1:
		await get_tree().physics_frame


func _check(condicion: bool, texto: String) -> void:
	if condicion:
		_ok += 1
		print("[mapa-suite] OK   ", texto)
	else:
		_fallos += 1
		print("[mapa-suite] FALLO ", texto)


func _piso() -> void:
	# Suelo GRANDE: los puntos de evento del director (hasta ±300 m) necesitan
	# suelo firme para resolver su ancla con el rayo real.
	var cuerpo := StaticBody3D.new()
	cuerpo.name = "Terreno"   # nombre de escenario estático: el minimapa lo respeta
	var forma := CollisionShape3D.new()
	var caja := BoxShape3D.new()
	caja.size = Vector3(900, 1, 900)
	forma.shape = caja
	cuerpo.add_child(forma)
	cuerpo.position = Vector3(0, -0.5, 0)
	add_child(cuerpo)
	var malla := MeshInstance3D.new()
	var caja_malla := BoxMesh.new()
	caja_malla.size = Vector3(900, 1, 900)
	malla.mesh = caja_malla
	cuerpo.add_child(malla)
	var luz := DirectionalLight3D.new()
	luz.rotation = Vector3(-0.9, 0.6, 0.0)
	add_child(luz)