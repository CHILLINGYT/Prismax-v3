class_name EfectoDanioPantalla
extends CanvasLayer

## Overlay de pantalla del daño del jugador: viñeta roja con matiz azulado en
## los bordes laterales, con el centro despejado.
##
## Es UNA sola capa compartida por todas las transformaciones: el controlador
## del jugador conecta aquí las señales del sistema de vida/escudo que ya existe
## (EstadisticasJugador), así que el efecto reacciona al daño REAL (pérdida de
## salud/escudo confirmada por el sistema), no a una animación de golpe.
##
## - `al_recibir_danio` (señal `danio_recibido`): pulso que aparece rápido y se
##   desvanece tras un breve intervalo. Varios impactos seguidos refuerzan la
##   intensidad sin reiniciar nada a golpe brusco (no hay parpadeo).
## - `al_romper_escudo` (señal `escudo_roto`, solo en la rotura REAL): modo
##   predominantemente rojo, más intenso y de mayor duración, con prioridad
##   visual durante su intervalo. Los impactos que lleguen mientras tanto se
##   registran (refuerzan) sin cortar ese modo ni impedir nuevos eventos.
##
## Nunca crea nodos por impacto: solo actualiza los uniforms del material.

@export_group("Viñeta")
## Cuánto azul oscuro lleva la mezcla en el pulso de daño normal (0 = solo rojo).
@export_range(0.0, 1.0, 0.01) var mezcla_azul_normal: float = 0.45
## Mezcla durante la rotura de escudo: casi solo rojo, más evidente.
@export_range(0.0, 1.0, 0.01) var mezcla_azul_rotura: float = 0.10

@export_group("Pulso de daño")
@export_range(0.0, 1.0, 0.01) var intensidad_danio: float = 0.55
## Refuerzo de intensidad por punto de daño recibido (para golpes más fuertes).
@export var refuerzo_por_danio: float = 0.006
## Techo de intensidad del pulso normal.
@export_range(0.0, 1.0, 0.01) var techo_danio: float = 0.75
## Tiempo a intensidad plena antes de empezar a desvanecerse.
@export var retencion_danio: float = 0.14
## Velocidad de subida y de bajada de la intensidad (por segundo).
@export var velocidad_aparicion: float = 10.0
@export var velocidad_bajada: float = 2.6

@export_group("Rotura de escudo")
@export_range(0.0, 1.0, 0.01) var intensidad_rotura: float = 0.90
## Duración del modo rotura con prioridad visual (después se desvanece solo).
@export var duracion_rotura: float = 1.7

var _intensidad: float = 0.0
var _objetivo: float = 0.0
var _t_retencion: float = 0.0
var _t_rotura: float = 0.0
var _material: ShaderMaterial


func _ready() -> void:
	set_process(false)
	var vineta := get_node_or_null("Vineta") as ColorRect
	if vineta != null:
		_material = vineta.material as ShaderMaterial
	_aplicar_uniforms()


## Daño confirmado por el sistema de vida (señal `danio_recibido`).
func al_recibir_danio(cantidad: float) -> void:
	if _t_rotura > 0.0:
		# La rotura conserva la prioridad visual durante su intervalo; el impacto
		# solo refuerza el rojo sin cambiar de modo ni reiniciar el desvanecido.
		_objetivo = maxf(_objetivo, minf(intensidad_rotura, _intensidad + refuerzo_por_danio * cantidad))
		return
	_objetivo = maxf(_objetivo, minf(techo_danio, intensidad_danio + refuerzo_por_danio * cantidad))
	_t_retencion = retencion_danio
	set_process(true)


## Rotura REAL del escudo (señal `escudo_roto`: la resistencia pasó de tener
## carga a cero con este golpe; con el escudo ya roto no se vuelve a emitir).
func al_romper_escudo() -> void:
	_t_rotura = duracion_rotura
	_t_retencion = 0.0
	_objetivo = maxf(_objetivo, intensidad_rotura)
	set_process(true)


func _process(delta: float) -> void:
	if _t_rotura > 0.0:
		# Prioridad de la rotura: la intensidad se mantiene arriba todo el intervalo.
		_t_rotura -= delta
		_objetivo = maxf(_objetivo, intensidad_rotura)
	elif _t_retencion > 0.0:
		_t_retencion -= delta
	else:
		_objetivo = move_toward(_objetivo, 0.0, velocidad_bajada * delta)

	var paso := (velocidad_aparicion if _objetivo > _intensidad else velocidad_bajada) * delta
	_intensidad = move_toward(_intensidad, _objetivo, paso)
	_aplicar_uniforms()

	if _intensidad <= 0.001 and _objetivo <= 0.001 and _t_rotura <= 0.0:
		_intensidad = 0.0
		_aplicar_uniforms()
		set_process(false)


func _aplicar_uniforms() -> void:
	if _material == null:
		return
	_material.set_shader_parameter("intensidad", _intensidad)
	_material.set_shader_parameter("mezcla_azul", mezcla_azul_rotura if _t_rotura > 0.0 else mezcla_azul_normal)