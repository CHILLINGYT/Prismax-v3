extends Node3D
## VISTA (no suite): balas reales del tirador cruzando de lado delante de una cámara
## fija, a la velocidad real, para ver el cartucho y su estela en pantalla.

const PROYECTIL := preload("res://Enemigos Prueba/Scenes/proyectil_enemigo.tscn")

var _t := 0.0


func _ready() -> void:
	var suelo := StaticBody3D.new()
	var forma := CollisionShape3D.new()
	var caja := BoxShape3D.new()
	caja.size = Vector3(60, 1, 60)
	forma.shape = caja
	suelo.add_child(forma)
	var malla := MeshInstance3D.new()
	var plano := PlaneMesh.new()
	plano.size = Vector2(60, 60)
	malla.mesh = plano
	malla.position.y = 0.5
	suelo.add_child(malla)
	suelo.position.y = -0.5
	add_child(suelo)
	var luz := DirectionalLight3D.new()
	luz.rotation = Vector3(-0.9, 0.5, 0.0)
	add_child(luz)
	var entorno := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.32, 0.36, 0.42)
	env.ambient_light_color = Color(0.6, 0.6, 0.6)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	entorno.environment = env
	add_child(entorno)
	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 1.3, 4.0)
	cam.fov = 60.0
	cam.current = true
	add_child(cam)


func _physics_process(delta: float) -> void:
	_t += delta
	if _t < 0.18:
		return
	_t = 0.0
	var p := PROYECTIL.instantiate()
	add_child(p)
	var y := randf_range(1.0, 1.6)
	p.call("lanzar", Vector3(-12.0, y, 0.0), Vector3(1.0, 0.0, 0.0), null, 26.0, 0.0)
