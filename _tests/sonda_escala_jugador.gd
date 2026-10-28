extends Node3D
## SONDA (sólo mide): altura REAL del jugador (malla visible de cada forma, en
## pose de reposo ya animada) frente a los vehículos aparcados.

const JUG := "res://personaje/base/escenas/leo_jugador.tscn"
const VEH := {
	"moto": "res://world/vehiculos/moto_vespa.tscn",
	"auto": "res://world/vehiculos/auto_datsun.tscn",
	"camioneta": "res://world/vehiculos/camioneta_zuk.tscn",
	"ford": "res://world/vehiculos/auto_ford_escort.tscn",
}


func _ready() -> void:
	var suelo := StaticBody3D.new()
	var f := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(50, 1, 50)
	f.shape = b
	suelo.add_child(f)
	suelo.position.y = -0.5
	add_child(suelo)
	var j := (load(JUG) as PackedScene).instantiate() as Node3D
	add_child(j)
	for i in 90:
		await get_tree().physics_frame
	var caps := (j.get_node("Colision") as CollisionShape3D).shape as CapsuleShape3D
	print("[escala] cápsula del jugador: alto %.2f radio %.2f" % [caps.height, caps.radius])
	for nombre in ["Humano", "Visual"]:
		var n := j.get_node_or_null(nombre) as Node3D
		if n == null:
			continue
		var caja := _caja_visible(n)
		print("[escala] %s visible=%s | AABB global y %.2f..%.2f (alto %.2f) | ancho %.2f fondo %.2f" % [
				nombre, n.is_visible_in_tree(), caja.position.y, caja.end.y, caja.size.y, caja.size.x, caja.size.z])
	# Cada forma hija de Visual por separado
	var v := j.get_node_or_null("Visual/Pose/Volteo")
	if v != null:
		for h in v.get_children():
			if h is Node3D:
				var c := _caja_visible(h, false)
				print("[escala]   forma %s visible=%s alto %.2f" % [h.name, (h as Node3D).is_visible_in_tree(), c.size.y])
	for k in VEH.keys():
		var veh := (load(VEH[k]) as PackedScene).instantiate() as VehiculoAparcado
		add_child(veh)
		await get_tree().process_frame
		var col := veh.get_node_or_null("Colision") as CollisionShape3D
		print("[escala] %s: largo %.2f ancho %.2f alto %.2f | escala modelo %.4f | caja col %s" % [
				k, veh.largo_m(), veh.ancho_m(), veh.alto_m(), (veh.get_node("Modelo") as Node3D).scale.x,
				str((col.shape as BoxShape3D).size) if col else "-"])
		veh.queue_free()
	print("[escala] FIN")


## Caja de las MeshInstance3D (con su pose skinneada aproximada por la AABB) en
## espacio global. Si solo_visibles, ignora las ocultas.
func _caja_visible(raiz: Node, solo_visibles: bool = true) -> AABB:
	var caja := AABB()
	var primero := true
	for n in raiz.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or (solo_visibles and not mi.is_visible_in_tree()):
			continue
		var a := mi.global_transform * mi.get_aabb()
		caja = a if primero else caja.merge(a)
		primero = false
	return caja
