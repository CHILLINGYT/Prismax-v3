extends Node
## =============================================================================
##  PRUEBA DE DETERMINISMO Y EDICIONES DEL MUNDO (v2)
## =============================================================================
## Comprueba, con el juego real por delante:
##   1. Que dos partidas (procesos distintos) dan EXACTAMENTE la misma ciudad.
##   2. Que regenerar en la misma sesión da el mismo mundo.
##   3. Que la generación POR ETAPAS (la que usa el juego al cargar) da lo mismo.
##   4. Que una edición individual (tapa escondida + objeto a mano) se aplica y
##      NO altera nada más.
##   5. Que editar un edificio concreto se aplica y NO altera nada fuera de su
##      parcela.
##   6. Que el streaming (cargar/descargar sectores) deja el mundo idéntico.
##
## La ciudad la genera ESTA prueba (no la escena del mundo) y justo después, en el
## mismo fotograma, se congelan los peatones: así la huella se toma siempre en el
## pie de generación y es comparable entre partidas.
##
## Modo: variable de entorno PRISMAX_MODO
##   (vacío)   → todo lo anterior y, si hay huella base, la compara
##   guardar   → sólo la 1ª generación: guarda su huella como base
##   comparar  → sólo la 1ª generación: la compara con la base guardada
## =============================================================================

const RUTA_MUNDO := "res://ziba/escenas/ziba_prototipo.tscn"
const DIR := "res://.backup_semilla/"
const RUTA_LOG := DIR + "log_prueba_mundo.txt"
const RUTA_BASE := DIR + "huella_base.txt"
const RUTA_CAPTURAS := DIR + "capturas/"
## Subárboles que entran en la huella estática (el resto —jugador, enemigos,
## cielo, sol, ambiente, terreno— se mueve, depende del reloj o se construye por
## fotogramas, y no forma parte del reparto procedural de la ciudad).
const RAMAS := ["Ciudad", "Bosque", "Muelle", "Barco", "Oceano",
		"LimitesMundo", "NPC_Estatico_Obrero", "Farolas"]

var _log := ""
var _fallos := 0
var _mundo: Node = null
var _ciudad: Node = null
var _jugador: Node3D = null


func _ready() -> void:
	await get_tree().process_frame
	var modo := OS.get_environment("PRISMAX_MODO")
	if modo == "":
		modo = "todo"
	_linea("=== PRUEBA DE DETERMINISMO Y EDICIONES — modo %s — %s ===" % [
			modo, Time.get_datetime_string_from_system()])
	_linea("Semilla del mundo: %s" % SemillaMundo.descripcion())
	_linea("Ediciones en la tabla: %s" % EdicionesCiudad.resumen())

	var montado: bool = await _montar_mundo()
	if not montado:
		await _cerrar()
		return

	var h_ciudad := _huella_estatica()
	var h_peat := _huella_peatones()
	_linea("1ª generación: ciudad %s | nodos %d | instancias %d | peatones %s (%d)" % [
			h_ciudad["clave"], h_ciudad["nodos"], h_ciudad["instancias"],
			h_peat["clave"], h_peat["cuantos"]])

	if modo == "guardar":
		_guardar_base(h_ciudad, h_peat)
		_comprobar("huella base guardada en %s" % RUTA_BASE, true)
		await _cerrar()
		return
	if modo == "comparar":
		await _comparar_con_base(h_ciudad, h_peat)
		await _cerrar()
		return

	# --- Comparación con una partida anterior (proceso nuevo), si hay base ------
	var base := _leer_base()
	if base.is_empty():
		_linea("(sin huella base: corre una vez con PRISMAX_MODO=guardar para comparar entre procesos)")
	else:
		_comprobar("misma CIUDAD que la partida anterior (proceso nuevo)",
				String(base.get("ciudad", "")) == h_ciudad["clave"],
				"base=%s ahora=%s" % [base.get("ciudad", "?"), h_ciudad["clave"]])
		_comprobar("mismos PEATONES que la partida anterior (proceso nuevo)",
				String(base.get("peatones", "")) == h_peat["clave"],
				"base=%s ahora=%s" % [base.get("peatones", "?"), h_peat["clave"]])

	# --- 2) Regenerar en la misma sesión ---------------------------------------
	var t0 := Time.get_ticks_msec()
	_generar_ahora(false)
	var h_ciudad2 := _huella_estatica()
	var h_peat2 := _huella_peatones()
	_comprobar("regenerar en la misma sesión da la MISMA ciudad",
			h_ciudad["clave"] == h_ciudad2["clave"],
			"%s vs %s" % [h_ciudad["clave"], h_ciudad2["clave"]])
	_comprobar("regenerar en la misma sesión da los MISMOS peatones",
			h_peat["clave"] == h_peat2["clave"], "%s vs %s" % [h_peat["clave"], h_peat2["clave"]])
	_linea("(regeneración en la misma sesión: %d ms)" % (Time.get_ticks_msec() - t0))

	# --- 3) Generación por etapas (el camino que usa el juego al cargar) --------
	await _generar_ahora(true)
	var h_ciudad3 := _huella_estatica()
	_comprobar("la generación POR ETAPAS da la MISMA ciudad",
			h_ciudad["clave"] == h_ciudad3["clave"],
			"%s vs %s" % [h_ciudad["clave"], h_ciudad3["clave"]])
	_comprobar("y los MISMOS peatones", h_peat["clave"] == _huella_peatones()["clave"])

	# --- 4) Edición de un prop + objeto a mano ---------------------------------
	await _probar_edicion_de_prop(h_ciudad, h_peat)
	# --- 5) Edición de un edificio concreto ------------------------------------
	await _probar_edicion_de_edificio(h_ciudad)
	# --- 6) Streaming ----------------------------------------------------------
	await _probar_streaming(h_ciudad)

	await _cerrar()


# ------------------------------------------------------------------ montaje

func _montar_mundo() -> bool:
	var escena: PackedScene = load(RUTA_MUNDO)
	if escena == null:
		_comprobar("la escena del mundo carga", false, RUTA_MUNDO)
		return false
	_mundo = escena.instantiate()
	# La ciudad la genera esta prueba (y no la escena) para poder tomar la huella
	# en el mismo fotograma de la generación.
	_ciudad = _mundo.get_node_or_null("Ciudad")
	if _ciudad == null:
		_comprobar("la escena del mundo trae el nodo Ciudad", false)
		return false
	_ciudad.set("generar_al_iniciar", false)
	get_tree().root.add_child.call_deferred(_mundo)
	await get_tree().process_frame
	await get_tree().process_frame
	_jugador = _mundo.get_node_or_null("Jugador") as Node3D
	_generar_ahora(false)
	var generada := _mundo.get_node_or_null("Ciudad/CiudadGenerada")
	var ok := generada != null
	_comprobar("mundo montado y ciudad generada", ok)
	if not ok:
		return false
	_linea("CiudadGenerada tiene %d hijos directos" % generada.get_child_count())
	_comprobar("director de peatones instalado",
			_mundo.get_node_or_null("Ciudad/CiudadGenerada/Peatones") != null)
	return true


## Genera la ciudad (de una vez o por etapas) y CONGELA a los peatones en el mismo
## fotograma: así la huella se toma en el pie de generación y no depende del reloj.
func _generar_ahora(por_etapas: bool) -> void:
	_ciudad.call("limpiar_ciudad")
	if por_etapas:
		await _ciudad.generar_ciudad_por_etapas()
	else:
		_ciudad.call("generar_ciudad")
	_congelar_peatones()


func _congelar_peatones() -> void:
	var p := _mundo.get_node_or_null("Ciudad/CiudadGenerada/Peatones")
	if p == null:
		return
	for c in p.get_children():
		if c is CharacterBody3D:
			c.set_physics_process(false)
			c.set_process(false)


# ------------------------------------------------------------------ huellas

## Huella del MAPA: posiciones, giros y escalas de cada nodo y de CADA instancia
## de cada multimesh, con la lista ORDENADA (no influye el orden de recorrido).
## Los esqueletos (huesos animados) y los peatones quedan fuera: los peatones
## tienen su propia huella, tomada en el pie de generación.
func _huella_estatica(excl_a := "", excl_b := "", caja := AABB()) -> Dictionary:
	var piezas: Array[String] = []
	var nodos := 0
	var instancias := 0
	var pila: Array[Node] = []
	for rama: String in RAMAS:
		var n := _mundo.get_node_or_null(rama)
		if n != null:
			pila.append(n)
	while not pila.is_empty():
		var n: Node = pila.pop_back()
		if String(n.name) == "Peatones" or n is Skeleton3D:
			continue
		if n is Node3D:
			var t: Transform3D = (n as Node3D).transform
			var o := t.origin
			if not _excluido(String(n.name), o, excl_a, excl_b, caja):
				var e := t.basis.get_euler()
				var s := t.basis.get_scale()
				piezas.append("N|%s|%.4f,%.4f,%.4f|%.4f,%.4f,%.4f|%.4f,%.4f,%.4f" % [
						n.name, o.x, o.y, o.z, e.x, e.y, e.z, s.x, s.y, s.z])
				nodos += 1
		if n is MultiMeshInstance3D:
			var mm := (n as MultiMeshInstance3D).multimesh
			if mm != null:
				var partes: Array[String] = []
				for i in mm.instance_count:
					var t := mm.get_instance_transform(i)
					if _excluido("", t.origin, excl_a, excl_b, caja):
						continue
					partes.append("%.4f,%.4f,%.4f|%.4f" % [t.origin.x, t.origin.y, t.origin.z,
							t.basis.get_euler().y])
				partes.sort()
				piezas.append("M|%s|%d|%s" % [n.name, partes.size(), ";".join(partes)])
				instancias += partes.size()
		for c in n.get_children():
			pila.append(c)
	piezas.sort()
	return {"clave": "%d" % hash("\n".join(piezas)), "nodos": nodos, "instancias": instancias}


## Huella de los PEATONES: cuántos, dónde nacieron y con qué carácter salieron
## (todo lo que decide su semilla).
func _huella_peatones() -> Dictionary:
	var p := _mundo.get_node_or_null("Ciudad/CiudadGenerada/Peatones")
	if p == null:
		return {"clave": "ausente", "cuantos": 0}
	var lineas: Array[String] = []
	var cuantos := 0
	for c in p.get_children():
		if not (c is CharacterBody3D):
			continue
		cuantos += 1
		var modelo := ""
		var ms: Variant = c.get("model_scene")
		if ms is PackedScene:
			modelo = (ms as PackedScene).resource_path
		var idle: Variant = c.get("idle_time")
		lineas.append("P|%.4f,%.4f,%.4f|%.4f|%s|%d|%.4f|%.4f|%.4f" % [
				c.position.x, c.position.y, c.position.z, c.rotation.y, modelo,
				int(c.get("semilla")), float(c.get("move_scale")), float(c.get("hurry_chance")),
				idle.x if idle is Vector2 else 0.0])
	lineas.sort()
	return {"clave": "%d" % hash("\n".join(lineas)), "cuantos": cuantos}


func _excluido(nombre: String, p: Vector3, excl_a: String, excl_b: String, caja: AABB) -> bool:
	if excl_a != "" and nombre == excl_a:
		return true
	if excl_b != "" and nombre == excl_b:
		return true
	if caja.size != Vector3.ZERO and p.x >= caja.position.x and p.x <= caja.end.x \
			and p.z >= caja.position.z and p.z <= caja.end.z:
		return true
	return false


# ------------------------------------------------------------------ pruebas

func _probar_edicion_de_prop(h_base: Dictionary, h_peat_base: Dictionary) -> void:
	_linea("--- Edición de una tapa + objeto a mano ---")
	var nodo_tapa := _mundo.find_child("tapa_V3_2", true, false)
	_comprobar("la tapa de partida existe (nodo tapa_V3_2)", nodo_tapa != null)
	var pieza := "Prop_ManholeCover"
	if nodo_tapa != null and nodo_tapa.scene_file_path != "":
		pieza = nodo_tapa.scene_file_path.get_file().get_basename()
	_linea("(pieza para el objeto a mano: %s)" % pieza)
	var pos_extra := Vector3(-21.0, 0.0, 11.0)
	EdicionesCiudad.inyectar({
		"props": {"tapa:V3:2": {"ocultar": true}},
		"extra": [{"nombre": "Prueba_extra", "pieza": pieza, "pos": pos_extra,
				"giro_grados": 33.0, "escala": 1.0, "apoyar": false}],
	})
	_generar_ahora(false)
	_comprobar("la tapa editada YA NO se genera",
			_mundo.find_child("tapa_V3_2", true, false) == null)
	var nodo_extra := _mundo.find_child("Prueba_extra", true, false) as Node3D
	_comprobar("el objeto a mano existe en su posición exacta",
			nodo_extra != null and nodo_extra.transform.origin.distance_to(pos_extra) < 0.001,
			"ausente" if nodo_extra == null else "pos %s" % nodo_extra.transform.origin)
	# La huella de esta generación se calcula SALTÁNDOSE la tapa quitada y el
	# objeto añadido: si algo más hubiera cambiado, las claves no cuadrarían.
	var h := _huella_estatica("tapa_V3_2", "Prueba_extra")
	_comprobar("el resto de la ciudad queda IGUAL (sólo cambian esos dos)",
			h["clave"] == h_base["clave"], "%s vs %s" % [h["clave"], h_base["clave"]])
	_comprobar("el reparto de peatones no se movió por editar una tapa",
			_huella_peatones()["clave"] == h_peat_base["clave"])
	EdicionesCiudad.limpiar_inyeccion()
	_generar_ahora(false)
	_comprobar("al quitar la edición vuelve EXACTAMENTE el mundo de antes",
			_huella_estatica()["clave"] == h_base["clave"])


func _probar_edicion_de_edificio(h_base: Dictionary) -> void:
	_linea("--- Edición de un edificio concreto ---")
	var cont := _mundo.get_node_or_null("Ciudad/CiudadGenerada/Modulares")
	if cont == null:
		_comprobar("contenedor de edificios modulares presente", false)
		return
	var elegido: Node3D = null
	var caja := Vector3.ZERO
	for c in cont.get_children():
		if not (c is Node3D) or not String(c.name).begins_with("E"):
			continue
		var col := c.find_child("Edificio_modular_*", false, false)
		if col == null:
			continue
		var forma := col.find_child("*", false, false)
		if forma is CollisionShape3D and (forma as CollisionShape3D).shape is BoxShape3D:
			elegido = c as Node3D
			caja = ((forma as CollisionShape3D).shape as BoxShape3D).size
			break
	if elegido == null:
		_comprobar("hay un edificio modular con parcela medible", false)
		return
	var id_ed := String(elegido.name)
	var centro := elegido.position
	_linea("edificio elegido: %s en (%.2f, %.2f, %.2f), parcela %.1f x %.1f m" % [
			id_ed, centro.x, centro.y, centro.z, caja.x, caja.z])
	# Caja de exclusión: la parcela con 1.5 m de margen es TODO lo que puede cambiar.
	var caja_excl := AABB(centro - Vector3(caja.x * 0.5 + 1.5, 0.0, caja.z * 0.5 + 1.5),
			Vector3(caja.x + 3.0, 0.0, caja.z + 3.0))
	EdicionesCiudad.inyectar({"edificios": {id_ed: {"pisos": 9, "color": Color(0.85, 0.25, 0.2)}}})
	_generar_ahora(false)
	var nuevo := _mundo.get_node_or_null("Ciudad/CiudadGenerada/Modulares/%s" % id_ed) as Node3D
	_comprobar("la casa editada sigue existiendo con su id", nuevo != null)
	var mallas := 0
	var con_material := 0
	if nuevo != null:
		for m in nuevo.find_children("*", "MeshInstance3D", true, false):
			mallas += 1
			if (m as MeshInstance3D).material_override != null:
				con_material += 1
	# La casa editada se construye aparte (instanciada) para no tocar el lote
	# compartido: por eso tiene mallas propias, todas con su material.
	_comprobar("la casa editada se construye aparte (mallas propias)", mallas > 0,
			"%d mallas" % mallas)
	_comprobar("la casa editada lleva su material/tinte propio",
			mallas > 0 and con_material == mallas, "%d de %d" % [con_material, mallas])
	var h := _huella_estatica("", "", caja_excl)
	_comprobar("fuera de esa parcela la ciudad queda IGUAL (nada más se movió)",
			h["clave"] == h_base["clave"], "%s vs %s" % [h["clave"], h_base["clave"]])
	await _capturar_parcela(centro, caja, "01_edificio_editado.png")
	EdicionesCiudad.limpiar_inyeccion()
	_generar_ahora(false)
	_comprobar("al quitar la edición del edificio vuelve EXACTAMENTE el mundo de antes",
			_huella_estatica()["clave"] == h_base["clave"])


func _probar_streaming(h_base: Dictionary) -> void:
	_linea("--- Streaming: cargar y descargar sectores ---")
	var st := _mundo.get_node_or_null("StreamingMundo")
	if st == null or _jugador == null:
		_comprobar("nodo StreamingMundo y jugador presentes", false)
		return
	var sectores := _mundo.get_node_or_null("Ciudad/CiudadGenerada/Sectores")
	var antes := _nombres_hijos(sectores)
	st.call("set_activo", true)
	await _esperar_fotogramas(10)
	_jugador.global_position = Vector3(-120.0, 3.0, -120.0)
	await _esperar_fotogramas(180)
	var en_medio := _nombres_hijos(sectores)
	_comprobar("el streaming descargó sectores al alejarse", en_medio.size() < antes.size(),
			"%d de %d sectores siguen cargados" % [en_medio.size(), antes.size()])
	_jugador.global_position = Vector3(0.0, 3.0, 0.0)
	await _esperar_fotogramas(240)
	var despues := _nombres_hijos(sectores)
	_comprobar("al volver se restauran TODOS los sectores", despues == antes,
			"%d de %d" % [despues.size(), antes.size()])
	var h := _huella_estatica()
	_comprobar("tras cargar y descargar, el mapa es IDÉNTICO", h["clave"] == h_base["clave"],
			"%s vs %s" % [h["clave"], h_base["clave"]])
	st.call("set_activo", false)
	_linea("(se descargaron %d sectores)" % (antes.size() - en_medio.size()))


func _capturar_parcela(centro: Vector3, caja: Vector3, archivo: String) -> void:
	if DisplayServer.get_name() == "headless":
		_linea("(captura omitida: esta corrida va sin ventana)")
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(RUTA_CAPTURAS))
	var cam := Camera3D.new()
	_mundo.add_child(cam)
	cam.position = centro + Vector3(caja.x * 1.1, maxf(14.0, caja.x * 0.9), caja.z * 1.1)
	cam.look_at(centro + Vector3(0.0, 6.0, 0.0))
	cam.current = true
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(RUTA_CAPTURAS + archivo)
	cam.queue_free()
	_linea("captura: %s" % (RUTA_CAPTURAS + archivo))


# ------------------------------------------------------------------ utilidades

func _nombres_hijos(n: Node) -> Array[String]:
	var lista: Array[String] = []
	if n == null:
		return lista
	for c in n.get_children():
		lista.append(String(c.name))
	lista.sort()
	return lista


func _esperar_fotogramas(cuantos: int) -> void:
	for _i in cuantos:
		await get_tree().process_frame


func _comparar_con_base(h_ciudad: Dictionary, h_peat: Dictionary) -> void:
	var base := _leer_base()
	if base.is_empty():
		_comprobar("hay huella base guardada", false, RUTA_BASE)
		return
	_comprobar("misma CIUDAD que en la partida anterior (proceso nuevo)",
			String(base.get("ciudad", "")) == h_ciudad["clave"],
			"base=%s ahora=%s" % [base.get("ciudad", "?"), h_ciudad["clave"]])
	_comprobar("mismos PEATONES que en la partida anterior (proceso nuevo)",
			String(base.get("peatones", "")) == h_peat["clave"],
			"base=%s ahora=%s" % [base.get("peatones", "?"), h_peat["clave"]])


func _comprobar(nombre: String, ok: bool, detalle := "") -> void:
	if not ok:
		_fallos += 1
	_linea("%s %s%s" % ["OK  " if ok else "FALLO", nombre,
			("  -> " + detalle) if detalle != "" else ""])


func _linea(texto: String) -> void:
	_log += texto + "\n"
	print("[PRUEBA] ", texto)


func _cerrar() -> void:
	_linea("=== FIN: %s ===" % ("TODO OK" if _fallos == 0 else "%d FALLOS" % _fallos))
	var f := FileAccess.open(RUTA_LOG, FileAccess.WRITE)
	if f != null:
		f.store_string(_log)
		f.close()
	print("[PRUEBA] registro en ", RUTA_LOG)
	await _esperar_fotogramas(2)
	get_tree().quit(0 if _fallos == 0 else 1)


func _guardar_base(h_ciudad: Dictionary, h_peat: Dictionary) -> void:
	var f := FileAccess.open(RUTA_BASE, FileAccess.WRITE)
	if f == null:
		return
	f.store_line("ciudad=%s" % h_ciudad["clave"])
	f.store_line("peatones=%s" % h_peat["clave"])
	f.store_line("nodos=%d" % h_ciudad["nodos"])
	f.store_line("instancias=%d" % h_ciudad["instancias"])
	f.close()


func _leer_base() -> Dictionary:
	if not FileAccess.file_exists(RUTA_BASE):
		return {}
	var f := FileAccess.open(RUTA_BASE, FileAccess.READ)
	if f == null:
		return {}
	var d := {}
	while not f.eof_reached():
		var l := f.get_line()
		if l.contains("="):
			d[l.get_slice("=", 0)] = l.get_slice("=", 1)
	f.close()
	return d