extends Node

## =============================================================================
##  SONDA de la GUÍA DE CONTROLES DE HABILIDADES
## =============================================================================
##  1. CAPTURAS reales: levanta el mundo con el JUGADOR REAL (que trae su HUD de
##     vida/estamina) y la guía, y guarda una imagen por cada tamaño (GRANDE,
##     MEDIANO, CHICO) y otra con la guía apagada. Es la única forma de ver de
##     verdad dónde queda y que no pisa la vida ni la estamina.
##  2. Recorrido del MENÚ Configuración → Jugabilidad con los MISMOS manejadores
##     que usa el juego (no una copia), para comprobar las dos opciones.
##  3. Persistencia REAL en disco: se relee el archivo de preferencias.
##
##  Vive en res://_tests/ y NO forma parte del juego.
## =============================================================================

const JUGADOR := preload("res://personaje/base/escenas/leo_jugador.tscn")
const RUTA_CAPTURAS := "res://_tests/capturas_guia_hud/"
const LOG := "res://_tests/sonda_guia_hud.txt"

var _lineas: Array[String] = []

func _ready() -> void:
	_correr.call_deferred()

func _m(t: String) -> void:
	_lineas.append(t)
	print("[SONDA] ", t)
	var f := FileAccess.open(LOG, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lineas))
		f.close()

func _esperar(n: int) -> void:
	for _i in n:
		await get_tree().process_frame

func _filas(panel: Node) -> int:
	var cols := panel.get_node_or_null("Caja/Marco/Contenido/Columnas")
	if cols == null:
		return 0
	var n := 0
	for col in cols.get_children():
		n += col.get_child_count()
	return n

func _capturar(nombre: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null:
		_m("NO se pudo capturar %s" % nombre)
		return
	var err := img.save_png(RUTA_CAPTURAS + nombre)
	_m("captura %s -> err=%d  %dx%d px" % [nombre, err, img.get_width(), img.get_height()])

func _correr() -> void:
	await _capturas()
	await _menu()
	_m("=== FIN de la sonda ===")
	get_tree().quit(0)

# --------------------------------------------------------------- 1. capturas
func _capturas() -> void:
	AjustesJugabilidad.poner_hud_controles_visible(true)

	# Mundo mínimo (cielo + luz + suelo) para que la captura no salga negra. La
	# ciudad no hace falta: lo que se mira es la INTERFAZ.
	var mundo := Node3D.new()
	mundo.name = "MundoSonda"
	add_child(mundo)
	var luz := DirectionalLight3D.new()
	luz.rotation_degrees = Vector3(-52.0, -38.0, 0.0)
	luz.light_energy = 1.1
	mundo.add_child(luz)
	var entorno := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = Sky.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.6
	entorno.environment = env
	mundo.add_child(entorno)
	var suelo := MeshInstance3D.new()
	var caja := BoxMesh.new()
	caja.size = Vector3(400.0, 1.0, 400.0)
	suelo.mesh = caja
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.42, 0.44, 0.40)
	suelo.material_override = mat
	suelo.position = Vector3(0.0, -0.5, 0.0)
	mundo.add_child(suelo)

	# Jugador REAL (trae su HUD circular de vida/estamina) y la guía encima.
	var jug: Node = JUGADOR.instantiate()
	mundo.add_child(jug)
	var panel := PanelHabilidadesHUD.new()
	add_child(panel)
	await _esperar(60)
	_m("jugador listo | guía: contexto=%s visible=%s filas=%d" % [
			str(panel._contexto_actual), str(panel.visible), _filas(panel)])

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(RUTA_CAPTURAS))
	var casos: Array = [
		["01_grande.png", AjustesJugabilidad.HUD_TAM_GRANDE],
		["02_mediano.png", AjustesJugabilidad.HUD_TAM_MEDIANO],
		["03_chico.png", AjustesJugabilidad.HUD_TAM_CHICO],
	]
	for caso_v in casos:
		var caso: Array = caso_v
		AjustesJugabilidad.poner_hud_controles_tamano(int(caso[1]))
		await _esperar(8)
		var rect: Rect2 = (panel.get_node("Caja") as Control).get_global_rect()
		_m("tamaño %d -> guía %s  filas=%d" % [int(caso[1]), str(rect), _filas(panel)])
		await _capturar(String(caso[0]))

	# Apagada: debe desaparecer por completo.
	AjustesJugabilidad.poner_hud_controles_visible(false)
	await _esperar(8)
	_m("apagada -> visible=%s" % str(panel.visible))
	await _capturar("04_apagada.png")
	AjustesJugabilidad.poner_hud_controles_visible(true)
	await _esperar(6)

# ------------------------------------------------------------------- 2. menú
func _menu() -> void:
	var vis_antes: bool = AjustesJugabilidad.hud_controles_visible
	var tam_antes: int = AjustesJugabilidad.hud_controles_tamano
	AjustesJugabilidad.poner_hud_controles_visible(true)

	var esc: PackedScene = load("res://ui/scenes/PauseMenu.tscn")
	if esc == null:
		_m("[menu] NO se pudo cargar PauseMenu.tscn")
		return
	var m: Node = esc.instantiate()
	add_child(m)
	await _esperar(4)
	var cont: Node = m.find_child("JugabilidadContent", true, false)
	_m("[menu] JugabilidadContent encontrado=%s" % str(cont != null))
	if cont != null:
		for l in cont.find_children("*", "Label", true, false):
			_m("[menu]   %s = %s" % [str(l.get_path()), (l as Label).text])

	# Los MISMOS manejadores del menú: la flecha de la derecha y la de la izquierda.
	var t0: int = AjustesJugabilidad.hud_controles_tamano
	m.call("_on_tam_habilidades_paso", 1)
	await _esperar(2)
	_m("[menu] flecha > : %d -> %d  (%s)" % [t0, AjustesJugabilidad.hud_controles_tamano,
			AjustesJugabilidad.texto_hud_controles_tamano()])
	m.call("_on_tam_habilidades_paso", 1)
	await _esperar(2)
	_m("[menu] flecha > : %d  (%s)" % [AjustesJugabilidad.hud_controles_tamano,
			AjustesJugabilidad.texto_hud_controles_tamano()])
	m.call("_on_tam_habilidades_paso", -2)
	await _esperar(2)
	_m("[menu] flecha < : %d  (%s)" % [AjustesJugabilidad.hud_controles_tamano,
			AjustesJugabilidad.texto_hud_controles_tamano()])
	if cont != null:
		for l in cont.find_children("*", "Label", true, false):
			_m("[menu]   tras cambiar: %s = %s" % [str(l.get_path()), (l as Label).text])

	m.call("_on_habilidades_paso")
	await _esperar(2)
	_m("[menu] alternar mostrar -> visible=%s" % str(AjustesJugabilidad.hud_controles_visible))
	if cont != null:
		for l in cont.find_children("*", "Label", true, false):
			_m("[menu]   tras alternar: %s = %s" % [str(l.get_path()), (l as Label).text])

	# ---------------------------------------------------- 3. persistencia real
	var cf := ConfigFile.new()
	var err := cf.load(AjustesJugabilidad.RUTA)
	_m("[persist] cargar %s -> %d" % [AjustesJugabilidad.RUTA, err])
	if err == OK:
		for k in cf.get_section_keys(AjustesJugabilidad.SECCION):
			_m("[persist]   %s = %s" % [str(k),
					str(cf.get_value(AjustesJugabilidad.SECCION, k))])

	m.queue_free()
	AjustesJugabilidad.poner_hud_controles_visible(vis_antes)
	AjustesJugabilidad.poner_hud_controles_tamano(tam_antes)
	await _esperar(3)
	_m("[persist] ajustes del jugador restaurados: visible=%s tamano=%d" % [
			str(AjustesJugabilidad.hud_controles_visible), AjustesJugabilidad.hud_controles_tamano])