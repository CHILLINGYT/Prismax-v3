extends Node3D
## PRUEBA AISLADA del disparo del enemigo TIRADOR (Tareas 1 y 2).
##
## Usa el jugador REAL, el tirador REAL y el proyectil REAL. Comprueba:
##   A. el proyectil se instancia CON su script (antes no compilaba) y se mueve;
##   B. el impacto contra el jugador aplica el daño UNA sola vez y por el sistema
##      real (EstadisticasJugador.recibir_danio), con el valor configurado;
##   C. si el tirador muere con la bala en vuelo, la bala sigue y no hay errores;
##   D. un disparo CANCELADO (tirador aturdido mientras apunta) no suelta bala ni daña;
##   E. el tirador real, en combate, hace daño al jugador a distancia;
##   F. (Tarea 2) cartucho visible durante el vuelo, orientado a lo largo del
##      recorrido, con una estela que lo acompaña y que se libera con la bala.

const TIRADOR := preload("res://enemigos/Scenes/enemigo_tirador.tscn")
const PROYECTIL := preload("res://enemigos/Scenes/proyectil_enemigo.tscn")

var _ok := 0
var _fallos := 0
var _danios: Array[float] = []
var _proyectiles_creados := 0

@onready var jugador: CharacterBody3D = $Jugador


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var stats := jugador.get_node("Estadisticas") as EstadisticasJugador
	stats.danio_recibido.connect(func(c: float) -> void: _danios.append(c))
	# Cualquier nodo del árbol (el tirador cuelga sus balas de SU padre, no de aquí).
	get_tree().node_added.connect(_al_entrar_hijo)
	await _prueba_proyectil_directo(stats)
	await _prueba_duenio_liberado()
	await _prueba_cancelado()
	await _prueba_tirador_real()
	print("==================== DISPARO TIRADOR: %d OK / %d FALLO ====================" % [_ok, _fallos])


func _al_entrar_hijo(n: Node) -> void:
	if n.has_method("lanzar"):
		_proyectiles_creados += 1


func _check(cond: bool, texto: String) -> void:
	if cond:
		_ok += 1
		print("[disparo] OK    ", texto)
	else:
		_fallos += 1
		print("[disparo] FALLO ", texto)


func _esperar_fisica(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


## A + B + F: una bala lanzada a mano hacia el pecho del jugador.
func _prueba_proyectil_directo(stats: EstadisticasJugador) -> void:
	var p := PROYECTIL.instantiate() as Node3D
	_check(p.get_script() != null and p.has_method("lanzar"),
			"A. el proyectil se instancia CON su script (lanzar disponible)")
	add_child(p)
	var origen := Vector3(0.0, 1.0, 10.0)
	var destino := jugador.global_position + Vector3.UP * 1.0
	p.call("lanzar", origen, destino - origen, null, 20.0, 8.0)
	var vida0 := stats.vida + stats.resistencia
	_danios.clear()
	await _esperar_fisica(3)
	var recorrido := p.global_position.distance_to(origen) if is_instance_valid(p) else -1.0
	_check(recorrido > 0.5, "A. el proyectil AVANZA (%.2f m en 3 fotogramas)" % recorrido)
	# F: el cartucho se ve y va alineado con el vuelo; la estela existe.
	if is_instance_valid(p):
		var mun := p.get_node_or_null("Municion") as Node3D
		var visible_ok := mun != null and mun.is_visible_in_tree()
		_check(visible_ok, "F. el cartucho real se ve en vuelo")
		if mun != null:
			# El eje largo del modelo es su +Y local: debe apuntar hacia el destino.
			var eje := mun.global_transform.basis.y.normalized()
			var vuelo := (destino - origen).normalized()
			_check(eje.dot(vuelo) > 0.98, "F. la punta del cartucho mira hacia donde vuela (dot %.3f)" % eje.dot(vuelo))
			var esc := mun.global_transform.basis.get_scale()
			_check(is_equal_approx(esc.x, esc.y) and is_equal_approx(esc.y, esc.z) and esc.x > 0.0,
					"F. escala UNIFORME del cartucho (%s)" % str(esc))
		var estela := p.get_node_or_null("Estela") as Node3D
		_check(estela != null and estela.is_visible_in_tree(), "F. la bala lleva su estela de trazadora")
		if estela != null:
			var cola := estela.global_transform.basis.y
			var vuelo2 := (destino - origen).normalized()
			_check(cola.normalized().dot(-vuelo2) > 0.98,
					"F. la estela queda DETRÁS de la bala, marcando la trayectoria (dot %.3f)" % cola.normalized().dot(-vuelo2))
			_check(cola.length() <= recorrido + 0.01,
					"F. la estela no es más larga que lo recorrido (%.2f ≤ %.2f m)" % [cola.length(), recorrido])
			var mat := (estela as MeshInstance3D).mesh.surface_get_material(0) as StandardMaterial3D
			_check(mat != null and mat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED and (estela as MeshInstance3D).cast_shadow == 0,
					"F. estela liviana: material sin sombreado y sin proyectar sombra")
		# Centro del cartucho sobre la esfera de colisión (el origen del proyectil).
		if mun != null:
			var centro := mun.global_transform * Vector3(0.0, 0.2241, 0.0)
			_check(centro.distance_to(p.global_position) < 0.02,
					"F. el cartucho va centrado sobre lo que choca (%.3f m)" % centro.distance_to(p.global_position))
	var estela_ref: Node = p.get_node_or_null("Estela") if is_instance_valid(p) else null
	await _esperar_fisica(60)
	_check(not is_instance_valid(p), "B. la bala se destruye al impactar")
	_check(_danios.size() == 1, "B. UN solo daño por impacto (%d)" % _danios.size())
	_check(_danios.size() == 1 and is_equal_approx(_danios[0], 8.0),
			"B. el daño es el configurado, sin inflar (%s)" % str(_danios))
	var vida1 := stats.vida + stats.resistencia
	_check(vida1 < vida0, "B. vida+escudo del jugador bajan por el sistema real (%.1f -> %.1f)" % [vida0, vida1])
	await _esperar_fisica(2)
	_check(estela_ref == null or not is_instance_valid(estela_ref),
			"F. la estela se libera junto con la bala (sin nodos huérfanos)")


## C: el tirador muere (se libera) con la bala en vuelo.
func _prueba_duenio_liberado() -> void:
	var t := TIRADOR.instantiate() as Node3D
	t.position = Vector3(30.0, 0.0, 30.0)
	add_child(t)
	await _esperar_fisica(2)
	var p := PROYECTIL.instantiate() as Node3D
	add_child(p)
	var origen := Vector3(0.0, 1.0, 12.0)
	_danios.clear()
	p.call("lanzar", origen, jugador.global_position + Vector3.UP - origen, t, 20.0, 8.0)
	await _esperar_fisica(2)
	t.free()
	await _esperar_fisica(60)
	_check(not is_instance_valid(p) and _danios.size() == 1,
			"C. con el tirador ya liberado la bala sigue, impacta y daña una vez (%d)" % _danios.size())


## D: el tirador (creado por el GERENTE, como en el juego) empieza a apuntar y lo
## aturden antes de soltar la bala. Control: sin aturdir, el mismo disparo SÍ sale.
func _prueba_cancelado() -> void:
	var gerente := $EnemigosPrueba
	var t := gerente.call("crear_enemigo_en", Vector3(0.0, 0.0, 9.0), 2) as Node3D
	_check(t != null and t.has_method("_iniciar_disparo"), "D. el gerente crea un tirador real")
	await _esperar_fisica(20)
	# Control positivo: un disparo iniciado y NO cancelado suelta bala.
	var antes_ok := _proyectiles_creados
	t.call("_iniciar_disparo")
	await _esperar_fisica(70)
	_check(_proyectiles_creados > antes_ok, "D. (control) sin cancelar, el disparo iniciado SÍ suelta bala")
	# Cancelado: se inicia y, antes del fotograma del disparo, lo aturden.
	await _esperar_fisica(30)
	_danios.clear()
	var antes := _proyectiles_creados
	t.call("_iniciar_disparo")
	await _esperar_fisica(1)
	t.call("take_hit", 1.0, Vector3.FORWARD, 0.0, 1.5)
	# Ventana menor que el aturdimiento: el disparo cancelado no debe salir nunca.
	await _esperar_fisica(70)
	_check(_proyectiles_creados == antes, "D. disparo CANCELADO por aturdimiento: no sale ninguna bala (%d)" % (_proyectiles_creados - antes))
	_check(_danios.is_empty(), "D. y el jugador no recibe daño (%d)" % _danios.size())
	gerente.call("retirar_grupo")
	if is_instance_valid(t):
		t.queue_free()
	await _esperar_fisica(30)


## E: un tirador real creado por el gerente, con su IA de siempre.
func _prueba_tirador_real() -> void:
	var t := $EnemigosPrueba.call("crear_enemigo_en", Vector3(0.0, 0.0, 10.0), 2) as Node3D
	# Tarea 3: el volumen del disparo, en el tirador REAL (no en la escena suelta).
	await _esperar_fisica(2)
	var son := t.find_child("SonidoDisparo", true, false) as AudioStreamPlayer3D
	_check(son != null and is_equal_approx(son.volume_db, -12.0),
			"T3. el disparo del tirador suena a -12 dB (antes -4: 8 dB menos) (%s)" % (str(son.volume_db) if son else "sin nodo"))
	_check(son != null and son.bus == &"Efectos", "T3. sigue en el bus Efectos, que no se modificó")
	_check(son is AudioStreamPlayer3D and son.unit_size > 0.0,
			"T3. sigue siendo audio 3D posicional (AudioStreamPlayer3D, unit_size %.1f)" % (son.unit_size if son else 0.0))
	_check(is_equal_approx(VocesAparicion.VOLUMEN_DB, -6.0), "T3. las voces de aparición no cambian (-6 dB)")
	_danios.clear()
	var antes := _proyectiles_creados
	for i in 480:
		await get_tree().physics_frame
		if _danios.size() >= 2:
			break
	var disparos := _proyectiles_creados - antes
	_check(disparos >= 1, "E. el tirador real suelta proyectiles de verdad (%d)" % disparos)
	_check(_danios.size() >= 1, "E. y le hacen daño real al jugador a distancia (%d impactos)" % _danios.size())
	_check(_danios.size() <= disparos, "E. nunca más daños que balas (%d daños / %d balas)" % [_danios.size(), disparos])
	$EnemigosPrueba.call("retirar_grupo")
	if is_instance_valid(t):
		t.queue_free()
