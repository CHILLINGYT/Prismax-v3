class_name NPCAnimationBaker
extends RefCounted

## HERRAMIENTA DE DESARROLLO (no se ejecuta durante el juego).
##
## Los ciudadanos usan los modelos de "Characters_psx" (rig Mixamo), pero sus animaciones
## vienen de otros packs con rigs distintos:
##   - "Human Basic Motions"  -> rig propio (B-hips, B-spine, B-upperArm.L, ...)
##   - "Universal Animation Lib" 1 y 2 -> rig estilo Unreal (pelvis, spine_01, upperarm_l, ...)
##
## Esta herramienta convierte (retargetea) esos clips al rig Mixamo y genera una
## AnimationLibrary COMPARTIDA que usan todos los NPCs:
##
##   res://NPCs/Animations/Citizen_Animations.res   (clips)
##   res://NPCs/Animations/Citizen_Locomotion.tres  (AnimationTree Idle/Walk)
##   res://NPCs/Navigation/NPC_TestGround.tres      (NavigationMesh del terreno de prueba)
##
## Cómo funciona el retarget:
##   Los rigs NO tienen la misma pose de reposo (Human Basic Motions y Universal Animation
##   Library están en T-Pose; los personajes PSX tienen los brazos bajados), así que aplicar
##   el delta de rotación en espacio mundial o en el marco local del hueso da poses rotas.
##   En su lugar se transfiere, hueso por hueso:
##     1. la DIRECCIÓN del hueso (columna Y de su base global animada de la fuente), y
##     2. el GIRO (twist) de la fuente alrededor de esa dirección, relativo a su reposo.
##   Las posiciones sólo se transfieren para la cadera (balanceo vertical), escaladas por
##   la diferencia de altura entre rigs, y al final se mide el deslizamiento del pie para
##   aplicar una corrección constante en Y y que los pies queden apoyados en el piso.
##
## Para volver a generar los recursos, ejecutar build_all() desde el editor/headless.

const TARGET_RIG := "res://NPCs/Characters/PSX/Male/Character_01.fbx"
const TRACK_PREFIX := "Model/Skeleton3D:"
const OUT_LIBRARY := "res://NPCs/Animations/Citizen_Animations.res"
const OUT_TREE := "res://NPCs/Animations/Citizen_Locomotion.tres"
const OUT_NAVMESH := "res://NPCs/Navigation/NPC_TestGround.tres"
const SAMPLE_FPS := 30.0

## Huesos del rig "Human Basic Motions" -> huesos Mixamo de los personajes PSX.
const HBM_MAP := {
	"B-hips": "mixamorig_Hips",
	"B-spine": "mixamorig_Spine",
	"B-chest": "mixamorig_Spine1",
	"B-neck": "mixamorig_Neck",
	"B-head": "mixamorig_Head",
	"B-shoulder.L": "mixamorig_LeftShoulder",
	"B-upperArm.L": "mixamorig_LeftArm",
	"B-forearm.L": "mixamorig_LeftForeArm",
	"B-hand.L": "mixamorig_LeftHand",
	"B-shoulder.R": "mixamorig_RightShoulder",
	"B-upperArm.R": "mixamorig_RightArm",
	"B-forearm.R": "mixamorig_RightForeArm",
	"B-hand.R": "mixamorig_RightHand",
	"B-thigh.L": "mixamorig_LeftUpLeg",
	"B-shin.L": "mixamorig_LeftLeg",
	"B-foot.L": "mixamorig_LeftFoot",
	"B-toe.L": "mixamorig_LeftToeBase",
	"B-thigh.R": "mixamorig_RightUpLeg",
	"B-shin.R": "mixamorig_RightLeg",
	"B-foot.R": "mixamorig_RightFoot",
	"B-toe.R": "mixamorig_RightToeBase",
}

## Huesos del rig de Universal Animation Library -> huesos Mixamo.
const UAL_MAP := {
	"pelvis": "mixamorig_Hips",
	"spine_01": "mixamorig_Spine",
	"spine_02": "mixamorig_Spine1",
	"spine_03": "mixamorig_Spine2",
	"neck_01": "mixamorig_Neck",
	"Head": "mixamorig_Head",
	"clavicle_l": "mixamorig_LeftShoulder",
	"upperarm_l": "mixamorig_LeftArm",
	"lowerarm_l": "mixamorig_LeftForeArm",
	"hand_l": "mixamorig_LeftHand",
	"clavicle_r": "mixamorig_RightShoulder",
	"upperarm_r": "mixamorig_RightArm",
	"lowerarm_r": "mixamorig_RightForeArm",
	"hand_r": "mixamorig_RightHand",
	"thigh_l": "mixamorig_LeftUpLeg",
	"calf_l": "mixamorig_LeftLeg",
	"foot_l": "mixamorig_LeftFoot",
	"ball_l": "mixamorig_LeftToeBase",
	"thigh_r": "mixamorig_RightUpLeg",
	"calf_r": "mixamorig_RightLeg",
	"foot_r": "mixamorig_RightFoot",
	"ball_r": "mixamorig_RightToeBase",
}

## --- Rig Auto-Rig Pro (City Folks / Urban Man) ------------------------------------------
## Los modelos nuevos (City Folks y Urban Man) comparten un rig de 59 huesos de Auto-Rig Pro
## (root.x, spine_01.x, arm_stretch.l...). Para ellos se hornea la MISMA lista de clips ya
## validados, cambiando sólo el nombre de hueso de destino.
const ARP_TARGET := "res://Assets NPCS/UrbanMan_PolyMate_alstrainfinite/GLB/UrbanMan_CityFolks_PolyMate.glb"
const OUT_LIBRARY_ARP := "res://NPCs/Animations/Citizen_Animations_ARP.res"

const ARP_NAME_OF := {
	"mixamorig_Hips": "root.x",
	"mixamorig_Spine": "spine_01.x",
	"mixamorig_Spine1": "spine_02.x",
	"mixamorig_Neck": "neck.x",
	"mixamorig_Head": "head.x",
	"mixamorig_LeftShoulder": "shoulder.l",
	"mixamorig_LeftArm": "arm_stretch.l",
	"mixamorig_LeftForeArm": "forearm_stretch.l",
	"mixamorig_LeftHand": "hand.l",
	"mixamorig_RightShoulder": "shoulder.r",
	"mixamorig_RightArm": "arm_stretch.r",
	"mixamorig_RightForeArm": "forearm_stretch.r",
	"mixamorig_RightHand": "hand.r",
	"mixamorig_LeftUpLeg": "thigh_stretch.l",
	"mixamorig_LeftLeg": "leg_stretch.l",
	"mixamorig_LeftFoot": "foot.l",
	"mixamorig_LeftToeBase": "toes_01.l",
	"mixamorig_RightUpLeg": "thigh_stretch.r",
	"mixamorig_RightLeg": "leg_stretch.r",
	"mixamorig_RightFoot": "foot.r",
	"mixamorig_RightToeBase": "toes_01.r",
}

## Rig de 3ds Max Biped del pack "RPG Animations GLB FREE" (53 huesos, unidades ~cm).
const DIR_RPG := "res://Assets NPCS/RPG_Animations_GLB_FREE/Unarmed.glb"
const RPG_MAP := {
	"B_Pelvis": "mixamorig_Hips",
	"B_Spine": "mixamorig_Spine",
	"B_Spine1": "mixamorig_Spine1",
	"B_Spine2": "mixamorig_Spine2",
	"B_Neck": "mixamorig_Neck",
	"B_Head": "mixamorig_Head",
	"B_L_Clavicle": "mixamorig_LeftShoulder",
	"B_L_UpperArm": "mixamorig_LeftArm",
	"B_L_Forearm": "mixamorig_LeftForeArm",
	"B_L_Hand": "mixamorig_LeftHand",
	"B_R_Clavicle": "mixamorig_RightShoulder",
	"B_R_UpperArm": "mixamorig_RightArm",
	"B_R_Forearm": "mixamorig_RightForeArm",
	"B_R_Hand": "mixamorig_RightHand",
	"B_L_Thigh": "mixamorig_LeftUpLeg",
	"B_L_Calf": "mixamorig_LeftLeg",
	"B_L_Foot": "mixamorig_LeftFoot",
	"B_L_Toe0": "mixamorig_LeftToeBase",
	"B_R_Thigh": "mixamorig_RightUpLeg",
	"B_R_Calf": "mixamorig_RightLeg",
	"B_R_Foot": "mixamorig_RightFoot",
	"B_R_Toe0": "mixamorig_RightToeBase",
}

## Clips que sólo se hornean para el rig nuevo. El pack RPG Animations es de COMBATE (guardia
## con los brazos arriba): se midió que su "Idle" (manos +0,55 alturas por delante) y sus
## "Strafe" no sirven para un peatón civil, y que su única caminata, "WalkInjured", cojea.
## En cambio su carrera, su sprint y sus giros de 90° son mejores que lo que ya había.
const JOBS_ARP_EXTRA := [
	{"clip": "run_fwd_rpg", "rig": DIR_RPG, "anim": "UnarmedRunForward", "map": RPG_MAP, "loop": true, "kind": "run"},
	{"clip": "sprint_rpg", "rig": DIR_RPG, "anim": "UnarmedSprint", "map": RPG_MAP, "loop": true, "kind": "run"},
	{"clip": "turn90_l_rpg", "rig": DIR_RPG, "anim": "UnarmedTurnLeft90", "map": RPG_MAP, "loop": false, "kind": "turn"},
	{"clip": "turn90_r_rpg", "rig": DIR_RPG, "anim": "UnarmedTurnRight90", "map": RPG_MAP, "loop": false, "kind": "turn"},
	{"clip": "pickup_rpg", "rig": DIR_RPG, "anim": "UnarmedPickup", "map": RPG_MAP, "loop": false, "kind": "react"},
]

## Clips de AIRE del pack RPG — el único de los cuatro que trae salto, caída y aterrizaje. Se
## hornean también para el rig Mixamo porque los usa el jugador de prueba (los ciudadanos no saltan).
const JOBS_AIR := [
	{"clip": "jump_m1", "rig": DIR_RPG, "anim": "UnarmedJump", "map": RPG_MAP, "loop": false, "kind": "jump"},
	{"clip": "fall_m1", "rig": DIR_RPG, "anim": "UnarmedFall", "map": RPG_MAP, "loop": true, "kind": "fall"},
	{"clip": "land_m1", "rig": DIR_RPG, "anim": "UnarmedLand", "map": RPG_MAP, "loop": false, "kind": "land"},
]

const DIR_HBM := "res://NPCs/Animations/HumanBasic/"
const DIR_UAL1 := "res://NPCs/Animations/UAL1/UAL1_Standard.glb"
const DIR_UAL2 := "res://NPCs/Animations/UAL2/UAL2_Standard.glb"

## Clips a hornear. "map" elige el mapa de huesos según el rig de origen y "kind" clasifica
## cada clip (idle / walk / run / jog / turn) para que el ciudadano sepa cómo usarlo.
const JOBS := [
	# Human Basic Motions - masculino
	{"clip": "idle_m1", "rig": DIR_HBM + "Male/Idles/HumanM@Idle01.fbx", "anim": "", "map": HBM_MAP, "loop": true, "kind": "idle"},
	{"clip": "idle_m2", "rig": DIR_HBM + "Male/Idles/HumanM@Idle02.fbx", "anim": "", "map": HBM_MAP, "loop": true, "kind": "idle"},
	{"clip": "walk_m1", "rig": DIR_HBM + "Male/Movement/Walk/HumanM@Walk01_Forward.fbx", "anim": "", "map": HBM_MAP, "loop": true, "kind": "walk"},
	{"clip": "run_m1", "rig": DIR_HBM + "Male/Movement/Run/HumanM@Run01_Forward.fbx", "anim": "", "map": HBM_MAP, "loop": true, "kind": "run"},
	# Human Basic Motions - femenino
	{"clip": "idle_f1", "rig": DIR_HBM + "Female/Idles/HumanF@Idle01.fbx", "anim": "", "map": HBM_MAP, "loop": true, "kind": "idle"},
	{"clip": "idle_f2", "rig": DIR_HBM + "Female/Idles/HumanF@Idle02.fbx", "anim": "", "map": HBM_MAP, "loop": true, "kind": "idle"},
	{"clip": "walk_f1", "rig": DIR_HBM + "Female/Movement/Walk/HumanF@Walk01_Forward.fbx", "anim": "", "map": HBM_MAP, "loop": true, "kind": "walk"},
	{"clip": "run_f1", "rig": DIR_HBM + "Female/Movement/Run/HumanF@Run01_Forward.fbx", "anim": "", "map": HBM_MAP, "loop": true, "kind": "run"},
	# Giros en el sitio, para la secuencia Caminar -> Girar -> Caminar
	{"clip": "turn_m1_l", "rig": DIR_HBM + "Male/Movement/Turn/HumanM@Turn01_Left.fbx", "anim": "", "map": HBM_MAP, "loop": false, "kind": "turn"},
	{"clip": "turn_m1_r", "rig": DIR_HBM + "Male/Movement/Turn/HumanM@Turn01_Right.fbx", "anim": "", "map": HBM_MAP, "loop": false, "kind": "turn"},
	{"clip": "turn_f1_l", "rig": DIR_HBM + "Female/Movement/Turn/HumanF@Turn01_Left.fbx", "anim": "", "map": HBM_MAP, "loop": false, "kind": "turn"},
	{"clip": "turn_f1_r", "rig": DIR_HBM + "Female/Movement/Turn/HumanF@Turn01_Right.fbx", "anim": "", "map": HBM_MAP, "loop": false, "kind": "turn"},
	# Universal Animation Library 1 (rig tipo maniquí, sirve para ambos géneros).
	# Se descartaron a propósito tres clips que NO son caminatas civiles (medidos con sonda):
	#   Walk_Formal     (brazos rígidos, balanceo 0.07 m)
	#   Walk_Carry      (brazos adelantados +0.19 m y codo 57°: parece llevar algo en las manos)
	#   Idle_FoldArms   (codo 103°: brazos cruzados)
	{"clip": "idle_u1", "rig": DIR_UAL1, "anim": "Idle", "map": UAL_MAP, "loop": true, "kind": "idle"},
	{"clip": "idle_u3", "rig": DIR_UAL1, "anim": "Idle_Talking", "map": UAL_MAP, "loop": true, "kind": "idle"},
	{"clip": "walk_u1", "rig": DIR_UAL1, "anim": "Walk", "map": UAL_MAP, "loop": true, "kind": "walk"},
	{"clip": "jog_u1", "rig": DIR_UAL1, "anim": "Jog_Fwd", "map": UAL_MAP, "loop": true, "kind": "jog"},
	{"clip": "run_u1", "rig": DIR_UAL1, "anim": "Sprint", "map": UAL_MAP, "loop": true, "kind": "run"},
	# Universal Animation Library 2 (complemento): un gesto real y compatible para las reacciones
	# ("Yes" es un asentimiento con la cabeza; no se inventa ninguna animación).
	{"clip": "nod_u1", "rig": DIR_UAL2, "anim": "Yes", "map": UAL_MAP, "loop": false, "kind": "react"},
]

## Clips de VIDA COTIDIANA añadidos en la etapa de variedad. Se hornean SÓLO para el rig de los
## ciudadanos (Auto-Rig Pro). Todos se midieron en su rig de origen ANTES de elegirlos (mano
## respecto del pecho, altura de la mano respecto de la cabeza, distancia mano-cabeza y caída de
## la cabeza) y se descartaron los que no son de peatón civil:
##   UAL2 Idle_Lantern / Idle_Rail / Idle_Rail_Call -> la mano va por delante a la altura del pecho
##                                                     (parece llevar algo o apoyarse en algo invisible)
##   UAL1 Idle_Torch / Fixing_Kneeling / Sitting_*   -> necesitan un objeto o un sitio donde sentarse
##   UAL1 Walk_Formal                                -> camina bien, pero los brazos casi no se mueven
##   UAL1/UAl2 Walk_Carry                            -> brazos adelantados (parece llevar algo)
##
## "kind" es la CATEGORÍA del clip y es lo que usan los ciudadanos para armar sus listas, así que
## agregar una animación nueva es sólo agregar una línea aquí:
##   idle   -> quieto (puede ir en cualquiera de los cuatro huecos de idle)
##   social -> quieto "de vida" (teléfono, estirar) que sólo se cuela de vez en cuando
##   walk / jog / run / turn -> locomoción (turn: "_l" izquierda, "_r" derecha)
##   react  -> gesto breve de reacción al jugador
##   air    -> salto, caída y aterrizaje (sólo los personajes con salto)
const JOBS_SOCIAL := [
	# Un tercer idle masculino del pack de movimientos básicos.
	{"clip": "idle_m3", "rig": DIR_HBM + "Male/Idles/HumanM@Idle01-Idle02.fbx", "anim": "", "map": HBM_MAP, "loop": true, "kind": "idle"},
	# Agachado: la cabeza baja 0,50 alturas (un peatón que se ata los cordones).
	{"clip": "crouch_u1", "rig": DIR_UAL1, "anim": "Crouch_Idle", "map": UAL_MAP, "loop": true, "kind": "idle"},
	# Estirar el pecho: la cabeza baja 0,19 y las manos se van hacia atrás.
	{"clip": "stretch_u1", "rig": DIR_UAL2, "anim": "Chest_Open", "map": UAL_MAP, "loop": true, "kind": "idle"},
	# Al teléfono: la mano llega a la altura de la cabeza y se le queda a 0,15 alturas (medido).
	{"clip": "phone_u1", "rig": DIR_UAL2, "anim": "Idle_TalkingPhone", "map": UAL_MAP, "loop": true, "kind": "social"},
	# Reacciones: negar con la cabeza y un gesto con la mano hasta la altura del hombro.
	{"clip": "shake_u1", "rig": DIR_UAL2, "anim": "Idle_No", "map": UAL_MAP, "loop": false, "kind": "react"},
	{"clip": "gesture_u1", "rig": DIR_UAL1, "anim": "Interact", "map": UAL_MAP, "loop": false, "kind": "react"},
]

var _rig_cache: Dictionary = {}
var _report: Array[String] = []


## Hornea la librería del rig Mixamo (modelos PSX: es la de siempre) más los tres clips de aire y
## los de vida cotidiana. Se mantiene como superconjunto de lo que pide el árbol de estados, así
## que ningún rig se queda sin los clips que la máquina de estados conoce.
static func build_all() -> Array[String]:
	return NPCAnimationBaker.new()._build_all(TARGET_RIG, {}, OUT_LIBRARY, JOBS + JOBS_AIR + JOBS_SOCIAL, true)


## Hornea la librería del rig Auto-Rig Pro (City Folks / Urban Man): los mismos clips validados
## + los del pack RPG que aportan algo + los de vida cotidiana (JOBS_SOCIAL).
static func build_all_arp() -> Array[String]:
	return NPCAnimationBaker.new()._build_all(
		ARP_TARGET, ARP_NAME_OF, OUT_LIBRARY_ARP, JOBS + JOBS_ARP_EXTRA + JOBS_SOCIAL, true
	)


func _build_all(target_path: String, name_of: Dictionary, out_library: String, jobs: Array, with_extras: bool) -> Array[String]:
	for out: String in [out_library, OUT_TREE, OUT_NAVMESH]:
		DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	var target: Dictionary = _load_rig(target_path, "target")
	if target.is_empty():
		_report.append("ERROR  no se pudo cargar el rig destino %s" % target_path)
		return _report
	target["name_of"] = name_of
	var library := AnimationLibrary.new()
	for job: Dictionary in jobs:
		var src: Dictionary = _load_rig(job["rig"], "src")
		if src.is_empty():
			_report.append("ERROR  no se pudo cargar %s" % job["rig"])
			continue
		var anim: Animation = _pick_animation(src, job["anim"])
		if anim == null:
			_report.append("ERROR  sin animación en %s (%s)" % [job["rig"], job["anim"]])
			continue
		var clip: Animation = _retarget(target, src, anim, job["map"], job["loop"], String(job.get("kind", "")))
		if clip == null:
			_report.append("ERROR  no se pudo retargetear %s" % job["clip"])
			continue
		clip.resource_name = String(job["clip"])
		library.add_animation(job["clip"], clip)
		_report.append("clip %-9s %5.2fs  %3d claves/hueso  vel=%.2f m/s  corr_pie=%+.3f  (%s)" % [
			job["clip"], clip.length, int(round(clip.length * SAMPLE_FPS)) + 1,
			clip.get_meta("speed", 0.0), clip.get_meta("foot_fix", 0.0),
			String(job["rig"]).get_file() + ("#" + job["anim"] if job["anim"] != "" else ""),
		])
	var err := ResourceSaver.save(library, out_library)
	_report.append("library -> %s (%d clips, err=%d)" % [out_library, library.get_animation_list().size(), err])
	if with_extras:
		_build_tree()
		_build_test_navmesh()
	return _report


# ---------------------------------------------------------------- carga de rigs

func _load_rig(path: String, role: String) -> Dictionary:
	if _rig_cache.has(path):
		return _rig_cache[path]
	var root: Node = _instantiate_rig(path, role == "src")
	if root == null:
		return {}
	var skel: Skeleton3D = _find(root, "Skeleton3D")
	var player: AnimationPlayer = _find(root, "AnimationPlayer")
	if skel == null:
		root.free()
		return {}
	var count := skel.get_bone_count()
	var names := PackedStringArray()
	var parents := PackedInt32Array()
	var rest: Array[Transform3D] = []
	for i in count:
		names.append(skel.get_bone_name(i))
		parents.append(skel.get_bone_parent(i))
		rest.append(skel.get_bone_rest(i))
	var anims: Dictionary = {}
	if player != null:
		for a in player.get_animation_list():
			anims[String(a)] = player.get_animation(a)
	# Estos modelos traen los huesos en centésimas de metro y la escala real (0,01) en la
	# cadena de nodos por encima del esqueleto. Todo lo que se mida en metros (velocidad de
	# la animación, altura de apoyo del pie) hay que convertirlo con esto.
	var unit_scale := 1.0
	var node: Node = skel
	while node != null:
		if node is Node3D:
			unit_scale *= (node as Node3D).scale.y
		node = node.get_parent()
	var rig := {
		"path": path,
		"names": names,
		"parents": parents,
		"rest": rest,
		"order": _hierarchy_order(parents),
		"anims": anims,
		"role": role,
		"unit_scale": unit_scale,
	}
	rig["rest_global"] = _forward_kinematics(rig, {})
	rig["align"] = _src_align(rig)
	var align: Basis = rig["align"]
	# El alineado se aplica en los huesos raíz, así que hay que dejarlo también en el reposo
	# del ORIGEN (el destino se queda con su reposo tal cual).
	if role == "src" and not align.is_equal_approx(Basis.IDENTITY):
		for i in count:
			if parents[i] < 0:
				rest[i] = Transform3D(align, Vector3.ZERO) * rest[i]
		rig["rest_global"] = _forward_kinematics(rig, {})
	root.free()
	_rig_cache[path] = rig
	return rig


## Carga un rig como escena. Los FBX sólo existen a través de la importación del editor; los
## .glb se pueden abrir en crudo con GLTFDocument cuando la importación no trae animaciones.
func _instantiate_rig(path: String, need_anims: bool) -> Node:
	var raw: bool = path.get_extension().to_lower() == "glb"
	if ResourceLoader.exists(path):
		var ps: PackedScene = load(path)
		if ps != null:
			var node: Node = ps.instantiate()
			if not need_anims or _find(node, "AnimationPlayer") != null or not raw:
				return node
			node.free()
	elif not raw:
		return null
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(path, state) != OK:
		return null
	return doc.generate_scene(state)


## Rotación que lleva el rig de ORIGEN al convenio del proyecto (+Y arriba, +Z al frente).
## Los rigs de 3ds Max Biped (pack RPG) vienen en otro convenio: sin esto, copiar direcciones
## entre rigs produce poses giradas. Para los rigs ya alineados devuelve la identidad.
func _src_align(rig: Dictionary) -> Basis:
	var names: PackedStringArray = rig["names"]
	var rest: Array[Transform3D] = rig["rest_global"]
	var hips := _bone_named(names, ["mixamorig_Hips", "B_Pelvis", "pelvis", "root.x"])
	var head := _bone_named(names, ["mixamorig_Head", "B_Head", "Head", "head.x"])
	var ankle := _bone_named(names, ["mixamorig_LeftFoot", "B_L_Foot", "foot_l", "foot.l"])
	var toe := _bone_named(names, ["mixamorig_LeftToeBase", "B_L_Toe0", "ball_l", "toes_01.l"])
	if hips < 0 or head < 0 or ankle < 0 or toe < 0:
		return Basis.IDENTITY
	var up := (rest[head].origin - rest[hips].origin).normalized()
	var flat := rest[toe].origin - rest[ankle].origin
	flat -= up * flat.dot(up)
	if flat.length_squared() < 0.0001:
		return Basis.IDENTITY
	var fwd := flat.normalized()
	var x_axis := up.cross(fwd)
	if x_axis.length_squared() < 0.0001:
		return Basis.IDENTITY
	x_axis = x_axis.normalized()
	var source := Basis(x_axis, up, fwd)
	var align := source.transposed()
	# Si el rig ya está prácticamente en el convenio del proyecto, no se toca nada: así el
	# horneado de los rigs que ya funcionaban no cambia ni un grado.
	if align.get_rotation_quaternion().angle_to(Quaternion.IDENTITY) < deg_to_rad(10.0):
		return Basis.IDENTITY
	return align


## Nombre del hueso de destino para un papel (los papeles se escriben con los nombres Mixamo).
func _target_name(tgt_of: Dictionary, mixamo: String) -> String:
	return String(tgt_of.get(mixamo, mixamo))


func _find(root: Node, cls: String) -> Node:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n.is_class(cls):
			return n
		for c in n.get_children():
			stack.push_back(c)
	return null


func _hierarchy_order(parents: PackedInt32Array) -> PackedInt32Array:
	var order := PackedInt32Array()
	var queue := PackedInt32Array()
	for i in parents.size():
		if parents[i] < 0:
			queue.append(i)
	while queue.size() > 0:
		var b: int = queue[0]
		queue.remove_at(0)
		order.append(b)
		for i in parents.size():
			if parents[i] == b:
				queue.append(i)
	return order


func _pick_animation(rig: Dictionary, want: String) -> Animation:
	var anims: Dictionary = rig["anims"]
	if want != "":
		return anims.get(want, null)
	if anims.size() == 1:
		return anims.values()[0]
	return null


# ---------------------------------------------------------------- cinemática directa

## Devuelve las transformadas globales (espacio del Skeleton3D) usando los huesos de `locals`
## (índice -> Transform3D) y la pose de reposo para los que falten.
func _forward_kinematics(rig: Dictionary, locals: Dictionary) -> Array[Transform3D]:
	var count: int = rig["names"].size()
	var out: Array[Transform3D] = []
	out.resize(count)
	for i in rig["order"]:
		var local: Transform3D = rig["rest"][i]
		if locals.has(i):
			local = locals[i]
		var p: int = rig["parents"][i]
		out[i] = (out[p] * local) if p >= 0 else local
	return out


func _sample_quat(anim: Animation, track: int, time: float) -> Quaternion:
	var n := anim.track_get_key_count(track)
	if n == 0:
		return Quaternion.IDENTITY
	if time <= anim.track_get_key_time(track, 0):
		return anim.track_get_key_value(track, 0)
	if time >= anim.track_get_key_time(track, n - 1):
		return anim.track_get_key_value(track, n - 1)
	var lo := 0
	var hi := n - 1
	while hi - lo > 1:
		var mid := (lo + hi) / 2
		if anim.track_get_key_time(track, mid) <= time:
			lo = mid
		else:
			hi = mid
	var t0 := anim.track_get_key_time(track, lo)
	var t1 := anim.track_get_key_time(track, hi)
	var f := (time - t0) / maxf(t1 - t0, 0.0001)
	return (anim.track_get_key_value(track, lo) as Quaternion).slerp(anim.track_get_key_value(track, hi), f)


func _sample_vec(anim: Animation, track: int, time: float) -> Vector3:
	var n := anim.track_get_key_count(track)
	if n == 0:
		return Vector3.ZERO
	if time <= anim.track_get_key_time(track, 0):
		return anim.track_get_key_value(track, 0)
	if time >= anim.track_get_key_time(track, n - 1):
		return anim.track_get_key_value(track, n - 1)
	var lo := 0
	var hi := n - 1
	while hi - lo > 1:
		var mid := (lo + hi) / 2
		if anim.track_get_key_time(track, mid) <= time:
			lo = mid
		else:
			hi = mid
	var t0 := anim.track_get_key_time(track, lo)
	var t1 := anim.track_get_key_time(track, hi)
	var f := (time - t0) / maxf(t1 - t0, 0.0001)
	return (anim.track_get_key_value(track, lo) as Vector3).lerp(anim.track_get_key_value(track, hi), f)


# ---------------------------------------------------------------- retarget

func _retarget(target: Dictionary, src: Dictionary, anim: Animation, bone_map: Dictionary, loop: bool, kind: String) -> Animation:
	# Índices de track por hueso de origen
	var rot_tracks: Dictionary = {}
	var pos_tracks: Dictionary = {}
	for t in anim.get_track_count():
		if anim.track_get_type(t) != Animation.TYPE_ROTATION_3D and anim.track_get_type(t) != Animation.TYPE_POSITION_3D:
			continue
		var bone_name := str(anim.track_get_path(t).get_concatenated_subnames())
		var si: int = src["names"].find(bone_name)
		if si < 0:
			continue
		if anim.track_get_type(t) == Animation.TYPE_ROTATION_3D:
			rot_tracks[si] = t
		else:
			pos_tracks[si] = t

	# Correspondencia hueso destino -> hueso origen
	var tgt_of: Dictionary = target.get("name_of", {})
	var src_align: Basis = src.get("align", Basis.IDENTITY)
	var has_align := not src_align.is_equal_approx(Basis.IDENTITY)
	var bone_of: Dictionary = {}
	for src_name: String in bone_map:
		var si: int = src["names"].find(src_name)
		var ti: int = target["names"].find(_target_name(tgt_of, bone_map[src_name]))
		if si >= 0 and ti >= 0:
			bone_of[ti] = si
	var src_hips: int = src["names"].find(_src_name_for(bone_map, "mixamorig_Hips"))
	var tgt_hips: int = target["names"].find(_target_name(tgt_of, "mixamorig_Hips"))
	if src_hips < 0 or tgt_hips < 0:
		return null

	var src_rest: Array[Transform3D] = src["rest_global"]
	var tgt_rest: Array[Transform3D] = target["rest_global"]
	var pos_scale := tgt_rest[tgt_hips].origin.y / maxf(src_rest[src_hips].origin.y, 0.001)
	var unit_scale: float = target.get("unit_scale", 1.0)
	# Las dos mallas miran hacia +Z con Y arriba, por lo que las direcciones se pueden
	# comparar directamente entre rigs (sin corrección de orientación adicional).

	# Pies: se mide el apoyo en el piso (corrección de altura) y la zancada real
	# (desplazamiento del tobillo mientras el pie está apoyado -> velocidad de la animación).
	var foot_of: Dictionary = {}
	for name_of: String in ["mixamorig_LeftFoot", "mixamorig_RightFoot"]:
		var ti_foot: int = target["names"].find(_target_name(tgt_of, name_of))
		if ti_foot >= 0:
			foot_of[ti_foot] = []
	var toe_of: Dictionary = {}
	for pair: Array in [["mixamorig_LeftToeBase", "mixamorig_LeftToeBase"], ["mixamorig_RightToeBase", "mixamorig_RightToeBase"]]:
		var src_toe: int = src["names"].find(_src_name_for(bone_map, pair[0]))
		var tgt_toe: int = target["names"].find(_target_name(tgt_of, pair[1]))
		if src_toe >= 0 and tgt_toe >= 0:
			toe_of[tgt_toe] = INF

	var length := anim.length
	var frames := maxi(2, int(round(length * SAMPLE_FPS)))
	var step := length / float(frames)
	var rot_keys: Dictionary = {}
	var hips_keys := PackedVector3Array()
	for k in toe_of:
		toe_of[k] = INF
	var tgt_fwd_axis := _forward_dir(target).normalized()

	for frame in frames + 1:
		var t := frame * step
		# --- globals del rig de origen
		var sg: Array[Transform3D] = []
		sg.resize(src["names"].size())
		for si in src["order"]:
			var local: Transform3D = src["rest"][si]
			if rot_tracks.has(si):
				local.basis = Basis(_sample_quat(anim, rot_tracks[si], t))
			if pos_tracks.has(si):
				local.origin = _sample_vec(anim, pos_tracks[si], t)
			var p: int = src["parents"][si]
			if p < 0 and has_align:
				local = Transform3D(src_align, Vector3.ZERO) * local
			sg[si] = (sg[p] * local) if p >= 0 else local
		var hips_delta := (sg[src_hips].origin - src_rest[src_hips].origin) * pos_scale

		# --- globals del rig destino
		var tg: Array[Transform3D] = []
		tg.resize(target["names"].size())
		for ti in target["order"]:
			var tl: Transform3D = target["rest"][ti]
			var ti_parent: int = target["parents"][ti]
			var parent_global: Transform3D = tg[ti_parent] if ti_parent >= 0 else Transform3D.IDENTITY
			if bone_of.has(ti):
				var si2: int = bone_of[ti]
				var wanted := _aligned_basis(sg[si2], src_rest[si2], tgt_rest[ti])
				tl.basis = parent_global.basis.inverse() * wanted
				if not rot_keys.has(ti):
					rot_keys[ti] = []
			if ti == tgt_hips:
				tl.origin = target["rest"][ti].origin + parent_global.basis.inverse() * hips_delta
			tg[ti] = parent_global * tl
			if rot_keys.has(ti):
				# OJO: la clave de un track de hueso es la rotación LOCAL del hueso
				# (respecto de su padre), no la global.
				var q := tl.basis.get_rotation_quaternion()
				var keys: Array = rot_keys[ti]
				if keys.size() > 0 and keys[-1].dot(q) < 0.0:
					q = -q
				keys.append(q)
			if toe_of.has(ti):
				toe_of[ti] = minf(toe_of[ti], tg[ti].origin.y)
			if foot_of.has(ti):
				foot_of[ti].append(Vector2(tg[ti].origin.dot(tgt_fwd_axis), tg[ti].origin.y))
			if ti == tgt_hips:
				hips_keys.append(tl.origin)

	# Corrección de apoyo: el pie más bajo del ciclo debe quedar a la altura del reposo
	var foot_fix := 0.0
	var samples := 0
	for ti in toe_of:
		if toe_of[ti] < INF:
			foot_fix += tgt_rest[ti].origin.y - toe_of[ti]
			samples += 1
	if samples > 0:
		foot_fix = clampf(foot_fix / samples, -0.15 / unit_scale, 0.15 / unit_scale)

	# Velocidad implícita: durante el apoyo el tobillo retrocede respecto del cuerpo
	# exactamente a la velocidad de avance. Se busca la racha monótona más larga
	# alrededor del punto más bajo del pie y se divide el recorrido por su duración.
	var speed_total := 0.0
	var speed_feet := 0
	for ti in foot_of:
		var list: Array = foot_of[ti]
		if list.size() < 4:
			continue
		var i_min := 0
		for i in list.size():
			if list[i].y < list[i_min].y:
				i_min = i
		var i0 := i_min
		while i0 > 0 and list[i0 - 1].x > list[i0].x:
			i0 -= 1
		var i1 := i_min
		while i1 < list.size() - 1 and list[i1 + 1].x < list[i1].x:
			i1 += 1
		var travel: float = list[i0].x - list[i1].x
		var duration := float(i1 - i0) * step
		if duration > 0.08 and travel > 0.05 / unit_scale:
			speed_total += travel / duration
			speed_feet += 1
	# La velocidad se mide en unidades de esqueleto; se pasa a metros de escena.
	var speed := (speed_total / float(speed_feet) if speed_feet > 0 else 0.0) * unit_scale

	# --- construcción del clip
	var clip := Animation.new()
	clip.length = length
	clip.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	clip.step = 1.0 / SAMPLE_FPS
	for ti in rot_keys:
		var track := clip.add_track(Animation.TYPE_ROTATION_3D)
		clip.track_set_path(track, NodePath(TRACK_PREFIX + String(target["names"][ti])))
		clip.track_set_interpolation_type(track, Animation.INTERPOLATION_LINEAR)
		var keys: Array = rot_keys[ti]
		for i in keys.size():
			clip.track_insert_key(track, i * step, keys[i])
	var hips_track := clip.add_track(Animation.TYPE_POSITION_3D)
	clip.track_set_path(hips_track, NodePath(TRACK_PREFIX + _target_name(tgt_of, "mixamorig_Hips")))
	clip.track_set_interpolation_type(hips_track, Animation.INTERPOLATION_LINEAR)
	for i in hips_keys.size():
		clip.track_insert_key(hips_track, i * step, hips_keys[i] + Vector3(0.0, foot_fix, 0.0))
	clip.set_meta("speed", speed)
	clip.set_meta("foot_fix", foot_fix)
	clip.set_meta("loop", loop)
	clip.set_meta("kind", kind)
	clip.set_meta("source", src["path"])
	return clip


func _src_name_for(bone_map: Dictionary, mixamo: String) -> String:
	for k: String in bone_map:
		if bone_map[k] == mixamo:
			return k
	return ""


## Orientación global deseada para un hueso del destino a partir de su equivalente en la fuente.
## Se copia la DIRECCIÓN del hueso (columna Y de la base global animada de la fuente) y se
## agrega el twist relativo de la fuente respecto de su propio reposo, girado alrededor de esa
## misma dirección. Al no depender de la pose de reposo, funciona aunque los rigs no coincidan
## (por ejemplo fuente en T-Pose y personajes PSX con los brazos bajados).
func _aligned_basis(src_anim: Transform3D, src_rest: Transform3D, tgt_rest: Transform3D) -> Basis:
	var d_s := src_anim.basis.y.normalized()
	var d_t := tgt_rest.basis.y.normalized()
	if d_s.length_squared() < 0.5 or d_t.length_squared() < 0.5:
		return tgt_rest.basis
	var wanted := Basis(Quaternion(d_t, d_s)) * tgt_rest.basis
	var delta := (src_anim.basis * src_rest.basis.inverse()).get_rotation_quaternion()
	var tw := delta.x * d_s.x + delta.y * d_s.y + delta.z * d_s.z
	if absf(tw) > 0.000001 or absf(delta.w) < 0.999999:
		wanted = Basis(Quaternion(d_s, 2.0 * atan2(tw, delta.w))) * wanted
	return wanted


func _forward_dir(rig: Dictionary) -> Vector3:
	var names: PackedStringArray = rig["names"]
	var rest: Array[Transform3D] = rig["rest_global"]
	var left := _bone_named(names, ["mixamorig_LeftArm", "B-upperArm.L", "upperarm_l", "arm_stretch.l", "B_L_UpperArm"])
	var right := _bone_named(names, ["mixamorig_RightArm", "B-upperArm.R", "upperarm_r", "arm_stretch.r", "B_R_UpperArm"])
	if left < 0 or right < 0:
		return Vector3.ZERO
	var axis := rest[left].origin - rest[right].origin
	axis.y = 0.0
	return axis.normalized().cross(Vector3.UP)


func _bone_named(names: PackedStringArray, candidates: Array) -> int:
	for c: String in candidates:
		var i := names.find(c)
		if i >= 0:
			return i
	return -1


# ---------------------------------------------------------------- recursos auxiliares

func _build_tree() -> void:
	# Máquina de estados que comparten TODOS los ciudadanos (y el jugador de prueba). Los
	# nombres de los estados son fijos ("idle", "walk", "jog", "turn_l"...) y cada personaje
	# entrega sus propios clips bajo esos nombres: un solo recurso sirve para todos y aun
	# así nadie se mueve igual que otro.
	var sm := AnimationNodeStateMachine.new()
	var states := {
		# Cuatro huecos de quieto: cada ciudadano trae cuatro clips de idle distintos y va
		# saltando de uno a otro mientras espera, sin quedarse nunca con la misma pose.
		"idle": Vector2(120, 100),
		"idle_b": Vector2(120, 260),
		"idle_c": Vector2(120, 620),
		"idle_d": Vector2(120, 780),
		"walk": Vector2(380, 100),
		"jog": Vector2(380, 260),
		"turn_l": Vector2(380, 420),
		"turn_r": Vector2(380, 580),
		"react": Vector2(120, 420),
		# Aire: los usan sólo los personajes con salto (el jugador de prueba). Los ciudadanos
		# nunca piden estos estados, así que para ellos son estados muertos que no molestan.
		"jump": Vector2(640, 100),
		"fall": Vector2(640, 260),
		"land": Vector2(640, 420),
	}
	for state_name: String in states:
		var node := AnimationNodeAnimation.new()
		node.animation = StringName(state_name)
		sm.add_node(state_name, node, states[state_name])
	var links := [
		# origen, destino, tiempo de fundido, sincronizar la fase de la zancada
		["walk", "jog", 0.25, true],
		["jog", "walk", 0.25, true],
		["jog", "idle", 0.30, false],
		["walk", "turn_l", 0.20, true],
		["walk", "turn_r", 0.20, true],
		["jog", "turn_l", 0.20, true],
		["jog", "turn_r", 0.20, true],
		["turn_l", "walk", 0.25, true],
		["turn_r", "walk", 0.25, true],
		# Reacciones sociales: se puede entrar a "react" desde cualquier estado en movimiento
		# o quieto, y se sale de vuelta a idle o a caminar (nunca se queda enganchado).
		["walk", "react", 0.30, true],
		["jog", "react", 0.30, true],
		["react", "idle", 0.35, false],
		["react", "walk", 0.30, true],
		# Salto, caída y aterrizaje: se puede saltar desde quieto o andando, y el aterrizaje
		# siempre sale a idle o a caminar (nunca se queda enganchado en el aire).
		["walk", "jump", 0.10, false],
		["jog", "jump", 0.10, false],
		["jump", "fall", 0.25, false],
		["fall", "land", 0.10, false],
		["land", "idle", 0.25, false],
		["land", "walk", 0.25, true],
	]
	# Cruces de los cuatro huecos de idle: de cualquiera a cualquiera (fundido largo, 0,60 s, para
	# que el cambio de postura no se note como un salto), salida a andar y a saltar desde todos, y
	# entrada a la reacción social desde todos.
	var idle_slots := ["idle", "idle_b", "idle_c", "idle_d"]
	for a: String in idle_slots:
		for b: String in idle_slots:
			if a != b:
				links.append([a, b, 0.60, true])
		links.append([a, "walk", 0.25, true])
		links.append([a, "react", 0.30, true])
		links.append([a, "jump", 0.10, false])
		links.append(["walk", a, 0.30, false])
	for link: Array in links:
		var transition := AnimationNodeStateMachineTransition.new()
		transition.xfade_time = float(link[2])
		if bool(link[3]):
			transition.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_SYNC
		sm.add_transition(String(link[0]), String(link[1]), transition)
	var err := ResourceSaver.save(sm, OUT_TREE)
	_report.append("tree    -> %s (%d estados, err=%d)" % [OUT_TREE, states.size(), err])


func _build_test_navmesh() -> void:
	var nm := NavigationMesh.new()
	var half := 34.0
	nm.vertices = PackedVector3Array([
		Vector3(-half, 0.02, -half),
		Vector3(half, 0.02, -half),
		Vector3(half, 0.02, half),
		Vector3(-half, 0.02, half),
	])
	nm.add_polygon([0, 3, 2, 1])
	var err := ResourceSaver.save(nm, OUT_NAVMESH)
	_report.append("navmesh -> %s (err=%d)" % [OUT_NAVMESH, err])