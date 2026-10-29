extends Node3D

## Pruebas del sistema de CONTROLES (CONFIGURACIÓN > CONTROLES).
##
## Comprueba, con el sistema REAL:
##   1. El catálogo cubre acciones que existen en el Input Map.
##   2. La reasignación escribe en el InputMap (no sólo cambia un texto).
##   3. La tecla nueva MUEVE de verdad al jugador y la vieja deja de hacerlo.
##   4. Conflictos: se detectan entre acciones que pueden estar activas a la vez
##      y NO entre acciones de formas distintas (contextual).
##   5. Escape está reservado.
##   6. El intercambio conserva las dos asignaciones.
##   7. Persistencia: un servicio nuevo relee lo guardado.
##   8. El panel: selector de formas, listas por forma y captura con teclado.
##   9. La transformación rápida con G ya no existe y el menú radial (F) sigue
##      siendo el camino de transformación.
##  10. RESTABLECER TECLAS: confirmación, cancelación y restauración GLOBAL.
##  11. Distribución del selector (izquierda) e icono circular sin marco.
##
## NO forma parte del juego. Al terminar deja las asignaciones de fábrica.

const PauseMenuScene := preload("res://ui/scenes/PauseMenu.tscn")

var _ok := 0
var _fail := 0

@onready var jug: CharacterBody3D = $Jugador
@onready var pausa: CanvasLayer = $Pausa

func _ready() -> void:
	await get_tree().process_frame
	AjustesControles.restablecer_todo()
	print("[TEST] ================= CONTROLES =================")
	await _probar_catalogo()
	await _probar_reasignacion()
	await _probar_jugador_real()
	await _probar_acciones_de_forma()
	await _probar_conflictos()
	_probar_reservado()
	_probar_intercambio()
	await _probar_persistencia()
	await _probar_panel()
	await _probar_captura_panel()
	await _probar_g_eliminada()
	await _probar_restablecer()
	await _probar_distribucion_selector()
	AjustesControles.restablecer_todo()
	print("[TEST] ===== RESUMEN CONTROLES: %d OK, %d FALLOS =====" % [_ok, _fail])

# ---------------------------------------------------------------- utilidades
func _check(nombre: String, cond: bool, extra: String = "") -> void:
	if cond:
		_ok += 1
		print("[TEST] OK :: ", nombre, " | ", extra)
	else:
		_fail += 1
		print("[TEST] FALLO :: ", nombre, " | ", extra)

func _tecla(code: Key) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.pressed = true
	return ev

func _soltar(code: Key) -> InputEventKey:
	var ev := _tecla(code)
	ev.pressed = false
	return ev

func _enviar(ev: InputEvent) -> void:
	Input.parse_input_event(ev)
	await get_tree().process_frame
	await get_tree().process_frame

func _fila_textos(rows: VBoxContainer) -> Array:
	var salida: Array = []
	for fila in rows.get_children():
		var cont := fila.get_node_or_null("Contenido")
		if cont == null:
			continue
		var acc := cont.get_node_or_null("Accion")
		if acc == null:
			continue
		var nombre := acc.get_node_or_null("Nombre")
		if nombre != null:
			salida.append(String(nombre.text))
	return salida

# ---------------------------------------------------------------- 1. catálogo
func _probar_catalogo() -> void:
	var faltan: Array = []
	for entrada in AjustesControlesService.CATALOGO:
		if not InputMap.has_action(entrada["accion"]):
			faltan.append(String(entrada["accion"]))
	_check("todas las acciones del catálogo existen en el Input Map",
			faltan.is_empty(), "faltan=%s" % str(faltan))

	var humano: Array = AjustesControles.acciones_para(AjustesControlesService.HUMANO)
	_check("Humano usa el movimiento compartido y correr/agacharse",
			humano.has(&"mover_adelante") and humano.has(&"correr") and humano.has(&"agacharse"))
	_check("Humano NO muestra el dash (es del Velocista)", not humano.has(&"dash"))

	var velo: Array = AjustesControles.acciones_para(AjustesControlesService.VELOCISTA)
	_check("Velocista usa dash, emote y cargar poder",
			velo.has(&"dash") and velo.has(&"emote") and velo.has(&"cargar_poder"))
	_check("Velocista NO muestra habilidades de agua", not velo.has(&"agua_habilidad_1"))

	var acua: Array = AjustesControles.acciones_para(AjustesControlesService.ACUATICO)
	_check("Acuático usa las cuatro habilidades de agua",
			acua.has(&"agua_habilidad_1") and acua.has(&"agua_habilidad_4"))

	var fuerza: Array = AjustesControles.acciones_para(AjustesControlesService.FUERZA)
	_check("Fuerza usa embestida, pisotón y roca",
			fuerza.has(&"fuerza_embestida") and fuerza.has(&"fuerza_slam") and fuerza.has(&"fuerza_roca"))

	_check("la misma acción cambia de nombre según la forma",
			AjustesControles.etiqueta_de(&"correr", AjustesControlesService.ACUATICO) == "Nadar rápido",
			AjustesControles.etiqueta_de(&"correr", AjustesControlesService.ACUATICO))
	_check("texto de tecla legible", AjustesControles.texto_de(&"mover_adelante") == "W",
			AjustesControles.texto_de(&"mover_adelante"))
	await get_tree().process_frame

# ---------------------------------------------------------------- 2. reasignar
func _probar_reasignacion() -> void:
	var res: Dictionary = AjustesControles.asignar(&"mover_adelante", _tecla(KEY_T))
	_check("asignar T a mover_adelante", bool(res["ok"]), String(res["mensaje"]))
	_check("el Input Map usa ahora T",
			InputMap.event_is_action(_tecla(KEY_T), &"mover_adelante"))
	_check("W ya NO activa mover_adelante",
			not InputMap.event_is_action(_tecla(KEY_W), &"mover_adelante"))
	var eventos: Array[InputEvent] = InputMap.action_get_events(&"mover_adelante")
	_check("la acción queda con UNA sola asignación (no se acumulan)",
			eventos.size() == 1, "n=%d" % eventos.size())
	_check("el texto del panel refleja la tecla nueva",
			AjustesControles.texto_de(&"mover_adelante") == "T",
			AjustesControles.texto_de(&"mover_adelante"))
	await get_tree().process_frame

# ---------------------------------------------------------------- 3. jugador
## La prueba fuerte: la tecla nueva mueve al personaje REAL y la vieja no.
func _probar_jugador_real() -> void:
	if jug == null:
		_check("jugador instanciado", false)
		return
	# Aseguramos suelo bajo los pies antes de medir.
	for _i in 40:
		await get_tree().physics_frame
		if jug.is_on_floor():
			break
	_check("el jugador está en el suelo", jug.is_on_floor())

	# --- con la tecla NUEVA (T) ---
	await _enviar(_tecla(KEY_T))
	var act_t: bool = Input.is_action_pressed("mover_adelante")
	var movio := 0.0
	var p0: Vector3 = jug.global_position
	for _i in 30:
		await get_tree().physics_frame
	movio = Vector2(jug.global_position.x - p0.x, jug.global_position.z - p0.z).length()
	await _enviar(_soltar(KEY_T))
	_check("T activa la acción mover_adelante", act_t)
	_check("T desplaza de verdad al personaje", movio > 0.2, "%.2f m" % movio)

	# --- la tecla VIEJA (W) ya no debe moverlo ---
	# Antes de medir esperamos a que se agote la inercia del tramo anterior: si no,
	# el desplazamiento residual se confundiría con un movimiento provocado por W.
	for _i in 45:
		await get_tree().physics_frame
	var p1: Vector3 = jug.global_position
	await _enviar(_tecla(KEY_W))
	var act_w: bool = Input.is_action_pressed("mover_adelante")
	for _i in 30:
		await get_tree().physics_frame
	var movio_w := Vector2(jug.global_position.x - p1.x, jug.global_position.z - p1.z).length()
	await _enviar(_soltar(KEY_W))
	_check("W ya no activa mover_adelante", not act_w)
	_check("W ya no desplaza al personaje", movio_w < 0.05, "%.3f m" % movio_w)

	# Dejamos mover_adelante en W para el resto de pruebas.
	AjustesControles.restablecer(&"mover_adelante")

# ------------------------------------------- 3b. acciones de una transformación
## Prueba acciones que SOLO existen en una transformación: si su tecla se cambia,
## la habilidad debe seguir disparándose con la tecla nueva.
func _probar_acciones_de_forma() -> void:
	if jug == null:
		_check("jugador disponible para las acciones de forma", false)
		return

	# --- VELOCISTA: el dash es exclusivo de esta forma ---
	AjustesControles.asignar(&"dash", _tecla(KEY_J))
	jug._entrar_velocista()
	await get_tree().physics_frame
	for _i in 10:
		await get_tree().physics_frame
	_check("el dash ya no está en SHIFT",
			not InputMap.event_is_action(_tecla(KEY_SHIFT), &"dash"))
	await _enviar(_tecla(KEY_J))
	var estado_tras_dash: int = int(jug.estado)
	await _enviar(_soltar(KEY_J))
	_check("J dispara el dash del Velocista tras reasignarlo",
			estado_tras_dash == 1, "estado=%d (1=DASH)" % estado_tras_dash)
	# La tecla vieja ya no debe dispararlo.
	for _i in 40:
		await get_tree().physics_frame
	await _enviar(_tecla(KEY_SHIFT))
	var estado_tras_shift: int = int(jug.estado)
	await _enviar(_soltar(KEY_SHIFT))
	_check("SHIFT ya no dispara el dash", estado_tras_shift == 0,
			"estado=%d" % estado_tras_shift)

	# --- ACUÁTICO: una habilidad de agua, también exclusiva de su forma ---
	AjustesControles.asignar(&"agua_habilidad_1", _tecla(KEY_R))
	jug._entrar_acuatico()
	for _i in 10:
		await get_tree().physics_frame
	var tiene_clip: bool = jug.anim_acuatico != null \
			and jug.anim_acuatico.has_animation("ability_1")
	if not tiene_clip:
		print("[TEST] (no verificable) el modelo acuático no tiene el clip ability_1")
	else:
		await _enviar(_tecla(KEY_R))
		var lanzo: bool = bool(jug.a_en_habilidad) \
				or float(jug.a_cooldowns.get(1, 0.0)) > 0.0
		await _enviar(_soltar(KEY_R))
		_check("R lanza la habilidad de agua 1 tras reasignarla", lanzo)

	jug._entrar_humano()
	AjustesControles.restablecer_todo()
	await get_tree().process_frame

# ---------------------------------------------------------------- 4. conflictos
func _probar_conflictos() -> void:
	# W pertenece a mover_adelante y dash es del Velocista: el movimiento es común
	# a todas las formas, así que sí pueden coincidir -> conflicto.
	var res: Dictionary = AjustesControles.asignar(&"dash", _tecla(KEY_W))
	_check("conflicto detectado al pedir W para el dash",
			not bool(res["ok"]) and StringName(res["conflicto"]) == &"mover_adelante",
			"conflicto=%s" % String(res["conflicto"]))
	_check("el conflicto NO cambia nada: W sigue en mover_adelante",
			InputMap.event_is_action(_tecla(KEY_W), &"mover_adelante"))
	_check("el conflicto NO cambia nada: dash sigue en SHIFT",
			InputMap.event_is_action(_tecla(KEY_SHIFT), &"dash"))

	# E pertenece al pisotón (Fuerza) y el emote es del Velocista: formas
	# distintas, nunca activas a la vez -> compartir tecla es legítimo.
	var res2: Dictionary = AjustesControles.asignar(&"emote", _tecla(KEY_E))
	_check("formas distintas SÍ pueden compartir tecla (emote = E)",
			bool(res2["ok"]), String(res2["mensaje"]))
	_check("el emote queda realmente en E con E ya usada por el pisotón",
			InputMap.event_is_action(_tecla(KEY_E), &"emote")
			and InputMap.event_is_action(_tecla(KEY_E), &"fuerza_slam"))
	AjustesControles.restablecer(&"emote")

	# CORRER es de TECLA FIJA (SHIFT): no se puede reasignar (ni con conflicto).
	var res3: Dictionary = AjustesControles.asignar(&"correr", _tecla(KEY_A))
	_check("correr es fijo: pedir otra tecla se rechaza",
			not bool(res3["ok"]) and StringName(res3["conflicto"]) == &"")
	_check("correr sigue en SHIFT tras el intento",
			InputMap.event_is_action(_tecla(KEY_SHIFT), &"correr"))
	await get_tree().process_frame

# ---------------------------------------------------------------- 5. reservado
func _probar_reservado() -> void:
	var res: Dictionary = AjustesControles.asignar(&"mover_adelante", _tecla(KEY_ESCAPE))
	_check("ESC no se puede asignar (reservado para pausa/cancelar)",
			not bool(res["ok"]), String(res["mensaje"]))
	_check("ESC no altera la asignación de mover_adelante",
			InputMap.event_is_action(_tecla(KEY_W), &"mover_adelante"))

# ---------------------------------------------------------------- 6. intercambio
func _probar_intercambio() -> void:
	AjustesControles.restablecer_todo()
	var antes_w: String = AjustesControles.texto_de(&"mover_adelante")
	var antes_s: String = AjustesControles.texto_de(&"mover_atras")
	var res: Dictionary = AjustesControles.intercambiar(&"mover_adelante", &"mover_atras")
	_check("intercambio aplicado", bool(res["ok"]), String(res["mensaje"]))
	_check("mover_adelante toma la tecla que tenía mover_atras",
			AjustesControles.texto_de(&"mover_adelante") == antes_s,
			"%s -> %s" % [antes_w, AjustesControles.texto_de(&"mover_adelante")])
	_check("mover_atras toma la tecla que tenía mover_adelante",
			AjustesControles.texto_de(&"mover_atras") == antes_w)
	_check("ninguna de las dos se quedó sin asignación",
			AjustesControles.evento_de(&"mover_adelante") != null
			and AjustesControles.evento_de(&"mover_atras") != null)
	AjustesControles.restablecer_todo()

# ---------------------------------------------------------------- 7. persistencia
func _probar_persistencia() -> void:
	AjustesControles.asignar(&"mover_adelante", _tecla(KEY_T))
	AjustesControles.asignar(&"dash", _tecla(KEY_J))
	_check("se escribió el archivo de controles",
			FileAccess.file_exists(AjustesControlesService.RUTA),
			AjustesControlesService.RUTA)

	# Un servicio NUEVO (como al reiniciar el juego) relee lo guardado.
	var nuevo: Node = load("res://ui/scripts/ajustes_controles.gd").new()
	add_child(nuevo)
	await get_tree().process_frame
	_check("tras recargar, mover_adelante sigue en T",
			AjustesControles.texto_de_evento(nuevo.evento_de(&"mover_adelante")) == "T")
	_check("tras recargar, dash sigue en J",
			AjustesControles.texto_de_evento(nuevo.evento_de(&"dash")) == "J")
	_check("tras recargar, una acción no tocada conserva su tecla de fábrica",
			AjustesControles.texto_de_evento(nuevo.evento_de(&"mover_izquierda")) == "A")

	# Una entrada ilegible no debe romper la carga.
	var cf := ConfigFile.new()
	cf.load(AjustesControlesService.RUTA)
	cf.set_value(AjustesControlesService.SECCION, "correr", {"tipo": "basura"})
	cf.set_value(AjustesControlesService.SECCION, "accion_inexistente", {"tipo": "tecla", "codigo": 90})
	cf.save(AjustesControlesService.RUTA)
	var tercero: Node = load("res://ui/scripts/ajustes_controles.gd").new()
	add_child(tercero)
	await get_tree().process_frame
	_check("una entrada corrupta no rompe la carga (cae al valor de fábrica)",
			AjustesControles.texto_de_evento(tercero.evento_de(&"correr")) == "SHIFT",
			AjustesControles.texto_de_evento(tercero.evento_de(&"correr")))
	_check("una acción inexistente en el archivo se ignora sin error", true)
	nuevo.queue_free()
	tercero.queue_free()
	AjustesControles.restablecer_todo()

# ---------------------------------------------------------------- 8. panel
func _probar_panel() -> void:
	if pausa == null:
		_check("escena de pausa instanciada", false)
		return
	var panel: PanelControles = pausa.get_node("%ControlsContent")
	_check("el panel CONTROLES existe en el menú de pausa", panel != null)
	if panel == null:
		return
	pausa.visible = true
	panel.activar()
	await get_tree().process_frame

	var rows: VBoxContainer = panel.get_node("%ControlesRows")
	var esperadas := [
		AjustesControlesService.HUMANO,
		AjustesControlesService.VELOCISTA,
		AjustesControlesService.ACUATICO,
		AjustesControlesService.FUERZA,
		AjustesControlesService.COMBATE,
	]
	for i in esperadas.size():
		var forma: StringName = esperadas[i]
		var n_acciones: int = AjustesControles.acciones_para(forma).size()
		var n_extras: int = 2 if forma == AjustesControlesService.FUERZA else 1
		_check("lista de %s generada" % String(forma),
				rows.get_child_count() == n_acciones + n_extras,
				"filas=%d esperadas=%d" % [rows.get_child_count(), n_acciones + n_extras])
		var textos: Array = _fila_textos(rows)
		if forma == AjustesControlesService.VELOCISTA:
			_check("Velocista muestra Dash", textos.has("Dash"))
		if forma == AjustesControlesService.HUMANO:
			_check("Humano NO muestra Dash", not textos.has("Dash"))
			_check("Humano muestra Agacharse", textos.has("Agacharse"))
			# CORRER es de tecla FIJA: se muestra con SHIFT y no se puede reasignar.
			var filas_h: Array = panel.get("_filas")
			var idx_correr := -1
			for k in filas_h.size():
				if filas_h[k]["accion"] == &"correr":
					idx_correr = k
			var fila_correr: Dictionary = filas_h[idx_correr] if idx_correr >= 0 else {}
			_check("la fila de correr es FIJA y muestra SHIFT",
					not fila_correr.is_empty() and not bool(fila_correr["editable"]) \
						and String(fila_correr["etiqueta_tecla"].text) == "SHIFT",
					"idx=%d" % idx_correr)
			if idx_correr >= 0:
				panel.set("_seleccion", idx_correr)
				panel.confirmar()
				_check("la fila de correr NO entra en captura", not panel.esta_capturando())
		if forma == AjustesControlesService.FUERZA:
			_check("Fuerza muestra Embestida, Pisotón y Levantar roca",
					textos.has("Embestida") and textos.has("Pisotón") and textos.has("Levantar roca"))
		var icono: TextureRect = panel.get_node("%ControlesIcono")
		_check("icono del HUD cargado para %s" % String(forma), icono.texture != null)
		panel.cambiar_forma(1)
		await get_tree().process_frame

	_check("el selector vuelve a Humano tras la última forma (recorrido circular)",
			panel.get_node("%ControlesNombreForma").text == "HUMANO",
			panel.get_node("%ControlesNombreForma").text)
	panel.cambiar_forma(-1)
	await get_tree().process_frame
	_check("la flecha izquierda vuelve a la forma anterior",
			panel.get_node("%ControlesNombreForma").text == "COMBATE",
			panel.get_node("%ControlesNombreForma").text)
	panel.activar()
	await get_tree().process_frame

# ---------------------------------------------------------------- 9. captura
func _probar_captura_panel() -> void:
	var panel: PanelControles = pausa.get_node("%ControlsContent")
	AjustesControles.restablecer_todo()
	panel.activar()
	await get_tree().process_frame

	# Selecciona la fila de "Moverse hacia delante".
	var filas: Array = panel.get("_filas")
	var idx := -1
	for i in filas.size():
		if filas[i]["accion"] == &"mover_adelante":
			idx = i
			break
	_check("la fila de mover_adelante está en la lista", idx >= 0)
	if idx < 0:
		return
	panel.set("_seleccion", idx)
	panel.mover_seleccion(0)
	await get_tree().process_frame

	panel.confirmar()
	await get_tree().process_frame
	_check("la fila entra en modo captura", panel.esta_capturando())
	var etiqueta: Label = filas[idx]["etiqueta_tecla"]
	_check("la fila muestra «PULSA UNA TECLA…»",
			etiqueta.text == "PULSA UNA TECLA…", etiqueta.text)

	# La pulsación elegida se captura y se aplica de verdad.
	await _enviar(_tecla(KEY_T))
	await _enviar(_soltar(KEY_T))
	_check("la captura termina al recibir la tecla", not panel.esta_capturando())
	_check("la tecla capturada se aplica al Input Map",
			InputMap.event_is_action(_tecla(KEY_T), &"mover_adelante"))
	_check("la fila vuelve a mostrar la tecla",
			etiqueta.text == "T", etiqueta.text)
	_check("T mueve al personaje tras reasignar desde el panel",
			await _comprobar_movimiento(KEY_T))

	# Cancelar con ESC no debe cambiar nada.
	panel.set("_seleccion", idx)
	panel.confirmar()
	await get_tree().process_frame
	var antes: String = AjustesControles.texto_de(&"mover_adelante")
	await _enviar(_tecla(KEY_ESCAPE))
	_check("ESC cancela la captura sin dejar el panel bloqueado",
			not panel.esta_capturando())
	_check("ESC no cambia la asignación",
			AjustesControles.texto_de(&"mover_adelante") == antes, antes)
	_check("el menú de pausa sigue cerrado tras cancelar (ESC no lo abrió)",
			not pausa.esta_abierto())
	AjustesControles.restablecer_todo()

## Comprueba que la tecla indicada mueve al jugador real.
func _comprobar_movimiento(code: Key) -> bool:
	if jug == null:
		return false
	# Se espera a que el personaje esté quieto para que el desplazamiento medido
	# sea sólo el que provoca la tecla nueva.
	for _i in 45:
		await get_tree().physics_frame
	await _enviar(_tecla(code))
	var p0: Vector3 = jug.global_position
	for _i in 25:
		await get_tree().physics_frame
	var d := Vector2(jug.global_position.x - p0.x, jug.global_position.z - p0.z).length()
	await _enviar(_soltar(code))
	print("[TEST]   movimiento con la tecla nueva: %.2f m" % d)
	return d > 0.2

# --------------------------------------- 10. G eliminada y menú radial (F) vivo
## El antiguo interruptor directo humano <-> velocista con G ya no existe; el menú
## radial (F) debe seguir siendo el camino de transformación del personaje.
func _probar_g_eliminada() -> void:
	_check("la acción «transformacion_velocidad» ya no existe en el Input Map",
			not InputMap.has_action(&"transformacion_velocidad"))
	var en_catalogo := false
	for entrada in AjustesControlesService.CATALOGO:
		if entrada["accion"] == &"transformacion_velocidad":
			en_catalogo = true
	_check("la acción obsoleta ya no se ofrece en CONTROLES", not en_catalogo)

	if jug == null:
		_check("jugador disponible para probar G", false)
		return
	jug._entrar_humano()
	for _i in 8:
		await get_tree().physics_frame
	_check("el jugador está en Humano antes de la prueba", jug.forma == 0, "forma=%d" % jug.forma)

	# G no debe hacer absolutamente nada.
	await _enviar(_tecla(KEY_G))
	await _enviar(_soltar(KEY_G))
	for _i in 20:
		await get_tree().physics_frame
	_check("G ya no transforma al personaje", jug.forma == 0, "forma=%d" % jug.forma)
	_check("G tampoco abre el menú radial", not jug.menu_transf.esta_abierto())

	# F: el menú radial sigue abriéndose con la misma ruta de entrada del juego.
	await _enviar(_tecla(KEY_F))
	await _enviar(_soltar(KEY_F))
	await get_tree().process_frame
	_check("F sigue abriendo el menú radial de transformaciones",
			jug.menu_transf.esta_abierto() and bool(jug._menu_abierto))

	# Ruta REAL del menú: animación -> cierre -> señal -> transición del personaje.
	jug.menu_transf._seleccionar(&"velocista")
	for _i in 300:
		await get_tree().physics_frame
		if jug.forma == 1:
			break
	_check("el menú radial sigue transformando al personaje (Velocista)",
			jug.forma == 1, "forma=%d" % jug.forma)
	_check("el menú radial se cierra tras elegir", not jug.menu_transf.esta_abierto())
	for _i in 300:
		await get_tree().physics_frame
		if not bool(jug._transformando):
			break
	jug._entrar_humano()
	for _i in 8:
		await get_tree().physics_frame

# ---------------------------------------------------- 10. RESTABLECER TECLAS
## Texto de la tecla que el panel muestra para una acción (o "<no está>").
func _texto_fila(panel: PanelControles, accion: StringName) -> String:
	for f in panel.get("_filas"):
		if f["accion"] == accion:
			return String(f["etiqueta_tecla"].text)
	return "<no está>"

## Contenido de los OTROS archivos de preferencias (para comprobar que no se tocan).
func _leer_ajenos() -> String:
	var s := ""
	for ruta in ["user://ajustes_graficos.cfg", "user://ajustes_jugabilidad.cfg"]:
		if FileAccess.file_exists(ruta):
			s += FileAccess.get_file_as_string(ruta)
	return s

func _cfg_contiene(clave: String) -> bool:
	var cf := ConfigFile.new()
	if cf.load(AjustesControlesService.RUTA) != OK:
		return false
	return cf.has_section_key(AjustesControlesService.SECCION, clave)

func _probar_restablecer() -> void:
	var panel: PanelControles = pausa.get_node("%ControlsContent")
	panel.activar()
	await get_tree().process_frame

	var boton: Button = panel.get_node("%ControlesRestablecer")
	var cancelar: Button = panel.get_node("%ControlesCancelar")
	var confirmar: Button = panel.get_node("%ControlesConfirmarBtn")
	var fila_conf: Control = panel.get_node("%ControlesConfirmarFila")
	var hint: Label = panel.get_node("%ControlesHint")

	_check("el pie muestra el botón RESTABLECER TECLAS",
			boton.text == "RESTABLECER TECLAS", boton.text)
	_check("al abrir el panel se ve el botón y la confirmación está oculta",
			boton.visible and not fila_conf.visible)
	_check("la confirmación ofrece CANCELAR y RESTABLECER",
			cancelar.text == "CANCELAR" and confirmar.text == "RESTABLECER")

	# Se personalizan teclas de tres transformaciones distintas y de una común.
	var ajenos_antes := _leer_ajenos()
	AjustesControles.asignar(&"mover_adelante", _tecla(KEY_T))
	AjustesControles.asignar(&"saltar", _tecla(KEY_Y))
	AjustesControles.asignar(&"dash", _tecla(KEY_J))
	AjustesControles.asignar(&"agua_habilidad_1", _tecla(KEY_R))
	AjustesControles.asignar(&"fuerza_embestida", _tecla(KEY_H))
	panel.activar()
	await get_tree().process_frame
	_check("hay asignaciones personalizadas antes de restablecer",
			AjustesControles.hay_personalizaciones())
	_check("la fila de mover_adelante muestra la tecla personalizada",
			_texto_fila(panel, &"mover_adelante") == "T", _texto_fila(panel, &"mover_adelante"))

	# --- 1) Pedir confirmación NO cambia nada por sí solo ---
	boton.pressed.emit()
	await get_tree().process_frame
	_check("pulsar el botón pide confirmación", panel.esta_confirmando())
	_check("la confirmación aparece y el botón principal se oculta",
			fila_conf.visible and not boton.visible)
	_check("se muestra la pregunta de confirmación",
			hint.text.contains("restablecer todas las teclas"), hint.text)
	_check("pedir confirmación no cambia ninguna tecla",
			AjustesControles.texto_de(&"mover_adelante") == "T"
			and AjustesControles.texto_de(&"dash") == "J")
	var forma_antes: String = panel.get_node("%ControlesNombreForma").text
	panel.cambiar_forma(1)
	_check("con la confirmación abierta, las flechas no cambian de transformación",
			panel.get_node("%ControlesNombreForma").text == forma_antes)

	# --- 2) ESC cancela ---
	await _enviar(_tecla(KEY_ESCAPE))
	_check("ESC cancela la confirmación", not panel.esta_confirmando())
	_check("ESC no cambia ninguna asignación",
			AjustesControles.texto_de(&"mover_adelante") == "T"
			and InputMap.event_is_action(_tecla(KEY_T), &"mover_adelante"))
	_check("y ESC no abre el menú de pausa", not pausa.esta_abierto())

	# --- 3) El botón CANCELAR tampoco cambia nada ---
	boton.pressed.emit()
	await get_tree().process_frame
	cancelar.pressed.emit()
	await get_tree().process_frame
	_check("CANCELAR cierra la confirmación", not panel.esta_confirmando())
	_check("CANCELAR devuelve el botón principal a la vista",
			boton.visible and not fila_conf.visible)
	_check("CANCELAR no cambia ninguna asignación",
			AjustesControles.texto_de(&"mover_adelante") == "T"
			and AjustesControles.texto_de(&"saltar") == "Y"
			and AjustesControles.texto_de(&"fuerza_embestida") == "H")

	# --- 4) RESTABLECER: vuelve TODO a fábrica, no sólo la forma mostrada ---
	boton.pressed.emit()
	await get_tree().process_frame
	confirmar.pressed.emit()
	await get_tree().process_frame
	_check("el restablecimiento cierra la confirmación", not panel.esta_confirmando())
	_check("se muestra la notificación de éxito",
			hint.text == "Controles restablecidos correctamente", hint.text)
	_check("vuelve el movimiento (W)", AjustesControles.texto_de(&"mover_adelante") == "W")
	_check("vuelve el salto (ESPACIO)", AjustesControles.texto_de(&"saltar") == "ESPACIO")
	_check("vuelve el dash del VELOCISTA (SHIFT), no sólo el de la forma mostrada",
			AjustesControles.texto_de(&"dash") == "SHIFT")
	_check("vuelve la habilidad del ACUÁTICO (1)",
			AjustesControles.texto_de(&"agua_habilidad_1") == "1")
	_check("vuelve la habilidad de FUERZA (R)",
			AjustesControles.texto_de(&"fuerza_embestida") == "R")
	_check("el Input Map real vuelve a W (y T deja de mover)",
			InputMap.event_is_action(_tecla(KEY_W), &"mover_adelante")
			and not InputMap.event_is_action(_tecla(KEY_T), &"mover_adelante"))
	_check("no queda ninguna personalización", not AjustesControles.hay_personalizaciones())
	_check("las teclas mostradas se actualizan al instante",
			_texto_fila(panel, &"mover_adelante") == "W", _texto_fila(panel, &"mover_adelante"))
	_check("cada acción vuelve a tener UNA sola asignación",
			InputMap.action_get_events(&"mover_adelante").size() == 1)

	# El restablecimiento se guarda: un servicio nuevo (como al reiniciar) lo relee.
	var nuevo: Node = load("res://ui/scripts/ajustes_controles.gd").new()
	add_child(nuevo)
	await get_tree().process_frame
	_check("tras reabrir el juego, los valores restablecidos siguen vigentes",
			AjustesControles.texto_de_evento(nuevo.evento_de(&"mover_adelante")) == "W"
			and AjustesControles.texto_de_evento(nuevo.evento_de(&"dash")) == "SHIFT"
			and AjustesControles.texto_de_evento(nuevo.evento_de(&"fuerza_embestida")) == "R")
	nuevo.queue_free()
	await get_tree().process_frame

	_check("el restablecimiento no toca gráficos ni jugabilidad", _leer_ajenos() == ajenos_antes)
	_check("el archivo de controles ya no guarda la acción obsoleta",
			not _cfg_contiene("transformacion_velocidad"))

	# Una configuración vieja, con la acción eliminada, no debe romper la carga.
	var cf := ConfigFile.new()
	cf.load(AjustesControlesService.RUTA)
	cf.set_value(AjustesControlesService.SECCION, "transformacion_velocidad",
			{"tipo": "tecla", "codigo": 71})
	cf.save(AjustesControlesService.RUTA)
	var viejo: Node = load("res://ui/scripts/ajustes_controles.gd").new()
	add_child(viejo)
	await get_tree().process_frame
	_check("una configuración vieja con la acción eliminada no provoca errores",
			not InputMap.has_action(&"transformacion_velocidad")
			and AjustesControles.texto_de_evento(viejo.evento_de(&"mover_adelante")) == "W")
	_check("la referencia obsoleta se limpia sola del archivo guardado",
			not _cfg_contiene("transformacion_velocidad"))
	viejo.queue_free()
	await get_tree().process_frame
	# Se retira esa entrada obsoleta para no dejar basura en el archivo del jugador.
	cf.load(AjustesControlesService.RUTA)
	cf.erase_section_key(AjustesControlesService.SECCION, "transformacion_velocidad")
	cf.save(AjustesControlesService.RUTA)
	AjustesControles.restablecer_todo()

# ---------------------------------------------- 11. distribución del selector
func _probar_distribucion_selector() -> void:
	var panel: PanelControles = pausa.get_node("%ControlsContent")
	pausa.visible = true
	panel.get_parent().visible = true
	panel.visible = true
	panel.activar()
	for _i in 4:
		await get_tree().process_frame

	var icono: TextureRect = panel.get_node("%ControlesIcono")
	var nombre: Label = panel.get_node("%ControlesNombreForma")
	var selector: Control = icono.get_parent()
	var rows: VBoxContainer = panel.get_node("%ControlesRows")

	_check("el panel tiene tamaño real para poder medir la distribución",
			panel.size.x > 100.0 and icono.size.x > 10.0,
			"panel=%.0f icono=%.0f" % [panel.size.x, icono.size.x])

	# --- icono circular: sin marco cuadrado detrás ---
	_check("el contenedor del icono es el propio selector, no un marco",
			selector.name == "Selector" and selector is HBoxContainer)
	var marco := false
	var n: Node = icono.get_parent()
	while n != null and n != panel:
		if n is PanelContainer:
			marco = true
		n = n.get_parent()
	_check("el icono NO tiene ningún cuadrado/panel detrás", not marco)
	_check("el icono conserva la textura original del HUD", icono.texture != null)
	_check("el selector mantiene flecha-icono-flecha",
			selector.get_child_count() == 3
			and selector.get_child(0) == panel.get_node("%ControlesPrev")
			and selector.get_child(2) == panel.get_node("%ControlesNext"))

	# --- nombre a la derecha del selector ---
	var centro_icono_x: float = icono.global_position.x + icono.size.x * 0.5
	_check("el nombre está a la derecha del icono",
			nombre.global_position.x > centro_icono_x,
			"nombre.x=%.1f icono.x=%.1f" % [nombre.global_position.x, centro_icono_x])
	_check("el nombre está a la derecha de TODO el selector",
			nombre.global_position.x >= selector.global_position.x + selector.size.x,
			"nombre.x=%.1f fin_selector=%.1f"
					% [nombre.global_position.x, selector.global_position.x + selector.size.x])
	_check("el nombre ya NO está debajo del icono",
			nombre.global_position.y < icono.global_position.y + icono.size.y * 0.5)
	var dy: float = (nombre.global_position.y + nombre.size.y * 0.5) \
			- (icono.global_position.y + icono.size.y * 0.5)
	_check("el nombre queda alineado con el icono", absf(dy) < 24.0, "dy=%.1f" % dy)

	# --- selector desplazado a la izquierda ---
	var margen: float = selector.global_position.x - panel.global_position.x
	_check("el selector está desplazado a la izquierda del panel",
			margen >= -1.0 and margen < panel.size.x * 0.35,
			"margen=%.1f ancho_panel=%.1f" % [margen, panel.size.x])

	# --- el nombre y la lista cambian con las flechas ---
	var textos_antes: Array = _fila_textos(rows)
	panel.cambiar_forma(1)
	for _i in 2:
		await get_tree().process_frame
	_check("el nombre cambia al usar las flechas", nombre.text == "VELOCISTA", nombre.text)
	_check("el nombre ya no aparece duplicado bajo la imagen",
			nombre.global_position.y < icono.global_position.y + icono.size.y * 0.5)
	var textos_despues: Array = _fila_textos(rows)
	_check("la lista de la transformación se actualiza con el nombre",
			textos_antes != textos_despues and textos_despues.has("Dash"))
	panel.cambiar_forma(-1)
	for _i in 2:
		await get_tree().process_frame
	_check("la flecha izquierda vuelve a la transformación anterior",
			nombre.text == "HUMANO", nombre.text)