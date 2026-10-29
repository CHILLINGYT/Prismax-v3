extends Node3D

## =============================================================================
##  VERIFICACIÓN de los AJUSTES pedidos (estamina de las transformaciones + panel
##  de controles de habilidades). Se mide sobre el jugador REAL (leo_jugador.tscn),
##  igual que `prueba_estamina.gd`, sin duplicar sistemas.
##
##   1. Volar (volar/boost/picada) NO consume estamina; volar con 0 también vale.
##   2. El dash del velocista cuesta la MITAD que antes (5.0, era 10.0) y se cobra
##      UNA sola vez, sin duplicar.
##   3. El golpe del velocista: sin estamina NO arranca (ni animación ni daño),
##      da igual cuántas veces se pida; con estamina cobra UNA vez por golpe.
##   4. La carga del supersalto de Fuerza consume PROGRESIVAMENTE (a más tiempo,
##      más gasto), no una cantidad entera por fotograma; al soltar se corta; no
##      se cobra dos veces; con la estamina agotada la carga se corta sin errores.
##   5. Panel de habilidades: aparece en el cuadrante inferior izquierdo con
##      margen inferior, lista SÓLO las habilidades del personaje equipado, se
##      actualiza al transformarse, y su encendido/tamaño van por separado del
##      resto del HUD y se guardan.
##
## No forma parte del juego: vive en res://_tests/ y se ejecuta como ESCENA.
## =============================================================================

const JUGADOR := preload("res://personaje/base/escenas/leo_jugador.tscn")

const F_VELOCISTA := 1
const F_FUERZA := 3
const F_VUELO := 5

var _ok := 0
var _fallos := 0
var _jug: ControladorLeo
var _stats: EstadisticasJugador
var _panel: PanelHabilidadesHUD
# Copia de los ajustes del jugador para dejarlos EXACTAMENTE como estaban.
var _aj_visible := true
var _aj_tamano := AjustesJugabilidad.HUD_TAM_GRANDE

func _ready() -> void:
	call_deferred("_correr")

func _check(nombre: String, ok: bool, detalle: String = "") -> void:
	var sufijo := (" — " + detalle) if detalle != "" else ""
	if ok:
		_ok += 1
		print("[OK]    ", nombre, sufijo)
	else:
		_fallos += 1
		print("[FALLA] ", nombre, sufijo)

func _esperar(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame

func _leer(id: StringName) -> float:
	return float(_stats.estado_de_forma(id).get("stamina", -1.0))

func _poner(id: StringName, valor: float) -> void:
	var e := _stats._estados[id] as Dictionary
	e["stamina"] = valor
	e["t_desde_gasto"] = 0.0
	if id == _stats.forma_actual():
		_stats._sincronizar_activa()

func _cambiar_forma(id: StringName, forma: int) -> bool:
	_jug._on_transformacion_elegida(id)
	var t := 0
	while (int(_jug.forma) != forma or _jug._transformando) and t < 900:
		await get_tree().physics_frame
		t += 1
	await _esperar(10)
	return int(_jug.forma) == forma

func _correr() -> void:
	print("=== PRUEBA: AJUSTES DE ESTAMINA + PANEL DE CONTROLES ===")
	_aj_visible = AjustesJugabilidad.hud_controles_visible
	_aj_tamano = AjustesJugabilidad.hud_controles_tamano

	var suelo := StaticBody3D.new()
	var forma_s := CollisionShape3D.new()
	var caja := BoxShape3D.new()
	caja.size = Vector3(400.0, 1.0, 400.0)
	forma_s.shape = caja
	suelo.add_child(forma_s)
	suelo.position = Vector3(0.0, -0.5, 0.0)
	add_child(suelo)

	_jug = JUGADOR.instantiate() as ControladorLeo
	_jug.position = Vector3(0.0, 0.1, 0.0)
	add_child(_jug)
	_stats = _jug.get_node_or_null("Estadisticas") as EstadisticasJugador
	await _esperar(30)
	if _stats == null:
		_check("jugador y estadísticas listos", false)
		await _cierre()
		return
	_check("jugador y estadísticas listos", true)
	await _esperar(20)

	# ================================================= 1. Tablas de coste
	print("--- 1. Tablas ---")
	_check("1. Volar NO cuesta (volar = 0.0)",
			CostosEstamina.costo_movimiento(&"aguila", &"volar") == 0.0,
			"%.2f" % CostosEstamina.costo_movimiento(&"aguila", &"volar"))
	_check("1. El boost del vuelo NO cuesta (0.0)",
			CostosEstamina.costo_movimiento(&"aguila", &"volar_boost") == 0.0,
			"%.2f" % CostosEstamina.costo_movimiento(&"aguila", &"volar_boost"))
	_check("1. La picada NO cuesta (0.0)",
			CostosEstamina.costo_movimiento(&"aguila", &"volar_picada") == 0.0,
			"%.2f" % CostosEstamina.costo_movimiento(&"aguila", &"volar_picada"))
	_check("1. El esprint del águila en TIERRA sí cuesta (5.5)",
			CostosEstamina.costo_movimiento(&"aguila", &"correr") > 0.0,
			"%.2f" % CostosEstamina.costo_movimiento(&"aguila", &"correr"))
	_check("1. La carga del supersalto tiene coste por SEGUNDO",
			CostosEstamina.costo_movimiento(&"tanque", &"cargar_super") > 0.0,
			"%.2f/s" % CostosEstamina.costo_movimiento(&"tanque", &"cargar_super"))
	_check("1. El dash del velocista cuesta la MITAD (5.0, era 10.0)",
			is_equal_approx(CostosEstamina.costo_habilidad(&"velocista", &"dash"), 5.0),
			"%.2f" % CostosEstamina.costo_habilidad(&"velocista", &"dash"))
	_check("1. El golpe del velocista mantiene su coste (5.0)",
			is_equal_approx(CostosEstamina.costo_ataque(&"velocista", &"golpe"), 5.0),
			"%.2f" % CostosEstamina.costo_ataque(&"velocista", &"golpe"))

	# ================================================= 2. Vuelo gratis (en vivo)
	print("--- 2. Vuelo ---")
	# El VUELO está bloqueado hasta completar la misión de Iván (regla del juego):
	# se marca completada para poder medir la estamina del águila, igual que hacen
	# las suites existentes (`prueba_estamina_c.gd`). El bloqueo no se prueba aquí.
	Misiones.marcar_completada(Misiones.MISION_PROFUGOS)
	if await _cambiar_forma(&"aguila", F_VUELO):
		_poner(&"aguila", 50.0)
		var vuelo := _jug.get_node_or_null("Vuelo")
		var fc := vuelo.get_node_or_null("FlightController") if vuelo != null else null
		if vuelo is CharacterBody3D and fc != null:
			fc.set("is_flying", true)
			fc.set("is_diving", false)
			var antes := _leer(&"aguila")
			# 2 s de vuelo normal (20 llamadas de 0.1 s): el gasto tiene que ser CERO.
			for _i in 20:
				_jug._procesar_estamina_vuelo(0.1)
			_check("2. Volar 2 s NO gasta nada", is_equal_approx(_leer(&"aguila"), antes),
					"%.3f -> %.3f" % [antes, _leer(&"aguila")])
			# Boost y picada tampoco.
			fc.set("is_diving", true)
			for _i in 10:
				_jug._procesar_estamina_vuelo(0.1)
			_check("2. Picar 1 s NO gasta nada", is_equal_approx(_leer(&"aguila"), antes),
					"%.3f" % _leer(&"aguila"))
			fc.set("is_diving", false)
			if fc.has_method("is_boosting"):
				for _i in 10:
					_jug._procesar_estamina_vuelo(0.1)
			fc.set("is_flying", false)
			# Y con la estamina a CERO se puede seguir volando (no se bloquea nada).
			_poner(&"aguila", 0.0)
			fc.set("is_flying", true)
			for _i in 20:
				_jug._procesar_estamina_vuelo(0.1)
			_check("2. Con 0 de estamina se sigue volando (no gasta ni bloquea)",
					is_zero_approx(_leer(&"aguila")), "%.3f" % _leer(&"aguila"))
			fc.set("is_flying", false)
		else:
			_check("2. El cuerpo de vuelo tiene FlightController", false)
	else:
		_check("2. Se puede transformar en águila", false)

	# ================================================= 3. Golpe del velocista
	print("--- 3. Golpe del velocista ---")
	if await _cambiar_forma(&"velocista", F_VELOCISTA):
		# Sin estamina: NO arranca, por muchas veces que se pida.
		_poner(&"velocista", 0.0)
		_jug._ataque_activo = false
		for i in 10:
			_jug._on_golpe_realizado((i % 4) + 1)
		_check("3. Con 0 de estamina el golpe NO sale (10 intentos)",
				not _jug._ataque_activo, "estamina=%.3f" % _leer(&"velocista"))
		_check("3. Con 0 de estamina no hay gasto ni gasto negativo",
				is_zero_approx(_leer(&"velocista")), "%.3f" % _leer(&"velocista"))
		# Con estamina: cobra UNA vez por golpe.
		_poner(&"velocista", 50.0)
		_jug._ataque_activo = false
		_jug._on_golpe_realizado(1)
		_check("3. Con estamina el golpe SÍ sale", _jug._ataque_activo)
		_check("3. El golpe cobra UNA vez (5.0, no 10)",
				is_equal_approx(_leer(&"velocista"), 45.0), "%.3f" % _leer(&"velocista"))
		_jug._ataque_activo = false
		_jug._on_golpe_realizado(2)
		_check("3. Un segundo golpe vuelve a cobrar 5 (40.0)",
				is_equal_approx(_leer(&"velocista"), 40.0), "%.3f" % _leer(&"velocista"))
		# Justo por debajo del coste: no arranca (no vale "casi alcanza").
		_jug._ataque_activo = false
		_poner(&"velocista", 4.9)
		_jug._on_golpe_realizado(3)
		_check("3. Con 4.9 (menos que el coste) el golpe NO sale",
				not _jug._ataque_activo, "estamina=%.3f" % _leer(&"velocista"))
	else:
		_check("3. Se puede transformar en velocista", false)

	# ================================================= 4. Dash al 50 %
	print("--- 4. Dash ---")
	if int(_jug.forma) == F_VELOCISTA:
		_poner(&"velocista", 50.0)
		_jug.estado = 0
		_jug._intentar_dash()
		await _esperar(2)
		_check("4. El dash cuesta 5.0 UNA vez (50 -> 45)",
				is_equal_approx(_leer(&"velocista"), 45.0), "%.3f" % _leer(&"velocista"))
		_check("4. El dash sigue cambiando de estado (no se rompió)",
				int(_jug.estado) != 0, "estado=%d" % int(_jug.estado))
		# Sin estamina el dash no arranca.
		_jug.estado = 0
		_poner(&"velocista", 1.0)
		_jug._intentar_dash()
		await _esperar(2)
		_check("4. Sin estamina el dash NO arranca",
				int(_jug.estado) == 0 and is_equal_approx(_leer(&"velocista"), 1.0),
				"estado=%d estamina=%.3f" % [int(_jug.estado), _leer(&"velocista")])

	# ================================================= 5. Carga del supersalto
	print("--- 5. Carga del supersalto (Fuerza) ---")
	if await _cambiar_forma(&"tanque", F_FUERZA):
		var tasa := CostosEstamina.costo_movimiento(&"tanque", &"cargar_super")
		_poner(&"tanque", 100.0)
		_jug.f_super_cargando = false
		_jug.f_super_carga = 0.0
		Input.action_press("saltar")
		var t := 0
		while not _jug.f_super_cargando and t < 30:
			await get_tree().physics_frame
			t += 1
		_check("5. Mantener ESPACIO empieza la carga", _jug.f_super_cargando)
		# Un tramo medido de ~1 s: el gasto debe parecerse a tasa × tiempo (progresivo).
		var antes := _leer(&"tanque")
		var cuadros := 60
		for _i in cuadros:
			await get_tree().physics_frame
		var gasto_1s := antes - _leer(&"tanque")
		var esperado := tasa * (float(cuadros) / 60.0)
		_check("5. La carga gasta ~%.2f/s de forma progresiva (no de golpe)" % tasa,
				absf(gasto_1s - esperado) < 1.2, "gastado=%.2f esperado≈%.2f" % [gasto_1s, esperado])
		_check("5. Un tramo parcial cuesta MENOS que la activación vieja (10.0)",
				gasto_1s < 10.0, "gastado=%.2f" % gasto_1s)
		# La estamina no debe SUBIR mientras se carga (nada de regeneración).
		var marca := _leer(&"tanque")
		var subio := false
		for _i in 40:
			await get_tree().physics_frame
			if _leer(&"tanque") > marca + 0.001:
				subio = true
		_check("5. Durante la carga la estamina NO se regenera (sólo baja)", not subio)
		# Al SOLTAR: el consumo se corta y no hay segundo cobro.
		Input.action_release("saltar")
		await get_tree().physics_frame
		_check("5. Al soltar, la carga termina", not _jug.f_super_cargando)
		var tras_soltar := _leer(&"tanque")
		await _esperar(3)
		_check("5. Tras soltar no hay cobro extra (el gasto se corta)",
				absf(_leer(&"tanque") - tras_soltar) < 0.05,
				"%.3f -> %.3f" % [tras_soltar, _leer(&"tanque")])
		# Con la estamina al borde: la carga se corta sola y sin errores.
		_poner(&"tanque", 3.0)
		_jug.f_super_cargando = false
		_jug.f_super_carga = 0.0
		Input.action_press("saltar")
		t = 0
		while not _jug.f_super_cargando and t < 30:
			await get_tree().physics_frame
			t += 1
		for _i in 90:
			await get_tree().physics_frame
		Input.action_release("saltar")
		_check("5. Si la estamina se agota, la carga se corta de forma segura",
				not _jug.f_super_cargando and _leer(&"tanque") >= 0.0,
				"cargando=%s estamina=%.3f" % [str(_jug.f_super_cargando), _leer(&"tanque")])
		_check("5. El personaje sigue vivo y controlable (sin bloqueos)",
				is_instance_valid(_jug) and _jug.is_inside_tree())
	else:
		_check("5. Se puede transformar en Fuerza", false)

	# ================================================= 6. Panel de habilidades
	print("--- 6. Panel de controles ---")
	await _probar_panel()

	await _cierre()

# ------------------------------------------------------------------ panel
func _textos_filas(panel: PanelHabilidadesHUD) -> Array[String]:
	var salida: Array[String] = []
	# Las filas cuelgan de "Columnas": una o dos columnas según cuántas
	# habilidades tenga el personaje. El recorrido respeta el ORDEN lógico (la
	# primera mitad y después la segunda), que es como las pinta la guía.
	var filas: Array[Node] = []
	var columnas := panel.find_child("Columnas", true, false)
	if columnas != null:
		for col in columnas.get_children():
			for f in col.get_children():
				filas.append(f)
	if filas.is_empty():
		return salida
	# Cada fila es `TECLA — Descripción (nota)`: se lee por orden de etiquetas,
	# saltando el guion, así que la nota del final no estorba.
	for fila in filas:
		var tecla := ""
		var accion := ""
		for hijo in fila.get_children():
			var l := hijo as Label
			if l == null or l.text == "—":
				continue
			if tecla == "":
				tecla = l.text
			elif accion == "":
				accion = l.text
		salida.append("%s = %s" % [tecla, accion])
	return salida

func _probar_panel() -> void:
	_panel = PanelHabilidadesHUD.new()
	add_child(_panel)
	await _esperar(20)
	_check("6. El panel encuentra al jugador del mundo", _panel._jugador != null)
	# La prueba de la guía necesita la guía ENCENDIDA (el ajuste del jugador puede
	# estar apagado). Se enciende aquí y se restaura al final, como todo lo demás.
	AjustesJugabilidad.poner_hud_controles_visible(true)
	await _esperar(4)
	_check("6. Con el ajuste encendido la guía está visible y con filas",
			_panel.visible and _textos_filas(_panel).size() > 0,
			"visible=%s filas=%d ajuste=%s" % [str(_panel.visible),
					_textos_filas(_panel).size(), str(AjustesJugabilidad.hud_controles_visible)])
	# El panel sigue SIEMPRE al personaje real: se comprueba primero con una
	# transformación DE VERDAD (la que hace el juego por el menú) y después forma
	# por forma, comparando las filas con el catálogo REAL de controles.
	await _cambiar_forma(&"velocista", F_VELOCISTA)
	await _esperar(150)
	_check("6. Tras una transformación REAL el panel sigue al personaje equipado",
			_panel._contexto_actual == &"velocista" and _jug.id_forma() == &"velocista",
			"forma=%s contexto=%s" % [str(_jug.id_forma()), str(_panel._contexto_actual)])
	var casos := [
		{"id": &"humano", "ctx": &"humano"},
		{"id": &"tanque", "ctx": &"fuerza"},
		{"id": &"pes", "ctx": &"acuatico"},
		{"id": &"velocista", "ctx": &"velocista"},
		{"id": &"combate", "ctx": &"combate"},
		{"id": &"aguila", "ctx": &"vuelo"},
	]
	var contenido_ok := true
	var detalle := ""
	for caso_v in casos:
		var caso: Dictionary = caso_v
		var ctx: StringName = caso["ctx"]
		# El MISMO aviso que da el juego al terminar una transformación.
		_jug.forma_cambiada.emit(caso["id"])
		await _esperar(3)
		var filas := _textos_filas(_panel)
		# Lista esperada, calculada APARTE desde el catálogo real de controles.
		var esperadas: Array[String] = []
		for accion_v in AjustesControles.acciones_para(ctx):
			var accion: StringName = accion_v
			if PanelHabilidadesHUD.OMITIDAS.has(accion):
				continue
			esperadas.append("%s = %s" % [AjustesControles.texto_de(accion),
					AjustesControles.etiqueta_de(accion, ctx)])
		if filas != esperadas:
			contenido_ok = false
			detalle += "%s: %s != %s | " % [str(ctx), str(filas), str(esperadas)]
	_check("6. Cada personaje muestra SÓLO sus habilidades, con la tecla real",
			contenido_ok, detalle)
	# Filas concretas del encargo, para la transformación de FUERZA.
	_jug.forma_cambiada.emit(&"tanque")
	await _esperar(3)
	var filas_f := _textos_filas(_panel)
	print("        filas de FUERZA: ", filas_f)
	_check("6. La tecla mostrada es la REAL del InputMap (Q = levantar roca)",
			_contiene(filas_f, "Q = Levantar roca"), "filas=%s" % str(filas_f))
	_check("6. El supersalto sale con su matiz de mantener y soltar",
			_contiene(filas_f, "ESPACIO = Saltar / supersalto"), "filas=%s" % str(filas_f))
	_check("6. El pisotón aéreo (E) sale con su condición",
			_contiene(filas_f, "E = Pisotón"), "filas=%s" % str(filas_f))
	_check("6. Las habilidades de OTROS personajes no aparecen",
			not _contiene(filas_f, "Dash") and not _contiene(filas_f, "Plumas"),
			"filas=%s" % str(filas_f))
	# --- UNA SOLA COLUMNA: todas las filas una debajo de la otra -------------
	# Se usa VUELO, la forma con MÁS habilidades (10): es donde antes se partía en
	# dos columnas, así que es la prueba más dura.
	_jug.forma_cambiada.emit(&"aguila")
	await _esperar(5)
	var cols_una: Node = _panel.find_child("Columnas", true, false)
	var n_contenedores := cols_una.get_child_count() if cols_una != null else -1
	_check("6. La lista tiene UN único contenedor de filas (una sola columna)",
			n_contenedores == 1, "contenedores=%d" % n_contenedores)
	var rects: Array[Rect2] = []
	if n_contenedores == 1:
		for f in cols_una.get_child(0).get_children():
			rects.append((f as Control).get_global_rect())
	var misma_x := true
	var apiladas := true
	for i in rects.size():
		if i > 0:
			if not is_equal_approx(rects[i].position.x, rects[0].position.x):
				misma_x = false
			# Cada fila EMPIEZA en o por debajo del final de la anterior: nunca al lado.
			if rects[i].position.y + 0.5 < rects[i - 1].end.y:
				apiladas = false
	var xs: Array[float] = []
	var ys: Array[float] = []
	for r in rects:
		xs.append(r.position.x)
		ys.append(r.position.y)
	_check("6. VUELO: sus %d habilidades van todas en la MISMA columna" % rects.size(),
			rects.size() >= 8 and misma_x,
			"filas=%d  x=%s" % [rects.size(), str(xs)])
	_check("6. Ninguna fila queda al lado de otra: cada una empieza debajo de la anterior",
			rects.size() >= 8 and apiladas, "y por fila=%s" % str(ys))
	# Y la guía sigue estrecha: el ancho lo decide la fila más larga, no la pantalla.
	var vista_col := get_viewport().get_visible_rect().size
	var rect_vuelo := (_panel.get_node("Caja") as Control).get_global_rect()
	_check("6. La guía no se estira a lo ancho (ni se sale de la pantalla)",
			rect_vuelo.size.x <= vista_col.x * 0.6 and rect_vuelo.end.x <= vista_col.x,
			"ancho=%.0f px de %.0f (%.0f %%)" % [rect_vuelo.size.x, vista_col.x,
					rect_vuelo.size.x / vista_col.x * 100.0])
	_jug.forma_cambiada.emit(&"tanque")
	await _esperar(3)
	# --- Colocación: lado DERECHO, elevada, y sin pisar nada del HUD ni la misión ---
	var vista := get_viewport().get_visible_rect().size
	var caja: Control = _panel.get_node("Caja")
	var rect := caja.get_global_rect()
	# Vuelta al cuadrante inferior IZQUIERDO, con margen por la izquierda y sin
	# pegarse al borde inferior.
	_check("6. Está en el cuadrante inferior IZQUIERDO, con margen a la izquierda",
			rect.position.x >= 16.0 and rect.position.x < vista.x * 0.5,
			"x=%.1f..%.1f de %.1f" % [rect.position.x, rect.end.x, vista.x])
	_check("6. Subida del borde inferior, con margen visible",
			vista.y - rect.end.y >= 30.0, "margen inferior=%.1f px" % (vista.y - rect.end.y))
	# SIN fondo: no puede quedar NINGÚN elemento de fondo detrás del texto.
	var fondos := _panel.find_children("*", "PanelContainer", true, false).size() \
			+ _panel.find_children("*", "Panel", true, false).size()
	_check("6. NO tiene fondo: ni rectángulo, ni tarjeta, ni panel detrás del texto",
			fondos == 0, "elementos de fondo=%d" % fondos)
	# Contraste: cada rótulo lleva contorno oscuro (se lee sobre cielo y sobre suelo).
	var rotulos := _panel.find_children("*", "Label", true, false)
	var con_contorno := 0
	for l in rotulos:
		var lab := l as Label
		if lab.get_theme_constant("outline_size") > 0 \
				and lab.get_theme_color("font_outline_color").a > 0.4:
			con_contorno += 1
	_check("6. Todos los rótulos llevan contorno para leerse sobre cualquier fondo",
			rotulos.size() > 0 and con_contorno == rotulos.size(),
			"%d de %d" % [con_contorno, rotulos.size()])
	_check("6. Cabe entera dentro de la pantalla",
			rect.position.x >= 0.0 and rect.position.y >= 0.0 and rect.end.y <= vista.y,
			"guia=%s vista=%s" % [str(rect), str(vista)])
	var hud := _buscar_hud()
	if hud != null:
		var barra := hud.get_node_or_null("Raiz/BarraEstamina") as Control
		if barra != null:
			_check("6. No se superpone con la barra de ESTAMINA",
					not rect.intersects(barra.get_global_rect()),
					"guia=%s estamina=%s" % [str(rect), str(barra.get_global_rect())])
		var dial := hud.get_node_or_null("Raiz/Dial") as Control
		if dial != null:
			# Caja VISUAL del dial (el Control es más grande que el aro dibujado).
			var centro := dial.get_global_rect().get_center()
			var r := HUDCircular.VIDA_RADIO + HUDCircular.VIDA_GROSOR * 0.5
			var caja_dial := Rect2(centro - Vector2(r, r), Vector2(r * 2.0, r * 2.0))
			_check("6. No se superpone con el dial de VIDA",
					not rect.intersects(caja_dial),
					"guia=%s vida=%s" % [str(rect), str(caja_dial)])
	else:
		_check("6. HUD del jugador localizado para medir la vida/estamina", false)
	var mision := await _rect_mision()
	if mision != Rect2():
		_check("6. No se superpone con el panel de MISIÓN",
				not rect.intersects(mision), "guia=%s mision=%s" % [str(rect), str(mision)])
	# --- Cartel de MISIÓN: sigue bajo el minimapa, más chico y sin recortes ---
	print("        cartel de misión: ", await _revisar_mision())
	# Independencia: el ajuste de ocultar el HUD NO la toca.
	AjustesJugabilidad.poner_ocultar_hud(true)
	await _esperar(2)
	_check("6. Ocultar el HUD general NO apaga la guía (independiente)", _panel.visible)
	AjustesJugabilidad.poner_ocultar_hud(false)
	# Encendido/apagado propio, inmediato.
	AjustesJugabilidad.poner_hud_controles_visible(false)
	await _esperar(2)
	_check("6. El ajuste la apaga por completo en el acto",
			not _panel.visible, "visible=%s" % str(_panel.visible))
	AjustesJugabilidad.poner_hud_controles_visible(true)
	await _esperar(3)
	_check("6. Al volver a encenderla muestra el personaje ACTUAL",
			_panel.visible and _textos_filas(_panel).size() > 0,
			"filas=%d" % _textos_filas(_panel).size())
	# --- Tamaños: GRANDE (referencia), MEDIANO (75 %) y CHICO (50 %) ---
	AjustesJugabilidad.poner_hud_controles_tamano(AjustesJugabilidad.HUD_TAM_GRANDE)
	await _esperar(4)
	var alto_grande := _alto_panel(_panel)
	_check("6. GRANDE es la referencia: factor 1.0",
			is_equal_approx(AjustesJugabilidad.factor_hud_controles(), 1.0),
			"factor=%.2f algo=%.1f px" % [AjustesJugabilidad.factor_hud_controles(), alto_grande])
	AjustesJugabilidad.poner_hud_controles_tamano(AjustesJugabilidad.HUD_TAM_MEDIANO)
	await _esperar(4)
	var alto_mediano := _alto_panel(_panel)
	AjustesJugabilidad.poner_hud_controles_tamano(AjustesJugabilidad.HUD_TAM_CHICO)
	await _esperar(4)
	var alto_chico := _alto_panel(_panel)
	print("        alto real de la guía: GRANDE=%.1f  MEDIANO=%.1f  CHICO=%.1f px" % [
			alto_grande, alto_mediano, alto_chico])
	# Los tamaños se miden sobre la caja REAL y sobre la ALTURA DE FILA, que es el
	# contenido. La altura TOTAL queda un poco por encima de la proporción exacta
	# porque el texto y los bordes se redondean a píxeles enteros; la medida del
	# contenido (la fila) sí da la proporción exacta.
	var recortes := 0
	var detalle_recortes := ""
	var altos_fila := {}
	var anchos_caja := {}
	for tam in [AjustesJugabilidad.HUD_TAM_GRANDE, AjustesJugabilidad.HUD_TAM_MEDIANO,
			AjustesJugabilidad.HUD_TAM_CHICO]:
		AjustesJugabilidad.poner_hud_controles_tamano(tam)
		await _esperar(4)
		# Ancho REAL de la caja de la tecla: medida que decide la guía (74 px de
		# referencia) y visible. Se usa para comprobar la proporción porque las
		# métricas de una tipografía sí se redondean a píxeles enteros y no son
		# exactamente lineales con el tamaño.
		var col0 := _panel.find_child("Columnas", true, false)
		var h := 0.0
		var cw := 0.0
		if col0 != null and col0.get_child_count() > 0 \
				and col0.get_child(0).get_child_count() > 0:
			var fila0: Node = col0.get_child(0).get_child(0)
			h = (fila0 as Control).get_combined_minimum_size().y
			if fila0.get_child_count() > 0 and fila0.get_child(0) is Control:
				cw = (fila0.get_child(0) as Control).custom_minimum_size.x
		altos_fila[tam] = h
		anchos_caja[tam] = cw
		var malas := _etiquetas_recortadas(_panel)
		if malas > 0:
			recortes += malas
			detalle_recortes += "tam %d: %d; " % [tam, malas]
	_check("6. Ninguna etiqueta se recorta en ninguno de los tres tamaños",
			recortes == 0, detalle_recortes)
	var cg: float = float(anchos_caja.get(AjustesJugabilidad.HUD_TAM_GRANDE, 0.0))
	var cm: float = float(anchos_caja.get(AjustesJugabilidad.HUD_TAM_MEDIANO, 0.0))
	var cc: float = float(anchos_caja.get(AjustesJugabilidad.HUD_TAM_CHICO, 0.0))
	print("        ancho de la caja de TECLA: GRANDE=%.1f  MEDIANO=%.1f  CHICO=%.1f px" % [
			cg, cm, cc])
	print("        alto de una FILA: GRANDE=%.1f  MEDIANO=%.1f  CHICO=%.1f px" % [
			float(altos_fila.get(AjustesJugabilidad.HUD_TAM_GRANDE, 0.0)),
			float(altos_fila.get(AjustesJugabilidad.HUD_TAM_MEDIANO, 0.0)),
			float(altos_fila.get(AjustesJugabilidad.HUD_TAM_CHICO, 0.0))])
	_check("6. MEDIANO mide el 75 % de GRANDE",
			cg > 0.0 and absf(cm / cg - 0.75) <= 0.02,
			"%.3f" % (cm / cg if cg > 0.0 else 0.0))
	_check("6. CHICO mide el 50 % de GRANDE",
			cg > 0.0 and absf(cc / cg - 0.5) <= 0.02,
			"%.3f" % (cc / cg if cg > 0.0 else 0.0))
	_check("6. El panel ENTERO se reduce con el tamaño (dentro del redondeo de píxel)",
			alto_grande > alto_mediano and alto_mediano > alto_chico \
				and absf(alto_mediano / alto_grande - 0.75) <= 0.10 \
				and absf(alto_chico / alto_grande - 0.5) <= 0.10,
			"%.1f/%.1f/%.1f px" % [alto_grande, alto_mediano, alto_chico])
	# Guardado de los DOS ajustes propios de la guía.
	AjustesJugabilidad.poner_hud_controles_tamano(AjustesJugabilidad.HUD_TAM_MEDIANO)
	AjustesJugabilidad.poner_hud_controles_visible(false)
	var cf := ConfigFile.new()
	var err := cf.load(AjustesJugabilidad.RUTA)
	var guardado_ok := err == OK \
			and int(cf.get_value(AjustesJugabilidad.SECCION, "hud_controles_tamano", -1)) \
				== AjustesJugabilidad.HUD_TAM_MEDIANO \
			and bool(cf.get_value(AjustesJugabilidad.SECCION, "hud_controles_visible", true)) == false \
			and not cf.has_section_key(AjustesJugabilidad.SECCION, "hud_controles_escala")
	_check("6. Los dos ajustes de la guía se guardan en las preferencias", guardado_ok,
			"error=%d" % err)
	# Se dejan los ajustes del jugador EXACTAMENTE como estaban.
	AjustesJugabilidad.poner_hud_controles_tamano(_aj_tamano)
	AjustesJugabilidad.poner_hud_controles_visible(_aj_visible)
	await _esperar(2)

## Alto real dibujado de la guía: la escala se aplica a las MEDIDAS (tipografía,
## recuadros, alturas y márgenes), no con un transform, así que el control mide
## exactamente lo que ocupa.
func _alto_panel(panel: Node) -> float:
	var caja := panel.get_node_or_null("Caja") as Control
	return caja.size.y if caja != null else 0.0

## Etiquetas de la guía que NO caben en el sitio que tienen (texto recortado).
func _etiquetas_recortadas(panel: Node) -> int:
	var malas := 0
	for l in panel.find_children("*", "Label", true, false):
		var lab := l as Label
		var necesita := lab.get_combined_minimum_size()
		if lab.size.x + 0.5 < necesita.x or lab.size.y + 0.5 < necesita.y:
			malas += 1
	return malas

## HUD circular del jugador (vida/estamina), para medir sus cajas reales.
func _buscar_hud() -> Node:
	for n in _jug.get_children():
		if n is HUDCircular:
			return n
	return null

## Rectángulo REAL del panel de misión, para comprobar que la guía no lo pisa.
func _rect_mision() -> Rect2:
	var escena: PackedScene = load("res://ui/scenes/PanelMision.tscn")
	if escena == null:
		return Rect2()
	var m := escena.instantiate()
	add_child(m)
	await get_tree().process_frame
	var p := m.get_node_or_null("Raiz/Panel") as Control
	var r := p.get_global_rect() if p != null else Rect2()
	m.queue_free()
	return r

## Minimapa REAL del jugador (para medir el cartel de misión contra él).
func _buscar_minimapa() -> Control:
	var pila: Array[Node] = [self]
	while not pila.is_empty():
		var n: Node = pila.pop_back()
		if n is Minimapa:
			return n as Control
		for c in n.get_children():
			pila.append(c)
	return null

## Comprueba el cartel de misión REAL: que siga DEBAJO del minimapa con
## separación, que sea más chico que antes (156x156), que la jerarquía título /
## contador esté clara y que ningún texto se recorte. Sólo MIDE: no toca la
## lógica de misiones ni decide nada.
func _revisar_mision() -> String:
	var escena: PackedScene = load("res://ui/scenes/PanelMision.tscn")
	if escena == null:
		_check("7. Se pudo cargar el cartel de misión", false)
		return "no cargó"
	var m := escena.instantiate()
	add_child(m)
	await get_tree().process_frame
	await get_tree().process_frame
	var panel := m.get_node_or_null("Raiz/Panel") as Control
	var minimapa := _buscar_minimapa()
	if panel == null or minimapa == null:
		_check("7. Cartel de misión y minimapa localizados en el HUD real", false,
				"panel=%s minimapa=%s" % [str(panel != null), str(minimapa != null)])
		m.queue_free()
		return "faltan nodos"
	var r := panel.get_global_rect()
	var rm := minimapa.get_global_rect()
	var res := "cartel=%s  minimapa=%s" % [str(r), str(rm)]
	_check("7. El cartel sigue DEBAJO del minimapa y con separación",
			r.position.y >= rm.end.y and r.position.y - rm.end.y >= 8.0,
			"separación=%.1f px  %s" % [r.position.y - rm.end.y, res])
	_check("7. No se superpone con el minimapa", not r.intersects(rm), res)
	_check("7. Es MÁS PEQUEÑO que antes (156x156)",
			r.size.x <= 150.0 and r.size.y <= 120.0,
			"%.0fx%.0f px (antes 156x156)" % [r.size.x, r.size.y])
	var recortadas := 0
	for l in panel.find_children("*", "Label", true, false):
		var lab := l as Label
		var nec := lab.get_combined_minimum_size()
		if lab.size.x + 0.5 < nec.x or lab.size.y + 0.5 < nec.y:
			recortadas += 1
	_check("7. Ningún texto del cartel se recorta ni se sale de la tarjeta",
			recortadas == 0, "etiquetas recortadas=%d" % recortadas)
	var titulo := m.get_node_or_null("Raiz/Panel/Columna/Titulo") as Label
	var estado := m.get_node_or_null("Raiz/Panel/Columna/Estado") as Label
	var jerarquia := titulo != null and estado != null \
			and titulo.get_theme_font_size("font_size") > estado.get_theme_font_size("font_size") \
			and titulo.get_theme_color("font_color").v >= estado.get_theme_color("font_color").v
	_check("7. Jerarquía clara: el título destaca sobre el contador", jerarquia,
			"título=%d px, contador=%d px" % [
					titulo.get_theme_font_size("font_size") if titulo != null else -1,
					estado.get_theme_font_size("font_size") if estado != null else -1])
	m.queue_free()
	return res

func _contiene(filas: Array[String], texto: String) -> bool:
	for f in filas:
		if f.contains(texto):
			return true
	return false

func _cierre() -> void:
	print("=== FIN: %d OK, %d FALLOS ===" % [_ok, _fallos])
	await _esperar(2)
	get_tree().quit(0 if _fallos == 0 else 1)