class_name VistaSubmarina
extends Node3D
## =============================================================================
##  VISTA SUBACUÁTICA (filtro azul + niebla) Y BURBUJAS DE LA CÁMARA
## =============================================================================
##  Se activa por la POSICIÓN REAL DE LA CÁMARA, no por la transformación elegida:
##  si la cámara está por encima de la superficie no hay efecto aunque el personaje
##  esté nadando, y si el velocista se hunde con la cámara dentro, sí lo hay. La
##  entrada y la salida son un fundido suave, así que cruzar la superficie no da
##  ningún salto visual.
##
##  Reutiliza lo que YA existe en el proyecto en vez de montar sistemas nuevos:
##    * el velo de pantalla `acuatica/vfx/underwater_overlay.gdshader` (tiñe, ondula
##      un poco la imagen y la cierra con una viñeta), montado en una CanvasLayer
##      por DEBAJO del HUD: la interfaz, los indicadores de habilidad y el menú
##      nunca se tiñen, y la capa no captura el ratón (mouse_filter IGNORE),
##    * el shader de gota `acuatica/vfx/water_particle.gdshader` para las burbujas,
##    * la niebla del Environment de la escena, que se guarda y se RESTAURA igual
##      (no se duplica el entorno: el ciclo de día y noche es su dueño).
##
##  No toca la cámara, ni el movimiento, ni el daño: es sólo aspecto.
## =============================================================================

const SHADER_VELO := preload("res://personaje/transformaciones/acuatica/vfx/underwater_overlay.gdshader")
const SHADER_GOTA := preload("res://personaje/transformaciones/acuatica/vfx/water_particle.gdshader")

## Capa del velo: por encima del juego y de la distorsión del velocista (capa 1)
## pero MUY por debajo del HUD (10) y de los menús (50/100/120).
const CAPA_VELO := 2

@export_group("Filtro")
## Profundidad (m) de la cámara bajo la superficie con el efecto a tope.
@export var profundidad_max: float = 6.0
## Curva del efecto con la profundidad: < 1 = aparece pronto y satura despacio.
@export var curva_profundidad: float = 0.55
## Rapidez (1/s) del fundido de entrada y de salida.
@export var velocidad_fundido: float = 2.2
## Cuánto tiñe el velo a tope (0..1).
@export var tinte_max: float = 0.5
## Color del agua (azul-turquesa) que absorbe la imagen.
@export var color_tinte: Color = Color(0.06, 0.33, 0.46)
## Cuánto ondula la imagen a tope (distorsión leve).
@export var ondulacion: float = 0.7
## Fuerza de la viñeta a tope.
@export var vineta: float = 1.0

@export_group("Niebla")
## La niebla del agua es lo que quita nitidez a lo LEJANO: absorbe la luz con la
## distancia. Densidad a tope; con la cámara fuera se restaura la de la escena.
@export var niebla_densidad_max: float = 0.022
@export var niebla_color: Color = Color(0.05, 0.23, 0.34)
## Distancia (m) a la que empieza y acaba la niebla a tope.
@export var niebla_cerca: float = 1.0
@export var niebla_lejos: float = 46.0

@export_group("Burbujas de la cámara")
## Burbujas alrededor de la cámara. Algunas quedan cerca (recién nacidas) y otras
## lejanas (más viejas), porque nacen en el espacio del mundo y la cámara las deja
## atrás al avanzar.
@export var burbujas_cantidad: int = 24
@export var burbujas_volumen: float = 5.5
@export var burbujas_tamano: float = 0.055

@export_group("Audio sumergido")
## Con la cámara bajo el agua TODO suena amortiguado: se le baja el corte al
## filtro paso-bajo que se añade a los buses de sonido del proyecto. El estado es
## el MISMO `_inmersion` que tiñe la pantalla (cámara real), así que la imagen y
## el sonido entran y salen juntos, sin un segundo detector de agua.
@export var audio_sumergido: bool = true
## Corte (Hz) del filtro con la cámara FUERA: es el máximo (filtro apagado).
@export_range(4000.0, 20500.0, 100.0) var audio_corte_fuera: float = 20500.0
## Corte (Hz) con la cámara bien dentro del agua: sonido apagado, "bajo el agua".
@export_range(120.0, 4000.0, 20.0) var audio_corte_dentro: float = 700.0
@export_range(0.0, 4.0, 0.1) var audio_resonancia: float = 0.6
## Buses del proyecto que se amortiguan (por NOMBRE; los que no existan se omiten
## sin fallar). No se toca el layout de buses ni los volúmenes de los ajustes.
@export var audio_buses: PackedStringArray = PackedStringArray(["Efectos", "Musica", "Dialogos"])

var _camara: Camera3D = null
var _velo: ColorRect = null
var _mat_velo: ShaderMaterial = null
var _burbujas: GPUParticles3D = null
var _entorno: Environment = null
var _base_guardada: bool = false
var _base_niebla_activa: bool = false
var _base_niebla_densidad: float = 0.0
var _base_niebla_color: Color = Color.WHITE
var _base_niebla_cielo: float = 1.0
var _inmersion: float = 0.0
## Filtros paso-bajo añadidos a los buses: [(bus, índice del efecto, filtro)].
## Se RETIRAN al salir del árbol, para que recargar la escena no los acumule.
var _audio: Array = []
var _audio_aplicado: float = -1.0


func _ready() -> void:
	_montar_velo()
	_montar_burbujas()
	_montar_audio()
	_guardar_entorno()
	_aplicar()


func _process(delta: float) -> void:
	var profundidad := _profundidad_camara()
	var objetivo := pow(clampf(profundidad / maxf(profundidad_max, 0.1), 0.0, 1.0), curva_profundidad)
	var anterior := _inmersion
	# Se acerca al objetivo a velocidad constante: nunca hay salto ni parpadeo.
	_inmersion = move_toward(_inmersion, objetivo, velocidad_fundido * delta)
	if absf(_inmersion - objetivo) > 0.0005 or _inmersion > 0.0005 or anterior > 0.0005:
		_aplicar()


# -----------------------------------------------------------------------------
#  API (por si otro sistema quiere saber si la CÁMARA está bajo el agua)
# -----------------------------------------------------------------------------
## 0 = cámara fuera del agua, 1 = bien dentro. Ya suavizado.
func inmersion() -> float:
	return _inmersion


## Profundidad (m) de la CÁMARA bajo la superficie del agua, o 0 si está fuera.
func _profundidad_camara() -> float:
	var cam := _camara_actual()
	if cam == null or not is_instance_valid(cam) or not cam.is_inside_tree():
		return 0.0
	# `Relieve.NIVEL_MAR` es la MISMA cota de mar que genera el mundo. La superficie
	# VISIBLE del océano está 5 cm por debajo (Agua/Scenes/Ocean.tscn), así que el
	# efecto empieza justo cuando la cámara toca el agua, sin quedarse corto.
	return maxf(Relieve.NIVEL_MAR - cam.global_position.y, 0.0)


func _camara_actual() -> Camera3D:
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		return cam
	if _camara != null and is_instance_valid(_camara):
		return _camara
	_camara = _buscar_camara(get_parent())
	return _camara


func _buscar_camara(nodo: Node) -> Camera3D:
	if nodo == null:
		return null
	for hijo in nodo.get_children():
		if hijo is Camera3D:
			return hijo
		var hondo := _buscar_camara(hijo)
		if hondo != null:
			return hondo
	return null


# -----------------------------------------------------------------------------
#  Audio sumergido (Tarea 10)
# -----------------------------------------------------------------------------
## Añade un filtro paso-bajo a cada bus de sonido del proyecto. Es ADITIVO: no
## toca el layout de buses ni los volúmenes que manejan los ajustes de audio.
## Fuera del agua el corte queda en su MÁXIMO (20500 Hz), que es lo mismo que no
## filtrar: el audio suena exactamente como si el filtro no estuviera.
func _montar_audio() -> void:
	if not audio_sumergido:
		return
	for nombre in audio_buses:
		var bus := AudioServer.get_bus_index(StringName(nombre))
		if bus < 0:
			continue
		var filtro := AudioEffectLowPassFilter.new()
		filtro.cutoff_hz = audio_corte_fuera
		filtro.resonance = audio_resonancia
		AudioServer.add_bus_effect(bus, filtro)
		_audio.append({"bus": bus, "idx": AudioServer.get_bus_effect_count(bus) - 1, "filtro": filtro})


## Aplica la inmersión al audio: fuera del agua el corte vuelve al máximo (sin
## filtrar); dentro baja hasta `audio_corte_dentro` con la MISMA curva suave que
## el velo, así que no hay saltos de sonido al cruzar la superficie.
func _aplicar_audio(a: float) -> void:
	if _audio.is_empty():
		return
	if is_equal_approx(a, _audio_aplicado):
		return
	_audio_aplicado = a
	var corte := lerpf(audio_corte_fuera, audio_corte_dentro, clampf(a, 0.0, 1.0))
	for e in _audio:
		var d := e as Dictionary
		var filtro := d.get("filtro") as AudioEffectLowPassFilter
		if filtro == null or not is_instance_valid(filtro):
			continue
		filtro.cutoff_hz = maxf(20.0, corte)


## Estado actual del audio sumergido (para pruebas y para quien quiera consultarlo).
func audio_inmersion() -> float:
	return _audio_aplicado


func _exit_tree() -> void:
	for e in _audio:
		var d := e as Dictionary
		var bus := int(d.get("bus", -1))
		var idx := int(d.get("idx", -1))
		if bus < 0 or idx < 0:
			continue
		if bus < AudioServer.bus_count and idx < AudioServer.get_bus_effect_count(bus):
			AudioServer.remove_bus_effect(bus, idx)
	_audio.clear()


# -----------------------------------------------------------------------------
#  Velo de pantalla
# -----------------------------------------------------------------------------
func _montar_velo() -> void:
	var capa := CanvasLayer.new()
	capa.name = "CapaVistaSubmarina"
	capa.layer = CAPA_VELO
	add_child(capa)
	_velo = ColorRect.new()
	_velo.name = "Velo"
	_velo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# No captura el ratón: controles, apuntado y UI siguen funcionando igual.
	_velo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat_velo = ShaderMaterial.new()
	_mat_velo.shader = SHADER_VELO
	_velo.material = _mat_velo
	_velo.visible = false
	capa.add_child(_velo)


# -----------------------------------------------------------------------------
#  Niebla del agua (se guarda la de la escena y se restaura tal cual)
# -----------------------------------------------------------------------------
func _guardar_entorno() -> void:
	var we := _buscar_entorno(get_tree().current_scene)
	if we == null or we.environment == null:
		return
	_entorno = we.environment
	_base_niebla_activa = _entorno.fog_enabled
	_base_niebla_densidad = _entorno.fog_density
	_base_niebla_color = _entorno.fog_light_color
	_base_niebla_cielo = _entorno.fog_sky_affect
	_base_guardada = true


func _buscar_entorno(nodo: Node) -> WorldEnvironment:
	if nodo == null:
		return null
	if nodo is WorldEnvironment and (nodo as WorldEnvironment).environment != null:
		return nodo as WorldEnvironment
	for hijo in nodo.get_children():
		var e := _buscar_entorno(hijo)
		if e != null:
			return e
	return null


# -----------------------------------------------------------------------------
#  Burbujas de la cámara
# -----------------------------------------------------------------------------
func _montar_burbujas() -> void:
	var proceso := ParticleProcessMaterial.new()
	proceso.direction = Vector3(0.0, 1.0, 0.0)
	proceso.spread = 14.0
	proceso.initial_velocity_min = 0.28
	proceso.initial_velocity_max = 0.75
	# Gravedad "hacia arriba": las burbujas suben, no caen.
	proceso.gravity = Vector3(0.0, 0.4, 0.0)
	proceso.scale_min = 0.55
	proceso.scale_max = 1.7
	proceso.damping_min = 0.0
	proceso.damping_max = 0.25
	proceso.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	proceso.emission_box_extents = Vector3(
			burbujas_volumen * 0.5, burbujas_volumen * 0.35, burbujas_volumen * 0.5)

	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * burbujas_tamano
	var mat := ShaderMaterial.new()
	mat.shader = SHADER_GOTA
	mat.set_shader_parameter("color", Color(0.8, 0.94, 1.0, 0.5))

	_burbujas = GPUParticles3D.new()
	_burbujas.name = "BurbujasCamara"
	_burbujas.amount = maxi(burbujas_cantidad, 4)
	_burbujas.lifetime = 2.8
	# En el espacio del MUNDO: nacen donde está la cámara y se quedan atrás, así que
	# unas se ven de cerca y otras de lejos según avanza.
	_burbujas.local_coords = false
	_burbujas.draw_pass_1 = quad
	_burbujas.material_override = mat
	_burbujas.process_material = proceso
	# El emisor viaja con la cámara, así que su caja de visibilidad tiene que ser
	# holgada o el motor descartaría las partículas por "fuera de pantalla".
	_burbujas.visibility_aabb = AABB(
			Vector3.ONE * -burbujas_volumen * 2.0, Vector3.ONE * burbujas_volumen * 4.0)
	_burbujas.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_burbujas.emitting = false
	add_child(_burbujas)


# -----------------------------------------------------------------------------
#  Aplicar
# -----------------------------------------------------------------------------
func _aplicar() -> void:
	var a := _inmersion
	if _mat_velo != null:
		_mat_velo.set_shader_parameter("amount", a)
		_mat_velo.set_shader_parameter("tint", Vector3(color_tinte.r, color_tinte.g, color_tinte.b))
		_mat_velo.set_shader_parameter("tint_strength", tinte_max)
		_mat_velo.set_shader_parameter("wobble", ondulacion)
		_mat_velo.set_shader_parameter("vignette", vineta)
	if _velo != null:
		_velo.visible = a > 0.004
	_aplicar_niebla(a)
	_aplicar_audio(a)
	if _burbujas != null and is_instance_valid(_burbujas):
		var cam := _camara_actual()
		if cam != null and is_instance_valid(cam) and cam.is_inside_tree():
			_burbujas.global_position = cam.global_position
		_burbujas.emitting = a > 0.12
		_burbujas.amount_ratio = clampf(a * 1.3, 0.0, 1.0)


func _aplicar_niebla(a: float) -> void:
	if not _base_guardada or _entorno == null:
		return
	if a <= 0.004:
		_entorno.fog_enabled = _base_niebla_activa
		_entorno.fog_density = _base_niebla_densidad
		_entorno.fog_light_color = _base_niebla_color
		_entorno.fog_sky_affect = _base_niebla_cielo
		return
	_entorno.fog_enabled = true
	_entorno.fog_mode = Environment.FOG_MODE_DEPTH
	_entorno.fog_light_color = niebla_color
	_entorno.fog_light_energy = 1.0
	_entorno.fog_density = niebla_densidad_max * a
	# El cielo no se tiñe de niebla: con la cámara dentro del agua no se ve cielo.
	_entorno.fog_sky_affect = 0.0
	# Con la densidad a tope la niebla empieza a 1 m; al entrar (a pequeña) empieza
	# muy lejos, así que en la superficie casi no se nota.
	_entorno.fog_depth_begin = niebla_cerca
	_entorno.fog_depth_end = lerpf(220.0, niebla_lejos, a)
