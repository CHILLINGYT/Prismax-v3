extends Node3D
## =============================================================================
##  RECORRIDO TEMPORAL: playa, prado costero y ventanas nocturnas
## =============================================================================
##  Verificación visual de las mejoras estéticas (se retira al terminar el
##  trabajo): instancia el MAPA REAL con semilla fija, informa las posiciones
##  reales del mobiliario de playa y de las ventanas encendidas, y coloca una
##  cámara libre con varias vistas.
##  Teclas 1..6: vistas.  Tecla N: alterna día/noche.
## =============================================================================

const MAPA := "res://ziba/escenas/ziba_prototipo.tscn"
const SEMILLA := 20260707

# Las vistas con y = 0 en "pos" se apoyan en la altura REAL del terreno +1,6 m
# (cámara a la altura de los ojos sobre la arena o el césped). Las vistas con
# "auto" buscan su objetivo entre las instancias reales ya generadas.
const VISTAS: Array = [
	{"nombre": "playa este a nivel de ojo", "pos": Vector3(171, 0, -40), "mira": Vector3(148, 2, 70), "fov": 70.0},
	{"nombre": "playa sureste aerea", "pos": Vector3(85, 48, 115), "mira": Vector3(160, -1, 168), "fov": 68.0},
	{"nombre": "loma desde la arena (como la foto)", "pos": Vector3(-40, 0, 158), "mira": Vector3(-220, 16, 170), "fov": 72.0},
	{"nombre": "paseo y arena a ras", "pos": Vector3(163, 2.4, 25), "mira": Vector3(152, 0.2, 105), "fov": 72.0},
	{"nombre": "primer plano sombrilla+reposeras", "pos": Vector3.ZERO, "auto": "mobiliario", "fov": 60.0},
	{"nombre": "ciudad y ventanas (tecla N)", "pos": Vector3(300, 55, 150), "mira": Vector3(30, 12, 20), "fov": 66.0},
]

var _camara: Camera3D
var _vista := 0
var _ciclo: Node
var _noche := false
var _mapa: Node3D
var _t := 0.0
var _informado := false


func _ready() -> void:
	var escena: PackedScene = load(MAPA)
	_mapa = escena.instantiate()
	var ciudad := _mapa.get_node_or_null("Ciudad")
	if ciudad != null:
		ciudad.set("semilla", SEMILLA)
	add_child(_mapa)
	_ciclo = _mapa.get_node_or_null("CicloDiaNoche")
	_camara = Camera3D.new()
	_camara.name = "CamaraLibre"
	_camara.far = 4000.0
	_camara.near = 0.1
	add_child(_camara)
	_aplicar(0)
	print("[vista_playa] mapa cargado (semilla %d)" % SEMILLA)


func _process(delta: float) -> void:
	# La ciudad se genera en los primeros segundos: cuando ya hay datos, se
	# vuelcan una vez las posiciones reales y se reafirma la cámara (el juego
	# crea la suya al arrancar).
	_t += delta
	if not _informado and _t > 5.0:
		_informar_posiciones()
	if _camara != null and not _camara.current:
		_camara.make_current()


## Vuelca a la consola las posiciones REALES del mobiliario de playa y de las
## ventanas encendidas (para encuadrar las cámaras sobre lo generado) y valida
## las reglas de colocación: con el render real las transformaciones de la
## MultiMesh sí se leen (en headless devuelven identidad).
func _informar_posiciones() -> void:
	_informado = true
	var ciudad := _mapa.get_node_or_null("Ciudad")
	if ciudad == null:
		print("[vista_playa] sin nodo Ciudad")
		return
	var props: Node = ciudad.get_node_or_null("CiudadGenerada/Props")
	if props == null:
		print("[vista_playa] la ciudad no se ha generado")
		return
	var rel := Relieve.new()
	var palmeras: Array[Vector2] = []
	var sombrillas: Array[Vector2] = []
	var reposeras: Array[Vector2] = []
	var e_min := 99.0
	var e_max := -99.0
	var flotan := 0
	var en_agua := 0
	print("[vista_playa] == mobiliario de playa (instancias reales) ==")
	for n in props.get_children():
		var mmi := n as MultiMeshInstance3D
		if mmi == null:
			continue
		if not (mmi.name.begins_with("Palmeras") or mmi.name.begins_with("Sombrillas")
				or mmi.name.begins_with("Reposeras")):
			continue
		var cuantas: int = mmi.multimesh.instance_count
		print("  %s x%d" % [mmi.name, cuantas])
		for k in cuantas:
			var t: Transform3D = mmi.multimesh.get_instance_transform(k)
			var o := t.origin
			if mmi.name.begins_with("Sombrillas"):
				sombrillas.append(Vector2(o.x, o.z))
			elif mmi.name.begins_with("Reposeras"):
				reposeras.append(Vector2(o.x, o.z))
			else:
				palmeras.append(Vector2(o.x, o.z))
				e_min = minf(e_min, t.basis.get_scale().y)
				e_max = maxf(e_max, t.basis.get_scale().y)
				if o.y - rel.altura(o.x, o.z) > 0.02:
					flotan += 1
				if rel.altura(o.x, o.z) < -1.7:
					en_agua += 1
	var alto_malla: float = Playa.malla_palmera().get_aabb().size.y
	print("  palmeras: escala=%.2f..%.2f -> alto=%.1f..%.1f m (malla %.1f)  flotan=%d  en_agua=%d"
			% [e_min, e_max, alto_malla * e_min, alto_malla * e_max, alto_malla, flotan, en_agua])
	var fuera_arena := 0
	for s in sombrillas:
		var h := rel.altura(s.x, s.y)
		if h > Relieve.COTA_ARENA or h < -1.35:
			fuera_arena += 1
	var junta_rep := 0
	var rep_vs_somb := 99.0
	for r in reposeras:
		var h2 := rel.altura(r.x, r.y)
		if h2 > Relieve.COTA_ARENA - 0.04 or h2 < -1.45:
			fuera_arena += 1
		for s in sombrillas:
			rep_vs_somb = minf(rep_vs_somb, r.distance_to(s))
		for r2 in reposeras:
			if r != r2 and r.distance_to(r2) < 1.14:
				junta_rep += 1
	print("  sombrillas=%d (fuera de arena seca: %d)  reposeras=%d  sombrillas<->reposera min=%.2f m  pares de reposeras <1.14 m=%d"
			% [sombrillas.size(), fuera_arena, reposeras.size(), rep_vs_somb, junta_rep])
	var muestra := ""
	for i in mini(3, palmeras.size()):
		muestra += "(%d,%d) " % [palmeras[i].x, palmeras[i].y]
	print("  ejemplo palmeras: ", muestra)
	var modulares: Node = ciudad.get_node_or_null("CiudadGenerada/Edificios/Modulares")
	if modulares != null:
		for n2 in modulares.get_children():
			var v := n2 as MultiMeshInstance3D
			if v != null and v.name.begins_with("VentanasNoche"):
				var muestra2 := ""
				for k in mini(v.multimesh.instance_count, 6):
					var o2: Vector3 = v.multimesh.get_instance_transform(k).origin
					muestra2 += "(%.0f,%.0f,%.0f) " % [o2.x, o2.y, o2.z]
				print("  %s  %s" % [v.name, muestra2])
	var control := ciudad.get_node_or_null("CiudadGenerada/LucesVentanas")
	if control != null:
		print("  ", control.call("resumen"))


func _aplicar(i: int) -> void:
	_vista = clampi(i, 0, VISTAS.size() - 1)
	var v: Dictionary = VISTAS[_vista]
	var pos: Vector3 = v["pos"]
	var mira: Vector3 = v.get("mira", Vector3.ZERO)
	if v.has("auto"):
		var objetivo := _buscar_objetivo(String(v["auto"]))
		if objetivo != Vector3.ZERO:
			var rel := Relieve.new()
			var desde := objetivo + Vector3(5.5, 0.0, 4.2)
			pos = Vector3(desde.x, rel.altura(desde.x, desde.z) + 1.9, desde.z)
			mira = objetivo + Vector3(0.0, 0.8, 0.0)
	elif is_zero_approx(pos.y):
		pos.y = Relieve.new().altura(pos.x, pos.z) + 1.6
	_camara.fov = v["fov"]
	_camara.global_position = pos
	_camara.look_at(mira, Vector3.UP)
	_camara.make_current()
	print("[vista_playa] %d: %s en %s (mira %s)" % [_vista + 1, v["nombre"], pos, mira])


## Objetivo automático de las vistas "auto": hoy, la sombrilla con más
## reposeras alrededor (el ejemplar más completo del mobiliario).
func _buscar_objetivo(que: String) -> Vector3:
	if que != "mobiliario":
		return Vector3.ZERO
	var ciudad := _mapa.get_node_or_null("Ciudad")
	if ciudad == null:
		return Vector3.ZERO
	var props: Node = ciudad.get_node_or_null("CiudadGenerada/Props")
	if props == null:
		return Vector3.ZERO
	var sombrillas: Array[Vector3] = []
	var reposeras: Array[Vector3] = []
	for n in props.get_children():
		var mmi := n as MultiMeshInstance3D
		if mmi == null:
			continue
		if not (mmi.name.begins_with("Sombrillas") or mmi.name.begins_with("Reposeras")):
			continue
		for k in mmi.multimesh.instance_count:
			var o: Vector3 = mmi.multimesh.get_instance_transform(k).origin
			if mmi.name.begins_with("Sombrillas"):
				sombrillas.append(o)
			else:
				reposeras.append(o)
	var mejor := Vector3.ZERO
	var mejor_n := -1
	for s in sombrillas:
		var n_cerca := 0
		for r in reposeras:
			if Vector2(r.x, r.z).distance_to(Vector2(s.x, s.z)) < 3.4:
				n_cerca += 1
		if n_cerca > mejor_n:
			mejor_n = n_cerca
			mejor = s
	return mejor


func _input(evento: InputEvent) -> void:
	if not (evento is InputEventKey) or not (evento as InputEventKey).pressed \
			or (evento as InputEventKey).echo:
		return
	var k: int = (evento as InputEventKey).keycode
	if k >= KEY_1 and k <= KEY_6:
		_aplicar(k - KEY_1)
	elif k == KEY_N:
		_noche = not _noche
		if _ciclo != null:
			_ciclo.set("_fase", 0.86 if _noche else 0.33)
		print("[vista_playa] noche=%s" % str(_noche))
	elif k == KEY_P:
		_informar_posiciones()