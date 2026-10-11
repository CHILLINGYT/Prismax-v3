extends Node3D
## Sonda dirigida (temporal): pone en fila a los modelos SOSPECHOSOS (los que dieron anomalía en
## la orientación de los pies) junto a tres de control, todos con la pose de caminar y mirando a
## +Z, y hace una captura desde el frente. Si un modelo mira de lado, se ve aquí.

const DIR_PSX := "res://NPCs/Characters/PSX/"
const ESCENA := "res://NPCs/Scenes/NPC_Citizen.tscn"
const SOSPECHOSOS := ["Male/Character_Male_33.fbx", "Male/Character_Male_34.fbx",
		"Male/Character_Male_35.fbx", "Male/Character_Male_36.fbx",
		"Male/Character_Sheriff_N.fbx"]
const CONTROLES := ["Male/Character_01.fbx", "Male/Character_09.fbx", "Female/Character_Female_02.fbx"]
const PASO := 2.4

var _cam: Camera3D = null
var _paso := 0
var _t0 := 0
var _lista: Array[String] = []
var _n := 0


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.backup_peatones/capturas"))
	_lista.append_array(SOSPECHOSOS)
	_lista.append_array(CONTROLES)
	var suelo := MeshInstance3D.new()
	var caja := BoxMesh.new()
	caja.size = Vector3(40.0, 0.2, 40.0)
	suelo.mesh = caja
	suelo.position = Vector3(0.0, -0.1, 0.0)
	add_child(suelo)
	var sol := DirectionalLight3D.new()
	sol.rotation_degrees = Vector3(-55.0, 25.0, 0.0)
	sol.light_energy = 1.3
	add_child(sol)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.62, 0.70)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.78, 0.80, 0.82)
	e.ambient_light_energy = 1.0
	env.environment = e
	add_child(env)
	_cam = Camera3D.new()
	_cam.fov = 45.0
	add_child(_cam)
	_cam.make_current()
	var escena: PackedScene = load(ESCENA)
	var ancho := (_lista.size() - 1) * PASO
	for i in _lista.size():
		var partes := _lista[i].split("/")
		var c: Node = escena.instantiate()
		c.set("model_scene", load(DIR_PSX + _lista[i]))
		c.set("body_type", "female" if String(partes[0]) == "Female" else "male")
		c.set("vary_model_parts", false)
		(c as Node3D).position = Vector3(float(i) * PASO - ancho * 0.5, 0.05, 0.0)
		(c as Node3D).rotation.y = 0.0
		add_child(c)
		c.set_physics_process(false)
		_n += 1
		# Se les dice "anda" con la misma máquina de estados que usa el juego.
		var arboles: Array = c.find_children("*", "AnimationTree", true, false)
		if not arboles.is_empty():
			var arbol: AnimationTree = arboles[0]
			arbol.active = true
			(arbol.get("parameters/playback") as AnimationNodeStateMachinePlayback).travel("walk")
			print("[Sospechosos] %d %-32s face_yaw=%.1f° clip=%s" % [i, _lista[i],
					rad_to_deg(c.get("_face_yaw")), String(c.get("_active_clip"))])
	_cam.position = Vector3(0.0, 1.55, ancho * 0.5 + 5.5)
	_cam.look_at(Vector3(0.0, 1.0, 0.0))
	_t0 = Time.get_ticks_msec()
	print("[Sospechosos] fila preparada: %d modelos" % _n)


func _process(_d: float) -> void:
	var t := float(Time.get_ticks_msec() - _t0) / 1000.0
	if _paso == 0 and t > 2.5:
		_paso = 1
		_capturar("cap14_sospechosos_frente")


func _capturar(nombre: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png("res://.backup_peatones/capturas/%s.png" % nombre)
	print("[Sospechosos] captura %s -> %s" % [nombre, "OK" if err == OK else str(err)])
	await get_tree().create_timer(0.2).timeout
	print("[Sospechosos] fin")
	get_tree().quit()