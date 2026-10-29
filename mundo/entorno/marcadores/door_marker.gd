@tool
class_name DoorMarker
extends Node3D
## =============================================================================
##  MARCADOR DE PUERTA (estilo entrada de propiedad de GTA San Andreas)
## =============================================================================
##  Flecha 3D que flota sobre el punto de entrada, GIRA despacio sobre su eje
##  vertical y SUBE Y BAJA con un vaivén suave. Amarillo saturado que no depende
##  de la luz de la escena (se ve igual de día y de noche) con contorno oscuro
##  para recortarse sobre cielo y fachadas claras. Detrás lleva un HALO y en el
##  suelo un ANILLO con ondas; los dos se encienden al acercarse el jugador.
##
##  Todo es nativo y se genera por código (ArrayMesh extruido + shaders): ningún
##  modelo importado. Reutilizable: instanciar `door_marker.tscn` donde haga falta
##  (el nodo raíz va A RAS DE SUELO, en el punto de entrada) y ajustar parámetros.

@export_group("Aspecto")
@export var color := Color(1.0, 0.76, 0.0):
	set(v):
		color = v
		_aplicar_materiales()
## Escala uniforme de la flecha (1 = ~1 m de alto).
@export_range(0.2, 4.0, 0.05) var escala := 1.0:
	set(v):
		escala = v
		if _pivote != null:
			_pivote.scale = Vector3.ONE * escala
@export var contorno := true:
	set(v):
		contorno = v
		if _contorno != null:
			_contorno.visible = v

@export_group("Movimiento")
## Altura (m) del centro del vaivén sobre el suelo.
@export var altura := 2.6
## Vueltas por segundo alrededor del eje vertical.
@export_range(0.0, 2.0, 0.01) var velocidad_giro := 0.35
## Amplitud (m) del vaivén vertical (arriba y abajo).
@export_range(0.0, 1.0, 0.01) var altura_vaiven := 0.15
## Ciclos de vaivén por segundo.
@export_range(0.0, 3.0, 0.01) var frecuencia_vaiven := 0.45

@export_group("Proximidad")
## Halo detrás de la flecha y anillo en el suelo.
@export var halo := true
@export var anillo_suelo := true
## Grupo donde se busca al jugador (el más cercano manda).
@export var grupo_jugador := &"player"
## Distancias (m): a `distancia_cerca` el brillo es máximo; más allá de
## `distancia_lejos` queda en su mínimo (la flecha nunca se apaga).
@export var distancia_cerca := 3.0
@export var distancia_lejos := 18.0
@export var radio_anillo := 0.9

var _pivote: Node3D
var _flecha: MeshInstance3D
var _contorno: MeshInstance3D
var _halo: MeshInstance3D
var _anillo: MeshInstance3D
var _mat_flecha: ShaderMaterial
var _mat_contorno: ShaderMaterial
var _mat_halo: ShaderMaterial
var _mat_anillo: ShaderMaterial
var _t := 0.0
var _cercania := 0.0


func _ready() -> void:
	_construir()
	set_process(true)


func _construir() -> void:
	for h in get_children():
		if String(h.name).begins_with("_DM"):
			h.free()
	_pivote = Node3D.new()
	_pivote.name = "_DMPivote"
	add_child(_pivote)
	_pivote.scale = Vector3.ONE * escala
	var malla := _malla_flecha()
	_mat_flecha = ShaderMaterial.new()
	_mat_flecha.shader = preload("res://mundo/entorno/marcadores/door_marker_flecha.gdshader")
	_flecha = MeshInstance3D.new()
	_flecha.name = "_DMFlecha"
	_flecha.mesh = malla
	_flecha.material_override = _mat_flecha
	_flecha.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pivote.add_child(_flecha)
	# Contorno: la misma malla, algo mayor alrededor de su centro, sólo por detrás.
	_mat_contorno = ShaderMaterial.new()
	_mat_contorno.shader = preload("res://mundo/entorno/marcadores/door_marker_contorno.gdshader")
	_contorno = MeshInstance3D.new()
	_contorno.name = "_DMContorno"
	_contorno.mesh = malla
	_contorno.material_override = _mat_contorno
	_contorno.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var centro := Vector3(0.0, 0.48, 0.0)
	var s := Vector3(1.09, 1.07, 1.45)
	_contorno.transform = Transform3D(Basis.from_scale(s), centro - centro * s)
	_contorno.visible = contorno
	_pivote.add_child(_contorno)
	var sh_halo := preload("res://mundo/entorno/marcadores/door_marker_halo.gdshader")
	_mat_halo = ShaderMaterial.new()
	_mat_halo.shader = sh_halo
	_mat_halo.set_shader_parameter("modo", 0)
	_halo = MeshInstance3D.new()
	_halo.name = "_DMHalo"
	var q := QuadMesh.new()
	q.size = Vector2(2.0, 2.0)
	_halo.mesh = q
	_halo.material_override = _mat_halo
	_halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_halo.position = Vector3(0.0, 0.5, 0.0)
	_pivote.add_child(_halo)
	_mat_anillo = ShaderMaterial.new()
	_mat_anillo.shader = sh_halo
	_mat_anillo.set_shader_parameter("modo", 1)
	_anillo = MeshInstance3D.new()
	_anillo.name = "_DMAnillo"
	var plano := PlaneMesh.new()
	plano.size = Vector2.ONE * 2.0
	_anillo.mesh = plano
	_anillo.material_override = _mat_anillo
	_anillo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_anillo.position = Vector3(0.0, 0.03, 0.0)
	_anillo.scale = Vector3.ONE * radio_anillo
	add_child(_anillo)
	_aplicar_materiales()
	_actualizar(0.0)


## Flecha apuntando hacia ABAJO, perfil extruido (grosor en Z). Punta en y = 0,
## cola en y = 1 (el pivote la coloca a `altura`). Caras planas con normales
## propias: el sombreado de la cara deja leer el volumen al girar.
func _malla_flecha() -> ArrayMesh:
	var cola := 0.98
	var cabeza := 0.44
	var ancho_cabeza := 0.34
	var ancho_vastago := 0.13
	var grosor := 0.075
	var perfil := PackedVector2Array([
		Vector2(-ancho_vastago, cola), Vector2(ancho_vastago, cola),
		Vector2(ancho_vastago, cabeza), Vector2(ancho_cabeza, cabeza),
		Vector2(0.0, 0.0),
		Vector2(-ancho_cabeza, cabeza), Vector2(-ancho_vastago, cabeza),
	])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tris := Geometry2D.triangulate_polygon(perfil)
	# Caras delantera (+Z) y trasera (−Z).
	for cara in [1.0, -1.0]:
		var z: float = grosor * cara
		st.set_normal(Vector3(0.0, 0.0, cara))
		for i in range(0, tris.size(), 3):
			var a := perfil[tris[i]]
			var b := perfil[tris[i + 1]]
			var c := perfil[tris[i + 2]]
			if cara > 0.0:
				st.add_vertex(Vector3(a.x, a.y, z)); st.add_vertex(Vector3(c.x, c.y, z)); st.add_vertex(Vector3(b.x, b.y, z))
			else:
				st.add_vertex(Vector3(a.x, a.y, z)); st.add_vertex(Vector3(b.x, b.y, z)); st.add_vertex(Vector3(c.x, c.y, z))
	# Laterales: un quad por arista del perfil, normal hacia fuera.
	var n := perfil.size()
	var horario := _area(perfil) < 0.0
	for i in n:
		var p0 := perfil[i]
		var p1 := perfil[(i + 1) % n]
		var e := (p1 - p0).normalized()
		var nor := Vector3(e.y, -e.x, 0.0) if not horario else Vector3(-e.y, e.x, 0.0)
		st.set_normal(nor)
		var a0 := Vector3(p0.x, p0.y, grosor)
		var a1 := Vector3(p1.x, p1.y, grosor)
		var b0 := Vector3(p0.x, p0.y, -grosor)
		var b1 := Vector3(p1.x, p1.y, -grosor)
		if not horario:
			st.add_vertex(a0); st.add_vertex(b1); st.add_vertex(a1)
			st.add_vertex(a0); st.add_vertex(b0); st.add_vertex(b1)
		else:
			st.add_vertex(a0); st.add_vertex(a1); st.add_vertex(b1)
			st.add_vertex(a0); st.add_vertex(b1); st.add_vertex(b0)
	return st.commit()


func _area(p: PackedVector2Array) -> float:
	var s := 0.0
	for i in p.size():
		var a := p[i]
		var b := p[(i + 1) % p.size()]
		s += a.x * b.y - b.x * a.y
	return s * 0.5


func _aplicar_materiales() -> void:
	if _mat_flecha == null:
		return
	_mat_flecha.set_shader_parameter("color", color)
	_mat_contorno.set_shader_parameter("color", Color(color.r * 0.16, color.g * 0.1, color.b * 0.05))
	_mat_halo.set_shader_parameter("color", color)
	_mat_anillo.set_shader_parameter("color", color)


func _process(delta: float) -> void:
	_actualizar(delta)


func _actualizar(delta: float) -> void:
	if _pivote == null:
		return
	_t += delta
	_pivote.position.y = altura + sin(_t * TAU * frecuencia_vaiven) * altura_vaiven
	_pivote.rotation.y = wrapf(_t * TAU * velocidad_giro, -PI, PI)
	# Cercanía del jugador (0 lejos → 1 cerca), suavizada.
	var objetivo := 0.0
	if not Engine.is_editor_hint() and is_inside_tree():
		var d := _distancia_jugador()
		objetivo = 1.0 - smoothstep(distancia_cerca, distancia_lejos, d)
	_cercania = lerpf(_cercania, objetivo, clampf(4.0 * delta, 0.0, 1.0))
	var pulso := 0.5 + 0.5 * sin(_t * 4.0)
	_halo.visible = halo
	_anillo.visible = anillo_suelo
	_mat_halo.set_shader_parameter("intensidad", lerpf(0.35, 0.95, _cercania) * lerpf(0.85, 1.0, pulso))
	_mat_anillo.set_shader_parameter("intensidad", lerpf(0.0, 1.0, _cercania))
	_mat_flecha.set_shader_parameter("brillo", lerpf(1.0, 1.25, _cercania))


func _distancia_jugador() -> float:
	var mejor := INF
	for n in get_tree().get_nodes_in_group(grupo_jugador):
		var j := n as Node3D
		if j != null and j.is_visible_in_tree():
			mejor = minf(mejor, j.global_position.distance_to(global_position))
	return mejor


# --- Lecturas (pruebas / otros sistemas) ------------------------------------
func altura_flecha() -> float:
	return _pivote.position.y if _pivote != null else 0.0


func giro_flecha() -> float:
	return _pivote.rotation.y if _pivote != null else 0.0


func cercania() -> float:
	return _cercania
