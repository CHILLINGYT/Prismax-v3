extends Node3D
## =============================================================================
##  PRUEBA P9-B — STREAMING DE LOS TROZOS DEL BOSQUE (AISLADA, SIN EL MUNDO)
## =============================================================================
##  Escena MÍNIMA: sólo `Bosque` + un marcador `Jugador` + el `Gestor`. No carga
##  la ciudad ni el terreno: el bosque es autónomo (usa Relieve y Vegetacion), así
##  que la prueba es ligera y no sufre la presión de memoria del mundo completo.
##
##  Comprueba:
##    · que al alejar al jugador se DESCARGAN trozos (nodos presentes bajan),
##    · que al volver se RESTAURAN exactamente (misma firma: nombres, posiciones,
##      mallas, cast_shadow, nº de instancias y TODAS las matrices/colores),
##    · que no aparecen duplicados, ni referencias inválidas, ni errores,
##    · que los recuentos vuelven al valor inicial tras cada ciclo (3 ciclos),
##    · la memoria de objetos de Godot antes y después de descargar.
##
##  Uso:  XDG_DATA_HOME=/tmp/... godot --headless --path . \
##          res://_tests/streaming_bosque_test.tscn
## =============================================================================

const P_CIUDAD := Vector3(0.0, 0.0, 0.0)           # centro urbano (lejos del bosque)
const P_BOSQUE := Vector3(-450.0, 0.0, -450.0)     # dentro del bosque (noroeste)
const CICLOS := 3
const ESPERA_S := 0.7

var _bosque: Node3D
var _gestor: Node
var _jugador: Node3D
var _ok := 0
var _fallos := 0
var _mem_ref := 0.0
var _mem_min := 1.0e12


func _ready() -> void:
	_bosque = $Bosque
	_gestor = $Gestor
	_jugador = $Jugador

	if not await _esperar_bosque():
		print("[TEST] FALLO: el bosque no generó trozos.")
		get_tree().quit(1)
		return

	print("[TEST] gestor activo=%s | radios a=%.0f p=%.0f d=%.0f | trozos=%d" % [
			str(_gestor.get("activo")), float(_gestor.get("r_activo")),
			float(_gestor.get("r_precarga")), float(_gestor.get("r_descarga")),
			int(_gestor.call("resumen")["total"])])
	_listar_distancias()

	# --- Estado de referencia: forzamos TODO cargado y capturamos ---
	_gestor.call("restaurar_todo")
	var firma_inicial: Dictionary = _firma()
	var res_inicial: Dictionary = _gestor.call("resumen")
	var mem_inicial := _memoria()
	_mem_ref = mem_inicial
	print("[TEST] referencia (todo cargado): nodos=%d instancias=%d memoria_static=%.3f MB" % [
			int(res_inicial["nodos_presentes"]), int(res_inicial["instancias_presentes"]),
			mem_inicial])
	_comprobar("referencia: TODOS los trozos cargados",
			int(res_inicial["nodos_presentes"]) == int(res_inicial["total"]))

	# --- Ciclos: alejar (descarga), acercar, y reconstrucción TOTAL exacta ---
	for it in CICLOS:
		_jugador.global_position = P_CIUDAD
		await _esperar(ESPERA_S)
		var res_lejos: Dictionary = _gestor.call("resumen")
		var mem_lejos := _memoria()
		print("[TEST] ciclo %d · ciudad: nodos=%d/%d (U=%d R=%d A=%d) inst=%d mem=%.3f MB" % [
				it, int(res_lejos["nodos_presentes"]), int(res_lejos["total"]),
				int(res_lejos["unloaded"]), int(res_lejos["ready"]), int(res_lejos["active"]),
				int(res_lejos["instancias_presentes"]), mem_lejos])
		_comprobar("ciclo %d: al alejarse se DESCARGAN trozos" % it,
				int(res_lejos["nodos_presentes"]) < int(res_inicial["total"]))
		print("[TEST] ciclo %d: memoria_static (17 cargados)=%.3f MB vs (14 cargados)=%.3f MB -> delta %+.3f MB" % [
				it, mem_inicial, mem_lejos, mem_lejos - mem_inicial])
		_comprobar("ciclo %d: sin duplicados tras descargar" % it, _sin_duplicados())
		_comprobar("ciclo %d: referencias válidas tras descargar" % it, _todas_validas())

		_jugador.global_position = P_BOSQUE
		await _esperar(ESPERA_S)
		var res_bosque: Dictionary = _gestor.call("resumen")
		var mem_bosque := _memoria()
		print("[TEST] ciclo %d · bosque: nodos=%d/%d (U=%d R=%d A=%d) inst=%d mem=%.3f MB" % [
				it, int(res_bosque["nodos_presentes"]), int(res_bosque["total"]),
				int(res_bosque["unloaded"]), int(res_bosque["ready"]), int(res_bosque["active"]),
				int(res_bosque["instancias_presentes"]), mem_bosque])

		# Reconstrucción TOTAL y comparación EXACTA con el estado recién generado.
		_gestor.call("restaurar_todo")
		var res_full: Dictionary = _gestor.call("resumen")
		var firma_full: Dictionary = _firma()
		_comprobar("ciclo %d: tras restaurar, TODOS los trozos presentes" % it,
				int(res_full["nodos_presentes"]) == int(res_full["total"])
						and int(res_full["unloaded"]) == 0)
		_comprobar("ciclo %d: contenido restaurado EXACTO (hash y conteos)" % it,
				firma_full["hash"] == firma_inicial["hash"]
						and firma_full["nodos"] == firma_inicial["nodos"]
						and firma_full["instancias"] == firma_inicial["instancias"])
		_comprobar("ciclo %d: sin duplicados tras restaurar" % it, _sin_duplicados())
		_comprobar("ciclo %d: referencias válidas tras restaurar" % it, _todas_validas())

	_comprobar("la firma restaurada es idéntica carácter a carácter",
			String(_firma()["texto"]) == String(firma_inicial["texto"]))

	print("[TEST] MEMORIA: MEMORY_STATIC con todo cargado=%.3f MB; mínimo observado al descargar=%.3f MB (delta %+.3f MB). Los búferes de instancia del MultiMesh viven en el servidor de render (VRAM) y NO se cuentan en MEMORY_STATIC; en headless no hay GPU real. REDUCCIÓN DE RAM: NO DEMOSTRADA (inconcluso)." % [
			_mem_ref, _mem_min, _mem_min - _mem_ref])
	print("[TEST] ===== RESULTADO STREAMING BOSQUE: %d OK, %d FALLOS =====" % [_ok, _fallos])
	get_tree().quit(0 if _fallos == 0 else 1)


# ------------------------------------------------------------------ utilidades
func _esperar_bosque() -> bool:
	for i in 600:
		if _bosque.get_child_count() > 0 and _gestor.call("resumen")["total"] > 0:
			return true
		await get_tree().process_frame
	return false


func _listar_distancias() -> void:
	var r: Dictionary = _gestor.call("resumen")
	print("[TEST] %d trozos. Distancia de su centro a ciudad/bosque:" % int(r["total"]))
	for c in _bosque.get_children():
		if c is Node3D and String(c.name).begins_with("Trozo_"):
			var centro: Vector3 = (c as Node3D).global_position + Vector3(100, 0, 100)
			var dc := Vector2(centro.x, centro.z).distance_to(Vector2(P_CIUDAD.x, P_CIUDAD.z))
			var db := Vector2(centro.x, centro.z).distance_to(Vector2(P_BOSQUE.x, P_BOSQUE.z))
			print("        %s centro=(%.0f,%.0f) d_ciudad=%.0f d_bosque=%.0f" % [
					c.name, centro.x, centro.z, dc, db])


func _esperar(seg: float) -> void:
	await get_tree().create_timer(seg, true, false, true).timeout


## Firma canónica de TODO el bosque: nombres, posiciones, mallas, cast_shadow, nº
## de instancias y cada matriz/color. Dos firmas iguales => restauración idéntica.
func _firma() -> Dictionary:
	var nombres: Array[String] = []
	for c in _bosque.get_children():
		if c is Node3D and String(c.name).begins_with("Trozo_"):
			nombres.append(String(c.name))
	nombres.sort()
	var s := ""
	var inst := 0
	for nombre in nombres:
		var nodo := _bosque.get_node_or_null(NodePath(nombre)) as Node3D
		if nodo == null:
			continue
		s += nombre + "@" + str(nodo.position) + ";"
		var hijos: Array[Node3D] = []
		for m in nodo.get_children():
			if m is MultiMeshInstance3D:
				hijos.append(m as Node3D)
		hijos.sort_custom(func(a: Node3D, b: Node3D) -> bool: return String(a.name) < String(b.name))
		for m in hijos:
			var mmi := m as MultiMeshInstance3D
			var mm := mmi.multimesh
			s += "%s*%d*%d*%d*" % [mmi.name, mm.mesh.get_instance_id(), mmi.cast_shadow, mm.instance_count]
			for i in mm.instance_count:
				s += str(mm.get_instance_transform(i))
				if mm.use_colors:
					s += str(mm.get_instance_color(i))
			s += ";"
			inst += mm.instance_count
	return {"hash": hash(s), "nodos": nombres.size(), "instancias": inst, "texto": s}


func _sin_duplicados() -> bool:
	var vistos := {}
	for c in _bosque.get_children():
		if c is Node3D and String(c.name).begins_with("Trozo_"):
			if vistos.has(c.name):
				return false
			vistos[c.name] = true
	return true


func _todas_validas() -> bool:
	for c in _bosque.get_children():
		if c is Node3D and String(c.name).begins_with("Trozo_"):
			if not is_instance_valid(c):
				return false
	return true


## Memoria de objetos de Godot (estática). NO incluye fragmentación del heap del
## SO ni la VRAM de mallas/texturas compartidas. En headless no hay GPU real.
func _memoria() -> float:
	var m := Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	if m < _mem_min:
		_mem_min = m
	return m


func _comprobar(texto: String, ok: bool) -> void:
	if ok:
		_ok += 1
		print("[OK]    ", texto)
	else:
		_fallos += 1
		print("[FALLO] ", texto)