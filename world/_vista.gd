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
	{"nombre": "ciudad aerea", "pos": Vector3(-60.0, 130.0, -150.0), "mira": Vector3(120.0, 0.0, 110.0), "fov": 70.0},
	{"nombre": "ciudad calle", "pos": Vector3(0.0, 2.2, 70.0), "mira": Vector3(0.0, 2.2, -40.0), "fov": 70.0},
	{"nombre": "transicion ciudad-bosque", "pos": Vector3(-100.0, 14.0, -100.0), "mira": Vector3(-420.0, 14.0, -420.0), "fov": 70.0},
	{"nombre": "montanas desde el bosque", "pos": Vector3(-160.0, 24.0, -130.0), "mira": Vector3(-370.0, 58.0, -60.0), "fov": 70.0},
	{"nombre": "arboles de acera (bases)", "pos": Vector3(3.5, 1.8, 46.0), "mira": Vector3(6.6, 1.0, 14.0), "fov": 75.0},
	{"nombre": "union rasante (este, z=30)", "pos": Vector3(136.0, 1.7, 30.0), "mira": Vector3(172.0, -1.0, 34.0), "fov": 78.0},
	{"nombre": "ciudad y playa desde el mar", "pos": Vector3(330.0, 65.0, 165.0), "mira": Vector3(20.0, 0.0, 20.0), "fov": 70.0},
	{"nombre": "cielo hacia arriba", "pos": Vector3(-60.0, 60.0, -60.0), "mira": Vector3(-20.0, 400.0, 20.0), "fov": 80.0},
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
# Prueba de nado (tecla J): comprueba que sólo la forma acuática nada.
var _nado: bool = false
var _fase_nado: int = 0
var _t_nado: float = 0.0
var _muestras_nado: int = 0
# Prueba del límite de agua de las formas terrestres (tecla K).
var _limite: bool = false
var _fase_limite: int = 0
var _t_limite: float = 0.0
var _muestras_limite: int = 0
# Prueba del bug de ESPACIO durante el nado (tecla H): mantiene "saltar" pulsado
# mientras nada y comprueba que NO sale del agua ni sigue subiendo.
var _espacio: bool = false
var _fase_espacio: int = 0
var _t_espacio: float = 0.0
var _muestras_espacio: int = 0
# Prueba del FILTRO SUBMARINO (tecla X): mete la cámara bajo el agua y comprueba el
# velo azul, la inmersión y las burbujas de cámara y de la cabeza.
var _filtro: bool = false
var _fase_filtro: int = 0
var _t_filtro: float = 0.0
var _muestras_filtro: int = 0
# Prueba de NADO RÁPIDO y COMBATE EN EL AGUA (tecla RETROCESO): mide la velocidad
# de nado normal y con SHIFT, lanza la habilidad 1 nadando y da el golpe cuerpo a
# cuerpo nadando, con maniquíes REALES del proyecto para comprobar el daño.
var _agua2: bool = false
var _fase_agua2: int = 0
var _t_agua2: float = 0.0
var _muestras_agua2: int = 0
var _suma_normal: float = 0.0
var _suma_rapido: float = 0.0
var _n_normal: int = 0
var _n_rapido: int = 0
var _dummy_abil: Node3D
var _en_tierra_agua2: bool = false
var _corriendo_agua2: bool = false
# Prueba del GOLPE cuerpo a cuerpo nadando (tecla INTRO), con el clic inyectado por
# el ejecutor por la acción "atacar".
var _golpe: bool = false
var _fase_golpe: int = 0
var _t_golpe: float = 0.0
var _muestras_golpe: int = 0
var _dummy_golpe: Node3D
var _vida_antes: int = 100

const RUTA_MANIQUI := "res://personaje/transformaciones/acuatica/scenes/training_dummy.gd"


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
	if _vista == 9:
		# Vista dinámica: apunta al SOL de día y a la LUNA de noche, siguiendo la
		# posición real que marca el ciclo (para comprobar discos y colores).
		_vista_astro()
		return
	var v: Dictionary = VISTAS[_vista]
	_camara.fov = v["fov"]
	_camara.global_position = v["pos"]
	_camara.look_at(v["mira"], Vector3.UP)
	_camara.make_current()
	print("[vista] %d: %s  en %s" % [_vista + 1, v["nombre"], v["pos"]])


## Coloca la cámara libre mirando al SOL (de día) o a la LUNA (de noche), leyendo su
## dirección real de las luces del juego. Sirve para comprobar el tamaño de los
## discos, su color y las transiciones del amanecer/atardecer.
func _vista_astro() -> void:
	var sol := find_child("Sol", true, false) as DirectionalLight3D
	if sol == null:
		return
	var d: Vector3 = sol.global_transform.basis.z.normalized()
	var luna := find_child("Luna3D", true, false) as DirectionalLight3D
	var usar := d
	if d.y < 0.0:
		usar = -d                     # de noche, a la luna (que va opuesta al sol)
	var dir := Vector3(usar.x, maxf(usar.y, -0.03), usar.z).normalized()
	_camara.fov = 75.0
	_camara.global_position = Vector3(0.0, 30.0, 30.0)
	_camara.look_at(_camara.global_position + dir * 300.0, Vector3.UP)
	_camara.make_current()
	_camara_juego = true
	print("[vista] mirando %s: dir=%s (altura %.1f°) luz luna=%s" % [
		"al sol" if d.y >= 0.0 else "a la luna", usar, rad_to_deg(asin(clampf(usar.y, -1.0, 1.0))),
		str(luna.light_energy) if luna != null else "-"])


func _process(_delta: float) -> void:
	_cuadros += 1
	if _cuadros == 12:
		_comprobar_terreno()
	if _prueba:
		_procesar_prueba(_delta)
	if _recorrido:
		_procesar_recorrido(_delta)
	if _nado:
		_procesar_nado(_delta)
	if _limite:
		_procesar_limite(_delta)
	if _espacio:
		_procesar_espacio(_delta)
	if _filtro:
		_procesar_filtro(_delta)
	if _agua2:
		_procesar_agua2(_delta)
	if _golpe:
		_procesar_golpe(_delta)
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


## PRUEBA DE NADO (tecla J): deja a la forma ACUÁTICA en la playa, la hace entrar
## andando al mar, comprueba que pasa a nadar y flota, la sumerge con CTRL y
## comprueba que vuelve sola a la superficie. Imprime el estado real cada 0,6 s.
func _iniciar_prueba_nado() -> void:
	var jug := find_child("Jugador", true, false) as CharacterBody3D
	if jug == null:
		print("[nado] no encuentro al jugador")
		return
	var rel := Relieve.new()
	_jugador = jug
	var x := 158.0
	var z := 20.0
	jug.global_position = Vector3(x, rel.altura(x, z) + 1.0, z)
	jug.velocity = Vector3.ZERO
	jug.call("_entrar_acuatico")
	var pivote := jug.get_node_or_null("PivoteCamara") as Node3D
	if pivote != null:
		pivote.rotation.y = -PI / 2.0          # mirando al mar (+X)
		if pivote.has_method("definir_pitch"):
			pivote.call("definir_pitch", -0.12)
	_camara_juego = true
	_camara.current = false
	var cam := find_child("Camara", true, false) as Camera3D
	if cam != null:
		cam.make_current()
	_nado = true
	_fase_nado = 0
	_t_nado = 0.0
	_muestras_nado = 0
	print("[nado] empieza en (%.0f, %.0f): profundidad %.2f m (nivel del mar %.2f)" % [
			x, z, rel.profundidad_agua(x, z), rel.NIVEL_MAR])


func _procesar_nado(delta: float) -> void:
	_t_nado += delta
	var rel := Relieve.new()
	# La cámara de tercera persona del juego gira sola para seguir al personaje, lo
	# que cambiaría la dirección de avance a mitad de la prueba: aquí se fija el
	# rumbo (y se desactiva el look) para que el personaje camine/nade siempre hacia
	# el mar y la prueba mida lo que debe medir.
	var pivote := _jugador.get_node_or_null("PivoteCamara") as Node3D
	if pivote != null:
		pivote.set("permitir_look", false)
		pivote.rotation.y = -PI / 2.0          # mirando al mar (+X)
	match _fase_nado:
		0:                                     # que se asiente sobre el terreno
			if _t_nado > 1.5:
				Input.action_press("mover_adelante")
				_fase_nado = 1
				_t_nado = 0.0
				_muestras_nado = 0
		1:                                     # andar hacia el agua hasta ponerse a nadar
			if _t_nado > 0.4:
				_t_nado = 0.0
				_muestras_nado += 1
				var prof: float = rel.profundidad_agua(_jugador.global_position.x, _jugador.global_position.z)
				_informe_nado(rel, "avanzando")
				if prof > 1.2 or _muestras_nado >= 34:
					_tecla_nado(KEY_CTRL, true)
					_fase_nado = 2
					_t_nado = 0.0
					_muestras_nado = 0
		2:                                     # bucear (seguir avanzando, ahora bajo el agua)
			if _t_nado > 0.5:
				_t_nado = 0.0
				_muestras_nado += 1
				_informe_nado(rel, "buceando")
				if _muestras_nado >= 5:
					_tecla_nado(KEY_CTRL, false)
					Input.action_release("mover_adelante")
					_fase_nado = 3
					_t_nado = 0.0
					_muestras_nado = 0
		3:                                     # soltar: debe volver a flotar a la superficie
			if _t_nado > 0.5:
				_t_nado = 0.0
				_muestras_nado += 1
				_informe_nado(rel, "flotando")
				if _muestras_nado >= 6:
					_nado = false
					print("[nado] fin de la prueba")


## Informe de un instante del nado: posición, profundidad REAL bajo el cuerpo, si
## está nadando, velocidad y el clip que reproduce el modelo acuático.
func _informe_nado(rel: Relieve, etiqueta: String) -> void:
	var p: Vector3 = _jugador.global_position
	var ap := _jugador.get_node_or_null("Acuatico/AnimadorAcuatico") as AnimationPlayer
	var clip := "-"
	if ap != null:
		clip = ap.current_animation
	print("[nado] %-10s pos=(%.1f, %.2f, %.1f)  profundidad=%.2f  nadando=%s  v=(%.1f, %.2f, %.1f)  clip=%s" % [
			etiqueta, p.x, p.y, p.z, rel.profundidad_agua(p.x, p.z), str(_jugador.get("a_nadando")),
			_jugador.velocity.x, _jugador.velocity.y, _jugador.velocity.z, clip])


## Pulsa o suelta una tecla física (CTRL) como haría el jugador.
func _tecla_nado(codigo: Key, pulsada: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = codigo
	ev.physical_keycode = codigo
	ev.pressed = pulsada
	Input.parse_input_event(ev)


## DIAGNÓSTICO DE LA UNIÓN CIUDAD-PLAYA (tecla Z): lanza rayos verticales desde
## dentro de la ciudad hacia el mar en varios sectores de la costa e informa, en
## cada punto, de la altura del terreno (`Relieve`), la altura FÍSICA y el NODO que
## la soporta. Así se ve exactamente qué superficie queda elevada y cuánto.
func _diagnostico_union() -> void:
	var rel := Relieve.new()
	print("[union] terreno natural de la ciudad (COTA_CIUDAD) = %.3f | cota de arena = %.3f" % [
			Relieve.COTA_CIUDAD, Relieve.COTA_ARENA])
	var filas := [
		{"nombre": "lado ESTE  z=30 ", "vertical": true, "fijo": 30.0},
		{"nombre": "lado ESTE  z=90 ", "vertical": true, "fijo": 90.0},
		{"nombre": "lado ESTE  z=-30", "vertical": true, "fijo": -30.0},
		{"nombre": "lado SUR   x=30 ", "vertical": false, "fijo": 30.0},
	]
	for fila: Dictionary in filas:
		var texto := "\n  %s (desde el borde urbano hacia el mar):" % fila["nombre"]
		var d := 0.0
		while d <= 40.0:
			var x: float
			var z: float
			if fila["vertical"]:
				x = 120.0 + d
				z = fila["fijo"]
			else:
				x = fila["fijo"]
				z = 120.0 + d
			var info := _rayo_info(x, z)
			var fis := "SIN SUELO"
			if not info.is_empty():
				fis = "%7.3f [%s]" % [info["y"], info["nodo"]]
			texto += "\n    (%.0f, %.0f)  relieve %7.3f  |  fisica %s" % [
					x, z, rel.altura(x, z), fis]
			d += 5.0
		print("[union]%s" % texto)


## Rayo vertical en (x, z): devuelve la altura del golpe y el nodo que lo soporta,
## o un diccionario vacío si no hay suelo.
func _rayo_info(x: float, z: float) -> Dictionary:
	var mundo := get_world_3d()
	if mundo == null:
		return {}
	var consulta := PhysicsRayQueryParameters3D.create(
			Vector3(x, 300.0, z), Vector3(x, -200.0, z), 1)
	var golpe := mundo.direct_space_state.intersect_ray(consulta)
	if golpe.is_empty():
		return {}
	var col := golpe["collider"] as Node
	var nombre := "?"
	if col != null:
		nombre = col.name
		var p := col.get_parent()
		if p != null:
			nombre = "%s/%s" % [p.name, nombre]
	return {"y": (golpe["position"] as Vector3).y, "nodo": nombre}


## Fija la FASE del ciclo de día y noche (0 = medianoche, 0.25 amanecer, 0.5
## mediodía, 0.75 atardecer) e informa del minuto de juego al que corresponde.
func _fase_ciclo(f: float) -> void:
	var ciclo := find_child("CicloDiaNoche", true, false)
	if ciclo == null:
		print("[fase] no encuentro el ciclo de día y noche")
		return
	ciclo.set("_fase", f)
	print("[fase] puesta a %.3f = minuto %.1f de juego" % [f, _minuto_de_fase(f)])


## Minuto de juego de una fase del ciclo (900 s de día y 900 s de noche).
func _minuto_de_fase(f: float) -> float:
	if f >= 0.25 and f < 0.75:
		return (f - 0.25) * 1800.0
	if f >= 0.75:
		return 900.0 + (f - 0.75) * 1800.0
	return 1350.0 + f * 1800.0


## Estado de las farolas y tabla del factor de encendido por fase (con la MISMA
## función que usa el juego): comprueba a qué minuto empiezan a encenderse, en
## cuál están del todo encendidas y cuándo se apagan al amanecer.
func _informe_farolas() -> void:
	var far := find_child("Farolas", true, false)
	if far != null:
		print("[farolas] %s" % far.call("resumen"))
	var tabla := ""
	for f: float in [0.55, 0.65, 0.68333, 0.70, 0.72, 0.74, 0.749, 0.75, 0.80, 0.99,
			0.0, 0.10, 0.179, 0.20, 0.23, 0.249, 0.30]:
		tabla += "\n    fase %.5f (minuto %5.1f de juego) -> factor %.2f  %s" % [
				f, _minuto_de_fase(f), Farolas.factor_noche(f),
				"ENCENDIDAS" if Farolas.factor_noche(f) > 0.001 else "apagadas"]
	print("[farolas] factor de encendido según la fase:%s" % tabla)


## COMPROBACIÓN DEL ANCLAJE DE LOS ÁRBOLES (tecla A): busca una tarjeta de árbol
## de la ciudad, informa de dónde cae la BASE DE LA FIGURA dibujada y la compara
## con el suelo físico en ese punto, y deja la cámara a pocos metros para verlo.
func _vista_arbol() -> void:
	var gen := find_child("Ciudad", true, false)
	if gen == null:
		print("[arbol] no encuentro la ciudad")
		return
	var elegido := Vector3.ZERO
	var escala := 1.0
	var base_carta := 0.0
	var hallado := false
	for n: Node in gen.find_children("*", "MultiMeshInstance3D", true, false):
		var mmi := n as MultiMeshInstance3D
		if mmi == null or mmi.multimesh == null:
			continue
		var mat := mmi.material_override as StandardMaterial3D
		if mat == null or mat.albedo_texture == null:
			continue
		if mat.albedo_texture.resource_path != Vegetacion.ARBOL_A:
			continue
		var mm := mmi.multimesh
		for i in mini(mm.instance_count, 60):
			var xf := mm.get_instance_transform(i)
			var p := xf.origin
			if absf(p.x) < 120.0 and absf(p.z) < 120.0:
				elegido = p
				escala = xf.basis.get_scale().y
				base_carta = p.y
				hallado = true
				break
		if hallado:
			break
	if not hallado:
		print("[arbol] no encuentro ninguna tarjeta del árbol A en la ciudad")
		return
	var aire := Vegetacion.margenes(Vegetacion.ARBOL_A)
	var base_figura := base_carta + aire.y * escala
	var suelo: Variant = _rayo_suelo(elegido.x, elegido.z)
	print("[arbol] árbol en (%.1f, %.1f): base de la FIGURA %.3f | suelo físico %s | diferencia %s | alto tarjeta %.2f (aire %.2f%%)" % [
		elegido.x, elegido.z, base_figura,
		"sin suelo" if suelo == null else "%.3f" % (suelo as float),
		"-" if suelo == null else "%+.3f m" % (base_figura - (suelo as float)),
		escala, aire.y * 100.0])
	_camara.fov = 60.0
	_camara.global_position = elegido + Vector3(2.6, 1.5, 2.2)
	_camara.look_at(Vector3(elegido.x, elegido.y + 1.4, elegido.z), Vector3.UP)
	_camara.make_current()
	_camara_juego = true
	print("[arbol] cámara a %.1f m del árbol" % _camara.global_position.distance_to(elegido))


## PRUEBA DEL FILTRO SUBMARINO (tecla X): deja a la forma ACUÁTICA en agua HONDA y
## bucea con CTRL hasta que la CÁMARA cruza la superficie. Comprueba la inmersión
## (que sigue la posición real de la cámara), que el velo se ve bajo el agua y no
## fuera, y que las burbujas de la cámara y de la cabeza se encienden sólo dentro.
func _iniciar_prueba_filtro() -> void:
	var jug := find_child("Jugador", true, false) as CharacterBody3D
	if jug == null:
		print("[filtro] no encuentro al jugador")
		return
	var rel := Relieve.new()
	_jugador = jug
	# Agua honda: la cámara necesita sitio para quedar por debajo de la superficie.
	# Se coloca YA en la línea de flotación, con la cámara fuera del agua, que es el
	# estado que hay que comprobar primero.
	var x := 290.0
	var z := 30.0
	jug.global_position = Vector3(x, Relieve.NIVEL_MAR - 1.05, z)
	jug.velocity = Vector3.ZERO
	jug.call("_entrar_acuatico")
	var pivote := jug.get_node_or_null("PivoteCamara") as Node3D
	if pivote != null:
		pivote.rotation.y = -PI / 2.0
		if pivote.has_method("definir_pitch"):
			pivote.call("definir_pitch", -0.12)
	_camara_juego = true
	_camara.current = false
	var cam := find_child("Camara", true, false) as Camera3D
	if cam != null:
		cam.make_current()
	_filtro = true
	_fase_filtro = 0
	_t_filtro = 0.0
	_muestras_filtro = 0
	print("[filtro] arranca en (%.0f, %.0f): profundidad del fondo %.2f m" % [
			x, z, rel.profundidad_agua(x, z)])


func _procesar_filtro(delta: float) -> void:
	_t_filtro += delta
	var pivote := _jugador.get_node_or_null("PivoteCamara") as Node3D
	if pivote != null:
		pivote.set("permitir_look", false)
		pivote.rotation.y = -PI / 2.0
	match _fase_filtro:
		0:                                     # en superficie: el filtro debe estar APAGADO
			if _t_filtro > 2.0:
				_informe_filtro("superficie")
				_fase_filtro = 1
				_t_filtro = 0.0
		1:                                     # bucear con CTRL hasta que la cámara se hunda
			_tecla_nado(KEY_CTRL, true)
			if _t_filtro > 0.6:
				_t_filtro = 0.0
				_muestras_filtro += 1
				_informe_filtro("buceando")
				if _muestras_filtro >= 3:
					_tecla_nado(KEY_CTRL, false)
					_fase_filtro = 2
					_t_filtro = 0.0
					_muestras_filtro = 0
		2:                                     # subir con "saltar": el filtro debe volver a 0
			Input.action_press("saltar")
			if _t_filtro > 0.6:
				_t_filtro = 0.0
				_muestras_filtro += 1
				_informe_filtro("subiendo")
				if _muestras_filtro >= 5:
					Input.action_release("saltar")
					_fase_filtro = 3
					_t_filtro = 0.0
		3:
			if _t_filtro > 0.5:
				_informe_filtro("final")
				# A TIERRA: el pez anda por la playa; las burbujas del personaje
				# deben APAGARSE (ya no está nadando).
				_jugador.global_position = Vector3(150.0, 1.0, 30.0)
				_fase_filtro = 4
				_t_filtro = 0.0
		4:
			if _t_filtro > 1.2:
				_informe_filtro("en tierra")
				_filtro = false
				print("[filtro] fin de la prueba")


func _informe_filtro(etiqueta: String) -> void:
	var cam := find_child("Camara", true, false) as Camera3D
	var y_cam := 0.0
	var depth := 0.0
	if cam != null:
		y_cam = cam.global_position.y
		depth = maxf(Relieve.NIVEL_MAR - y_cam, 0.0)
	var vista := _jugador.get_node_or_null("VistaSubmarina")
	var inmersion := 0.0
	if vista != null:
		inmersion = float(vista.call("inmersion"))
	var velo := false
	var capa := _jugador.get_node_or_null("VistaSubmarina/CapaVistaSubmarina")
	if capa != null:
		var v := capa.get_node_or_null("Velo") as Control
		if v != null:
			velo = v.visible
	var burb_cam := false
	var bc := _jugador.get_node_or_null("VistaSubmarina/BurbujasCamara") as GPUParticles3D
	if bc != null:
		burb_cam = bc.emitting
	var burb_cab := false
	var bk := _jugador.get_node_or_null("BurbujasAcuaticas/BurbujasCabeza") as GPUParticles3D
	if bk != null:
		burb_cab = bk.emitting
	print("[filtro] %-11s cuerpo.y=%6.2f  camara.y=%6.2f  prof.camara=%.2f  inmersion=%.2f  velo=%s  burbCam=%s  burbCabeza=%s" % [
			etiqueta, _jugador.global_position.y, y_cam, depth, inmersion,
			str(velo), str(burb_cam), str(burb_cab)])


## PRUEBA DE ESPACIO AL NADAR (tecla H): deja a la forma ACUÁTICA nadando en agua
## honda y MANTIENE "saltar" pulsado 3 s. Si el bug sigue, el cuerpo sale del agua y
## sigue subiendo (la cota deja de subir con la superficie). Lo correcto es que suba
## hasta la superficie, se quede flotando ahí y NO pase nunca de la línea del agua.
func _iniciar_prueba_espacio() -> void:
	var jug := find_child("Jugador", true, false) as CharacterBody3D
	if jug == null:
		print("[espacio] no encuentro al jugador")
		return
	var rel := Relieve.new()
	_jugador = jug
	# Agua de 2 m: arranca nadando directamente (no hay que vadear antes).
	var x := 225.0
	var z := 30.0
	jug.global_position = Vector3(x, rel.altura(x, z) + 1.5, z)
	jug.velocity = Vector3.ZERO
	jug.call("_entrar_acuatico")
	var pivote := jug.get_node_or_null("PivoteCamara") as Node3D
	if pivote != null:
		pivote.rotation.y = -PI / 2.0
		if pivote.has_method("definir_pitch"):
			pivote.call("definir_pitch", -0.12)
	_camara_juego = true
	_camara.current = false
	var cam := find_child("Camara", true, false) as Camera3D
	if cam != null:
		cam.make_current()
	_espacio = true
	_fase_espacio = 0
	_t_espacio = 0.0
	_muestras_espacio = 0
	print("[espacio] arranca en (%.0f, %.0f): profundidad %.2f m, superficie visible -2.05" % [
			x, z, rel.profundidad_agua(x, z)])


func _procesar_espacio(delta: float) -> void:
	_t_espacio += delta
	var rel := Relieve.new()
	var pivote := _jugador.get_node_or_null("PivoteCamara") as Node3D
	if pivote != null:
		pivote.set("permitir_look", false)
		pivote.rotation.y = -PI / 2.0
	match _fase_espacio:
		0:                                     # que se asiente y empiece a nadar
			if _t_espacio > 1.5:
				_informe_espacio(rel, "reposo")
				_fase_espacio = 1
				_t_espacio = 0.0
				_muestras_espacio = 0
		1:                                     # ESPACIO mantenido 3 s
			Input.action_press("saltar")
			if _t_espacio > 0.5:
				_t_espacio = 0.0
				_muestras_espacio += 1
				_informe_espacio(rel, "ESPACIO pulsado")
				if _muestras_espacio >= 6:
					Input.action_release("saltar")
					_fase_espacio = 2
					_t_espacio = 0.0
					_muestras_espacio = 0
		2:                                     # soltado: vuelve a flotar
			if _t_espacio > 0.5:
				_t_espacio = 0.0
				_muestras_espacio += 1
				_informe_espacio(rel, "soltado")
				if _muestras_espacio >= 6:
					_espacio = false
					print("[espacio] fin de la prueba")


func _informe_espacio(rel: Relieve, etiqueta: String) -> void:
	var p: Vector3 = _jugador.global_position
	print("[espacio] %-16s y=%6.2f  (superficie -2.05)  sobre_agua=%.2f  nadando=%s  v.y=%5.2f  prof=%.2f" % [
			etiqueta, p.y, p.y - (-2.05), str(_jugador.get("a_nadando")),
			_jugador.velocity.y, rel.profundidad_agua(p.x, p.z)])


## PRUEBA DEL LÍMITE DE AGUA (tecla K): pone al VELOCISTA y luego al TANQUE (Fuerza)
## en aguas someras y los empuja hacia el mar. Ninguno de los dos debe ganar
## profundidad: se tienen que frenar en la orilla, con el agua por debajo del límite
## que puede vadear una forma terrestre (0,55 m).
func _iniciar_prueba_limite() -> void:
	var jug := find_child("Jugador", true, false) as CharacterBody3D
	if jug == null:
		return
	var rel := Relieve.new()
	_jugador = jug
	var x := 180.0
	var z := 20.0
	jug.global_position = Vector3(x, rel.altura(x, z) + 0.5, z)
	jug.velocity = Vector3.ZERO
	jug.call("_entrar_velocista")
	# Hay que pasar a la cámara del juego: Terrain3D construye la colisión alrededor
	# de la cámara ACTIVA y, si sigue siendo la libre (que mira desde el cenital), no
	# hay colisión bajo el personaje y se cae al vacío.
	_camara_juego = true
	_camara.current = false
	var cam := find_child("Camara", true, false) as Camera3D
	if cam != null:
		cam.make_current()
	_limite = true
	_fase_limite = 0
	_t_limite = 0.0
	_muestras_limite = 0
	print("[limite] empieza en (%.0f, %.0f): profundidad %.2f m" % [x, z, rel.profundidad_agua(x, z)])


func _procesar_limite(delta: float) -> void:
	_t_limite += delta
	var rel := Relieve.new()
	var pivote := _jugador.get_node_or_null("PivoteCamara") as Node3D
	if pivote != null:
		pivote.set("permitir_look", false)
		pivote.rotation.y = -PI / 2.0          # mirando al mar (+X)
	match _fase_limite:
		0:                                     # asentar y salir corriendo
			if _t_limite > 1.5:
				Input.action_press("mover_adelante")
				_fase_limite = 1
				_t_limite = 0.0
				_muestras_limite = 0
		1:                                     # VELOCISTA hacia el agua
			if _t_limite > 0.5:
				_t_limite = 0.0
				_muestras_limite += 1
				_informe_limite(rel, "velocista")
				if _muestras_limite >= 10:
					Input.action_release("mover_adelante")
					_jugador.call("_entrar_fuerza")
					_fase_limite = 2
					_t_limite = 0.0
					_muestras_limite = 0
		2:                                     # TANQUE hacia el agua
			if _t_limite > 0.5:
				_t_limite = 0.0
				_muestras_limite += 1
				_informe_limite(rel, "tanque")
				if _muestras_limite >= 10:
					Input.action_release("mover_adelante")
					_limite = false
					print("[limite] fin de la prueba")


func _informe_limite(rel: Relieve, etiqueta: String) -> void:
	var p: Vector3 = _jugador.global_position
	print("[limite] %-10s pos=(%.1f, %.2f, %.1f)  profundidad=%.2f m  v=(%.1f, %.2f, %.1f)  forma=%d" % [
			etiqueta, p.x, p.y, p.z, rel.profundidad_agua(p.x, p.z),
			_jugador.velocity.x, _jugador.velocity.y, _jugador.velocity.z, _jugador.get("forma")])


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


## PRUEBA DE NADO RÁPIDO Y COMBATE EN EL AGUA (tecla RETROCESO): pone a la forma
## acuática en mar abierto y (1) mide la velocidad de nado normal y con SHIFT, (2)
## lanza la HABILIDAD 1 nadando y (3) da el GOLPE cuerpo a cuerpo (clic) nadando.
## El daño se comprueba contra maniquíes REALES del proyecto ("damageable"), y al
## final se vuelve a tierra para ver que SHIFT recupera su papel de correr.
func _iniciar_prueba_agua2() -> void:
	var jug := find_child("Jugador", true, false) as CharacterBody3D
	if jug == null:
		print("[agua2] no encuentro al jugador")
		return
	var rel := Relieve.new()
	_jugador = jug
	var x := 290.0
	var z := 30.0
	jug.global_position = Vector3(x, Relieve.NIVEL_MAR - 1.05, z)
	jug.velocity = Vector3.ZERO
	jug.call("_entrar_acuatico")
	var pivote := jug.get_node_or_null("PivoteCamara") as Node3D
	if pivote != null:
		pivote.rotation.y = -PI / 2.0          # mirando a +X: mar abierto
		if pivote.has_method("definir_pitch"):
			pivote.call("definir_pitch", -0.05)
	_camara_juego = true
	_camara.current = false
	var cam := find_child("Camara", true, false) as Camera3D
	if cam != null:
		cam.make_current()
	_dummy_abil = null
	_en_tierra_agua2 = false
	_corriendo_agua2 = false
	_agua2 = true
	_fase_agua2 = 0
	_t_agua2 = 0.0
	_muestras_agua2 = 0
	_suma_normal = 0.0
	_suma_rapido = 0.0
	_n_normal = 0
	_n_rapido = 0
	print("[agua2] arranca en (%.0f, %.0f): profundidad %.2f m" % [x, z, rel.profundidad_agua(x, z)])


## Maniquí de entrenamiento REAL del proyecto, colocado en [param pos].
func _crear_maniqui(pos: Vector3) -> Node3D:
	var m := (load(RUTA_MANIQUI) as GDScript).new() as Node3D
	if m == null:
		return null
	m.name = "ManiquiPrueba"
	add_child(m)
	m.global_position = pos
	return m


## Pulsa la habilidad acuática [param idx] (1..4) por la MISMA puerta que el teclado
## del juego (el 1-4 del controlador), sin pasar por las teclas 1-4 del arnés, que
## son las que cambian de punto de vista.
func _pulsar_habilidad_agua(idx: int) -> void:
	var ev := InputEventKey.new()
	ev.keycode = (KEY_1 + (idx - 1)) as Key
	ev.physical_keycode = (KEY_1 + (idx - 1)) as Key
	ev.pressed = true
	_jugador.call("_unhandled_input", ev)


func _vel_horizontal() -> float:
	return Vector2(_jugador.velocity.x, _jugador.velocity.z).length()


func _vida(n: Node3D) -> int:
	if n == null or not is_instance_valid(n):
		return -1
	return int(round(float(n.get("health"))))


func _procesar_agua2(delta: float) -> void:
	_t_agua2 += delta
	var pivote := _jugador.get_node_or_null("PivoteCamara") as Node3D
	if pivote != null:
		pivote.set("permitir_look", false)
		pivote.rotation.y = -PI / 2.0
	match _fase_agua2:
		0:                                     # asentar sobre la superficie
			if _t_agua2 > 1.5:
				_informe_agua2("reposo")
				Input.action_press("mover_adelante")
				_fase_agua2 = 1
				_t_agua2 = 0.0
				_muestras_agua2 = 0
		1:                                     # nado NORMAL (sin SHIFT)
			if _t_agua2 > 0.25:
				_t_agua2 = 0.0
				_muestras_agua2 += 1
				_suma_normal += _vel_horizontal()
				_n_normal += 1
				if _muestras_agua2 >= 7:
					_tecla_nado(KEY_SHIFT, true)
					_fase_agua2 = 2
					_t_agua2 = 0.0
					_muestras_agua2 = 0
		2:                                     # nado RÁPIDO (SHIFT mantenido)
			_tecla_nado(KEY_SHIFT, true)
			if _t_agua2 > 0.25:
				_t_agua2 = 0.0
				_muestras_agua2 += 1
				_suma_rapido += _vel_horizontal()
				_n_rapido += 1
				_informe_agua2("nado RÁPIDO")
				if _muestras_agua2 >= 7:
					_tecla_nado(KEY_SHIFT, false)
					Input.action_release("mover_adelante")
					var vn := _suma_normal / maxf(float(_n_normal), 1.0)
					var vr := _suma_rapido / maxf(float(_n_rapido), 1.0)
					print("[agua2] velocidades medias: normal %.2f m/s | SHIFT %.2f m/s | factor %.2f" % [
							vn, vr, vr / maxf(vn, 0.01)])
					_fase_agua2 = 3
					_t_agua2 = 0.0
		3:                                     # HABILIDAD 1 nadando (maniquí a 8 m)
			if _t_agua2 > 0.8:
				var p: Vector3 = _jugador.global_position
				_dummy_abil = _crear_maniqui(Vector3(p.x + 8.0, p.y, p.z))
				_pulsar_habilidad_agua(1)
				_informe_agua2("lanza habilidad 1")
				print("[agua2] maniquí de la habilidad a 8 m: vida %d" % _vida(_dummy_abil))
				_fase_agua2 = 4
				_t_agua2 = 0.0
				_muestras_agua2 = 0
		4:                                     # seguimiento del proyectil
			if _t_agua2 > 0.5:
				_t_agua2 = 0.0
				_muestras_agua2 += 1
				_informe_agua2("habilidad 1")
				if _muestras_agua2 >= 4:
					print("[agua2] vida del maniquí tras la habilidad: %d de 100" % _vida(_dummy_abil))
					# El GOLPE cuerpo a cuerpo nadando se comprueba en su propia prueba
					# (tecla INTRO), donde el clic lo inyecta el ejecutor.
					_fase_agua2 = 8
					_t_agua2 = 0.0
					_muestras_agua2 = 0
		8:                                     # SUMERGIRSE con CTRL
			_tecla_nado(KEY_CTRL, true)
			if _t_agua2 > 0.5:
				_t_agua2 = 0.0
				_muestras_agua2 += 1
				_informe_agua2("sumergiéndose")
				if _muestras_agua2 >= 3:
					_tecla_nado(KEY_CTRL, false)
					_fase_agua2 = 9
					_t_agua2 = 0.0
					_muestras_agua2 = 0
		9:                                     # habilidad SUMERGIDO (sin tocar nada más)
			if _muestras_agua2 == 0:
				_muestras_agua2 = 1
				var p: Vector3 = _jugador.global_position
				_dummy_abil = _crear_maniqui(Vector3(p.x + 8.0, p.y, p.z))
				_pulsar_habilidad_agua(1)
				_informe_agua2("lanza SUMERGIDO")
				_t_agua2 = 0.0
			elif _t_agua2 > 0.5:
				_t_agua2 = 0.0
				_muestras_agua2 += 1
				_informe_agua2("habilidad sumergido")
				if _muestras_agua2 >= 6:
					print("[agua2] vida del maniquí tras la habilidad SUMERGIDO: %d de 100" % _vida(_dummy_abil))
					_fase_agua2 = 7
					_t_agua2 = 0.0
		7:                                     # vuelta a tierra: SHIFT = correr otra vez
			if _t_agua2 > 0.2 and not _en_tierra_agua2:
				_en_tierra_agua2 = true
				_jugador.global_position = Vector3(150.0, 1.0, 30.0)
				_jugador.velocity = Vector3.ZERO
				_t_agua2 = 0.0
			elif _en_tierra_agua2 and not _corriendo_agua2 and _t_agua2 > 1.2:
				_corriendo_agua2 = true
				_t_agua2 = 0.0
				Input.action_press("mover_adelante")
				_tecla_nado(KEY_SHIFT, true)
			elif _corriendo_agua2 and _t_agua2 > 1.5:
				_informe_agua2("SHIFT en tierra")
				Input.action_release("mover_adelante")
				_tecla_nado(KEY_SHIFT, false)
				_agua2 = false
				print("[agua2] fin de la prueba")


func _informe_agua2(etiqueta: String) -> void:
	var p: Vector3 = _jugador.global_position
	var ap := _jugador.get_node_or_null("Acuatico/AnimadorAcuatico") as AnimationPlayer
	var clip := "-"
	var escala := 0.0
	if ap != null:
		clip = ap.current_animation
		escala = ap.speed_scale
	print("[agua2] %-16s y=%6.2f nadando=%s ataque=%s habilidad=%s v=(%.2f, %.2f, %.2f) |v|=%.2f clip=%s x%.2f" % [
			etiqueta, p.y, str(_jugador.get("a_nadando")), str(_jugador.get("a_ataque_activo")),
			str(_jugador.get("a_en_habilidad")), _jugador.velocity.x, _jugador.velocity.y,
			_jugador.velocity.z, _vel_horizontal(), clip, escala])


## PRUEBA DEL GOLPE CUERPO A CUERPO NADANDO (tecla INTRO): deja a la forma acuática
## nadando, inmóvil y con la cámara fija, y pone un maniquí REAL a 1,3 m por delante.
## El clic lo inyecta el EJECUTOR por la acción "atacar" (la misma ruta que usa el
## jugador con el ratón): el arnés sólo vigila la vida del maniquí, si el ataque se
## activa y si al terminar el personaje sigue nadando.
func _iniciar_prueba_golpe() -> void:
	var jug := find_child("Jugador", true, false) as CharacterBody3D
	if jug == null:
		print("[golpe] no encuentro al jugador")
		return
	_jugador = jug
	jug.global_position = Vector3(290.0, Relieve.NIVEL_MAR - 1.05, 30.0)
	jug.velocity = Vector3.ZERO
	jug.call("_entrar_acuatico")
	var pivote := jug.get_node_or_null("PivoteCamara") as Node3D
	if pivote != null:
		pivote.rotation.y = -PI / 2.0
		if pivote.has_method("definir_pitch"):
			pivote.call("definir_pitch", -0.05)
	_camara_juego = true
	_camara.current = false
	var cam := find_child("Camara", true, false) as Camera3D
	if cam != null:
		cam.make_current()
	_golpe = true
	_fase_golpe = 0
	_t_golpe = 0.0
	_muestras_golpe = 0
	_dummy_golpe = null
	_vida_antes = 100
	print("[golpe] listo en (%.0f, %.0f); el maniquí se pondrá a 1,3 m por delante" % [
			jug.global_position.x, jug.global_position.z])


func _procesar_golpe(delta: float) -> void:
	_t_golpe += delta
	var pivote := _jugador.get_node_or_null("PivoteCamara") as Node3D
	if pivote != null:
		pivote.set("permitir_look", false)
		pivote.rotation.y = -PI / 2.0
	match _fase_golpe:
		0:                                     # asentar y aparecer el maniquí
			if _t_golpe > 1.6:
				var p: Vector3 = _jugador.global_position
				_dummy_golpe = _crear_maniqui(Vector3(p.x + 1.3, p.y, p.z))
				_vida_antes = _vida(_dummy_golpe)
				_informe_golpe("antes del clic")
				print("[golpe] maniquí a 1,3 m con vida %d; esperando el clic (acción 'atacar')" % _vida_antes)
				_fase_golpe = 1
				_t_golpe = 0.0
				_muestras_golpe = 0
		1:                                     # vigilar el golpe
			if _t_golpe > 0.4:
				_t_golpe = 0.0
				_muestras_golpe += 1
				_informe_golpe("vigilando")
				var ahora := _vida(_dummy_golpe)
				if ahora < _vida_antes:
					print("[golpe] GOLPE REGISTRADO: vida %d -> %d (daño %d)" % [
							_vida_antes, ahora, _vida_antes - ahora])
					_vida_antes = ahora
					_fase_golpe = 2
					_t_golpe = 0.0
					_muestras_golpe = 0
				elif _muestras_golpe >= 22:
					print("[golpe] sin daño tras %.0f s de vigilancia" % (_muestras_golpe * 0.4))
					_fase_golpe = 3
					_t_golpe = 0.0
					_muestras_golpe = 0
		2:                                     # comprobar que vuelve a nadar
			if _t_golpe > 0.6:
				_t_golpe = 0.0
				_muestras_golpe += 1
				_informe_golpe("tras el golpe")
				if _muestras_golpe >= 4:
					_fase_golpe = 3
					_t_golpe = 0.0
		3:
			_informe_golpe("final")
			_golpe = false
			print("[golpe] fin de la prueba")


func _informe_golpe(etiqueta: String) -> void:
	var ap := _jugador.get_node_or_null("Acuatico/AnimadorAcuatico") as AnimationPlayer
	var clip := "-"
	if ap != null:
		clip = ap.current_animation
	print("[golpe] %-16s vida=%3d nadando=%s ataque=%s habilidad=%s clip=%s v=(%.2f, %.2f, %.2f)" % [
			etiqueta, _vida(_dummy_golpe), str(_jugador.get("a_nadando")),
			str(_jugador.get("a_ataque_activo")), str(_jugador.get("a_en_habilidad")), clip,
			_jugador.velocity.x, _jugador.velocity.y, _jugador.velocity.z])


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
			_fase_ciclo(0.95)              # noche cerrada
		elif k == KEY_F:
			_fase_ciclo(0.755)             # justo tras el ocaso: ventana del bug de la luna
		elif k == KEY_E:
			_fase_ciclo(0.746)             # atardecer: el sol toca el horizonte
		elif k == KEY_D:
			_fase_ciclo(0.55)              # pleno día: las farolas deben estar apagadas
		elif k == KEY_G:
			_informe_farolas()
		elif k == KEY_A:
			_vista_arbol()
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
		elif k == KEY_M:
			# Recorrido de la UNIÓN CIUDAD-PLAYA: arranca en la calzada del anillo
			# exterior este (x=126) y va hacia el mar (+X), así cruza en orden
			# calzada -> acera -> borde urbano -> paseo -> pasto -> arena -> agua.
			_iniciar_prueba_recorrido(Vector3(126.0, 0.0, 30.0), -PI / 2.0, "ciudad -> playa")
		elif k == KEY_J:
			_iniciar_prueba_nado()
		elif k == KEY_H:
			_iniciar_prueba_espacio()
		elif k == KEY_X:
			_iniciar_prueba_filtro()
		elif k == KEY_BACKSPACE:
			_iniciar_prueba_agua2()
		elif k == KEY_ENTER:
			_iniciar_prueba_golpe()
		elif k == KEY_Z:
			_diagnostico_union()
		elif k == KEY_B:
			_iniciar_prueba_limite()
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
