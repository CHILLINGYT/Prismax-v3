extends Node3D

# Arnés de prueba (headless, como ESCENA) del DASH del Velocista y de su
# movimiento normal, sobre el jugador REAL y su cámara real.
#
# Comprueba los casos del informe de bug:
#   1. mantener W y ejecutar varios dashes seguidos;
#   2. seguir avanzando con W entre dash y dash (sin quedarse parado);
#   3. dash mientras se mantiene A, S y D;
#   4. dashes en las 8 direcciones, diagonales incluidas;
#   5. cambiar de dirección DURANTE el dash y ENTRE dashes;
#   6. pulsar otra tecla de movimiento durante y después del dash sin que el
#      personaje se detenga;
#   7. soltar todo -> el personaje se detiene;
#   8. un dash en curso no se duplica al insistir con la tecla;
#   9. salto y ataque siguen funcionando.
#
# Se ejecuta como escena (no con -s: necesita el mundo en marcha):
#   godot --headless --path . _tests/prueba_dash_velocista.tscn

const ESTADO_NORMAL := 0
const ESTADO_DASH := 1
const FORMA_VELOCISTA := 1

const TECLAS := [
	"mover_adelante", "mover_atras", "mover_izquierda", "mover_derecha",
	"dash", "saltar", "atacar",
]

var _pasadas := 0
var _falladas := 0
var _pos_base := Vector3(0.0, 0.1, 0.0)
var _vigilar_nodos := false

@onready var jug: ControladorLeo = $Jugador

func _ready() -> void:
	get_tree().node_added.connect(_al_anadir_nodo)
	call_deferred("_correr")

## Registra los nodos que entran al árbol: cada alta de un Control/Node3D hace que
## el autoload AjustesControles reescriba el InputMap, y eso descarta el estado
## pulsado de las acciones (bug del dash). Sirve para ver el disparador exacto.
func _al_anadir_nodo(n: Node) -> void:
	if _vigilar_nodos:
		print("[NODO+] %s (%s)" % [n.name, n.get_class()])

func _check(nombre: String, ok: bool, detalle: String = "") -> void:
	var sufijo := (" — " + detalle) if detalle != "" else ""
	if ok:
		_pasadas += 1
		print("[OK]    ", nombre, sufijo)
	else:
		_falladas += 1
		print("[FALLA] ", nombre, sufijo)

func _esperar(frames: int) -> void:
	for _i in frames:
		await get_tree().physics_frame

func _pos() -> Vector3:
	return jug.global_position

func _solatar_todo() -> void:
	for a in TECLAS:
		Input.action_release(a)

## Pulsa y suelta la acción dash (como un toque real de la tecla).
func _pulsar_dash() -> void:
	var w0 := Input.is_action_pressed("mover_adelante")
	Input.action_press("dash")
	await get_tree().physics_frame
	var w1 := Input.is_action_pressed("mover_adelante")
	await get_tree().physics_frame
	var w2 := Input.is_action_pressed("mover_adelante")
	Input.action_release("dash")
	await get_tree().physics_frame
	var w3 := Input.is_action_pressed("mover_adelante")
	var st := int(jug.estado) if jug != null else -1
	print("[TELE-D] W antes=%s +1=%s +2=%s +3=%s | estado=%d foco=%s raton=%d" % [
			str(w0), str(w1), str(w2), str(w3), st,
			str(get_window().has_focus()), int(Input.mouse_mode)])

## Espera a que el dash termine (vuelve a NORMAL). Devuelve los frames usados.
func _esperar_fin_dash(max_frames: int = 120) -> int:
	var n := 0
	while n < max_frames and int(jug.estado) == ESTADO_DASH:
		await get_tree().physics_frame
		n += 1
	return n

## Devuelve el cuerpo al centro, quieto, de pie y en NORMAL.
func _reset() -> void:
	_solatar_todo()
	jug.global_position = _pos_base
	jug.velocity = Vector3.ZERO
	jug.estado = ESTADO_NORMAL
	await _esperar(18)

## Pulsa/suelta una TECLA FÍSICA REAL (pasa por el mismo camino que el teclado del
## jugador, a diferencia de Input.action_press).
func _tecla_real(codigo: int, pulsada: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = codigo
	ev.pressed = pulsada
	Input.parse_input_event(ev)

## Telemetría fotograma a fotograma: sirve para ver POR QUÉ el personaje no
## avanza (estado, velocidad, dirección leída, orientación de cámara y modelo).
func _telemetria(frames: int, etiqueta: String) -> void:
	print("[TELE] --- ", etiqueta)
	for _i in frames:
		var v := Vector2(jug.velocity.x, jug.velocity.z).length()
		var d: Vector3 = jug._direccion_entrada()
		print("[TELE] f=%d est=%d |v|=%5.2f dir=%s cam_yaw=%6.3f vis_y=%6.1f pos_y=%5.2f suelo=%s W=%s A=%s" % [
				_i, int(jug.estado), v,
				str(d.snapped(Vector3(0.01, 0.01, 0.01))),
				jug.pivote.global_rotation.y, rad_to_deg(jug.visual.rotation.y),
				jug.global_position.y, str(jug.is_on_floor()),
				str(Input.is_action_pressed("mover_adelante")),
				str(Input.is_action_pressed("mover_izquierda"))])
		await get_tree().physics_frame

## Dirección que DEBE tomar el dash según la entrada y la base real de la
## cámara (el mismo criterio que sigue el controlador: es el contrato vigente).
func _direccion_esperada(teclas: Array) -> Vector3:
	var base := jug.pivote.global_transform.basis
	var adelante := -base.z
	adelante.y = 0.0
	adelante = adelante.normalized()
	var derecha := base.x
	derecha.y = 0.0
	derecha = derecha.normalized()
	var v := Vector2.ZERO
	if teclas.has("mover_adelante"):
		v.y -= 1.0
	if teclas.has("mover_atras"):
		v.y += 1.0
	if teclas.has("mover_izquierda"):
		v.x -= 1.0
	if teclas.has("mover_derecha"):
		v.x += 1.0
	if v == Vector2.ZERO:
		return Vector3.ZERO
	v = v.normalized()
	return (adelante * (-v.y) + derecha * v.x).normalized()

## Mantiene las teclas dadas, ejecuta UN dash y mide su desplazamiento.
func _dash_con(teclas: Array, nombre: String) -> Vector3:
	await _reset()
	for k in teclas:
		Input.action_press(k)
	await _esperar(14)
	var antes := _pos()
	await _pulsar_dash()
	await _esperar_fin_dash()
	var delta := _pos() - antes
	delta.y = 0.0
	var esperado := _direccion_esperada(teclas)
	var dir := delta.normalized() if delta.length() > 0.05 else Vector3.ZERO
	var punto := dir.dot(esperado) if esperado.length() > 0.5 else -2.0
	_check("dash con [%s]: recorre su distancia" % nombre, delta.length() >= 5.0,
			"d=%.2f m" % delta.length())
	_check("dash con [%s]: va en la dirección de la entrada" % nombre,
			punto >= 0.85, "dot=%.2f dir=%s" % [punto, str(dir.snapped(Vector3(0.01, 0.01, 0.01)))])
	_solatar_todo()
	await _esperar(6)
	return delta

func _correr() -> void:
	print("[DASH] arrancando arnés del velocista")
	await _esperar(20)
	_check("el jugador está de pie antes de empezar", jug.is_on_floor())

	# --- Entrada al Velocista por el camino REAL del menú radial -------------
	jug._on_transformacion_elegida(&"velocista")
	var t := 0
	while (int(jug.forma) != FORMA_VELOCISTA or jug._transformando) and t < 600:
		await get_tree().physics_frame
		t += 1
	_check("el Velocista entra por el menú (id &\"velocista\")",
			int(jug.forma) == FORMA_VELOCISTA, "forma=%d" % int(jug.forma))
	await _esperar(20)

	# --- 1 y 2: mantener W y tres dashes seguidos, sin dejar de avanzar ------
	await _reset()
	Input.action_press("mover_adelante")
	await _esperar(20)
	var p_caminar := _pos()
	await _esperar(30)
	var v_caminar := (_pos() - p_caminar).length() / (30.0 / 60.0)
	_check("con W sola camina de verdad", v_caminar >= 3.0, "v=%.2f m/s" % v_caminar)
	for i in 3:
		var antes := _pos()
		_vigilar_nodos = i == 0
		await _pulsar_dash()
		await _esperar_fin_dash()
		_vigilar_nodos = false
		var d := (_pos() - antes).length()
		_check("dash %d seguido con W mantenida se ejecuta" % (i + 1), d >= 5.0,
				"d=%.2f m" % d)
		# Entre dash y dash debe seguir avanzando (W sigue pulsada).
		var a := _pos()
		await _esperar(30)
		var v := (_pos() - a).length() / (30.0 / 60.0)
		_check("tras el dash %d sigue avanzando con W (no se detiene)" % (i + 1),
				v >= 1.5, "v=%.2f m/s" % v)
		if i == 0:
			await _telemetria(12, "inmediatamente después del dash 1 (W mantenida)")
	_solatar_todo()

	# --- 3 y 4: dash en las 8 direcciones -----------------------------------
	await _dash_con(["mover_adelante"], "W")
	await _dash_con(["mover_izquierda"], "A")
	await _dash_con(["mover_atras"], "S")
	await _dash_con(["mover_derecha"], "D")
	await _dash_con(["mover_adelante", "mover_izquierda"], "W+A")
	await _dash_con(["mover_adelante", "mover_derecha"], "W+D")
	await _dash_con(["mover_atras", "mover_izquierda"], "S+A")
	await _dash_con(["mover_atras", "mover_derecha"], "S+D")

	# --- 5 y 6: cambio de dirección durante el dash y después ---------------
	await _reset()
	Input.action_press("mover_adelante")
	await _esperar(20)
	var p0 := _pos()
	await _pulsar_dash()
	# A mitad del dash se pulsa OTRA tecla de movimiento (W sigue pulsada).
	Input.action_press("mover_izquierda")
	var en_dash := int(jug.estado) == ESTADO_DASH
	await _esperar_fin_dash()
	var d_mitad := (_pos() - p0).length()
	_check("el dash sigue completándose al pulsar otra tecla a mitad (estaba en DASH=%s)" % str(en_dash),
			d_mitad >= 5.0, "d=%.2f m" % d_mitad)
	# Con W+A pulsadas, tras el dash debe seguir moviéndose (no detenido).
	var a := _pos()
	await _esperar(30)
	var v := (_pos() - a).length() / (30.0 / 60.0)
	_check("tras el dash con W+A el personaje sigue avanzando", v >= 1.5,
			"v=%.2f m/s" % v)
	# Y un segundo dash en diagonal debe ejecutarse igual.
	var b := _pos()
	await _pulsar_dash()
	await _esperar_fin_dash()
	var d_diag := (_pos() - b).length()
	var esperado_diag := _direccion_esperada(["mover_adelante", "mover_izquierda"])
	var dir_diag := ((_pos() - b) * Vector3(1, 0, 1)).normalized() if d_diag > 0.05 else Vector3.ZERO
	_check("segundo dash con W+A se ejecuta en diagonal", d_diag >= 5.0 and dir_diag.dot(esperado_diag) >= 0.85,
			"d=%.2f m dot=%.2f" % [d_diag, dir_diag.dot(esperado_diag)])

	# Cambio de dirección ENTRE dashes: el segundo debe ir a la nueva dirección.
	Input.action_release("mover_adelante")
	await _esperar(10)
	print("[TELE] antes del dash con A: dir_leida=%s cam_yaw=%.3f A=%s W=%s est=%d |v|=%.2f" % [
			str(jug._direccion_entrada()), jug.pivote.global_rotation.y,
			str(Input.is_action_pressed("mover_izquierda")),
			str(Input.is_action_pressed("mover_adelante")), int(jug.estado),
			Vector2(jug.velocity.x, jug.velocity.z).length()])
	await _telemetria(6, "antes del dash con A")
	var c := _pos()
	await _pulsar_dash()
	await _esperar_fin_dash()
	var d_final := (_pos() - c).length()
	var dir_final := ((_pos() - c) * Vector3(1, 0, 1)).normalized() if d_final > 0.05 else Vector3.ZERO
	var esperado_final := _direccion_esperada(["mover_izquierda"])
	_check("tras cambiar de W a A, el dash va hacia la nueva dirección",
			d_final >= 5.0 and dir_final.dot(esperado_final) >= 0.85,
			"d=%.2f m dot=%.2f" % [d_final, dir_final.dot(esperado_final)])
	_solatar_todo()

	# --- 7: al soltar todo, el personaje se detiene -------------------------
	await _esperar(60)
	var v_final := Vector2(jug.velocity.x, jug.velocity.z).length()
	_check("al soltar todas las teclas el personaje se detiene", v_final < 0.1,
			"|v|=%.3f m/s" % v_final)

	# --- 8: insistir con dash durante un dash no lo duplica ----------------
	await _reset()
	Input.action_press("mover_adelante")
	await _esperar(10)
	var p8 := _pos()
	Input.action_press("dash")
	await get_tree().physics_frame
	Input.action_release("dash")
	# Tres pulsaciones más mientras el dash está en curso.
	for _i in 3:
		Input.action_press("dash")
		await get_tree().physics_frame
		Input.action_release("dash")
		await get_tree().physics_frame
	await _esperar_fin_dash()
	var d8 := (_pos() - p8).length()
	_check("insistir con dash durante un dash no encadena otro (recorrido de un solo dash)",
			d8 >= 5.0 and d8 <= 14.0, "d=%.2f m" % d8)
	_solatar_todo()

	# --- 9: salto y ataque siguen funcionando ------------------------------
	await _reset()
	var y0 := _pos().y
	Input.action_press("saltar")
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release("saltar")
	await _esperar(25)
	var altura := _pos().y - y0
	_check("el salto sigue funcionando con el velocista", altura > 0.4,
			"altura=%.2f m" % altura)
	var t_aire := 0
	while not jug.is_on_floor() and t_aire < 180:
		await get_tree().physics_frame
		t_aire += 1
	await _esperar(10)
	Input.action_press("atacar")
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release("atacar")
	await _esperar(3)
	_check("el ataque sigue funcionando con el velocista", bool(jug._ataque_activo),
			"ataque_activo=%s" % str(jug._ataque_activo))
	await _esperar(40)

	# --- 10: con TECLAS FÍSICAS REALES (el caso del informe de bug) ---------
	# Mantener W real, dash real (SHIFT), pulsar A a mitad y seguir con otro dash
	# en diagonal: antes de la corrección, el alta de nodos del dash hacía que el
	# autoload AjustesControles reescribiera el InputMap y la tecla mantenida se
	# "soltara" sola (el personaje se detenía).
	await _reset()
	_tecla_real(87, true)                     # W
	await _esperar(20)
	var p10 := _pos()
	_tecla_real(4194325, true)                # SHIFT = dash
	await _esperar(2)
	_tecla_real(4194325, false)
	_tecla_real(65, true)                     # A a mitad del dash
	var en_dash10 := int(jug.estado) == ESTADO_DASH
	await _esperar_fin_dash()
	var d10 := (_pos() - p10).length()
	var a10 := _pos()
	await _esperar(30)
	var v10 := (_pos() - a10).length() / (30.0 / 60.0)
	_check("teclas REALES: dash con W y A a mitad (DASH=%s) y el personaje sigue avanzando" % str(en_dash10),
			d10 >= 5.0 and v10 >= 1.5, "d=%.2f m v=%.2f m/s" % [d10, v10])
	var b10 := _pos()
	_tecla_real(4194325, true)
	await _esperar(2)
	_tecla_real(4194325, false)
	await _esperar_fin_dash()
	var delta10 := _pos() - b10
	delta10.y = 0.0
	var esp10 := _direccion_esperada(["mover_adelante", "mover_izquierda"])
	var dir10 := delta10.normalized() if delta10.length() > 0.05 else Vector3.ZERO
	_check("teclas REALES: segundo dash en diagonal (W+A) con la dirección correcta",
			delta10.length() >= 5.0 and dir10.dot(esp10) >= 0.85,
			"d=%.2f m dot=%.2f" % [delta10.length(), dir10.dot(esp10)])
	_tecla_real(87, false)
	_tecla_real(65, false)
	await _esperar(40)
	var vf := Vector2(jug.velocity.x, jug.velocity.z).length()
	_check("teclas REALES: al soltar todas las teclas el personaje se detiene",
			vf < 0.1, "|v|=%.3f m/s" % vf)

	print("[DASH] ===== RESULTADO: %d OK, %d FALLOS =====" % [_pasadas, _falladas])
	get_tree().quit(1 if _falladas > 0 else 0)