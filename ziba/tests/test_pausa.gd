extends Node3D

# Verifica que el mundo quede realmente detenido con la pausa abierta y que se
# reanude al cerrarla. Mide el desplazamiento del jugador manteniendo W pulsado
# en tres tramos: jugando, en pausa y tras reanudar.

var prototipo: Node3D
var jugador: CharacterBody3D
var pausa: PauseMenu

func _esperar(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _ready() -> void:
	prototipo = $ZibaPrototipo
	pausa = prototipo.get_node("Pausa") as PauseMenu
	await _esperar(20)
	jugador = prototipo.get_node("Jugador") as CharacterBody3D

	print("[TEST] pausado al iniciar=", get_tree().paused)

	# Tramo 1: jugando normal, W debe mover al jugador.
	var p0 := jugador.global_position
	Input.action_press("mover_adelante")
	await _esperar(45)
	Input.action_release("mover_adelante")
	var p1 := jugador.global_position
	print("[TEST] jugando: desplazamiento=", snappedf((p1 - p0).length(), 0.01), " m")

	# Abrir la pausa y comprobar que el mundo se detiene de verdad.
	pausa.abrir()
	print("[TEST] pausa abierta=", pausa.esta_abierto(), " arbol pausado=", get_tree().paused)
	await _esperar(15)
	var p_ref := jugador.global_position
	Input.action_press("mover_adelante")
	await _esperar(60)
	Input.action_release("mover_adelante")
	var p_pausa := jugador.global_position
	print("[TEST] en pausa: desplazamiento=", snappedf((p_pausa - p_ref).length(), 0.001), " m (debe ser 0)")

	# Cerrar la pausa y comprobar que se recupera el control.
	pausa.cerrar()
	print("[TEST] pausa abierta=", pausa.esta_abierto(), " arbol pausado=", get_tree().paused)
	await _esperar(5)
	var p2 := jugador.global_position
	Input.action_press("mover_adelante")
	await _esperar(45)
	Input.action_release("mover_adelante")
	var p3 := jugador.global_position
	print("[TEST] tras reanudar: desplazamiento=", snappedf((p3 - p2).length(), 0.01), " m (debe ser > 0)")

	print("[TEST] FIN")
	get_tree().quit()