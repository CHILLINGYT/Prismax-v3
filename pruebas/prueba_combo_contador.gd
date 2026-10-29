extends Node
## PRUEBA UNITARIA (headless, < 2 s) del contador de combo de JuiceCombate:
## reglas de acumulación/decaimiento con tiempo simulado (sin mundo ni jugador).
##   godot --headless --path . res://pruebas/prueba_combo_contador.tscn

var _ok := 0
var _fallos := 0


func _ready() -> void:
	var j := JuiceCombate.new()
	add_child(j)
	await get_tree().process_frame
	j.set_process(false)   # el tiempo lo simula la prueba
	# Antes: 2,0 s. Ahora 3,0 s tras el último impacto.
	for i in 4:
		j.call("_sumar_combo")
	_avanzar(j, 2.5)
	_check(j.combo_actual_contador() == 4, "a los 2,5 s sin acertar el combo SIGUE (antes se perdía a los 2,0)")
	_avanzar(j, 0.6)
	_check(j.combo_actual_contador() == 0, "a los 3,1 s sin pelear se pierde")
	# Lanzar golpes (aunque fallen) lo sostiene.
	for i in 6:
		j.call("_sumar_combo")
	for k in 5:
		_avanzar(j, 1.2)
		j.call("_sostener_combo")
	_check(j.combo_actual_contador() == 6, "lanzando golpes cada 1,2 s (sin acertar) se mantiene 6 s (%d)" % j.combo_actual_contador())
	# Daño: conserva la mitad, una vez por intercambio.
	j.call("_on_danio_recibido", 5.0)
	_check(j.combo_actual_contador() == 3, "recibir daño conserva la mitad (6 → %d; antes 0)" % j.combo_actual_contador())
	j.call("_on_danio_recibido", 5.0)
	_check(j.combo_actual_contador() == 3, "un segundo golpe enseguida no lo vuelve a reducir (%d)" % j.combo_actual_contador())
	# Con el ajuste viejo (conserva 0) vuelve el comportamiento de antes.
	j.contador_conserva_al_dano = 0.0
	j.set("_inmune_dano_hasta", 0)
	j.call("_on_danio_recibido", 5.0)
	_check(j.combo_actual_contador() == 0, "contador_conserva_al_dano = 0 → se borra como antes")
	# Barra de decaimiento proporcional.
	for i in 3:
		j.call("_sumar_combo")
	_avanzar(j, 1.5)
	var barra := j.get("_barra_contador") as Panel
	_check(barra != null and absf(barra.custom_minimum_size.x - 48.0) < 1.0,
			"la barra marca el tiempo restante (mitad de la ventana → %.0f px de 96)" % (barra.custom_minimum_size.x if barra else -1.0))
	# Tamaño compacto: el número usa el tema (40 px; antes 72).
	var num := j.get("_lbl_numero") as Label
	_check(num != null and num.get_theme_font_size("font_size") == 40, "número a 40 px (antes 72)")
	print("==================== COMBO CONTADOR: %d OK / %d FALLO ====================" % [_ok, _fallos])
	get_tree().quit()


func _avanzar(j: JuiceCombate, segundos: float) -> void:
	var paso := 0.05
	var t := 0.0
	while t < segundos - 0.0001:
		j.call("_actualizar_contador", paso)
		t += paso


func _check(c: bool, t: String) -> void:
	if c:
		_ok += 1
		print("[combo] OK   ", t)
	else:
		_fallos += 1
		print("[combo] FALLO ", t)
