extends RefCounted

## HERRAMIENTA DE DESARROLLO (no se ejecuta durante el juego).
##
## HORNEADO NATIVO: copia los clips Mixamo (`mixamo_com`) del pack de animaciones
## a una AnimationLibrary lista para un modelo CONCRETO del proyecto, SIN
## retargeting.
##
## POR QUÉ NO HACE FALTA RETARGETEAR AQUÍ (medido, no supuesto):
##   · Los FBX de `aniumacion enemigo/` son rigs Mixamo de 65 huesos `mixamorig_*`.
##   · Los modelos `enemigocombate.fbx` y `enemigoconarma.fbx` tienen EXACTAMENTE
##     los mismos 65 nombres de hueso, `Skeleton3D` y pesos de skin (`skin=true`).
##   Comprobado con `verificar_skin_enemigo.gd`: 65/65 huesos idénticos.
##   Copiar las rotaciones tal cual es correcto; retargetearlas contra OTRO rig
##   (el proxy de Fuerza, con reposo distinto) las deformaría.
##
## LO ÚNICO QUE SE ADAPTA: la PISTA DE POSICIÓN de la cadera se escala por
## `cadera_destino / cadera_origen`, porque los personajes Mixamo no miden igual
## (origen ≈0.998 m; `enemigocombate` ≈0.938 m; `enemigoconarma` ≈1.009 m). Sin
## esa corrección la pelvis quedaría unos centímetros alta o baja y los pies no
## apoyarían bien.
##
## DE CADA FBX se usa el clip `mixamo_com`; `Take 001` es el take neutro y se
## descarta. Se EXCLUYEN `Walking.fbx` y `Y Bot.fbx` (pose en T de referencia).
##
## Uso (editor o headless):
##   for l in BakerAnimacionesNativo.bake_todos(): print(l)
##   # o uno concreto:  BakerAnimacionesNativo.bake("res://.../modelo.fbx", "res://.../lib.tres")

const DIR_ANIM := "res://cosas para enemigos/aniumacion enemigo/"
const CLIP_ORIGEN := "mixamo_com"
## Todas las pistas quedan con este prefijo: la escena cuelga un nodo `Skeleton3D`
## de la raíz visual y apunta ahí el `root_node` del AnimationPlayer.
const TRACK_PREFIX := "Skeleton3D:"
const HUESO_CADERA := "mixamorig_Hips"

const MODELO_COMBATE := "res://cosas para enemigos/enemigos/enemigocombate.fbx"
const MODELO_ARMA := "res://cosas para enemigos/enemigos/enemigoconarma.fbx"
const OUT_COMBATE := "res://Enemigos Prueba/Animations/enemigo_animaciones_mixamo.tres"
const OUT_ARMA := "res://Enemigos Prueba/Animations/enemigo_animaciones_mixamo_arma.tres"

## Clip destino -> archivo de origen, si hace bucle y categoría (misma tabla que
## el baker con retargeting, para que los nombres no cambien entre librerías).
const JOBS := [
	# --- Cuerpo a cuerpo ---
	{"clip": "idle_combate",    "file": "idlecombate.fbx",        "loop": true,  "kind": "idle"},
	{"clip": "caminar_combate", "file": "caminarcombate.fbx",     "loop": true,  "kind": "walk"},
	{"clip": "golpe_1",         "file": "golpe1.fbx",             "loop": false, "kind": "attack"},
	{"clip": "golpe_2",         "file": "golpe2.fbx",             "loop": false, "kind": "attack"},
	{"clip": "golpe_3",         "file": "golpe3.fbx",             "loop": false, "kind": "attack"},
	{"clip": "recibir_combate", "file": "recibedañocombate.fbx",  "loop": false, "kind": "hit"},
	# --- Tirador (con arma) ---
	{"clip": "idle_arma",       "file": "Idleconarma.fbx",        "loop": true,  "kind": "idle"},
	{"clip": "caminar_arma",    "file": "caminarconarma.fbx",     "loop": true,  "kind": "walk"},
	{"clip": "disparar",        "file": "disparar.fbx",           "loop": false, "kind": "shoot"},
	{"clip": "recibir_arma",    "file": "dañoconarma.fbx",        "loop": false, "kind": "hit"},
	# --- Muertes ---
	{"clip": "muerte_1",        "file": "muerte1.fbx",            "loop": false, "kind": "death"},
	{"clip": "muerte_2",        "file": "muerte2.fbx",            "loop": false, "kind": "death"},
	{"clip": "muerte_3",        "file": "muerte3.fbx",            "loop": false, "kind": "death"},
	{"clip": "muerte_jugador",  "file": "muerte-de-juagador.fbx", "loop": false, "kind": "death"},
]


static func bake_todos() -> Array[String]:
	var out: Array[String] = []
	out.append_array(bake(MODELO_COMBATE, OUT_COMBATE))
	out.append_array(bake(MODELO_ARMA, OUT_ARMA))
	return out


static func bake(target_path: String, out_path: String) -> Array[String]:
	var report: Array[String] = []
	var target: Dictionary = _rig(target_path)
	if target.is_empty():
		report.append("ERROR  no se pudo cargar el modelo destino %s" % target_path)
		return report
	var cadera_destino: float = float(target["cadera"])
	report.append("modelo %s  huesos=%d  cadera=%.3f m" % [
			target_path.get_file(), (target["nombres"] as Array).size(), cadera_destino])

	var library := AnimationLibrary.new()
	for job: Dictionary in JOBS:
		var src_path := DIR_ANIM + String(job["file"])
		if not ResourceLoader.exists(src_path):
			report.append("ERROR  falta el origen %s" % src_path)
			continue
		var src: Dictionary = _rig(src_path)
		if src.is_empty():
			report.append("ERROR  no se pudo cargar %s" % job["file"])
			continue
		var anim: Animation = _clip(src, CLIP_ORIGEN)
		if anim == null:
			report.append("ERROR  sin clip '%s' en %s" % [CLIP_ORIGEN, job["file"]])
			continue
		# Los huesos deben coincidir EXACTAMENTE; si no, esto no es una copia directa.
		if not _mismos_huesos(src["nombres"], target["nombres"]):
			report.append("ERROR  el rig de %s NO coincide con el modelo: haría falta retargeting" % job["file"])
			continue
		var clip: Animation = anim.duplicate(true) as Animation
		_reescribir_pistas(clip)
		var factor: float = cadera_destino / maxf(float(src["cadera"]), 0.001)
		_escalar_cadera(clip, factor)
		clip.loop_mode = Animation.LOOP_LINEAR if bool(job["loop"]) else Animation.LOOP_NONE
		clip.resource_name = String(job["clip"])
		library.add_animation(String(job["clip"]), clip)
		report.append("clip %-16s %5.2fs  %2d pistas  escala_cadera=%.3f  (%s)" % [
				job["clip"], clip.length, clip.get_track_count(), factor, job["file"]])

	# Guarda: si el rig del modelo no coincidió con ningún clip (p. ej. porque sus
	# huesos llevan otro prefijo de armadura), NO se escribe nada. Antes se guardaba
	# una librería VACÍA encima de la que funcionaba.
	if library.get_animation_list().is_empty():
		report.append("ABORTADO  no se horneó ningún clip: no se toca %s" % out_path)
		report.append("   Si el modelo renombró sus huesos, religá la librería existente con")
		report.append("   Scripts/Tools/religar_animaciones_a_modelo.gd en vez de re-hornear.")
		return report
	DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
	var err := ResourceSaver.save(library, out_path)
	report.append("library -> %s (%d clips, err=%d)" % [
			out_path, library.get_animation_list().size(), err])
	return report


## Deja todas las pistas con el prefijo propio, conservando el nombre del hueso.
static func _reescribir_pistas(clip: Animation) -> void:
	for t in clip.get_track_count():
		var ruta := String(clip.track_get_path(t))
		var i := ruta.find("Skeleton3D:")
		if i < 0:
			continue
		clip.track_set_path(t, NodePath(TRACK_PREFIX + ruta.substr(i + "Skeleton3D:".length())))


## Escala la pista de POSICIÓN de la cadera (y sólo esa) por el factor de tamaño.
static func _escalar_cadera(clip: Animation, factor: float) -> void:
	if is_equal_approx(factor, 1.0):
		return
	for t in clip.get_track_count():
		if clip.track_get_type(t) != Animation.TYPE_POSITION_3D:
			continue
		if not String(clip.track_get_path(t)).ends_with(HUESO_CADERA):
			continue
		for k in clip.track_get_key_count(t):
			var v: Vector3 = clip.track_get_key_value(t, k)
			clip.track_set_key_value(t, k, v * factor)


static func _mismos_huesos(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for n in a:
		if not b.has(n):
			return false
	return true


## Carga un FBX y devuelve nombres de hueso, altura de cadera en reposo y los
## clips YA DUPLICADOS (hay que copiarlos antes de liberar el nodo del FBX).
static func _rig(ruta: String) -> Dictionary:
	var ps: PackedScene = load(ruta)
	if ps == null:
		return {}
	var raiz: Node = ps.instantiate()
	var sk: Skeleton3D = null
	var ap: AnimationPlayer = null
	for n in _todos(raiz):
		if n is Skeleton3D and sk == null:
			sk = n
		elif n is AnimationPlayer and ap == null:
			ap = n
	if sk == null:
		raiz.free()
		return {}
	var nombres: Array = []
	for i in sk.get_bone_count():
		nombres.append(sk.get_bone_name(i))
	var idx := sk.find_bone(HUESO_CADERA)
	var cadera := 0.0
	if idx >= 0:
		cadera = sk.get_bone_rest(idx).origin.y
	var clips: Dictionary = {}
	if ap != null:
		for lib_name in ap.get_animation_library_list():
			var lib: AnimationLibrary = ap.get_animation_library(lib_name)
			for a_name in lib.get_animation_list():
				clips[String(a_name)] = (lib.get_animation(a_name) as Animation).duplicate(true)
	raiz.free()
	return {"nombres": nombres, "cadera": cadera, "clips": clips}


static func _clip(rig: Dictionary, nombre: String) -> Animation:
	var clips: Dictionary = rig.get("clips", {})
	return clips.get(nombre, null) as Animation


static func _todos(n: Node) -> Array:
	var out: Array = [n]
	for c in n.get_children():
		out.append_array(_todos(c))
	return out