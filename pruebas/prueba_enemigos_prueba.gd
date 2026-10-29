extends Node3D

# Suite automática (se ejecuta como ESCENA) del sistema de ENEMIGOS DE PRUEBA y
# de la viñeta de daño del jugador. Comprueba, sobre el jugador REAL y con el
# CombatManager del módulo FreeFlow, la lista de pruebas del encargo:
#   1. el mapa de entrada de main: G = enemigos_prueba (sin duplicados), el menú
#      radial de transformaciones sigue en F y la acción directa antigua no vuelve;
#   2. la API de cápsulas (generar_grupo) genera exactamente 6 repartidas
#      alrededor del jugador. La tecla G ya NO genera cápsulas: ahora genera 5
#      enemigos, 3 de cuerpo a cuerpo + 2 con armas (eso lo verifica la suite de
#      esqueleto). Aquí se sigue validando el sistema de CÁPSULAS, sin cambios;
#   3. todos quedan en los grupos "enemigos_prueba" y "damageable" y registrados;
#   4. el anillo de cerco reparte 6 posiciones (formación del módulo);
#   5. el sistema de turnos limita a 2 atacantes simultáneos;
#   6. un golpe enemigo aplica daño UNA sola vez (ventana de impacto);
#   7. el jugador recibe daño por el sistema real en TODAS las formas;
#   8. la viñeta es rojo azulada con escudo, roja y persistente con escudo roto,
#      y vuelve al recuperarse;
#   9. FreeFlow selecciona y golpea las cápsulas (daño por take_hit);
#  10. la muerte retira al enemigo del combate, de los grupos y de la selección;
#  11. retirar/generar de la API de cápsulas no duplica y permite regenerar;
#  12. la escena principal del proyecto no cambia y contiene el sistema.
#
# No forma parte del juego: vive en res://pruebas/ y se ejecuta como una ESCENA
# (igual que las suites de main: controles_test, jugabilidad_test...). Es lo que
# garantiza que los autoloads del proyecto ya existan cuando se compila el
# controlador de main, que ahora los usa:
#   godot --headless --path <proyecto> res://pruebas/prueba_enemigos_prueba.tscn
# También se puede abrir y ejecutar desde el editor (F6).

const JUGADOR := preload("res://personaje/base/escenas/leo_jugador.tscn")
const GestorCombate := preload("res://personaje/transformaciones/transformacion ataque/scripts/combat/combat_manager.gd")
const ConfigCombate := preload("res://personaje/transformaciones/transformacion ataque/resources/combat_config.tres")
const GerenteScript := preload("res://Enemigos Prueba/Scripts/gerente_enemigos_prueba.gd")
const ClaseEnemigo := preload("res://Enemigos Prueba/Scripts/enemigo_prueba.gd")

const ESCENA_MUNDO := "res://mundo/escena/ziba_prototipo.tscn"
const ESCENA_PRINCIPAL := "res://ui/scenes/IntroVideo.tscn"
const FORMA_COMBATE := 4
const C_LIBRE := 0

var _pasadas := 0
var _falladas := 0
var _jug: ControladorLeo
var _stats: EstadisticasJugador
var _gerente: Node3D
var _mgr: Node
var _danios: Array[float] = []

func _ready() -> void:
	call_deferred("_correr")

func _check(nombre: String, ok: bool, detalle: String = "") -> void:
	var sufijo := (" — " + detalle) if detalle != "" else ""
	if ok:
		_pasadas += 1
		print("[OK]    ", nombre, sufijo)
	else:
		_falladas += 1
		print("[FALLA] ", nombre, sufijo)

func _esperar_frames(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame

func _tecla_de(accion: StringName) -> int:
	for ev in InputMap.action_get_events(accion):
		if ev is InputEventKey:
			return (ev as InputEventKey).physical_keycode
	return -1

## Pulsa una tecla FÍSICA de verdad (pasa por _unhandled_input, como el juego).
func _pulsar_tecla(codigo: Key) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = codigo
	ev.pressed = true
	Input.parse_input_event(ev)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var suelta := InputEventKey.new()
	suelta.physical_keycode = codigo
	suelta.pressed = false
	Input.parse_input_event(suelta)
	await get_tree().physics_frame
	await get_tree().physics_frame

func _enemigos() -> Array:
	var lista: Array = []
	for n in get_tree().get_nodes_in_group(&"enemigos_prueba"):
		if is_instance_valid(n) and n is ClaseEnemigo:
			lista.append(n)
	return lista

func _contar_danio(cantidad: float) -> void:
	_danios.append(cantidad)

func _correr() -> void:
	# ---------------------------------------------------------------- 1. entrada
	# El Input Map de main manda: las transformaciones se eligen en el menú radial
	# (F) y la antigua acción directa "transformacion_velocidad" ya no existe, así
	# que este PR no reasigna ninguna tecla de main: sólo añade G.
	var tecla_g := _tecla_de(&"enemigos_prueba")
	var tecla_f := _tecla_de(&"menu_transformaciones")
	_check("1. G está asignada a 'enemigos_prueba' (tecla libre en el Input Map de main)",
			tecla_g == KEY_G, "tecla=%d" % tecla_g)
	_check("1. El menú radial de transformaciones sigue en F (arquitectura de main)",
			tecla_f == KEY_F, "tecla=%d" % tecla_f)
	_check("1. No se reintroduce la antigua acción directa 'transformacion_velocidad'",
			not InputMap.has_action(&"transformacion_velocidad"))
	var otras: Array[String] = []
	for accion in InputMap.get_actions():
		if accion != &"enemigos_prueba" and _tecla_de(accion) == KEY_G:
			otras.append(String(accion))
	_check("1. Ninguna otra acción usa G (sin conflictos)",
			otras.is_empty(), ", ".join(otras))

	# ---------------------------------------------------------------- mundo mínimo
	var mundo := Node3D.new()
	mundo.name = "MundoPrueba"
	add_child(mundo)
	var suelo := StaticBody3D.new()
	suelo.position = Vector3(0.0, -0.5, 0.0)
	var forma := CollisionShape3D.new()
	var caja := BoxShape3D.new()
	caja.size = Vector3(60.0, 1.0, 60.0)
	forma.shape = caja
	suelo.add_child(forma)
	mundo.add_child(suelo)

	# El gestor del encuentro: EL MISMO del módulo (sin duplicar gestores).
	_mgr = Node.new()
	_mgr.name = "CombatManager"
	_mgr.set_script(GestorCombate)
	_mgr.set("config", ConfigCombate)
	mundo.add_child(_mgr)

	_jug = JUGADOR.instantiate() as ControladorLeo
	mundo.add_child(_jug)
	_jug.global_position = Vector3(0.0, 0.1, 0.0)
	_stats = _jug.get_node_or_null("Estadisticas") as EstadisticasJugador
	await _esperar_frames(10)

	_gerente = Node3D.new()
	_gerente.name = "EnemigosPrueba"
	_gerente.set_script(GerenteScript)
	_gerente.set("cantidad", 6)
	_gerente.set("radio_aparicion", 7.0)
	_gerente.set("vida_enemigo", 60.0)
	# Daño pequeño para que el jugador no muera durante una suite larga; el daño
	# del golpe medido en la prueba 6 se fija aparte, a mano, a su valor exacto.
	_gerente.set("dano_enemigo", 2.0)
	mundo.add_child(_gerente)
	await _esperar_frames(4)

	_check("2. El gerente localiza al jugador integrado (ControladorLeo)",
			_gerente.call("jugador") == _jug)
	_check("2. El gestor del encuentro recibe al jugador (set_player)",
			_mgr.call("get_player") == _jug)

	# ---------------------------------------------------------------- 2. G = 6
	_gerente.call("generar_grupo")
	await _esperar_frames(3)
	var enemigos := _enemigos()
	_check("2. La API de cápsulas genera exactamente 6 enemigos", enemigos.size() == 6,
			"grupo=%d" % enemigos.size())

	# Distribución alrededor del jugador (se mide enseguida: aún casi no caminan).
	var angulos: Array[float] = []
	var distancias: Array[float] = []
	var muy_junto := false
	for e in enemigos:
		var dif: Vector3 = (e as Node3D).global_position - _jug.global_position
		var dist := Vector2(dif.x, dif.z).length()
		distancias.append(dist)
		angulos.append(atan2(dif.z, dif.x))
		if dist < 3.0:
			muy_junto = true
	_check("2. Los 6 aparecen repartidos alrededor (3-11 m, ninguno encima)",
			not muy_junto and angulos.size() == 6,
			"distancias=%s" % str(distancias.map(func(d: float) -> float: return snappedf(d, 0.1))))
	var sep_min := 999.0
	for i in angulos.size():
		for j in range(i + 1, angulos.size()):
			sep_min = minf(sep_min, absf(rad_to_deg(wrapf(angulos[i] - angulos[j], -PI, PI))))
	_check("2. Separación angular de aparición ≥ 35° (reparto, no racimo)",
			sep_min >= 35.0, "mínima=%.1f°" % sep_min)

	# Grupos, registro y ids únicos.
	var ids := {}
	var en_grupos := true
	for e in enemigos:
		ids[e.id_ia] = true
		if not e.is_in_group(&"damageable") or not e.is_in_group(&"enemigos_prueba"):
			en_grupos = false
	_check("3. Todos en 'enemigos_prueba' y 'damageable'", en_grupos)
	_check("3. Todos registrados en el CombatManager (selección de objetivos)",
			_mgr.call("get_active_enemies").size() == 6,
			"activos=%d" % _mgr.call("get_active_enemies").size())
	_check("3. Identificador de IA único por instancia", ids.size() == 6,
			"ids=%s" % str(ids.keys()))

	# ---------------------------------------------------------------- 4. cerco
	await _esperar_frames(8)
	var slots_ok := true
	var ang_slots: Array[float] = []
	for e in enemigos:
		if not bool(_mgr.get("formation").has_slot(e)):
			slots_ok = false
			continue
		var pos: Vector3 = _mgr.get("formation").get_slot(e)
		var dif := pos - _jug.global_position
		ang_slots.append(atan2(dif.z, dif.x))
	_check("4. El anillo de cerco (CombatFormation del módulo) asigna posición a los 6",
			slots_ok and ang_slots.size() == 6)
	var sep_slots := 999.0
	for i in ang_slots.size():
		for j in range(i + 1, ang_slots.size()):
			sep_slots = minf(sep_slots, absf(rad_to_deg(wrapf(ang_slots[i] - ang_slots[j], -PI, PI))))
	_check("4. Las 6 posiciones de cerco están repartidas (~60°)",
			sep_slots >= 45.0, "mínima=%.1f°" % sep_slots)

	# ---------------------------------------------------------------- 5. turnos
	# Se desactiva el ataque propio de los enemigos para medir el turnero aislado.
	for e in enemigos:
		e.alcance_golpe = 0.05
	await _esperar_frames(10)
	var tokens: Variant = _mgr.get("tokens")
	for e in enemigos:
		tokens.release(e)
	tokens.update()
	_check("5. Turnero vacío al empezar la medición", int(tokens.count_used()) == 0,
			"usados=%d" % int(tokens.count_used()))
	for e in enemigos:
		tokens.request(e)
	tokens.update()
	var usados_2 := int(tokens.count_used())
	_check("5. Con 6 pretendientes solo 2 tienen turno de ataque (máx. 2)",
			usados_2 == 2, "usados=%d" % usados_2)
	# Al liberar uno, el siguiente de la cola (el que más espera) entra.
	var titular: Variant = enemigos[0]
	tokens.release(titular)
	tokens.update()
	_check("5. Al terminar un atacante, el siguiente de la cola aprovecha el hueco",
			int(tokens.count_used()) == 2 and not bool(tokens.has_token(titular)),
			"usados=%d" % int(tokens.count_used()))
	for e in enemigos:
		tokens.release(e)
	tokens.update()
	_check("5. Todos los turnos se pueden soltar (sin bloqueos)", int(tokens.count_used()) == 0)

	# ---------------------------------------------------------------- 6/7. golpe
	# Un único enemigo vuelve a poder atacar, con daño exacto y sin varianza.
	var atacante: Variant = enemigos[0]
	# Se espera a que esté cerca del anillo (el cerco está a ~2.5 m).
	var t_acerca := 0
	while t_acerca < 240 and (atacante as Node3D).global_position.distance_to(_jug.global_position) > 3.0:
		await get_tree().physics_frame
		t_acerca += 1
	atacante.danio_base = 10.0
	atacante.varianza_dano = 0.0
	atacante.alcance_golpe = 4.0
	var vida_total_antes: float = _stats.vida + _stats.resistencia
	_danios.clear()
	_stats.danio_recibido.connect(_contar_danio)
	var vio_preparar := false
	var vio_golpear := false
	var vio_recuperar := false
	for _i in 300:
		await get_tree().physics_frame
		var st: int = int(atacante.estado_actual())
		if st == ClaseEnemigo.Estado.PREPARAR:
			vio_preparar = true
		elif st == ClaseEnemigo.Estado.GOLPEAR:
			vio_golpear = true
		elif st == ClaseEnemigo.Estado.RECUPERAR:
			vio_recuperar = true
		if vio_recuperar:
			break
	_stats.danio_recibido.disconnect(_contar_danio)
	_check("6. El ataque muestra preparación, golpe y recuperación",
			vio_preparar and vio_golpear and vio_recuperar,
			"prep=%s golpe=%s recup=%s" % [str(vio_preparar), str(vio_golpear), str(vio_recuperar)])
	_check("6. El golpe aplica daño UNA sola vez (ventana de impacto)",
			_danios.size() == 1 and is_equal_approx(_danios[0], 10.0),
			"danios=%s" % str(_danios))
	var vida_total_despues: float = _stats.vida + _stats.resistencia
	_check("6. El daño entra por el sistema real (vida+resistencia baja 10)",
			absf(vida_total_antes - vida_total_despues - 10.0) < 0.05,
			"antes=%.1f despues=%.1f" % [vida_total_antes, vida_total_despues])
	# El siguiente golpe no puede llegar antes de la espera propia (0.8 s mínimo):
	# se comprueba que no hay goteo de daño tras la recuperación.
	_danios.clear()
	_stats.danio_recibido.connect(_contar_danio)
	await _esperar_frames(20)
	_stats.danio_recibido.disconnect(_contar_danio)
	_check("6. No hay daño continuo por fotograma (sin goteo tras el golpe)",
			_danios.is_empty(), "danios_en_ventana_muerta=%s" % str(_danios))
	atacante.alcance_golpe = 0.05

	# ---------------------------------------------------------------- 7. formas
	var formas: Array = [
		{"nombre": "humano", "metodo": &"_entrar_humano"},
		{"nombre": "velocista", "metodo": &"_entrar_velocista"},
		{"nombre": "pes", "metodo": &"_entrar_acuatico"},
		{"nombre": "tanque", "metodo": &"_entrar_fuerza"},
		{"nombre": "combate", "metodo": &"_entrar_combate"},
	]
	for f in formas:
		_jug.call(f["metodo"])
		await _esperar_frames(2)
		var total_antes: float = _stats.vida + _stats.resistencia
		var res_antes: float = _stats.resistencia
		_stats.recibir_danio(10.0)
		await _esperar_frames(1)
		var total_despues: float = _stats.vida + _stats.resistencia
		var absorbido: float = res_antes - _stats.resistencia
		var esperado: float = 8.0 if res_antes > 0.0 else 0.0
		_check("7. El jugador en %s recibe el daño por el sistema real (escudo 80%%)" % f["nombre"],
				absf(total_antes - total_despues - 10.0) < 0.05 and absf(absorbido - esperado) < 0.05,
				"absorbido=%.1f vida=%.1f escudo=%.1f" % [absorbido, _stats.vida, _stats.resistencia])

	# ---------------------------------------------------------------- 8. viñeta
	var hud: Node = _jug.get_node_or_null("HUD")
	var vineta: ColorRect = null
	var mat: ShaderMaterial = null
	if hud != null:
		vineta = hud.get_node_or_null("Raiz/VinetaDano") as ColorRect
		if vineta != null:
			mat = vineta.material as ShaderMaterial
	_check("8. La viñeta de daño vive en el HUD existente (ColorRect + shader)",
			vineta != null and mat != null)
	if mat != null:
		# En reposo (sin pulso reciente) la viñeta está apagada.
		await _esperar_frames(75)
		var intensidad_reposo := float(mat.get_shader_parameter("intensidad"))
		_check("8. En reposo la pantalla queda despejada (intensidad ~0)",
				intensidad_reposo < 0.05, "intensidad=%.3f" % intensidad_reposo)
		# Estado A: escudo con carga -> pulso rojo azulado.
		_stats.recibir_danio(20.0)
		await _esperar_frames(2)
		var color_a: Color = mat.get_shader_parameter("color")
		var intensidad_a := float(mat.get_shader_parameter("intensidad"))
		_check("8. Golpe con escudo: pulso visible y tinte ROJO AZULADO",
				intensidad_a > 0.15 and color_a.r > 0.4 and color_a.b > 0.25,
				"intensidad=%.2f color=%s" % [intensidad_a, str(color_a)])
		# Estado B: escudo a cero -> rojo puro persistente (sin componente azul).
		_stats.resistencia = 0.0
		_stats.resistencia_cambiada.emit(0.0, _stats.resistencia_max)
		await _esperar_frames(2)
		var color_b: Color = mat.get_shader_parameter("color")
		_check("8. Escudo roto: la viñeta pasa a ROJA sin azul",
				color_b.r > 0.5 and color_b.b < 0.2, "color=%s" % str(color_b))
		await _esperar_frames(45)
		var intensidad_b := float(mat.get_shader_parameter("intensidad"))
		_check("8. El estado rojo PERSISTE mientras el escudo siga roto",
				intensidad_b > 0.2, "intensidad=%.2f" % intensidad_b)
		# Recuperación: el escudo vuelve y la viñeta se apaga sola.
		_stats.resistencia = _stats.resistencia_max
		_stats.resistencia_cambiada.emit(_stats.resistencia, _stats.resistencia_max)
		await _esperar_frames(60)
		var color_c: Color = mat.get_shader_parameter("color")
		var intensidad_c := float(mat.get_shader_parameter("intensidad"))
		_check("8. Al recuperarse el escudo la viñeta vuelve al estado con carga y se apaga",
				intensidad_c < 0.12 and color_c.b > 0.25,
				"intensidad=%.2f color=%s" % [intensidad_c, str(color_c)])

	# ---------------------------------------------------------------- 9. FreeFlow
	# Vuelta a humano y entrada a Combate por el camino REAL del menú radial.
	_jug.call(&"_entrar_humano")
	await _esperar_frames(2)
	_jug._on_transformacion_elegida(&"combate")
	var t_forma := 0
	while (_jug.forma != FORMA_COMBATE or _jug._transformando) and t_forma < 600:
		await get_tree().physics_frame
		t_forma += 1
	_check("9. La forma Combate entra por el camino del menú (id &\"combate\")",
			_jug.forma == FORMA_COMBATE and _jug.id_forma() == &"combate",
			"forma=%d" % _jug.forma)
	while not _jug.is_on_floor() and t_forma < 900:
		await get_tree().physics_frame
		t_forma += 1

	var vida_antes := {}
	for e in _enemigos():
		vida_antes[e.get_instance_id()] = e.vida_actual()
	Input.action_press("atacar")
	await get_tree().physics_frame
	Input.action_release("atacar")
	var objetivo: Node = null
	var arranco := false
	var hubo_golpe := false
	for _i in 300:
		await get_tree().physics_frame
		if _jug.c_estado != C_LIBRE:
			arranco = true
		if _jug.c_objetivo != null and is_instance_valid(_jug.c_objetivo):
			objetivo = _jug.c_objetivo
		if int(_mgr.get("combo").count) > 0:
			hubo_golpe = true
			break
	_check("9. FreeFlow arranca el golpe en el suelo (estado de combate)", arranco,
			"estado=%d" % _jug.c_estado)
	_check("9. El targeting contextual selecciona una cápsula registrada",
			objetivo != null and objetivo is ClaseEnemigo,
			"objetivo=%s" % str(objetivo))
	var bajo_vida := false
	for e in _enemigos():
		var antes := float(vida_antes.get(e.get_instance_id(), e.vida_actual()))
		if e.vida_actual() < antes - 0.5:
			bajo_vida = true
	_check("9. El golpe aplica daño a la cápsula (contrato take_hit) y cuenta combo",
			hubo_golpe and bajo_vida,
			"combo=%d" % int(_mgr.get("combo").count))

	# ---------------------------------------------------------------- 10. muerte
	var victima: Variant = _enemigos()[0]
	for e in _enemigos():
		tokens.release(e)
	tokens.request(victima)
	tokens.update()
	var tenia_turno := bool(tokens.has_token(victima))
	victima.take_hit(999.0, Vector3.FORWARD, 0.0, 0.0)
	await _esperar_frames(3)
	_check("10. La vida llega a 0 y el enemigo deja de estar vivo",
			victima.vida_actual() <= 0.0 and not bool(victima.is_alive()),
			"vida=%.1f" % victima.vida_actual())
	_check("10. Al morir sale de los grupos de objetivos",
			not victima.is_in_group(&"damageable") and not victima.is_in_group(&"enemigos_prueba"))
	_check("10. Al morir sale de la selección del CombatManager",
			_mgr.call("get_active_enemies").size() == 5,
			"activos=%d" % _mgr.call("get_active_enemies").size())
	_check("10. Al morir libera el turno que tuviera reservado",
			not bool(tokens.has_token(victima)), "tenía turno=%s" % str(tenia_turno))
	var t_libre := 0
	while is_instance_valid(victima) and t_libre < 180:
		await get_tree().physics_frame
		t_libre += 1
	_check("10. El enemigo muerto se retira de la escena de forma segura",
			not is_instance_valid(victima), "frames=%d" % t_libre)
	await _esperar_frames(5)
	var slots_5 := 0
	for e in _enemigos():
		if bool(_mgr.get("formation").has_slot(e)):
			slots_5 += 1
	_check("10. Con 5 vivos el cerco se recalcula solo (todos con posición)",
			slots_5 == 5, "con_slot=%d" % slots_5)

	# ------------------------------------------------------- 11. regenerar (API)
	_gerente.call("retirar_grupo")
	await _esperar_frames(2)
	var restantes := _enemigos()
	_check("11. Retirar con el grupo activo lo quita entero (no genera otros seis encima)",
			restantes.is_empty(), "quedan=%d" % restantes.size())
	_check("11. El gerente queda sin referencias tras retirar",
			_gerente.call("enemigos_vivos").is_empty())
	_gerente.call("generar_grupo")
	await _esperar_frames(3)
	var nuevos := _enemigos()
	var ids_nuevos := {}
	for e in nuevos:
		ids_nuevos[e.id_ia] = true
	_check("11. Volver a generar produce un grupo limpio de 6", nuevos.size() == 6,
			"grupo=%d" % nuevos.size())
	_gerente.call("generar_grupo")
	await _esperar_frames(3)
	_check("11. Llamar a generar con grupo activo no duplica (sigue habiendo 6)",
			_enemigos().size() == 6, "grupo=%d" % _enemigos().size())
	_gerente.call("retirar_grupo")
	await _esperar_frames(2)
	_check("11. Limpieza final del grupo de pruebas", _enemigos().is_empty())

	# ---------------------------------------------------------------- 12. proyecto
	var principal: String = str(ProjectSettings.get_setting("application/run/main_scene"))
	_check("12. La escena principal del proyecto sigue siendo IntroVideo",
			principal == ESCENA_PRINCIPAL, principal)
	_check("12. La escena del mundo existe", ResourceLoader.exists(ESCENA_MUNDO))
	var texto := ""
	var f := FileAccess.open(ESCENA_MUNDO, FileAccess.READ)
	if f != null:
		texto = f.get_as_text()
	_check("12. El mundo principal integra el CombatManager",
			texto.contains("name=\"CombatManager\""))
	_check("12. El mundo principal integra el gerente de enemigos (G)",
			texto.contains("name=\"EnemigosPrueba\""))
	_check("12. El mundo principal conserva el barco y el muelle de main",
			texto.contains("name=\"Barco\"") and texto.contains("name=\"Muelle\""))

	print("[TEST] ===== RESULTADO: %d OK, %d FALLOS =====" % [_pasadas, _falladas])
	get_tree().quit(1 if _falladas > 0 else 0)