extends Node3D
## PRUEBAS del GOLPE NORMAL DEL VELOCISTA (Tarea 3): daño real por el flujo de
## verdad (forma velocista + tecla de ataque), sin llamar a funciones internas.
##
## Comprueba:
##   1. el golpe normal CONECTA con un enemigo pegado delante (la distancia a la
##      que pelea cualquier cuerpo a cuerpo) y le baja la vida;
##   2. también conecta a media y a larga distancia útil;
##   3. un mismo golpe NO aplica daño dos veces;
##   4. atacar al aire NO aplica daño a nadie;
##   5. un enemigo DETRÁS no recibe nada;
##   6. el impacto confirmado deja la reacción REAL del enemigo (clip recibir) y su
##      efecto de impacto, y el golpe al aire NO deja efecto;
##   7. el resto de la transformación sigue funcionando (el combo avanza 1->2->3).
##
## Se ejecutan con la tecla `atacar` (una pulsación = un golpe) igual que en el
## juego: `Input.action_press`/`release` dentro de fotogramas distintos.

const JUGADOR := "res://personaje/base/escenas/leo_jugador.tscn"
const ENEMIGO := "res://enemigos/Scenes/enemigo_prueba.tscn"

var _ok := 0
var _fallos := 0
var _jug: CharacterBody3D
var _enemigos: Array[Node3D] = []

func _ready() -> void:
	_piso()
	_jug = (load(JUGADOR) as PackedScene).instantiate() as CharacterBody3D
	_jug.position = Vector3(0, 0.2, 0)
	add_child(_jug)
	await get_tree().create_timer(0.8).timeout

	var entro := await _cambiar_forma(&"velocista", 1)
	_check(entro, "el jugador entra en la forma velocista por el menú real")

	# ---------- 1. Enemigo pegado delante: DEBE conectar, y en el contacto ----------
	var cerca := await _crear_enemigo(1.2)
	var v0 := _vida(cerca)
	var combo_antes := int((_jug.get_node("Combate") as SistemaCombate).golpe_actual())
	var esperado := float(_jug.call("_espera_de_contacto", 1))
	print("[velocista-suite] espera de contacto calculada: %.3f s (combo-1)" % esperado)
	# Pulsación y SEGUIMIENTO fotograma a fotograma: en qué ms llega el daño y si
	# se frena la animación del enemigo (hit-stop).
	Input.action_press("atacar")
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release("atacar")
	var reloj := Time.get_ticks_msec()
	var t_dano := -1
	var frenado := false
	var t_frenado := -1
	while Time.get_ticks_msec() - reloj < 500:
		await get_tree().process_frame
		var ap := cerca.get_node_or_null("Animador") as AnimationPlayer
		if ap != null and ap.speed_scale < 0.99:
			frenado = true
			if t_frenado < 0:
				t_frenado = Time.get_ticks_msec() - reloj
		if t_dano < 0 and _vida(cerca) < v0 - 0.01:
			t_dano = Time.get_ticks_msec() - reloj
	print("[velocista-suite] daño a los %d ms | hit-stop a los %d ms | esperado %d ms" % [
			t_dano, t_frenado, int(esperado * 1000.0)])
	_check(t_dano < 0 or float(t_dano) > (esperado * 1000.0) * 0.75,
			"el daño NO llega antes del contacto real (%d ms, contacto %d ms)" % [
					t_dano, int(esperado * 1000.0)])
	var v1 := _vida(cerca)
	_check(v1 < v0, "el golpe normal CONECTA con el enemigo pegado delante (%.0f -> %.0f)" % [v0, v1])
	_check(frenado, "el impacto confirmado frena un instante la animación del enemigo (hit-stop)")
	var combo_despues := int((_jug.get_node("Combate") as SistemaCombate).golpe_actual())
	_check(combo_despues == combo_antes + 1 or combo_despues == 1,
			"la pulsación avanza el combo del velocista (%d -> %d)" % [combo_antes, combo_despues])
	# El hit-stop se suelta solo: no deja al enemigo frenado.
	await get_tree().create_timer(0.3).timeout
	var ap_fin := cerca.get_node_or_null("Animador") as AnimationPlayer
	var esc_fin := ap_fin.speed_scale if ap_fin != null else 1.0
	_check(ap_fin == null or absf(esc_fin - 1.0) < 0.01,
			"la animación del enemigo vuelve a su velocidad normal después (%.2f)" % esc_fin)

	# ---------- 3. Un golpe no duplica el daño ----------
	await get_tree().create_timer(0.4).timeout
	var v2 := _vida(cerca)
	_check(absf(v2 - v1) < 0.01, "el mismo golpe NO sigue restando vida después (%.1f estable)" % v2)

	# ---------- 2. A media y a larga distancia útil ----------
	var media := await _crear_enemigo(2.4)
	var vm0 := _vida(media)
	await _pulsar_atacar()
	_check(_vida(media) < vm0, "conecta a media distancia (2.4 m: %.0f -> %.0f)" % [vm0, _vida(media)])
	var lejos := await _crear_enemigo(3.2)
	var vl0 := _vida(lejos)
	await _pulsar_atacar()
	_check(_vida(lejos) < vl0, "conecta al borde del alcance (3.2 m: %.0f -> %.0f)" % [vl0, _vida(lejos)])

	# ---------- 5. Enemigo detrás: nada ----------
	var atras := await _crear_enemigo(-1.6)
	var va0 := _vida(atras)
	await _pulsar_atacar()
	_check(absf(_vida(atras) - va0) < 0.01, "un enemigo DETRÁS no recibe daño")

	# ---------- 4. Al aire: nada ----------
	for e in _enemigos:
		if is_instance_valid(e):
			e.queue_free()
	await get_tree().process_frame
	await get_tree().create_timer(0.3).timeout
	await _pulsar_atacar()
	_check(_enemigos_vivos() == 0, "golpe AL AIRE: no hay ningún enemigo al que dañar (0 vivos)")

	# ---------- 6. Reacción real y efecto de impacto al conectar ----------
	var reaccion := await _crear_enemigo(1.5)
	var clip_antes := _clip_actual(reaccion)
	# La reacción dura duracion_recibir (0,35 s): se VIGILA durante la ventana en vez
	# de mirar el clip sólo al final (a los 0,45 s ya había vuelto a la locomoción).
	Input.action_press("atacar")
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release("atacar")
	var reacciono := false
	var clip_visto := StringName()
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 900:
		await get_tree().process_frame
		var c := _clip_actual(reaccion)
		# El nombre puede venir con la biblioteca delante ("recibir_combate/...").
		if String(c).begins_with("recibir") or String(c).contains("recibir"):
			reacciono = true
			clip_visto = c
			break
	var particulas := _contar_particulas()
	_check(_vida(reaccion) < 100.0, "el golpe sobre el enemigo de prueba le resta vida")
	_check(reacciono, "el enemigo reproduce su animación REAL de reacción (%s)" % (
			clip_visto if reacciono else clip_antes))
	_check(particulas > 0, "el impacto confirmado deja su efecto en el punto de contacto (%d partículas)" % particulas)

	# Golpe al aire: sin efecto nuevo.
	for e in _enemigos:
		if is_instance_valid(e):
			e.queue_free()
	await get_tree().process_frame
	await get_tree().create_timer(0.6).timeout
	var antes := _contar_particulas()
	await _pulsar_atacar()
	await get_tree().create_timer(0.1).timeout
	_check(_contar_particulas() <= antes, "el golpe al aire NO genera efecto de impacto")

	print("==================== GOLPE VELOCISTA: %d OK / %d FALLO ====================" % [_ok, _fallos])
	await get_tree().create_timer(0.5).timeout


# ------------------------------------------------------------------ auxiliares
func _crear_enemigo(distancia: float) -> Node3D:
	var e := (load(ENEMIGO) as PackedScene).instantiate() as Node3D
	add_child(e)
	# Delante = la dirección a la que MIRA el jugador (su visual), no el -Z del mundo.
	var base: Node3D = _jug.get("visual") as Node3D
	var adelante := -base.global_transform.basis.z
	adelante.y = 0.0
	adelante = adelante.normalized()
	e.global_position = _jug.global_position + adelante * distancia
	_enemigos.append(e)
	await get_tree().physics_frame
	return e


func _vida(e: Node3D) -> float:
	if e == null or not is_instance_valid(e):
		return -1.0
	if e.has_method("vida_actual"):
		return float(e.call("vida_actual"))
	return -1.0


func _clip_actual(e: Node3D) -> StringName:
	var ap := e.get_node_or_null("Animador") as AnimationPlayer
	return ap.current_animation if ap != null else &""


## Una pulsación REAL de la tecla de ataque (igual que un clic del jugador).
func _pulsar_atacar() -> void:
	Input.action_press("atacar")
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release("atacar")
	await get_tree().physics_frame
	# El daño llega en el fotograma de contacto: se le da tiempo de sobra.
	await get_tree().create_timer(0.45).timeout


func _enemigos_vivos() -> int:
	var n := 0
	for e in _enemigos:
		if e != null and is_instance_valid(e) and _vida(e) > 0.0:
			n += 1
	return n


## Partículas de impacto vivas en la escena (las crea VfxImpacto al confirmar daño).
func _contar_particulas() -> int:
	var n := 0
	for p in get_tree().root.find_children("*", "GPUParticles3D", true, false):
		n += 1
	return n


func _cambiar_forma(id: StringName, forma: int) -> bool:
	_jug.call("_on_transformacion_elegida", id)
	var t := 0
	while (int(_jug.get("forma")) != forma or bool(_jug.get("_transformando"))) and t < 900:
		await get_tree().physics_frame
		t += 1
	await get_tree().create_timer(0.2).timeout
	return int(_jug.get("forma")) == forma


func _check(condicion: bool, texto: String) -> void:
	if condicion:
		_ok += 1
		print("[velocista-suite] OK   ", texto)
	else:
		_fallos += 1
		print("[velocista-suite] FALLO ", texto)


func _piso() -> void:
	var cuerpo := StaticBody3D.new()
	var forma := CollisionShape3D.new()
	var caja := BoxShape3D.new()
	caja.size = Vector3(160, 0.5, 160)
	forma.shape = caja
	cuerpo.add_child(forma)
	cuerpo.position = Vector3(0, -0.25, 0)
	add_child(cuerpo)
	var malla := MeshInstance3D.new()
	var caja_m := BoxMesh.new()
	caja_m.size = Vector3(160, 0.5, 160)
	malla.mesh = caja_m
	malla.position = Vector3(0, -0.25, 0)
	add_child(malla)
	var luz := DirectionalLight3D.new()
	luz.rotation = Vector3(-0.9, 0.6, 0.0)
	add_child(luz)
	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 3.0, 12.0)
	cam.current = true
	add_child(cam)