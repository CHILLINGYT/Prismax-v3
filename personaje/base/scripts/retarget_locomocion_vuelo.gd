extends SceneTree
## HERRAMIENTA (se corre con --script): retargetea el clip `walk` del personaje de
## COMBATE al esqueleto del personaje de VUELO (maniquí Godot Standard, 53 huesos)
## con la MISMA técnica de reposos que las animaciones de muerte
## (`controlador_leo._retarget_clip` + MAPA_MIXAMO_MANIQUE) y guarda la librería
## en res://personaje/transformaciones/vuelo/animations/vuelo_walk.tres.
##
## ADEMÁS alinea el clip al SUELO del rig de destino: el retargeteado crudo deja
## los pies a -0.168 m (medido EN VIVO con _tests/probe_fases_vuelo_walk.tscn),
## así que se sube la pista de posición de la cadera ese valor para que el punto
## más bajo del pie toque el piso — sale 0.910 m, casi exactamente el reposo de la
## cadera del maniquí (0.9167), que es la comprobación de que la altura es la
## correcta para caminar de pie.

const JUGADOR := "res://personaje/base/escenas/leo_jugador.tscn"
const LIB_COMBATE := "res://personaje/transformaciones/transformacion ataque/animations/player_anim_library.tres"
const MODELO_COMBATE := "res://personaje/transformaciones/transformacion ataque/animations/pose t.fbx"
const SALIDA := "res://personaje/transformaciones/vuelo/animations/vuelo_walk.tres"
const NOMBRE := &"vuelo_walk"
## Corrección vertical medida (m): los pies del clip crudo llegan a -0.168.
const OFFSET_CADERA_M := 0.168

func _init() -> void:
	var ps := load(JUGADOR) as PackedScene
	if ps == null:
		push_error("No carga " + JUGADOR)
		quit(1)
		return
	var jug := ps.instantiate()
	get_root().add_child(jug)
	var vuelo: Node = jug.get_node_or_null("Vuelo")
	var ap := vuelo.get_node_or_null("VisualRoot/AnimationLibrary_Godot_Standard/AnimationPlayer") as AnimationPlayer
	var skel := vuelo.get_node_or_null("VisualRoot/AnimationLibrary_Godot_Standard/Rig/GeneralSkeleton") as Skeleton3D
	var lib_combate := load(LIB_COMBATE) as AnimationLibrary
	if ap == null or skel == null or lib_combate == null:
		push_error("Faltan piezas: ap=%s skel=%s lib=%s" % [str(ap), str(skel), str(lib_combate)])
		quit(1)
		return
	var origen: Animation = lib_combate.get_animation("walk")
	if origen == null:
		push_error("El personaje de Combate no tiene clip 'walk'")
		quit(1)
		return
	var mapa: Dictionary = (jug.get_script() as GDScript).get_script_constant_map().get("MAPA_MIXAMO_MANIQUE", {})
	print("[locomocion] retargeteando 'walk' (%.3f s, %d pistas) con %d huesos mapeados" % [origen.length, origen.get_track_count(), mapa.size()])
	var ok: bool = bool(jug.call("_retarget_clip", origen, ap, skel, NOMBRE, true, MODELO_COMBATE, mapa))
	print("[locomocion] retarget=", ok)
	if not ok:
		push_error("El retargeting no casó ningún hueso")
		quit(1)
		return
	var clip: Animation = ap.get_animation(NOMBRE)
	print("[locomocion] clip generado: %.3f s, %d pistas, loop=%d" % [clip.length, clip.get_track_count(), clip.loop_mode])
	# --- Alineación al suelo: subir la pista de posición de la cadera ---------
	for p in clip.get_track_count():
		if clip.track_get_type(p) != Animation.TYPE_POSITION_3D:
			continue
		if not String(clip.track_get_path(p)).contains("Hips"):
			continue
		var antes := Vector3.ZERO
		for k in clip.track_get_key_count(p):
			var v := clip.track_get_key_value(p, k) as Vector3
			if k == 0:
				antes = v
			clip.track_set_key_value(p, k, v + Vector3(0.0, OFFSET_CADERA_M, 0.0))
		print("[locomocion] pista '%s' subida %.3f m (y %.4f -> %.4f)" % [
				String(clip.track_get_path(p)), OFFSET_CADERA_M, antes.y, antes.y + OFFSET_CADERA_M])
	# -------------------------------------------------------------------------
	var lib := AnimationLibrary.new()
	lib.add_animation(NOMBRE, clip)
	DirAccess.make_dir_recursive_absolute("res://personaje/transformaciones/vuelo/animations")
	var err := ResourceSaver.save(lib, SALIDA)
	print("[locomocion] guardado: %s (%s)" % [error_string(err), SALIDA])
	var recargada := load(SALIDA) as AnimationLibrary
	if recargada == null or not recargada.has_animation(NOMBRE):
		push_error("La librería guardada no se recarga")
		quit(1)
		return
	var fin: Animation = recargada.get_animation(NOMBRE)
	for p in fin.get_track_count():
		if fin.track_get_type(p) == Animation.TYPE_POSITION_3D:
			var mn := INF
			var mx := -INF
			for k in fin.track_get_key_count(p):
				var v := fin.track_get_key_value(p, k) as Vector3
				mn = minf(mn, v.y)
				mx = maxf(mx, v.y)
			print("[locomocion] VERIFICACIÓN pista de posición '%s': y de %.4f a %.4f" % [String(fin.track_get_path(p)), mn, mx])
	print("[locomocion] OK: clips=%s (%.3f s, %d pistas)" % [str(recargada.get_animation_list()), fin.length, fin.get_track_count()])
	jug.free()
	quit()