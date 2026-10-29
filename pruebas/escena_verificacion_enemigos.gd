extends Node3D

# Escena de verificación EN VIVO del sistema de ENEMIGOS DE PRUEBA de la partida
# principal y de la viñeta de daño del HUD.
#
# NO forma parte del juego: vive en res://pruebas/ y sólo sirve para comprobar a
# ojo, con el jugador REAL y una pista plana con luz, la lista de pruebas del
# encargo:
#   1. la tecla G genera seis cápsulas alrededor del jugador (con barra de vida);
#   2. las cápsulas cercan al jugador y se reparten en anillo;
#   3. nunca atacan más de dos a la vez (se mide y se imprime el máximo);
#   4. cada golpe enemigo quita vida/escudo por el sistema real (HUD);
#   5. la viñeta de daño pulsa en rojo azulado con escudo y se queda roja fija
#      cuando el escudo se rompe.
#
# Los golpes del guion (fotogramas 180 y 300) entran por la MISMA vía que los
# golpes de los enemigos —EstadisticasJugador.recibir_danio()— para poder ver
# los dos estados de la viñeta dentro de una captura corta.
#
# Se ejecuta desde el editor con la escena abierta y pulsando G en el juego.

const ClaseEnemigo := preload("res://enemigos/Scripts/enemigo_prueba.gd")
const GRUPO_ENEMIGOS := &"enemigos_prueba"
const GRUPO_GESTOR := &"combat_manager"
const NOMBRES_ESTADO := ["CERCO", "ATURDIDO", "PREPARAR", "GOLPEAR", "RECUPERAR", "MUERTO"]
const FRAME_GOLPES := 180      # ~3 s: golpes con escudo -> viñeta rojo azulada
const FRAME_ROTURA := 300      # ~5 s: escudo a cero -> viñeta roja persistente
const FRAME_VEREDICTO := 420   # ~7 s: resumen final

@onready var jug: CharacterBody3D = $Jugador
@onready var gerente: Node3D = $EnemigosPrueba

var _stats: EstadisticasJugador
var _mgr: Node
var _mat_vineta: ShaderMaterial
var _frames := 0
var _max_vivos := 0
var _max_turnos := 0
var _golpes_guion := 0
var _danios_jugador := 0
var _roto_ya := false
var _veredicto_dado := false
var _estados_vistos := {}

func _ready() -> void:
	print("[MON] verificación en vivo de enemigos lista: pulsa G para generarlos")
	var cam := jug.get_node_or_null("PivoteCamara/Brazo/Camara") as Camera3D
	if cam != null:
		cam.make_current()
	_stats = jug.get_node_or_null("Estadisticas") as EstadisticasJugador
	_mgr = get_tree().get_first_node_in_group(GRUPO_GESTOR)
	var hud := jug.get_node_or_null("HUD")
	if hud != null:
		var vineta := hud.get_node_or_null("Raiz/VinetaDano") as ColorRect
		if vineta != null:
			_mat_vineta = vineta.material as ShaderMaterial
	print("[MON] gestor=%s | estadisticas=%s | vineta=%s" % [
			"ok" if _mgr != null else "FALTA",
			"ok" if _stats != null else "FALTA",
			"ok" if _mat_vineta != null else "FALTA"])
	if _stats != null:
		_stats.danio_recibido.connect(_al_recibir_danio)

func _al_recibir_danio(_cantidad: float) -> void:
	_danios_jugador += 1

func _physics_process(_delta: float) -> void:
	_frames += 1
	var vivos := 0
	var turnos := 0
	var resumen := ""
	for n in get_tree().get_nodes_in_group(GRUPO_ENEMIGOS):
		if not is_instance_valid(n) or not (n is ClaseEnemigo):
			continue
		var e: Node3D = n
		vivos += 1
		var estado: int = int(e.estado_actual())
		_estados_vistos[estado] = true
		if _mgr != null:
			var tokens: Variant = _mgr.get("tokens")
			if tokens != null and bool(tokens.has_token(e)):
				turnos += 1
		resumen += "%s:v%d/%s " % [e.name, int(e.vida_actual()), NOMBRES_ESTADO[estado]]
	_max_vivos = maxi(_max_vivos, vivos)
	_max_turnos = maxi(_max_turnos, turnos)

	if _frames == FRAME_GOLPES:
		print("[MON] --- golpes con escudo (guion, por la misma vía que los enemigos) ---")
		for _i in 3:
			_golpes_guion += 1
			_stats.recibir_danio(20.0)
	if _frames == FRAME_ROTURA and not _roto_ya:
		_roto_ya = true
		print("[MON] --- escudo a cero (guion): la viñeta debe quedarse ROJA ---")
		_stats.resistencia = 0.0
		_stats.resistencia_cambiada.emit(0.0, _stats.resistencia_max)
	if _frames % 30 == 0:
		var intensidad := 0.0
		var color := Color.BLACK
		if _mat_vineta != null:
			intensidad = float(_mat_vineta.get_shader_parameter("intensidad"))
			color = _mat_vineta.get_shader_parameter("color")
		print("[MON] f=%d vivos=%d atacando=%d vida=%.0f escudo=%.0f viñeta(int=%.2f color=%s) | %s" % [
				_frames, vivos, turnos, _stats.vida, _stats.resistencia,
				intensidad, str(color), resumen])
	if _frames >= FRAME_VEREDICTO and not _veredicto_dado:
		_veredicto_dado = true
		var estados_nombres: Array = []
		for k in _estados_vistos.keys():
			estados_nombres.append(NOMBRES_ESTADO[int(k)])
		estados_nombres.sort()
		print("[MON] VEREDICTO: max vivos=%d | max atacantes simultáneos=%d (límite 2) | golpes guion=%d | daños reales=%d | vida=%.0f escudo=%.0f | estados vistos=%s" % [
				_max_vivos, _max_turnos, _golpes_guion, _danios_jugador,
				_stats.vida, _stats.resistencia, str(estados_nombres)])