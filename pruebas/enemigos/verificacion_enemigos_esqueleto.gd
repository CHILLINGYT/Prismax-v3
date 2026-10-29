extends Node3D

# Verificación EN VIVO de los enemigos CON ESQUELETO (cuerpo a cuerpo y tirador).
# NO forma parte del juego: vive en res://pruebas/enemigos/.
#
# A diferencia del monitor de las cápsulas (que filtra por su clase), este
# reconoce a CUALQUIER enemigo del grupo "enemigos_prueba" con is_alive() y un
# nodo Visual (es decir, los de esqueleto) y va imprimiendo cada medio segundo
# cuántos hay, con su vida, su estado y su posición. No aplica daño de guion: el
# jugador sólo recibe lo que le peguen los enemigos.
#
# Se ejecuta desde el editor con la escena abierta y pulsando H (cuerpo a cuerpo)
# o J (tiradores) en el juego; G sigue siendo las cápsulas.

const GRUPO_ENEMIGOS := &"enemigos_prueba"
const NOMBRES_ESTADO := ["CERCO", "ATURDIDO", "ATACAR", "RECUPERAR", "MUERTO"]

@onready var jug: CharacterBody3D = $Jugador
@onready var gerente: Node3D = $EnemigosPrueba

var _frames := 0
var _stats: EstadisticasJugador
var _max_vivos := 0
var _max_tiradores := 0

func _ready() -> void:
	var cam := jug.get_node_or_null("PivoteCamara/Brazo/Camara") as Camera3D
	if cam != null:
		cam.make_current()
	_stats = jug.get_node_or_null("Estadisticas") as EstadisticasJugador
	print("[ESQ] listo: pulsa H (cuerpo a cuerpo) o J (tiradores) para generarlos")

func _physics_process(_delta: float) -> void:
	_frames += 1
	var vivos := 0
	var tiradores := 0
	var linea := ""
	for n in get_tree().get_nodes_in_group(GRUPO_ENEMIGOS):
		var e := n as Node3D
		if e == null or not e.has_method("is_alive"):
			continue
		if e.get_node_or_null("Visual") == null:
			continue  # cápsula u otro tipo sin esqueleto
		if not bool(e.call("is_alive")):
			continue
		vivos += 1
		if e.has_method("_iniciar_disparo"):
			tiradores += 1
		var est := int(e.call("estado_actual"))
		var nombre_estado: String = NOMBRES_ESTADO[est] if est >= 0 and est < NOMBRES_ESTADO.size() else str(est)
		linea += "%s(vida=%.0f %s pos=%s) " % [
				e.name, float(e.call("vida_actual")), nombre_estado,
				str(e.global_position.round())]
	_max_vivos = maxi(_max_vivos, vivos)
	_max_tiradores = maxi(_max_tiradores, tiradores)
	if _frames % 30 == 0:
		var vida := -1.0
		var escudo := -1.0
		if _stats != null:
			vida = _stats.vida
			escudo = _stats.resistencia
		print("[ESQ] f=%d vivos=%d tiradores=%d | jugador(vida=%.0f escudo=%.0f) | %s" % [
				_frames, vivos, tiradores, vida, escudo, linea])