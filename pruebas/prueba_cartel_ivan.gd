extends Node3D
## PRUEBAS del CARTEL DE IVÁN (Tarea 5): el aviso contextual "E — Hablar con Iván"
## y el cartel de objetivo ("habla con el hombre en la plaza").
##
## Lo que se comprueba EN VIVO, con el NPC y el cartel de verdad:
##  1. el aviso existe y lleva su texto;
##  2. FUERA de rango NO se ve (ni al empezar ni al alejarse: es el fallo reportado);
##  3. dentro de rango se ve, y SIN pulsar la tecla no pasa nada más;
##  4. pulsar E FUERA de rango no abre nada y no deja el aviso colgado;
##  5. pulsar E dentro de rango abre la conversación: el aviso se oculta y el cartel
##     de objetivo se da por cumplido;
##  6. al cerrarse la conversación, si el jugador sigue cerca el aviso vuelve (es una
##     invitación a hablar) y al alejarse se oculta otra vez.

const NPC := "res://npcs/Scenes/NPC_Estatico_Obrero.tscn"
const CARTEL := "res://ui/scripts/cartel_objetivo.gd"
const DISTANCIA_CERCA := 2.0
const DISTANCIA_LEJOS := 40.0

var _ok := 0
var _fallos := 0
var _npc: NPCEstaticoObrero
var _jugador: CharacterBody3D
var _aviso: CanvasLayer
var _cartel: CanvasLayer

func _ready() -> void:
	_piso()
	# Ciudad mínima: el NPC necesita encontrar "CiudadGenerada/Parque_N" para
	# plantarse (si no, no queda listo y no hay interacción).
	var ciudad := Node3D.new()
	ciudad.name = "CiudadGenerada"
	add_child(ciudad)
	var parque := StaticBody3D.new()
	parque.name = "Parque_1"
	ciudad.add_child(parque)
	var forma := CollisionShape3D.new()
	var caja := BoxShape3D.new()
	caja.size = Vector3(30, 0.5, 30)
	forma.shape = caja
	parque.add_child(forma)
	parque.position = Vector3(0, -0.25, 0)

	# Jugador de mentira, en el grupo real: al NPC le basta su global_position.
	_jugador = CharacterBody3D.new()
	_jugador.name = "Jugador"
	_jugador.add_to_group(&"player")
	var forma_j := CollisionShape3D.new()
	var capsula := CapsuleShape3D.new()
	capsula.radius = 0.4
	capsula.height = 1.8
	forma_j.shape = capsula
	_jugador.add_child(forma_j)
	add_child(_jugador)

	_npc = (load(NPC) as PackedScene).instantiate() as NPCEstaticoObrero
	_npc.name = "NPC_Estatico_Obrero"
	add_child(_npc)

	# Cartel de objetivo (el mismo script que usa el mundo). Se le da un `owner`
	# para que encuentre la raíz igual que en la escena real.
	_cartel = CanvasLayer.new()
	_cartel.set_script(load(CARTEL))
	_cartel.name = "CartelObjetivo"
	add_child(_cartel)
	_cartel.owner = self

	await get_tree().create_timer(1.2).timeout   # que el NPC busque plaza y se plante
	_aviso = _npc.get_node_or_null("IndicadorInteraccion") as CanvasLayer

	# ---------- 1. El aviso existe y es el cartel de la interacción ----------
	_check(_npc.is_inside_tree(), "T5 el NPC del objetivo está en la escena")
	_check(_npc.has_method("_actualizar_interaccion"), "T5 el NPC tiene la lógica de interacción")
	_check(_aviso != null, "T5 existe el aviso contextual (IndicadorInteraccion)")
	var etiqueta := _aviso.get_node_or_null("Aviso/Texto") as Label if _aviso != null else null
	_check(etiqueta != null and "Iván" in etiqueta.text,
			"T5 el texto sigue siendo el de Iván (%s)" % (etiqueta.text if etiqueta != null else "—"))

	# ---------- 2. FUERA de rango: no se ve --------------------------------
	_alejar()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(not _aviso.visible, "T5 con el jugador LEJOS el aviso NO se ve")

	# ---------- 3. Dentro de rango: se ve; sin pulsar tecla no pasa nada ----
	_acercar()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(_aviso.visible, "T5 con el jugador CERCA el aviso se ve (invita a pulsar E)")
	var globo_antes := _globo()
	await get_tree().create_timer(0.8).timeout
	_check(_globo() == globo_antes, "T5 sin pulsar la tecla no se abre ninguna conversación")
	_check(_aviso.visible, "T5 y el aviso sigue donde estaba (no se cuelga ni parpadea)")

	# ---------- 4. Pulsar E FUERA de rango: nada ---------------------------
	_alejar()
	# Dos fotogramas: `process_frame` se emite ANTES de los `_process` de los nodos,
	# así que con uno solo se lee la visibilidad del fotograma anterior.
	await get_tree().process_frame
	await get_tree().process_frame
	_check(not _aviso.visible, "T5 al ALEJARSE el aviso se oculta (fallo reportado)")
	await _pulsar_interactuar()
	await get_tree().process_frame
	_check(_globo() == null, "T5 pulsar E fuera de rango NO abre la conversación")
	_check(not _aviso.visible, "T5 y el aviso sigue oculto (no se queda colgado fuera de rango)")

	# ---------- 5. Pulsar E dentro de rango: conversación ------------------
	_acercar()
	await get_tree().process_frame
	var senal := [false]
	_npc.dialogo_iniciado.connect(func() -> void: senal[0] = true)
	await _pulsar_interactuar()
	await get_tree().create_timer(0.4).timeout
	var globo := _globo()
	_check(globo != null, "T5 pulsar E dentro de rango abre la conversación con Iván")
	_check(senal[0], "T5 y avisa del objetivo cumplido (señal dialogo_iniciado)")
	_check(not _aviso.visible, "T5 durante la conversación el aviso está oculto")
	_check(not _cartel.visible, "T5 el cartel de objetivo ('habla con el hombre en la plaza') desaparece")

	# ---------- 6. Al cerrarse: vuelve el aviso si sigue cerca -------------
	if globo != null and is_instance_valid(globo):
		globo.queue_free()
		if globo.has_signal("cerrado"):
			globo.emit_signal("cerrado")
	await get_tree().create_timer(0.4).timeout
	_check(_globo() == null, "T5 al cerrarse la conversación el NPC olvida la referencia al globo")
	_check(_aviso.visible, "T5 con el jugador todavía cerca, el aviso reaparece")
	_alejar()
	await get_tree().create_timer(0.3).timeout
	_check(not _aviso.visible, "T5 y al volver a alejarse se oculta otra vez")

	print("==================== CARTEL IVÁN: %d OK / %d FALLO ====================" % [_ok, _fallos])
	await get_tree().create_timer(0.5).timeout


# ------------------------------------------------------------------ auxiliares
func _acercar() -> void:
	_jugador.global_position = _npc.global_position + Vector3(0.0, 0.0, DISTANCIA_CERCA)

func _alejar() -> void:
	_jugador.global_position = _npc.global_position + Vector3(0.0, 0.0, DISTANCIA_LEJOS)

## Globo de diálogo abierto del NPC (null si no hay ninguno).
func _globo() -> Node:
	var g: Variant = _npc.get("_globo")
	return g as Node if g is Node and is_instance_valid(g) else null


func _pulsar_interactuar() -> void:
	Input.action_press(&"interactuar")
	await get_tree().process_frame
	await get_tree().process_frame
	Input.action_release(&"interactuar")
	await get_tree().process_frame


func _check(condicion: bool, texto: String) -> void:
	if condicion:
		_ok += 1
		print("[ivan-suite] OK   ", texto)
	else:
		_fallos += 1
		print("[ivan-suite] FALLO ", texto)


func _piso() -> void:
	var cuerpo := StaticBody3D.new()
	var forma := CollisionShape3D.new()
	var caja := BoxShape3D.new()
	caja.size = Vector3(200, 0.5, 200)
	forma.shape = caja
	cuerpo.add_child(forma)
	cuerpo.position = Vector3(0, -0.25, 0)
	add_child(cuerpo)
	var luz := DirectionalLight3D.new()
	luz.rotation = Vector3(-0.9, 0.6, 0.0)
	add_child(luz)
	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 3.0, 12.0)
	cam.current = true
	add_child(cam)