class_name SalidaInterior
extends Node3D
## =============================================================================
##  LA SALIDA DE LA CASA DE LEO (interior)
## =============================================================================
##  Está DELANTE DEL VANO por el que se entra (el del pasillo: el mismo por el que
##  aparece Leo), no en mitad del salón. `casa_leo.gd` la coloca en el punto real
##  medido del modelo y le da su lado (`normal`): el aviso del HUD sólo se ofrece
##  desde el pasillo — nunca desde el otro lado del muro (el dormitorio), donde no
##  hay puerta ninguna.
##
##  Al pulsar E vuelve a la ciudad con la misma pantalla de carga del juego y el
##  punto de vuelta que dejó la puerta de la calle (delante de su portal, mirando a
##  la calle). El aviso va por el canal de siempre: el controlador lo publica en
##  `texto_interaccion()` y el HUD lo pinta con su fundido.

## Radio (m) del aviso: cubre el pasillo delante de la puerta, no el dormitorio.
const RADIO_SALIDA := 1.1
const TEXTO := "Presiona E para salir a la ciudad"
## Segundos que la salida se ignora después de usarla (nunca cuenta dos veces).
const ESPERA := 1.0

@export var radio := RADIO_SALIDA
## Lado en el que SÍ se sale (el pasillo). Lo escribe `casa_leo.gd`.
@export var normal := Vector3.LEFT

var _usando := false
var _t_espera := 0.0


func _ready() -> void:
	add_to_group("salida_interior")
	set_process(true)


func _process(delta: float) -> void:
	if _t_espera > 0.0:
		_t_espera = maxf(0.0, _t_espera - delta)


func texto_prompt() -> String:
	return TEXTO


## ¿Leo está delante de la puerta? Dentro del radio Y del lado del pasillo.
func en_rango() -> bool:
	var jugador := get_tree().get_first_node_in_group("player") as Node3D
	if jugador == null:
		return false
	var d := jugador.global_position - global_position
	d.y = 0.0
	if normal.length_squared() > 0.001 and d.dot(normal.normalized()) < 0.0:
		return false
	return d.length() <= radio


func puede_usar() -> bool:
	return not _usando and _t_espera <= 0.0 and en_rango()


## Vuelve a la ciudad por la puerta de la calle (punto de vuelta ya marcado).
func intentar_usar() -> bool:
	if not puede_usar():
		return false
	_usando = true
	_t_espera = ESPERA
	if not EstadoCasaLeo.hay_vuelta():
		# Sin punto de vuelta (por ejemplo, si se abrió la casa por su cuenta para
		# probarla) se vuelve igual: el mundo coloca a Leo donde pueda.
		EstadoCasaLeo.marcar_vuelta(global_position + Vector3(0.0, 0.0, 1.5), Vector3.FORWARD)
	print("[casa] saliendo a la ciudad desde la puerta interior")
	EstadoCasaLeo.salir(self)
	return true