extends Node3D

# Verificacion funcional (no visual) de las dos modificaciones:
#  1) los rayos de ataque crecen de intensidad con el combo (1..4);
#  2) ESPACIO cancela el ataque y arranca "jumping up(1)".

@onready var prototipo: Node3D = $ZibaPrototipo

func _esperar_frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _ready() -> void:
	await _esperar_frames(6)
	var jugador: Node = prototipo.get_node("Jugador")
	var efectos: Node = jugador.get_node("Efectos")
	var combate: Node = jugador.get_node("Combate")
	print("[TEST] on_floor=", jugador.is_on_floor())

	# --- Progresion de rayos por golpe ---
	var niveles: Array = []
	for i in 4:
		combate.intentar_golpe()
		await _esperar_frames(7)
		niveles.append(snappedf(efectos._nivel_ataque, 0.001))
	print("[TEST] niveles de rayos por combo (1..4): ", niveles)
	var creciente: bool = niveles[0] > 0.05 and niveles[1] > niveles[0] and niveles[2] > niveles[1] and niveles[3] > niveles[2]
	print("[TEST] progresion creciente: ", creciente)

	# Dejar que los rayos decaigan solos (no deben quedar permanentes).
	await _esperar_frames(40)
	print("[TEST] nivel de rayos tras decaer: ", snappedf(efectos._nivel_ataque, 0.001))

	# --- Cancelacion por salto ---
	await _esperar_frames(4)
	combate.intentar_golpe()
	await _esperar_frames(2)
	print("[TEST] combo activo antes del salto: ", combate.golpe_actual(), " ataque_activo=", jugador._ataque_activo)
	Input.action_press("saltar")
	await _esperar_frames(2)
	Input.action_release("saltar")
	await _esperar_frames(3)
	print("[TEST] tras ESPACIO -> golpe_actual=", combate.golpe_actual(), " ataque_activo=", jugador._ataque_activo, " anim=", jugador._anim_actual, " vel_y=", snappedf(jugador.velocity.y, 0.01))

	# --- El salto normal sin ataque sigue igual ---
	await _esperar_frames(60)
	Input.action_press("saltar")
	await _esperar_frames(2)
	Input.action_release("saltar")
	await _esperar_frames(3)
	print("[TEST] salto normal (sin ataque) anim=", jugador._anim_actual, " vel_y=", snappedf(jugador.velocity.y, 0.01))

	print("[TEST] FIN")
	get_tree().quit()