extends Node3D
## PRUEBAS del REALISMO ESPACIAL del Free Flow (Tarea 11), SIN tocar animaciones:
##  A. ACERCAMIENTO continuo: el atacante camina hacia el objetivo (estado
##     ACERCARSE) y cada fotograma avanza poco (sin teletransportes);
##  B. PARA al llegar a la distancia de golpe (ni lejos ni dentro del enemigo);
##  C. ALINEACIÓN: gira hacia el objetivo a ritmo limitado y pega mirándolo;
##  D. el OBJETIVO también se acerca a pie, sin atravesarse con el atacante;
##  E. las ANIMACIONES del módulo están intactas: mismos 8 clips y la cadena sigue
##     siendo jab/cros/gancho (no se añadió ni se retocó ninguna).
##
##   godot --headless --path <proyecto> res://pruebas/prueba_freeflow_espacial.tscn

const JUGADOR := "res://personaje/base/escenas/leo_jugador.tscn"
const GestorCombate := preload("res://personaje/transformaciones/transformacion ataque/scripts/combat/combat_manager.gd")
const ConfigCombate := preload("res://personaje/transformaciones/transformacion ataque/resources/combat_config.tres")
const PlayerAtaque := preload("res://personaje/transformaciones/transformacion ataque/scripts/player.gd")
const LIB_ATAQUE := "res://personaje/transformaciones/transformacion ataque/animations/player_anim_library.tres"
const ENEMIGO := "res://Enemigos Prueba/Scenes/enemigo_prueba.tscn"

const FORMA_COMBATE := 4
const C_LIBRE := 0
const C_ACERCARSE := 1
const C_PREPARAR := 2
const C_ACTIVO := 3
const C_RECUPERAR := 4
## Distancia inicial del objetivo (m): fuera del alcance, obliga a acercarse.
const DIST_INICIAL := 6.0
## Clips propios del módulo de combate (no se toca ninguno).
const CLIPS_ESPERADOS := ["combat_idle", "cros", "dos", "gancho", "idle", "jab", "jump", "walk"]

var _ok := 0
var _fallos := 0
var _jug: Node3D
var _enemigo: Node3D

func _ready() -> void:
	_piso()
	var mgr := Node.new()
	mgr.name = "CombatManager"
	mgr.set_script(GestorCombate)
	mgr.set("config", ConfigCombate)
	add_child(mgr)
	_jug = (load(JUGADOR) as PackedScene).instantiate() as Node3D
	_jug.position = Vector3(0, 0.1, 0)
	add_child(_jug)
	await get_tree().create_timer(0.9).timeout
	_jug.call("_on_transformacion_elegida", &"combate")
	var t := 0.0
	while (int(_jug.get("forma")) != FORMA_COMBATE or bool(_jug.get("_transformando"))) and t < 8.0:
		await get_tree().physics_frame
		t += 1.0 / 60.0
	await get_tree().create_timer(0.5).timeout
	_check(int(_jug.get("forma")) == FORMA_COMBATE, "el jugador entra en la forma Combate")

	# --- 5. Las animaciones del módulo, intactas ---------------------------
	var lib := load(LIB_ATAQUE) as AnimationLibrary
	var nombres: Array = []
	for n in lib.get_animation_list():
		nombres.append(String(n))
	nombres.sort()
	var esperados := CLIPS_ESPERADOS.duplicate()
	esperados.sort()
	_check(nombres == esperados,
			"la librería del módulo sigue con sus 8 clips intactos (%s)" % str(nombres))
	_check(PlayerAtaque.SPRINT.size() == 3 and String(PlayerAtaque.SPRINT[0]["anim"]) == "jab" \
			and String(PlayerAtaque.SPRINT[1]["anim"]) == "cros" \
			and String(PlayerAtaque.SPRINT[2]["anim"]) == "gancho",
			"la cadena sigue siendo jab/cros/gancho (animaciones sin tocar)")

	# --- Objetivo lejos, fuera del alcance ---------------------------------
	_enemigo = (load(ENEMIGO) as PackedScene).instantiate() as Node3D
	_enemigo.name = "Blanco"
	add_child(_enemigo)
	_enemigo.global_position = _jug.global_position + Vector3(0.0, 0.0, -DIST_INICIAL)
	await get_tree().create_timer(0.5).timeout
	var ideal := float(ConfigCombate.attack_ideal_distance)
	var velocidad_acercar := float(ConfigCombate.approach_speed)
	var t_max_acercar := float(ConfigCombate.approach_max_time)
	var giro_max := float(ConfigCombate.player_turn_speed)

	# --- A/B/C. Pulsar ataque y medir el acercamiento fotograma a fotograma --
	Input.action_press("atacar")
	await get_tree().physics_frame
	Input.action_release("atacar")
	var visto_acercarse := false
	var visto_activo := false
	var paso_max := 0.0
	var paso_max_enemigo := 0.0
	var giro_max_visto := 0.0
	var dist_activo := -1.0
	var dist_min := 999.0
	var dist_min_enemigo := 999.0
	var t_acercar := 0.0
	var t_espera := 0.0
	var dir_ok := 1.0
	var frame_activo := false
	var pos_antes := _jug.global_position
	var rot_antes := float((_jug.get("acuatico") as Node3D).rotation.y) if false else _rot_jug()
	var pos_antes_enemigo := _enemigo.global_position
	var volvio_a_la_mano := false
	while t_espera < 3.2:
		await get_tree().physics_frame
		t_espera += 1.0 / 60.0
		var estado := int(_jug.get("c_estado"))
		if estado == C_ACERCARSE:
			visto_acercarse = true
			t_acercar += 1.0 / 60.0
		var d := _distancia()
		dist_min = minf(dist_min, d)
		var paso := Vector2(_jug.global_position.x - pos_antes.x, _jug.global_position.z - pos_antes.z).length()
		paso_max = maxf(paso_max, paso)
		pos_antes = _jug.global_position
		var paso_e := Vector2(_enemigo.global_position.x - pos_antes_enemigo.x,
				_enemigo.global_position.z - pos_antes_enemigo.z).length()
		paso_max_enemigo = maxf(paso_max_enemigo, paso_e)
		pos_antes_enemigo = _enemigo.global_position
		var rot := _rot_jug()
		giro_max_visto = maxf(giro_max_visto, absf(wrapf(rot - rot_antes, -PI, PI)))
		rot_antes = rot
		if not frame_activo and (estado == C_ACTIVO or estado == C_PREPARAR):
			frame_activo = true
			dist_activo = d
			var dir := _enemigo.global_position - _jug.global_position
			dir.y = 0.0
			var fwd := -(_jug.get("ataque_visual") as Node3D).global_transform.basis.z
			fwd.y = 0.0
			if dir.length() > 0.001 and fwd.length() > 0.001:
				dir_ok = fwd.normalized().dot(dir.normalized())
		if estado in [C_PREPARAR, C_ACTIVO, C_RECUPERAR]:
			visto_activo = true
		if visto_activo and estado == C_LIBRE:
			volvio_a_la_mano = true
			break
	await get_tree().create_timer(0.6).timeout
	dist_min_enemigo = _distancia()
	var vida_tras := float(_enemigo.call("vida_actual"))
	await get_tree().create_timer(0.6).timeout

	# --- Comprobaciones ----------------------------------------------------
	_check(visto_acercarse, "el atacante CAMINA hacia el objetivo (estado ACERCARSE)")
	var paso_limite := velocidad_acercar * (1.0 / 60.0) * 2.5 + 0.06
	_check(paso_max <= paso_limite,
			"sin teletransportes: el paso mayor por fotograma fue %.3f m (límite %.3f)" % [paso_max, paso_limite])
	_check(visto_activo, "el golpe se EJECUTA tras acercarse")
	_check(dist_activo >= ideal * 0.5 and dist_activo <= ideal + 0.8,
			"para a la distancia de golpe: %.2f m (ideal %.2f)" % [dist_activo, ideal])
	_check(t_acercar <= t_max_acercar + 0.35,
			"el acercamiento dura lo permitido: %.2f s (tope %.2f)" % [t_acercar, t_max_acercar])
	_check(volvio_a_la_mano, "el golpe termina y el cuerpo vuelve al control normal")
	_check(dir_ok >= 0.9, "pega MIRANDO al objetivo (alineación %.2f)" % dir_ok)
	var giro_limite := giro_max * (1.0 / 60.0) * 2.0 + 0.02
	_check(giro_max_visto <= giro_limite,
			"el giro hacia el objetivo es continuo (%.3f rad/fotograma, tope %.3f)" % [giro_max_visto, giro_limite])
	_check(dist_min >= 0.55,
			"atacante y objetivo NO se atraviesan (distancia mínima %.2f m)" % dist_min)
	_check(paso_max_enemigo <= 0.35,
			"el objetivo también se mueve a pie, sin saltos (paso mayor %.3f m)" % paso_max_enemigo)
	_check(dist_min_enemigo <= 3.0,
			"el objetivo se acerca al jugador hasta distancia de pelea (%.2f m)" % dist_min_enemigo)
	_check(vida_tras < float(_enemigo.get("vida_max")),
			"el golpe aplica daño real (vida %.0f)" % vida_tras)
	var vida_estable := float(_enemigo.call("vida_actual"))
	_check(is_equal_approx(vida_estable, vida_tras),
			"el daño se aplica UNA vez (sin repetirse por fotograma)")

	print("==================== FREEFLOW ESPACIAL: %d OK / %d FALLO ====================" % [_ok, _fallos])


# ------------------------------------------------------------------ auxiliares
func _distancia() -> float:
	var d := _enemigo.global_position - _jug.global_position
	d.y = 0.0
	return d.length()


func _distancia_enemigo_jugador() -> float:
	var d := _enemigo.global_position - _jug.global_position
	d.y = 0.0
	return d.length()


func _rot_jug() -> float:
	var vis := _jug.get("ataque_visual") as Node3D
	return vis.rotation.y if vis != null else 0.0


func _check(condicion: bool, texto: String) -> void:
	if condicion:
		_ok += 1
		print("[freeflow-suite] OK   ", texto)
	else:
		_fallos += 1
		print("[freeflow-suite] FALLO ", texto)


func _piso() -> void:
	var cuerpo := StaticBody3D.new()
	cuerpo.name = "Piso"
	var forma := CollisionShape3D.new()
	var caja := BoxShape3D.new()
	caja.size = Vector3(160, 1, 160)
	forma.shape = caja
	cuerpo.add_child(forma)
	cuerpo.position = Vector3(0, -0.5, 0)
	add_child(cuerpo)
	var malla := MeshInstance3D.new()
	var caja_malla := BoxMesh.new()
	caja_malla.size = Vector3(160, 1, 160)
	malla.mesh = caja_malla
	cuerpo.add_child(malla)
	var luz := DirectionalLight3D.new()
	luz.rotation = Vector3(-0.9, 0.6, 0.0)
	add_child(luz)
	var cam := Camera3D.new()
	cam.position = Vector3(4.0, 3.0, 6.0)
	cam.look_at_from_position(Vector3(4.0, 3.0, 6.0), Vector3(0.0, 1.0, 0.0))
	cam.current = true
	add_child(cam)
