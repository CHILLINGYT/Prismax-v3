extends Node3D
## PRUEBAS del CONTACTO DE GOLPES de todas las transformaciones (Tarea 6):
##  A · el módulo compartido `ContactoGolpe` (superficie, arco, banda vertical, vivo);
##  B · el golpe del VELOCISTA con ese criterio: alcanza por la SUPERFICIE del
##      objetivo (radio real), no golpea lo que está detrás ni lo que está fuera de
##      la banda vertical;
##  C · el CONTRATO DE GOLPE del jugador (centro y radio reales de su cápsula), que
##      es lo que ahora usan los enemigos para medir arco y alcance vertical;
##  D · los ATAQUES ENEMIGOS: el cuerpo a cuerpo conecta con el jugador a su alcance
##      normal y NO conecta si el jugador sube fuera de su banda, con lo que se
##      comprueba que el criterio sigue siendo el suyo y el de siempre en el suelo;
##  E · las otras formas conservan sus criterios ya verificados (combate con su
##      config de arco/distancia, vuelo con su alcance y tolerancia, Fuerza con su
##      esfera física real).

const JUGADOR := "res://personaje/base/escenas/leo_jugador.tscn"
const ENEMIGO := "res://Enemigos Prueba/Scenes/enemigo_prueba.tscn"
const GERENTE := "res://Enemigos Prueba/Scripts/gerente_enemigos_prueba.gd"
const CONFIG_ATAQUE := "res://personaje/transformaciones/transformacion ataque/resources/combat_config.tres"
const GROUND_COMBAT := "res://personaje/transformaciones/vuelo/scripts/ground_combat.gd"

## Objetivo de mentira con el mismo contrato que los enemigos del proyecto
## (centro de golpe a 1 m de los pies y radio 0.5): permite medir las primitivas del
## módulo con números exactos.
class FalsoObjetivo extends Node3D:
	var radio := 0.5
	var vivo := true
	func get_hit_center() -> Vector3:
		return global_position + Vector3.UP * 1.0
	func get_hit_radius() -> float:
		return radio
	func is_alive() -> bool:
		return vivo

var _ok := 0
var _fallos := 0
var _jugador: CharacterBody3D
var _stats: EstadisticasJugador

func _ready() -> void:
	_piso()
	_jugador = (load(JUGADOR) as PackedScene).instantiate() as CharacterBody3D
	_jugador.position = Vector3(0, 0.1, 0)
	add_child(_jugador)
	await get_tree().create_timer(0.6).timeout
	_stats = _jugador.get_node_or_null("Estadisticas") as EstadisticasJugador

	# ---------------- A. Primitivas del módulo compartido ----------------
	var falso := FalsoObjetivo.new()
	falso.position = Vector3(0, 0, -2.0)
	add_child(falso)
	var punto := Vector3(0, 1.0, 0)   # el centro de golpe del atacante
	var d := ContactoGolpe.distancia_de_contacto(falso, punto)
	_check(absf(d - 1.5) <= 0.001, "A distancia de SUPERFICIE = 2.0 - 0.5 = 1.5 m (%.3f)" % d)
	var d2 := ContactoGolpe.distancia_de_contacto(falso, punto, 1.0, 0.4)
	_check(absf(d2 - 1.1) <= 0.001, "A con el volumen del atacante (0.4): 1.1 m (%.3f)" % d2)
	var contacto := ContactoGolpe.punto_de_contacto(falso, punto)
	_check(absf(contacto.distance_to(ContactoGolpe.centro(falso)) - 0.5) < 0.12,
			"A el punto de contacto cae sobre la SUPERFICIE (%.3f m del centro)" %
			contacto.distance_to(ContactoGolpe.centro(falso)))
	_check(ContactoGolpe.en_arco(falso, punto, Vector3(0, 0, -1), 0.2),
			"A un objetivo DELANTE entra en el arco")
	_check(not ContactoGolpe.en_arco(falso, punto, Vector3(0, 0, 1), 0.2),
			"A el mismo objetivo DETRÁS queda fuera del arco")
	_check(ContactoGolpe.en_banda_vertical(falso, _jugador, 2.2),
			"A a la misma altura entra en la banda vertical")
	falso.position = Vector3(0, 4.0, -2.0)
	_check(not ContactoGolpe.en_banda_vertical(falso, _jugador, 2.2),
			"A 4 m por encima queda fuera de la banda vertical")
	falso.position = Vector3(0, 0, -2.0)
	falso.vivo = false
	_check(not ContactoGolpe.objetivo_valido(falso, _jugador), "A un objetivo derrotado no es válido")
	falso.vivo = true
	# Para `alcanza()` el objetivo se pone DENTRO del alcance de contacto (el puño
	# aporta su volumen y el objetivo el suyo): 1.0 - 0.5 - 1.0 < 0.
	falso.position = Vector3(0, 0, -1.0)
	_check(ContactoGolpe.alcanza(falso, _jugador, punto, 1.0, Vector3(0, 0, -1), 0.2, 2.2),
			"A `alcanza()` reúne los cuatro criterios (cerca, delante, a nivel, vivo)")
	_check(not ContactoGolpe.alcanza(falso, _jugador, punto, 0.2, Vector3(0, 0, -1), 0.2, 2.2),
			"A y falla si no llega (radio de golpe pequeño)")
	falso.queue_free()
	await get_tree().process_frame

	# ---------------- B. El golpe del VELOCISTA con ese criterio ----------------
	var e := (load(ENEMIGO) as PackedScene).instantiate() as Node3D
	add_child(e)
	await get_tree().process_frame
	var radio_e := 0.5
	if e.has_method("get_hit_radius"):
		radio_e = float(e.call("get_hit_radius"))
	var alcanza := 1.9 + 1.0 + radio_e     # alcance + volumen del puño + radio del enemigo
	print("[contacto-suite] INFO velocista: alcance útil %.2f m (enemigo con radio %.2f)" % [alcanza, radio_e])
	# El "adelante" del golpe es el del VISUAL del jugador (el controlador lo gira con
	# la cámara): los enemigos se colocan sobre ESE adelante, no sobre el -Z del mundo.
	var base_jug: Node3D = _jugador.get("visual") as Node3D
	var frente := -base_jug.global_transform.basis.z
	frente.y = 0.0
	frente = frente.normalized()

	# (1) delante y a la distancia de siempre: conecta
	e.global_position = _jugador.global_position + frente * 2.5
	await get_tree().physics_frame
	var vida0 := float(e.call("vida_actual"))
	_jugador.call("_aplicar_impacto_velocista", 0)
	await get_tree().physics_frame
	var vida1 := float(e.call("vida_actual"))
	_check(vida1 < vida0, "B el golpe del velocista CONECTA por delante a 2.5 m (%.1f -> %.1f de vida)" % [vida0, vida1])

	# (2) cerca del borde del contacto: sigue conectando (mide superficie). Se le
	# quita la velocidad porque el golpe anterior lo EMPUJA hacia atrás y, al medir
	# tan al borde, un fotograma de empuje cambia el resultado.
	e.global_position = _jugador.global_position + frente * (alcanza - 0.3)
	e.set("velocity", Vector3.ZERO)
	await get_tree().physics_frame
	e.set("velocity", Vector3.ZERO)
	var vida2 := float(e.call("vida_actual"))
	# Diagnóstico de geometría: el hueco REAL que ve el módulo compartido (0 = contacto).
	var punto_golpe := _jugador.global_position + frente * 1.9
	var hueco := ContactoGolpe.distancia_de_contacto(e, punto_golpe, 0.0, 1.0)
	print("[contacto-suite] INFO borde: enemigo a %.2f m del jugador | hueco %.3f m" % [
			_jugador.global_position.distance_to(e.global_position), hueco])
	_jugador.call("_aplicar_impacto_velocista", 0)
	_check(float(e.call("vida_actual")) < vida2,
			"B conecta cerca del BORDE del alcance (%.2f m: cuenta el radio real del enemigo)" % (alcanza - 0.3))

	# (3) más allá: no conecta
	e.global_position = _jugador.global_position + frente * (alcanza + 0.6)
	e.set("velocity", Vector3.ZERO)
	await get_tree().physics_frame
	e.set("velocity", Vector3.ZERO)
	var vida3 := float(e.call("vida_actual"))
	_jugador.call("_aplicar_impacto_velocista", 0)
	_check(float(e.call("vida_actual")) == vida3, "B NO conecta fuera de alcance (%.2f m)" % (alcanza + 0.6))

	# (4) detrás: no conecta
	e.global_position = _jugador.global_position - frente * 1.5
	e.set("velocity", Vector3.ZERO)
	await get_tree().physics_frame
	e.set("velocity", Vector3.ZERO)
	var vida4 := float(e.call("vida_actual"))
	_jugador.call("_aplicar_impacto_velocista", 0)
	_check(float(e.call("vida_actual")) == vida4, "B NO conecta hacia atrás (el arco frontal manda)")

	# (5) muy por encima: no conecta
	e.global_position = _jugador.global_position + frente * 2.0 + Vector3.UP * 3.0
	e.set("velocity", Vector3.ZERO)
	await get_tree().physics_frame
	e.set("velocity", Vector3.ZERO)
	var vida5 := float(e.call("vida_actual"))
	_jugador.call("_aplicar_impacto_velocista", 0)
	_check(float(e.call("vida_actual")) == vida5, "B NO conecta 3 m por encima (banda vertical)")
	e.queue_free()
	await get_tree().process_frame

	# ---------------- C. Contrato de golpe del jugador ----------------
	_check(_jugador.has_method("get_hit_center") and _jugador.has_method("get_hit_radius"),
			"C el jugador expone el contrato de golpe (centro y radio)")
	var centro_jug := _jugador.call("get_hit_center") as Vector3
	var radio_jug := float(_jugador.call("get_hit_radius"))
	_check(absf(radio_jug - 0.4) <= 0.01, "C el radio es el REAL de su cápsula (%.2f m)" % radio_jug)
	_check(centro_jug.y - _jugador.global_position.y > 0.5,
			"C y el centro cae en el CUERPO, no en los pies (+%.2f m)" %
			(centro_jug.y - _jugador.global_position.y))

	# ---------------- D. Ataques enemigos ----------------
	var gerente := load(GERENTE).new() as Node3D
	gerente.name = "EnemigosPrueba"
	add_child(gerente)
	await get_tree().create_timer(0.2).timeout
	var vida_antes := _stats.vida
	var m := gerente.call("crear_enemigo_en", _jugador.global_position + Vector3(0, 0.0, -2.0), 1) as Node3D
	_check(m != null, "D se creó un enemigo cuerpo a cuerpo a 2 m del jugador")
	var t0 := Time.get_ticks_msec()
	var golpeado := false
	while Time.get_ticks_msec() - t0 < 7000:
		await get_tree().process_frame
		if _stats.vida < vida_antes - 0.01:
			golpeado = true
			break
	_check(golpeado, "D el enemigo CONECTA su combo con el jugador en el suelo (vida %.0f -> %.0f)" % [
			vida_antes, _stats.vida])
	# Fuera de su banda vertical: el jugador sube 5 m y el enemigo deja de conectar.
	# Se le mantiene arriba a la fuerza (si no, la gravedad lo devuelve al suelo en un
	# segundo y el enemigo volvería a conectar).
	var vida_alto := _stats.vida
	var en_el_aire := _jugador.global_position + Vector3(0.0, 5.0, 0.0)
	var t1 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t1 < 3500:
		await get_tree().process_frame
		_jugador.global_position = en_el_aire
		_jugador.set("velocity", Vector3.ZERO)
	# Sin daño NUEVO: la vida no baja (puede subir si regenera, eso no es un golpe).
	_check(_stats.vida >= vida_alto - 0.01,
			"D con el jugador 5 m por encima NO conecta (banda vertical del enemigo)")

	# ---------------- E. Las demás formas conservan sus criterios ----------------
	var cfg := load(CONFIG_ATAQUE)
	_check(cfg != null and cfg.get("attack_ideal_distance") > 0.0,
			"E combate: conserva su distancia ideal de golpe (%.2f m)" %
			(cfg.get("attack_ideal_distance") if cfg != null else -1.0))
	_check(cfg != null and float(cfg.get("attack_hit_arc")) > 0.0 and float(cfg.get("attack_hit_arc")) <= 1.0,
			"E combate: conserva su arco de golpe (%.2f)" % (cfg.get("attack_hit_arc") if cfg != null else -1.0))
	# Vuelo: sus dos valores de contacto son @export (no constantes), así que se
	# comprueba en el propio archivo que conservan su ajuste verificado.
	var texto := FileAccess.get_file_as_string(GROUND_COMBAT)
	_check("alcance_objetivo: float = 2.6" in texto and "tolerancia_vertical: float = 1.8" in texto,
			"E vuelo: conserva su alcance (2.6 m) y su tolerancia vertical (1.8 m)")
	# Fuerza: sus golpes van por una esfera FÍSICA contra las cápsulas reales de los
	# enemigos (el hitbox más exacto del proyecto): se comprueba que sigue ahí.
	var texto_fuerza := FileAccess.get_file_as_string(
			"res://personaje/transformaciones/fuerza/scripts (1)/Combat (1).gd")
	_check("static func golpear_esfera(" in texto_fuerza,
			"E Fuerza: sigue golpeando con su esfera física (colisión real, no distancia estimada)")

	print("==================== CONTACTO: %d OK / %d FALLO ====================" % [_ok, _fallos])
	await get_tree().create_timer(0.5).timeout


func _check(condicion: bool, texto: String) -> void:
	if condicion:
		_ok += 1
		print("[contacto-suite] OK   ", texto)
	else:
		_fallos += 1
		print("[contacto-suite] FALLO ", texto)


func _piso() -> void:
	var cuerpo := StaticBody3D.new()
	var forma := CollisionShape3D.new()
	var caja := BoxShape3D.new()
	caja.size = Vector3(120, 0.5, 120)
	forma.shape = caja
	cuerpo.add_child(forma)
	cuerpo.position = Vector3(0, -0.25, 0)
	add_child(cuerpo)
	var malla := MeshInstance3D.new()
	var caja_m := BoxMesh.new()
	caja_m.size = Vector3(120, 0.5, 120)
	malla.mesh = caja_m
	malla.position = Vector3(0, -0.25, 0)
	add_child(malla)
	var luz := DirectionalLight3D.new()
	luz.rotation = Vector3(-0.9, 0.6, 0.0)
	add_child(luz)
	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 3.0, 10.0)
	cam.current = true
	add_child(cam)