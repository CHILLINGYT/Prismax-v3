extends Node3D

# DIAGNÓSTICO AISLADO: ¿el proyectil enemigo daña de verdad al jugador?
# Se ejecuta como escena headless/live. Mide la vida AUTORITATIVA (estado_de_forma)
# y el número de señal danio_recibido. Comprueba:
#   A) un proyectil lanzado directo al pecho del jugador, sin obstáculos;
#   B) un tirador REAL disparando por su cuenta durante varios segundos.

const ESCENA_PROYECTIL := preload("res://Enemigos Prueba/Scenes/proyectil_enemigo.tscn")

var _danios := 0

@onready var gerente: Node3D = $EnemigosPrueba
@onready var jugador: CharacterBody3D = $Jugador
@onready var stats: EstadisticasJugador = $Jugador/Estadisticas

func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	stats.danio_recibido.connect(func(_c: float) -> void: _danios += 1)
	print("[diag] jugador layer=%d mask=%d | stats=%s" % [
			jugador.collision_layer, jugador.collision_mask, str(stats != null)])

	var origen := jugador.global_position + Vector3(0.0, 1.0, 4.0)
	var dir := (jugador.global_position + Vector3(0.0, 1.0, 0.0) - origen).normalized()

	# ---- Sonda física manual: ¿qué devuelve el barrido del proyectil? ----
	_sondar(origen, dir)

	# ---- A) Proyectil directo al pecho, sin obstáculos ----
	stats.reiniciar()
	_danios = 0
	var va := _vida()
	var p: Node = ESCENA_PROYECTIL.instantiate()
	get_tree().root.add_child(p)
	await get_tree().process_frame
	p.call("lanzar", origen, dir, null, 26.0, 8.0)
	for i in 30:
		await get_tree().physics_frame
	print("[diag] A) proyectil directo: vida %.1f -> %.1f | danios=%d | proyectil_vivo=%s" % [
			va, _vida(), _danios, str(is_instance_valid(p))])

	# ---- B) Tirador real disparando por su cuenta ----
	stats.reiniciar()
	_danios = 0
	var vb := _vida()
	gerente.set("cantidad_tirador", 1)
	gerente.call("retirar_grupo")
	await get_tree().process_frame
	gerente.call("generar_tipo", 2)
	for i in 480:
		await get_tree().physics_frame
	print("[diag] B) tirador real: vida %.1f -> %.1f | danios=%d" % [vb, _vida(), _danios])

	# ---- C) Daño en OTRA transformación (mismo cuerpo físico comparte Estadisticas) ----
	stats.reiniciar()
	_danios = 0
	if jugador.has_method("_on_transformacion_elegida"):
		jugador.call("_on_transformacion_elegida", &"velocista")
		var t := 0
		while bool(jugador.get("_transformando")) and t < 900:
			await get_tree().physics_frame
			t += 1
		await get_tree().physics_frame
	var vc := _vida()
	var origenC := jugador.global_position + Vector3(0.0, 1.0, 4.0)
	var dirC := (jugador.global_position + Vector3(0.0, 1.0, 0.0) - origenC).normalized()
	var pc: Node = ESCENA_PROYECTIL.instantiate()
	get_tree().root.add_child(pc)
	await get_tree().process_frame
	pc.call("lanzar", origenC, dirC, null, 26.0, 8.0)
	for i in 30:
		await get_tree().physics_frame
	print("[diag] C) forma=%s tras transformar: vida %.1f -> %.1f | danios=%d" % [
			str(jugador.get("forma")), vc, _vida(), _danios])

	get_tree().quit()

func _vida() -> float:
	return float(stats.estado_de_forma(stats.forma_actual()).get("vida", -1.0))

## Replica EXACTA de la consulta del proyectil: barrido de esfera + búsqueda del
## collider en el punto de impacto. Imprime qué devuelve cada paso.
func _sondar(desde: Vector3, dir: Vector3) -> void:
	var espacio := get_world_3d().direct_space_state
	var bola := SphereShape3D.new()
	bola.radius = 0.14
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = bola
	q.collide_with_bodies = true
	q.collide_with_areas = false
	q.collision_mask = 1
	q.exclude = []
	var paso := dir * 10.0
	q.transform = Transform3D(Basis(), desde)
	q.motion = paso
	var fr := espacio.cast_motion(q)
	print("[sonda] cast_motion=", fr)
	if fr.is_empty():
		return
	# (1) intersect_shape EXACTAMENTE en el punto de parada segura (lo que hace hoy el proyectil)
	var choque := desde + paso * fr[0]
	q.transform = Transform3D(Basis(), choque)
	q.motion = Vector3.ZERO
	var r_safe := espacio.intersect_shape(q, 4)
	print("[sonda] intersect_shape en frac segura=%.4f -> n=%d %s" % [fr[0], r_safe.size(), _colliders(r_safe)])
	# (2) intersect_shape en la fracción INSEGURA (donde ya hay solape)
	var choque2 := desde + paso * fr[1]
	q.transform = Transform3D(Basis(), choque2)
	var r_unsafe := espacio.intersect_shape(q, 4)
	print("[sonda] intersect_shape en frac insegura=%.4f -> n=%d %s" % [fr[1], r_unsafe.size(), _colliders(r_unsafe)])
	# (3) un rayo por el mismo segmento
	var rayo := PhysicsRayQueryParameters3D.create(desde, desde + paso, 1, [] as Array[RID])
	var golpe := espacio.intersect_ray(rayo)
	print("[sonda] intersect_ray -> %s" % (str(golpe.get("collider")) if not golpe.is_empty() else "vacío"))

func _colliders(res: Array) -> String:
	var out: Array[String] = []
	for r in res:
		out.append(str(r.get("collider")))
	return str(out)