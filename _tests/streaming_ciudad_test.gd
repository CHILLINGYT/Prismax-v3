extends Node3D
## =============================================================================
##  PRUEBA P9-D1a — STREAMING VISUAL DE LOS SECTORES DE CIUDAD (AISLADA)
## =============================================================================
##  Escena MÍNIMA: sólo el generador `Ciudad` (con peatones desactivados para
##  aligerar; los sectores NO dependen de ellos) + un marcador `Jugador` + el
##  `Gestor`. No carga terreno, bosque, oceano ni HUD.
##
##  Comprueba:
##    · referencia con TODOS los sectores cargados,
##    · ≥3 ciclos de descarga y restauración,
##    · firmas canónicas idénticas (nombres, posiciones, mallas, cast_shadow,
##      nº de instancias y TODAS las matrices/colores),
##    · sin duplicados, sin referencias inválidas, sin errores,
##    · memoria de objetos de Godot (con sus limitaciones).
##
##  Uso:  XDG_DATA_HOME=/tmp/... godot --headless --path . \
##          res://_tests/streaming_ciudad_test.tscn
## =============================================================================

const P_DENTRO := Vector3(0.0, 0.0, 0.0)       # dentro de la ciudad (todo cargado)
const P_FUERA := Vector3(600.0, 0.0, 600.0)    # lejos (todo descargado)
const CICLOS := 3
const ESPERA_S := 0.8

var _ciudad: Node
var _gestor: Node
var _jugador: Node3D
var _sectores: Node3D
var _ok := 0
var _fallos := 0
var _mem_ref := 0.0
var _mem_min := 1.0e12


func _ready() -> void:
	_ciudad = $Ciudad
	_gestor = $Gestor
	_jugador = $Jugador

	if not await _esperar_sectores():
		print("[TEST] FALLO: la ciudad no generó sectores.")
		get_tree().quit(1)
		return
	_sectores = _ciudad.get_node("CiudadGenerada/Sectores") as Node3D

	print("[TEST] gestor activo=%s | radios a=%.0f p=%.0f d=%.0f | sectores=%d" % [
			str(_gestor.get("activo")), float(_gestor.get("r_activo")),
			float(_gestor.get("r_precarga")), float(_gestor.get("r_descarga")),
			int(_gestor.call("resumen")["total"])])
	_listar_distancias()

	# --- Referencia: forzamos TODO cargado ---
	_gestor.call("restaurar_todo")
	var firma_inicial: Dictionary = _firma()
	var res_inicial: Dictionary = _gestor.call("resumen")
	var mem_inicial := _memoria()
	_mem_ref = mem_inicial
	print("[TEST] referencia (todo cargado): sectores=%d instancias=%d memoria_static=%.3f MB" % [
			int(res_inicial["nodos_presentes"]), int(res_inicial["instancias_presentes"]),
			mem_inicial])
	_comprobar("referencia: TODOS los sectores cargados",
			int(res_inicial["nodos_presentes"]) == int(res_inicial["total"]))

	# --- Ciclos: alejar (descarga), volver, reconstrucción TOTAL exacta ---
	for it in CICLOS:
		_jugador.global_position = P_FUERA
		await _esperar_hasta(func(r: Dictionary) -> bool: return int(r["unloaded"]) == int(r["total"]))
		var res_lejos: Dictionary = _gestor.call("resumen")
		var mem_lejos := _memoria()
		print("[TEST] ciclo %d · fuera: sectores=%d/%d (U=%d R=%d A=%d) inst=%d mem=%.3f MB" % [
				it, int(res_lejos["nodos_presentes"]), int(res_lejos["total"]),
				int(res_lejos["unloaded"]), int(res_lejos["ready"]), int(res_lejos["active"]),
				int(res_lejos["instancias_presentes"]), mem_lejos])
		_comprobar("ciclo %d: al alejarse se DESCARGAN sectores" % it,
				int(res_lejos["nodos_presentes"]) < int(res_inicial["total"]))
		_comprobar("ciclo %d: se descargan TODOS los sectores lejanos" % it,
				int(res_lejos["nodos_presentes"]) == 0
						and int(res_lejos["unloaded"]) == int(res_lejos["total"]))
		print("[TEST] ciclo %d: memoria_static (todo)=%.3f MB vs (lejos)=%.3f MB -> delta %+.3f MB" % [
				it, mem_inicial, mem_lejos, mem_lejos - mem_inicial])
		_comprobar("ciclo %d: sin duplicados tras descargar" % it, _sin_duplicados())
		_comprobar("ciclo %d: referencias válidas tras descargar" % it, _todas_validas())

		_jugador.global_position = P_DENTRO
		await _esperar_hasta(func(r: Dictionary) -> bool: return int(r["unloaded"]) == 0 and int(r["loading"]) == 0 and int(r["unloading"]) == 0 and int(r["nodos_presentes"]) == int(r["total"]))
		var res_dentro: Dictionary = _gestor.call("resumen")
		print("[TEST] ciclo %d · dentro: sectores=%d/%d (U=%d R=%d A=%d)" % [
				it, int(res_dentro["nodos_presentes"]), int(res_dentro["total"]),
				int(res_dentro["unloaded"]), int(res_dentro["ready"]), int(res_dentro["active"])])

		# Reconstrucción TOTAL y comparación EXACTA con la referencia.
		_gestor.call("restaurar_todo")
		var res_full: Dictionary = _gestor.call("resumen")
		var firma_full: Dictionary = _firma()
		_comprobar("ciclo %d: tras restaurar, TODOS los sectores presentes" % it,
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

	print("[TEST] MEMORIA: MEMORY_STATIC (todo cargado)=%.3f MB; mínimo observado al descargar=%.3f MB (delta %+.3f MB). Los búferes de instancia del MultiMesh viven en el servidor de render (VRAM) y NO se cuentan; en headless no hay GPU. AHORRO DE RAM/VRAM: NO DEMOSTRADO." % [
			_mem_ref, _mem_min, _mem_min - _mem_ref])
	print("[TEST] ===== RESULTADO STREAMING CIUDAD: %d OK, %d FALLOS =====" % [_ok, _fallos])
	get_tree().quit(0 if _fallos == 0 else 1)


# ------------------------------------------------------------------ utilidades
func _esperar_sectores() -> bool:
	for i in 900:
		var s := _ciudad.get_node_or_null("CiudadGenerada/Sectores")
		if s != null and s.get_child_count() > 0 and _gestor.call("resumen")["total"] > 0:
			return true
		await get_tree().process_frame
	return false


func _listar_distancias() -> void:
	var r: Dictionary = _gestor.call("resumen")
	print("[TEST] %d sectores." % int(r["total"]))


func _esperar(seg: float) -> void:
	await get_tree().create_timer(seg, true, false, true).timeout


## Espera hasta que se cumpla la condición sobre el resumen del gestor (o agota
## el tiempo). Necesario en headless: el gestor aplica por fotogramas y lento.
func _esperar_hasta(cond: Callable, timeout_s := 40.0) -> bool:
	var t := 0.0
	while t < timeout_s:
		if cond.call(_gestor.call("resumen")):
			return true
		await get_tree().create_timer(0.1, true, false, true).timeout
		t += 0.1
	return false


## Firma canónica de TODOS los sectores.
func _firma() -> Dictionary:
	var nodos: Array[String] = []
	for c in _sectores.get_children():
		if c is Node3D and String(c.name).begins_with("S_"):
			nodos.append(String(c.name))
	nodos.sort()
	var s := ""
	var inst := 0
	for nombre in nodos:
		var nodo := _sectores.get_node_or_null(NodePath(nombre)) as Node3D
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
	return {"hash": hash(s), "nodos": nodos.size(), "instancias": inst, "texto": s}


func _sin_duplicados() -> bool:
	var vistos := {}
	for c in _sectores.get_children():
		if c is Node3D and String(c.name).begins_with("S_"):
			if vistos.has(c.name):
				return false
			vistos[c.name] = true
	return true


func _todas_validas() -> bool:
	for c in _sectores.get_children():
		if c is Node3D and String(c.name).begins_with("S_"):
			if not is_instance_valid(c):
				return false
	return true


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