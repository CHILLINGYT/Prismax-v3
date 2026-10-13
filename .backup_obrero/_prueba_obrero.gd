extends Node

## PRUEBA EN VIVO DEL NPC OBRERO (carpeta temporal, no forma parte del juego).
## Instancia la escena REAL del juego (ziba_prototipo.tscn) dentro de este envoltorio
## y comprueba, sobre la partida en curso:
##   A) el NPC existe; B) está dentro de una plaza y no de un edificio; C) aspecto
##   (capturas en color); D) no se mueve; E) la flecha amarilla; F) los pies apoyados;
##   G) los peatones siguen ahí; H) sobrevive a una regeneración de la ciudad;
##   I) el resto (FPS, cámara del jugador, HUD).
## Guarda capturas en res://.backup_obrero/capturas/.

const SALIDA := "res://.backup_obrero/capturas"
const LOG := "res://.backup_obrero/log_prueba.txt"
const ESPERA_CIUDAD := 40.0
const LIMITE := 150.0             # autolímite duro: la prueba SIEMPRE termina
const ALTO_INFORME := 1.05        # altura a la que se apunta al obrero
const LADO_MIN := 2.1             # corredor libre de árboles del generador

var _t := 0.0
var _fase := 0
var _fase_ant := -1
var _frames := 0
var _t_marca := 0.0
var _juego: Node = null
var _obrero: Node3D = null
var _camara: Camera3D = null
var _pos0 := Vector3.ZERO
var _plaza0: Node3D = null
var _peatones0 := 0
var _fps: Array = []
var _fallos := 0
var _hud: CanvasLayer = null
var _archivo: FileAccess = null

func _log(txt: String) -> void:
	print(txt)
	if _archivo != null:
		_archivo.store_line("[%6.2f] %s" % [_t, txt])
		_archivo.flush()

func _ready() -> void:
	_archivo = FileAccess.open(LOG, FileAccess.WRITE)
	_log("prueba iniciada")
	_juego = get_parent().get_node_or_null("Juego")
	if _juego == null:
		_log("FALLO: no se encontró el juego")
		get_tree().quit()
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SALIDA))
	# Autolímite: pase lo que pase, la prueba termina y devuelve el control.
	var reloj := Timer.new()
	reloj.wait_time = LIMITE
	reloj.one_shot = true
	reloj.timeout.connect(func() -> void:
		_log("TIEMPO AGOTADO (fase %d)" % _fase)
		get_tree().quit())
	add_child(reloj)
	reloj.start()
	_camara = Camera3D.new()
	_camara.name = "CamaraPrueba"
	_camara.fov = 62.0
	_camara.near = 0.05
	_camara.far = 4000.0
	_juego.add_child(_camara)
	_hud = _juego.get_node_or_null("Jugador/HUD") as CanvasLayer
	_log("juego instanciado; HUD encontrado: %s" % str(_hud != null))

func _process(delta: float) -> void:
	_t += delta
	_frames += 1
	if _t > 2.0:
		_fps.append(Engine.get_frames_per_second())
	if _obrero == null or not is_instance_valid(_obrero):
		_obrero = _juego.get_node_or_null("NPC_Estatico_Obrero") as Node3D
		if _obrero == null:
			return
	match _fase:
		0: _fase_espera()
		1: _fase_captura("plaza_aerea", _vista_aerea)
		2: _fase_captura("obrero_lejos", func() -> Transform3D: return _vista_obrero(5.5))
		3: _fase_captura("obrero_cerca", func() -> Transform3D: return _vista_obrero(2.4))
		4: _fase_estabilidad()
		5: _fase_regen_espera()
		6: _fase_captura("plaza_aerea_regen", _vista_aerea)
		7: _fase_captura("obrero_de_frente", func() -> Transform3D: return _vista_frente(2.6))
		8: _informe_final()
	if _fase != _fase_ant:
		_fase_ant = _fase
		_log("--- fase %d ---" % _fase)

# ---------------------------------------------------------------- fases
func _fase_espera() -> void:
	var plazas := _plazas()
	if plazas.is_empty():
		if _t > ESPERA_CIUDAD:
			_log("FALLO: la ciudad no generó plazas en %.0f s" % ESPERA_CIUDAD)
			_informe_final()
		return
	if _obrero.get("_plaza") == null:
		if fmod(_t, 5.0) < 0.05:
			_log("esperando a que el obrero se plante (plazas %d, _plaza %s)..." % [
					plazas.size(), str(_obrero.get("_plaza"))])
		return
	_log("\n========== PRUEBA A/B: NPC Y PLAZA ==========")
	_log("plazas encontradas: %d" % plazas.size())
	for p in plazas:
		var caja := _caja_de_plaza(p as Node3D)
		_log("   %-10s centro (%.2f, %.2f) | tamaño %.1f x %.1f | y=%.3f" % [
				String(p.name), (p as Node3D).global_position.x, (p as Node3D).global_position.z,
				caja.x, caja.y, (p as Node3D).global_position.y])
	_informe_obrero(plazas)
	_poner_camara(_vista_aerea())
	_fase = 1
	_frames = 0

func _fase_captura(nombre: String, vista: Callable) -> void:
	if _frames < 6:
		return
	_poner_camara((vista as Callable).call() as Transform3D)
	if _frames < 12:
		return
	_guardar(nombre)
	_frames = 0
	_fase += 1

func _fase_estabilidad() -> void:
	if _t_marca == 0.0:
		_t_marca = _t
		_pos0 = _obrero.global_position
		_plaza0 = _obrero.get("_plaza") as Node3D
		_peatones0 = _contar_peatones()
		print("\n========== PRUEBA D: MOVIMIENTO Y ESTABILIDAD ==========")
		_log("posición de partida: %s | plaza %s | peatones %d" % [
				str(_pos0), String(_plaza0.name), _peatones0])
		return
	if _t - _t_marca < 8.0:
		return
	var movio := _obrero.global_position.distance_to(_pos0)
	var plaza_ahora := _obrero.get("_plaza") as Node3D
	_log("tras %.1f s: posición %s | desplazamiento %.6f m | misma plaza: %s" % [
			_t - _t_marca, str(_obrero.global_position), movio,
			str(is_instance_valid(plaza_ahora) and plaza_ahora == _plaza0)])
	_log("¿tiene IA/navegación/movimiento? NavigationAgent3D: %s | CharacterBody3D: %s | _physics_process: %s" % [
			str(_obrero.find_child("NavigationAgent3D", true, false) != null),
			str(_obrero is CharacterBody3D),
			str((_obrero.get_script() as Script).has_method("_physics_process"))])
	if movio > 0.0001:
		_fallos += 1
	# Regeneración de la ciudad (misma llamada que hace el arranque).
	_log("\n========== PRUEBA H: REGENERACIÓN ==========")
	_log("peatones antes: %d | se regenera la ciudad..." % _peatones0)
	var ciudad := _juego.get_node_or_null("Ciudad")
	if ciudad == null or not ciudad.has_method("generar_ciudad"):
		print("FALLO: no se pudo regenerar (sin nodo Ciudad)")
		_fallos += 1
		_fase = 7
		return
	_pos0 = _obrero.global_position
	ciudad.call("generar_ciudad")
	_fase = 5
	_frames = 0
	_t_marca = _t

func _fase_regen_espera() -> void:
	if _frames < 30:
		return
	var plazas := _plazas()
	if plazas.is_empty():
		return
	var plaza_ahora := _obrero.get("_plaza") as Node3D
	print("plazas nuevas: %d | obrero en %s | posición %s | se movió %.2f m" % [
			plazas.size(), String(plaza_ahora.name) if plaza_ahora != null else "—",
			str(_obrero.global_position), _obrero.global_position.distance_to(_pos0)])
	print("peatones después: %d (antes %d) | vivo: %s" % [
			_contar_peatones(), _peatones0, str(_contar_peatones() > 0)])
	var nueva := _plaza_que_lo_contiene(plazas)
	print("sigue dentro de una plaza: %s | NPC válido: %s" % [
			String(nueva.name) if nueva != null else "NO", str(is_instance_valid(_obrero))])
	if nueva == null:
		_fallos += 1
	_poner_camara(_vista_aerea())
	_fase = 6
	_frames = 0

func _informe_final() -> void:
	_log("\n========== PRUEBA E/F: FLECHA Y APOYO ==========")
	var punta := _obrero.get_node_or_null("IndicadorAmarillo/Flecha/Punta") as MeshInstance3D
	var vastago := _obrero.get_node_or_null("IndicadorAmarillo/Flecha/Vastago") as MeshInstance3D
	var modelo := _obrero.get_node_or_null("Model") as Node3D
	var y_min := 1e9
	var y_max := -1e9
	if modelo != null:
		for n in modelo.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			if mi == null or mi.mesh == null:
				continue
			var a := _extremos(mi)
			y_min = minf(y_min, a.x)
			y_max = maxf(y_max, a.y)
		_log("modelo: pies y=%.3f | coronilla y=%.3f | alto %.3f | cajas medidas %d" % [
				y_min, y_max, y_max - y_min,
				modelo.find_children("*", "MeshInstance3D", true, false).size()])
		_log("apoyo: y del NPC = %.3f m | pies del modelo respecto al suelo = %+.4f m" % [
				_obrero.global_position.y, y_min - _obrero.global_position.y])
	if punta == null or vastago == null:
		_log("FALLO: falta la flecha")
		_fallos += 1
	else:
		var ap_p := _extremos(punta)
		var ap_v := _extremos(vastago)
		_log("flecha: punta y[%.3f .. %.3f] | vastago y[%.3f .. %.3f] | alto total %.3f m | ancho de la punta %.2f m" % [
				ap_p.x, ap_p.y, ap_v.x, ap_v.y, ap_v.y - ap_p.x,
				(punta.mesh as CylinderMesh).top_radius * 2.0 if punta.mesh is CylinderMesh else -1.0])
		var mate := punta.material_override as StandardMaterial3D
		if mate != null:
			_log("material: shading_mode %d (UNSHADED=%d) | color %s" % [
					mate.shading_mode, BaseMaterial3D.SHADING_MODE_UNSHADED, str(mate.albedo_color)])
		if y_max > -1e8:
			_log("separación punta de flecha -> coronilla: %.3f m" % (ap_p.x - y_max))
	_log("\n========== PRUEBA G/I: PEATONES Y RESTO ==========")
	_log("peatones en el árbol: %d | director de peatones: %s" % [
			_contar_peatones(), str(_juego.find_child("DirectorPeatones*", true, false) != null)])
	var fps_min := 999.0
	var fps_suma := 0.0
	for f in _fps:
		fps_min = minf(fps_min, float(f))
		fps_suma += float(f)
	_log("FPS: medio %.0f | mínimo %.0f (muestras %d)" % [
			fps_suma / maxf(1.0, float(_fps.size())), fps_min, _fps.size()])
	_log("HUD intacto: %s | cámara del viewport: %s | jugador presente: %s" % [
			str(_hud != null and is_instance_valid(_hud)),
			str(get_viewport().get_camera_3d() != null),
			str(_juego.get_node_or_null("Jugador") != null)])
	_log("\n========== RESULTADO ==========")
	_log("fallos detectados: %d %s" % [_fallos, "OK" if _fallos == 0 else "!! REVISAR"])
	get_tree().quit()

# ---------------------------------------------------------------- utilidades
func _plazas() -> Array:
	var cont := _juego.find_child("CiudadGenerada", true, false)
	if cont == null:
		return []
	return cont.find_children("Parque_*", "StaticBody3D", true, false)

func _caja_de_plaza(p: Node3D) -> Vector2:
	var mallas := p.find_children("*", "MeshInstance3D", true, false)
	if not mallas.is_empty():
		var malla := mallas[0] as MeshInstance3D
		if malla != null and malla.mesh is BoxMesh:
			var t := (malla.mesh as BoxMesh).size
			return Vector2(t.x, t.z)
	return Vector2.ZERO

func _plaza_que_lo_contiene(plazas: Array) -> Node3D:
	var pos := _obrero.global_position
	for p in plazas:
		var centro := (p as Node3D).global_position
		var caja := _caja_de_plaza(p as Node3D)
		if absf(pos.x - centro.x) <= caja.x * 0.5 and absf(pos.z - centro.z) <= caja.y * 0.5:
			return p as Node3D
	return null

func _informe_obrero(plazas: Array) -> void:
	print("\n========== PRUEBA B: ¿DENTRO DE UNA PLAZA? ==========")
	var plaza := _plaza_que_lo_contiene(plazas)
	var pos := _obrero.global_position
	_log("posición del obrero: (%.3f, %.3f, %.3f) | giro %.1f grados" % [
			pos.x, pos.y, pos.z, rad_to_deg(_obrero.rotation.y)])
	if plaza == null:
		_log("FALLO: no está dentro de ninguna plaza")
		_fallos += 1
		return
	var centro := plaza.global_position
	var caja := _caja_de_plaza(plaza)
	_log("plaza: %s | centro (%.2f, %.2f) | tamaño %.1f x %.1f" % [
			String(plaza.name), centro.x, centro.z, caja.x, caja.y])
	_log("desde el centro: dx %.2f | dz %.2f | distancia %.2f m (media manzana %.1f)" % [
			pos.x - centro.x, pos.z - centro.z,
			Vector2(pos.x - centro.x, pos.z - centro.z).length(), caja.x * 0.5])
	_log("desviación del eje de la senda este-oeste: %.2f m (senda de 3 m -> ±1.5; corredor libre %.1f)" % [
			absf(pos.z - centro.z), LADO_MIN])
	# Colisionadores a menos de 1.6 m (independiente del radio que exige la colocación).
	var forma := SphereShape3D.new()
	forma.radius = 1.6
	var consulta := PhysicsShapeQueryParameters3D.new()
	consulta.shape = forma
	consulta.collision_mask = 1
	consulta.collide_with_areas = false
	consulta.transform = Transform3D(Basis(), pos + Vector3.UP * 1.8)
	var golpes := _obrero.get_world_3d().direct_space_state.intersect_shape(consulta, 12)
	var nombres: Array = []
	for g in golpes:
		var o: Variant = g.get("collider")
		if o is Node:
			nombres.append(String((o as Node).name))
	_log("colisionadores a menos de 1.6 m (cuerpo, sin suelo): %d %s" % [golpes.size(), str(nombres)])
	# Comprobación de que no está sobre un banco, árbol, arbusto ni bolardo cercano.
	var cerca := []
	for n in _juego.find_children("*", "Node3D", true, false):
		var s := String(n.name)
		if not (s.begins_with("BancoParque_") or s.begins_with("Farol") or s.begins_with("Boldo")):
			continue
		if n is Node3D and (n as Node3D).global_position.distance_to(pos) < 1.6:
			cerca.append("%s a %.2f m" % [s, (n as Node3D).global_position.distance_to(pos)])
	print("objetos a menos de 1.6 m: %s" % ("ninguno" if cerca.is_empty() else str(cerca)))

func _contar_peatones() -> int:
	var cont := _juego.find_child("CiudadGenerada", true, false)
	if cont == null:
		return 0
	var pe := cont.find_child("Peatones", true, false)
	if pe == null:
		return 0
	return pe.get_child_count()

func _extremos(mi: MeshInstance3D) -> Vector2:
	var a := mi.mesh.get_aabb()
	var t := mi.global_transform
	var y0 := t.origin.y + a.position.y
	var y1 := t.origin.y + a.end.y
	return Vector2(minf(y0, y1), maxf(y0, y1))

func _vista_aerea() -> Transform3D:
	var plaza := _plaza_que_lo_contiene(_plazas())
	var centro := plaza.global_position if plaza != null else _obrero.global_position
	var caja := _caja_de_plaza(plaza) if plaza != null else Vector2(24.0, 24.0)
	var pos := centro + Vector3(0.0, maxf(26.0, caja.x * 1.3), maxf(22.0, caja.x * 1.1))
	var t := Transform3D()
	t.origin = pos
	t = t.looking_at(centro + Vector3(0.0, 1.0, 0.0), Vector3.UP)
	return t

func _vista_obrero(dist: float) -> Transform3D:
	var pos := _obrero.global_position
	var adelante := -_obrero.global_transform.basis.z
	var cam := pos + adelante * dist + Vector3.UP * 1.65
	var t := Transform3D()
	t.origin = cam
	return t.looking_at(pos + Vector3.UP * ALTO_INFORME, Vector3.UP)

## Cámara situada en el lado hacia el que el obrero DEBE mirar (el cruce de la plaza):
## si la orientación es correcta, se le ve la cara.
func _vista_frente(dist: float) -> Transform3D:
	var pos := _obrero.global_position
	var hacia := Vector3.FORWARD
	var plaza := _plaza_que_lo_contiene(_plazas())
	if plaza != null:
		var d := plaza.global_position - pos
		d.y = 0.0
		if d.length_squared() > 0.0001:
			hacia = d.normalized()
	var t := Transform3D()
	t.origin = pos + hacia * dist + Vector3.UP * 1.65
	return t.looking_at(pos + Vector3.UP * ALTO_INFORME, Vector3.UP)

func _poner_camara(t: Transform3D) -> void:
	_camara.global_transform = t
	_camara.make_current()

func _guardar(nombre: String) -> void:
	_log("   capturando %s..." % nombre)
	var img := get_viewport().get_texture().get_image()
	_log("   imagen leída %dx%d" % [img.get_width(), img.get_height()])
	var ruta := "%s/%s.png" % [SALIDA, nombre]
	var err := img.save_png(ruta)
	_log("   captura %s -> %s (%s) | cámara de prueba activa: %s" % [
			nombre, ruta, error_string(err),
			str(get_viewport().get_camera_3d() == _camara)])