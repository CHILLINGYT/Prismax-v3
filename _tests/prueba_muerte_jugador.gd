extends Node3D

# PRUEBA DEL SISTEMA DE MUERTE DEL JUGADOR (permanente).
#
# Comprueba, en vivo y con el jugador REAL en una escena mínima (suelo + jugador):
#   1. Los FBX de muerte/morido y sus clips reales (esqueleto Mixamo, duraciones).
#   2. Recibir daño SIN cumplir la condición de muerte no activa nada.
#   3. La condición real: muerte sólo con vida Y resistencia a cero; con reserva
#      defensiva el personaje NO muere (última reserva) y se recupera.
#   4. La secuencia: `muerte` el clip entero -> `morido` en bucle -> fundido a
#      negro -> pantalla final con el logo y los DOS botones con sus sonidos.
#   5. Bloqueo total de controles durante la secuencia.
#   6. NUEVA PARTIDA lleva al flujo real (pantalla de carga -> mundo).
#
# La prueba blanca de la "última reserva" escribe directamente el estado interno
# de EstadisticasJugador (vida 1, resistencia 100) porque esa combinación no se
# alcanza jugando con el reparto 80/20 actual; sirve para fijar la REGLA.

const JUGADOR := preload("res://personaje/base/escenas/leo_jugador.tscn")
const ESC_MUERTE := "res://personaje/transformaciones/Muerte.fbx"
const ESC_MORIDO := "res://personaje/transformaciones/Morido.fbx"
const ESCENA_MUNDO := "res://ziba/escenas/ziba_prototipo.tscn"
const ESCENA_CARGA := "res://ui/scenes/LoadingScreen.tscn"
const LARGO_MUERTE := 4.367
const LARGO_MORIDO := 0.067


## Observador fuera de la escena actual: sobrevive al cambio de escena y comprueba
## a dónde ha ido el botón (la escena actual se libera al cambiar, así que la
## comprobación no puede vivir en la prueba). El mundo tarda en generarse y bloquea
## el hilo: por eso se mira el DESTINO de la pantalla de carga en cuanto se puede.
class Observador extends Node:
	var esperado := ""
	func _ready() -> void:
		var visto := PackedStringArray()
		var destino := ""
		var t := 0.0
		while t < 22.0:
			await get_tree().process_frame
			t += get_process_delta_time()
			if destino == "":
				destino = LoadingScreen.destino
			var actual := get_tree().current_scene
			var ruta := "" if actual == null else actual.scene_file_path
			if ruta != "" and (visto.is_empty() or visto[visto.size() - 1] != ruta):
				visto.append(ruta)
				print("[OBS] escena actual: '%s' (a los %.1f s)" % [ruta, t])
			if ruta == esperado:
				break
		var ok := destino == esperado or (visto.size() > 0 and visto[visto.size() - 1] == esperado)
		print("[OBS] escena final='%s' | pantalla de carga -> '%s' (esperado '%s') | recorrido=%s -> %s" % [
				"" if visto.is_empty() else visto[visto.size() - 1], destino, esperado,
				str(visto), "OK" if ok else "FALLO"])
		print("[OBS] ===== OBSERVADOR: %s =====" % ("OK" if ok else "FALLO"))
		get_tree().quit(0 if ok else 1)

var _jug: CharacterBody3D
var _stats: EstadisticasJugador
var _pantalla: DeathScreen
var _ok := 0
var _fallos := 0
var _t_muerte := 0
var _t_morido := 0
var _cadera_pie := 0.0


func _check(nombre: String, condicion: bool, detalle: String = "") -> void:
	if condicion:
		_ok += 1
		print("[OK]    %s%s" % [nombre, (" — " + detalle) if detalle != "" else ""])
	else:
		_fallos += 1
		print("[FALLO] %s%s" % [nombre, (" — " + detalle) if detalle != "" else ""])


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame


func _segundos(s: float) -> void:
	var t := 0.0
	while t < s:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()


func _animador_de(nodo: Node) -> AnimationPlayer:
	if nodo == null:
		return null
	for n in nodo.find_children("*", "AnimationPlayer", true, false):
		return n as AnimationPlayer
	return null


func _esqueleto_de(nodo: Node) -> Skeleton3D:
	if nodo == null:
		return null
	for n in nodo.find_children("*", "Skeleton3D", true, false):
		return n as Skeleton3D
	return null


func _fbx(ruta: String) -> Dictionary:
	var ps := load(ruta) as PackedScene
	if ps == null:
		return {}
	var raiz := ps.instantiate()
	var anim := _animador_de(raiz)
	var out := {"raiz": raiz, "anim": anim, "skel": _esqueleto_de(raiz)}
	out["clips"] = anim.get_animation_list() if anim != null else PackedStringArray()
	return out


func _ready() -> void:
	call_deferred("_correr")


func _correr() -> void:
	# ---------------------------------------------------- 1. Los FBX de muerte
	var m := _fbx(ESC_MUERTE)
	var mo := _fbx(ESC_MORIDO)
	_check("1. Muerte.fbx y Morido.fbx se cargan como escena", not m.is_empty() and not mo.is_empty())
	var sk_m: Skeleton3D = m.get("skel")
	var an_m: AnimationPlayer = m.get("anim")
	var sk_mo: Skeleton3D = mo.get("skel")
	var an_mo: AnimationPlayer = mo.get("anim")
	_check("1. Traen esqueleto Mixamo (65 huesos) y AnimationPlayer",
			sk_m != null and sk_m.get_bone_count() == 65 and an_m != null \
			and sk_mo != null and sk_mo.get_bone_count() == 65 and an_mo != null,
			"huesos=%d/%d" % [sk_m.get_bone_count() if sk_m != null else -1,
					sk_mo.get_bone_count() if sk_mo != null else -1])
	_check("1. El hueso raíz es mixamorig_Hips en los dos",
			sk_m != null and sk_m.find_bone("mixamorig_Hips") >= 0 \
			and sk_mo != null and sk_mo.find_bone("mixamorig_Hips") >= 0)
	var largo_m := 0.0
	var largo_mo := 0.0
	if an_m != null and an_m.get_animation_list().size() > 0:
		largo_m = an_m.get_animation(an_m.get_animation_list()[0]).length
	if an_mo != null and an_mo.get_animation_list().size() > 0:
		largo_mo = an_mo.get_animation(an_mo.get_animation_list()[0]).length
	_check("1. Los clips miden lo que se midió al importarlos (%.3f / %.3f s)" % [largo_m, largo_mo],
			absf(largo_m - LARGO_MUERTE) < 0.1 and absf(largo_mo - LARGO_MORIDO) < 0.05)
	if m.get("raiz") != null:
		(m.get("raiz") as Node).free()
	if mo.get("raiz") != null:
		(mo.get("raiz") as Node).free()

	# ---------------------------------------------------- Montaje del jugador
	var suelo := StaticBody3D.new()
	suelo.collision_layer = 1
	suelo.collision_mask = 0
	var fs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(60, 1, 60)
	fs.shape = bs
	fs.position = Vector3(0, -0.5, 0)
	suelo.add_child(fs)
	add_child(suelo)

	_jug = JUGADOR.instantiate() as CharacterBody3D
	add_child(_jug)
	await _frames(8)
	_stats = _jug.get_node_or_null("Estadisticas") as EstadisticasJugador
	_check("2. El jugador real trae el sistema de vida/escudo", _stats != null and _jug.is_on_floor(),
			"vida=%.0f escudo=%.0f" % [
					_stats.vida if _stats != null else -1.0,
					_stats.resistencia if _stats != null else -1.0])
	var humano := _jug.get_node_or_null("Humano") as Node3D
	# El reproductor del JUEGO de esa forma (no el que los modelos FBX traen dentro).
	var anim_act: AnimationPlayer = _jug.anim_humano
	var sk_pie := _esqueleto_de(humano)
	# Altura MUNDIAL de la cadera de pie (referencia real, sin mezclar espacios).
	if sk_pie != null and sk_pie.find_bone("mixamorig_Hips") >= 0:
		_cadera_pie = (sk_pie.global_transform * sk_pie.get_bone_global_pose(
				sk_pie.find_bone("mixamorig_Hips")).origin).y
	_check("2. Punto de partida: el personaje está de pie (cadera alta)", _cadera_pie > 0.7,
			"cadera de pie y=%.2f m" % _cadera_pie)
	# ------------------------------------------------- 2. Daño sin muerte
	var murios := [0]
	_stats.murio.connect(func() -> void: murios[0] += 1)
	_stats.recibir_danio(25.0)
	await _frames(3)
	_check("2. Daño sin agotar vida y escudo: NO hay muerte ni animación",
			not _stats.muerto and int(_jug._muerte_estado) == 0 \
			and anim_act != null and not anim_act.has_animation("muerte") \
			and murios[0] == 0,
			"vida=%.0f escudo=%.0f muerto=%s señal=%d" % [_stats.vida, _stats.resistencia,
					str(_stats.muerto), murios[0]])

	# ------------------------------- 3. Condición real (regla de la última reserva)
	# Estado escrito a mano: vida 1 y resistencia 100 (no alcanzable jugando hoy).
	var est: Dictionary = _stats._estados[_stats.forma_actual()]
	est["vida"] = 1.0
	est["resistencia"] = 100.0
	_stats._sincronizar_activa()
	_stats.recibir_danio(25.0)
	await _frames(2)
	_check("3. Con reserva defensiva NO muere (última reserva: vida 0 y escudo > 0)",
			not _stats.muerto and _stats.vida <= 0.0 and _stats.resistencia > 0.0 and murios[0] == 0,
			"vida=%.0f escudo=%.0f" % [_stats.vida, _stats.resistencia])
	# La reserva aguanta los golpes: el personaje puede recuperarse.
	var vida_tras: float = _stats.vida
	_stats.curar(20.0)
	await _frames(2)
	_check("3. La última reserva permite recuperarse (curar sube la vida)",
			_stats.vida > vida_tras, "vida %.0f -> %.0f" % [vida_tras, _stats.vida])
	# Vaciar la reserva: ahora sí muere.
	var golpes := 0
	while not _stats.muerto and golpes < 40:
		_stats.recibir_danio(25.0)
		golpes += 1
		await _frames(2)
	_t_muerte = Time.get_ticks_msec()
	_check("3. La muerte llega justo cuando vida Y escudo están a cero",
			_stats.muerto and _stats.vida <= 0.0 and _stats.resistencia <= 0.0 and murios[0] == 1,
			"vida=%.0f escudo=%.0f señal=%d golpes=%d" % [_stats.vida, _stats.resistencia,
					murios[0], golpes])
	_check("3. El estado del jugador pasa a MURIENDO una sola vez",
			int(_jug._muerte_estado) == 1, "estado=%d" % int(_jug._muerte_estado))

	# ------------------------------------------------- 4. Animación de muerte
	var clips_ok: bool = anim_act != null and anim_act.has_animation("muerte") \
			and anim_act.has_animation("morido")
	_check("4. El clip real de muerte se copió al esqueleto de la forma activa", clips_ok,
			"clips=%s" % (str(anim_act.get_animation_list()) if anim_act != null else "—"))
	_check("4. `muerte` empieza desde el principio (no a mitad de clip)",
			anim_act != null and anim_act.current_animation == "muerte" \
			and anim_act.current_animation_position < 1.0,
			"clip=%s pos=%.2f" % [str(anim_act.current_animation) if anim_act != null else "",
					anim_act.current_animation_position if anim_act != null else -1.0])
	# Otros esqueletos de formas disponibles: el retarget casa por nombre de hueso.
	var aqu := _jug.get_node_or_null("Acuatico") as Node3D
	var an_aq: AnimationPlayer = _jug.anim_acuatico
	var sk_aq := _esqueleto_de(aqu)
	var casaron := 0
	if an_aq != null and sk_aq != null:
		if an_aq.has_animation("muerte"):
			casaron += 1
		elif _jug._retarget_clip(_jug._clip_de_fbx(ESC_MUERTE), an_aq, sk_aq, &"muerte", false,
				_jug._factor_unidades_fbx(ESC_MUERTE, sk_aq)):
			casaron += 1
			var lib := an_aq.get_animation_library(&"")
			if lib != null and lib.has_animation(&"muerte"):
				lib.remove_animation(&"muerte")
	_check("4. El mismo clip de muerte encaja en el esqueleto de la forma acuática",
			casaron == 1, "huesos=%d" % [sk_aq.get_bone_count() if sk_aq != null else -1])

	# ------------------------------------------------- 5. Bloqueo de controles
	var pos0: Vector3 = _jug.global_position
	var forma0: int = int(_jug.forma)
	var pos_clip0: float = anim_act.current_animation_position
	Input.action_press("mover_adelante")
	Input.action_press("saltar")
	Input.action_press("atacar")
	Input.action_press("correr")
	var ev := InputEventAction.new()
	ev.action = "menu_transformaciones"
	ev.pressed = true
	Input.parse_input_event(ev)
	var ev2 := InputEventAction.new()
	ev2.action = "dano_prueba"
	ev2.pressed = true
	Input.parse_input_event(ev2)
	await _segundos(0.7)
	Input.action_release("mover_adelante")
	Input.action_release("saltar")
	Input.action_release("atacar")
	Input.action_release("correr")
	_check("5. Nada detiene la secuencia: ni movimiento, ni salto, ni ataque, ni F",
			int(_jug._muerte_estado) == 1 \
			and anim_act.current_animation == "muerte" \
			and anim_act.current_animation_position > pos_clip0,
			"estado=%d clip=%s pos=%.2f" % [int(_jug._muerte_estado),
					str(anim_act.current_animation), anim_act.current_animation_position])
	_check("5. El cuerpo no se mueve ni se transforma durante la muerte",
			pos0.distance_to(_jug.global_position) < 0.15 and int(_jug.forma) == forma0,
			"delta=%.3f m forma=%d" % [pos0.distance_to(_jug.global_position), int(_jug.forma)])
	_check("5. El daño posterior no reinicia nada (sigue muerto y sin nuevas señales)",
			_stats.muerto and murios[0] == 1, "señal=%d" % murios[0])

	# ------------------------------------------- 6. Fin del clip -> morido en bucle
	var t := 0.0
	while int(_jug._muerte_estado) == 1 and t < 8.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	_t_morido = Time.get_ticks_msec()
	var dur := float(_t_morido - _t_muerte) / 1000.0
	_check("6. `muerte` se reprodujo COMPLETA antes de pasar a morido (%.2f s)" % dur,
			int(_jug._muerte_estado) == 2 and absf(dur - largo_m) < 0.6,
			"estado=%d duración=%.2f s (clip=%.2f s)" % [int(_jug._muerte_estado), dur, largo_m])
	_check("6. Ahora corre `morido` en bucle infinito",
			anim_act.current_animation == "morido" and anim_act.is_playing() \
			and anim_act.get_animation("morido").loop_mode == Animation.LOOP_LINEAR,
			"clip=%s loop=%d" % [str(anim_act.current_animation),
					int(anim_act.get_animation("morido").loop_mode)])
	await _segundos(0.8)
	_check("6. Sigue en `morido` (no se reinicia ni salta a otra animación)",
			anim_act.current_animation == "morido" and int(_jug._muerte_estado) == 2)
	# El cadáver está en el suelo y en su sitio. Se mide en el MUNDO (la verdad
	# física: de pie la cadera está a ≈1.16 m y tumbado debe caer a ≲0.4 m).
	var sk_act := _esqueleto_de(humano)
	var cadera_y := 99.0
	if sk_act != null:
		var i_cad := sk_act.find_bone("mixamorig_Hips")
		if i_cad >= 0:
			cadera_y = (sk_act.global_transform * sk_act.get_bone_global_pose(i_cad).origin).y
	_check("6. El cuerpo queda en el SUELO (la cadera baja desde la altura de pie)",
			cadera_y < 0.6 and cadera_y > -0.2 and _cadera_pie - cadera_y > 0.5,
			"cadera tumbado y=%.2f m (de pie %.2f m)" % [cadera_y, _cadera_pie])
	_check("6. Sin teletransportes: sigue donde murió",
			pos0.distance_to(_jug.global_position) < 0.2,
			"delta=%.3f m" % pos0.distance_to(_jug.global_position))

	# ------------------------------------------------- 7. Fundido y pantalla final
	_pantalla = null
	var host := _jug.get_parent()
	for n in host.get_children():
		if n is DeathScreen:
			_pantalla = n as DeathScreen
	_check("7. La pantalla final existe (CanvasLayer por encima de todo)",
			_pantalla != null and _pantalla.layer >= 100,
			"layer=%d" % [_pantalla.layer if _pantalla != null else -1])
	var negro: ColorRect = null
	if _pantalla != null:
		negro = _pantalla.get_node_or_null("Negro") as ColorRect
	var fundido_ok := false
	var t2 := 0.0
	while t2 < 6.0:
		await get_tree().physics_frame
		t2 += get_physics_process_delta_time()
		if negro != null and negro.modulate.a >= 0.999:
			fundido_ok = true
			break
	_check("7. El fundido llega a NEGRO OPACO (cubre mundo, ciudad e interfaz)",
			fundido_ok, "alpha=%.3f tras %.1f s" % [negro.modulate.a if negro != null else -1.0, t2])
	# La aparición del contenido es corta pero posterior al fundido: se espera a
	# que termine antes de comprobar que el logo y los botones están a la vista.
	var centro := _pantalla.get_node_or_null("Centro") as Control if _pantalla != null else null
	var t3 := 0.0
	while t3 < 3.0 and (centro == null or centro.modulate.a < 0.9):
		await get_tree().physics_frame
		t3 += get_physics_process_delta_time()
	var centro_visible := centro != null and centro.visible and centro.modulate.a > 0.9 \
			and negro != null and negro.modulate.a > 0.999
	_check("7. Sobre el negro aparecen el logo y los botones (solo negro + interfaz)",
			centro_visible, "alpha centro=%.2f tras %.1f s" % [
					centro.modulate.a if centro != null else -1.0, t3])
	var items := _pantalla.get_node_or_null("%Items") as VBoxContainer if _pantalla != null else null
	_check("7. Hay EXACTAMENTE dos botones, en orden: NUEVA PARTIDA y VOLVER AL MENÚ",
			items != null and items.get_child_count() == 2 \
			and _texto_fila(items, 0) == "NUEVA PARTIDA" and _texto_fila(items, 1) == "VOLVER AL MENÚ",
			"%s / %s" % [_texto_fila(items, 0), _texto_fila(items, 1)])
	var logo := _pantalla.get_node_or_null("Centro/Columna/LogoBox/Logo") if _pantalla != null else null
	_check("7. El logo es el REAL del proyecto (GameLogo.tscn con su prisma y su nombre)",
			logo != null and logo.get_node_or_null("VBox/Row/Prism") != null \
			and logo.get_node_or_null("VBox/Name") != null,
			"texto='%s'" % (logo.get_node("VBox/Name").text if logo != null \
					and logo.get_node_or_null("VBox/Name") != null else "—"))

	# ------------------------------------------------- 8. Sonidos de los botones
	var reproductor := SonidoUI.get_node_or_null("ReproductorUI") as AudioStreamPlayer
	var sonido_ok := await _probar_sonido(items, 1, reproductor, "cursor")
	_check("8. Pasar el cursor por un botón reproduce el sonido del menú (cursor.wav)",
			sonido_ok, "stream=%s" % _ruta_stream(reproductor))
	# Pulsar VOLVER AL MENÚ en OTRA prueba (esta comprueba NUEVA PARTIDA). Aquí se
	# verifica el CLICK con la fila 0 (que es además la que inicia la partida).
	var click_ok := await _probar_clic(items, 0, reproductor)
	_check("8. Pulsar un botón reproduce el click del menú (click.wav)", click_ok,
			"stream=%s" % _ruta_stream(reproductor))

	# ------------------------------------------------- 9. NUEVA PARTIDA -> flujo real
	var obs := Observador.new()
	obs.esperado = ESCENA_MUNDO
	get_tree().root.add_child.call_deferred(obs)
	print("[QA] ===== MUERTE DEL JUGADOR: %d OK / %d FALLOS (la última prueba la cierra el observador) =====" % [_ok, _fallos])


func _texto_fila(items: VBoxContainer, i: int) -> String:
	if items == null or i >= items.get_child_count():
		return "—"
	var l := items.get_child(i).get_node_or_null("Label") as Label
	return "—" if l == null else l.text


func _ruta_stream(p: AudioStreamPlayer) -> String:
	if p == null or p.stream == null:
		return "—"
	return p.stream.resource_path


## Simula pasar el cursor por una fila y comprueba que suena el cursor del menú.
func _probar_sonido(items: VBoxContainer, i: int, p: AudioStreamPlayer, esperado: String) -> bool:
	if items == null or i >= items.get_child_count() or p == null:
		return false
	var fila := items.get_child(i) as Control
	if fila == null:
		return false
	if p.playing:
		p.stop()
	await _frames(2)
	fila.mouse_entered.emit()
	await _frames(3)
	return p.playing and p.stream != null and p.stream.resource_path.contains(esperado)


## Simula un clic de ratón en una fila y comprueba que suena el click del menú.
func _probar_clic(items: VBoxContainer, i: int, p: AudioStreamPlayer) -> bool:
	if items == null or i >= items.get_child_count() or p == null:
		return false
	var fila := items.get_child(i) as Control
	if fila == null:
		return false
	if p.playing:
		p.stop()
	await _frames(2)
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	fila.gui_input.emit(ev)
	await _frames(3)
	return p.playing and p.stream != null and p.stream.resource_path.contains("click")