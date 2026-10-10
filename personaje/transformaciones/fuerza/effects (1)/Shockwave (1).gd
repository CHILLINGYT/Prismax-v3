class_name FuerzaShockwave
extends Node3D

## =============================================================================
##  Shockwave.gd — onda expansiva del pisotón
## =============================================================================
##  Se coloca en el punto de impacto y hace tres cosas de golpe:
##    1. Dibuja un anillo de energía que se abre por el suelo (character_package/Fuerza/materials/shockwave.gdshader)
##    2. Levanta polvo, escombros y chispas
##    3. Hace daño EN ÁREA a todo lo que esté dentro del radio (grupo "damageable")
##
##  El daño NO depende del daño de los puñetazos: es su propia variable.
##  Se autodestruye al terminar; no hay que limpiarla a mano.
## =============================================================================

@export_group("Onda")
## Radio de la onda (unidades). Todo lo que esté dentro recibe daño.
@export var radius: float = 4.5
## Daño en el centro de la onda (independiente de los puñetazos).
@export var damage: float = 60.0
## Empuje que se lleva a los enemigos alcanzados.
@export var knockback: float = 12.0
## Duración de la animación del anillo (segundos).
@export var duration: float = 0.55
## Fracción del daño que queda en el borde del radio (0.45 = 45 %).
@export_range(0.0, 1.0, 0.05) var dano_en_el_borde: float = 0.45
## Color del anillo y de las chispas.
@export var color: Color = Color(1.0, 0.72, 0.35)

@export_group("Efectos")
@export var lanzar_polvo: bool = true
@export var lanzar_escombros: bool = true
@export var lanzar_chispas: bool = true

## Quien provocó la onda: nunca se daña a sí misma.
var autor: Node = null

var _anillo: MeshInstance3D
var _mat: ShaderMaterial
var _t: float = 0.0
var _acabado: bool = false


func _ready() -> void:
	_construir_anillo()
	_lanzar_efectos()
	_danar()
	# Red de seguridad: nunca se queda colgada en la escena.
	FuerzaVfx.liberar_mas_tarde(self, duration + 3.0)


func _process(delta: float) -> void:
	if _acabado:
		return
	_t += delta
	var u: float = clampf(_t / maxf(duration, 0.05), 0.0, 1.0)
	# El aro sale disparado al principio y frena: golpe seco, no niebla.
	var abre: float = 1.0 - pow(1.0 - u, 3.0)
	if _mat != null:
		_mat.set_shader_parameter("progreso", u)
	if _anillo != null:
		_anillo.scale = Vector3.ONE * lerpf(0.15, radius, abre)
	if u >= 1.0:
		_acabado = true
		queue_free()


func _construir_anillo() -> void:
	_anillo = MeshInstance3D.new()
	_anillo.name = "Anillo"
	var cuadro: QuadMesh = QuadMesh.new()
	cuadro.size = Vector2(2.0, 2.0)   # escala 1 = radio 1
	_anillo.mesh = cuadro

	_mat = ShaderMaterial.new()
	_mat.shader = load("res://personaje/transformaciones/fuerza/materials (1)/shockwave (1).gdshader")
	_mat.set_shader_parameter("color", Vector3(color.r, color.g, color.b))
	_mat.set_shader_parameter("progreso", 0.0)
	_mat.set_shader_parameter("grosor", 0.13)
	_mat.set_shader_parameter("intensidad", 4.0)
	_anillo.material_override = _mat

	# Tumbado en el suelo, un pelín por encima para no pelearse con él.
	_anillo.rotation.x = -PI * 0.5
	_anillo.position.y = 0.07
	_anillo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_anillo)


func _lanzar_efectos() -> void:
	# Las partículas se cuelgan del PADRE (el mundo), no de la onda: así siguen
	# vivas cuando la onda se autodestruye y no se cortan a media animación.
	var mundo: Node = get_parent()
	if not (mundo is Node3D):
		mundo = self
	var p: Node3D = mundo
	var punto: Vector3 = global_position

	if lanzar_polvo:
		FuerzaVfx.polvo(p, punto, radius * 0.55, 34, Color(0.60, 0.53, 0.44), 1.4, 3.6)
	if lanzar_escombros:
		FuerzaVfx.escombros(p, punto, radius * 0.5, 26, Color(0.33, 0.29, 0.25), 1.9, 8.0)
	if lanzar_chispas:
		FuerzaVfx.chispas(p, punto + Vector3.UP * 0.12, radius * 0.45, 34, color, 0.65, 10.0)


func _danar() -> void:
	var mundo: World3D = get_world_3d()
	if mundo == null:
		return
	var excluir: Array = []
	if autor is CollisionObject3D:
		excluir.append((autor as CollisionObject3D).get_rid())
	FuerzaCombat.golpear_esfera(mundo.direct_space_state, global_position, radius,
		damage, knockback, excluir, dano_en_el_borde, 0.35)
