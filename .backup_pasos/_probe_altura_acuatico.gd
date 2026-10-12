extends Node
## Diagnóstico temporal: medir globalmente puntas de pie/toes en escena integrada
## contra el plano de suelo asumido en y=CharacterBody3D.global_position.y.

var _jug: Node3D
var _ap: AnimationPlayer
var _sk: Skeleton3D

func _ready() -> void:
	_jug = (load("res://personaje/base/escenas/leo_jugador.tscn") as PackedScene).instantiate() as Node3D
	add_child(_jug)
	_jug.set_physics_process(false)
	_jug.set_process(false)
	_jug.global_position = Vector3.ZERO
	_ap = _jug.get_node("Acuatico/AnimadorAcuatico") as AnimationPlayer
	_sk = _jug.get_node("Acuatico/Visual/CharacterModel/Skeleton3D") as Skeleton3D
	print("[probe] transforms root=", _jug.transform, " acuatico=", _jug.get_node("Acuatico").transform, " visual=", _jug.get_node("Acuatico/Visual").transform, " model=", _jug.get_node("Acuatico/Visual/CharacterModel").transform, " armature=", _jug.get_node("Acuatico/Visual/CharacterModel/Armature").transform, " skeleton=", _sk.transform)
	print("[probe] collision=", (_jug.get_node("Colision") as CollisionShape3D).transform, " shape=", (_jug.get_node("Colision") as CollisionShape3D).shape)
	print("[probe] lib clips=", _ap.get_animation_list())
	for clip: String in ["idle_stand", "walk", "run", "jump", "fall", "swim_forward"]:
		await _measure_clip(clip)
	get_tree().quit()

func _measure_clip(clip: String) -> void:
	if not _ap.has_animation(clip):
		print("[probe] missing clip ", clip)
		return
	var anim: Animation = _ap.get_animation(clip)
	_ap.play(clip)
	_ap.pause()
	var min_left := INF
	var max_left := -INF
	var min_right := INF
	var max_right := -INF
	var min_hip := INF
	var max_hip := -INF
	var samples := 0
	for i: int in range(0, 61):
		var t: float = anim.length * float(i) / 60.0
		_ap.seek(t, true)
		_sk.force_update_all_bone_transforms()
		var lidx: int = _sk.find_bone("mixamorig_LeftToe_End")
		var ridx: int = _sk.find_bone("mixamorig_RightToe_End")
		var hidx: int = _sk.find_bone("mixamorig_Hips")
		var ly: float = (_sk.global_transform * _sk.get_bone_global_pose(lidx)).origin.y
		var ry: float = (_sk.global_transform * _sk.get_bone_global_pose(ridx)).origin.y
		var hy: float = (_sk.global_transform * _sk.get_bone_global_pose(hidx)).origin.y
		min_left = minf(min_left, ly); max_left = maxf(max_left, ly)
		min_right = minf(min_right, ry); max_right = maxf(max_right, ry)
		min_hip = minf(min_hip, hy); max_hip = maxf(max_hip, hy)
		samples += 1
	print("[probe] %s len=%.4f samples=%d toe_endY L=[%.4f,%.4f] R=[%.4f,%.4f] hipsY=[%.4f,%.4f] relative_floor=0" % [clip, anim.length, samples, min_left, max_left, min_right, max_right, min_hip, max_hip])