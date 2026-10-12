extends Node3D

## VISTA PREVIA (desarrollo). No forma parte del juego.
##
## Encuadra de frente a un enemigo tirador y reproduce el clip "disparar" en bucle
## para comprobar A OJO que el arma 3D queda bien sujeta a la mano derecha
## (posición/orientación), que no flota ni atraviesa el cuerpo y que el cañón
## apunta hacia adelante, en la misma dirección en la que sale el proyectil.
##
## La IA del tirador se desactiva (`set_physics_process(false)`) para que no
## cambie el clip; el AnimationPlayer sigue funcionando por su cuenta.

const CLIP := "disparar"

@onready var _ap: AnimationPlayer = $Tirador/Animador
@onready var _cam: Camera3D = $Camara
@onready var _tir: Node3D = $Tirador
@onready var _arma: Node3D = $Tirador/Visual/Skeleton3D/AnclajeArma/ArmaTirador

var _t := 0.0
var _impreso := false

func _ready() -> void:
	_tir.set_physics_process(false)
	_cam.look_at_from_position(Vector3(2.4, 1.5, 0.0), Vector3(0.0, 1.25, 0.0), Vector3.UP)
	if _ap.has_animation(CLIP):
		var a := _ap.get_animation(CLIP)
		if a != null:
			a.loop_mode = Animation.LOOP_LINEAR
		_ap.play(CLIP)
		print("[VISTA] clip=", CLIP)
	else:
		print("[VISTA] FALTA el clip ", CLIP)

func _process(delta: float) -> void:
	_t += delta
	if _impreso or _t < 0.6:
		return
	_impreso = true
	var ag := _arma.global_transform
	print("[VISTA] arma_global O=", ag.origin, " Z=", ag.basis.z)
	var boca := _arma.find_child("BocaArma", true, false) as Node3D
	if boca != null:
		print("[VISTA] boca_global=", boca.global_position)