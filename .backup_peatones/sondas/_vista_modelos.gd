extends Node3D
## Inspección de MODELOS PSX (temporal, no forma parte del juego): monta todos los modelos
## de NPCs/Characters/PSX en parrillas (una por sexo) para ver de un vistazo la postura de
## pie (idle) y en marcha (walk): encorvados, cabezas torcidas u orientaciones raras.
## Guarda las capturas en res://.backup_peatones/capturas/ y termina sola.

const DIR_PSX := "res://NPCs/Characters/PSX/"
const DIR_CAP := "res://.backup_peatones/capturas"
const ESCENA := "res://NPCs/Scenes/NPC_Citizen.tscn"
const PASO := 2.6           ## separación entre modelos de la parrilla
const COLS := 5

var _cam: Camera3D = null
var _por_sexo := {"Male": [], "Female": []}
var _paso := 0
var _t0 := 0


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR_CAP))
	# Suelo claro para que se lean las siluetas.
	var suelo := MeshInstance3D.new()
	var caja := BoxMesh.new()
	caja.size = Vector3(60.0, 0.2, 60.0)
	suelo.mesh = caja
	suelo.position = Vector3(0.0, -0.1, 0.0)
	add_child(suelo)
	var sol := DirectionalLight3D.new()
	sol.rotation_degrees = Vector3(-55.0, 35.0, 0.0)
	sol.light_energy = 1.3
	add_child(sol)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.62, 0.70)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.78, 0.8)
	e.ambient_light_energy = 0.9
	env.environment = e
	add_child(env)
	_cam = Camera3D.new()
	_cam.fov = 50.0
	add_child(_cam)
	_cam.make_current()
	# Se separan por sexo y se ordenan como en el director.
	for sexo: String in ["Male", "Female"]:
		var nombres: Array[String] = []
		for f in DirAccess.get_files_at(DIR_PSX + sexo + "/"):
			if f.ends_with(".fbx") and f != "Character_Female_01.fbx":
				nombres.append(f)
		nombres.sort()
		_por_sexo[sexo] = nombres
	_montar("Male", Vector3.ZERO)
	_montar("Female", Vector3(0.0, 0.0, -18.0))
	_t0 = Time.get_ticks_msec()
	print("[Modelos] parrillas: Male %d · Female %d" % [
			(_por_sexo["Male"] as Array).size(), (_por_sexo["Female"] as Array).size()])
	# (el diagnóstico se vuelca al final, en _process, para que no lo corte el log)


func _montar(sexo: String, origen: Vector3) -> void:
	var nombres: Array = _por_sexo[sexo]
	var escena: PackedScene = load(ESCENA)
	var filas := ceili(nombres.size() / float(COLS))
	for i in nombres.size():
		var col := i % COLS
		var fila := floori(i / float(COLS))
		var c := escena.instantiate()
		c.set("model_scene", load(DIR_PSX + sexo + "/" + String(nombres[i])))
		c.set("body_type", "female" if sexo == "Female" else "male")
		c.set("vary_model_parts", false)     # tal cual viene del paquete
		# Parrilla centrada en `origen` (la cámara mira ahí).
		c.position = origen + Vector3((float(col) - (COLS - 1) * 0.5) * PASO, 0.05,
				(float(fila) - (filas - 1) * 0.5) * PASO)
		c.rotation.y = 0.0                   # mirando a +Z (la cámara se pone delante)
		add_child(c)
		c.set_physics_process(false)         # sin gravedad: aquí sólo se mira la postura
		# Altura real del esqueleto en reposo (para detectar gigantes y enanos).
		var alto := 0.0
		var esq := c.find_children("*", "Skeleton3D", true, false)
		if not esq.is_empty():
			var sk: Skeleton3D = esq[0]
			var cabeza := -1
			for b in sk.get_bone_count():
				if String(sk.get_bone_name(b)).to_lower().ends_with("head"):
					cabeza = b
					break
			if cabeza >= 0:
				alto = sk.get_bone_global_rest(cabeza).origin.y * sk.global_transform.basis.get_scale().y
		print("[Modelos] %-4s %2d %-26s cabeza≈%.2f m" % [sexo, i, String(nombres[i]), alto])


## Vuelca todo lo que pueda explicar por qué un modelo no se ve.
func _diag(c: Node) -> void:
	print("[diag] %s en %s" % [c.name, str((c as Node3D).global_position)])
	for h in c.find_children("*", "", true, false):
		var vis := "-"
		if h is Node3D:
			vis = str((h as Node3D).visible)
		if h is MeshInstance3D:
			var m: MeshInstance3D = h
			var mat: Material = m.get_surface_override_material(0)
			if mat == null and m.mesh != null and m.mesh.get_surface_count() > 0:
				mat = m.mesh.surface_get_material(0)
			print("  %s (%s) vis=%s capas=%d aabb=%s skel=%s mat=%s esc=%s" % [h.name, h.get_class(),
					vis, m.layers, str(m.get_aabb()), str(m.skeleton),
					"null" if mat == null else mat.get_class(), str(m.global_transform.basis.get_scale())])
		elif h is Skeleton3D:
			print("  %s (%s) vis=%s huesos=%d esc=%s" % [h.name, h.get_class(), vis,
					(h as Skeleton3D).get_bone_count(), str((h as Skeleton3D).global_transform.basis.get_scale())])
		else:
			print("  %s (%s) vis=%s" % [h.name, h.get_class(), vis])


func _process(_d: float) -> void:
	var t := float(Time.get_ticks_msec() - _t0) / 1000.0
	match _paso:
		0:
			if t > 2.0:
				_mirar(Vector3(0.0, 1.0, 0.0), 15.5, 2.0)
				_capturar("modelos_male_idle")
				_paso = 1
		1:
			if t > 3.0:
				_mirar(Vector3(0.0, 1.0, -18.0), 13.0, 2.0)
				_capturar("modelos_female_idle")
				_paso = 2
		2:
			if t > 4.0:
				_caminar()
		3:
			if t > 6.0:
				_mirar(Vector3(0.0, 1.0, 0.0), 15.5, 2.0)
				_capturar("modelos_male_walk")
				_paso = 4
		4:
			if t > 7.5:
				_mirar(Vector3(0.0, 1.0, -18.0), 13.0, 2.0)
				_capturar("modelos_female_walk")
				_paso = 5
		5:
			if t > 8.5:
				for c in get_children():
					if c is CharacterBody3D:
						_diag(c)
						break
				print("[Modelos] fin")
				get_tree().quit()


## Pone a todos en marcha (sin moverlos: sólo interesa la postura del paso).
func _caminar() -> void:
	for c in get_children():
		if c.get("model_scene") != null and c.has_method("velocidad_real"):
			var arbol: AnimationTree = c.find_children("*", "AnimationTree", true, false)[0]
			var pb: AnimationNodeStateMachinePlayback = arbol.get("parameters/playback")
			arbol.active = true
			pb.travel("walk")


func _mirar(centro: Vector3, dist: float, alto: float) -> void:
	_cam.global_position = centro + Vector3(0.0, alto, dist)
	_cam.look_at(centro + Vector3(0.0, 0.5, 0.0))


func _capturar(nombre: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png("%s/%s.png" % [DIR_CAP, nombre])
	print("[Modelos] captura %s -> %s (%s)" % [nombre, err, "OK" if err == OK else str(err)])