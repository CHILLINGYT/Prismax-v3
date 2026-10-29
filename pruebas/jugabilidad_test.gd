extends Node3D

# Arnés de prueba del panel JUGABILIDAD y de sus efectos reales:
#   · sensibilidad del ratón aplicada por la cámara (CamaraZiba),
#   · inversión del eje vertical (solo vertical),
#   · grupo `hud_juego` que controla OCULTAR INTERFAZ,
#   · persistencia en user://ajustes_jugabilidad.cfg y límites del valor.
#
# No forma parte del juego: vive en res://pruebas/ y se ejecuta solo con run_scene.
# Al terminar deja los ajustes en un estado razonable (5, sin invertir, HUD visible).

const CAMARA := preload("res://personaje/base/camara/camara_jugador.gd")
const JUGADOR := preload("res://personaje/base/escenas/leo_jugador.tscn")

const BASE := 0.0025      # sensibilidad base de CamaraZiba
const TOL := 0.0005
const DX := 200.0
const DY := 100.0

var _ok := 0
var _fail := 0
var _J: Node

func _listo(nombre: String, ok: bool, detalle: String) -> void:
	if ok:
		_ok += 1
	else:
		_fail += 1
	print("[TEST] %s :: %s | %s" % ["OK" if ok else "FALLO", nombre, detalle])

## Aplica un movimiento de ratón al controlador de cámara y devuelve
## (yaw, pitch_objetivo) resultantes.
func _giro(cam: Node3D, dx: float, dy: float) -> Vector2:
	cam.rotation = Vector3.ZERO
	cam._pitch_obj = 0.0
	var ev := InputEventMouseMotion.new()
	ev.relative = Vector2(dx, dy)
	cam._unhandled_input(ev)
	return Vector2(cam.rotation.y, cam._pitch_obj)

func _ready() -> void:
	_J = get_node_or_null("/root/AjustesJugabilidad")
	_listo("autoload AjustesJugabilidad presente", _J != null, "")
	if _J == null:
		get_tree().quit()
		return
	await get_tree().process_frame

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	await get_tree().process_frame
	_listo("ratón capturado para la prueba (guard de la cámara)",
			Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "mode=%d" % Input.mouse_mode)

	var cam := Node3D.new()
	cam.set_script(CAMARA)
	add_child(cam)
	await get_tree().process_frame

	_probar_sensibilidad(cam)
	_probar_inversion(cam)
	await _probar_hud()
	_probar_persistencia()

	print("[TEST] ===== RESUMEN: %d OK, %d FALLOS =====" % [_ok, _fail])
	get_tree().quit()

# ---------------------------------------------------------------- sensibilidad
func _probar_sensibilidad(cam: Node3D) -> void:
	_J.invertir_eje_vertical = false
	var magnitudes := {}
	for nivel in [0, 5, 10]:
		_J.sensibilidad = nivel
		var f := float(nivel + 1) / 6.0
		var g := _giro(cam, DX, DY)
		var esperado_yaw := -DX * BASE * f
		var esperado_pitch := -DY * BASE * f
		_listo("sensibilidad %d: giro horizontal" % nivel, absf(g.x - esperado_yaw) < TOL,
				"yaw=%.4f esperado=%.4f" % [g.x, esperado_yaw])
		_listo("sensibilidad %d: giro vertical" % nivel, absf(g.y - esperado_pitch) < TOL,
				"pitch=%.4f esperado=%.4f" % [g.y, esperado_pitch])
		magnitudes[nivel] = absf(g.x)
	_listo("más sensibilidad = más giro",
			magnitudes[10] > magnitudes[5] and magnitudes[5] > magnitudes[0],
			"|0|=%.4f |5|=%.4f |10|=%.4f" % [magnitudes[0], magnitudes[5], magnitudes[10]])
	_listo("nivel 0 gira poco pero sin error ni división por cero",
			magnitudes[0] > 0.0 and magnitudes[0] < magnitudes[5], "|0|=%.4f" % magnitudes[0])

# ---------------------------------------------------------------- inversión
func _probar_inversion(cam: Node3D) -> void:
	_J.sensibilidad = 5
	_J.invertir_eje_vertical = false
	var normal := _giro(cam, DX, DY)
	_J.invertir_eje_vertical = true
	var invertido := _giro(cam, DX, DY)
	# El pitch se recorta a limite_pitch_superior (0,20), así que se comprueba el
	# CAMBIO DE SIGNO, no la magnitud exacta.
	_listo("invertir: el eje vertical cambia de signo",
			normal.y < 0.0 and invertido.y > 0.0,
			"normal=%.4f invertido=%.4f" % [normal.y, invertido.y])
	_listo("invertir: el eje horizontal no cambia",
			absf(invertido.x - normal.x) < TOL,
			"normal=%.4f invertido=%.4f" % [normal.x, invertido.x])
	_J.invertir_eje_vertical = false

# ---------------------------------------------------------------- HUD
func _probar_hud() -> void:
	var jug = JUGADOR.instantiate()
	add_child(jug)
	await get_tree().process_frame
	await get_tree().process_frame

	var hud := jug.get_node_or_null("HUD")
	var menu := jug.get_node_or_null("MenuTransformaciones")
	var grupo := get_tree().get_nodes_in_group("hud_juego")
	_listo("el HUD del juego existe", hud != null, "")
	_listo("hud_juego contiene solo el HUD del juego",
			grupo.size() == 1 and grupo.has(hud), "n=%d" % grupo.size())
	_listo("el menú de transformaciones NO está en hud_juego", not grupo.has(menu), "")

	_J.poner_ocultar_hud(true)
	await get_tree().process_frame
	_listo("OCULTAR INTERFAZ = SÍ oculta el HUD", not hud.visible, "visible=%s" % hud.visible)
	_listo("OCULTAR INTERFAZ no destruye el nodo del HUD", is_instance_valid(hud), "")

	_J.poner_ocultar_hud(false)
	await get_tree().process_frame
	_listo("OCULTAR INTERFAZ = NO vuelve a mostrar el HUD", hud.visible,
			"visible=%s" % hud.visible)

	jug.queue_free()
	await get_tree().process_frame

# ---------------------------------------------------------------- persistencia
func _probar_persistencia() -> void:
	_J.poner_sensibilidad(3)
	_J.poner_invertir_eje_vertical(true)
	_J.poner_mostrar_ayudas(true)
	_J.poner_ocultar_hud(false)

	var cf := ConfigFile.new()
	var err := cf.load("user://ajustes_jugabilidad.cfg")
	_listo("se escribió user://ajustes_jugabilidad.cfg", err == OK, "err=%d" % err)
	_listo("persiste sensibilidad=3", int(cf.get_value("jugabilidad", "sensibilidad", -1)) == 3, "")
	_listo("persiste invertir_eje_vertical=true",
			bool(cf.get_value("jugabilidad", "invertir_eje_vertical", false)), "")
	_listo("persiste mostrar_ayudas=true",
			bool(cf.get_value("jugabilidad", "mostrar_ayudas", false)), "")
	_listo("persiste ocultar_hud=false",
			not bool(cf.get_value("jugabilidad", "ocultar_hud", true)), "")

	_J.poner_sensibilidad(99)
	_listo("sensibilidad se limita a 10", _J.sensibilidad == 10, "v=%d" % _J.sensibilidad)
	_J.poner_sensibilidad(-7)
	_listo("sensibilidad se limita a 0", _J.sensibilidad == 0, "v=%d" % _J.sensibilidad)

	# Estado final razonable para el usuario.
	_J.poner_sensibilidad(5)
	_J.poner_invertir_eje_vertical(false)
	_J.poner_mostrar_ayudas(false)
	_J.poner_ocultar_hud(false)