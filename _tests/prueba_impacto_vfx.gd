extends Node3D
## PRUEBAS de los EFECTOS DE IMPACTO sobre los enemigos (Tarea 4):
##  A. contrato del enemigo: un daño CONFIRMADO produce UN impacto en el punto de
##     contacto (sobre la superficie que mira al atacante, nunca en el suelo);
##     un daño inválido (0) o sobre un muerto NO produce nada; el impacto no se
##     duplica con el paso de los fotogramas; la reacción es la animación REAL
##     del enemigo, una vez por golpe.
##  B. camino de ataque real: un golpe al aire NO genera efecto y un golpe que
##     conecta SÍ lo genera (en el enemigo).

const JUGADOR := "res://personaje/base/escenas/leo_jugador.tscn"
## Gestor del encuentro FreeFlow y su configuración: el MISMO del módulo (así la
## forma Combate selecciona objetivo igual que en la partida).
const GestorCombate := preload("res://personaje/transformaciones/transformacion ataque/scripts/combat/combat_manager.gd")
const ConfigCombate := preload("res://personaje/transformaciones/transformacion ataque/resources/combat_config.tres")
## Enemigo de la PARTE A: el de cuerpo a cuerpo (librería horneada con la
## animación de reacción).
const ENEMIGO := "res://Enemigos Prueba/Scenes/enemigo_melee.tscn"
## Enemigo de la PARTE B: el mismo que usan las suites de combate ya probadas.
const ENEMIGO_COMBATE := "res://Enemigos Prueba/Scenes/enemigo_prueba.tscn"

var _ok := 0
var _fallos := 0
var _jug: Node3D
var _enemigo: Node3D
var _raiz_efectos: Node3D

func _ready() -> void:
	_piso()
	_raiz_efectos = Node3D.new()
	_raiz_efectos.name = "Efectos"
	add_child(_raiz_efectos)
	# El gestor del módulo ANTES del jugador: el controlador lo resuelve en _ready.
	var mgr := Node.new()
	mgr.name = "CombatManager"
	mgr.set_script(GestorCombate)
	mgr.set("config", ConfigCombate)
	add_child(mgr)
	var ps := load(JUGADOR) as PackedScene
	_jug = ps.instantiate() as Node3D
	_jug.position = Vector3(0, 0.1, 0)
	add_child(_jug)
	await get_tree().create_timer(0.8).timeout

	# --- A. Contrato del enemigo -------------------------------------------
	_enemigo = (load(ENEMIGO) as PackedScene).instantiate() as Node3D
	_enemigo.name = "Blanco"
	_raiz_efectos.add_child(_enemigo)
	_enemigo.global_position = Vector3(4.0, 0.1, 4.0)
	await get_tree().create_timer(0.3).timeout

	var vida0 := float(_enemigo.call("vida_actual"))
	var antes := _contar_particulas()
	# Golpe desde el SUR del enemigo (atacante en +Z): el contacto debe caer del
	# lado que mira al atacante, a la altura del pecho.
	var atacante := _enemigo.global_position + Vector3(0.0, 0.0, 3.0)
	var dir := (_enemigo.global_position - atacante)
	dir.y = 0.0
	dir = dir.normalized()
	_enemigo.call("take_hit", 12.0, dir, 4.0, 0.0)
	await get_tree().physics_frame
	var despues := _contar_particulas()
	_check(despues - antes == 2, "un impacto confirmado crea el efecto (chispas + polvo = %d partículas nuevas)" % (despues - antes))
	_check(float(_enemigo.call("vida_actual")) < vida0, "el daño se aplicó (%.0f → %.0f)" % [vida0, float(_enemigo.call("vida_actual"))])

	# Punto de contacto: centro de golpe del enemigo + radio, del lado del atacante.
	var centro: Vector3 = _enemigo.call("get_hit_center")
	var radio := float(_enemigo.call("get_hit_radius"))
	var esperado := centro - dir * radio * 0.9 + Vector3.UP * 0.05 - dir * 0.05
	var particulas := _particulas_nuevas(antes)
	var punto_real := Vector3.ZERO
	if not particulas.is_empty():
		punto_real = (particulas[0] as Node3D).global_position
	var dist := punto_real.distance_to(esperado)
	_check(dist < 0.25, "el efecto nace en el PUNTO DE CONTACTO (a %.2f m del punto teórico sobre la superficie)" % dist)
	_check(punto_real.y > centro.y - radio - 0.2 and punto_real.y > 0.4,
			"el efecto NO está en el suelo (altura %.2f m)" % punto_real.y)
	var lado := (punto_real - centro)
	lado.y = 0.0
	_check(lado.normalized().dot(-dir) > 0.5,
			"el efecto sale del lado que MIRA AL ATACANTE (dot %.2f)" % lado.normalized().dot(-dir))

	# Reacción: el clip real del enemigo, una vez por golpe. El reproductor del
	# enemigo vive en el nodo "Animador" (ver `@onready _anim` de enemigo_base).
	var anim := _enemigo.get_node_or_null("Animador") as AnimationPlayer
	_check(anim != null and anim.has_animation(&"recibir_combate"),
			"la librería del enemigo trae la animación de reacción 'recibir_combate'")
	var clip_reaccion := ""
	if anim != null:
		clip_reaccion = String(anim.current_animation)
	_check(clip_reaccion.contains("recibir"), "el enemigo reproduce su animación REAL de reacción ('%s')" % clip_reaccion)

	# No se duplica con el paso de los fotogramas (las partículas se liberan solas,
	# así que lo que se comprueba es que NO aparecen nuevas y que la vida no baja).
	var antes_estable := _contar_particulas()
	var vida_estable := float(_enemigo.call("vida_actual"))
	await get_tree().create_timer(1.0).timeout
	_check(_contar_particulas() <= antes_estable and is_equal_approx(float(_enemigo.call("vida_actual")), vida_estable),
			"el mismo impacto NO se duplica con los fotogramas (%d partículas ≤ %d y vida %.1f)" % [_contar_particulas(), antes_estable, float(_enemigo.call("vida_actual"))])

	# Tras la reacción, la locomoción vuelve sola.
	await get_tree().create_timer(0.4).timeout
	var volvio := true
	if anim != null:
		volvio = not String(anim.current_animation).contains("recibir")
	_check(volvio, "la reacción dura lo suyo y el enemigo vuelve a su locomoción")

	# Daño inválido y enemigo muerto: NADA.
	var antes_invalido := _contar_particulas()
	_enemigo.call("take_hit", 0.0, dir, 0.0, 0.0)
	await get_tree().physics_frame
	_check(_contar_particulas() == antes_invalido, "un golpe con daño 0 no produce efecto")
	_enemigo.call("execute")
	await get_tree().physics_frame
	var antes_muerto := _contar_particulas()
	_enemigo.call("take_hit", 99.0, dir, 0.0, 0.0)
	await get_tree().physics_frame
	_check(_contar_particulas() == antes_muerto, "un golpe sobre un enemigo ya muerto no produce efecto")
	_enemigo.queue_free()
	_enemigo = null
	await get_tree().create_timer(0.6).timeout

	# --- B. Camino de ataque real (forma Combate) ---------------------------
	_jug.call("_on_transformacion_elegida", &"combate")
	await get_tree().create_timer(2.0).timeout
	# Blanco lejano: el golpe sale al aire.
	_enemigo = (load(ENEMIGO_COMBATE) as PackedScene).instantiate() as Node3D
	_enemigo.name = "Blanco"
	_raiz_efectos.add_child(_enemigo)
	_enemigo.global_position = _jug.global_position + Vector3(0.0, 0.0, -30.0)
	var antes_aire := _contar_particulas()
	var vida_aire := float(_enemigo.call("vida_actual"))
	await _pulsar_ataque()
	await get_tree().create_timer(1.2).timeout
	_check(_contar_particulas() <= antes_aire and (_contar_particulas() - antes_aire) <= 0, "golpe AL AIRE: ningún efecto de impacto (%d partículas nuevas)" % (_contar_particulas() - antes_aire))
	_check(is_equal_approx(float(_enemigo.call("vida_actual")), vida_aire), "golpe AL AIRE: tampoco quita vida al que está lejos")

	# Blanco delante, cerca: el golpe conecta y el efecto sale sobre él.
	_enemigo.global_position = _jug.global_position + Vector3(0.0, 0.0, -1.5)
	await get_tree().create_timer(0.4).timeout
	_check(_gestor().call("get_active_enemies").size() >= 1,
			"el gestor FreeFlow ve al enemigo registrado (%d activos)" % _gestor().call("get_active_enemies").size())
	var antes_cerca := _contar_particulas()
	var vida_antes := float(_enemigo.call("vida_actual"))
	await _pulsar_ataque()
	# Sondeo continuo: las partículas de vida corta se liberan solas, así que se
	# mide el PICO de partículas nuevas y se guardan sus posiciones.
	var res := await _esperar_impacto(antes_cerca, 1.5)
	var nuevas := int(res["max"])
	_check(nuevas >= 2, "golpe que CONECTA: efecto de impacto sobre el enemigo (%d partículas nuevas en el pico)" % nuevas)
	_check(float(_enemigo.call("vida_actual")) < vida_antes, "el daño llegó al enemigo (%.0f → %.0f)" % [vida_antes, float(_enemigo.call("vida_actual"))])
	var cerca_del_enemigo := false
	var minima := 999.0
	for p in (res["puntos"] as Array):
		var d := (p as Vector3).distance_to(_enemigo.global_position)
		minima = minf(minima, d)
		if d < 2.0:
			cerca_del_enemigo = true
	_check(cerca_del_enemigo, "el efecto salió pegado al enemigo golpeado (a %.2f m, no en el suelo del jugador)" % minima)

	print("==================== IMPACTO VFX: %d OK / %d FALLO ====================" % [_ok, _fallos])
	# Deja un golpe nuevo para que la CAPTURA final muestre el impacto.
	await _pulsar_ataque()
	await get_tree().create_timer(0.22).timeout


# ------------------------------------------------------------------ auxiliares
func _gestor() -> Node:
	return get_node_or_null("CombatManager")


## Sondea `segundos` y devuelve el pico de partículas nuevas (`max`) con las
## posiciones vistas (`puntos`): las partículas de vida corta se autoliberan, así
## que contar al final daría menos de las que realmente salieron.
func _esperar_impacto(antes: int, segundos: float) -> Dictionary:
	var max_nuevas := 0
	var puntos: Array[Vector3] = []
	var t := 0.0
	while t < segundos:
		await get_tree().physics_frame
		t += 1.0 / 60.0
		var nuevas := _contar_particulas() - antes
		if nuevas > max_nuevas:
			max_nuevas = nuevas
		if nuevas > 0:
			for p in _particulas_nuevas(antes):
				puntos.append((p as Node3D).global_position)
	return {"max": max_nuevas, "puntos": puntos}


func _contar_particulas() -> int:
	var n := 0
	for nodo in _raiz_efectos.find_children("*", "GPUParticles3D", true, false):
		n += 1
	return n


func _particulas_nuevas(desde_indice: int) -> Array[Node3D]:
	var lista: Array[Node3D] = []
	for nodo in _raiz_efectos.find_children("*", "GPUParticles3D", true, false):
		lista.append(nodo as Node3D)
	# Las primeras `desde_indice` son las que ya existían.
	var nuevas: Array[Node3D] = []
	for i in range(lista.size()):
		if i >= desde_indice:
			nuevas.append(lista[i])
	return nuevas


## Pulsa el ataque como el jugador real: `Input.action_press` con la tecla
## mantenida unos fotogramas (igual que la suite de combate ya probada). Con
## `parse_input_event` el controlador no lo veía como "recién pulsado".
func _pulsar_ataque() -> void:
	Input.action_press("atacar")
	for _i in 3:
		await get_tree().physics_frame
	Input.action_release("atacar")
	await get_tree().physics_frame


func _check(condicion: bool, texto: String) -> void:
	if condicion:
		_ok += 1
		print("[impacto-suite] OK   ", texto)
	else:
		_fallos += 1
		print("[impacto-suite] FALLO ", texto)


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
	cam.position = Vector3(3.0, 2.2, 7.0)
	cam.look_at_from_position(Vector3(3.0, 2.2, 7.0), Vector3(1.0, 1.2, 0.0))
	cam.current = true
	add_child(cam)