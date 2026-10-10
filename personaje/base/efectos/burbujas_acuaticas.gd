class_name BurbujasAcuaticas
extends Node3D
## =============================================================================
##  BURBUJAS DE LA CABEZA/ BOCA DEL PERSONAJE ACUÁTICO
## =============================================================================
##  Mientras el personaje es un PEZ y está NADANDO, suelta burbujitas por la cabeza
##  que suben y se van quedando atrás. Son discretas e intermitentes (el caudal
##  sube y baja solo) y sólo salen en el agua: al salir a tierra se deja de emitir y
##  las que ya había terminan su vida de forma natural (no se cortan a golpe).
##
##  DÓNDE NACE LA BURBUJA: en el hueso REAL de la cabeza del modelo acuático
##  (`mixamorig_Head`, verificado en el esqueleto importado). No hay hueso de boca,
##  así que la zona de la cabeza es el anclaje más cercano y no se inventa ningún
##  nombre: se prueban los que usan los modelos Mixamo ("Head", "mixamorig:Head",
##  "mixamorig_Head") y si ninguno existe, simplemente no hay burbujas.
##
##  El anclaje es un `BoneAttachment3D` (marcador auxiliar colgado del ESQUELETO,
##  sin tocar el modelo): sigue a la cabeza sola, así que las burbujas acompañan al
##  personaje al nadar, girar y cambiar de profundidad sin recalcular nada.
##
##  Reutiliza el shader de gota `acuatica/vfx/water_particle.gdshader` (la burbuja
##  no es una textura: es un degradado radial con borde claro).
## =============================================================================

const SHADER_GOTA := preload("res://personaje/transformaciones/acuatica/vfx/water_particle.gdshader")
## Nombre ESTÁNDAR de la cabeza. Se prueban las variantes de Mixamo al buscarlo.
const HUESO_CABEZA := &"Head"

@export_group("Burbujas del personaje")
## Cuántas burbujas caben a la vez (el caudal real lo modula `amount_ratio`).
@export var cantidad: int = 14
@export var tamano: float = 0.05
@export var vida: float = 2.4
## Radio (m) del área de emisión alrededor de la cabeza.
@export var radio_emision: float = 0.11

var _jugador: Node = null
var _burbujas: GPUParticles3D = null
var _anclaje: BoneAttachment3D = null
var _fase: float = 0.0


func _ready() -> void:
	# El dueño es el propio jugador (este nodo cuelga de él).
	_jugador = get_parent()
	_fase = randf() * TAU


func _process(delta: float) -> void:
	# Si el modelo visual se cambió, el anclaje se queda colgando de un esqueleto ya
	# liberado: se desmonta el emisor para volver a montarlo sobre el esqueleto nuevo
	# (nada de nodos acumulados ni de tocar objetos liberados).
	if _burbujas != null and (not is_instance_valid(_burbujas) or not is_instance_valid(_anclaje)):
		if is_instance_valid(_burbujas):
			_burbujas.queue_free()
		_burbujas = null
		_anclaje = null
	if not _asegurar_anclaje():
		return
	# La cabeza se mueve: el emisor la sigue. Va con `top_level`, así que su base es
	# del MUNDO y las burbujas suben rectas aunque el pez nade inclinado.
	_burbujas.global_position = _anclaje.global_position
	var nadando := false
	if _jugador != null and is_instance_valid(_jugador):
		var v: Variant = _jugador.get("a_nadando")
		nadando = bool(v) if v != null else false
	_burbujas.emitting = nadando
	if nadando:
		_fase += delta
		# Caudal variable: ráfagas suaves en vez de un chorro constante.
		_burbujas.amount_ratio = 0.3 + 0.7 * (0.5 + 0.5 * sin(_fase * 1.1))


# -----------------------------------------------------------------------------
#  Montaje (perezoso: hasta que no existe el modelo acuático no hay nada que hacer)
# -----------------------------------------------------------------------------
func _asegurar_anclaje() -> bool:
	if _burbujas != null and is_instance_valid(_burbujas):
		return true
	var esqueleto := _buscar_esqueleto()
	if esqueleto == null:
		return false
	var hueso := _buscar_hueso(esqueleto, HUESO_CABEZA)
	if hueso < 0:
		return false
	_anclaje = BoneAttachment3D.new()
	_anclaje.name = "AnclaBurbujas"
	esqueleto.add_child(_anclaje)
	# Se fija el índice Y el nombre REALES del hueso del modelo importado.
	_anclaje.bone_idx = hueso
	_anclaje.bone_name = esqueleto.get_bone_name(hueso)
	_montar_particulas()
	return true


func _montar_particulas() -> void:
	var proceso := ParticleProcessMaterial.new()
	proceso.direction = Vector3(0.0, 1.0, 0.0)
	proceso.spread = 18.0
	proceso.initial_velocity_min = 0.25
	proceso.initial_velocity_max = 0.7
	# "Gravedad" hacia arriba: en el agua las burbujas suben.
	proceso.gravity = Vector3(0.0, 0.45, 0.0)
	proceso.scale_min = 0.5
	proceso.scale_max = 1.8
	proceso.damping_min = 0.0
	proceso.damping_max = 0.3
	proceso.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	proceso.emission_sphere_radius = radio_emision

	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * tamano
	var mat := ShaderMaterial.new()
	mat.shader = SHADER_GOTA
	mat.set_shader_parameter("color", Color(0.82, 0.95, 1.0, 0.55))

	_burbujas = GPUParticles3D.new()
	_burbujas.name = "BurbujasCabeza"
	_burbujas.amount = maxi(cantidad, 4)
	_burbujas.lifetime = vida
	# Mundo (no locales): la burbuja nace en la cabeza y se queda atrás mientras el
	# pez avanza, que es justo el efecto de nadar.
	_burbujas.local_coords = false
	_burbujas.top_level = true
	_burbujas.draw_pass_1 = quad
	_burbujas.material_override = mat
	_burbujas.process_material = proceso
	_burbujas.visibility_aabb = AABB(Vector3.ONE * -6.0, Vector3.ONE * 12.0)
	_burbujas.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_burbujas.emitting = false
	add_child(_burbujas)


## Esqueleto del modelo acuático: se busca dentro del nodo "Acuatico" del jugador
## (el mismo "slot" que usa el controlador), sin depender de una ruta fija.
func _buscar_esqueleto() -> Skeleton3D:
	if _jugador == null or not is_instance_valid(_jugador):
		return null
	var acuatico := _jugador.get_node_or_null("Acuatico")
	if acuatico == null:
		return null
	return _buscar_en(acuatico)


func _buscar_en(nodo: Node) -> Skeleton3D:
	for hijo in nodo.get_children():
		if hijo is Skeleton3D:
			return hijo
		var hondo := _buscar_en(hijo)
		if hondo != null:
			return hondo
	return null


## Índice del hueso probando los nombres que usan los modelos importados
## (Mixamo con "_" o ":"). -1 si no existe.
func _buscar_hueso(esqueleto: Skeleton3D, hueso: StringName) -> int:
	var i := esqueleto.find_bone(hueso)
	if i < 0:
		i = esqueleto.find_bone(StringName("mixamorig:" + String(hueso)))
	if i < 0:
		i = esqueleto.find_bone(StringName("mixamorig_" + String(hueso)))
	return i