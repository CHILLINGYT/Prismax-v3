class_name TrazadorRuta
extends Node3D

# Sistema de trazado libre de una ruta de supervelocidad.
# - El trazado empieza en el personaje.
# - Cada movimiento del mouse agrega puntos (con distancia minima => evita zigzags).
# - Al finalizar se suaviza y se remuestrea con una spline Catmull-Rom (curvas suaves).
# - Fase de planificacion: linea energetica limpia sobre el suelo.
# - Fase de ejecucion: la linea se transforma en una estela de supervelocidad.

var activo: bool = false
var en_ejecucion: bool = false
var puntos: Array[Vector3] = []
var min_dist: float = 0.45

# --- Consulta del suelo ---------------------------------------------------
# La ruta ya no se apoya en un plano horizontal fijo (eso dejaba la línea
# flotando o enterrada en cuanto el terreno subía o bajaba): cada punto se
# posa sobre el suelo real sondeado con un rayo.
## Capa de física del terreno transitable (mundo: ciudad + isla). Es una máscara
## de consulta PROPIA del trazado; no cambia la collision_mask del personaje.
var mascara_suelo: int = 1
## Subida admitida sobre el punto anterior, sin contar el margen por distancia (m).
## Cubre de sobra un bordillo de acera (0,15 m) y el ruido del terreno.
const SALTO_ARRIBA_BASE := 1.0
## Margen extra de subida por cada metro recorrido en horizontal: deja pasar una
## cuesta muy empinada (≈50°) aunque el cursor se mueva deprisa.
const SALTO_ARRIBA_POR_METRO := 1.2
## Tope de subida (m). Un edificio tiene 5 m o más de alto, así que su AZOTEA
## nunca entra: esto es lo que impide que la ruta se suba a los tejados.
const SALTO_ARRIBA_MAX := 4.0
## Bajada admitida respecto del punto anterior (m): una cuesta o un escalón bajan,
## un precipicio o el borde de una azotea no.
const SALTO_ABAJO := 4.0
## Componente vertical mínima de la normal para dar una superficie por pisable:
## 0,70 ≈ 45°. Una pared o un techo inclinado no lo pasan.
const NORMAL_PISABLE := 0.70
## Altura (m) a la que se comprueba si hay un muro que la ruta no puede cruzar.
const ALTURA_OBSTRUCCION := 1.1
## Por debajo de esta cota no hay suelo transitable a pie (nivel del océano).
var nivel_agua: float = -2.0

const MAX_HIST := 80
const ANCHO_PLAN := 0.18
const ANCHO_ESTELA := 0.32

var _cursor: Vector2
var _camara: Camera3D
var _plano_y: float = 0.0
var _plan_inst: MeshInstance3D
var _plan_mesh: ImmediateMesh
var _trail_inst: MeshInstance3D
var _trail_mesh: ImmediateMesh
var _marca: MeshInstance3D
var _historial: Array[Vector3] = []
var _t: float = 0.0
var _cuerpo: CollisionObject3D = null

func _ready() -> void:
	_cuerpo = get_parent() as CollisionObject3D
	_plan_inst = _crear_instancia()
	_plan_mesh = _plan_inst.mesh as ImmediateMesh
	_trail_inst = _crear_instancia()
	_trail_mesh = _trail_inst.mesh as ImmediateMesh
	_marca = _crear_marca()

func _crear_instancia() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.top_level = true
	mi.mesh = ImmediateMesh.new()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.material_override = m
	mi.visible = false
	add_child(mi)
	return mi

func _crear_marca() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.top_level = true
	var sm := SphereMesh.new()
	sm.radius = 0.14
	sm.height = 0.28
	mi.mesh = sm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(0.75, 1.0, 1.0)
	mi.material_override = m
	mi.visible = false
	add_child(mi)
	return mi

func iniciar(desde: Vector3, camara: Camera3D, _plano: float = 0.0) -> void:
	activo = true
	en_ejecucion = false
	puntos = [desde]
	_historial = [desde]
	_camara = camara
	_plano_y = desde.y
	_cursor = get_viewport().get_visible_rect().size * 0.5
	_plan_inst.visible = true
	_marca.visible = true
	_trail_inst.visible = false
	_reconstruir_plan()

func _input(event: InputEvent) -> void:
	if not activo or en_ejecucion:
		return
	if event is InputEventMouseMotion:
		_cursor += event.relative
		var r := get_viewport().get_visible_rect().size
		_cursor.x = clampf(_cursor.x, 0.0, r.x)
		_cursor.y = clampf(_cursor.y, 0.0, r.y)

func _process(delta: float) -> void:
	_t += delta
	if activo and not en_ejecucion:
		_agregar_desde_cursor()

func _agregar_desde_cursor() -> void:
	if _camara == null:
		return
	var origen := _camara.project_ray_origin(_cursor)
	var dir := _camara.project_ray_normal(_cursor)
	if absf(dir.y) < 0.02:
		return
	var t := (_plano_y - origen.y) / dir.y
	if t <= 0.0:
		return
	# El plano horizontal sólo decide DÓNDE (x, z): la altura se toma del suelo
	# real, así la ruta sigue las subidas y bajadas del terreno.
	var plano := origen + dir * t
	var previo := puntos[puntos.size() - 1] if not puntos.is_empty() else plano
	var hueco := 0.0
	if not puntos.is_empty():
		hueco = Vector2(plano.x - previo.x, plano.z - previo.z).length()
	var y := _altura_suelo(plano.x, plano.z, previo.y, hueco)
	if is_nan(y):
		return                                  # agua, muro o azotea: no hay ruta
	var punto := Vector3(plano.x, y, plano.z)
	if not puntos.is_empty() and not _paso_libre(previo, punto):
		return                                  # un muro de verdad: la ruta no cruza
	if puntos.is_empty() or (punto - puntos[puntos.size() - 1]).length() >= min_dist:
		puntos.append(punto)
		_reconstruir_plan()


## Altura del suelo transitable en (x, z), o NAN si no hay apoyo (agua, vacío,
## muro o azotea). Usa la geometría real del mundo (la ciudad y el terreno de la
## isla están los dos en la capa 1) y excluye la colisión del propio personaje.
##
## El sondeo NO se lanza desde muy arriba: se hace dentro de una BANDA alrededor
## de la altura del punto anterior ([param referencia]). Antes se lanzaba desde
## 220 m y, dentro de la ciudad, el rayo acertaba primero la AZOTEA de un edificio
## (24 m) en vez de la calle; la ruta se subía al tejado y el velocista se
## estrellaba contra la pared. Con la banda, un bordillo o una cuesta pasan y una
## azotea o un muro no.
func _altura_suelo(x: float, z: float, referencia: float = NAN, hueco: float = 0.0) -> float:
	var mundo := get_world_3d()
	if mundo == null:
		return NAN
	var ref := _plano_y if is_nan(referencia) else referencia
	var subida := clampf(SALTO_ARRIBA_BASE + SALTO_ARRIBA_POR_METRO * maxf(hueco, 0.0),
			SALTO_ARRIBA_BASE, SALTO_ARRIBA_MAX)
	var consulta := PhysicsRayQueryParameters3D.create(
			Vector3(x, ref + subida, z), Vector3(x, ref - SALTO_ABAJO, z), mascara_suelo)
	if _cuerpo != null:
		consulta.exclude = [_cuerpo.get_rid()]
	consulta.collide_with_areas = false
	var golpe := mundo.direct_space_state.intersect_ray(consulta)
	if golpe.is_empty():
		return NAN
	if (golpe["normal"] as Vector3).y < NORMAL_PISABLE:
		return NAN                              # pared o techo: no es suelo
	var y: float = (golpe["position"] as Vector3).y
	if y < nivel_agua:
		return NAN                              # bajo el agua no se corre a pie
	return y


## ¿Se puede ir a pie desde [param desde] hasta [param hasta]? Sondea a la altura
## del pecho (por encima de un bordillo, por debajo de una ventana): así la ruta
## se corta en un muro de verdad —un edificio— y no en un escalón de acera.
func _paso_libre(desde: Vector3, hasta: Vector3) -> bool:
	var mundo := get_world_3d()
	if mundo == null:
		return false
	var a := desde + Vector3.UP * ALTURA_OBSTRUCCION
	var b := hasta + Vector3.UP * ALTURA_OBSTRUCCION
	if a.distance_to(b) < 0.05:
		return true
	var consulta := PhysicsRayQueryParameters3D.create(a, b, mascara_suelo)
	if _cuerpo != null:
		consulta.exclude = [_cuerpo.get_rid()]
	consulta.collide_with_areas = false
	return mundo.direct_space_state.intersect_ray(consulta).is_empty()

func finalizar() -> Array[Vector3]:
	activo = false
	_marca.visible = false
	print("[Ziba] puntos de ruta dibujados: ", puntos.size())
	if puntos.size() < 2:
		return []
	var suave := _suavizar(puntos)
	var muestras := _catmull(suave, 0.6)
	# La spline puede cortar una loma o salirse sobre el agua: se vuelve a posar
	# cada punto muestreado sobre el suelo y la ruta se recorta donde el terreno
	# transitable se acaba (por ejemplo, en la línea de costa).
	var salida: Array[Vector3] = []
	var ancla: Vector3 = puntos[0]
	for p: Vector3 in muestras:
		var hueco := Vector2(p.x - ancla.x, p.z - ancla.z).length()
		var y := _altura_suelo(p.x, p.z, ancla.y, hueco)
		if is_nan(y):
			break
		var apoyo := Vector3(p.x, y, p.z)
		if not _paso_libre(ancla, apoyo):
			break
		salida.append(apoyo)
		ancla = apoyo
	print("[Ziba] puntos de recorrido apoyados en el suelo: ", salida.size())
	return salida

func _suavizar(pts: Array[Vector3]) -> Array[Vector3]:
	var out: Array[Vector3] = []
	out.resize(pts.size())
	for i in pts.size():
		out[i] = pts[i]
	for _p in 2:
		var ref: Array[Vector3] = []
		ref.resize(out.size())
		for i in out.size():
			ref[i] = out[i]
		for i in range(1, out.size() - 1):
			out[i] = ref[i - 1] * 0.25 + ref[i] * 0.5 + ref[i + 1] * 0.25
	return out

func _catmull(pts: Array[Vector3], paso: float) -> Array[Vector3]:
	if pts.size() < 2:
		return pts
	var muestras: Array[Vector3] = []
	var p: Array[Vector3] = [pts[0]]
	p.append_array(pts)
	p.append(pts[pts.size() - 1])
	for i in range(1, p.size() - 2):
		var p0 := p[i - 1]
		var p1 := p[i]
		var p2 := p[i + 1]
		var p3 := p[i + 2]
		var seg := p1.distance_to(p2)
		var n := maxi(1, int(ceil(seg / paso)))
		for j in n:
			var tt := float(j) / float(n)
			var q := 0.5 * ((2.0 * p1) + (-p0 + p2) * tt + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * tt * tt + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * tt * tt * tt)
			muestras.append(q)
	muestras.append(pts[pts.size() - 1])
	return muestras

func _reconstruir_plan() -> void:
	_construir(_plan_mesh, puntos, ANCHO_PLAN, 0.05, Color(0.65, 1.0, 1.0))
	if not puntos.is_empty():
		_marca.global_position = puntos[puntos.size() - 1] + Vector3.UP * 0.18
		var s := 1.0 + 0.3 * sin(_t * 7.0)
		_marca.scale = Vector3(s, s, s)

func set_ejecucion(v: bool) -> void:
	en_ejecucion = v
	if v:
		_plan_inst.visible = false
		_marca.visible = false
		_trail_inst.visible = true
		_reconstruir_estela()

func agregar_estela(pos: Vector3) -> void:
	if _historial.is_empty() or (pos - _historial[_historial.size() - 1]).length() >= 0.25:
		_historial.append(pos)
		while _historial.size() > MAX_HIST:
			_historial.pop_front()
	_reconstruir_estela()

func _reconstruir_estela() -> void:
	_construir(_trail_mesh, _historial, ANCHO_ESTELA, 0.06, Color(0.8, 0.95, 1.0, 0.65))

func finalizar_ejecucion() -> void:
	en_ejecucion = false
	activo = false
	var t := create_tween()
	t.tween_property(_trail_inst, "transparency", 1.0, 0.6)
	t.tween_callback(func() -> void:
		_trail_inst.visible = false
		_trail_inst.transparency = 0.0
		_trail_mesh.clear_surfaces())
	_plan_mesh.clear_surfaces()

func limpiar() -> void:
	activo = false
	en_ejecucion = false
	puntos.clear()
	_historial.clear()
	_plan_mesh.clear_surfaces()
	_trail_mesh.clear_surfaces()
	_plan_inst.visible = false
	_trail_inst.visible = false
	_marca.visible = false

func _construir(mesh: ImmediateMesh, pts: Array[Vector3], ancho: float, alto: float, color: Color) -> void:
	mesh.clear_surfaces()
	if pts.size() < 2:
		return
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var n := pts.size()
	for i in n:
		var p := pts[i]
		var dir: Vector3
		if i == 0:
			dir = pts[1] - pts[0]
		elif i == n - 1:
			dir = pts[n - 1] - pts[n - 2]
		else:
			dir = pts[i + 1] - pts[i - 1]
		dir.y = 0.0
		if dir.length() < 0.0001:
			dir = Vector3(0.0, 0.0, -1.0)
		dir = dir.normalized()
		var lado := dir.cross(Vector3.UP).normalized() * (ancho * 0.5)
		var base := p + Vector3.UP * alto
		mesh.surface_set_color(color)
		mesh.surface_add_vertex(base + lado)
		mesh.surface_set_color(color)
		mesh.surface_add_vertex(base - lado)
	mesh.surface_end()
