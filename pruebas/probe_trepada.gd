extends Node3D
## SONDA (no es prueba): mide la ORIENTACIÓN real de la trepada del acuático en la
## escalera del barco para saber si el cuerpo sube/baja de espaldas o de frente.
##
## Mide, a mitad de la trepada y al terminar:
##  · dónde quedan las MANOS del modelo respecto al plano de los peldaños (lado del
##    casco = de frente / lado del mar = de espaldas);
##  · hacia dónde mira la cabeza del modelo y hacia dónde mira el propio cuerpo;
##  · dónde acaba el cuerpo al coronar la cubierta y al volver al agua.
##
##   godot --headless --path <proyecto> res://pruebas/probe_trepada.tscn

const JUGADOR := "res://personaje/base/escenas/leo_jugador.tscn"
const BARCO := "res://mundo/entorno/barco.tscn"

var _jug: Node3D
var _esc: EscaleraBarco
var _barco: Node3D

func _ready() -> void:
	_barco = (load(BARCO) as PackedScene).instantiate() as Node3D
	add_child(_barco)
	await get_tree().create_timer(0.6).timeout
	for n in get_tree().get_nodes_in_group("escalera_barco"):
		_esc = n as EscaleraBarco
	if _esc == null:
		print("[trepada] SIN ESCALERA: el barco no registró ninguna")
		return
	_jug = (load(JUGADOR) as PackedScene).instantiate() as Node3D
	add_child(_jug)
	await get_tree().create_timer(0.8).timeout

	# Forma acuática (la única que usa la escalera).
	_jug.call("_on_transformacion_elegida", &"pes")
	var t := 0.0
	while int(_jug.get("forma")) != 2 and t < 6.0:
		await get_tree().physics_frame
		t += 1.0 / 60.0
	await get_tree().create_timer(0.6).timeout

	# Cámara lateral que mira la escalera para la captura.
	var cam := Camera3D.new()
	var p := _esc.global_position
	var lateral := _esc.direccion_mirada().cross(Vector3.UP)
	if lateral.length_squared() < 0.001:
		lateral = Vector3.FORWARD
	lateral = lateral.normalized()
	cam.global_position = p + lateral * 7.0 + Vector3.UP * 1.4
	cam.look_at_from_position(cam.global_position, p + Vector3.UP * 0.6)
	cam.current = true
	add_child(cam)

	print("[trepada] escalera en %s | mirada %s | giro_cuerpo %.3f" % [
			str(p.snapped(Vector3(0.01, 0.01, 0.01))),
			str(_esc.direccion_mirada().snapped(Vector3(0.01, 0.01, 0.01))),
			_esc.giro_cuerpo])
	print("[trepada] inicio %s | tope %s | fin %s" % [
			str(_esc.punto_trepada(0.0).snapped(Vector3(0.01, 0.01, 0.01))),
			str(_esc.punto_trepada(0.82).snapped(Vector3(0.01, 0.01, 0.01))),
			str(_esc.punto_trepada(1.0).snapped(Vector3(0.01, 0.01, 0.01)))])

	# --- SUBIDA ------------------------------------------------------------
	_jug.set("global_position", _esc.punto_trepada(0.0))
	_jug.call("_iniciar_trepada", _esc, false)
	await get_tree().create_timer(0.9).timeout
	_medir("SUBIENDO")
	await get_tree().create_timer(1.2).timeout
	while bool(_jug.get("a_subiendo_escalera")) and t < 20.0:
		await get_tree().physics_frame
		t += 1.0 / 60.0
	await get_tree().create_timer(0.6).timeout
	_medir("EN CUBIERTA (fin subida)")
	print("[trepada] distancia al punto FIN del recorrido: %.2f m" % _jug.global_position.distance_to(_esc.punto_trepada(1.0)))

	# --- BAJADA ------------------------------------------------------------
	_jug.call("_iniciar_trepada", _esc, true)
	await get_tree().create_timer(0.9).timeout
	_medir("BAJANDO")
	await get_tree().create_timer(1.6).timeout
	while bool(_jug.get("a_subiendo_escalera")) and t < 40.0:
		await get_tree().physics_frame
		t += 1.0 / 60.0
	await get_tree().create_timer(0.6).timeout
	_medir("EN EL AGUA (fin bajada)")
	print("[trepada] distancia al punto INICIO del recorrido: %.2f m" % _jug.global_position.distance_to(_esc.punto_trepada(0.0)))

	# --- Captura: se deja una SUBIDA A MEDIAS para poder VER la trepada ---------
	_jug.global_position = _esc.punto_trepada(0.0)
	_jug.call("_iniciar_trepada", _esc, false)
	await get_tree().create_timer(1.3).timeout
	_medir("CAPTURA (subiendo)")
	print("[trepada] FIN")


func _medir(momento: String) -> void:
	var mirada := _esc.direccion_mirada()
	mirada.y = 0.0
	mirada = mirada.normalized()
	var cuerpo := _jug.global_position
	var acu := _jug.get_node_or_null("Acuatico") as Node3D
	var manos := _manos(acu)
	var lado_manos := 999.0
	if manos != Vector3.INF:
		var d := manos - cuerpo
		d.y = 0.0
		lado_manos = d.dot(mirada)
	var mira_cuerpo := 999.0
	var mira_cabeza := 999.0
	if acu != null:
		var f := -acu.global_transform.basis.z
		f.y = 0.0
		if f.length_squared() > 0.0001:
			mira_cuerpo = f.normalized().dot(mirada)
	var cabeza := _hueso(acu, "Head")
	if cabeza != Vector3.INF:
		var dc := cabeza - cuerpo
		dc.y = 0.0
		mira_cabeza = dc.dot(mirada)
	print("[trepada] %s | manos hacia el casco: %+.2f m (positivo = de frente) | mira cuerpo %+.2f | mira cabeza %+.2f | nodo.y %.1f°" % [
			momento, lado_manos, mira_cuerpo, mira_cabeza,
			rad_to_deg(float(_jug.get("acuatico").rotation.y)) if _jug.get("acuatico") != null else 0.0])


## Centro de las MANOS del modelo: los huesos viven dentro del Skeleton3D (no son
## nodos), así que se leen con la pose global de hueso del esqueleto.
func _manos(acu: Node3D) -> Vector3:
	var izq := _hueso(acu, "LeftHand")
	var der := _hueso(acu, "RightHand")
	if izq == Vector3.INF or der == Vector3.INF:
		return Vector3.INF
	return (izq + der) * 0.5


## Posición GLOBAL del hueso cuyo nombre contiene `trozo` (o Vector3.INF). Si el
## trozo es "Head", devuelve además... no: devuelve la posición del hueso.
func _hueso(acu: Node3D, trozo: String) -> Vector3:
	if acu == null:
		return Vector3.INF
	for n in acu.find_children("*", "Skeleton3D", true, false):
		var sk := n as Skeleton3D
		for i in sk.get_bone_count():
			if String(sk.get_bone_name(i)).contains(trozo):
				return (sk.global_transform * sk.get_bone_global_pose(i)).origin
	return Vector3.INF