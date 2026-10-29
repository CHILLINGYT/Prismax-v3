extends RefCounted

## HERRAMIENTA DE DESARROLLO (no se ejecuta durante el juego).
##
## Retargetea las animaciones del pack de enemigos (FBX con rig Mixamo "Y Bot" de
## 65 huesos `mixamorig_*`) al esqueleto riggeado de la SKIN del enemigo y genera
## una AnimationLibrary COMPARTIDA y autocontenida para los dos enemigos nuevos:
##
##   res://Enemigos Prueba/Animations/enemigo_animations.tres
##
## POR QUÉ HAY QUE RETARGETEAR (medido, no supuesto):
##   · Origen (Y Bot.fbx):        cadera a ~1.00 m, hueso de pierna con su propio roll.
##   · Destino (un Tripo Mixamo): cadera a ~0.52 m y reposo de huesos distinto
##     (p. ej. la cadera está girada -90° en Y). Copiar los clips tal cual deja al
##     modelo torsionado y con la mitad de escala en el balanceo.
##   Por eso se transfiere, hueso por hueso:
##     1. la DIRECCIÓN del hueso (columna Y de su base global animada de la fuente), y
##     2. el GIRO (twist) de la fuente alrededor de esa dirección, relativo a su reposo,
##   y las posiciones sólo para la cadera, escaladas por la diferencia de altura entre
##   rigs, con corrección constante de apoyo del pie. Es EXACTAMENTE la técnica ya
##   validada en el proyecto por `NPCAnimationBaker`, que se reutiliza aquí (no se
##   duplica la matemática ni se toca aquel fichero).
##
## DE CADA FBX se usa el clip `mixamo_com`. El otro clip, `Take 001`, es el take
## neutro (verificado: 0.000 rad de desviación respecto del reposo en todos los
## huesos sondeados) y se descarta.
##
## EXCLUIDAS A PROPÓSITO (indicación del usuario):
##   · Walking.fbx        → no se usa como locomoción de estos enemigos.
##   · Y Bot.fbx          → es una pose en T de referencia, no una animación de combate.
##
## DESTINO (RIG DE LA SKIN): mientras la skin definitiva riggeada no esté en el
## proyecto se hornea contra el único rig Mixamo Tripo disponible (el modelo de la
## forma Fuerza), que sirve de PROXY del rig que traerá la skin. La librería depende
## del reposo del destino, así que cuando llegue la skin riggeada hay que volver a
## hornear con su ruta:  BakerAnimacionesEnemigo.bake("res://.../skin.fbx")
##
## Uso (editor o headless):
##   var rep := BakerAnimacionesEnemigo.bake()
##   for l in rep: print(l)

const NPC := preload("res://NPCs/Scripts/Tools/npc_animation_baker.gd")

const DIR_ANIM := "res://cosas para enemigos/aniumacion enemigo/"

## PROXY del rig de la skin definitiva (mismo pipeline Mixamo de 65 huesos que traerá).
const DESTINO := "res://personaje/transformaciones/fuerza/model (1)/tripo_convert_69413d1d-9e71-458a-9b8b-ac8ba6650d4c (1).fbx"

const OUT_LIBRARY := "res://Enemigos Prueba/Animations/enemigo_animations.tres"

## Todas las pistas quedan con este prefijo: se elige para que las escenas de los
## enemigos puedan poner un nodo `Skeleton3D` colgando de la raíz visual y apuntar
## el `root_node` del AnimationPlayer ahí (paths cortos y estables).
const TRACK_PREFIX := "Skeleton3D:"

## El clip real dentro de cada FBX (el otro, "Take 001", es el take neutro).
const CLIP_ORIGEN := "mixamo_com"

## Clip destino -> archivo de origen, si hace bucle y categoría (para diagnóstico).
const JOBS := [
	# --- Cuerpo a cuerpo (enemigo A) ---
	{"clip": "idle_combate",    "file": "idlecombate.fbx",        "loop": true,  "kind": "idle"},
	{"clip": "caminar_combate", "file": "caminarcombate.fbx",     "loop": true,  "kind": "walk"},
	{"clip": "golpe_1",         "file": "golpe1.fbx",             "loop": false, "kind": "attack"},
	{"clip": "golpe_2",         "file": "golpe2.fbx",             "loop": false, "kind": "attack"},
	{"clip": "golpe_3",         "file": "golpe3.fbx",             "loop": false, "kind": "attack"},
	{"clip": "recibir_combate", "file": "recibedañocombate.fbx",  "loop": false, "kind": "hit"},
	# --- Tirador (enemigo B) ---
	{"clip": "idle_arma",       "file": "Idleconarma.fbx",        "loop": true,  "kind": "idle"},
	{"clip": "caminar_arma",    "file": "caminarconarma.fbx",     "loop": true,  "kind": "walk"},
	{"clip": "disparar",        "file": "disparar.fbx",           "loop": false, "kind": "shoot"},
	{"clip": "recibir_arma",    "file": "dañoconarma.fbx",        "loop": false, "kind": "hit"},
	# --- Muertes (comunes; se elige una tras verificar su contenido) ---
	{"clip": "muerte_1",        "file": "muerte1.fbx",            "loop": false, "kind": "death"},
	{"clip": "muerte_2",        "file": "muerte2.fbx",            "loop": false, "kind": "death"},
	{"clip": "muerte_3",        "file": "muerte3.fbx",            "loop": false, "kind": "death"},
	{"clip": "muerte_jugador",  "file": "muerte-de-juagador.fbx", "loop": false, "kind": "death"},
]


static func bake(target_path: String = DESTINO) -> Array[String]:
	var report: Array[String] = []
	var baker: RefCounted = NPC.new()
	var target: Dictionary = baker.call("_load_rig", target_path, "target")
	if target.is_empty():
		report.append("ERROR  no se pudo cargar el rig destino %s" % target_path)
		return report

	# Mapa de huesos: identidad (origen y destino usan los MISMOS nombres mixamorig_*).
	var ident: Dictionary = {}
	for name in target["names"]:
		ident[String(name)] = String(name)

	var library := AnimationLibrary.new()
	for job: Dictionary in JOBS:
		var src_path := DIR_ANIM + String(job["file"])
		if not ResourceLoader.exists(src_path):
			report.append("ERROR  falta el origen %s" % src_path)
			continue
		var src: Dictionary = baker.call("_load_rig", src_path, "src")
		if src.is_empty():
			report.append("ERROR  no se pudo cargar el rig origen %s" % src_path)
			continue
		var anim: Animation = baker.call("_pick_animation", src, CLIP_ORIGEN)
		if anim == null:
			report.append("ERROR  sin clip '%s' en %s" % [CLIP_ORIGEN, job["file"]])
			continue
		var clip: Animation = baker.call("_retarget", target, src, anim, ident,
				bool(job["loop"]), String(job["kind"]))
		if clip == null:
			report.append("ERROR  no se pudo retargetear %s" % job["clip"])
			continue
		_reprefix(clip)
		clip.resource_name = String(job["clip"])
		library.add_animation(String(job["clip"]), clip)
		report.append("clip %-16s %5.2fs  %2d pistas  vel=%.2f m/s  corr_pie=%+.3f  (%s)" % [
			job["clip"], clip.length, clip.get_track_count(),
			clip.get_meta("speed", 0.0), clip.get_meta("foot_fix", 0.0), job["file"]])

	DirAccess.make_dir_recursive_absolute(OUT_LIBRARY.get_base_dir())
	var err := ResourceSaver.save(library, OUT_LIBRARY)
	report.append("library -> %s (%d clips, err=%d)" % [
			OUT_LIBRARY, library.get_animation_list().size(), err])
	return report


## Reescribe el prefijo de pista que deja NPCAnimationBaker ("Model/Skeleton3D:") por
## el prefijo propio del enemigo, conservando el nombre de hueso.
static func _reprefix(clip: Animation) -> void:
	for t in clip.get_track_count():
		var p := String(clip.track_get_path(t))
		var i := p.find("Skeleton3D:")
		if i < 0:
			continue
		var bone := p.substr(i + "Skeleton3D:".length())
		clip.track_set_path(t, NodePath(TRACK_PREFIX + bone))


## Diagnóstico: compara el reposo del rig de las animaciones con el del destino, hueso
## a hueso, para saber cuánto trabajo de retargeting hay (y si hiciera falta copia directa).
static func verificar(target_path: String = DESTINO) -> Array[String]:
	var out: Array[String] = []
	var baker: RefCounted = NPC.new()
	var target: Dictionary = baker.call("_load_rig", target_path, "target")
	var src: Dictionary = baker.call("_load_rig", DIR_ANIM + "golpe1.fbx", "src")
	if target.is_empty() or src.is_empty():
		out.append("ERROR  no se pudieron cargar los rigs")
		return out
	var t_names: PackedStringArray = target["names"]
	var t_rest: Array = target["rest"]
	var s_names: PackedStringArray = src["names"]
	var s_rest: Array = src["rest"]
	var peor := 0.0
	var peor_hueso := ""
	var n := 0
	for i in t_names.size():
		var si := s_names.find(t_names[i])
		if si < 0:
			continue
		var q_s: Quaternion = (s_rest[si] as Transform3D).basis.get_rotation_quaternion()
		var q_t: Quaternion = (t_rest[i] as Transform3D).basis.get_rotation_quaternion()
		var ang := rad_to_deg(q_s.angle_to(q_t))
		n += 1
		if ang > peor:
			peor = ang
			peor_hueso = String(t_names[i])
	out.append("reposo origen vs destino: %d huesos comparados, peor diferencia %.1f° (%s)" % [n, peor, peor_hueso])
	var hips_s := (s_rest[s_names.find("mixamorig_Hips")] as Transform3D).origin.y
	var hips_t := (t_rest[t_names.find("mixamorig_Hips")] as Transform3D).origin.y
	out.append("cadera origen=%.3f m  destino=%.3f m  escala de balanceo=%.3f" % [
			hips_s, hips_t, hips_t / maxf(hips_s, 0.001)])
	return out