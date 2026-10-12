class_name Minimapa
extends Control

## MINIMAPA DINÁMICO (cámara 3D cenital del terreno REAL).
##
## Una Camera3D ORTOGRÁFICA mira verticalmente hacia abajo y renderiza el mundo
## real del juego dentro de un SubViewport, mostrado en el HUD (esquina superior
## izquierda). Una flecha central indica la dirección HORIZONTAL de la mirada de
## la cámara principal.
##
## CLAVES DE DISEÑO (para no romper ni costar de más):
##  · NO duplica el mundo: el SubViewport comparte el World3D del juego
##    (`own_world_3d = false`), así que muestra la MISMA ciudad/terreno de la
##    partida actual. No se instancia nada nuevo.
##  · Excluye a los actores SIN tocar colisiones: `cull_mask = capa 1` y los
##    actores (jugador, Vuelo, barco, enemigos, proyectiles, efectos) se mueven a
##    la CAPA VISUAL 2. La cámara principal conserva su cull_mask por defecto, de
##    modo que su aspecto NO cambia.
##  · Coste bajo: SubViewport de baja resolución, sin MSAA/AA/TAA, y render a
##    demanda (`UPDATE_ONCE`) a la frecuencia configurable. No hay búsquedas de
##    nodos ni bucles pesados por fotograma: se guardan las referencias.
##  · Sigue al jugador y, en la transformación VUELO, al nodo `Vuelo`.
##  · Respeta la pausa y el grupo `hud_juego` (ocultar interfaz).

## Capa visual que ve la cámara del minimapa (el escenario estático).
const LAYER_MUNDO := 1
## Capa visual a la que se mueven las entidades móviles (excluidas del minimapa).
const LAYER_DINAMICO := 2
## Hijos DIRECTOS del mundo que son escenario estático (se quedan en el minimapa).
const ESTATICOS := [&"Terreno", &"Ciudad", &"Oceano", &"Bosque", &"Farolas", &"Muelle"]
## Nombres de contenedores de entidades MÓVILES (se excluyen del minimapa). Basta
## con que aparezca en el árbol de ancestros del nodo (a cualquier profundidad).
const DINAMICOS := [&"Jugador", &"Barco", &"EnemigosPrueba", &"Peatones"]

@export var activo: bool = true

@export_group("Tamaño en pantalla")
## Lado del minimapa en píxeles (dentro del HUD), en su MODO NORMAL.
@export var tamano_px: int = 170
## Separación de la esquina superior izquierda.
@export var margen_px: int = 16
## Radio de las esquinas (fracción del lado). La imagen y el marco lo comparten.
@export_range(0.0, 0.4, 0.01) var radio_esquina: float = 0.10
## Color del borde/marco (gris muy oscuro: negro suave, no puro).
@export var borde_color: Color = Color(0.19, 0.19, 0.20, 1.0)

@export_group("Renderizado")
## Resolución INTERNA del SubViewport en modo normal (independiente del tamaño
## en pantalla).
@export_range(64, 512, 8) var resolucion: int = 256
## Metros de terreno que abarca el lado del cuadrado visible (escala del mapa).
@export var metros_visibles: float = 140.0
## Altura de la cámara sobre el objetivo (no cambia la escala en ortográfica).
@export var altura: float = 220.0
## Frecuencia de refresco del mapa en Hz (0 = cada fotograma).
@export_range(0.0, 60.0, 1.0) var fps_actualizacion: float = 20.0

@export_group("Modo ampliado (tecla M)")
## Fracción del lado menor de la pantalla que ocupa el mapa ampliado.
@export_range(0.3, 0.95, 0.01) var factor_ampliado: float = 0.72
## Metros que abarca el mapa ampliado (debe cubrir la isla COMPLETA). La isla
## tiene radio de costa medio ~410 m con un 12 % de asimetría (ver Relieve):
## ~1000 m de lado la engloba con margen.
@export var metros_isla: float = 1000.0
## Resolución INTERNA del SubViewport en modo ampliado (moderada y configurable).
@export_range(128, 1024, 16) var resolucion_ampliada: int = 512

@export_group("Flecha")
## Relleno de la flecha (blanco) y su contorno (negro), para que se distinga
## sobre terrenos claros y oscuros.
@export var flecha_color: Color = Color(1, 1, 1, 1)
@export var flecha_borde_color: Color = Color(0, 0, 0, 1)

var _jugador: Node3D
var _mundo: Node
var _vuelo: Node3D
var _pivote_leo: Node3D
var _pivote_vuelo: Node3D
var _cam: Camera3D
var _sub: SubViewport
var _flecha: Node2D
var _vista: TextureRect
var _marco: Panel
var _mat_redondeo: ShaderMaterial
var _flecha_base: float = 170.0
var _acum: float = 0.0
var _pausado: bool = false
var _ampliado: bool = false


func _ready() -> void:
	# Corre también en pausa para poder congelar el render (barato).
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2(float(margen_px), float(margen_px))
	size = Vector2(float(tamano_px), float(tamano_px))

	if not activo:
		visible = false
		set_process(false)
		return

	_jugador = _buscar_jugador()
	if _jugador == null:
		push_warning("[Minimapa] No se encontró el ControladorLeo: minimapa desactivado.")
		set_process(false)
		return
	_mundo = _jugador.get_parent()
	_vuelo = _jugador.get_node_or_null("Vuelo")
	_pivote_leo = _jugador.get_node_or_null("PivoteCamara")
	_pivote_vuelo = _vuelo.get_node_or_null("CameraPivot") if _vuelo != null else null

	_construir_vista()
	_excluir_dinamicos_inicial()
	# Las entidades que aparezcan DESPUÉS (enemigos, proyectiles, restos de
	# ciudad ya estáticos...) se clasifican al añadirse: sólo se añade capa a los
	# nodos MÓVILES; el escenario estático no se toca.
	get_tree().node_added.connect(_on_node_added)

	get_viewport().size_changed.connect(_on_viewport_resized)
	_aplicar_layout()
	_actualizar_seguimiento()
	_sub.render_target_update_mode = SubViewport.UPDATE_ONCE


# =============================================================== Construcción
func _construir_vista() -> void:
	# 1) SubViewport que COMPARTE el mundo del juego.
	_sub = SubViewport.new()
	_sub.name = "MinimapaViewport"
	_sub.size = Vector2i(resolucion, resolucion)
	_sub.own_world_3d = false
	_sub.transparent_bg = false
	_sub.disable_3d = false
	_sub.msaa_3d = Viewport.MSAA_DISABLED
	_sub.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	_sub.use_taa = false
	_sub.use_debanding = false
	_sub.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_sub)

	# 2) Cámara cenital ortográfica.
	_cam = Camera3D.new()
	_cam.name = "CamaraMinimapa"
	_cam.top_level = true   # su transformación no depende del jugador (es global)
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = metros_visibles
	_cam.keep_aspect = Camera3D.KEEP_HEIGHT
	_cam.near = 1.0
	_cam.far = altura + 500.0
	_cam.cull_mask = LAYER_MUNDO
	_cam.rotation = Vector3(-PI * 0.5, 0.0, 0.0)  # mira verticalmente hacia abajo, norte arriba
	_cam.current = true
	_sub.add_child(_cam)

	# 3) Imagen (textura del SubViewport) recortada con las MISMAS esquinas
	# redondeadas que el marco, mediante un shader local barato (no por fotograma).
	_vista = TextureRect.new()
	_vista.name = "Vista"
	_vista.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vista.texture = _sub.get_texture()
	_vista.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_vista.stretch_mode = TextureRect.STRETCH_SCALE
	_vista.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_vista.clip_contents = true
	_mat_redondeo = ShaderMaterial.new()
	_mat_redondeo.shader = load("res://personaje/hud_transformacion/shaders/minimapa_redondeado.gdshader")
	_vista.material = _mat_redondeo
	add_child(_vista)
	_vista.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# 4) Marco (sólo borde, dibujado encima) con el mismo radio de esquina.
	_marco = Panel.new()
	_marco.name = "Marco"
	_marco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_marco)
	_marco.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# 5) Flecha central: relleno BLANCO + contorno NEGRO, en un Node2D que se rota
	# entero según la mirada. La forma se define UNA vez (base _flecha_base) y se
	# ESCALA en _aplicar_layout(): no se recrea al alternar de modo.
	_flecha = Node2D.new()
	_flecha.name = "Flecha"
	var h := _flecha_base * 0.075
	var w := _flecha_base * 0.058
	var forma := PackedVector2Array([
		Vector2(0.0, -h * 1.5),
		Vector2(w * 1.2, h * 1.0),
		Vector2(0.0, h * 0.25),
		Vector2(-w * 1.2, h * 1.0),
	])
	var contorno := Polygon2D.new()
	contorno.name = "Contorno"
	contorno.polygon = _contorno_de(forma, 2.0)
	contorno.color = flecha_borde_color
	_flecha.add_child(contorno)
	var relleno := Polygon2D.new()
	relleno.name = "Relleno"
	relleno.polygon = forma
	relleno.color = flecha_color
	_flecha.add_child(relleno)
	add_child(_flecha)


# =============================================================== Seguimiento
func _es_vuelo() -> bool:
	return _vuelo != null and _jugador != null and _jugador.id_forma() == &"aguila"


func _objetivo() -> Node3D:
	if _es_vuelo() and _vuelo != null:
		return _vuelo
	return _jugador


func _actualizar_seguimiento() -> void:
	if _cam == null:
		return
	if _ampliado:
		# Modo ampliado: la cámara se centra en la ISLA (no sigue al jugador).
		var c := _centro_isla()
		_cam.global_position = Vector3(c.x, altura, c.y)
	else:
		var obj := _objetivo()
		if obj == null:
			return
		var p := obj.global_position
		_cam.global_position = Vector3(p.x, p.y + altura, p.z)
	_cam.global_rotation = Vector3(-PI * 0.5, 0.0, 0.0)


func _actualizar_flecha() -> void:
	if _flecha == null:
		return
	var piv: Node3D = _pivote_vuelo if (_es_vuelo() and _pivote_vuelo != null) else _pivote_leo
	if piv == null:
		return
	var f := -piv.global_transform.basis.z
	f.y = 0.0
	if f.length_squared() < 0.0001:
		return
	f = f.normalized()
	# Mapa con el norte (-Z) arriba: ángulo medido desde "arriba" en sentido horario.
	_flecha.rotation = atan2(f.x, -f.z)


# =============================================================== Modo ampliado (M)
## La tecla M alterna normal/ampliado. Es una acción GLOBAL del proyecto
## (`toggle_minimapa`), común a TODAS las formas: el minimapa vive en el HUD del
## jugador, así que no hace falta lógica por personaje. No está en el catálogo de
## reasignables => no se puede remapear.
func _unhandled_input(event: InputEvent) -> void:
	if not (_es_tecla_m(event) or event.is_action_pressed("toggle_minimapa")):
		return
	# No alternar mientras el juego está pausado (menús): no corresponde controlar.
	if get_tree().paused:
		return
	_alternar_ampliado()
	get_viewport().set_input_as_handled()


## Tecla física M (independiente de la codificación del evento).
func _es_tecla_m(event: InputEvent) -> bool:
	if not (event is InputEventKey):
		return false
	var k := event as InputEventKey
	return k.pressed and not k.echo \
			and (k.physical_keycode == KEY_M or k.keycode == KEY_M)


## Alterna minimapa normal <-> mapa ampliado de la isla. Reutiliza el MISMO
## SubViewport, la MISMA cámara y el MISMO marco: sólo cambia el tamaño del
## control, la cobertura de la cámara y la resolución interna. No duplica nada.
func _alternar_ampliado() -> void:
	_ampliado = not _ampliado
	_aplicar_layout()
	_actualizar_seguimiento()
	if _sub != null:
		_sub.render_target_update_mode = SubViewport.UPDATE_ONCE


func _on_viewport_resized() -> void:
	if _ampliado:
		_aplicar_layout()


## Aplica tamaño, posición, radio de esquinas, cobertura y resolución interna
## según el modo. Es lo ÚNICO que cambia al alternar (sin recrear recursos).
func _aplicar_layout() -> void:
	if _sub == null:
		return
	var vp := get_viewport_rect().size
	if _ampliado:
		var lado := maxf(120.0, minf(vp.x, vp.y) * factor_ampliado)
		size = Vector2(lado, lado)
		position = (vp - size) * 0.5
	else:
		size = Vector2(float(tamano_px), float(tamano_px))
		position = Vector2(float(margen_px), float(margen_px))

	# Marco: borde oscuro redondeado, con el MISMO radio que el recorte.
	var radio := float(int(size.x * radio_esquina))
	var estilo := StyleBoxFlat.new()
	estilo.draw_center = false
	estilo.set_corner_radius_all(int(radio))
	estilo.set_border_width_all(2)
	estilo.border_color = borde_color
	_marco.add_theme_stylebox_override("panel", estilo)

	# Recorte redondeado de la imagen (mismo radio y tamaño que el marco).
	if _mat_redondeo != null:
		_mat_redondeo.set_shader_parameter("radio", radio)
		_mat_redondeo.set_shader_parameter("tam", size)

	# Cobertura de la cámara y resolución interna según el modo.
	_cam.size = metros_isla if _ampliado else metros_visibles
	_sub.size = Vector2i(resolucion_ampliada, resolucion_ampliada) if _ampliado \
			else Vector2i(resolucion, resolucion)

	# Flecha: escalada al tamaño actual y centrada (sin recrear).
	_flecha.scale = Vector2.ONE * minf(size.x / _flecha_base, 2.0)
	_flecha.position = size * 0.5


## Centro de la isla (para el modo ampliado). Se toma de la MISMA matemática del
## mundo que usan el terreno y la ciudad (Relieve), no de un valor inventado.
func _centro_isla() -> Vector2:
	return Relieve.CENTRO


## Contorno: desplaza cada vértice hacia fuera desde el centro, para un borde
## uniforme y fino (mejor que un escalado, que engrosaría las puntas).
func _contorno_de(puntos: PackedVector2Array, grosor: float) -> PackedVector2Array:
	var centro := Vector2.ZERO
	for p in puntos:
		centro += p
	centro /= float(puntos.size())
	var salida := PackedVector2Array()
	for p in puntos:
		var d := p - centro
		var n := d.normalized() if d.length() > 0.0001 else Vector2.ZERO
		salida.append(p + n * grosor)
	return salida


# =============================================================== Bucle
func _process(delta: float) -> void:
	var pausa := get_tree().paused
	if pausa:
		if not _pausado:
			_pausado = true
			if _sub != null:
				_sub.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	_pausado = false

	_actualizar_flecha()
	if fps_actualizacion <= 0.0:
		_actualizar_seguimiento()
		_sub.render_target_update_mode = SubViewport.UPDATE_ONCE
		return
	_acum += delta
	if _acum >= 1.0 / fps_actualizacion:
		_acum = 0.0
		_actualizar_seguimiento()
		_sub.render_target_update_mode = SubViewport.UPDATE_ONCE


# =============================================================== Exclusión
func _on_node_added(n: Node) -> void:
	if not (n is VisualInstance3D):
		return
	if _es_dinamico(n):
		_marcar_dinamico(n)


func _excluir_dinamicos_inicial() -> void:
	if _mundo == null:
		return
	_recorrer(_mundo)


func _recorrer(n: Node) -> void:
	for c in n.get_children():
		if _es_dinamico(c):
			_marcar_dinamico(c)
		else:
			_recorrer(c)


## ¿El nodo pertenece a una entidad MÓVIL (se excluye del minimapa)? Dos reglas:
##  1. Algún ancestro hasta el mundo está en DINAMICOS (jugador —y por tanto el
##     Vuelo, que es su hijo—, barco, enemigos, peatones/NPCs).
##  2. Su primer ancestro hijo directo del mundo NO es escenario estático: esto
##     captura proyectiles y objetos sueltos añadidos al mundo en tiempo real.
func _es_dinamico(n: Node) -> bool:
	var actual: Node = n
	while actual != null and actual != _mundo:
		if actual.name in DINAMICOS:
			return true
		actual = actual.get_parent()
	if actual == null:
		return false
	var anc := _primer_hijo_del_mundo(n)
	return anc != null and not (anc.name in ESTATICOS)


## Primer ancestro (incluido el propio nodo) que es hijo directo del mundo.
## Devuelve null si el nodo no está bajo el mundo.
func _primer_hijo_del_mundo(n: Node) -> Node:
	var actual: Node = n
	while actual != null and actual.get_parent() != _mundo:
		actual = actual.get_parent()
	return actual


func _marcar_dinamico(n: Node) -> void:
	if n is VisualInstance3D:
		(n as VisualInstance3D).layers = LAYER_DINAMICO
	for c in n.get_children():
		_marcar_dinamico(c)


func _buscar_jugador() -> Node3D:
	var n: Node = self
	while n != null:
		if n is ControladorLeo:
			return n as Node3D
		n = n.get_parent()
	return null


func _exit_tree() -> void:
	if _sub != null and is_instance_valid(_sub):
		_sub.render_target_update_mode = SubViewport.UPDATE_DISABLED