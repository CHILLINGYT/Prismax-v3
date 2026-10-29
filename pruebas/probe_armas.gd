extends SceneTree

## SONDA (no es una suite): comprueba que los recursos REALES de las armas
## cargan desde su ubicación definitiva (Tarea 7, "modelos 3d armas/" y
## "Audio/disparo/") y mide la geometría que necesitan las tareas 1 y 2:
##   · el AK real: nº de mallas/materiales y su caja envolvente compuesta;
##   · el cartucho: caja envolvente (eje largo y largo real del modelo);
##   · el audio de disparo: duración y formato importados.
##
## Se ejecuta con:
##   Godot --headless --path . --script res://pruebas/probe_armas.gd

func _init() -> void:
	print("=== PROBE ARMAMENTO (Tareas 1, 2 y 3) ===")
	# Piezas del AK cuya posición se quiere comprobar (nombres reales del glTF): la
	# boca del cañón, la empuñadura y el cargador son las referencias de la Tarea 1.
	_caja("res://modelos 3d armas/akmn.glb", "AK",
			["comp_low_barrel_0", "wStock.001_low_wStock_0", "bGrip_low_receiver_0",
			"akmMag.001_low.003_akmMag_0", "barrel.001_low_barrel_0"])
	_caja("res://modelos 3d armas/bullet_6.5x55mm_swedish.glb", "CARTUCHO", [])
	var st := load("res://Audio/disparo/freesound_community-ak47-sfx-102801 (mp3cut.net).wav") as AudioStream
	if st == null:
		print("[Audio] NO carga el disparo")
	else:
		print("[Audio] disparo OK: ", st.get_class(), "  duracion = %.3f s" % st.get_length(), "  bus sugerido Efectos")
	quit()

## Caja envolvente COMPUESTA del recurso (en el espacio de su raíz) + conteo de
## mallas y de superficies con material.
func _caja(ruta: String, etiqueta: String, piezas: Array = []) -> void:
	var t0 := Time.get_ticks_msec()
	var ps := load(ruta) as PackedScene
	if ps == null:
		print("[%s] NO CARGA: %s" % [etiqueta, ruta])
		return
	var raiz := ps.instantiate() as Node3D
	var mallas := raiz.find_children("*", "MeshInstance3D", true, false)
	var con_material := 0
	var caja := AABB()
	var hay := false
	for m in mallas:
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			if mi.get_active_material(s) != null:
				con_material += 1
		# La caja va EN EL ESPACIO DE LA RAÍZ: se compone toda la cadena de padres
		# (hay nodos intermedios con escala: multiplicar sólo su transform propio
		# da medidas falsas — cientos de unidades donde el arma mide ~0,9 m).
		var a: AABB = _compuesta(mi, mi.get_aabb())
		caja = a if not hay else caja.merge(a)
		hay = true
	print("[%s] carga en %d ms | mallas=%d | superficies con material=%d" % [
			etiqueta, Time.get_ticks_msec() - t0, mallas.size(), con_material])
	if hay:
		print("      raiz=%s | AABB compuesto min=%v max=%v" % [
				raiz.name, caja.position, caja.position + caja.size])
		print("      TAMANO (X,Y,Z)=%v" % caja.size)
		if piezas:
			_detalle_piezas(raiz, piezas)
	raiz.free()

## Caja de una malla en el espacio de la RAÍZ de su escena (compone los padres).
func _compuesta(n: Node3D, caja: AABB) -> AABB:
	var t := n.transform
	var p := n.get_parent() as Node3D
	while p != null:
		t = p.transform * t
		p = p.get_parent() as Node3D
	return t * caja

## Imprime la caja compuesta de las piezas pedidas por nombre de nodo (boca del
## cañón, empuñadura, cargador, culata...): son las referencias que usan las tareas
## 1 y 2 para colocar la boca del arma y el eje del cartucho.
func _detalle_piezas(raiz: Node3D, nombres: Array) -> void:
	for m in raiz.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null or not nombres.has(String(mi.name)):
			continue
		var c := _compuesta(mi, mi.get_aabb())
		print("      · %-34s min=%v max=%v" % [mi.name, c.position, c.position + c.size])