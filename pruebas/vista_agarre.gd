extends Node3D
## ESCENA DE VISTA (no es suite): el tirador CON el AK real, visto desde 4 ángulos a
## la vez (0°, 90°, 180° y 270°), para comprobar a ojo el AGARRE sin tocar ninguna
## animación. Además MIDE, con el esqueleto real:
##   · distancia de la mano derecha (`mixamorig_RightHand`) al punto de agarre del
##     arma (el origen del nodo, que por convención es la empuñadura);
##   · hacia dónde apunta la boca del cañón (debe ir hacia el frente del enemigo).
## Las medidas quedan en consola para contrastarlas con la foto.

const TIRADOR := "res://Enemigos Prueba/Scenes/enemigo_tirador.tscn"
const ANGULOS := [0.0, PI * 0.5, PI, PI * 1.5]
const SEPARACION := 1.7

func _ready() -> void:
	_piso()
	var i := 0
	for ang in ANGULOS:
		var e := (load(TIRADOR) as PackedScene).instantiate() as Node3D
		e.position = Vector3(-1.5 * SEPARACION + float(i) * SEPARACION, 0.0, 0.0)
		e.rotation = Vector3(0.0, ang, 0.0)
		add_child(e)
		i += 1
	await get_tree().process_frame
	await get_tree().process_frame
	i = 0
	for e in get_children():
		if not (e is CharacterBody3D):
			continue
		_medir(e as CharacterBody3D, i)
		i += 1

func _medir(e: CharacterBody3D, indice: int) -> void:
	var arma := e.find_child("ArmaTirador", true, false) as Node3D
	var sk := e.find_child("Skeleton3D", true, false) as Skeleton3D
	if arma == null or sk == null:
		print("[agarre %d] falta el arma o el esqueleto (arma=%s sk=%s)" % [indice, arma != null, sk != null])
		return
	var mano := -1
	for b in sk.get_bone_count():
		if String(sk.get_bone_name(b)) == "mixamorig_RightHand":
			mano = b
			break
	var p_mano := Vector3.ZERO
	if mano >= 0:
		p_mano = sk.global_transform * sk.get_bone_global_pose(mano).origin
	var p_agarre := arma.global_position
	var boca := arma.get_node_or_null("BocaArma") as Node3D
	var p_boca := boca.global_position if boca != null else Vector3.ZERO
	var frente := -e.global_transform.basis.z
	var dir_boca := (p_boca - p_agarre).normalized() if boca != null else Vector3.ZERO
	print("[agarre %d] giro %.0f° | mano<->agarre %.3f m | largo hasta la boca %.3f m | boca·frente %.2f | boca·arriba %.2f" % [
			indice, rad_to_deg(ANGULOS[indice]),
			p_mano.distance_to(p_agarre),
			p_agarre.distance_to(p_boca),
			dir_boca.dot(frente),
			dir_boca.dot(Vector3.UP)])
	var sk_txt := "huesos=%d" % sk.get_bone_count()
	print("            %s | mano global %s | agarre global %s" % [sk_txt, p_mano.snapped(Vector3(0.001, 0.001, 0.001)), p_agarre.snapped(Vector3(0.001, 0.001, 0.001))])

## Piso CON colisión: sin ella los enemigos (que aplican gravedad en su _fisica)
## caían fuera de la foto antes de capturarla.
func _piso() -> void:
	var cuerpo := StaticBody3D.new()
	var forma := CollisionShape3D.new()
	var caja_col := BoxShape3D.new()
	caja_col.size = Vector3(60, 0.5, 40)
	forma.shape = caja_col
	cuerpo.add_child(forma)
	cuerpo.position = Vector3(0, -0.25, 0)
	add_child(cuerpo)
	var malla := MeshInstance3D.new()
	var caja := BoxMesh.new()
	caja.size = Vector3(60, 0.5, 40)
	malla.mesh = caja
	malla.position = Vector3(0, -0.25, 0)
	add_child(malla)
	var luz := DirectionalLight3D.new()
	luz.rotation = Vector3(-0.7, 0.4, 0.0)
	luz.light_energy = 1.5
	add_child(luz)
	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 1.35, 5.2)
	cam.rotation = Vector3(-0.06, 0.0, 0.0)
	cam.fov = 60.0
	cam.current = true
	add_child(cam)