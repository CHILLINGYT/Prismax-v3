extends RefCounted

## HERRAMIENTA DE DESARROLLO (no se ejecuta durante el juego).
##
## RELIGA una AnimationLibrary ya horneada al esqueleto de un modelo CONCRETO.
##
## POR QUÉ HACE FALTA (medido, no supuesto): las pistas de una librería son rutas
## `Skeleton3D:<hueso>` y por tanto dependen del NOMBRE de los huesos del modelo.
## Godot nombra los huesos de un FBX con el prefijo de su armadura
## (`fbx/naming_version=2`): con la armadura llamada `mixamorig` salen los
## nombres estándar `mixamorig_Hips`, pero con la armadura llamada `mixamorig8`
## salen `mixamorig8_Hips`. Mismo rig, mismo número de huesos, MISMO orden: si la
## librería busca `mixamorig_Hips` y el modelo tiene `mixamorig8_Hips`, el
## AnimationPlayer no encuentra ninguna pista y el modelo se queda en su pose de
## reposo (la "T"). Esta herramienta reescribe esas rutas para que apunten a los
## huesos reales del modelo SIN tocar los clips: mismos fotogramas y duración.
##
## POR QUÉ NO se renombran los huesos del MODELO en vez de las pistas: los `Skin`
## de la malla resuelven sus binds POR NOMBRE, así que renombrar el esqueleto los
## deja en -1 (medido) y la malla deja de deformarse. Las pistas, en cambio, se
## pueden reescribir sin riesgo.
##
## El emparejamiento es conservador: se compara el nombre del hueso quitando el
## prefijo `mixamorig<N>_` (así `mixamorig_HeadTop_End` casa con
## `mixamorig8_HeadTop_End` y no con otro hueso). Si un hueso no casa, se avisa y
## esa pista se deja igual: nunca se inventa un destino.
##
## Uso (editor o headless):
##   const Religar := preload("res://Enemigos Prueba/Scripts/Tools/religar_animaciones_a_modelo.gd")
##   for l in Religar.religar_todos(): print(l)
##   # o uno concreto:
##   Religar.religar("res://.../modelo.fbx", "res://.../libreria.tres")

const MODELO_COMBATE := "res://cosas para enemigos/enemigos/enemigocombate.fbx"
const MODELO_ARMA := "res://cosas para enemigos/enemigos/enemigoconarma.fbx"
const LIB_COMBATE := "res://Enemigos Prueba/Animations/enemigo_animaciones_mixamo.tres"
const LIB_ARMA := "res://Enemigos Prueba/Animations/enemigo_animaciones_mixamo_arma.tres"


static func religar_todos() -> Array[String]:
	var out: Array[String] = []
	out.append_array(religar(MODELO_COMBATE, LIB_COMBATE))
	out.append_array(religar(MODELO_ARMA, LIB_ARMA))
	return out


## Reescribe las rutas de TODAS las pistas de `lib_path` para que apunten a los
## huesos del modelo `modelo_path`. Devuelve un informe legible. Si no hace falta
## cambiar nada, NO vuelve a escribir el fichero.
static func religar(modelo_path: String, lib_path: String) -> Array[String]:
	var report: Array[String] = []
	report.append("=== religando %s -> %s ===" % [lib_path.get_file(), modelo_path.get_file()])
	var huesos: Array = _huesos_de(modelo_path)
	if huesos.is_empty():
		report.append("ERROR  no se pudo leer el esqueleto de %s" % modelo_path)
		return report
	var lib: AnimationLibrary = load(lib_path)
	if lib == null:
		report.append("ERROR  no se pudo cargar la librería %s" % lib_path)
		return report
	# sufijo -> nombre real. Los nombres repetidos se descartan: preferimos avisar.
	var por_sufijo: Dictionary = {}
	var ambiguos: Dictionary = {}
	for h: String in huesos:
		var s := _sufijo(h)
		if por_sufijo.has(s):
			ambiguos[s] = true
		por_sufijo[s] = h
	for s: String in ambiguos.keys():
		por_sufijo.erase(s)
	var cambios := 0
	var iguales := 0
	var perdidos: Array[String] = []
	for nombre in lib.get_animation_list():
		var clip: Animation = lib.get_animation(nombre)
		var en_clip := 0
		for t in clip.get_track_count():
			var ruta := String(clip.track_get_path(t))
			var i := ruta.find(":")
			if i < 0:
				continue
			var hueso := ruta.substr(i + 1)
			if huesos.has(hueso):
				iguales += 1
				continue
			var destino: String = String(por_sufijo.get(_sufijo(hueso), ""))
			if destino == "":
				if not perdidos.has(hueso):
					perdidos.append(hueso)
				continue
			clip.track_set_path(t, NodePath(ruta.substr(0, i + 1) + destino))
			cambios += 1
			en_clip += 1
		if en_clip > 0:
			report.append("  %-16s %d pistas religadas" % [nombre, en_clip])
	for h: String in perdidos:
		report.append("  AVISO  el hueso '%s' no existe en el modelo: pista sin religar" % h)
	report.append("  pistas ya correctas: %d   religadas: %d   sin destino: %d" % [
			iguales, cambios, perdidos.size()])
	if cambios == 0:
		report.append("  nada que cambiar: NO se reescribe el fichero")
		return report
	var err := ResourceSaver.save(lib, lib_path)
	report.append("  guardada %s (err=%d, %d clips)" % [lib_path, err, lib.get_animation_list().size()])
	return report


## Nombres de hueso del primer Skeleton3D del modelo.
static func _huesos_de(modelo_path: String) -> Array:
	var ps: PackedScene = load(modelo_path)
	if ps == null:
		return []
	var raiz: Node = ps.instantiate()
	var sk: Skeleton3D = null
	for n in _todos(raiz):
		if n is Skeleton3D:
			sk = n
			break
	var out: Array = []
	if sk != null:
		for i in sk.get_bone_count():
			out.append(String(sk.get_bone_name(i)))
	raiz.free()
	return out


## Nombre de hueso sin el prefijo de la armadura Mixamo:
## `mixamorig_Hips` y `mixamorig8_HeadTop_End` -> `Hips` y `HeadTop_End`.
## Cualquier otro nombre se devuelve tal cual (así un rig distinto exige
## coincidencia exacta y nunca se empareja por error).
static func _sufijo(nombre: String) -> String:
	if not nombre.begins_with("mixamorig"):
		return nombre
	var i := nombre.find("_")
	return nombre if i < 0 else nombre.substr(i + 1)


static func _todos(n: Node) -> Array:
	var out: Array = [n]
	for c in n.get_children():
		out.append_array(_todos(c))
	return out