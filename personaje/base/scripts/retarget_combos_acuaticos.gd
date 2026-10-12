extends SceneTree
## =============================================================================
##  Retargeting REAL de los 4 golpes (jab, dos, cros, gancho) del personaje de
##  Combate al esqueleto del personaje acuático.
## =============================================================================
##  Por qué la versión anterior deformaba y hundía al personaje:
##
##  * Los dos esqueletos usan nombres `mixamorig_*`, pero NO comparten las
##    rotaciones de reposo por hueso: el Hips acuático está girado -90° Y, los
##    hombros ~183°, el torso lleva un "roll" de ~90°, etc. (medido sobre los
##    rest reales). Copiar los valores crudos retuerce todas las articulaciones
##    porque cada pista rota el hueso en ejes que no le corresponden.
##  * La pista de posición del Hips venía en las unidades locales del modelo de
##    Combate (1 unidad ≈ 1/184 m; el modelo mide ~1.84 m). Aplicada tal cual
##    sobre el espacio del modelo acuático (1 unidad ≈ 1/1.79 m) la pelvis caía
##    de ~0.578 a ~0.005: el personaje se hundía hasta el suelo.
##
##  Método correcto (cambio de base con las poses de reposo reales):
##      local_destino(t) = A · local_origen(t) · B
##      A = ReposoDestino(padre)⁻¹ · ReposoOrigen(padre)
##      B = ReposoOrigen(hueso)⁻¹ · ReposoDestino(hueso)
##  Con esto reposo→reposo es EXACTO (local_destino = reposo_destino) y cada
##  movimiento se expresa en los ejes propios del rig acuático. No se toca ni el
##  esqueleto ni el modelo acuático: sólo se adaptan las animaciones.
##
##  La posición del hueso raíz se convierte entre espacios de modelo con la razón
##  real de escalas de las cadenas de nodos (el modelo de Combate se instancia a
##  184.5 en leo_jugador.tscn; el modelo acuático trae 1.792225 dentro de su
##  propia escena) y se conserva SÓLO el desplazamiento respecto al reposo.
## =============================================================================

const COMBAT_LIBRARY_PATH: String = "res://personaje/transformaciones/transformacion ataque/animations/player_anim_library.tres"
const COMBAT_MODEL_PATH: String = "res://personaje/transformaciones/transformacion ataque/animations/pose t.fbx"
const AQUATIC_MODEL_PATH: String = "res://personaje/transformaciones/acuatica/models/futuristic_armor_character.tscn"
const OUTPUT_PATH: String = "res://personaje/base/animations/combos_acuaticos.tres"
const BACKUP_PATH: String = "user://backup_combos_acuaticos_previo.tres"
const TARGET_PATH_PREFIX: String = "Visual/CharacterModel/Skeleton3D:"

const CLIPS: Array[String] = ["jab", "dos", "cros", "gancho"]
const FPS: float = 30.0
const ROOT_BONE: String = "mixamorig_Hips"

## Escala de la cadena Combate→mundo en el juego: res://personaje/base/escenas/
## leo_jugador.tscn instancia `pose t.fbx` con escala 184.5 (el interior del
## modelo está a escala 1). Si esa instancia cambiara, hay que actualizar esto.
const COMBAT_CHAIN_SCALE: float = 184.5


func _init() -> void:
	var combate_lib: AnimationLibrary = load(COMBAT_LIBRARY_PATH) as AnimationLibrary
	var combate_raiz: Node3D = (load(COMBAT_MODEL_PATH) as PackedScene).instantiate() as Node3D
	var acuatico_raiz: Node3D = (load(AQUATIC_MODEL_PATH) as PackedScene).instantiate() as Node3D
	if combate_lib == null or combate_raiz == null or acuatico_raiz == null:
		push_error("No se pudieron cargar las dependencias del retargeting")
		quit(1)
		return
	var sk_origen: Skeleton3D = _buscar_esqueleto(combate_raiz)
	var sk_destino: Skeleton3D = _buscar_esqueleto(acuatico_raiz)

	# Escalas reales de cada espacio de modelo (modelo→mundo).
	var escala_destino: float = acuatico_raiz.transform.basis.get_scale().x
	var k_pos: float = COMBAT_CHAIN_SCALE / escala_destino
	print("[retarget] escala combate=%.4f  acuatico=%.4f  k_pos=%.4f" % [COMBAT_CHAIN_SCALE, escala_destino, k_pos])

	# Poses de reposo (sólo rotación) en espacio de modelo, por nombre de hueso.
	var reposo_origen: Dictionary = _reposos_mundo(sk_origen)
	var reposo_destino: Dictionary = _reposos_mundo(sk_destino)

	# Respaldo del archivo anterior.
	if FileAccess.file_exists(OUTPUT_PATH):
		var prev := FileAccess.get_file_as_bytes(OUTPUT_PATH)
		var f := FileAccess.open(BACKUP_PATH, FileAccess.WRITE)
		if f != null:
			f.store_buffer(prev)
			f.close()
			print("[retarget] respaldo del recurso anterior: %s (%d bytes)" % [BACKUP_PATH, prev.size()])

	# Variante ADOPTADA: con las direcciones de reposo alineadas a las del origen.
	# Así la dirección de CADA hueso del acuático coincide con la del original en
	# todo instante (desvío medido 0.00°), eliminando la diferencia constante de
	# postura entre ambos reposos (hasta 18° en cuello/cabeza/manos, 10-12° en
	# piernas) sin tocar el esqueleto del acuático.
	var reposo_alineado: Dictionary = _reposos_alineados(reposo_origen, reposo_destino)
	var salida: AnimationLibrary = _construir_libreria(combate_lib, sk_origen, sk_destino, reposo_origen, reposo_alineado, k_pos, escala_destino, "alineada")

	combate_raiz.free()
	acuatico_raiz.free()

	var err: Error = ResourceSaver.save(salida, OUTPUT_PATH)
	if err != OK:
		push_error("No se pudo guardar %s: %s" % [OUTPUT_PATH, error_string(err)])
		quit(1)
		return

	# Verificación inmediata: recargar el archivo recién guardado.
	var guardada: AnimationLibrary = load(OUTPUT_PATH) as AnimationLibrary
	if guardada == null or guardada.get_animation_list().size() != CLIPS.size():
		push_error("La librería guardada no se puede recargar correctamente")
		quit(1)
		return
	print("[retarget] OK: %s -> %s" % [str(guardada.get_animation_list()), OUTPUT_PATH])
	quit()


## Reposo del destino con las DIRECCIONES de hueso alineadas a las del origen
## (rotación de arco mínimo dir_destino→dir_origen aplicada a cada reposo).
func _reposos_alineados(reposo_origen: Dictionary, reposo_destino: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for nombre: String in reposo_destino:
		var q_d: Quaternion = reposo_destino[nombre]
		var q_o: Quaternion = reposo_origen.get(nombre, q_d)
		var u: Vector3 = (q_d * Vector3.UP).normalized()
		var v: Vector3 = (q_o * Vector3.UP).normalized()
		out[nombre] = Quaternion(u, v) * q_d
	return out


## Construye la librería completa con un reposo de destino dado.
func _construir_libreria(combate_lib: AnimationLibrary, sk_origen: Skeleton3D, sk_destino: Skeleton3D,
		reposo_origen: Dictionary, reposo_destino: Dictionary, k_pos: float,
		escala_destino: float, etiqueta: String) -> AnimationLibrary:
	var salida: AnimationLibrary = AnimationLibrary.new()
	for clip: String in CLIPS:
		var origen: Animation = combate_lib.get_animation(clip)
		if origen == null:
			push_error("Falta el clip de origen: %s" % clip)
			continue
		var adaptada: Animation = _retarget_clip(origen, sk_origen, sk_destino, reposo_origen, reposo_destino, k_pos, escala_destino)
		salida.add_animation(clip, adaptada)
		print("[retarget %s] %s: %d pistas, duración %.3f s (origen %.3f s)" % [
				etiqueta, clip, adaptada.get_track_count(), adaptada.length, origen.length])
	return salida


## Devuelve una copia adaptada del clip. Escribe una pista de rotación por cada
## hueso animado en el origen (mismo nombre en destino) y la pista de posición
## del hueso raíz convertida al espacio del modelo acuático.
func _retarget_clip(origen: Animation, sk_origen: Skeleton3D, sk_destino: Skeleton3D,
		reposo_origen: Dictionary, reposo_destino: Dictionary, k_pos: float,
		escala_destino: float) -> Animation:
	var n_pasos: int = int(round(origen.length * FPS))
	var tiempos: Array[float] = []
	for i: int in n_pasos + 1:
		tiempos.append(minf(float(i) / FPS, origen.length))

	var adaptada: Animation = Animation.new()
	adaptada.length = origen.length

	# --- pista de posición del hueso raíz (si el origen la trae) ---
	var pista_pos_origen: int = _pista_de(origen, ROOT_BONE, Animation.TYPE_POSITION_3D)
	if pista_pos_origen >= 0:
		var idx_raiz_d: int = sk_destino.find_bone(ROOT_BONE)
		var reposo_pos_d: Vector3 = sk_destino.get_bone_rest(idx_raiz_d).origin
		var reposo_pos_o: Vector3 = sk_origen.get_bone_rest(sk_origen.find_bone(ROOT_BONE)).origin
		var p_pos: int = adaptada.add_track(Animation.TYPE_POSITION_3D)
		adaptada.track_set_path(p_pos, NodePath(TARGET_PATH_PREFIX + ROOT_BONE))
		adaptada.track_set_interpolation_type(p_pos, Animation.INTERPOLATION_LINEAR)
		var min_y: float = INF
		var max_y: float = -INF
		for t: float in tiempos:
			var v: Vector3 = origen.position_track_interpolate(pista_pos_origen, t, false)
			var destino_v: Vector3 = reposo_pos_d + (v - reposo_pos_o) * k_pos
			min_y = minf(min_y, destino_v.y)
			max_y = maxf(max_y, destino_v.y)
			adaptada.track_insert_key(p_pos, t, destino_v)
		print("    posición raíz: y destino de %.4f a %.4f (equivale a %.3f–%.3f m en mundo)" % [
				min_y, max_y, min_y * escala_destino, max_y * escala_destino])

	# --- rotaciones ---
	var escritas: int = 0
	var ignoradas: Array[String] = []
	for p: int in origen.get_track_count():
		if origen.track_get_type(p) != Animation.TYPE_ROTATION_3D:
			continue
		var ruta: String = String(origen.track_get_path(p))
		var partes: PackedStringArray = ruta.split(":")
		if partes.size() < 2:
			continue
		var hueso: String = partes[1]
		var idx_o: int = sk_origen.find_bone(hueso)
		var idx_d: int = sk_destino.find_bone(hueso)
		if idx_o < 0:
			continue
		if idx_d < 0:
			ignoradas.append(hueso)
			continue
		# A = ReposoDestino(padre)⁻¹ · ReposoOrigen(padre)
		# B = ReposoOrigen(hueso)⁻¹ · ReposoDestino(hueso)
		var a: Quaternion = Quaternion.IDENTITY
		var par_o: int = sk_origen.get_bone_parent(idx_o)
		if par_o >= 0:
			var nombre_padre_o: String = sk_origen.get_bone_name(par_o)
			var q_padre_d: Quaternion = reposo_destino.get(nombre_padre_o, Quaternion.IDENTITY)
			var q_padre_o: Quaternion = reposo_origen.get(nombre_padre_o, Quaternion.IDENTITY)
			a = q_padre_d.inverse() * q_padre_o
		var b: Quaternion = (reposo_origen.get(hueso, Quaternion.IDENTITY) as Quaternion).inverse() \
				* (reposo_destino.get(hueso, Quaternion.IDENTITY) as Quaternion)
		var pista_r: int = adaptada.add_track(Animation.TYPE_ROTATION_3D)
		adaptada.track_set_path(pista_r, NodePath(TARGET_PATH_PREFIX + hueso))
		adaptada.track_set_interpolation_type(pista_r, Animation.INTERPOLATION_LINEAR)
		for t: float in tiempos:
			var local_origen: Quaternion = origen.rotation_track_interpolate(p, t, false)
			adaptada.track_insert_key(pista_r, t, a * local_origen * b)
		escritas += 1
	if not ignoradas.is_empty():
		print("    aviso: huesos del origen sin equivalente en destino: %s" % ", ".join(ignoradas))
	return adaptada


## Índice de la primera pista del clip sobre el hueso y tipo pedidos (-1 si no hay).
func _pista_de(anim: Animation, hueso: String, tipo: Animation.TrackType) -> int:
	for p: int in anim.get_track_count():
		if anim.track_get_type(p) != tipo:
			continue
		if hueso in String(anim.track_get_path(p)):
			return p
	return -1


## Rotación de reposo (en espacio de modelo/esqueleto) de cada hueso, por nombre.
func _reposos_mundo(sk: Skeleton3D) -> Dictionary:
	var mundos: Array[Quaternion] = []
	for i: int in sk.get_bone_count():
		var q: Quaternion = sk.get_bone_rest(i).basis.get_rotation_quaternion()
		var par: int = sk.get_bone_parent(i)
		if par >= 0:
			q = mundos[par] * q
		mundos.append(q)
	var salida: Dictionary = {}
	for i: int in sk.get_bone_count():
		salida[sk.get_bone_name(i)] = mundos[i]
	return salida


func _buscar_esqueleto(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c: Node in n.get_children():
		var r: Skeleton3D = _buscar_esqueleto(c)
		if r != null:
			return r
	return null