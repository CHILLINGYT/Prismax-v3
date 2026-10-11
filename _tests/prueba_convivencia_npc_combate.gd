extends Node3D

## Suite (ESCENA) de CONVIVENCIA: carga el MUNDO REAL (`ziba_prototipo.tscn`) y
## comprueba que todo lo que viene de `main` (ciudad, peatones/NPC, cámara aérea,
## audio) sigue funcionando junto al combate nuevo de esta rama (CombatManager,
## gerente de enemigos con G, vida/escudo por personaje, HUD).
##
##   godot --headless --path . _tests/prueba_convivencia_npc_combate.tscn

const MUNDO := preload("res://ziba/escenas/ziba_prototipo.tscn")
const RUTA_NPC := "res://NPCs/Scripts/npc_citizen.gd"

var _pasadas := 0
var _falladas := 0

func _ready() -> void:
	call_deferred("_correr")

func _check(nombre: String, ok: bool, detalle: String = "") -> void:
	var sufijo := (" — " + detalle) if detalle != "" else ""
	if ok:
		_pasadas += 1
		print("[OK]    ", nombre, sufijo)
	else:
		_falladas += 1
		print("[FALLA] ", nombre, sufijo)

func _esperar(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame

func _esperar_seg(s: float) -> void:
	await _esperar(int(ceil(s * 60.0)))

func _contar_npc(n: Node) -> int:
	var c := 0
	var s: Script = n.get_script() as Script
	if s != null and String(s.resource_path).ends_with("npc_citizen.gd"):
		c += 1
	for h in n.get_children():
		c += _contar_npc(h)
	return c

func _buscar(nombre: String) -> Node:
	return get_tree().root.find_child(nombre, true, false)

## Tecla REAL G: el gerente de enemigos la lee por `_unhandled_input`
## (`event.is_action_pressed("enemigos_prueba")`), así que `Input.action_press` NO
## llega ahí: hay que sintetizar el evento de teclado, como en el juego.
func _tecla_g(pulsada: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_G
	ev.pressed = pulsada
	Input.parse_input_event(ev)

func _pulsar_g() -> void:
	_tecla_g(true)
	await _esperar(4)
	_tecla_g(false)
	await _esperar_seg(2)

func _correr() -> void:
	print("=== PRUEBA: convivencia mundo (NPC/ciudad/audio) + combate nuevo ===")
	var mundo := MUNDO.instantiate()
	add_child(mundo)
	# La ciudad y los peatones se generan al arrancar: se les da tiempo real.
	await _esperar_seg(8)

	# --- 1) piezas del mundo de main ---------------------------------------
	_check("la escena principal sigue siendo IntroVideo",
			ProjectSettings.get_setting("application/run/main_scene") == "res://ui/scenes/IntroVideo.tscn",
			str(ProjectSettings.get_setting("application/run/main_scene")))
	_check("existe el autoload de audio de main (AjustesAudio)",
			get_node_or_null("/root/AjustesAudio") != null)
	_check("el mundo tiene la cámara aérea de main", _buscar("CamaraAerea") != null)
	_check("el mundo tiene la ciudad y su generador", _buscar("Ciudad") != null)
	var hud := get_tree().get_first_node_in_group("hud_juego")
	_check("el jugador tiene su HUD", hud != null)

	# --- 2) peatones / NPC reales ------------------------------------------
	var npcs_inicial := _contar_npc(self)
	var director := _buscar("DirectorPeatones")
	if director == null:
		var ciudad := _buscar("Ciudad")
		if ciudad != null:
			director = ciudad.get("director_peatones")
	var resumen: Dictionary = {}
	if director != null and is_instance_valid(director) and director.has_method("resumen"):
		resumen = director.call("resumen")
	print("[DIAG] peatones generados=%d | resumen del director=%s" % [npcs_inicial, str(resumen)])
	_check("se generan peatones (NPC) en la ciudad", npcs_inicial > 0, "npc=%d" % npcs_inicial)

	# --- 3) combate nuevo integrado ----------------------------------------
	_check("el mundo integra el CombatManager",
			get_tree().get_first_node_in_group("combat_manager") != null)
	_check("el mundo integra el gerente de enemigos (G)", _buscar("EnemigosPrueba") != null)
	var jug := get_tree().get_first_node_in_group("player")
	_check("el mundo tiene al jugador", jug != null)
	var stats: Node = null
	if jug != null:
		stats = jug.get_node_or_null("Estadisticas")
	_check("el jugador lleva su sistema de vida/escudo", stats != null)

	# G: grupo de enemigos de prueba, sin perder ningún NPC
	await _pulsar_g()
	var enemigos := get_tree().get_nodes_in_group("enemigos_prueba").size()
	var npcs_tras := _contar_npc(self)
	_check("G genera el grupo de enemigos de prueba", enemigos == 6, "enemigos=%d" % enemigos)
	_check("los peatones siguen ahí tras generar enemigos", npcs_tras == npcs_inicial,
			"antes=%d ahora=%d" % [npcs_inicial, npcs_tras])

	# --- 4) vida/escudo por personaje responden con todo el mundo cargado ---
	if stats != null:
		var v0: float = stats.get("vida")
		var e0: float = stats.get("resistencia")
		stats.call("recibir_danio", 20.0)
		var v1: float = stats.get("vida")
		var e1: float = stats.get("resistencia")
		_check("el daño real baja escudo/vida del personaje activo",
				e1 < e0 or v1 < v0, "vida %.1f→%.1f escudo %.1f→%.1f" % [v0, v1, e0, e1])
		_check("el personaje activo es el humano con sus máximos propios",
				String(stats.call("forma_actual")) == "humano" and is_equal_approx(v1 + e1, v0 + e0 - 20.0),
				"forma=%s" % String(stats.call("forma_actual")))

	# --- 5) retirar el grupo (la ciudad sigue en pie) -----------------------
	await _pulsar_g()
	_check("G retira el grupo sin dejar enemigos colgados",
			get_tree().get_nodes_in_group("enemigos_prueba").is_empty(),
			"quedan=%d" % get_tree().get_nodes_in_group("enemigos_prueba").size())
	_check("los peatones siguen intactos al final", _contar_npc(self) == npcs_inicial,
			"npc=%d" % _contar_npc(self))

	print("=== RESULTADO: %d OK, %d FALLOS ===" % [_pasadas, _falladas])
	get_tree().quit(1 if _falladas > 0 else 0)