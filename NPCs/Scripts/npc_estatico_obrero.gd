class_name NPCEstaticoObrero
extends Node3D

## OBRERO DE CONSTRUCCIÓN ESTÁTICO: un único NPC decorativo que vive en una de las
## plazas (manzanas-parque) de la ciudad y no se mueve nunca.
##
## No tiene IA, ni navegación, ni movimiento, ni colisión: sólo monta el modelo del
## obrero (casco, chaleco reflectante y botas), le deja una pose de reposo en el sitio
## y lo planta UNA vez sobre el sendero de una plaza. No toca ningún sistema del
## proyecto: los peatones, la ciudad, el jugador y las físicas quedan como estaban.
##
## ¿POR QUÉ LA POSICIÓN SE RESUELVE EN CÓDIGO Y NO CON UNA COORDENADA FIJA?
## La ciudad se genera con semilla ALEATORIA en cada partida (generador_ciudad.gd:
## `semilla = 0` → `randi()`), así que las tres plazas caen en manzanas distintas cada
## vez: una coordenada fija quedaría la mayoría de las partidas dentro de un edificio
## o sobre la calzada. Aquí se busca la plaza REAL de la partida en curso (los nodos
## `Parque_1..3` que crea el generador) y se apoya al obrero sobre su sendero, cuya
## geometría es conocida y estable:
##   · senderos en cruz de 3 m de ancho a cota de acera (Y_ACERA = 0),
##   · césped 15 cm más bajo,
##   · árboles, arbustos, jardineras y bancos apartados ≥ 2.1 m del eje de los senderos.
## Se planta en el MARGEN DE CÉSPED que queda junto a la senda este-oeste, a 6 m del
## cruce y 1.9 m del eje: no bloquea el sendero y queda dentro del corredor que el
## generador mantiene libre de árboles y jardineras (±2.1 m del eje), lejos de los
## arbustos (2.3 m), de los bancos (a 1.9 m de su borde) y de los bolardos. El apoyo
## se mide con un rayo hacia abajo, así que los pies quedan sobre la superficie real
## (la propia medida avisa de la cota en la que cayó).
##
## COLISIÓN: una cápsula del tamaño de la de un ciudadano (r 0.30, alto 1.78) en la
## CAPA 2 (la de los ciudadanos), igual que ellos, para que el jugador —que sí colisiona
## con esa capa (Jugador: collision_mask = 3)— no lo atraviese. Los peatones llevan
## máscara 1, así que esta cápsula NO les afecta: su navegación queda igual que antes.
##
## Si la ciudad se REGENERA (limpiar_ciudad + generar otra con semilla nueva), los
## nodos de la plaza son otros y el obrero se vuelve a plantar en la plaza nueva: no
## se queda dentro de un edificio ni desaparece.
##
## FLECHA AMARILLA (NPC_Estatico_Obrero.tscn, nodo IndicadorAmarillo/Flecha): es la
## marca para localizar a Iván de lejos. Su tamaño está en las MALLAS, con el nodo SIN
## escala (así ninguna propiedad puede quedar sobrescrita): punta = cono de 1.728 m de
## alto por 1.296 m de ancho (malla "Mesh_punta_flecha", top_radius 0.648, radio
## inferior 0 → vértice hacia abajo), vástago = cilindro de 2.16 m de alto por 0.486 m
## de ancho. Total: 3.888 m de alto, con la punta a y = 2.0 (0.21 m sobre la
## coronilla) para que señale al personaje sin atravesarlo. Material sin sombreado
## (shading_mode = 0, UNSHADED): no depende de la luz ni del ciclo día/noche.

## Señal de OBJETIVO: avisa de que la conversación con el obrero EMPIEZA de verdad
## (el globo de diálogo llegó a abrirse). La usa el cartel de objetivo del HUD para
## darse por completado. Sólo se emite con la interacción real dentro del rango: ni al
## acercarse, ni al mirar al NPC, ni al pulsar E fuera de distancia.
signal dialogo_iniciado

## Modelo del obrero: el del pack de Mixamo que trae casco, chaleco reflectante,
## botas y pantalón de trabajo (verificado en sus piezas y en su atlas de texturas).
const MODELO := "res://modelos 3d npcs/Ch17_nonPBR.fbx"
## Librería de clips que ya usa el sistema de ciudadanos (se lee, no se modifica).
const LIBRERIA := "res://NPCs/Animations/Citizen_Animations_Mixamo.res"
## Clip de reposo: un idle del mismo repertorio que usan los ciudadanos.
const CLIP_REPOSO := "idle_m1"
## Nombre que debe tener el nodo del modelo: las pistas del clip son
## "Model/Skeleton3D:hueso".
const NOMBRE_MODELO := "Model"
## Cota del césped de las plazas (generador_ciudad.gd: Y_PARQUE = -0.15). Sólo se
## usa como respaldo si el rayo de apoyo no engancha nada.
const Y_CESPED := -0.15
## Sitios candidatos (x, z) medidos DESDE el centro de la plaza, en orden de
## preferencia: todos sobre el margen de césped junto a la senda este-oeste
## (|z| = 1.9 m, senda de 3 m -> borde a 1.5). Se elige el primero que esté libre de
## obstáculos: el generador aparta árboles y jardineras del eje de las sendas, pero
## las jardineras pueden caer al lado del sitio elegido, así que se comprueba.
const SITIOS := [
	Vector2(6.0, 1.9), Vector2(6.0, -1.9),
	Vector2(4.5, 1.9), Vector2(4.5, -1.9),
	Vector2(7.5, 1.9), Vector2(7.5, -1.9),
	Vector2(3.0, 1.9), Vector2(9.0, 1.9),
]
## Radio (m) de espacio libre que se exige alrededor del obrero.
const RADIO_LIBRE := 0.75
## Altura (m) desde la que se lanza el rayo de apoyo y hasta dónde baja.
const RAYO_ALTO := 6.0
const RAYO_BAJO := -3.0
## Capa 1 (mundo): la misma que usan los peatones para pisar.
const CAPA_SUELO := 1
## Espera máxima (s) a que la ciudad esté generada antes de darse por vencido.
const ESPERA_MAX := 30.0
## Cada cuánto (s) se comprueba si la plaza sigue existiendo (por si se regenera).
const REVISAR := 0.5

## --- INTERACCIÓN -----------------------------------------------------------
## Distancia (m) a la que se puede hablar con el obrero: dentro del rango pedido
## (2.5-3 m) y algo mayor que su cápsula (radio 0.30) para no tener que pegarse.
const DISTANCIA_INTERACCION := 2.8
## Acción del proyecto que abre la conversación (tecla E, ya definida en el input map).
const ACCION_INTERACTUAR := &"interactuar"
## Texto del indicador contextual.
const TEXTO_INDICADOR := "E — Hablar con Iván"
## Aviso con el estilo nuevo del HUD (componente AvisoInteraccion). `false` = el
## panel anterior (para comparar).
const AVISO_ESTILO_NUEVO := true
## Archivo de diálogo de Dialogue Manager y cue por el que empieza la conversación.
const RUTA_DIALOGO := "res://NPCs/Dialogues/ivan.dialogue"
const CUE_INICIO := "inicio"

var _modelo: Node3D = null
var _animador: AnimationPlayer = null
var _contenedor: Node = null            ## nodo CiudadGenerada de la partida en curso
var _plaza: Node3D = null               ## nodo Parque_N en el que está plantado
var _t_espera := 0.0
var _t_revisar := 0.0
var _avisado := false
var _listo := false
var _jugador: Node3D = null             ## jugador (grupo "player"), cacheado
var _dialogo: DialogueResource = null   ## .dialogue de Iván, cargado una vez
var _globo: Node = null                 ## conversación abierta (null = ninguna)
var _capa_indicador: CanvasLayer = null

func _ready() -> void:
	_montar_modelo()
	_crear_indicador()

func _process(delta: float) -> void:
	_t_espera += delta
	_actualizar_interaccion()
	_t_revisar -= delta
	if _t_revisar > 0.0:
		return
	_t_revisar = REVISAR
	var plaza := _buscar_plaza()
	if plaza == null:
		if not _listo and _t_espera > ESPERA_MAX and not _avisado:
			_avisado = true
			push_warning("[Obrero] La ciudad no tiene ninguna plaza (manzana-parque): el obrero no se coloca.")
			visible = false
		return
	if plaza == _plaza:
		return                              # la misma plaza de siempre: no se toca nada
	_plaza = plaza
	_plantar_en_plaza(plaza)

# ------------------------------------------------------------------ montaje del modelo

## Monta el modelo del obrero con la MISMA receta que usa el sistema de ciudadanos,
## porque es la que hace que los clips compartidos encajen en estos FBX: renombrar
## huesos y bind names del Skin a la forma canónica ("mixamorig_X") ANTES de entrar
## al árbol (si se hiciera después, el motor avisa y la malla sale deforme), y apagar
## el AnimationPlayer propio del FBX para que no pelee por la pose de los huesos.
func _montar_modelo() -> void:
	var escena: PackedScene = load(MODELO)
	if escena == null:
		push_error("[Obrero] No se pudo cargar el modelo %s" % MODELO)
		return
	var modelo := escena.instantiate() as Node3D
	modelo.name = NOMBRE_MODELO
	for n in modelo.find_children("*", "AnimationPlayer", true, false):
		var ap := n as AnimationPlayer
		ap.autoplay = ""
		ap.stop()
	_normalizar_esqueleto(modelo)
	add_child(modelo)
	_modelo = modelo
	# Pose de reposo: un idle de la librería compartida, en bucle. Se duplica el clip
	# para ponerle el bucle sin tocar el recurso compartido que usan los ciudadanos.
	_animador = AnimationPlayer.new()
	_animador.name = "AnimadorReposo"
	add_child(_animador)
	var compartida: AnimationLibrary = load(LIBRERIA)
	if compartida == null or not compartida.has_animation(CLIP_REPOSO):
		push_warning("[Obrero] La librería %s no trae el clip %s: el obrero se queda en su pose de reposo del FBX." % [LIBRERIA, CLIP_REPOSO])
		return
	var copia := (compartida.get_animation(CLIP_REPOSO) as Animation).duplicate() as Animation
	copia.loop_mode = Animation.LOOP_LINEAR
	var propia := AnimationLibrary.new()
	propia.add_animation(CLIP_REPOSO, copia)
	_animador.add_animation_library("", propia)
	_animador.play(CLIP_REPOSO)

## Pasa los nombres de hueso a la forma canónica "mixamorig_X" (los FBX de Mixamo
## numeran el prefijo: "mixamorig1_Hips"). Idempotente: un nombre ya canónico se deja
## igual, así que repetirlo no cuesta nada.
func _normalizar_esqueleto(modelo: Node) -> void:
	var esqueleto := modelo.find_child("Skeleton3D", true, false) as Skeleton3D
	if esqueleto == null:
		push_warning("[Obrero] El modelo no trae Skeleton3D.")
		return
	for i in esqueleto.get_bone_count():
		var canon := _nombre_canonico(String(esqueleto.get_bone_name(i)))
		if canon != "":
			esqueleto.set_bone_name(i, canon)
	# Cada malla trae un Skin con los NOMBRES de hueso del FBX original: si sólo se
	# renombrara el esqueleto, el skin ya no encontraría sus huesos y la malla saldría
	# deforme (cuerpo hundido). Se renombran los dos lados con la misma regla.
	for nodo in modelo.find_children("*", "MeshInstance3D", true, false):
		var piel: Skin = (nodo as MeshInstance3D).skin
		if piel == null:
			continue
		for b in piel.get_bind_count():
			var canon2 := _nombre_canonico(piel.get_bind_name(b))
			if canon2 != "":
				piel.set_bind_name(b, canon2)

func _nombre_canonico(nombre: String) -> String:
	if not nombre.begins_with("mixamorig"):
		return ""
	var pos := nombre.find("_")
	if pos <= 0:
		return ""
	var canon := "mixamorig_" + nombre.substr(pos + 1)
	return canon if nombre != canon else ""

# ------------------------------------------------------------------ colocación

## Busca la plaza de la partida en curso. Devuelve SIEMPRE la misma (la primera por
## nombre) para que el obrero no salte de una plaza a otra: sólo cambia cuando la
## ciudad se regenera y los nodos son otros.
func _buscar_plaza() -> Node3D:
	if _contenedor == null or not is_instance_valid(_contenedor):
		var escena := get_tree().current_scene
		if escena == null:
			return null
		_contenedor = escena.find_child("CiudadGenerada", true, false)
		if _contenedor == null:
			# La ciudad puede llamarse de otra forma en otras escenas: se busca directo.
			_contenedor = escena
	var plazas := _contenedor.find_children("Parque_*", "StaticBody3D", true, false)
	if plazas.is_empty():
		return null
	var nombres: Array[String] = []
	var por_nombre := {}
	for p in plazas:
		var s := String(p.name)
		nombres.append(s)
		por_nombre[s] = p
	nombres.sort()
	return por_nombre[nombres[0]] as Node3D

## Planta al obrero sobre el sendero de la plaza, mirando al cruce.
func _plantar_en_plaza(plaza: Node3D) -> void:
	var centro := Vector2(plaza.global_position.x, plaza.global_position.z)
	var sitio := _elegir_sitio(centro)
	var apoyo := _medir_apoyo(sitio.x, sitio.y)
	global_position = Vector3(sitio.x, apoyo, sitio.y)
	var hacia := Vector3(centro.x - sitio.x, 0.0, centro.y - sitio.y)
	if hacia.length_squared() > 0.0001:
		# Los modelos de Mixamo del proyecto miran hacia su +Z (el director de
		# peatones orienta con atan2(dir.x, dir.z)): se le pone de cara al cruce.
		rotation.y = atan2(hacia.x, hacia.z)
	visible = true
	_listo = true
	# El césped de las plazas está 15 cm por debajo de la acera, así que el apoyo
	# esperado es la cota del césped. Si saliera otra, se avisa (la posición sigue
	# siendo la medida: no se inventa ninguna altura).
	var aviso := "otra cota (%.3f)" % apoyo
	if absf(apoyo - Y_CESPED) < 0.05:
		aviso = "cesped junto al sendero"
	elif absf(apoyo) < 0.05:
		aviso = "sendero (cota de acera)"
	print("[Obrero] plantado en %s -> posicion (%.2f, %.3f, %.2f) | apoyo: %s | libre alrededor: %s | giro %.1f grados | modelo %s" % [
			plaza.name, global_position.x, global_position.y, global_position.z,
			aviso, str(_sitio_libre(sitio)),
			rad_to_deg(rotation.y), str(_modelo != null)])

## Primer sitio candidato con espacio libre alrededor; si ninguno lo tiene, el primero
## (mejor un obrero algo pegado a un seto que uno dentro de un árbol).
func _elegir_sitio(centro: Vector2) -> Vector2:
	for s in SITIOS:
		var p: Vector2 = centro + (s as Vector2)
		if _sitio_libre(p):
			return p
	return centro + (SITIOS[0] as Vector2)

## ¿Hay al menos RADIO_LIBRE metros sin nada alrededor, a la altura del cuerpo?
## La esfera se centra 1 m sobre el césped: no toca el propio suelo ni los bordes de
## las losas del sendero (que quedan por debajo) y sí detecta troncos y jardineras.
func _sitio_libre(p: Vector2) -> bool:
	var forma := SphereShape3D.new()
	forma.radius = RADIO_LIBRE
	var consulta := PhysicsShapeQueryParameters3D.new()
	consulta.shape = forma
	consulta.collision_mask = CAPA_SUELO
	consulta.collide_with_areas = false
	consulta.transform = Transform3D(Basis(), Vector3(p.x, Y_CESPED + 1.0, p.y))
	var golpes := get_world_3d().direct_space_state.intersect_shape(consulta, 1)
	return golpes.is_empty()

## Altura de la superficie real bajo el punto (capa 1). Si el rayo no engancha nada
## (p. ej. el césped de la plaza sin colisión), se usa la cota del césped que
## documenta el generador (Y_PARQUE = -0.15), que es donde se apoya el obrero.
func _medir_apoyo(x: float, z: float) -> float:
	var desde := Vector3(x, RAYO_ALTO, z)
	var hasta := Vector3(x, RAYO_BAJO, z)
	var consulta := PhysicsRayQueryParameters3D.create(desde, hasta)
	consulta.collision_mask = CAPA_SUELO
	var golpe := get_world_3d().direct_space_state.intersect_ray(consulta)
	if golpe.is_empty():
		return Y_CESPED
	return float((golpe["position"] as Vector3).y)

# ------------------------------------------------------------------ interacción (E)

## Detecta al jugador, enseña el indicador contextual cuando está cerca y abre la
## conversación al pulsar `E`. La distancia se recalcula cada fotograma, así que sigue
## funcionando cuando el obrero se replanta al regenerarse la ciudad.
func _actualizar_interaccion() -> void:
	if _globo != null and not is_instance_valid(_globo):
		_globo = null                       # el globo se cerró y se liberó solo
	if _jugador == null or not is_instance_valid(_jugador):
		_jugador = get_tree().get_first_node_in_group("player") as Node3D
	var cerca := false
	if _listo and _jugador != null:
		cerca = global_position.distance_to(_jugador.global_position) <= DISTANCIA_INTERACCION
	if _capa_indicador != null:
		# El indicador sólo aparece cerca y cuando NO hay ya una conversación abierta.
		_capa_indicador.visible = cerca and _globo == null
	if not cerca or _globo != null:
		return
	# `just_pressed`: mantener la tecla pulsada NO repite la interacción, y con una
	# conversación abierta este código ni se alcanza (no se abre una segunda).
	if Input.is_action_just_pressed(ACCION_INTERACTUAR):
		_abrir_dialogo()

## Abre la conversación con el globo de diálogo configurado en Dialogue Manager.
## Se usa la vía recomendada por el addon: `DialogueManager.show_dialogue_balloon`.
func _abrir_dialogo() -> void:
	if _globo != null:
		return
	if not Engine.has_singleton("DialogueManager"):
		push_warning("[Obrero] Dialogue Manager no está activo: añade su autoload (ver addons/dialogue_manager).")
		return
	if _dialogo == null:
		_dialogo = _cargar_dialogo()
	if _dialogo == null:
		return
	_globo = (Engine.get_singleton("DialogueManager") as Node).show_dialogue_balloon(_dialogo, CUE_INICIO, [self])
	if _globo != null and _globo.has_signal("cerrado"):
		_globo.cerrado.connect(_al_cerrar_dialogo)
	if _globo != null:
		# La conversación empezó de verdad: aquí el objetivo del cartel queda cumplido.
		dialogo_iniciado.emit()
	if _capa_indicador != null:
		_capa_indicador.visible = false

func _al_cerrar_dialogo() -> void:
	_globo = null
	# La conversación ha terminado (el jugador pulsó «Entendido»): arranca la misión
	# de Iván. `activar_mision` es idempotente, así que volver a hablar con él NO
	# reinicia el progreso ni duplica el panel. No se activa mientras el diálogo
	# sigue abierto: sólo se llega aquí cuando se cierra.
	Misiones.activar_mision(Misiones.MISION_PROFUGOS)

## Carga el .dialogue. Lo normal es que Dialogue Manager ya lo haya importado (su
## importador del editor compila el texto a un DialogueResource): entonces basta `load`.
## Si todavía no está importado (por ejemplo antes de reiniciar el editor tras activar
## el addon), se compila aquí con EL MISMO compilador del addon, igual que hace su
## import_plugin.gd. No se inventa sintaxis ni se duplica el sistema: sólo se adelanta
## el trabajo del importador para que la conversación funcione igual.
func _cargar_dialogo() -> DialogueResource:
	if ResourceLoader.exists(RUTA_DIALOGO):
		var recurso := load(RUTA_DIALOGO)
		if recurso is DialogueResource:
			return recurso
	if not FileAccess.file_exists(RUTA_DIALOGO):
		push_error("[Obrero] No existe el archivo de diálogo %s" % RUTA_DIALOGO)
		return null
	var texto := FileAccess.get_file_as_string(RUTA_DIALOGO)
	var resultado: DMCompilerResult = DMCompiler.compile_string(texto, RUTA_DIALOGO)
	if not resultado.errors.is_empty():
		for e in resultado.errors:
			push_error("[Obrero] Error en %s: %s" % [RUTA_DIALOGO, str(e)])
		return null
	# Nombre propio para el recurso compilado: el `var recurso` de arriba (el del
	# `load`) ya vive en este mismo ámbito y GDScript rechaza redeclararlo
	# ("is declared below in the parent block"), que dejaba el script SIN COMPILAR.
	# (Recurso de respaldo: sólo se usa si el importador del addon aún no lo hizo.)
	var recurso_compilado := DialogueResource.new()
	recurso_compilado.using_states = resultado.using_states
	recurso_compilado.cues = resultado.cues
	recurso_compilado.first_cue = resultado.first_cue
	recurso_compilado.character_names = resultado.character_names
	recurso_compilado.lines = resultado.lines
	return recurso_compilado

## Indicador contextual "E — Hablar con Iván": una capa de interfaz propia (no toca el
## HUD del juego), centrada abajo y por encima de la banda del diálogo. Mismo lenguaje
## visual que los avisos del HUD (fondo oscuro translúcido, borde cian, texto claro).
func _crear_indicador() -> void:
	_capa_indicador = CanvasLayer.new()
	_capa_indicador.name = "IndicadorInteraccion"
	_capa_indicador.layer = 80
	add_child(_capa_indicador)
	if AVISO_ESTILO_NUEVO:
		# Mismo componente que el aviso del HUD (tema central + keycap). La capa
		# sigue siendo la que enciende/apaga `_actualizar_interaccion`.
		var aviso := AvisoInteraccion.new()
		aviso.name = "Aviso"
		_capa_indicador.add_child(aviso)
		aviso.anclar_abajo_centro(128.0)
		aviso.seguir_capa(_capa_indicador, TEXTO_INDICADOR)
		_capa_indicador.visible = false
		return
	var caja := PanelContainer.new()
	caja.name = "Aviso"
	caja.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caja.grow_horizontal = Control.GROW_DIRECTION_BOTH
	var estilo := StyleBoxFlat.new()
	estilo.bg_color = Color(0.05, 0.07, 0.10, 0.78)
	estilo.border_color = Color(0.45, 0.82, 1.0, 0.9)
	estilo.set_border_width_all(2)
	estilo.set_corner_radius_all(10)
	estilo.content_margin_left = 12.0
	estilo.content_margin_right = 12.0
	estilo.content_margin_top = 5.0
	estilo.content_margin_bottom = 5.0
	caja.add_theme_stylebox_override("panel", estilo)
	var etiqueta := Label.new()
	etiqueta.name = "Texto"
	etiqueta.text = TEXTO_INDICADOR
	etiqueta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	etiqueta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	etiqueta.add_theme_font_size_override("font_size", 18)
	etiqueta.add_theme_color_override("font_color", Color(0.93, 0.97, 1.0, 1.0))
	etiqueta.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	etiqueta.add_theme_constant_override("outline_size", 4)
	caja.add_child(etiqueta)
	_capa_indicador.add_child(caja)
	# Centrado horizontal y a 128 px del borde inferior: la banda del diálogo ocupa
	# la franja baja (panel compacto), así que el aviso queda justo por encima.
	caja.anchor_left = 0.5
	caja.anchor_right = 0.5
	caja.anchor_top = 1.0
	caja.anchor_bottom = 1.0
	caja.offset_left = -110.0
	caja.offset_right = 110.0
	caja.offset_top = -166.0
	caja.offset_bottom = -128.0
	_capa_indicador.visible = false