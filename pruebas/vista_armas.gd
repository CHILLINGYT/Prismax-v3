extends Node3D
## ESCENA DE VISTA (no es suite): foto de producto de las armas integradas.
##   · el AK real (arma_ak_tirador.tscn) tal cual cuelga de la mano;
##   · el cartucho 6.5x55 al tamaño EXACTO al que lo dibuja el proyectil
##     (radio 0.14 * 2 * escala 1.0 = 0.28 m de largo);
##   · una instancia del proyectil real, orientada como vuela (mira hacia su -Z).
## Deja en consola las medidas de las cajas para contrastarlas con la foto.

const ARMA := "res://enemigos/Scenes/arma_ak_tirador.tscn"
const MUNICION := "res://enemigos/armas/bullet_6.5x55mm_swedish.glb"
const PROYECTIL := "res://enemigos/Scenes/proyectil_enemigo.tscn"
const LARGO_MODELO := 0.4482

func _ready() -> void:
	_piso()
	var arma := (load(ARMA) as PackedScene).instantiate() as Node3D
	arma.position = Vector3(-0.75, 1.15, 0.0)
	# De perfil: se ve el largo real del arma (0.889 m) y su boca hacia -Z.
	arma.rotation = Vector3(0.0, -PI * 0.5, 0.0)
	add_child(arma)

	var cartucho := (load(MUNICION) as PackedScene).instantiate() as Node3D
	cartucho.position = Vector3(0.35, 1.15, 0.0)
	cartucho.rotation = Vector3(0.0, -PI * 0.5, 0.0)
	cartucho.scale = Vector3.ONE * (0.14 * 2.0 * 1.0 / LARGO_MODELO)
	add_child(cartucho)

	var proy := (load(PROYECTIL) as PackedScene).instantiate() as Node3D
	proy.position = Vector3(1.15, 1.15, 0.0)
	proy.rotation = Vector3(0.0, -PI * 0.5, 0.0)
	add_child(proy)

	print("[vista] AK en %s (largo medido 0.889 m) | cartucho escala %.3f (largo %.3f m) | proyectil radio %.2f" % [
			arma.position, cartucho.scale.x, cartucho.scale.x * LARGO_MODELO, 0.14])
	var boca := arma.get_node_or_null("BocaArma") as Node3D
	if boca != null:
		print("[vista] BocaArma del AK en local %s (boca real: z 0.320..0.351 del modelo)" % boca.position)

func _piso() -> void:
	var malla := MeshInstance3D.new()
	var caja := BoxMesh.new()
	caja.size = Vector3(40, 0.2, 40)
	malla.mesh = caja
	malla.position = Vector3(0, 0.0, 0)
	add_child(malla)
	var luz := DirectionalLight3D.new()
	luz.rotation = Vector3(-0.8, 0.5, 0.0)
	luz.light_energy = 1.4
	add_child(luz)
	var cam := Camera3D.new()
	cam.position = Vector3(0.1, 1.25, 2.1)
	cam.rotation = Vector3(-0.05, 0.0, 0.0)
	cam.fov = 55.0
	cam.current = true
	add_child(cam)