extends Node3D

## =============================================================================
##  SONDA de la TRANSICIÓN CIUDAD -> PLAYA
## =============================================================================
##  Genera la CIUDAD REAL (el mismo generador del juego) y luego:
##   1. Busca el BORDE urbano (la caja del suelo) y la frontera con la arena.
##   2. LISTA la geometría que hay en esa franja: nombre, contenedor, sitio,
##      tamaño de malla y color del material. Con eso se identifica QUÉ piezas son
##      los "bloques" que se ven raros (no se adivina).
##   3. Guarda CAPTURAS para mirarlo (necesita ventana: save_png no funciona en
##      headless, que no emite frame_post_draw).
##
##  No forma parte del juego: vive en res://_tests/.
## =============================================================================

const CIUDAD := preload("res://generador_ciudad.gd")
const RUTA_CAPTURAS := "res://_tests/capturas_playa/"

var _gen: GeneradorCiudad3D
var _lineas: Array[String] = []

func _ready() -> void:
	call_deferred("_correr")

func _m(t: String) -> void:
	_lineas.append(t)
	print("[SONDA] ", t)

func _listo() -> void:
	var f := FileAccess.open("res://_tests/sonda_playa.txt", FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lineas))
		f.close()

func _esperar(n: int) -> void:
	for _i in n:
		await get_tree().process_frame

func _correr() -> void:
	var luz := DirectionalLight3D.new()
	luz.rotation_degrees = Vector3(-52.0, -38.0, 0.0)
	luz.light_energy = 1.1
	add_child(luz)
	var entorno := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = Sky.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.6
	entorno.environment = env
	add_child(entorno)

	_gen = CIUDAD.new()
	_gen.generar_al_iniciar = false
	add_child(_gen)
	await get_tree().process_frame
	_m("generando la ciudad…")
	_gen.generar_ciudad()
	await _esperar(90)

	var raiz := _gen.get_node_or_null("CiudadGenerada")
	if raiz == null:
		_m("NO se encontró CiudadGenerada")
		_listo()
		get_tree().quit(1)
		return
	# --- Borde urbano: la pieza del suelo ("Terreno") marca la extensión real ---
	var nodo_terreno := raiz.find_child("Terreno", true, false)
	var malla_terreno: MeshInstance3D = null
	if nodo_terreno is MeshInstance3D:
		malla_terreno = nodo_terreno as MeshInstance3D
	elif nodo_terreno != null:
		malla_terreno = nodo_terreno.find_child("*", false, false) as MeshInstance3D
	var caja_terreno := AABB()
	if malla_terreno != null and malla_terreno.mesh != null:
		var tam_terreno := malla_terreno.mesh.get_aabb().size
		caja_terreno = AABB(malla_terreno.global_position - tam_terreno * 0.5, tam_terreno)
	var borde_x := caja_terreno.end.x
	var borde_z := caja_terreno.end.z
	_m("borde urbano: x=%.1f  z=%.1f  (terreno %s)" % [borde_x, borde_z, str(caja_terreno)])

	# --- Relieve real: dónde empieza la arena (cota por debajo de COTA_ARENA) ---
	var rel := Relieve.new()
	var frontera_x := -1.0
	for d in range(0, 120):
		var p := Vector2(borde_x + float(d), 0.0)
		if rel.altura(p.x, p.y) < Relieve.COTA_ARENA:
			frontera_x = float(d)
			break
	_m("arena a %.0f m del borde en +X (cota arena=%.2f)" % [frontera_x, Relieve.COTA_ARENA])

	# --- Geometría en la franja del borde +X (banda de 70 m hacia dentro) ---
	var banda := 70.0
	var cuenta := {}
	var claros: Array[String] = []
	for cont: String in ["Suelo", "Aceras", "Calles", "MarcasViales", "Props", "Vegetacion", "Edificios"]:
		var nodo := raiz.get_node_or_null(cont)
		if nodo == null:
			continue
		for mi in nodo.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			if m.mesh == null or m.global_position.x < borde_x - banda:
				continue
			var tam := m.mesh.get_aabb().size
			cuenta[cont] = int(cuenta.get(cont, 0)) + 1
			var c := _color_de(m)
			var lum := c.get_luminance()
			if lum >= 0.35 and tam.y > 0.05:
				claros.append("%s | %s | pos=(%.1f, %.2f, %.1f) | tam=(%.2f, %.2f, %.2f) | albedo=%.2f %.2f %.2f (lum %.2f)" % [
						cont, String(m.name), m.global_position.x, m.global_position.y,
						m.global_position.z, tam.x, tam.y, tam.z, c.r, c.g, c.b, lum])
	_m("piezas por contenedor en la banda del borde +X: %s" % str(cuenta))
	_m("piezas CLARAS (lum >= 0.35) y con volumen en esa banda: %d" % claros.size())
	claros.sort()
	for i in mini(claros.size(), 40):
		_m("  CLARA %s" % claros[i])

	# --- Terreno de ARENA construido desde el relieve REAL ----------------
	# La sonda no carga la escena del mundo porque un script ajeno
	# (`Enemigos Prueba/Scripts/proyectil_enemigo.gd`) tiene un error de sintaxis
	# PREVIO que impide cargarla. Con el relieve real (el mismo que usa el terreno
	# del juego) se ve igual de bien si la ciudad pisa la arena, si hay bloques
	# flotando o si algo sobresale.
	_terreno(rel, borde_x)

	# --- Capturas ---
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(RUTA_CAPTURAS))
	await _capturar(Vector3(borde_x + 26.0, 16.0, 0.0), Vector3(borde_x - 12.0, 0.5, 0.0),
			"01_borde_este.png")
	await _capturar(Vector3(borde_x + 8.0, 3.2, 0.0), Vector3(borde_x + 30.0, 0.2, 0.0),
			"02_desde_la_ciudad.png")
	await _capturar(Vector3(borde_x + 60.0, 55.0, 60.0), Vector3(borde_x - 6.0, 0.0, 0.0),
			"03_cenital_borde.png")
	_listo()
	get_tree().quit(0)

## Color de la primera superficie de la malla (albedo del material de la pieza).
func _color_de(m: MeshInstance3D) -> Color:
	var mat: Material = m.material_override
	if mat == null and m.mesh.get_surface_count() > 0:
		mat = m.mesh.surface_get_material(0)
	if mat is StandardMaterial3D:
		return (mat as StandardMaterial3D).albedo_color
	return Color(0.5, 0.5, 0.5)

func _capturar(pos: Vector3, mira: Vector3, archivo: String) -> void:
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 70.0
	cam.global_position = pos
	cam.look_at(mira, Vector3.UP)
	cam.current = true
	await _esperar(3)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img != null:
		img.save_png(RUTA_CAPTURAS + archivo)
		_m("captura: %s" % (RUTA_CAPTURAS + archivo))
	cam.queue_free()

func _terreno(rel: Relieve, borde_x: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var paso := 4.0
	var x_ini := borde_x - 60.0
	var x_fin := borde_x + 70.0
	var z_ini := -70.0
	var z_fin := 70.0
	var nx := int((x_fin - x_ini) / paso)
	var nz := int((z_fin - z_ini) / paso)
	for i in nx:
		for j in nz:
			var a := Vector3(x_ini + i * paso, 0.0, z_ini + j * paso)
			var b := Vector3(a.x + paso, 0.0, a.z)
			var c := Vector3(a.x + paso, 0.0, a.z + paso)
			var d := Vector3(a.x, 0.0, a.z + paso)
			a.y = rel.altura(a.x, a.z)
			b.y = rel.altura(b.x, b.z)
			c.y = rel.altura(c.x, c.z)
			d.y = rel.altura(d.x, d.z)
			st.add_vertex(a)
			st.add_vertex(b)
			st.add_vertex(c)
			st.add_vertex(a)
			st.add_vertex(c)
			st.add_vertex(d)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "Arena_sonda"
	mi.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.84, 0.78, 0.63)
	mat.roughness = 1.0
	mi.material_override = mat
	add_child(mi)
	_m("arena construida del relieve real: x %.0f..%.0f  z %.0f..%.0f" % [x_ini, x_fin, z_ini, z_fin])