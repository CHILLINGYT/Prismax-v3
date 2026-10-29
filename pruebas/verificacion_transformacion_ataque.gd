extends Node3D

# Escena de verificación EN VIVO de la transformación de ataque (forma Combate).
#
# NO forma parte del juego: vive en res://pruebas/ y sólo sirve para comprobar,
# con el jugador REAL y una pista plana con luz, la lista de pruebas del
# encargo:
#   1. F abre el menú y ofrece "Combate";
#   2. el clic en Combate carga la forma (modelo + animación);
#   3. el FOV usa el mecanismo central de las demás formas (CamaraZiba);
#   4. en el suelo el clic izquierdo ataca (cadena FreeFlow);
#   5. en el aire ningún clic inicia ni encola ataques;
#   6. al aterrizar no queda ningún ataque pendiente;
#   7. las demás transformaciones siguen funcionando.
#
# Imprime cada cambio relevante del jugador (forma, estado del combate, suelo)
# para que la prueba en vivo deje evidencia legible en la consola del juego, y
# saca un veredicto del bloqueo aéreo al aterrizar.

const NOMBRES_ESTADO := ["LIBRE", "ACERCARSE", "PREPARAR", "ACTIVO", "RECUPERAR"]

@onready var jug: CharacterBody3D = $Jugador

var _estado_prev: int = -1
var _forma_prev: StringName = &""
var _armado := false
var _frames_en_suelo := 0
var _hubo_aire := false
var _aterrizo := false
var _clics_aire := 0
var _clics_suelo := 0
var _golpes := 0
var _golpes_aire := 0
var _clics_suelo_tras_aterrizar := 0
var _golpes_tras_aterrizar := 0
var _frames_tras_aterrizar := 0
var _veredicto_dado := false

func _ready() -> void:
	print("[MON] escena de verificación lista")
	if jug == null:
		return
	jug.menu_transf.menu_abierto.connect(_al_abrir_menu)
	jug.menu_transf.menu_cerrado.connect(_al_cerrar_menu)
	jug.menu_transf.transformacion_elegida.connect(_al_elegir)

func _al_abrir_menu() -> void:
	print("[MON] F: menú radial ABIERTO")

func _al_cerrar_menu() -> void:
	print("[MON] F: menú radial CERRADO")

func _al_elegir(id: StringName) -> void:
	print("[MON] menú: transformación elegida = ", id)

func _physics_process(_delta: float) -> void:
	if jug == null:
		return
	var forma: StringName = jug.id_forma()
	if forma != _forma_prev:
		print("[MON] forma = %s | modelo ataque visible = %s" % [String(forma), str(jug.ataque_visual.visible)])
		_forma_prev = forma
	var estado: int = int(jug.c_estado)
	if estado != _estado_prev:
		var nombre: String = NOMBRES_ESTADO[estado] if estado >= 0 and estado < NOMBRES_ESTADO.size() else str(estado)
		print("[MON] estado combate -> %s (suelo=%s)" % [nombre, str(jug.is_on_floor())])
		if estado != 0:
			_golpes += 1
			if not jug.is_on_floor():
				_golpes_aire += 1
			if _aterrizo:
				_golpes_tras_aterrizar += 1
		_estado_prev = estado
	var en_suelo: bool = jug.is_on_floor()
	# La medición no arranca hasta que el jugador lleva unos fotogramas estable
	# en el suelo: la caída inicial de la aparición no debe contarse como salto.
	if not _armado:
		_frames_en_suelo = _frames_en_suelo + 1 if en_suelo else 0
		if _frames_en_suelo >= 15:
			_armado = true
			print("[MON] medición armada (jugador estable en el suelo)")
		return
	if Input.is_action_just_pressed("atacar"):
		if en_suelo:
			_clics_suelo += 1
			if _aterrizo:
				_clics_suelo_tras_aterrizar += 1
		else:
			_clics_aire += 1
	if not en_suelo:
		if not _hubo_aire:
			print("[MON] salto: el cuerpo está en el aire")
		_hubo_aire = true
	elif _hubo_aire and not _aterrizo:
		_aterrizo = true
		print("[MON] aterrizó | clics en el aire = %d | ataques iniciados en el aire = %d" % [_clics_aire, _golpes_aire])
	if _aterrizo and not _veredicto_dado:
		_frames_tras_aterrizar += 1
		if _frames_tras_aterrizar >= 45:
			_veredicto_dado = true
			var ok: bool = _golpes_aire == 0 and _golpes_tras_aterrizar <= _clics_suelo_tras_aterrizar
			var veredicto := "PASA" if ok else "FALLA"
			print("[MON] VEREDICTO BLOQUEO AÉREO: %s | clics aire=%d, golpes aire=%d, golpes tras aterrizar=%d (clics de suelo tras aterrizar=%d), clics suelo=%d, golpes suelo=%d" % [
				veredicto, _clics_aire, _golpes_aire, _golpes_tras_aterrizar,
				_clics_suelo_tras_aterrizar, _clics_suelo, _golpes])