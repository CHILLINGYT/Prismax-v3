extends Node3D

# ARNÉS TEMPORAL DE VERIFICACIÓN EN VIVO (se elimina al terminar).
# Instancia el jugador REAL sobre un suelo y prueba la transformación VUELO
# (Águila): que se active/desactive el cuerpo volador, la cámara y las
# colisiones, y que AL SALIR se limpie todo su estado. NO modifica el proyecto.

const LEO := preload("res://personaje/base/escenas/leo_jugador.tscn")

var _j: Node3D
var _v: Node3D
var _ok := 0
var _fail := 0
var _log := ""

func _chk(nombre: String, cond: bool, detalle: String = "") -> void:
	if cond: _ok += 1
	else: _fail += 1
	var linea := "[TEST] %s :: %s | %s" % ["OK" if cond else "FALLO", nombre, detalle]
	_log += linea + "\n"
	print(linea)

func _esperar(s: float) -> void:
	await get_tree().create_timer(s).timeout

func _ready() -> void:
	var suelo := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(300, 1, 300)
	cs.shape = bs
	suelo.add_child(cs)
	suelo.position = Vector3(0, -0.5, 0)
	add_child(suelo)

	_j = LEO.instantiate()
	add_child(_j)
	_j.global_position = Vector3(0, 1.0, 0)
	await _esperar(0.8)

	_v = _j.get_node_or_null("Vuelo")
	var col_leo: CollisionShape3D = _j.get_node("Colision")
	_chk("la escena del jugador incluye el nodo Vuelo", _v != null)
	if _v == null:
		_volcar()
		get_tree().quit()
		return
	var cs_vuelo: CollisionShape3D = _v.get_node("CollisionShape3D")

	_chk("Vuelo arranca oculto", not _v.visible)
	_chk("Vuelo arranca desactivado (process_mode DISABLED)",
		_v.process_mode == Node.PROCESS_MODE_DISABLED)
	_chk("colisión de Vuelo desactivada al inicio", cs_vuelo.disabled)
	_chk("colisión del jugador ACTIVA al inicio", not col_leo.disabled)
	_chk("id_forma inicial = humano", _j.id_forma() == &"humano")

	# --- Menú: Águila BLOQUEADA hasta completar la misión ---
	_j.menu_transf.abrir()
	await get_tree().process_frame
	var entrada = _j.menu_transf._entradas.get(&"aguila", null)
	_chk("Águila aparece BLOQUEADA en el menú (misión sin completar)",
		entrada != null and entrada["bloqueada"])
	var candado: CanvasItem = entrada.get("candado", null) if entrada != null else null
	_chk("el candado rojo de Vuelo está VISIBLE mientras la misión no está completa",
		candado != null and candado.visible)
	# Hover sobre Vuelo bloqueado: mensaje EXACTO de dos líneas en la zona central.
	_j.menu_transf._on_icono_entra(&"aguila")
	await get_tree().process_frame
	_chk("el mensaje de bloqueo aparece al pasar el cursor sobre Vuelo",
		_j.menu_transf._detalle.text == "requiere completar\nla mision",
		"texto=%s" % _j.menu_transf._detalle.text)
	_j.menu_transf._on_icono_sale(&"aguila")
	await get_tree().process_frame
	_chk("el mensaje desaparece al retirar el cursor de Vuelo",
		_j.menu_transf._detalle.text == "")
	# Marca DEMO: escala de grises + etiqueta roja, SÓLO en Águila.
	var ic_aguila: TextureRect = entrada["tex"] if entrada != null else null
	var demo_lbl: Label = (
		ic_aguila.get_parent().get_node_or_null("Demo") if ic_aguila != null else null
	)
	_chk("el retrato de Águila usa material de escala de grises",
		ic_aguila != null and ic_aguila.material is ShaderMaterial)
	_chk("la tarjeta de Águila muestra la etiqueta DEMO",
		demo_lbl != null and demo_lbl.text == "DEMO",
		"texto=%s" % (demo_lbl.text if demo_lbl != null else "<ninguno>"))
	var col_demo: Color = (
		demo_lbl.get_theme_color("font_color") if demo_lbl != null else Color(0, 0, 0)
	)
	_chk("DEMO está en rojo intenso",
		col_demo.r > 0.7 and col_demo.g < 0.3 and col_demo.b < 0.3,
		"color=%.2f,%.2f,%.2f" % [col_demo.r, col_demo.g, col_demo.b])
	var otras_limpias := true
	for otro in [&"velocista", &"pes", &"tanque", &"combate"]:
		var e_otro = _j.menu_transf._entradas.get(otro, null)
		if e_otro != null and (
			e_otro["tex"].material != null
			or e_otro["control"].get_node_or_null("Demo") != null
		):
			otras_limpias = false
	_chk("las demás transformaciones conservan su aspecto (sin gris ni DEMO)",
		otras_limpias)
	# Candado FUNCIONAL: con la misión incompleta, Vuelo no se activa ni aunque se
	# emita la señal de elección directamente (el ControladorLeo lo rechaza).
	_j.menu_transf.transformacion_elegida.emit(&"aguila")
	await _esperar(0.5)
	_chk("con la misión incompleta, Vuelo NO se activa (candado funcional)",
		_j.forma == _j.Forma.HUMANO and _j.id_forma() == &"humano",
		"forma=%d" % _j.forma)
	# Al completar la misión, Vuelo se DESBLOQUEA sin cerrar ni reabrir el menú.
	Misiones.marcar_completada(Misiones.MISION_PROFUGOS)
	await get_tree().process_frame
	_chk("al completar la misión, Águila queda DESBLOQUEADA en el menú",
		entrada != null and not entrada["bloqueada"])
	_chk("el candado rojo desaparece al completar la misión",
		candado != null and not candado.visible)
	_j.menu_transf.cerrar()
	await get_tree().process_frame

	# --- Configuración de controles: habilidades de Vuelo ---
	_chk("InputMap tiene la acción 'palmazo'", InputMap.has_action("palmazo"))
	_chk("InputMap tiene la acción 'grab'", InputMap.has_action("grab"))
	var acciones_vuelo: Array = AjustesControles.acciones_para(&"vuelo")
	_chk("CONTROLES lista habilidades de Vuelo (palmazo, grab, guard…)",
		acciones_vuelo.has(&"palmazo") and acciones_vuelo.has(&"grab")
		and acciones_vuelo.has(&"guard") and acciones_vuelo.has(&"aim"))
	_chk("Movimiento común disponible en Vuelo",
		acciones_vuelo.has(&"mover_adelante") and acciones_vuelo.has(&"saltar"))
	_chk("Etiqueta de 'palmazo' en Vuelo = 'Palmazo de viento'",
		AjustesControles.etiqueta_de(&"palmazo", &"vuelo") == "Palmazo de viento")
	_chk("Retrato de Vuelo usa el icono de Águila",
		ResourceLoader.exists("res://personaje/hud_transformacion/iconos/aguila.png"))
	_chk("CONTROLES muestra C para iniciar el vuelo",
		AjustesControles.texto_de(&"toggle_flight") == "C",
		"toggle=%s" % AjustesControles.texto_de(&"toggle_flight"))
	_chk("CONTROLES muestra X para picar",
		AjustesControles.texto_de(&"fly_down") == "X",
		"picada=%s" % AjustesControles.texto_de(&"fly_down"))
	_chk("F conserva el menú de transformaciones",
		InputMap.has_action("menu_transformaciones"))
	var sk_v := _v.get_node("VisualRoot/AnimationLibrary_Godot_Standard/Rig/GeneralSkeleton") as Skeleton3D
	var piel := sk_v.get_node_or_null("AguilaSkinned") as MeshInstance3D
	_chk("el maniquí NO es el cuerpo visible (está oculto)",
		not (sk_v.get_node("Mannequin") as MeshInstance3D).visible)
	_chk("el cuerpo visible es la malla del Tripo, con skin al esqueleto",
		piel != null and piel.visible and piel.skin != null and piel.skeleton == NodePath(".."))
	_chk("la malla del Tripo tiene pesos de huesos (se deforma con las animaciones)",
		piel != null and piel.mesh != null
		and piel.mesh.surface_get_arrays(0)[Mesh.ARRAY_BONES] != null
		and piel.mesh.surface_get_arrays(0)[Mesh.ARRAY_WEIGHTS] != null)

	# --- Transformar a VUELO (por el MISMO camino que el menú) ---
	_j.menu_transf.transformacion_elegida.emit(&"aguila")
	await _esperar(1.2)
	_chk("forma == VUELO", _j.forma == _j.Forma.VUELO, "forma=%d" % _j.forma)
	_chk("id_forma = aguila", _j.id_forma() == &"aguila")
	_chk("Vuelo visible", _v.visible)
	_chk("Vuelo procesando", _v.process_mode == Node.PROCESS_MODE_INHERIT)
	_chk("colisión de Vuelo ACTIVA", not cs_vuelo.disabled)
	_chk("colisión del jugador desactivada durante el vuelo", col_leo.disabled)
	_chk("el vuelo NO se autoactiva (lo inicia C)", not _v.get_node("FlightController").is_flying)
	# C (acción "toggle_flight") inicia el vuelo con la lógica del módulo.
	Input.action_press("toggle_flight")
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release("toggle_flight")
	await _esperar(0.3)
	_chk("C inicia el vuelo (is_flying)", _v.get_node("FlightController").is_flying)
	_chk("la cámara del vuelo es la ACTIVA",
		(_v.get_node("CameraPivot/SpringArm3D/Camera3D") as Camera3D).current)
	_chk("la cámara terrestre dejó de procesar",
		not (_j.get_node("PivoteCamara") as Node).is_processing())
	_chk("GroundCombat expone cancelar_todo",
		_v.get_node("GroundCombat").has_method("cancelar_todo"))
	_chk("TalonsAbility expone soltar_todo",
		_v.get_node("TalonsAbility").has_method("soltar_todo"))
	_chk("FeatherAbility expone cancelar_apuntado",
		_v.get_node("FeatherAbility").has_method("cancelar_apuntado"))
	var col_efecto: Color = _j.efecto_transf.color
	_chk("efecto de transformación = celeste claro (~#87CEFA)",
		absf(col_efecto.r - 0.53) < 0.03 and absf(col_efecto.g - 0.81) < 0.03
		and absf(col_efecto.b - 0.98) < 0.03,
		"color=%.2f,%.2f,%.2f" % [col_efecto.r, col_efecto.g, col_efecto.b])

	# --- Volver a HUMANO: limpieza total ---
	_j.menu_transf.transformacion_elegida.emit(&"aguila")  # ya en vuelo -> vuelve a humano
	await _esperar(1.2)
	_chk("vuelve a humano", _j.forma == _j.Forma.HUMANO, "forma=%d" % _j.forma)
	_chk("Vuelo oculto al salir", not _v.visible)
	_chk("Vuelo desactivado al salir", _v.process_mode == Node.PROCESS_MODE_DISABLED)
	_chk("colisión de Vuelo desactivada al salir", cs_vuelo.disabled)
	_chk("colisión del jugador restaurada", not col_leo.disabled)
	_chk("el volador ya no vuela", not _v.get_node("FlightController").is_flying)
	_chk("la cámara terrestre vuelve a procesar",
		(_j.get_node("PivoteCamara") as Node).is_processing())
	_chk("la cámara del vuelo dejó de ser la activa",
		not (_v.get_node("CameraPivot/SpringArm3D/Camera3D") as Camera3D).current)

	# --- Cambio a otra transformación existente (no debe romperse) ---
	_j.menu_transf.transformacion_elegida.emit(&"velocista")
	await _esperar(1.2)
	_chk("cambia a Velocista tras Vuelo", _j.forma == _j.Forma.VELOCISTA, "forma=%d" % _j.forma)
	_chk("el volador sigue apagado", _v.process_mode == Node.PROCESS_MODE_DISABLED and not _v.visible)
	_j.menu_transf.transformacion_elegida.emit(&"pes")
	await _esperar(1.2)
	_chk("cambia a Acuático tras Velocista", _j.forma == _j.Forma.ACUATICO, "forma=%d" % _j.forma)

	print("[TEST] ===== RESUMEN VUELO: %d OK, %d FALLOS =====" % [_ok, _fail])
	_volcar()
	await _esperar(0.4)
	get_tree().quit()

func _volcar() -> void:
	var f := FileAccess.open("res://pruebas/_resultado_vuelo.txt", FileAccess.WRITE)
	if f != null:
		f.store_string(_log + "RESUMEN: %d OK, %d FALLOS\n" % [_ok, _fail])
		f.close()