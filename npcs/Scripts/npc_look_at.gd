class_name NPCLookAt
extends SkeletonModifier3D

## Mirada procedimental de la cabeza (Etapa 3).
##
## Gira SÓLO el hueso de la cabeza hacia un objetivo (el jugador), con límites de ángulo y con
## fundido de entrada/salida. Al ser un SkeletonModifier3D hijo del Skeleton3D, se aplica
## DESPUÉS de la animación de cada fotograma: la cabeza mira al jugador sin pelearse con el
## AnimationTree y sin quedarse clavada.
##
## Se implementa a mano (en vez de usar LookAtModifier3D) porque el enumerado de ejes de esa
## clase en esta versión de Godot no permite fijar el eje de giro correcto para estos rigs:
## se midió que en los huesos Mixamo la cara apunta al +X local y el "arriba" es el +Y local.
##
## Cómo funciona: en cada fotograma se mide qué le falta girar a la cara de la cabeza para
## apuntar al objetivo (un viraje respecto al "arriba" del personaje y una inclinación), se
## recorta a los límites y se aplica sobre la pose animada. Como el cálculo parte de la pose
## del fotograma, aplicarlo dos veces no acumula: converge y se queda ahí.

## Ejes locales del hueso de la cabeza (se detectan solos en cada esqueleto):
## _forward apunta hacia la cara y _up_axis hacia arriba. Medidos en los rigs Mixamo: +X y +Y;
## en los rigs Auto-Rig Pro (City Folks / Urban Man) los ejes no son los mismos, así que se
## deducen del propio reposo del esqueleto en vez de darlos por hechos.
var _forward := Vector3(1.0, 0.0, 0.0)
var _up_axis := Vector3(0.0, 1.0, 0.0)

## 0 = pose animada sin tocar; 1 = mira todo lo que permitan los límites.
var watch := 0.0
var yaw_limit := deg_to_rad(60.0)
var pitch_limit := deg_to_rad(25.0)

var _head_bone_name := ""
var _target: Node3D
var _skeleton: Skeleton3D
var _head := -1

## Contadores de diagnóstico (los leen las sondas de prueba).
var calls := 0
var last_yaw := 0.0
var last_pitch := 0.0
var last_applied := false
## Error real que queda DESPUÉS de aplicar el giro, medido dentro del propio modificador
## (0° = la cara apunta al objetivo). Sirve para distinguir "no gira" de "gira y no se ve".
var debug_error_deg := 999.0


## Se llama al crear el modificador, antes de meterlo en el árbol.
func setup(head_bone_name: String, target: Node3D, yaw_deg: float, pitch_deg: float) -> void:
	_head_bone_name = head_bone_name
	_target = target
	yaw_limit = deg_to_rad(yaw_deg)
	pitch_limit = deg_to_rad(pitch_deg)


func _ready() -> void:
	_skeleton = get_parent() as Skeleton3D
	if _skeleton != null and _head_bone_name != "":
		_head = _skeleton.find_bone(_head_bone_name)
		_detect_axes()


## Deduce qué eje local del hueso de la cabeza apunta a la cara y cuál hacia arriba, midiendo
## el reposo del propio esqueleto: cada rig (Mixamo, Auto-Rig Pro...) usa ejes distintos.
func _detect_axes() -> void:
	if _skeleton == null or _head < 0:
		return
	var forward := _skeleton_forward()
	var up := _skeleton_up()
	var bone_basis := _skeleton.get_bone_global_rest(_head).basis
	if forward != Vector3.ZERO:
		_forward = _best_axis(bone_basis, forward)
	if up != Vector3.ZERO:
		_up_axis = _best_axis(bone_basis, up)


## De los seis ejes locales posibles, el que más se acerca a una dirección del esqueleto.
func _best_axis(bone_basis: Basis, direction: Vector3) -> Vector3:
	var best := Vector3(1.0, 0.0, 0.0)
	var best_dot := -2.0
	var wanted := direction.normalized()
	for axis: Vector3 in [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD]:
		var d := (bone_basis * axis).normalized().dot(wanted)
		if d > best_dot:
			best_dot = d
			best = axis
	return best


## Hacia dónde mira el personaje, en espacio del esqueleto: la dirección del pie.
func _skeleton_forward() -> Vector3:
	var up := _skeleton_up()
	var ankle := _bone(["mixamorig_LeftFoot", "foot.l", "B_L_Foot"])
	var toe := _bone(["mixamorig_LeftToeBase", "toes_01.l", "B_L_Toe0"])
	if ankle < 0 or toe < 0:
		return Vector3.ZERO
	var flat := _skeleton.get_bone_global_rest(toe).origin - _skeleton.get_bone_global_rest(ankle).origin
	flat -= up * flat.dot(up)
	return flat.normalized() if flat.length_squared() > 0.000001 else Vector3.ZERO


## "Arriba" del personaje en espacio del esqueleto (de las caderas a la cabeza).
func _skeleton_up() -> Vector3:
	var hips := _bone(["mixamorig_Hips", "root.x", "B_Pelvis"])
	var head := _bone(["mixamorig_Head", "head.x", "B_Head"])
	if hips < 0 or head < 0:
		return Vector3.UP
	return (_skeleton.get_bone_global_rest(head).origin - _skeleton.get_bone_global_rest(hips).origin).normalized()


func _bone(candidates: Array) -> int:
	for c: String in candidates:
		var i := _skeleton.find_bone(c)
		if i >= 0:
			return i
	return -1


func _process_modification() -> void:
	_apply()


func _process_modification_with_delta(_delta: float) -> void:
	_apply()


func _apply() -> void:
	if _skeleton == null or _head < 0 or _target == null or watch <= 0.001:
		return
	var head_pose := _skeleton.get_bone_global_pose(_head)
	var skel_to_world := _skeleton.global_transform
	var target_local := skel_to_world.affine_inverse() * _target.global_position
	var to_target := target_local - head_pose.origin
	if to_target.length_squared() < 0.0001:
		return
	to_target = to_target.normalized()
	var face := (head_pose.basis * _forward).normalized()
	# "Arriba" del personaje, en el espacio del esqueleto (cada rig viene orientado a su manera).
	var up := (head_pose.basis * _up_axis).normalized()
	var face_flat := face - up * face.dot(up)
	var target_flat := to_target - up * to_target.dot(up)
	if face_flat.length_squared() < 0.0001 or target_flat.length_squared() < 0.0001:
		return
	face_flat = face_flat.normalized()
	target_flat = target_flat.normalized()
	# Viraje (izquierda/derecha) y inclinación (arriba/abajo) que le faltan a la cara.
	var yaw := clampf(face_flat.signed_angle_to(target_flat, up), -yaw_limit, yaw_limit)
	var pitch := clampf(
		asin(clampf(to_target.dot(up), -1.0, 1.0)) - asin(clampf(face.dot(up), -1.0, 1.0)),
		-pitch_limit,
		pitch_limit
	)
	var side := face_flat.cross(up).normalized()
	# El signo de la inclinación es negativo porque girar alrededor de `side` sube el "arriba"
	# hacia la cara, o sea que hace que el personaje baje la mirada.
	var look_rotation := Quaternion(up, yaw * watch) * Quaternion(side, -pitch * watch)
	calls += 1
	last_yaw = rad_to_deg(yaw * watch)
	last_pitch = rad_to_deg(-pitch * watch)
	var parent_global := Basis.IDENTITY
	var parent := _skeleton.get_bone_parent(_head)
	if parent >= 0:
		parent_global = _skeleton.get_bone_global_pose(parent).basis
	# La pose del hueso vive dentro de (pose del padre * reposo del hueso): se pasa el giro a
	# ese espacio para poder aplicarlo sobre la pose animada del fotograma.
	var base := parent_global * _skeleton.get_bone_rest(_head).basis
	var pose_new := (base.inverse() * Basis(look_rotation) * base) * Basis(_skeleton.get_bone_pose_rotation(_head))
	_skeleton.set_bone_pose_rotation(_head, Quaternion(pose_new.orthonormalized()))
	last_applied = true
	# Comprobación interna: ¿dónde apunta la cara con la pose que se acaba de escribir?
	var check_face := (base * Basis(_skeleton.get_bone_pose_rotation(_head)) * _forward).normalized()
	debug_error_deg = rad_to_deg(check_face.angle_to(to_target))