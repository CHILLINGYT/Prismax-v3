class_name FuerzaBrazosIK
extends SkeletonModifier3D

# =============================================================================
#  IK DE LOS BRAZOS PARA SOSTENER LA ROCA (Q)  —  LeftHandTarget / RightHandTarget
# =============================================================================
#  Los clips de la mole están construidos hueso a hueso y por eso la MUÑECA
#  sale doblada hacia atrás (≈55°): la mano aguanta la piedra, sí, pero la
#  articulación no está recta. Este modificador de esqueleto lo corrige EN
#  CALIENTE: SkeletonModifier3D siempre corre DESPUÉS del AnimationMixer, así
#  que la animación sigue poniendo el cuerpo (torso, piernas, la subida de la
#  roca...) y aquí sólo se recolocan los BRAZOS para que:
#
#    · la MANO llegue exactamente a su punto de agarre de la roca (los nodos
#      LeftHandTarget / RightHandTarget, hijos de este modificador);
#    · la MUÑECA quede RECTA: los dedos continúan la línea del antebrazo, sin
#      doblarse hacia atrás ni girarse de lado;
#    · la PALMA siga mirando a la roca igual que en la pose aprobada (la
#      referencia se mide de la propia pose la primera vez que el IK se
#      enciende: no hay números mágicos escritos a mano);
#    · el CODO se abra en un plano natural (polo hacia atrás/afuera) y los
#      antebrazos apunten a la roca.
#
#  Es un IK analítico de 2 huesos, el mismo truco que el de las piernas del
#  motor de poses (ver MartialKick.gd): con la posición del hombro y la del
#  agarre se calcula el codo por ley de cosenos y un "polo" decide hacia dónde
#  se abre. SÓLO se escriben ROTACIONES locales: la longitud del brazo no se
#  estira nunca y las posiciones de los huesos quedan como las dejó el clip.
#
#  La entrada/salida la mezcla el propio Skeleton3D con "influence": con peso 0
#  la animación manda otra vez (lanzar o cancelar devuelven los brazos al
#  sistema de animación normal, sin dejar nada a medias).
# =============================================================================

## Huesos del brazo izquierdo: brazo (hombro), antebrazo (codo), mano (muñeca)
## y el nudillo que marca hacia dónde apuntan los dedos (para medir la muñeca).
@export var huesos_izq: Array[StringName] = [
	&"mixamorig_LeftArm", &"mixamorig_LeftForeArm", &"mixamorig_LeftHand",
	&"mixamorig_LeftHandMiddle1",
]
## Lo mismo para el brazo derecho.
@export var huesos_der: Array[StringName] = [
	&"mixamorig_RightArm", &"mixamorig_RightForeArm", &"mixamorig_RightHand",
	&"mixamorig_RightHandMiddle1",
]

## Polo del codo en espacio del esqueleto: cuánto se abre hacia AFUERA del
## cuerpo, hacia ATRÁS y hacia ABAJO. Con los brazos casi rectos apenas cambia
## la pose; sirve para que el codo no se cruce ni cambie de lado nunca.
@export var polo_salida: float = 0.35
@export var polo_atras: float = 1.0
@export var polo_abajo: float = 0.0

## Velocidad con la que el IK entra y sale (peso por segundo). Con 5 tarda
## ~0,2 s de 0 a 1: tiempo de sobra para que no se vea ningún salto.
@export var peso_velocidad: float = 5.0

## Peso pedido por el jugador (0 = animación normal, 1 = IK completo).
var peso_objetivo: float = 0.0
## Peso real: sigue a peso_objetivo con una rampa corta (lo aplica Skeleton3D).
var peso_actual: float = 0.0
## Centro de la roca en espacio del esqueleto (lo fija Player.gd cada frame).
var centro: Vector3 = Vector3.ZERO

var _objetivo_izq: Node3D = null
var _objetivo_der: Node3D = null
var _sk: Skeleton3D = null
var _idx_izq: Array[int] = []
var _idx_der: Array[int] = []
# Referencia local de cada mano: [y_local (dedos), z_local (palma), Basis()].
# Son constantes del rig (no dependen de la pose); se miden una vez, la primera
# vez que el IK se enciende, de la propia pose que está sonando.
var _ref_izq: Array = []
var _ref_der: Array = []


func _ready() -> void:
	active = true
	influence = 0.0
	_objetivo_izq = get_node_or_null("LeftHandTarget") as Node3D
	_objetivo_der = get_node_or_null("RightHandTarget") as Node3D


## Entra el IK: se llama cuando Player.gd ya ha movido los agarres.
## Sólo se implementa ESTE virtual (el que el motor llama una vez por
## actualización del esqueleto), así que la rampa de peso no se puede acelerar
## por dobles llamadas.
func _process_modification() -> void:
	var sk: Skeleton3D = get_skeleton()
	if sk == null:
		return
	# get_process_delta_time() puede valer 0 si el nodo no pasa por _process:
	# en ese caso se usa el paso nominal de 60 Hz. La rampa sólo pule la entrada
	# y la salida del IK (0.2 s), así que un paso fijo es perfectamente válido.
	var paso: float = get_process_delta_time()
	if paso <= 0.0:
		paso = 1.0 / 60.0
	peso_actual = move_toward(peso_actual, clampf(peso_objetivo, 0.0, 1.0),
		peso_velocidad * paso)
	influence = peso_actual
	if peso_actual <= 0.001:
		return
	# Los dos nodos de agarre son hijos de este modificador. Se buscan aquí (y no
	# sólo en _ready) para que el IK funcione aunque el nodo se cree en marcha.
	if _objetivo_izq == null or _objetivo_der == null:
		_objetivo_izq = get_node_or_null("LeftHandTarget") as Node3D
		_objetivo_der = get_node_or_null("RightHandTarget") as Node3D
	if _objetivo_izq == null or _objetivo_der == null:
		return
	resolver(sk, _objetivo_izq.position, _objetivo_der.position, centro)


## Fija los dos puntos de agarre (espacio del esqueleto). Es lo que llama
## Player.gd cuando la roca está en las manos.
func fijar_agarres(izq: Vector3, der: Vector3) -> void:
	if _objetivo_izq != null:
		_objetivo_izq.position = izq
	if _objetivo_der != null:
		_objetivo_der.position = der


## Resuelve los dos brazos hacia sus agarres. Devuelve medidas de control
## (extensiones y ángulos de muñeca) por si hay que verificarlo desde fuera.
## Todo en espacio del esqueleto.
func resolver(sk: Skeleton3D, agarre_izq: Vector3, agarre_der: Vector3,
		cent: Vector3) -> Dictionary:
	if sk == null:
		return {}
	if sk != _sk:
		_sk = sk
		_idx_izq = _buscar(sk, huesos_izq)
		_idx_der = _buscar(sk, huesos_der)
		_ref_izq.clear()
		_ref_der.clear()
	if _idx_izq.size() < 4 or _idx_der.size() < 4:
		return {}

	var res: Dictionary = {}
	res["izq"] = _brazo(sk, _idx_izq, agarre_izq, cent, true)
	res["der"] = _brazo(sk, _idx_der, agarre_der, cent, false)
	if sk.has_method("force_update_all_bone_transforms"):
		sk.force_update_all_bone_transforms()

	# Medidas de control tras aplicar: muñeca recta y mano en su agarre.
	res["muneca_izq_grados"] = _angulo_muneca(sk, _idx_izq)
	res["muneca_der_grados"] = _angulo_muneca(sk, _idx_der)
	res["error_izq"] = (sk.get_bone_global_pose(_idx_izq[2]).origin - agarre_izq).length()
	res["error_der"] = (sk.get_bone_global_pose(_idx_der[2]).origin - agarre_der).length()
	return res


## Resuelve UN brazo (hombro -> codo -> muñeca) y deja escritas las tres
## rotaciones locales. Devuelve la extensión alcanzada (1 = brazo del todo).
func _brazo(sk: Skeleton3D, idx: Array[int], objetivo: Vector3, cent: Vector3,
		es_izq: bool) -> float:
	var i_arm: int = idx[0]
	var i_fore: int = idx[1]
	var i_hand: int = idx[2]
	var g_arm: Transform3D = sk.get_bone_global_pose(i_arm)
	var g_fore: Transform3D = sk.get_bone_global_pose(i_fore)
	var g_hand: Transform3D = sk.get_bone_global_pose(i_hand)

	var s: Vector3 = g_arm.origin
	var l1: float = (g_fore.origin - s).length()
	var l2: float = (g_hand.origin - g_fore.origin).length()
	if l1 < 0.0001 or l2 < 0.0001:
		return 0.0

	# Referencia local de la mano (una sola vez por sesión de IK).
	var ref: Array = _ref_izq if es_izq else _ref_der
	if ref.is_empty() and not _medir_referencia(sk, idx, cent, ref):
		return 0.0

	# --- IK de 2 huesos: codo por ley de cosenos, plano fijado por el polo ---
	var v: Vector3 = objetivo - s
	var alcance: float = (l1 + l2) * 0.995
	var d: float = clampf(v.length(), absf(l1 - l2) * 1.001 + 0.0005, alcance)
	var n: Vector3 = v.normalized()
	var polo: Vector3 = Vector3(
		polo_salida if es_izq else -polo_salida, -polo_abajo, -polo_atras)
	var pp: Vector3 = polo - n * n.dot(polo)
	if pp.length() < 0.05:
		pp = (Vector3.RIGHT if es_izq else Vector3.LEFT) - n * n.dot(
			Vector3.RIGHT if es_izq else Vector3.LEFT)
	if pp.length() < 0.05:
		pp = Vector3.UP - n * n.y
	pp = pp.normalized()
	var a: float = (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
	var h: float = sqrt(maxf(l1 * l1 - a * a, 0.0))
	var codo: Vector3 = s + n * a + pp * h
	var muneca: Vector3 = s + n * d

	# --- Orientaciones --------------------------------------------------------
	# Brazo y antebrazo: se gira lo MÍNIMO desde la pose actual (conserva el
	# roll del clip, que es el que ya se veía bien); la MANO se construye desde
	# cero para dejar la muñeca recta y la palma mirando a la roca.
	var dir_arm_act: Vector3 = (g_fore.origin - s).normalized()
	var b_arm: Basis = Basis(Quaternion(dir_arm_act, (codo - s).normalized())) * g_arm.basis
	var dir_fore_act: Vector3 = (g_hand.origin - g_fore.origin).normalized()
	var dir_fore: Vector3 = (muneca - codo).normalized()
	var b_fore: Basis = Basis(Quaternion(dir_fore_act, dir_fore)) * g_fore.basis

	var b_hand: Basis = _basis_mano(g_hand.basis, ref, dir_fore, cent - muneca)

	# --- Aplicar (sólo rotaciones locales; Skeleton3D mezcla con influence) ---
	var p_arm: Basis = Basis.IDENTITY
	var p_padre: int = sk.get_bone_parent(i_arm)
	if p_padre >= 0:
		p_arm = sk.get_bone_global_pose(p_padre).basis
	sk.set_bone_pose_rotation(i_arm, (p_arm.inverse() * b_arm).get_rotation_quaternion())
	sk.set_bone_pose_rotation(i_fore, (b_arm.inverse() * b_fore).get_rotation_quaternion())
	sk.set_bone_pose_rotation(i_hand, (b_fore.inverse() * b_hand).get_rotation_quaternion())
	return d / maxf(l1 + l2, 0.0001)


## Marco de la mano: dedos (y) siguiendo al antebrazo y dirección de la roca
## (z) como en la pose de referencia. Así la muñeca queda recta y la palma
## mantiene la orientación aprobada.
func _basis_mano(b_actual: Basis, ref: Array, dir_dedos: Vector3,
		hacia_roca: Vector3) -> Basis:
	var b_l: Basis = ref[2]
	var y_d: Vector3 = dir_dedos.normalized()
	var z_d: Vector3 = hacia_roca - y_d * y_d.dot(hacia_roca)
	if z_d.length() < 0.0001:
		z_d = b_actual.z - y_d * y_d.dot(b_actual.z)
	if z_d.length() < 0.0001:
		z_d = y_d.cross(Vector3.UP)
		if z_d.length() < 0.0001:
			z_d = y_d.cross(Vector3.RIGHT)
	z_d = z_d.normalized()
	var x_d: Vector3 = y_d.cross(z_d)
	var b_d: Basis = Basis(x_d, y_d, z_d)
	return b_d * b_l.inverse()


## Mide la referencia local de la mano (dedos + palma) de la pose que está
## sonando. La relación local es constante del rig, así que vale para siempre;
## se mide en la primera pose en la que el IK se enciende (las manos ya están
## palmeando la roca en todos los clips de la mole).
func _medir_referencia(sk: Skeleton3D, idx: Array[int], cent: Vector3,
		ref: Array) -> bool:
	var g_hand: Transform3D = sk.get_bone_global_pose(idx[2])
	var dedos: Vector3 = sk.get_bone_global_pose(idx[3]).origin - g_hand.origin
	if dedos.length() < 0.000001:
		return false
	var y_g: Vector3 = dedos.normalized()
	var hacia: Vector3 = cent - g_hand.origin
	var palma_g: Vector3 = hacia - y_g * y_g.dot(hacia)
	if palma_g.length() < 0.0001:
		return false
	palma_g = palma_g.normalized()
	var inv: Basis = g_hand.basis.inverse()
	var y_l: Vector3 = (inv * y_g).normalized()
	var z_l: Vector3 = inv * palma_g
	z_l = z_l - y_l * y_l.dot(z_l)
	if z_l.length() < 0.0001:
		return false
	z_l = z_l.normalized()
	ref.append(y_l)
	ref.append(z_l)
	ref.append(Basis(y_l.cross(z_l), y_l, z_l))
	return true


func _angulo_muneca(sk: Skeleton3D, idx: Array[int]) -> float:
	var g_hand: Transform3D = sk.get_bone_global_pose(idx[2])
	var g_fore: Transform3D = sk.get_bone_global_pose(idx[1])
	var dedos: Vector3 = sk.get_bone_global_pose(idx[3]).origin - g_hand.origin
	var antebrazo: Vector3 = g_hand.origin - g_fore.origin
	if dedos.length() < 0.000001 or antebrazo.length() < 0.000001:
		return 0.0
	return rad_to_deg(dedos.normalized().angle_to(antebrazo.normalized()))


func _buscar(sk: Skeleton3D, nombres: Array[StringName]) -> Array[int]:
	var salida: Array[int] = []
	for nb: StringName in nombres:
		salida.append(sk.find_bone(nb))
	return salida