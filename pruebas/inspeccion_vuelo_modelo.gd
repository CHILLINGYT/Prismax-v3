extends Node3D

# ARNÉS TEMPORAL DE INSPECCIÓN VISUAL del personaje de vuelo (se elimina al
# terminar la auditoría). Monta la estatua original del FBX del Tripo y/o el
# personaje integrado, con suelo, luz y cámara, y vuelca por consola el estado
# real de la malla/esqueleto para contrastar con la captura.

const FBX_ESTATUA := "res://personaje/transformaciones/vuelo/tripo_convert_fa47b8ae-06e8-41b8-b855-5fae3ef597aa.fbx"
const JUGADOR_VUELO := "res://personaje/transformaciones/vuelo/player/vuelo_player.tscn"

@export var mostrar_estatua := true
@export var mostrar_jugador := true
@export var congelar_jugador := false
@export var camara_pos := Vector3(-0.9, 1.7, 4.2)
@export var camara_mira := Vector3(-0.9, 0.95, 0.0)

var _jug: Node3D


func _ready() -> void:
	call_deferred("_montar")


func _montar() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.25, 0.28, 0.32)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.8, 0.85, 0.9)
	e.ambient_light_energy = 1.0
	env.environment = e
	add_child(env)

	var luz := DirectionalLight3D.new()
	luz.rotation_degrees = Vector3(-45, -35, 0)
	luz.shadow_enabled = false
	add_child(luz)

	var piso := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	piso.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.52, 0.55)
	piso.material_override = mat
	add_child(piso)
	# Suelo CON colisión: sin esto el CharacterBody3D cae al vacío.
	var cuerpo := StaticBody3D.new()
	var forma := CollisionShape3D.new()
	var caja := BoxShape3D.new()
	caja.size = Vector3(40, 1, 40)
	forma.shape = caja
	forma.position = Vector3(0, -0.5, 0)
	cuerpo.add_child(forma)
	add_child(cuerpo)

	if mostrar_estatua:
		var ps := load(FBX_ESTATUA) as PackedScene
		if ps != null:
			var est := ps.instantiate() as Node3D
			add_child(est)
			est.position = Vector3(-2.6, 0.02, 0)
			print("[INS] estatua original: ", est.get_children().size(), " hijos")

	if mostrar_jugador:
		var psj := load(JUGADOR_VUELO) as PackedScene
		_jug = psj.instantiate() as Node3D
		add_child(_jug)
		_jug.position = Vector3(0.6, 0.05, 0)
		var cam_ajena: Camera3D = _jug.get_node_or_null("CameraPivot/SpringArm3D/Camera3D")
		if cam_ajena != null:
			cam_ajena.current = false

	var cam := Camera3D.new()
	add_child(cam)
	cam.position = camara_pos
	cam.look_at(camara_mira)
	cam.current = true

	await get_tree().create_timer(2.5).timeout

	if congelar_jugador and _jug != null:
		for mixer in _jug.find_children("*", "AnimationMixer", true, false):
			if mixer is AnimationPlayer:
				(mixer as AnimationPlayer).stop()
			elif mixer is AnimationTree:
				(mixer as AnimationTree).active = false
			(mixer as Node).process_mode = Node.PROCESS_MODE_DISABLED
		for sk in _jug.find_children("*", "Skeleton3D", true, false):
			var s := sk as Skeleton3D
			for i in s.get_bone_count():
				s.reset_bone_pose(i)
		print("[INS] jugador CONGELADO en reposo (sin animación)")

	await get_tree().create_timer(0.3).timeout
	_volcar()


func _volcar() -> void:
	if _jug == null:
		return
	var sk := _jug.find_child("GeneralSkeleton", true, false) as Skeleton3D
	var piel := sk.get_node_or_null("AguilaSkinned") as MeshInstance3D if sk != null else null
	var maniq := sk.get_node_or_null("Mannequin") as MeshInstance3D if sk != null else null
	var vis_p := "—"
	if piel != null:
		vis_p = str(piel.visible)
	var vis_m := "—"
	if maniq != null:
		vis_m = str(maniq.visible)
	print("[INS] AguilaSkinned visible=", vis_p, "  Mannequin visible=", vis_m)
	print("[INS] Animations que siguen reproduciéndose:")
	for ap in _jug.find_children("*", "AnimationPlayer", true, false):
		var p := ap as AnimationPlayer
		if p.is_playing():
			print("   - %s -> %s (pos %.2f)" % [p.name, str(p.current_animation), p.current_animation_position])
	if sk != null:
		for bn in ["Hips", "LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightHand", "Head", "LeftFoot", "RightFoot"]:
			var bi := sk.find_bone(bn)
			if bi >= 0:
				var pos := (sk.global_transform * sk.get_bone_global_pose(bi)).origin
				print("[INS] %s: mundo %s" % [bn, str(pos.snappedf(0.001))])