extends Node3D
## =============================================================================
##  VERIFICACIÓN TEMPORAL (se borra al terminar el trabajo)
## =============================================================================
##  Instancia el MAPA REAL y coloca una cámara libre para revisarlo desde
##  distintos puntos de vista. Teclas 1..0 y las flechas cambian de vista.
##  Así se comprueba siempre la escena de verdad, con su entorno y su luz.
## =============================================================================

const MAPA := "res://ziba/escenas/ziba_prototipo.tscn"

const VISTAS: Array = [
	{"nombre": "mapa cenital", "pos": Vector3(0.0, 640.0, -90.0), "mira": Vector3(-90.0, 0.0, -95.0), "fov": 85.0},
	{"nombre": "isla aerea", "pos": Vector3(-90.0, 420.0, 300.0), "mira": Vector3(-90.0, 0.0, -140.0), "fov": 75.0},
	{"nombre": "ciudad aerea", "pos": Vector3(0.0, 150.0, 190.0), "mira": Vector3(0.0, 0.0, -10.0), "fov": 70.0},
	{"nombre": "ciudad calle", "pos": Vector3(0.0, 2.2, 70.0), "mira": Vector3(0.0, 2.2, -40.0), "fov": 70.0},
	{"nombre": "transicion ciudad-bosque", "pos": Vector3(-100.0, 14.0, -100.0), "mira": Vector3(-420.0, 14.0, -420.0), "fov": 70.0},
	{"nombre": "montanas desde el bosque", "pos": Vector3(-160.0, 24.0, -130.0), "mira": Vector3(-370.0, 58.0, -60.0), "fov": 70.0},
	{"nombre": "costa sureste", "pos": Vector3(120.0, 22.0, 60.0), "mira": Vector3(330.0, -3.0, 220.0), "fov": 70.0},
	{"nombre": "playa", "pos": Vector3(320.0, 2.2, 0.0), "mira": Vector3(520.0, 0.6, 24.0), "fov": 70.0},
	{"nombre": "costa desde arriba", "pos": Vector3(260.0, 45.0, 0.0), "mira": Vector3(520.0, -10.0, 20.0), "fov": 70.0},
	{"nombre": "isla desde el mar", "pos": Vector3(620.0, 45.0, 260.0), "mira": Vector3(-90.0, 8.0, -90.0), "fov": 70.0},
]

var _camara: Camera3D
var _vista: int = 0
var _cuadros: int = 0
var _prueba: bool = false
var _t_prueba: float = 0.0
var _jugador: Node3D
var _camara_juego: bool = false
var _recorrido: bool = false
var _fase_recorrido: int = 0
var _t_recorrido: float = 0.0
var _pasos_trazo: int = 0
var _muestras_recorrido: int = 0
var _pos_inicial: Vector3 = Vector3.ZERO
var _perfil_impreso: bool = false
var _ocultar_fondo: bool = false


func _ready() -> void:
	var escena: PackedScene = load(MAPA)
	add_child(escena.instantiate())
	_camara = Camera3D.new()
	_camara.name = "CamaraLibre"
	_camara.far = 4000.0
	_camara.near = 0.1
	add_child(_camara)
	_aplicar(0)
	print("[vista] mapa cargado; teclas 1..0 cambian de punto de vista")


func _aplicar(i: int) -> void:
	_vista = clampi(i, 0, VISTAS.size() - 1)
	var v: Dictionary = VISTAS[_vista]
	_camara.fov = v["fov"]
	_camara.global_position = v["pos"]
	_camara.look_at(v["mira"], Vector3.UP)
	_camara.make_current()
	print("[vista] %d: %s  en %s" % [_vista + 1, v["nombre"], v["pos"]])


func _process(_delta: float) -> void:
	_cuadros += 1
	if _cuadros == 12:
		_comprobar_terreno()
	if _prueba:
		_procesar_prueba(_delta)
	if _recorrido:
		_procesar_recorrido(_delta)
	# El juego también crea su cámara: se reafirma la nuestra unas cuantas veces.
	if not _camara_juego and _cuadros in [2, 10, 30, 90] and not _camara.current:
		_camara.make_current()


## Prueba de la habilidad de recorrido (clic derecho) del velocista: coloca al
## velocista en [param desde], orienta su cámara a [param yaw], traza una ruta
## moviendo el cursor hacia arriba (como haría el jugador con el mouse), suelta y
## registra si el personaje recorre la ruta entera siguiendo el relieve.
func _iniciar_prueba_recorrido(desde: Vector3, yaw: float, nombre: String) -> void:
	var jug := find_child("Jugador", true, false) as CharacterBody3D
	if jug == null:
		print("[recorrido] no encuentro al jugador")
		return
	_jugador = jug
	# Se coloca con la altura ANALÍTICA del relieve, no con un rayo: nada más
	# teletransportar la cámara la colisión del terreno todavía no existe en el
	# sitio nuevo y el personaje aparecería dentro del terreno y caería al vacío.
	var suelo := Relieve.new().altura(desde.x, desde.z)
	jug.global_position = Vector3(desde.x, suelo + 1.5, desde.z)
	jug.velocity = Vector3.ZERO
	jug.call("_entrar_velocista")
	var pivote := jug.get_node_or_null("PivoteCamara") as Node3D
	if pivote != null:
		pivote.rotation.y = yaw
		if pivote.has_method("definir_pitch"):
			pivote.call("definir_pitch", -0.35)
	_camara_juego = true
	_camara.current = false
	var cam := find_child("Camara", true, false) as Camera3D
	if cam != null:
		cam.make_current()
	_recorrido = true
	_fase_recorrido = 0
	_t_recorrido = 0.0
	_pasos_trazo = 0
	_muestras_recorrido = 0
	_perfil_impreso = false
	_pos_inicial = desde
	print("[recorrido] %s: inicio en %s, rumbo %.0f°" % [nombre, desde, rad_to_deg(yaw)])


## Prueba del CORDÓN: coloca al velocista en la calzada y le da una ruta recta
## que cruza el bordillo de la acera. Sirve para reproducir el bloqueo del
## recorrido al subir un escalón urbano. Las alturas son las cotas REALES de la
## ciudad (calzada -0.155 = Y_TERRENO, acera -0.002 = Y_LOSA) y además se sondea
## la física en cada punto para comprobar que coincide con ellas.
func _iniciar_prueba_cordon(desde: Vector3, dir: Vector3, largo: float, nombre: String) -> void:
	var jug := find_child("Jugador", true, false) as CharacterBody3D
	if jug == null:
		print("[cordon] no encuentro al jugador")
		return
	_jugador = jug
	jug.global_position = Vector3(desde.x, 1.2, desde.z)
	jug.velocity = Vector3.ZERO
	jug.call("_entrar_velocista")
	var pivote := jug.get_node_or_null("PivoteCamara") as Node3D
	if pivote != null:
		pivote.rotation.y = atan2(-dir.x, -dir.z)
		if pivote.has_method("definir_pitch"):
			pivote.call("definir_pitch", -0.30)
	var puntos: Array[Vector3] = []
	var informe := ""
	var d := 0.0
	while d <= largo:
		var px := desde.x + dir.x * d
		var pz := desde.z + dir.z * d
		var alto := -0.155 if absf(px) < 6.0 else -0.002
		puntos.append(Vector3(px, alto, pz))
		var g: Variant = _rayo_suelo(px, pz)
		informe += "\n    x=%.1f ruta %.3f | fisica %s" % [px, alto, "SIN SUELO" if g == null else "%.3f" % (g as float)]
		d += 0.5
	print("[cordon] %s: %d puntos de (%.1f) a (%.1f)%s" % [nombre, puntos.size(), desde.x, desde.x + dir.x * largo, informe])
	if puntos.size() < 2:
		return
	jug.set("_puntos", puntos)
	jug.set("_idx", 0)
	jug.set("_vel_trayecto", jug.get("vel_trayecto_min"))
	jug.call("_iniciar_recorrido")
	_camara_juego = true
	_camara.current = false
	var cam := find_child("Camara", true, false) as Camera3D
	if cam != null:
		cam.make_current()
	_recorrido = true
	_fase_recorrido = 2
	_t_recorrido = 0.0
	_muestras_recorrido = 0
	_perfil_impreso = false
	_pos_inicial = jug.global_position


## Diagnóstico del agua: informa del árbol del océano (materiales, mallas,
## visibilidad) y, si [param ocultar_fondo], oculta el plano del fondo marino
## para distinguir si lo negro lo pone el fondo o la superficie del agua.
func _diagnostico_agua(ocultar_fondo: bool) -> void:
	var oceano := find_child("Oceano", true, false)
	if oceano == null:
		print("[agua] no encuentro el nodo Oceano")
		return
	for n: Node in oceano.get_children():
		var mi := n as MeshInstance3D
		var extra := ""
		if mi != null:
			var mat := mi.material_override
			if mat is ShaderMaterial:
				var sm := mat as ShaderMaterial
				extra = " shader=%s" % (sm.shader.resource_path if sm.shader != null else "NULO")
				for p: String in ["depth_fade", "alpha_deep", "alpha_shallow"]:
					extra += " %s=%s" % [p, str(sm.get_shader_parameter(p))]
			elif mat is StandardMaterial3D:
				extra = " albedo=%s" % str((mat as StandardMaterial3D).albedo_color)
			extra += " aabb=%s" % str(mi.get_aabb())
		print("[agua] %s (%s) visible=%s%s" % [n.name, n.get_class(), str(n.visible), extra])
		if ocultar_fondo and n.name == "FondoMarino":
			n.visible = false
			print("[agua] fondo marino OCULTO")


## Diagnóstico de la costa: mide el color REAL de los píxeles de la pantalla a
## distintas alturas (cielo, agua lejana, agua cercana) y comprueba si las
## texturas del terreno (incluida la arena del fondo) están cargadas. Con
## [param ocultar_agua] apaga la superficie del océano para ver qué hay debajo.
func _diagnostico_costa(ocultar_agua: bool) -> void:
	var img := get_viewport().get_texture().get_image()
	var vp := get_viewport().get_visible_rect().size
	var linea := ""
	for f: float in [0.30, 0.45, 0.52, 0.60, 0.75, 0.90]:
		var c := img.get_pixel(int(vp.x * 0.5), int(vp.y * f))
		linea += " y=%.2f:%s" % [f, c.to_html(false)]
	print("[costa] píxeles%s (agua %s)" % [linea, "OCULTA" if ocultar_agua else "visible"])
	if ocultar_agua:
		var oceano := find_child("Oceano", true, false)
		if oceano != null:
			var w := oceano.get_node_or_null("Water")
			if w != null:
				(w as Node3D).visible = false
	if _ocultar_fondo:
		var oceano2 := find_child("Oceano", true, false)
		if oceano2 != null:
			var f := oceano2.get_node_or_null("FondoMarino")
			if f != null:
				(f as Node3D).visible = false
	var terreno := find_child("Terrain3D", true, false)
	if terreno != null:
		var assets: Terrain3DAssets = (terreno as Terrain3D).assets
		if assets != null:
			var nombres := ""
			for i: int in assets.get_texture_count():
				var ta: Terrain3DTextureAsset = assets.get_texture(i)
				nombres += " [%d]%s=%s" % [i, ta.name,
						ta.albedo_texture.resource_path if ta.albedo_texture != null else "NULO"]
			print("[costa] texturas del terreno:%s" % nombres)
		print("[costa] terreno visible=%s material.world_background=%d" % [
				str((terreno as Node3D).visible), (terreno as Terrain3D).material.world_background])


## Pone el terreno del complemento en gris plano (modo de depuración del propio
## Terrain3D): sirve para saber si una zona se está dibujando o no.
func _terreno_gris() -> void:
	var t := find_child("Terrain3D", true, false) as Terrain3D
	if t == null:
		print("[costa] no encuentro el Terrain3D")
		return
	t.material.show_grey = true
	t.material.update()
	var informe := ""
	for p: Vector2 in [Vector2(320, 0), Vector2(360, 0), Vector2(420, 0), Vector2(520, 0), Vector2(700, 0), Vector2(1000, 0)]:
		var g: Variant = _rayo_suelo(p.x, p.y)
		informe += "\n    (%.0f,%.0f) relieve %.1f | fisica %s" % [p.x, p.y, Relieve.new().altura(p.x, p.y),
				"SIN SUELO" if g == null else "%.2f" % (g as float)]
	print("[costa] terreno en GRIS plano (show_grey=true, update())%s" % informe)


## Tiñe el agua con colores imposibles (verde claro en lo somero, magenta en lo
## profundo) para comprobar si el shader del océano está respondiendo de verdad.
func _agua_prueba() -> void:
	var oceano := find_child("Oceano", true, false)
	if oceano == null:
		print("[costa] no encuentro el Oceano")
		return
	var w := oceano.get_node_or_null("Water") as MeshInstance3D
	if w == null:
		print("[costa] no encuentro el Water")
		return
	var m := w.material_override as ShaderMaterial
	if m == null:
		print("[costa] el Water no tiene ShaderMaterial")
		return
	m.set_shader_parameter("color_shallow", Color(0.0, 1.0, 0.0))
	m.set_shader_parameter("color_deep", Color(1.0, 0.0, 1.0))
	m.set_shader_parameter("alpha_shallow", 0.0)
	m.set_shader_parameter("alpha_deep", 1.0)
	m.set_shader_parameter("depth_fade", 40.0)
	w.visible = true
	print("[costa] agua teñida: verde=shallow, magenta=deep, depth_fade=40")


## Oculta el nodo del terreno (Terrain3D): si la pantalla no cambia, es que esa
## zona no la está dibujando el terreno.
func _ocultar_terreno() -> void:
	var t := find_child("Terrain3D", true, false)
	if t == null:
		print("[costa] no encuentro el Terrain3D")
		return
	(t as Node3D).visible = false
	print("[costa] terreno OCULTO")


## Comprueba las REGIONES del terreno en puntos de tierra y de mar: si bajo el
## agua no hay región, el shader no dibuja superficie (o dibuja el fondo).
func _regiones_terreno() -> void:
	var t := find_child("Terrain3D", true, false) as Terrain3D
	if t == null:
		print("[costa] no encuentro el Terrain3D")
		return
	print("[costa] regiones: %d | locations=%s" % [
			t.data.get_region_count(), str(t.data.get_region_locations())])
	for p: Vector2 in [Vector2(0, 0), Vector2(320, 0), Vector2(420, 0), Vector2(700, 0), Vector2(-300, -300)]:
		var pos := Vector3(p.x, 0.0, p.y)
		print("[costa]   (%.0f,%.0f) has_region=%s id=%d loc=%s" % [
				p.x, p.y, str(t.data.has_regionp(pos)), t.data.get_region_idp(pos),
				str(t.data.get_region_location(pos))])
	print("[costa] altura en (320,0)=%.2f y en (700,0)=%.2f" % [
			t.data.get_height(Vector3(320.0, 0.0, 0.0)), t.data.get_height(Vector3(700.0, 0.0, 0.0))])


## Sustituye el shader del terreno por uno rojo plano: si la zona sumergida sale
## roja, la geometría se dibuja y el problema está en el shader del complemento.
func _terreno_rojo() -> void:
	var t := find_child("Terrain3D", true, false) as Terrain3D
	if t == null:
		print("[costa] no encuentro el Terrain3D")
		return
	var sh := Shader.new()
	sh.code = "shader_type spatial;\nvoid fragment() { ALBEDO = vec3(1.0, 0.0, 0.0); ROUGHNESS = 1.0; }"
	t.material.set_shader_override(sh)
	t.material.enable_shader_override(true)
	t.material.update()
	print("[costa] terreno con shader ROJO, override=%s" % str(t.material.is_shader_override_enabled()))


## Compara la altura del relieve con la que devuelve la física a lo largo de la
## ruta que se va a trazar: sirve para saber si el terreno visible y su colisión
## están sincronizados en el sitio por donde va a correr el personaje.
func _diagnostico_suelo() -> void:
	var rel := Relieve.new()
	var adelante: Vector3 = -(_jugador as Node3D).global_transform.basis.z
	var cad := ""
	for d: float in [0.0, 20.0, 40.0, 60.0, 80.0, 110.0]:
		var px := _jugador.global_position.x + adelante.x * d
		var pz := _jugador.global_position.z + adelante.z * d
		var fis: Variant = _rayo_suelo(px, pz)
		var texto := "SIN COLISION" if fis == null else "%.1f" % (fis as float)
		cad += "\n    a %.0f m: relieve %.1f | fisica %s" % [d, rel.altura(px, pz), texto]
	print("[recorrido] suelo a lo largo de la ruta:%s" % cad)


## Altura del suelo real (capa 1) en (x, z): la prueba coloca al personaje sobre
## el terreno de verdad, no a una altura fija.
func _suelo(x: float, z: float) -> float:
	var mundo := get_world_3d()
	if mundo == null:
		return 0.0
	var consulta := PhysicsRayQueryParameters3D.create(
			Vector3(x, 300.0, z), Vector3(x, -200.0, z), 1)
	var golpe := mundo.direct_space_state.intersect_ray(consulta)
	if golpe.is_empty():
		return 0.0
	return (golpe["position"] as Vector3).y


func _procesar_recorrido(delta: float) -> void:
	_t_recorrido += delta
	match _fase_recorrido:
		0:                                          # dejar que se asiente en el suelo
			# Casi dos segundos: la cámara acaba de saltar con el personaje y la
			# colisión del terreno (que Terrain3D construye alrededor de la cámara)
			# necesita unos fotogramas para existir bajo sus pies.
			if _t_recorrido > 1.8:
				Input.action_press("cargar_poder")
				_pos_inicial = _jugador.global_position
				print("[recorrido] cargando poder y trazando... (suelo bajo el jugador %.2f, jugador y=%.2f)" % [
						_suelo(_jugador.global_position.x, _jugador.global_position.z), _jugador.global_position.y])
				_diagnostico_suelo()
				_fase_recorrido = 1
		1:                                          # trazar moviendo el cursor
			if _t_recorrido > 0.03:
				_t_recorrido = 0.0
				var ev := InputEventMouseMotion.new()
				ev.relative = Vector2(0.0, -3.0)
				Input.parse_input_event(ev)
				_pasos_trazo += 1
			if _pasos_trazo >= 55:
				Input.action_release("cargar_poder")
				print("[recorrido] suelto el poder")
				_fase_recorrido = 2
				_t_recorrido = 0.0
		2:                                          # seguir la ejecución
			if not _perfil_impreso:
				_perfil_impreso = true
				var pts: Array = _jugador.get("_puntos")
				if pts.size() >= 2:
					var y0: float = (pts[0] as Vector3).y
					var y1: float = (pts[pts.size() - 1] as Vector3).y
					var ymin := y0
					var ymax := y0
					for q: Vector3 in pts:
						ymin = minf(ymin, q.y)
						ymax = maxf(ymax, q.y)
					print("[recorrido] ruta de %d puntos: altura inicio %.1f, fin %.1f, min %.1f, max %.1f" % [
							pts.size(), y0, y1, ymin, ymax])
			if _t_recorrido > 0.5:
				_t_recorrido = 0.0
				_muestras_recorrido += 1
				var puntos: Array = _jugador.get("_puntos")
				var p := _jugador.global_position
				print("[recorrido] t=%.1f  estado=%d  punto=%d/%d  pos=(%.1f, %.1f, %.1f)  recorrido=%.0f m" % [
						_muestras_recorrido * 0.5, _jugador.get("estado"), _jugador.get("_idx"),
						puntos.size(), p.x, p.y, p.z, p.distance_to(_pos_inicial)])
				if _muestras_recorrido >= 14:
					_recorrido = false
					print("[recorrido] fin: %d puntos de ruta, distancia %.0f m, desnivel %.1f m" % [
							puntos.size(), p.distance_to(_pos_inicial), p.y - _pos_inicial.y])


## Comprueba que la superficie visible (la que describe Relieve.altura) y la
## superficie física (la colisión que usan los rayos y el personaje) coinciden en
## toda la isla. Es la comprobación de que malla y colisión están sincronizadas.
func _comprobar_terreno() -> void:
	var rel := Relieve.new()
	var peor := 0.0
	var donde := Vector2.ZERO
	var n := 0
	var sin_colision := 0
	var detalle := ""
	for i: int in range(36):
		var a := TAU * float(i) / 36.0
		for r: float in [180.0, 240.0, 300.0, 380.0, 460.0, 540.0]:
			var x := Relieve.CENTRO.x + cos(a) * r
			var z := Relieve.CENTRO.y + sin(a) * r
			# Dentro de la ciudad el rayo acierta azoteas de edificios, no el
			# terreno: la comprobación de la isla se hace fuera de su recinto.
			if absf(x) < 150.0 and absf(z) < 150.0:
				continue
			var analitica := rel.altura(x, z)
			if analitica < Relieve.NIVEL_MAR + 0.3:
				continue
			n += 1
			var golpe: Variant = _rayo_suelo(x, z)
			if golpe == null:
				sin_colision += 1
				continue
			var fisica: float = golpe
			var dif := absf(analitica - fisica)
			if dif > peor:
				peor = dif
				donde = Vector2(x, z)
				detalle = "analitica %.1f vs fisica %.1f" % [analitica, fisica]
	print("[terreno] malla vs colisión: %d puntos con colisión, %d sin colisión construida, diferencia máxima %.3f m %s en (%.0f, %.0f)" % [
			n - sin_colision, sin_colision, peor, detalle, donde.x, donde.y])


## Altura del suelo físico (capa 1) o null si el rayo no encuentra nada.
func _rayo_suelo(x: float, z: float) -> Variant:
	var mundo := get_world_3d()
	if mundo == null:
		return null
	var consulta := PhysicsRayQueryParameters3D.create(
			Vector3(x, 300.0, z), Vector3(x, -200.0, z), 1)
	var golpe := mundo.direct_space_state.intersect_ray(consulta)
	if golpe.is_empty():
		return null
	return (golpe["position"] as Vector3).y


## Prueba de los límites del mundo: coloca al jugador junto al muro este, orienta
## su cámara hacia +X y lo empuja hacia el muro durante unos segundos, informando
## de su posición. Si el límite funciona, la X se queda pegada al muro.
func _iniciar_prueba_limites() -> void:
	_jugador = find_child("Jugador", true, false) as Node3D
	if _jugador == null:
		print("[limites] no encuentro al jugador")
		return
	_jugador.global_position = Vector3(1770.0, -60.0, 0.0)
	var pivote := _jugador.get_node_or_null("PivoteCamara") as Node3D
	if pivote != null:
		pivote.rotation.y = -PI / 2.0          # mirando hacia +X
	_camara.fov = 60.0
	_camara.global_position = Vector3(1600.0, 55.0, 220.0)
	_camara.look_at(Vector3(1900.0, 0.0, 0.0), Vector3.UP)
	_camara.make_current()
	_prueba = true
	_t_prueba = 0.0
	print("[limites] jugador en %s, empujando hacia +X" % _jugador.global_position)


func _procesar_prueba(delta: float) -> void:
	_t_prueba += delta
	if _t_prueba < 7.0:
		Input.action_press("mover_adelante")
	else:
		Input.action_release("mover_adelante")
	if floori(_t_prueba) != floori(_t_prueba - delta):
		var vel := Vector3.ZERO
		if _jugador is CharacterBody3D:
			vel = (_jugador as CharacterBody3D).velocity
		print("[limites] t=%.0f  pos=(%.1f, %.1f, %.1f)  vel=(%.2f, %.2f, %.2f)" % [
				_t_prueba, _jugador.global_position.x, _jugador.global_position.y, _jugador.global_position.z,
				vel.x, vel.y, vel.z])


func _input(evento: InputEvent) -> void:
	if evento is InputEventKey and (evento as InputEventKey).pressed and not (evento as InputEventKey).echo:
		var k: int = (evento as InputEventKey).keycode
		if k >= KEY_1 and k <= KEY_9:
			_aplicar(k - KEY_1)
		elif k == KEY_0:
			_aplicar(9)
		elif k == KEY_L:
			_iniciar_prueba_limites()
		elif k == KEY_C:
			_camara_juego = true          # deja la cámara real del juego
			_camara.current = false
			var cam_juego := find_child("Camara", true, false) as Camera3D
			if cam_juego != null:
				cam_juego.make_current()
			print("[vista] cámara del juego (%s)" % cam_juego)
		elif k == KEY_N:
			var ciclo := find_child("CicloDiaNoche", true, false)
			if ciclo != null:
				ciclo.set("_fase", 0.95)   # noche cerrada
				print("[vista] fase nocturna")
		elif k == KEY_T:
			_iniciar_prueba_recorrido(Vector3(-230.0, 0.0, -230.0), PI / 4.0, "bosque -> montanas")
		elif k == KEY_Y:
			_iniciar_prueba_recorrido(Vector3(0.0, 0.0, 70.0), 0.0, "calle de la ciudad")
		elif k == KEY_U:
			_iniciar_prueba_recorrido(Vector3(150.0, 0.0, 150.0), -PI * 0.75, "hacia la costa")
		elif k == KEY_I:
			# Recorrido REAL (usa el trazador): desde la calzada hacia +X, con lo que
			# cruza la acera y llega a un edificio, que es el caso que se atascaba.
			_iniciar_prueba_recorrido(Vector3(0.0, 0.0, 70.0), -PI / 2.0, "calzada -> acera -> edificio")
		elif k == KEY_K:
			_diagnostico_agua(true)
		elif k == KEY_O:
			_diagnostico_costa(false)
		elif k == KEY_P:
			_diagnostico_costa(true)
		elif k == KEY_Q:
			_ocultar_fondo = true
			_diagnostico_costa(true)
		elif k == KEY_R:
			_terreno_gris()
		elif k == KEY_S:
			_agua_prueba()
		elif k == KEY_J:
			_ocultar_terreno()
		elif k == KEY_V:
			_regiones_terreno()
		elif k == KEY_W:
			_terreno_rojo()
	if evento.is_action_pressed("ui_right"):
		_aplicar(_vista + 1)
	elif evento.is_action_pressed("ui_left"):
		_aplicar(_vista - 1)