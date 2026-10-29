extends Node3D
## PRUEBAS del COMBO COMPLETO del personaje de combate aunque NO conecte (Tarea 5).
##
## El problema: la ventana de combo sólo se refrescaba cuando un golpe CONECTABA,
## así que al lanzar los golpes al aire la cadena volvía siempre al primero y no se
## podía completar (recto → cruzado → gancho).
##
## Comprueba, sobre el jugador REAL (forma Combate por el camino del menú radial) y
## con el CombatManager del módulo FreeFlow:
##  1. la cadena COMPLETA se ejecuta sin conectar NINGÚN golpe (los 3 eslabones, en
##     orden, sin enemigos delante);
##  2. cada eslabón se EJECUTA de verdad (llega a preparar/activo el golpe);
##  3. si pasa la ventana de combo (combo_keep_time) sin lanzar nada, la cadena
##     vuelve a empezar por el primero;
##  4. con enemigo delante sigue encadenando y el daño real (10/14/17) se aplica;
##  5. pulsar en el aire NO inicia ningún golpe ni gasta un eslabón (regla ya
##     existente: en el aire no se encola nada).
##
##   godot --headless --path <proyecto> res://pruebas/prueba_combo_base.tscn

const JUGADOR := "res://personaje/base/escenas/leo_jugador.tscn"
const GestorCombate := preload("res://personaje/transformaciones/transformacion ataque/scripts/combat/combat_manager.gd")
const ConfigCombate := preload("res://personaje/transformaciones/transformacion ataque/resources/combat_config.tres")
const ENEMIGO := "res://Enemigos Prueba/Scenes/enemigo_prueba.tscn"

const FORMA_COMBATE := 4
const C_LIBRE := 0
## Ids de la cadena básica (PlayerAtaque.SPRINT del módulo).
const CADENA := ["jab", "cros", "gancho"]
## Daño real de cada eslabón: config.attack_damage x el multiplicador del módulo.
const DANOS := [10.0, 14.0, 17.0]

var _ok := 0
var _fallos := 0
var _jug: Node3D
var _enemigo: Node3D
var _ventana := 2.0
var _en_cadena := -1
var _estados_vistos: Array[int] = []

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
	_ventana = float(ConfigCombate.combo_keep_time)
	print("[combo-suite] ventana de combo del config: %.2f s" % _ventana)

	# Entrada a la forma Combate por el camino real del menú radial.
	_jug.call("_on_transformacion_elegida", &"combate")
	var t := 0.0
	while (int(_jug.get("forma")) != FORMA_COMBATE or bool(_jug.get("_transformando"))) and t < 8.0:
		await get_tree().physics_frame
		t += 1.0 / 60.0
	await get_tree().create_timer(0.6).timeout
	_check(int(_jug.get("forma")) == FORMA_COMBATE, "el jugador entró en la forma Combate")

	# --- 1 y 2. CADENA COMPLETA SIN CONECTAR NINGÚN GOLPE -------------------
	var ids: Array[String] = []
	var ejecutados: Array[bool] = []
	for i in 3:
		var r := await _lanzar_golpe()
		ids.append(String(r["id"]))
		ejecutados.append(bool(r["ejecutado"]))
		await get_tree().create_timer(0.7).timeout
	_check(ids == CADENA,
			"la cadena COMPLETA sale sin conectar ningún golpe: %s (esperado %s)" % [str(ids), str(CADENA)])
	var todos := true
	for e in ejecutados:
		todos = todos and e
	_check(todos, "los 3 eslabones se EJECUTARON de verdad (preparar/activo), no sólo se eligieron")
	_check(_sin_enemigos(), "no había ningún objetivo delante: los 3 golpes fueron al aire")

	# --- 4 (adelanto). Con enemigo delante sigue la cadena y el daño real ----
	# (se hace antes de la prueba de la ventana agotada para encadenar desde el
	# gancho: el siguiente eslabón vuelve a ser el primero).
	_enemigo = (load(ENEMIGO) as PackedScene).instantiate() as Node3D
	_enemigo.name = "Blanco"
	add_child(_enemigo)
	_enemigo.global_position = _jug.global_position + _jug.global_transform.basis * Vector3(0.0, 0.0, -1.5)
	await get_tree().create_timer(0.5).timeout
	var vida0 := float(_enemigo.call("vida_actual"))
	var r4 := await _lanzar_golpe()
	var vida1 := float(_enemigo.call("vida_actual"))
	_check(String(r4["id"]) == CADENA[0],
			"tras el gancho la cadena vuelve al primero con enemigo delante (%s)" % String(r4["id"]))
	_check(is_equal_approx(vida1, vida0 - DANOS[0]),
			"el golpe que CONECTA aplica su daño real (%.1f → %.1f, esperado %.1f)" % [vida0, vida1, DANOS[0]])
	# La ventana sigue viva por el golpe conectado: el siguiente eslabón sale ya.
	await get_tree().create_timer(1.2).timeout
	var r5 := await _lanzar_golpe()
	var vida2 := float(_enemigo.call("vida_actual"))
	_check(String(r5["id"]) == CADENA[1],
			"habiendo CONECTADO, 1,2 s después la cadena sigue por el segundo (%s)" % String(r5["id"]))
	_check(is_equal_approx(vida2, vida1 - DANOS[1]),
			"el segundo eslabón aplica su daño real (%.1f → %.1f, esperado %.1f)" % [vida1, vida2, DANOS[1]])
	_enemigo.queue_free()
	_enemigo = null
	await get_tree().create_timer(0.4).timeout

	# --- 3. Ventana agotada: la cadena vuelve a empezar ---------------------
	await get_tree().create_timer(_ventana + 0.6).timeout
	var r3 := await _lanzar_golpe()
	_check(String(r3["id"]) == CADENA[0],
			"pasada la ventana de combo (%.1f s) la cadena vuelve a empezar por el primero (%s)" % [_ventana, String(r3["id"])])
	# Y desde ahí, sin conectar nada, otra vez el segundo.
	await get_tree().create_timer(0.7).timeout
	var r3b := await _lanzar_golpe()
	_check(String(r3b["id"]) == CADENA[1],
			"y al aire vuelve a avanzar al segundo (%s)" % String(r3b["id"]))

	# --- 5. En el aire no se inicia ningún golpe ----------------------------
	await get_tree().create_timer(0.8).timeout
	var cadena_antes := int(_jug.get("c_cadena"))
	Input.action_press("saltar")
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release("saltar")
	var t_aire := 0
	while _jug.is_on_floor() and t_aire < 30:
		await get_tree().physics_frame
		t_aire += 1
	await get_tree().physics_frame
	var arranco_en_aire := false
	var sustentado := false
	for _i in 30:
		if not _jug.is_on_floor():
			sustentado = true
			Input.action_press("atacar")
			await get_tree().physics_frame
			Input.action_release("atacar")
			if int(_jug.get("c_estado")) != C_LIBRE:
				arranco_en_aire = true
		await get_tree().physics_frame
	_check(sustentado, "el salto despegó del suelo (se pudo probar en el aire)")
	_check(not arranco_en_aire, "pulsar en el aire NO inicia ningún golpe (regla existente intacta)")
	_check(int(_jug.get("c_cadena")) == cadena_antes, "el eslabón de la cadena no se consumió en el aire")
	while not _jug.is_on_floor():
		await get_tree().physics_frame

	print("==================== COMBO BASE: %d OK / %d FALLO ====================" % [_ok, _fallos])


# ------------------------------------------------------------------ auxiliares
## Pulsa ataque y devuelve qué eslabón de la cadena se EJECUTÓ (id) y si llegó a
## la fase de preparación/activo (ejecución real, no sólo elección).
func _lanzar_golpe() -> Dictionary:
	_estados_vistos.clear()
	Input.action_press("atacar")
	await get_tree().physics_frame
	Input.action_release("atacar")
	var id := ""
	var ejecutado := false
	for _i in 150:
		await get_tree().physics_frame
		var estado := int(_jug.get("c_estado"))
		if not _estados_vistos.has(estado):
			_estados_vistos.append(estado)
		if estado in [1, 2, 3]:  # PREPARAR / ACTIVO / RECUPERAR
			ejecutado = true
		var golpe: Variant = _jug.get("c_golpe")
		if golpe != null:
			id = String(golpe.get("id"))
			if ejecutado:
				break
	# El eslabón elegido también se puede leer del índice de la cadena.
	if id == "" and int(_jug.get("c_cadena")) >= 0:
		id = CADENA[int(_jug.get("c_cadena"))]
	_en_cadena = int(_jug.get("c_cadena"))
	# Se espera a que el golpe termine del todo antes de la siguiente medición.
	for _i in 120:
		if int(_jug.get("c_estado")) == C_LIBRE:
			break
		await get_tree().physics_frame
	return {"id": id, "ejecutado": ejecutado, "estados": _estados_vistos.duplicate()}


func _sin_enemigos() -> bool:
	for n in get_tree().get_nodes_in_group("damageable"):
		var o := n as Node3D
		if o != null and o != _jug and o.is_inside_tree():
			var d: Vector3 = o.global_position - _jug.global_position
			d.y = 0.0
			if d.length() < 4.0:
				return false
	return true


func _check(condicion: bool, texto: String) -> void:
	if condicion:
		_ok += 1
		print("[combo-suite] OK   ", texto)
	else:
		_fallos += 1
		print("[combo-suite] FALLO ", texto)


func _piso() -> void:
	var cuerpo := StaticBody3D.new()
	cuerpo.name = "Piso"
	var forma := CollisionShape3D.new()
	var caja := BoxShape3D.new()
	caja.size = Vector3(120, 1, 120)
	forma.shape = caja
	cuerpo.add_child(forma)
	cuerpo.position = Vector3(0, -0.5, 0)
	add_child(cuerpo)
	var malla := MeshInstance3D.new()
	var caja_malla := BoxMesh.new()
	caja_malla.size = Vector3(120, 1, 120)
	malla.mesh = caja_malla
	cuerpo.add_child(malla)
	var luz := DirectionalLight3D.new()
	luz.rotation = Vector3(-0.9, 0.6, 0.0)
	add_child(luz)
	var cam := Camera3D.new()
	cam.position = Vector3(3.6, 2.4, 4.6)
	cam.look_at_from_position(Vector3(3.6, 2.4, 4.6), Vector3(0.0, 1.1, 0.0))
	cam.current = true
	add_child(cam)