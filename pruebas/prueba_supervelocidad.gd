extends Node3D

## Suite (ESCENA) de la SUPERVEOLOCIDAD GUIADA del Velocista.
##
## Comprueba los casos del encargo:
##   1. enemigo aislado en la trayectoria;
##   2. varios enemigos alineados;
##   3. atravesando un grupo;
##   4. dos pasadas por la misma zona (cada enemigo, como máximo un golpe por
##      activación, y sin bloquear la segunda pasada);
##   5. pared / obstáculo sólido: la habilidad SÍ se detiene ahí;
##   6. la habilidad no se cancela por el contacto, termina bien y devuelve la
##      máscara de colisión a su valor normal.
##
## Trabaja sobre el jugador REAL, enemigos REALES (`EnemigoPrueba`) y el
## CombatManager del módulo FreeFlow. Suelo y muro van en la capa 1 (el mundo); los
## enemigos en la capa 5 (16). Se ejecuta como escena:
##
##   godot --headless --path . pruebas/prueba_supervelocidad.tscn

const JUGADOR := preload("res://personaje/base/escenas/leo_jugador.tscn")
const GestorCombate := preload("res://personaje/transformaciones/transformacion ataque/scripts/combat/combat_manager.gd")
const ConfigCombate := preload("res://personaje/transformaciones/transformacion ataque/resources/combat_config.tres")
const ESCENA_ENEMIGO := preload("res://Enemigos Prueba/Scenes/enemigo_prueba.tscn")

const FORMA_VELOCISTA := 1
const ESTADO_NORMAL := 0
const MASK_MUNDO := 1
const MASK_NORMAL := 17
const DANIO_SUPER := 5.0
const VIDA_ENEMIGO := 60.0

var _pasadas := 0
var _falladas := 0
var _jug: ControladorLeo
## Posición inicial de cada enemigo creado (para medir el empuje real).
var _pos_inicial: Dictionary = {}

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

func _esperar(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame

func _esperar_seg(s: float) -> void:
	await _esperar(int(ceil(s * 60.0)))

func _frente() -> Vector3:
	var f := -_jug.pivote.global_transform.basis.z
	f.y = 0.0
	return f.normalized() if f.length_squared() > 0.0001 else Vector3.FORWARD

func _derecha() -> Vector3:
	var d := _jug.pivote.global_transform.basis.x
	d.y = 0.0
	return d.normalized() if d.length_squared() > 0.0001 else Vector3.RIGHT

func _vida(e) -> float:
	if e == null or not is_instance_valid(e):
		return -1.0
	if e.has_method("vida_actual"):
		return float(e.call("vida_actual"))
	return float(e.get("vida_actual"))

func _vivo(e) -> bool:
	if e == null or not is_instance_valid(e):
		return false
	if not e.has_method("is_alive"):
		return false
	return bool(e.call("is_alive"))

func _aturdido(e) -> bool:
	if e == null or not is_instance_valid(e):
		return false
	if not e.has_method("is_stunned"):
		return false
	return bool(e.call("is_stunned"))

func _montar() -> void:
	var suelo := StaticBody3D.new()
	suelo.name = "Suelo"
	suelo.collision_layer = MASK_MUNDO
	var forma := CollisionShape3D.new()
	var caja := BoxShape3D.new()
	caja.size = Vector3(600.0, 1.0, 600.0)
	forma.shape = caja
	suelo.add_child(forma)
	suelo.position = Vector3(0.0, -0.5, 0.0)
	add_child(suelo)

	var mgr := Node.new()
	mgr.name = "CombatManager"
	mgr.set_script(GestorCombate)
	mgr.set("config", ConfigCombate)
	add_child(mgr)

	_jug = JUGADOR.instantiate()
	_jug.position = Vector3(0.0, 0.1, 0.0)
	add_child(_jug)

## Muro sólido en la capa del MUNDO (1): la habilidad debe seguir chocando con él.
func _muro(centro: Vector3, grosor: float = 0.6, ancho: float = 8.0) -> StaticBody3D:
	var muro := StaticBody3D.new()
	muro.name = "Muro"
	muro.collision_layer = MASK_MUNDO
	var forma := CollisionShape3D.new()
	var caja := BoxShape3D.new()
	caja.size = Vector3(ancho, 3.0, grosor)
	forma.shape = caja
	muro.add_child(forma)
	add_child(muro)
	muro.global_position = centro
	return muro

## Enemigo real. Congelado = sin IA, para que la distancia del caso no se mueva.
func _crear_enemigo(pos: Vector3, congelado: bool = true) -> Node3D:
	var e := ESCENA_ENEMIGO.instantiate()
	add_child(e)
	e.global_position = pos
	_pos_inicial[e.get_instance_id()] = pos
	if congelado:
		e.set_physics_process(false)
	return e

func _cambiar_forma(id: StringName, forma: int) -> bool:
	_jug._on_transformacion_elegida(id)
	var t := 0
	while (int(_jug.forma) != forma or _jug._transformando) and t < 900:
		await get_tree().physics_frame
		t += 1
	await _esperar(10)
	return int(_jug.forma) == forma

## Lanza la supervelocidad y devuelve lo medido: recorrido, máscara DURANTE el
## vuelo y, por cada enemigo de la lista, si fue golpeado (y cuánto daño, si quedó
## aturdido y con qué velocidad salió empujado).
func _lanzar_super(enemigos: Array) -> Dictionary:
	var p0 := _jug.global_position
	var info: Array = []
	var golpeado: Array = []
	var vid: Array = []
	for e in enemigos:
		vid.append(_vida(e))
		info.append({})
		golpeado.append(false)
	Input.action_press("cargar_poder")
	await _esperar_seg(1.0)
	Input.action_release("cargar_poder")
	var mask_vuelo := _jug.collision_mask
	var arranco := false
	var t := 0.0
	while t < 1.0 and not arranco:
		await get_tree().physics_frame
		t += 1.0 / 60.0
		if int(_jug.estado) != ESTADO_NORMAL:
			arranco = true
	while t < 5.0 and int(_jug.estado) != ESTADO_NORMAL:
		await get_tree().physics_frame
		t += 1.0 / 60.0
		# Mínimo observado: en la EJECUCIÓN la máscara deja fuera a los enemigos.
		mask_vuelo = mini(mask_vuelo, _jug.collision_mask)
		for i in enemigos.size():
			if golpeado[i]:
				continue
			var e = enemigos[i]
			if not is_instance_valid(e):
				continue
			if _vida(e) < float(vid[i]) - 0.001:
				golpeado[i] = true
				info[i] = {
					"dano": float(vid[i]) - _vida(e),
					"aturdido": _aturdido(e),
					"vel": float(e.get("velocity").length()) if e.get("velocity") != null else 0.0,
				}
	await _esperar(4)
	var d := _jug.global_position - p0
	d.y = 0.0
	return {"recorrido": d.length(), "mask_vuelo": mask_vuelo, "mask_final": _jug.collision_mask,
			"golpeado": golpeado, "info": info, "arranco": arranco}

func _correr() -> void:
	print("=== PRUEBA: supervelocidad guiada (atravesar enemigos, no paredes) ===")
	_montar()
	await _esperar(30)
	_check("jugador listo", _jug != null)
	var ok := await _cambiar_forma(&"velocista", FORMA_VELOCISTA)
	_check("el velocista entra por el menú de transformaciones", ok, "forma=%d" % int(_jug.forma))
	_check("la máscara de colisión normal incluye a los enemigos (capa 5)",
			_jug.collision_mask == MASK_NORMAL, "mask=%d" % _jug.collision_mask)

	# --- 0: referencia sin enemigos -----------------------------------------
	var base := await _lanzar_super([])
	_check("la habilidad se ejecuta en un tramo libre", base["arranco"] and base["recorrido"] >= 1.0,
			"recorrido=%.2f m" % base["recorrido"])
	var recorrido_base: float = base["recorrido"]
	_check("durante el vuelo la máscara quita SÓLO a los enemigos",
			int(base["mask_vuelo"]) == MASK_MUNDO, "mask en vuelo=%d" % int(base["mask_vuelo"]))
	_check("al terminar, la máscara vuelve a su valor normal",
			int(base["mask_final"]) == MASK_NORMAL, "mask final=%d" % int(base["mask_final"]))

	# --- 1: enemigo aislado --------------------------------------------------
	var frente := _frente()
	var derecha := _derecha()
	var enemigo_aislado := _crear_enemigo(_jug.global_position + frente * 2.6 + derecha * 0.7)
	var aislado := await _lanzar_super([enemigo_aislado])
	_check("1. enemigo aislado: recibe daño", aislado["golpeado"][0],
			"vida=%.1f" % _vida(enemigo_aislado))
	_check("1. enemigo aislado: el daño es el de la supervelocidad (5) y una sola vez",
			is_equal_approx(float(aislado["info"][0].get("dano", -1.0)), DANIO_SUPER),
			"daño=%.2f" % float(aislado["info"][0].get("dano", -1.0)))
	_check("1. enemigo aislado: queda aturdido", bool(aislado["info"][0].get("aturdido", false)))
	_check("1. enemigo aislado: sale empujado", float(aislado["info"][0].get("vel", 0.0)) >= 8.0,
			"velocidad=%.1f m/s" % float(aislado["info"][0].get("vel", 0.0)))
	_check("1. enemigo aislado: el enemigo NO detiene la trayectoria",
			aislado["recorrido"] >= recorrido_base * 0.8,
			"recorrido=%.2f m (libre %.2f m)" % [aislado["recorrido"], recorrido_base])

	# --- 1b: enemigo JUSTO en la línea de mira (sin desvío) ------------------
	_jug.global_position = Vector3(30.0, 0.3, 30.0)
	await _esperar(8)
	frente = _frente()
	var centro_linea := _crear_enemigo(_jug.global_position + frente * 3.0)
	var en_linea := await _lanzar_super([centro_linea])
	_check("1b. enemigo justo en la línea de mira: la habilidad arranca igual",
			bool(en_linea["arranco"]), "arranco=%s" % str(en_linea["arranco"]))
	_check("1b. enemigo justo delante: recibe su daño y no corta la trayectoria",
			en_linea["golpeado"][0] and en_linea["recorrido"] >= recorrido_base * 0.8,
			"recorrido=%.2f m (libre %.2f m) daño=%.2f" % [en_linea["recorrido"],
					recorrido_base, float(en_linea["info"][0].get("dano", -1.0))])

	# --- 2: varios enemigos alineados ---------------------------------------
	_jug.global_position = Vector3(60.0, 0.3, 60.0)
	await _esperar(6)
	frente = _frente()
	derecha = _derecha()
	var linea: Array = []
	for i in 3:
		linea.append(_crear_enemigo(_jug.global_position + frente * (2.4 + 1.1 * i)
				+ derecha * (0.5 + 0.2 * i)))
	var alineados := await _lanzar_super(linea)
	var danados := 0
	var aturdidos := 0
	for i in linea.size():
		if alineados["golpeado"][i] and is_equal_approx(float(alineados["info"][i].get("dano", -1.0)), DANIO_SUPER):
			danados += 1
		if bool(alineados["info"][i].get("aturdido", false)):
			aturdidos += 1
	_check("2. enemigos alineados: los tres reciben 5 de daño", danados == 3, "danados=%d/3" % danados)
	_check("2. enemigos alineados: los tres quedan aturdidos", aturdidos == 3, "aturdidos=%d/3" % aturdidos)
	_check("2. enemigos alineados: la trayectoria no se detiene",
			alineados["recorrido"] >= recorrido_base * 0.8,
			"recorrido=%.2f m (libre %.2f m)" % [alineados["recorrido"], recorrido_base])

	# --- 3: atravesando un grupo --------------------------------------------
	_jug.global_position = Vector3(120.0, 0.3, 120.0)
	await _esperar(6)
	frente = _frente()
	derecha = _derecha()
	var grupo: Array = []
	var p_grupo := _jug.global_position
	var centro := _jug.global_position + frente * 3.0
	grupo.append(_crear_enemigo(centro))
	grupo.append(_crear_enemigo(centro + derecha * 0.9))
	grupo.append(_crear_enemigo(centro - derecha * 0.9))
	grupo.append(_crear_enemigo(centro - frente * 0.9))
	var atravesado := await _lanzar_super(grupo)
	var danados_g := 0
	for i in grupo.size():
		if atravesado["golpeado"][i]:
			danados_g += 1
	_check("3. grupo: la arremetida alcanza a los cuatro", danados_g == 4, "alcanzados=%d/4" % danados_g)
	_check("3. grupo: la habilidad sigue su recorrido completo",
			atravesado["recorrido"] >= recorrido_base * 0.8,
			"recorrido=%.2f m (libre %.2f m)" % [atravesado["recorrido"], recorrido_base])

	# --- 4: dos pasadas por la misma zona -----------------------------------
	# Se vuelve a la MISMA posición de partida y se devuelve a los enemigos a su
	# sitio: la segunda pasada recorre exactamente la misma zona.
	_jug.global_position = p_grupo
	for i in grupo.size():
		var id_g: int = int(grupo[i].get_instance_id())
		if _pos_inicial.has(id_g):
			grupo[i].global_position = _pos_inicial[id_g]
	await _esperar(12)
	var vidas_tras_primera: Array = []
	for e in grupo:
		vidas_tras_primera.append(_vida(e))
	var segunda := await _lanzar_super(grupo)
	var repetidos := 0
	for i in grupo.size():
		if is_equal_approx(float(vidas_tras_primera[i]) - _vida(grupo[i]), DANIO_SUPER):
			repetidos += 1
	_check("4. segunda pasada: cada enemigo recibe otro golpe UNA vez (uno por activación)",
			repetidos == grupo.size(), "afectados=%d/%d" % [repetidos, grupo.size()])
	_check("4. segunda pasada: los enemigos ya golpeados no la bloquean",
			segunda["recorrido"] >= recorrido_base * 0.8,
			"recorrido=%.2f m (libre %.2f m)" % [segunda["recorrido"], recorrido_base])

	# --- 5: pared / obstáculo sólido ----------------------------------------
	_jug.global_position = Vector3(180.0, 0.3, 180.0)
	await _esperar(8)
	frente = _frente()
	var muro := _muro(_jug.global_position + frente * 4.0)
	await _esperar(6)
	var p_muro := _jug.global_position
	var contra_muro := await _lanzar_super([])
	_check("5. pared: la habilidad arranca con el muro delante", bool(contra_muro["arranco"]))
	# La trayectoria guiada se traza contra el mundo: con un muro de verdad delante
	# NO puede cruzarlo (o ni arranca). Lo que importa es que no lo atraviese nunca.
	var avance_muro := (_jug.global_position - p_muro).dot(frente)
	_check("5. pared: la habilidad NO atraviesa el obstáculo sólido",
			avance_muro < 3.7 and contra_muro["recorrido"] < recorrido_base * 0.9,
			"avance hacia el muro=%.2f m (muro a 4,00 m) recorrido=%.2f m" % [avance_muro,
					contra_muro["recorrido"]])
	_check("5. pared: la habilidad termina correctamente (no queda bloqueada)",
			int(_jug.estado) == ESTADO_NORMAL, "estado=%d" % int(_jug.estado))
	_check("5. pared: el jugador sigue de pie en su lado del muro",
			_jug.is_on_floor() and muro != null and is_instance_valid(muro)
			and _jug.global_position.distance_to(muro.global_position) >= 0.4,
			"distancia al muro=%.2f m" % _jug.global_position.distance_to(muro.global_position))

	# --- 6: cierre -----------------------------------------------------------
	_check("6. tras todas las pruebas la máscara está restaurada",
			_jug.collision_mask == MASK_NORMAL, "mask=%d" % _jug.collision_mask)
	_check("6. la habilidad termina en su estado normal y de pie",
			int(_jug.estado) == ESTADO_NORMAL and _jug.is_on_floor(),
			"estado=%d suelo=%s" % [int(_jug.estado), str(_jug.is_on_floor())])
	var expulsados := 0
	var seguidos := 0
	for e in grupo + linea:
		if not is_instance_valid(e):
			continue
		seguidos += 1
		var id: int = int(e.get_instance_id())
		if _pos_inicial.has(id) and e.global_position.distance_to(_pos_inicial[id]) > 15.0:
			expulsados += 1
	_check("6. el empuje aparta a los enemigos sin expulsarlos del escenario",
			seguidos > 0 and expulsados == 0,
			"vivos=%d expulsados=%d" % [seguidos, expulsados])

	_resumen()

func _resumen() -> void:
	print("=== RESULTADO: %d OK, %d FALLOS ===" % [_pasadas, _falladas])
	get_tree().quit(1 if _falladas > 0 else 0)