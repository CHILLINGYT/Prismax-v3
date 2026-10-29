extends Node3D

# Arnés de prueba aislado para el ascenso de bordillos del Velocista durante la
# EJECUCIÓN del trazado. Instancia la escena REAL del jugador (leo_jugador.tscn)
# sobre una calzada con dos aceras (bordillo de 0,15 m, igual que la ciudad) y
# coloca puntos de ruta a mano para reproducir cada caso sin depender del ratón.
#
# No forma parte del juego: vive en res://pruebas/ y se ejecuta solo con run_scene.

const JUGADOR := preload("res://personaje/base/escenas/leo_jugador.tscn")

const FORMA_VELOCISTA := 1     # ControladorLeo.Forma.VELOCISTA
const ESTADO_EJECUCION := 5    # ControladorLeo.Estado.EJECUCION
const ESTADO_NORMAL := 0

const Y_CALZADA := -0.15       # cara superior de la calzada
const Y_ACERA := 0.0           # cara superior de la acera (bordillo 0,15 m)

var _jug: CharacterBody3D
var _pasadas := 0
var _falladas := 0

func _ready() -> void:
	_construir_mundo()
	_jug = JUGADOR.instantiate()
	add_child(_jug)
	await get_tree().physics_frame
	await get_tree().physics_frame
	await _correr_todas()
	print("[TEST] ===== RESUMEN: %d OK, %d FALLOS =====" % [_pasadas, _falladas])

# ---------------------------------------------------------------- mundo
func _construir_mundo() -> void:
	# Calzada central: x en [-6, 6], cara superior en y=-0.15.
	_caja(Vector3(12.0, 1.0, 80.0), Vector3(0.0, Y_CALZADA - 0.5, 0.0))
	# Aceras a ambos lados: cara superior en y=0 (bordillo de 0,15 m).
	_caja(Vector3(40.0, 1.0, 80.0), Vector3(-26.0, Y_ACERA - 0.5, 0.0))
	_caja(Vector3(40.0, 1.0, 80.0), Vector3(26.0, Y_ACERA - 0.5, 0.0))
	# Pared alta para la prueba de obstáculo infranqueable (frente en x=20).
	_caja(Vector3(8.0, 6.0, 20.0), Vector3(24.0, 3.0, 0.0))

func _caja(tam: Vector3, pos: Vector3) -> void:
	var cuerpo := StaticBody3D.new()
	cuerpo.position = pos
	var forma := CollisionShape3D.new()
	var caja := BoxShape3D.new()
	caja.size = tam
	forma.shape = caja
	cuerpo.add_child(forma)
	add_child(cuerpo)

# ---------------------------------------------------------------- utilidades
func _linea(inicio: Vector3, dir: Vector3, largo: float, n: int) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for i in range(1, n + 1):
		out.append(inicio + dir.normalized() * (largo * float(i) / float(n)))
	return out

func _colocar(pos: Vector3) -> void:
	_jug.global_position = pos
	_jug.velocity = Vector3.ZERO
	_jug.forma = FORMA_VELOCISTA
	for _i in 2:
		await get_tree().physics_frame

func _iniciar_ejecucion(puntos: Array[Vector3]) -> void:
	_jug._puntos = puntos
	_jug._idx = 0
	_jug._vel_trayecto = _jug.vel_trayecto_min
	_jug.estado = ESTADO_EJECUCION

func _esperar_fin(max_frames: int) -> void:
	var f := 0
	while _jug.estado == ESTADO_EJECUCION and f < max_frames:
		await get_tree().physics_frame
		f += 1

func _registrar(nombre: String, ok: bool, detalle: String) -> void:
	if ok:
		_pasadas += 1
	else:
		_falladas += 1
	print("[TEST] %s :: %s | %s" % ["OK" if ok else "FALLO", nombre, detalle])

func _correr_todas() -> void:
	# 1) Calle -> acera (+X): debe subir el bordillo y terminar sobre la acera.
	await _colocar(Vector3(-2.0, Y_CALZADA, 0.0))
	_iniciar_ejecucion(_linea(Vector3(-2.0, Y_CALZADA, 0.0), Vector3.RIGHT, 12.0, 8))
	await _esperar_fin(400)
	_registrar("calle->acera +X",
			_jug.global_position.x > 6.0 and _jug.global_position.y >= Y_ACERA - 0.05,
			"pos=%s" % _jug.global_position)

	# 2) Acera -> calle (-X): debe bajar y seguir, sin cancelar.
	await _colocar(Vector3(8.0, Y_ACERA, 0.0))
	_iniciar_ejecucion(_linea(Vector3(8.0, Y_ACERA, 0.0), Vector3.LEFT, 12.0, 8))
	await _esperar_fin(400)
	_registrar("acera->calle -X",
			_jug.global_position.x < 0.0,
			"pos=%s" % _jug.global_position)

	# 3) Ruta sin obstáculos a lo largo de la acera (paralela al bordillo).
	await _colocar(Vector3(8.0, Y_ACERA, -6.0))
	_iniciar_ejecucion(_linea(Vector3(8.0, Y_ACERA, -6.0), Vector3.FORWARD, 12.0, 8))
	await _esperar_fin(400)
	_registrar("ruta libre paralela",
			_jug.global_position.z < -12.0,
			"pos=%s" % _jug.global_position)

	# 4) Oblicua que cruza el bordillo desde la calzada.
	await _colocar(Vector3(-2.0, Y_CALZADA, -3.0))
	var dir_oblicua := Vector3(2.0, 0.0, 1.0).normalized()
	_iniciar_ejecucion(_linea(Vector3(-2.0, Y_CALZADA, -3.0), dir_oblicua, 14.0, 8))
	await _esperar_fin(400)
	_registrar("oblicua cruza bordillo",
			_jug.global_position.x > 6.0 and _jug.global_position.y >= Y_ACERA - 0.05,
			"pos=%s" % _jug.global_position)

	# 5) Contra pared alta (x=20): debe bloquearse y NO atravesarla ni subirla.
	await _colocar(Vector3(4.0, Y_CALZADA, 0.0))
	_iniciar_ejecucion(_linea(Vector3(4.0, Y_CALZADA, 0.0), Vector3.RIGHT, 20.0, 10))
	await _esperar_fin(400)
	_registrar("pared infranqueable",
			_jug.global_position.x < 20.0,
			"pos=%s" % _jug.global_position)

	# 6) Recuperación: tras terminar, el estado debe volver a NORMAL.
	await _colocar(Vector3(-2.0, Y_CALZADA, 0.0))
	_iniciar_ejecucion(_linea(Vector3(-2.0, Y_CALZADA, 0.0), Vector3.RIGHT, 12.0, 8))
	await _esperar_fin(400)
	_registrar("estado vuelve a NORMAL",
			_jug.estado == ESTADO_NORMAL,
			"estado=%d" % _jug.estado)

	# 7) Movimiento NORMAL (Leo humano) subiendo el mismo bordillo: confirma que
	#    _resolver_escalon() sigue funcionando tras la corrección.
	_jug.estado = ESTADO_NORMAL
	await _colocar_humano(Vector3(4.0, Y_CALZADA, 0.0))
	Input.action_press("mover_derecha")
	for _i in 150:
		await get_tree().physics_frame
	Input.action_release("mover_derecha")
	_registrar("humano sube bordillo",
			_jug.global_position.x > 6.0 and _jug.global_position.y >= Y_ACERA - 0.05,
			"pos=%s" % _jug.global_position)

func _colocar_humano(pos: Vector3) -> void:
	_jug.global_position = pos
	_jug.velocity = Vector3.ZERO
	_jug.forma = 0   # ControladorLeo.Forma.HUMANO
	for _i in 2:
		await get_tree().physics_frame