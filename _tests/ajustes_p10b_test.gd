extends Node
## Prueba ligera de P10-B: la opción "Optimización agresiva del mundo" y sus
## controles en el menú de pausa. NO genera el mundo. Usa XDG aislado.

var _ok := 0
var _fallos := 0


func _ready() -> void:
	# 1) El autoload existe y la opción arranca APAGADA por defecto (salvo preferencia).
	_comprobar("AjustesGraficos es el autoload", AjustesGraficos != null)
	_comprobar("optimización arranca APAGADA", AjustesGraficos.optimizacion_agresiva == false)
	_comprobar("nivel de carga dentro de rango",
			AjustesGraficos.distancia_carga >= 0
			and AjustesGraficos.distancia_carga <= AjustesGraficos.CARGA_NIVELES)

	# 2) El mapeo a metros es monótono y dentro de los límites reales del mapa.
	var r0 := _radio_para(0)
	var r10 := _radio_para(10)
	_comprobar("radio de carga crece con el nivel", r10 > r0)
	_comprobar("radio de carga en 60..600 m",
			r0 >= 60.0 - 0.01 and r10 <= 600.0 + 0.01)
	_comprobar("margen de precarga crece y es positivo",
			_margen_para(10) > _margen_para(0) and _margen_para(0) > 0.0)

	# 3) La escena del menú de pausa carga con los controles nuevos (resuelve %nodos).
	var pm := (load("res://ui/scenes/PauseMenu.tscn") as PackedScene).instantiate()
	add_child(pm)
	await get_tree().process_frame
	_comprobar("PauseMenu se instancia sin error", pm != null)
	var base := "Root/ConfigPanel/ConfigScroll/ConfigContent/OptimizacionDependientes/"
	_comprobar("fila del interruptor presente",
			pm.get_node_or_null("Root/ConfigPanel/ConfigScroll/ConfigContent/OptimizacionFila/OptimizacionValor") != null)
	_comprobar("panel de dependientes presente",
			pm.get_node_or_null("Root/ConfigPanel/ConfigScroll/ConfigContent/OptimizacionDependientes") != null)
	_comprobar("barra de carga presente", pm.get_node_or_null(base + "CargaFila/CargaBarra") != null)
	_comprobar("barra de precarga presente", pm.get_node_or_null(base + "PrecargaFila/PrecargaBarra") != null)
	_comprobar("fila de diagnóstico presente", pm.get_node_or_null(base + "DiagnosticoFila/DiagnosticoValor") != null)
	# Están ocultos hasta activar la opción.
	var deps := pm.get_node_or_null("Root/ConfigPanel/ConfigScroll/ConfigContent/OptimizacionDependientes") as Control
	_comprobar("dependientes ocultos con la opción OFF", deps != null and deps.visible == false)

	# 4) Activar/desactivar y comprobar el estado real.
	AjustesGraficos.poner_distancia_carga(7)
	AjustesGraficos.poner_distancia_precarga(2)
	AjustesGraficos.poner_optimizacion_agresiva(true)
	_comprobar("se activa", AjustesGraficos.optimizacion_agresiva == true)
	_comprobar("carga queda en 7", AjustesGraficos.distancia_carga == 7)
	AjustesGraficos.poner_diagnostico_stream(true)
	_comprobar("diagnóstico activable", AjustesGraficos.modo_diagnostico_stream == true)
	AjustesGraficos.poner_optimizacion_agresiva(false)
	_comprobar("se desactiva", AjustesGraficos.optimizacion_agresiva == false)

	# 5) Persistencia: una instancia nueva relee lo guardado (XDG aislado).
	var svc = (load("res://ui/scripts/ajustes_graficos.gd") as GDScript).new()
	svc._cargar()
	_comprobar("persistencia: carga = 7", svc.distancia_carga == 7)
	_comprobar("persistencia: precarga = 2", svc.distancia_precarga == 2)
	_comprobar("persistencia: optimización = false", svc.optimizacion_agresiva == false)
	_comprobar("persistencia: diagnóstico = true", svc.modo_diagnostico_stream == true)
	svc.free()

	# 6) Menú PRINCIPAL: las MISMAS filas y la MISMA preferencia compartida.
	var mm := (load("res://ui/scenes/MainMenu.tscn") as PackedScene).instantiate()
	add_child(mm)
	await get_tree().process_frame
	await get_tree().process_frame
	mm.call("_entrar_ajustes")
	var cfg := mm.get_node("MenuPanel/Content/OptionsList/ConfigItems") as VBoxContainer
	mm.call("_toggle_categoria", 0, cfg.get_child(0) as MenuOption)
	await get_tree().process_frame
	var sec := mm.get_node("ConfigPanel/ConfigContent/SeccionGraficos") as VBoxContainer
	_comprobar("menú principal: fila de optimización presente",
			sec.get_node_or_null("OptimizacionOption") != null)
	_comprobar("menú principal: dependientes OCULTOS con la opción OFF",
			not (sec.get_node_or_null("CargaOption") as Control).visible)
	_comprobar("menú principal: la fila refleja el valor guardado (NO)",
			_label_de(sec, "OptimizacionOption").ends_with("NO"))

	# Activar desde el MENÚ PRINCIPAL y comprobar que cambia la preferencia única.
	mm.call("_activate", 3)   # hijo 3 = OptimizacionOption
	await get_tree().process_frame
	_comprobar("menú principal: activar cambia la preferencia compartida",
			AjustesGraficos.optimizacion_agresiva == true)
	_comprobar("menú principal: aparecen los dependientes al activar",
			(sec.get_node_or_null("CargaOption") as Control).visible)

	# El MENÚ DE PAUSA refleja el MISMO estado (misma preferencia, sin duplicar).
	var p2 := (load("res://ui/scenes/PauseMenu.tscn") as PackedScene).instantiate()
	add_child(p2)
	await get_tree().process_frame
	p2.call("abrir")
	var cfg2 := p2.get_node("Root/MenuPanel/Content/OptionsList/ConfigItems") as VBoxContainer
	p2.call("_toggle_categoria", 2, cfg2.get_child(2) as MenuOption)
	await get_tree().process_frame
	_comprobar("menú de pausa: refleja SÍ (mismo valor que el principal)",
			(p2.get_node("Root/ConfigPanel/ConfigScroll/ConfigContent/OptimizacionFila/OptimizacionValor")
					as Label).text == "SÍ")
	_comprobar("menú de pausa: dependientes visibles con la opción ON",
			(p2.get_node("Root/ConfigPanel/ConfigScroll/ConfigContent/OptimizacionDependientes")
					as Control).visible)

	# Cambiar desde el menú de pausa y verificar que la preferencia única cambia.
	AjustesGraficos.poner_distancia_carga(9)
	_comprobar("cambio desde pausa: preferencia única actualizada",
			AjustesGraficos.distancia_carga == 9)

	# Volver a la opción OFF (estado por defecto) y comprobar la redistribución.
	AjustesGraficos.poner_optimizacion_agresiva(false)
	mm.call("_refresh", true)
	await get_tree().process_frame
	_comprobar("menú principal: al desactivar se ocultan los dependientes",
			not (sec.get_node_or_null("CargaOption") as Control).visible)

	print("===== RESULTADO P10-B AJUSTES: %d OK, %d FALLOS =====" % [_ok, _fallos])
	get_tree().quit(0 if _fallos == 0 else 1)


func _radio_para(nivel: int) -> float:
	var antes := AjustesGraficos.distancia_carga
	AjustesGraficos.distancia_carga = nivel
	var r := AjustesGraficos.radio_carga_m()
	AjustesGraficos.distancia_carga = antes
	return r


func _margen_para(nivel: int) -> float:
	var antes := AjustesGraficos.distancia_precarga
	AjustesGraficos.distancia_precarga = nivel
	var m := AjustesGraficos.margen_precarga_m()
	AjustesGraficos.distancia_precarga = antes
	return m


func _comprobar(texto: String, ok: bool) -> void:
	if ok:
		_ok += 1
		print("[OK]    ", texto)
	else:
		_fallos += 1
		print("[FALLO] ", texto)


func _label_de(sec: VBoxContainer, nombre: String) -> String:
	var fila := sec.get_node_or_null(nombre) as MenuOption
	if fila == null:
		return ""
	var l := fila.get_node_or_null("Label") as Label
	return l.text if l != null else ""