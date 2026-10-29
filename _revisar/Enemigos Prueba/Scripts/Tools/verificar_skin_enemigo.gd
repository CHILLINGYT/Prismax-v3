extends SceneTree

## Comprueba si un FBX humanoide sirve como SKIN de los enemigos con esqueleto:
## esqueleto, pesos de deformación (skin) y compatibilidad de nombres de huesos
## con los clips Mixamo ya horneados.
##
## Uso (no abre ventana):
##   godot --headless --path . -s "res://Enemigos Prueba/Scripts/Tools/verificar_skin_enemigo.gd" -- "<ruta fbx>"
## (sin argumento comprueba el FBX táctico por defecto)
##
## Salida: un veredicto. "SIRVE tal cual" = tiene esqueleto y pesos, así que se
## puede hornear la librería y usarlo como nodo Visual de los enemigos.

const RUTA_POR_DEFECTO := "res://cosas para enemigos/Enemigo con esqueleto/tripo_convert_b9778dc3-3ee3-481b-92e7-9ed61b3c8285.fbx"

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var ruta := RUTA_POR_DEFECTO
	if args.size() > 0 and String(args[0]) != "":
		ruta = String(args[0])
	print("=== Verificando skin de enemigo: ", ruta, " ===")
	var ps: PackedScene = load(ruta)
	if ps == null:
		print("  [X] No se pudo cargar (¿ruta mal escrita o aún sin importar?)")
		quit(1)
		return
	var raiz: Node = ps.instantiate()
	var esqueletos := _buscar(raiz, "Skeleton3D")
	var mallas := _buscar(raiz, "MeshInstance3D")
	var anims := _buscar(raiz, "AnimationPlayer")
	print("  nodos: Skeleton3D=", esqueletos.size(), "  MeshInstance3D=", mallas.size(),
			"  AnimationPlayer=", anims.size())

	var tiene_rig := false
	for s: Node in esqueletos:
		var sk := s as Skeleton3D
		tiene_rig = sk.get_bone_count() > 0
		print("  [OK] Skeleton3D '", sk.name, "' con ", sk.get_bone_count(), " huesos")
		var mixamo := 0
		for i in sk.get_bone_count():
			if String(sk.get_bone_name(i)).begins_with("mixamorig"):
				mixamo += 1
		if mixamo >= sk.get_bone_count() - 1:
			print("     huesos mixamorig_* = ", mixamo, "/", sk.get_bone_count(),
					" -> COMPATIBLE con los clips existentes (NO hace falta retarget)")
		else:
			print("     huesos mixamorig_* = ", mixamo, "/", sk.get_bone_count(),
					" -> requeriría RETARGETING")
		var hips := sk.find_bone("mixamorig_Hips")
		if hips >= 0:
			print("     cadera en reposo: y = ", sk.get_bone_rest(hips).origin.y)
	if not tiene_rig:
		print("  [X] SIN esqueleto: la malla no se puede animar (Caso C)")

	var superficies_con_pesos := 0
	for m: Node in mallas:
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		for sup in mi.mesh.get_surface_count():
			var formato: int = mi.mesh.surface_get_format(sup)
			if (formato & Mesh.ARRAY_FORMAT_BONES) != 0 and (formato & Mesh.ARRAY_FORMAT_WEIGHTS) != 0:
				superficies_con_pesos += 1
		print("  malla '", mi.name, "': superficies=", mi.mesh.get_surface_count(),
				"  AABB=", mi.mesh.get_aabb().size, "  skin=", mi.skin != null)
	print("  superficies CON pesos de deformación = ", superficies_con_pesos)

	var clips: Array = []
	for a: Node in anims:
		clips.append_array((a as AnimationPlayer).get_animation_list())
	print("  clips incluidos en el FBX = ", clips)

	var sirve := tiene_rig and superficies_con_pesos > 0
	print("=== VEREDICTO: ", ("SIRVE tal cual" if sirve else "NO sirve todavía como skin animable"), " ===")
	if not sirve:
		print("   Falta un FBX con armature + pesos de skin (ideal: rig Mixamo de 65 huesos).")
	raiz.free()
	quit(0 if sirve else 1)

func _buscar(n: Node, clase: String) -> Array:
	var out: Array = []
	if n.is_class(clase):
		out.append(n)
	for c in n.get_children():
		out.append_array(_buscar(c, clase))
	return out