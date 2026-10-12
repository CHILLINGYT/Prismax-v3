class_name FuerzaRock
extends RigidBody3D

## =============================================================================
##  Rock.gd — la mole que el personaje arranca del suelo y lanza
## =============================================================================
##  Piedra irregular generada POR CÓDIGO (una esfera abollada con senos y con
##  las normales recalculadas): no hace falta ningún modelo. La textura sí es
##  una imagen de roca real (character_package/Fuerza/textures/rock_stone.png).
##
##  Vuela con física de verdad (RigidBody3D): gravedad, rebotes y choques.
##  Al chocar con fuerza hace daño en área y levanta polvo y escombros.
##
##  Mientras está "sujeta" (freeze) sigue las manos del personaje; al lanzarla
##  se activa la física y se olvida de él.
## =============================================================================

@export_group("Roca")
## Radio de la roca en unidades (1.1 ≈ una mole de más de dos metros).
@export var radius: float = 1.1
## Daño al chocar de lleno.
@export var damage: float = 80.0
## Radio del daño en área del impacto.
@export var impact_radius: float = 3.0
## Empuje a lo que alcance.
@export var knockback: float = 16.0
## Masa (pesada para que empuje, ligera para que vuele bonito).
## Se copia a la propiedad "mass" real del RigidBody3D al nacer.
@export var peso: float = 90.0
## Velocidad mínima de choque para que cuente como impacto.
@export var min_impact_speed: float = 4.0
## Segundos antes de desaparecer sola (no dejar basura en la escena).
@export var vida: float = 14.0
## Escala de la gravedad: menos de 1 = vuela más lejos y más tiempo.
@export var escala_gravedad: float = 0.6
## Sacudida de cámara al impactar.
@export var camera_shake: float = 0.55
## Capa y máscara de colisión que tiene la roca CUANDO VUELA.
##   capa_fisica    = 4 (bit 3, "proyectiles"). NO es la 1 a propósito: el
##                    jugador está en la capa 2 y la roca no debe verlo, porque
##                    al nacer entre sus manos su esfera solapa su cápsula, la
##                    física la escupe y el primer "body_entered" (¡a 40 cm del
##                    pecho!) contaría como impacto y repartiría daño en área
##                    sin haber tocado a nadie.
##   mascara_fisica = 1 (el escenario y los enemigos, que sí están en la 1).
@export var capa_fisica: int = 4
@export var mascara_fisica: int = 1
## Segundos de gracia tras el lanzamiento en los que la roca no hace daño: aún
## está saliendo de las manos y cualquier roce no es un golpe de verdad. Corto a
## propósito: con un tiro de 17 m/s la roca recorre un metro entero en ese
## tiempo, así que una diana cercana ya no se libra del impacto por llegar
## demasiado pronto (que era justo lo que pasaba con 0.12).
@export var margen_salida: float = 0.06
## Textura de la roca (si la dejas vacía se usa un material gris liso).
@export var textura: Texture2D = load("res://personaje/transformaciones/fuerza/textures (1)/rock_stone (1).png")

## Quien la lanzó (no se daña a sí mismo con su propia roca).
var autor: Node = null
## ¿Está en el aire? (Sólo entonces hace daño al chocar.)
var volando: bool = false

var _semilla: float = 1.0
var _reventada: bool = false
var _sujeta: bool = false
var _gracia: float = 0.0
var _empuje_pendiente: Vector3 = Vector3.ZERO
var _giro_pendiente: Vector3 = Vector3.ZERO
## Velocidad de los dos últimos fotogramas. Hace falta porque el motor (Jolt)
## resuelve el choque ANTES de avisar por body_entered: cuando llega la señal,
## linear_velocity ya es la de DESPUÉS del golpe (de 17 m/s a 4, por ejemplo) y
## el impacto se quedaría por debajo de min_impact_speed sin hacer daño. Con
## este historial se mide la velocidad REAL de llegada.
var _vel_reciente: PackedFloat32Array = PackedFloat32Array([0.0, 0.0])


func _ready() -> void:
	_semilla = randf_range(0.0, 20.0)

	var malla: MeshInstance3D = MeshInstance3D.new()
	malla.name = "Malla"
	malla.mesh = malla_roca(radius, _semilla)
	malla.material_override = _material()
	add_child(malla)

	var forma: SphereShape3D = SphereShape3D.new()
	forma.radius = radius * 0.9
	var cs: CollisionShape3D = CollisionShape3D.new()
	cs.shape = forma
	add_child(cs)

	mass = maxf(peso, 1.0)
	gravity_scale = clampf(escala_gravedad, 0.0, 4.0)
	contact_monitor = true
	max_contacts_reported = 8
	body_entered.connect(_al_chocar)
	_aplicar_colision()
	set_physics_process(false)
	# OJO: la cuenta atrás para desaparecer NO se pone aquí. Mientras la roca
	# está sujeta (preparada en las manos, p. ej. apuntando con Q) puede pasar
	# el tiempo que haga falta sin que se desvanezca: se programa al lanzarla.


# -----------------------------------------------------------------------------
#  Sujeta / lanzada
# -----------------------------------------------------------------------------
## La roca pasa a estar sujeta por el personaje (deja de tener física).
## OJO: no se toca gravity_scale (un cuerpo congelado no tiene gravedad de
## todos modos), porque al lanzarla hay que recuperar su valor real.
func sujetar() -> void:
	volando = false
	_sujeta = true
	freeze = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_aplicar_colision()


## Sujeta: no colisiona con NADA. Si no, nace dentro del cuerpo del personaje y
## lo pone a volar por los aires (y desvía su propio lanzamiento al soltarse).
## Volando: colisiona normalmente con el escenario y con los enemigos.
func _aplicar_colision() -> void:
	if _sujeta:
		collision_layer = 0
		collision_mask = 0
	else:
		collision_layer = capa_fisica
		collision_mask = mascara_fisica


## La roca sale volando desde la mano. La velocidad de verdad se aplica en el
## siguiente fotograma físico: al descongelar un RigidBody3D, Godot puede
## llevarse por delante la velocidad que le pongas en el mismo fotograma.
func lanzar(direccion: Vector3, velocidad: float, giro: float = 6.0) -> void:
	volando = true
	_reventada = false
	_sujeta = false
	_gracia = maxf(margen_salida, 0.0)
	freeze = false
	gravity_scale = clampf(escala_gravedad, 0.0, 4.0)
	_aplicar_colision()
	var v: Vector3 = direccion.normalized() * maxf(velocidad, 0.0)
	linear_velocity = v
	angular_velocity = Vector3(
		randf_range(-giro, giro), randf_range(-giro, giro), randf_range(-giro, giro))
	# Repetido un fotograma después, ya descongelada del todo.
	_empuje_pendiente = v
	_giro_pendiente = angular_velocity
	set_physics_process(true)
	# Ahora sí: lanzada, la roca se limpia sola si nadie la revienta antes.
	FuerzaVfx.liberar_mas_tarde(self, vida)


func _physics_process(delta: float) -> void:
	_gracia = maxf(_gracia - delta, 0.0)
	_vel_reciente[1] = _vel_reciente[0]
	_vel_reciente[0] = linear_velocity.length()

	if _empuje_pendiente != Vector3.ZERO:
		linear_velocity = _empuje_pendiente
		angular_velocity = _giro_pendiente
		_empuje_pendiente = Vector3.ZERO

	# Sólo se apaga cuando ya no queda nada que hacer.
	if _gracia <= 0.0 and _empuje_pendiente == Vector3.ZERO:
		set_physics_process(false)


func _al_chocar(_cuerpo: Node) -> void:
	# Velocidad REAL de llegada: la del fotograma del choque, no la que queda
	# después de que el motor lo resuelva.
	var velocidad: float = maxf(maxf(_vel_reciente[0], _vel_reciente[1]),
		linear_velocity.length())
	if not volando or _reventada or _gracia > 0.0:
		return
	if velocidad < min_impact_speed:
		return
	_reventada = true
	_impactar(velocidad)


func _impactar(velocidad: float) -> void:
	var punto: Vector3 = global_position
	# El daño escala con la velocidad del golpe (y tiene un mínimo decente).
	var factor: float = clampf(velocidad / 18.0, 0.4, 1.7)
	var dano: float = damage * factor

	var mundo: World3D = get_world_3d()
	if mundo != null:
		var excluir: Array = [get_rid()]
		if autor is CollisionObject3D:
			excluir.append((autor as CollisionObject3D).get_rid())
		FuerzaCombat.golpear_esfera(mundo.direct_space_state, punto, impact_radius,
			dano, knockback, excluir, 0.4, 0.25)

	# Polvo, escombros y chispas del hostiazo.
	var padre: Node = get_parent()
	if padre is Node3D:
		FuerzaVfx.polvo(padre, punto, radius * 1.7, 30, Color(0.62, 0.55, 0.46), 1.5, 5.0)
		FuerzaVfx.escombros(padre, punto, radius * 1.3, 28, Color(0.32, 0.28, 0.24), 2.0, 9.0)
		FuerzaVfx.chispas(padre, punto, radius * 0.8, 18, Color(1.0, 0.85, 0.5), 0.5, 7.0)

	FuerzaCombat.sacudir_camara(get_tree(), camera_shake * clampf(factor, 0.5, 1.5))
	# Se queda en el suelo un rato y luego desaparece.
	FuerzaVfx.liberar_mas_tarde(self, 5.0)


func _material() -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	if textura != null:
		m.albedo_texture = textura
		m.uv1_scale = Vector3(2.2, 2.2, 2.2)
		m.albedo_color = Color(0.86, 0.84, 0.80)
	else:
		m.albedo_color = Color(0.42, 0.40, 0.37)
	m.roughness = 1.0
	m.metallic = 0.0
	return m


# -----------------------------------------------------------------------------
#  Piedra irregular por código
# -----------------------------------------------------------------------------
## Esfera abollada de forma determinista + normales recalculadas (si no, la luz
## sale mal y parece un globo en vez de una piedra).
static func malla_roca(radio: float, semilla: float = 1.0, detalle: int = 16) -> Mesh:
	var base: SphereMesh = SphereMesh.new()
	base.radius = radio
	base.height = radio * 2.0
	base.radial_segments = maxi(detalle, 6)
	@warning_ignore("integer_division")
	base.rings = maxi(detalle / 2, 4)

	# sphere_get_arrays() no existe: la malla se saca del propio recurso. Si por
	# lo que sea no hay superficie, se devuelve la esfera tal cual (antes una
	# bola lisa que nada).
	var arr: Array = base.surface_get_arrays(0)
	if arr.is_empty() or arr[Mesh.ARRAY_VERTEX] == null:
		return base
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]

	var deformado: PackedVector3Array = PackedVector3Array()
	deformado.resize(verts.size())
	for i: int in verts.size():
		var v: Vector3 = verts[i]
		var n: Vector3 = v.normalized() if v.length_squared() > 0.0 else Vector3.UP
		var grueso: float = (sin(n.x * 5.13 + semilla) + sin(n.y * 4.31 - semilla * 1.7)
			+ sin(n.z * 6.71 + semilla * 2.3)) / 3.0
		var fino: float = sin(n.x * 11.0 + n.y * 9.0 + n.z * 13.0 + semilla) * 0.5
		deformado[i] = v * (1.0 + (grueso + fino) * 0.16)
	arr[Mesh.ARRAY_VERTEX] = deformado

	var indices: PackedInt32Array = PackedInt32Array()
	if arr[Mesh.ARRAY_INDEX] != null:
		indices = arr[Mesh.ARRAY_INDEX]

	var normales: PackedVector3Array = PackedVector3Array()
	normales.resize(deformado.size())
	if indices.size() >= 3:
		# Caras suavizadas: se acumula la normal de cada triángulo en sus vértices.
		var t: int = 0
		while t + 2 < indices.size():
			var a: int = indices[t]
			var b: int = indices[t + 1]
			var c: int = indices[t + 2]
			var n: Vector3 = (deformado[b] - deformado[a]).cross(deformado[c] - deformado[a])
			normales[a] += n
			normales[b] += n
			normales[c] += n
			t += 3
	else:
		# Sin índices: normales planas, una por triángulo.
		var t2: int = 0
		while t2 + 2 < deformado.size():
			var n2: Vector3 = (deformado[t2 + 1] - deformado[t2]).cross(
				deformado[t2 + 2] - deformado[t2])
			normales[t2] = n2
			normales[t2 + 1] = n2
			normales[t2 + 2] = n2
			t2 += 3
	for i: int in normales.size():
		var n: Vector3 = normales[i]
		normales[i] = Vector3.UP if n.length_squared() < 0.000001 else n.normalized()
	arr[Mesh.ARRAY_NORMAL] = normales

	var salida: ArrayMesh = ArrayMesh.new()
	salida.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return salida
