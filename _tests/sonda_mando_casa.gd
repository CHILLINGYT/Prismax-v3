extends Node3D
## SONDA del movimiento dentro de la casa: imprime posición, dirección de entrada y
## giros cada medio segundo mientras se pulsan los mandos. Sirve para medir qué hace
## exactamente cada mando (y con qué cámara), sin adivinar.

const CASA := "res://casa_leo/casa_leo.tscn"

var _jug: CharacterBody3D
var _pivote: Node3D
var _t := 0.0
var _plan: Array = [
	{"t": 0.0, "accion": ""},
	{"t": 1.0, "accion": "mover_derecha"},
	{"t": 3.0, "accion": ""},
	{"t": 4.0, "accion": "mover_izquierda"},
	{"t": 6.0, "accion": ""},
	{"t": 7.0, "accion": "mover_adelante"},
	{"t": 9.0, "accion": ""},
]
var _actual := ""
var _paso := 0


func _ready() -> void:
	var casa := (load(CASA) as PackedScene).instantiate() as CasaLeo
	add_child(casa)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_jug = casa.jugador() as CharacterBody3D
	_pivote = _jug.get("pivote") as Node3D
	print("[sonda-mando] inicio | jugador %s | pivote %s" % [
			str(_jug.global_position), str(_pivote.rotation)])
	await _correr()


func _correr() -> void:
	var t := 0.0
	while t < 11.5:
		for paso in _plan:
			if absf(t - float(paso["t"])) < 0.001:
				if _actual != "":
					Input.action_release(_actual)
				_actual = String(paso["accion"])
				if _actual != "":
					Input.action_press(_actual)
				print("[sonda-mando] t=%.1f mando='%s'" % [t, _actual])
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		_t += get_physics_process_delta_time()
		if int(_t * 2.0) != _paso:
			_paso = int(_t * 2.0)
			print("[sonda-mando]  pos %s | entrada %s | pivote.y %.3f | jugador.y %.3f | D=%s A=%s W=%s" % [
					str(_jug.global_position), str(_jug.call("_direccion_entrada")),
					_pivote.global_rotation.y, _jug.global_rotation.y,
					str(Input.is_action_pressed("mover_derecha")),
					str(Input.is_action_pressed("mover_izquierda")),
					str(Input.is_action_pressed("mover_adelante"))])
	print("[sonda-mando] FIN")