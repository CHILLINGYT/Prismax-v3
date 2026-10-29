extends Node3D

## ESCENA DE VISTA PREVIA (desarrollo). No forma parte del juego.
##
## Sirve para comprobar a ojo que el retargeting de las animaciones del enemigo
## (librería `res://Enemigos Prueba/Animations/enemigo_animations.tres`) DEFORMA bien
## la skin: extremidades sin torsionar, sin desplazamientos raros y los pies apoyados.
##
## Mientras la skin definitiva riggeada no esté en el proyecto, la escena instancia el
## rig Mixamo Tripo que se usó como PROXY al hornear. Cuando llegue la skin nueva:
##   1. cambia el PackedScene "Skin" de la escena por la skin riggeada,
##   2. vuelve a hornear con `BakerAnimacionesEnemigo.bake(<ruta de la skin>)`,
##   3. vuelve a ejecutar esta escena.
##
## Va reproduciendo los clips en bucle, uno detrás de otro, y los anuncia por consola.

const CLIPS := [
	"caminar_combate", "golpe_3", "recibir_combate",
	"idle_arma", "disparar", "muerte_1",
]
const SEGUNDOS_POR_CLIP := 2.0

@onready var _ap: AnimationPlayer = $Player

var _i := 0


func _ready() -> void:
	# Marco de referencia: el suelo a la altura de los pies del modelo.
	_play()
	var t := Timer.new()
	t.wait_time = SEGUNDOS_POR_CLIP
	t.one_shot = false
	add_child(t)
	t.timeout.connect(_next)
	t.start()


func _next() -> void:
	_i = (_i + 1) % CLIPS.size()
	_play()


func _play() -> void:
	var clip: String = CLIPS[_i]
	if not _ap.has_animation(clip):
		print("[VERIF] FALTA el clip ", clip)
		return
	_ap.play(clip)
	print("[VERIF] clip=", clip, " dur=%.2fs" % _ap.get_animation(clip).length)