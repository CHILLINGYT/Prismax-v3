class_name NPCEstabilizaCabeza
extends SkeletonModifier3D

## Estabilizador de CABEZA: mantiene la cara mirando al frente mientras el ciudadano anda.
##
## Los clips se hornean con la cabeza rígida respecto al pecho, y al andar el pecho gira con los
## hombros: medido en juego, la cara llega a ir 21° girada respecto a la cadera dentro de un mismo
## paso. Eso se lee como "cuello torcido" en un peatón que sólo camina. Aquí se gira la cabeza lo
## justo para devolverla hacia el frente del cuerpo (caderas), con fuerza parcial y tope de grados:
## la animación sigue mandando y el cuello no queda rígido, sólo se le quita el vaivén.
##
## Es un SkeletonModifier3D hijo del Skeleton3D, se aplica después de la animación de cada
## fotograma (igual que NPCLookAt, cuyo cálculo de aplicación reutiliza). Se apaga solo:
##   - cuando el ciudadano está sentado o tumbado (ahí la orientación de la cabeza es del clip),
##   - cuando está mirando al jugador (ahí manda NPCLookAt).

## Cuánto se corrige del vaivén (0 = nada, 1 = todo).
@export_range(0.0, 1.0) var fuerza := 0.75
## Tope de corrección en grados: nunca se gira la cabeza más que esto.
@export_range(0.0, 45.0) var tope := 18.0
## El ciudadano lo pone en false cuando la cabeza debe hacer otra cosa.
var activo := true

## Última corrección aplicada, en grados (para las pruebas).
var ultimo := 0.0
var aplicado := false

var _sk: Skeleton3D = null
var _cab := -1
var _cad := -1
var _arriba := Vector3.UP          # "arriba" del esqueleto, en su propio espacio
var _fwd_local := Vector3.ZERO     # "hacia delante" del cuerpo, en el marco local de la cadera
var _cara_local := Vector3.FORWARD # eje local de la cabeza que apunta a la cara


func _ready() -> void:
	_sk = get_parent() as Skeleton3D
	if _sk == null:
		return
	_cab = _hueso(["mixamorig_Head", "head.x", "B_Head"])
	_cad = _hueso(["mixamorig_Hips", "root.x", "B_Pelvis"])
	if _cab < 0 or _cad < 0:
		return
	_arriba = (_sk.global_transform.basis.inverse() * Vector3.UP).normalized()
	# "Hacia delante" del cuerpo: del tobillo al dedo del pie, aplanado, medido en REPOSO y
	# guardado en el marco local de la cadera (la cadera apenas gira al andar).
	var tobillo := _hueso(["mixamorig_LeftFoot", "foot.l", "B_L_Foot"])
	var dedo := _hueso(["mixamorig_LeftToeBase", "toes_01.l", "B_L_Toe0"])
	if tobillo < 0 or dedo < 0:
		return
	var pies := _sk.get_bone_global_rest(dedo).origin - _sk.get_bone_global_rest(tobillo).origin
	pies -= _arriba * pies.dot(_arriba)
	if pies.length_squared() < 0.000001:
		return
	pies = pies.normalized()
	_fwd_local = _sk.get_bone_global_rest(_cad).basis.inverse() * pies
	# Eje de la cara: el eje local de la cabeza que en reposo más apunta "hacia delante".
	var cab_rest := _sk.get_bone_global_rest(_cab).basis
	var mejor := -2.0
	for eje: Vector3 in [Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.FORWARD]:
		var d := (cab_rest * eje).normalized()
		var plano := d - _arriba * d.dot(_arriba)
		if plano.length_squared() < 0.000001:
			continue
		var val := plano.normalized().dot(pies)
		if val > mejor:
			mejor = val
			_cara_local = eje


func _process_modification() -> void:
	_apply()


func _process_modification_with_delta(_delta: float) -> void:
	_apply()


func _apply() -> void:
	if not activo or _sk == null or _cab < 0 or _cad < 0 or _fwd_local == Vector3.ZERO:
		return
	var cuerpo := _sk.get_bone_global_pose(_cad).basis * _fwd_local
	cuerpo -= _arriba * cuerpo.dot(_arriba)
	if cuerpo.length_squared() < 0.000001:
		return
	cuerpo = cuerpo.normalized()
	var cara := _sk.get_bone_global_pose(_cab).basis * _cara_local
	cara -= _arriba * cara.dot(_arriba)
	if cara.length_squared() < 0.000001:
		return
	cara = cara.normalized()
	var yaw := cuerpo.signed_angle_to(cara, _arriba)
	var tope_rad := deg_to_rad(tope)
	var corr := clampf(-yaw * fuerza, -tope_rad, tope_rad)
	ultimo = rad_to_deg(corr)
	if absf(corr) < 0.0005:
		# Ya mira al frente: se deja la pose tal cual (ni se toca el hueso).
		aplicado = false
		return
	var base := Basis.IDENTITY
	var padre := _sk.get_bone_parent(_cab)
	if padre >= 0:
		base = _sk.get_bone_global_pose(padre).basis
	base = base * _sk.get_bone_rest(_cab).basis
	var pose := (base.inverse() * Basis(Quaternion(_arriba, corr)) * base) \
			* Basis(_sk.get_bone_pose_rotation(_cab))
	_sk.set_bone_pose_rotation(_cab, Quaternion(pose.orthonormalized()))
	aplicado = true


## Giro de la cara respecto al frente del cuerpo, en grados (para las pruebas).
func giro_actual() -> float:
	if _sk == null or _cab < 0 or _cad < 0 or _fwd_local == Vector3.ZERO:
		return 0.0
	var cuerpo := _sk.get_bone_global_pose(_cad).basis * _fwd_local
	cuerpo -= _arriba * cuerpo.dot(_arriba)
	var cara := _sk.get_bone_global_pose(_cab).basis * _cara_local
	cara -= _arriba * cara.dot(_arriba)
	if cuerpo.length_squared() < 0.000001 or cara.length_squared() < 0.000001:
		return 0.0
	return rad_to_deg(cuerpo.normalized().signed_angle_to(cara.normalized(), _arriba))


func _hueso(candidatos: Array) -> int:
	for c: String in candidatos:
		var i := _sk.find_bone(c)
		if i >= 0:
			return i
	return -1