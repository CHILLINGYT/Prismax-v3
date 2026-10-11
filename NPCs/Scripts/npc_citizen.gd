class_name NPCCitizen
extends CharacterBody3D

## Ciudadano autónomo.
##
## Máquina de estados con variaciones aleatorias propias de cada ciudadano:
##
##   IDLE --(espera)--> DECIDE --(destino válido)--> WALK --> ARRIVE --> IDLE
##                        |                          |
##                        |                          +--> PAUSE (se detiene y sigue)
##                        +--(nada que hacer)             TURN  (gira en el sitio y sigue)
##
## Ningún ciudadano va en sincronía con otro: cada uno sortea su tempo, su velocidad
## (escala de animación incluida, para que los pies no patinen) y sus clips, así que no
## se ven clones haciendo lo mismo al mismo tiempo.
##
## Escalabilidad: el NPCSpawner asigna un nivel de actividad según la distancia al jugador
## (cerca = todo activo, media = sin evitación, lejos = congelado), de modo que se pueden
## tener cientos de ciudadanos en la ciudad pagando sólo por los que se ven de cerca.

enum State { IDLE, DECIDE, WALK, PAUSE, TURN, ARRIVE, NOTICE, REACT, POSTURA }

## Nivel de actividad (LOD de comportamiento). Lo asigna el NPCSpawner.
enum Activity { NEAR, MID, FAR }

## Tipos de reacción al jugador; cada ciudadano sortea uno con estos pesos.
## (Se descartó "saludar con la mano": el único clip de saludo de los packs, UAL2 "Yes", al pasarlo
## a estos rigs queda con pose de caminar. En su lugar está REACT_GREET, que se para y hace un gesto
## de los que YA están horneados y medidos: asentir, negar, señalar o recoger algo.)
const REACT_LOOK := 0   ## sigue a lo suyo y sólo gira la cabeza de reojo
const REACT_STOP := 1   ## se para y lo mira
const REACT_TURN := 2   ## se para y se gira de cuerpo entero hacia él
const REACT_GREET := 3  ## se para y le dedica un gesto breve
const REACT_WEIGHTS := [0.40, 0.24, 0.20, 0.16]

## Huecos de idle de la máquina de estados compartida. Cada ciudadano recibe en ellos CUATRO clips
## distintos y va pasando de uno a otro: quieto nunca se ve dos veces la misma postura.
const IDLE_SLOTS := ["idle", "idle_b", "idle_c", "idle_d"]

## Librería de animaciones horneada PARA EL RIG de los modelos que usa el juego (los Mixamo de
## "modelos 3d npcs"). No sirve cualquier librería: las poses guardan el roll del reposo del rig
## contra el que se hornearon, así que una librería hecha para otro reposo deja al ciudadano con
## el cuerpo girado 90° (mira al costado mientras camina). Ver NPCAnimationBaker.build_mixamo().
const SHARED_LIBRARY := "res://NPCs/Animations/Citizen_Animations_Mixamo.res"
## Librería del rig Auto-Rig Pro (City Folks / Urban Man). Se hornea con el mismo horneador a
## partir de los MISMOS clips ya validados, más la carrera y los giros del pack RPG.
const SHARED_LIBRARY_ARP := "res://NPCs/Animations/Citizen_Animations_ARP.res"
const LOCOMOTION_TREE := "res://NPCs/Animations/Citizen_Locomotion.tres"

const LAYER_WORLD := 1  # capa 1: terreno/edificios
const LAYER_NPC := 2    # capa 2: ciudadanos

## Clips disponibles por tipo de cuerpo y uso; cada ciudadano elige los suyos al azar.
##
## OJO: sólo entran caminatas e idles CIVILES. Se midió cada clip del pack y se descartaron
## tres que no lo eran (daban el aspecto de "llevar algo en las manos" o de estar de brazos
## cruzados): UAL "Walk_Carry" (brazos adelantados 0,19 m y codo 57°), "Walk_Formal" (los
## brazos apenas se mueven) e "Idle_FoldArms" (codo 103°). Tampoco se usa "Sprint", que con
## el paso de trote deja una zancada exagerada: para ir con prisa ya están "Jog_Fwd" y "Run".
const CLIP_POOLS := {
	## Ciudadanos del rig nuevo (City Folks / Urban Man): tienen a mano los 23 clips horneados
	## para ese rig, mezclando los dos sexos de origen y los giros y las carreras del pack RPG.
	"poly": {
		"idle": ["idle_m1", "idle_m2", "idle_u1", "idle_u3", "idle_f1", "idle_f2"],
		"walk": ["walk_m1", "walk_f1", "walk_u1"],
		"jog": ["jog_u1", "run_m1", "run_f1", "run_fwd_rpg"],
		"turn_l": ["turn_m1_l", "turn_f1_l", "turn90_l_rpg"],
		"turn_r": ["turn_m1_r", "turn_f1_r", "turn90_r_rpg"],
	},
	"male": {
		"idle": ["idle_m1", "idle_m2", "idle_u1", "idle_u3"],
		"walk": ["walk_m1", "walk_u1"],
		"jog": ["jog_u1", "run_m1"],
		"turn_l": ["turn_m1_l"],
		"turn_r": ["turn_m1_r"],
	},
	"female": {
		"idle": ["idle_f1", "idle_f2", "idle_u1", "idle_u3"],
		"walk": ["walk_f1", "walk_u1"],
		"jog": ["jog_u1", "run_f1"],
		"turn_l": ["turn_f1_l"],
		"turn_r": ["turn_f1_r"],
	},
}

## Clips que están horneados pero NO se usan, con el motivo medido. Están apuntados aquí para que no
## vuelvan a colarse solos al añadir animaciones nuevas a la librería (el sorteo se hace por
## categorías, no por listas a mano: ver POOL_OF_KIND).
const CLIPS_NOT_USED := {
	"idle_m3": "dura 0,67 s: es la transición entre dos idles, en bucle parece un tic",
	"run_u1": "es el Sprint de UAL1: 3,28 m/s de zancada, exagerada para un peatón",
	"sprint_rpg": "1,89 alturas de paso: carrera de atleta, no de transeúnte",
}

## Qué pool le toca a cada categoría ("kind" es el metadato con el que el horneador clasifica cada
## clip). Los clips se leen de la librería y se reparten con esta tabla, así que añadir animaciones
## nuevas al pack es hornearlas y ya entran solas en el sorteo, sin tocar este archivo.
const POOL_OF_KIND := {
	"idle": "idle", "social": "idle", "walk": "walk", "jog": "jog", "run": "jog",
	"turn": "turn", "react": "react",
}

@export_group("Modelo")
## Escena del modelo (los FBX de NPCs/Characters/PSX). Se instancia como hijo "Model".
@export var model_scene: PackedScene
@export_enum("male", "female") var body_type: String = "male"
## Sortea las piezas del cuerpo (cabeza, torso, manos, piernas y pies) para que no haya dos
## ciudadanos iguales. Se apaga para ver un modelo tal cual viene del paquete.
@export var vary_model_parts := true
## Monta la capa de decisión con planificador por objetivos (addon GdPlanningAI): el ciudadano
## decide pasear, descansar o acercarse a curiosear al jugador valorando coste y recompensa.
## El planificador por agente cuesta CPU, así que conviene activarlo sólo en los del nivel NEAR.
@export var use_goap := false

@export_group("Comportamiento")
## Zona (en coordenadas de mundo, XZ) por la que puede deambular.
@export var wander_area := Rect2(-28.0, -28.0, 56.0, 56.0)
## Tiempo quieto antes de elegir un nuevo destino.
@export var idle_time := Vector2(1.5, 6.0)
## Radio a partir del cual se considera que llegó al destino.
@export var arrival_distance := 0.7
## Viaje mínimo y máximo (metros) de cada trayecto.
@export var trip_distance := Vector2(6.0, 22.0)

@export_group("Personalidad")
## Si está activo, cada ciudadano sortea su propia personalidad al aparecer (no hay dos iguales).
@export var randomize_personality := true
## Multiplicador de velocidad; afecta al movimiento Y a la animación (los pies no patinan).
@export_range(0.6, 1.4) var move_scale := 1.0
## Probabilidad de ir con el paso acelerado (trote) en un trayecto.
@export_range(0.0, 1.0) var hurry_chance := 0.15
## Probabilidad de detenerse un momento a mitad de camino.
@export_range(0.0, 1.0) var pause_chance := 0.2
## Probabilidad de girar en el sitio (con su clip de giro) antes de retomar el paso.
@export_range(0.0, 1.0) var turn_chance := 0.15
## Probabilidad de mirar alrededor mientras espera.
@export_range(0.0, 1.0) var look_chance := 0.3
## Probabilidad de decidir quedarse quieto en vez de caminar (Idle -> Idle -> Walk).
@export_range(0.0, 1.0) var stay_chance := 0.15

@export_group("Reacciones al jugador")
## Distancia (metros) a la que un ciudadano se da cuenta del jugador.
@export var notice_distance := 6.5
## Por debajo de esta distancia se fijan en él aunque ya estuvieran dentro del radio.
@export var close_distance := 3.0
## Probabilidad de reaccionar al notarlo: el resto sigue a lo suyo (nada de reaccionar en masa).
@export_range(0.0, 1.0) var reaction_chance := 0.6
## Espera mínima y máxima (segundos) antes de poder volver a reaccionar.
@export var reaction_cooldown := Vector2(12.0, 28.0)
## Máximo que gira la cabeza sin mover el cuerpo (grados). Medido en juego: por encima de ~45°
## el giro deja de leerse como "mirar de reojo" y parece un cuello torcido, así que se recorta.
@export_range(15.0, 90.0) var head_yaw_limit := 42.0
## Máximo que sube o baja la mirada (grados).
@export_range(5.0, 45.0) var head_pitch_limit := 20.0
## Estabilizador de cabeza: tope (grados) y fuerza con que se quita el vaivén del cuello al andar.
@export_range(0.0, 45.0) var head_stab_tope := 18.0
@export_range(0.0, 1.0) var head_stab_fuerza := 0.75
## Altura del jugador a la que miran (cara/pecho).
@export var look_at_height := 1.5

@export_group("Movimiento")
## Giro máximo (radianes por segundo) al cambiar de dirección; evita giros bruscos.
@export_range(0.5, 12.0) var turn_rate := 3.5
## Distancia a la que empieza a frenar al llegar.
@export var brake_distance := 0.9
## Tiempo sin avanzar que dispara el recálculo de ruta (anti-atasco).
@export var stuck_timeout := 2.0

@onready var _agent: NavigationAgent3D = $NavigationAgent3D
@onready var _player: AnimationPlayer = $AnimationPlayer
@onready var _tree: AnimationTree = $AnimationTree

var state: State = State.IDLE
var activity: Activity = Activity.NEAR
var walk_speed := 1.2
var jog_speed := 2.5
var _idle_timer := 0.0
var _pause_timer := 0.0
var _arrive_timer := 0.0
var _turn_timer := 0.0
var _turn_duration := 0.5
var _turn_yaw := 0.0
var _variant_pending := false
var _variant_at := 0.0
var _face_yaw := 0.0
var _stuck_timer := 0.0
var _last_position := Vector3.ZERO
var _trip_start := Vector3.ZERO
var _trip_length := 1.0
var _pause_at := -1.0
var _turn_at := -1.0
var _hurrying := false
var _looking := false
var _look_yaw := 0.0
var _pending_freeze := false
var _freeze_timer := 0.0
var _playback: AnimationNodeStateMachinePlayback
var _active_clip := ""
var _idle_slot := ""   # hueco de idle en el que está ahora ("idle", "idle_b", "idle_c" o "idle_d")
# --- reacciones al jugador (Etapa 3)
var _player_node: Node3D
var _look_target: Node3D
var _look: NPCLookAt
var _estabiliza: NPCEstabilizaCabeza = null   # mantiene la cabeza mirando al frente al andar
var _watch := 0.0           # fundido de la mirada: 0 = no mira, 1 = mira al máximo
var _watching := false
var _notice_timer := 0.0    # comprobación escalonada y enfriamiento entre reacciones
var _noticed_inside := false
var _notice_hold := 0.0
var _react_timer := 0.0
var _react_kind := REACT_LOOK
var _was_walking := false
var _rng := RandomNumberGenerator.new()
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var _is_arp := false                 # el modelo es del rig nuevo (City Folks / Urban Man)

# --- Modo RED PEATONAL (ciudad) ---------------------------------------------
# Cuando el DirectorPeatones lo activa con activar_red(), el ciudadano deja de
# navegar libremente y se mueve SÓLO por las aristas de la red peatonal: veredas,
# pasos de peatones pintados, plazas, parques, paseo costero y arena. La calzada
# no es una superficie válida y el NavigationAgent3D no se usa en este modo.
var red: RedPeatonal = null          # la red del mapa generado
var director: Node = null            # DirectorPeatones (actividades y reservas)
var perfil := "paseo"                # "paseo" (ciudad) · "plaza" · "costa"
var puede_sentarse := false          # este ciudadano usa bancos
var puede_recostarse := false        # este ciudadano toma el sol en reposeras
var puede_arena := true              # el director lo apaga de noche
var _ruta := PackedInt32Array()      # ruta actual (vértices de la red)
var _ruta_i := 0                     # vértice al que se dirige ahora
var _largo_ruta := 0.0
var _desvio := 0.0                   # apartarse lateralmente para no chocar (m)
var _desvio_obj := 0.0
var _espera_peaton := 0.0            # bloqueo momentáneo por otro peatón (s)
# --- Postura (banco / reposera) ---------------------------------------------
var _postura := ""                   # "sentarse" | "recostarse"
var _postura_fase := ""              # acercarse | entrar | reposar | salir
var _postura_t := 0.0
var _postura_espera := 0.0           # cuánto dura el descanso
var _postura_punto := Vector3.ZERO   # el punto exacto del asiento
var _postura_yaw := 0.0
var _postura_tilt := 0.0             # inclinación del cuerpo sobre la reposera
var _postura_ref := -1               # plaza/reposera reservada en el director
var _salida_pendiente := false       # el director pidió levantarse (retirada)
var _posturas_ok := false            # la librería trae los clips de postura
var _dur_entrar := 1.3
var _dur_salir := 1.1
var _dur_sit_enter := 1.3
var _dur_sit_exit := 1.05
var _dur_lie_down := 1.55
var _dur_lie_up := 1.55
var _hablado := false

# --- Anti-atasco, evitación local y sincronía de la animación (2ª pasada) -----
# El avance se juzga por lo que el ciudadano se MUEVE de verdad (`_vel_real`), no por lo
# que quiere moverse: es lo que delata a un peatón clavado corriendo en el sitio.
var _vel_real := 0.0                 # velocidad real de este fotograma (m/s)
var _mov_ventana := 0.0              # metros movidos en la ventana de vigilancia
var _t_ventana := 0.0                # segundos de la ventana
var _bloqueos := 0                   # bloqueos reales seguidos (disparan la escalera de rescate)
var _reintentos := 0                 # trayectos cancelados seguidos sin avanzar bien
var _t_viaje := 0.0                  # tiempo del trayecto en curso
var _limite_viaje := 45.0            # tope de duración del trayecto (se calcula por ruta)
var _anim_frenada := false           # la locomoción está parada porque de verdad no se mueve
var _escala_tocada := false          # el speed_scale de la animación está corregido
var _evita_factor := 1.0             # frenado pedido por el director (gente/mobiliario delante)
var _desvio_max := 0.85              # tope de apartado lateral del tramo actual (según superficie)
var _desvio_pref := 0.6              # cuánto le gusta apartarse a este ciudadano (varía)
var _lado_pref := 1.0                # lado preferido al apartarse (estable por ciudadano)
var _bloqueo_t := 0.0                # paciencia acumulada en un bloqueo mutuo (s)
var _tramo_visto := -1               # último _ruta_i cuyo tope lateral ya se calculó
var _viajes_cancelados := 0          # trayectos cancelados por bloqueo (para las pruebas)


func _ready() -> void:
	_rng.randomize()
	collision_layer = LAYER_NPC
	collision_mask = LAYER_WORLD
	floor_snap_length = 0.4
	floor_max_angle = deg_to_rad(50.0)
	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	if randomize_personality:
		_randomize_personality()

	_spawn_model()
	_setup_animation()
	_setup_agent()
	_setup_goap()
	_enter_idle(true)


# ------------------------------------------------------------------ preparación

func _spawn_model() -> void:
	if model_scene == null:
		push_warning("NPCCitizen sin model_scene (nodo: %s)" % name)
		return
	var model := model_scene.instantiate()
	# El nombre debe ser exactamente "Model": las pistas de animación son "Model/Skeleton3D:hueso".
	model.name = "Model"
	# Antes de entrar al árbol: el AnimationPlayer propio del FBX se apaga AQUÍ porque cambiarle el
	# autoplay con el nodo ya dentro del árbol dispara un aviso del motor por cada ciudadano.
	_silenciar_animadores(model)
	# Los FBX descargados de Mixamo numeran el prefijo de los huesos según el personaje
	# (mixamorig1_, mixamorig7_, mixamorig12_...). La librería compartida de clips está horneada
	# con el prefijo canónico "mixamorig_": se renombran huesos Y bind names del Skin AQUÍ, antes de
	# entrar al árbol, para que las pistas enganchen y para que el chequeo de huesos del Skin lo vea
	# ya consistente (si se hiciera después, el motor avisa y la malla sale deforme).
	_normalizar_huesos(model)
	add_child(model)
	# Los packs nuevos (City Folks / Urban Man) cuelgan el esqueleto de un nodo intermedio y traen
	# las mallas separadas por pieza: se reestructura la jerarquía y se sortean las piezas para
	# que no haya dos ciudadanos iguales.
	var skeleton := model.find_child("Skeleton3D", true, false) as Skeleton3D
	_is_arp = NPCCitizenModel.is_arp_rig(skeleton)
	if _is_arp:
		# El color de la ropa se sortea aparte del cuerpo: así se combinan libremente (cualquier
		# cuerpo con cualquier ropa) y de ahí sale la variedad de aspecto.
		var plan := NPCCitizenModel.plan_variants(_rng) if vary_model_parts else {}
		NPCCitizenModel.prepare(model, _rng, vary_model_parts, NPCCitizenModel.PARTS, plan)
	# Acabado común a los dos rigs: brillo suave y perfilado (rim) para que el cuerpo se lea como
	# un volumen y no como una calcomanía plana. Se hace sobre copias, el pack queda intacto.
	NPCCitizenModel.polish_materials(model)
	_face_yaw = _detect_face_yaw(model)
	# NOTA: se probó a re-expresar la pose de cada hueso en el reposo del propio modelo para
	# arreglar los modelos de rig no estándar. No funciona: el horneador alinea por DIRECCIÓN de
	# hueso, no por marco de reposo, y esa corrección dejaba los brazos levantados. Esos modelos
	# se descartan en el director (MODELOS_DESCARTADOS) en vez de parchear la pose.
	_setup_look(model)


## Preparación de MODELOS de Mixamo.
##
## Los FBX de Mixamo nombran los huesos con un prefijo numerado por personaje: "mixamorig1_Hips",
## "mixamorig12_Head"... La librería compartida de clips (Citizen_Animations.res) tiene las pistas
## escritas con el prefijo canónico "mixamorig_", así que aquí se renombran los huesos del modelo a
## esa forma. Es idempotente (un nombre que ya es "mixamorig_X" se queda igual) y cuesta 65
## renombrados por ciudadano, una sola vez al cargar.
func _normalizar_huesos(model: Node) -> void:
	var sk := model.find_child("Skeleton3D", true, false) as Skeleton3D
	if sk == null:
		return
	for i in sk.get_bone_count():
		var nombre := _nombre_canonico(String(sk.get_bone_name(i)))
		if nombre != "":
			sk.set_bone_name(i, nombre)
	# CLAVE: cada MeshInstance3D trae un Skin con los NOMBRES de hueso del FBX original
	# ("mixamorig7_Hips"...). Si solo se renombra el esqueleto, el skin ya no encuentra sus huesos
	# ("Skin bind contains named bind ... but Skeleton3D has no bone by that name") y la malla se
	# dibuja deforme, con el cuerpo hundido. Se renombran los dos lados con la misma regla.
	for nodo in model.find_children("*", "MeshInstance3D", true, false):
		var piel: Skin = (nodo as MeshInstance3D).skin
		if piel == null:
			continue
		for b in piel.get_bind_count():
			var nombre := _nombre_canonico(piel.get_bind_name(b))
			if nombre != "":
				piel.set_bind_name(b, nombre)


## Devuelve el nombre canónico "mixamorig_X" si el nombre viene numerado ("mixamorig7_X"),
## o "" si ya es canónico o no es un hueso de Mixamo.
func _nombre_canonico(nombre: String) -> String:
	if not nombre.begins_with("mixamorig"):
		return ""
	var pos := nombre.find("_")
	if pos <= 0:
		return ""
	var canon := "mixamorig_" + nombre.substr(pos + 1)
	return canon if nombre != canon else ""


## Los FBX traen su propio AnimationPlayer ("Take 001" / "mixamo_com", una sola toma). Si quedara
## reproduciéndose, pelearía con el AnimationTree del ciudadano por la pose de los huesos.
func _silenciar_animadores(modelo: Node) -> void:
	for n in modelo.find_children("*", "AnimationPlayer", true, false):
		var ap: AnimationPlayer = n
		ap.stop()
		# El autoplay solo se puede limpiar sin ruido mientras el nodo no está en el árbol.
		if not ap.is_inside_tree():
			ap.autoplay = ""


## Prepara la mirada: busca el hueso de la cabeza y le cuelga el modificador que la gira.
## Si el modelo no tiene esqueleto ni cabeza (modelo raro), simplemente no mira y ya está.
func _setup_look(model: Node) -> void:
	var skeleton := model.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		return
	var head := -1
	for i in skeleton.get_bone_count():
		var bone_lower := String(skeleton.get_bone_name(i)).to_lower()
		# Rigs Mixamo: "mixamorig_Head". Rigs Auto-Rig Pro: "head.x".
		if bone_lower.ends_with("head") or bone_lower.begins_with("head"):
			head = i
			break
	if head < 0:
		return
	# Punto al que mira: se coloca en la cara del jugador cada vez que lo mira.
	_look_target = Node3D.new()
	_look_target.name = "LookTarget"
	_look_target.position = Vector3(0.0, look_at_height, 1.5)
	add_child(_look_target)
	# Estabilizador de cabeza: va ANTES de la mirada, para que la mirada (cuando toca) trabaje
	# sobre la pose ya estabilizada.
	_estabiliza = NPCEstabilizaCabeza.new()
	_estabiliza.name = "EstabilizaCabeza"
	_estabiliza.tope = head_stab_tope
	_estabiliza.fuerza = head_stab_fuerza
	skeleton.add_child(_estabiliza)
	_look = NPCLookAt.new()
	_look.name = "LookAt"
	_look.setup(String(skeleton.get_bone_name(head)), _look_target, head_yaw_limit, head_pitch_limit)
	skeleton.add_child(_look)


## Los tres rigs miran hacia +Z; se mide igualmente para que agregar modelos no rompa el giro.
func _detect_face_yaw(model: Node) -> float:
	var skeleton: Skeleton3D = model.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		return 0.0
	var left := _find_bone(skeleton, ["mixamorig_LeftArm", "arm_stretch.l", "B_L_UpperArm"])
	var right := _find_bone(skeleton, ["mixamorig_RightArm", "arm_stretch.r", "B_R_UpperArm"])
	if left < 0 or right < 0:
		return 0.0
	var axis := skeleton.get_bone_global_rest(left).origin - skeleton.get_bone_global_rest(right).origin
	axis.y = 0.0
	if axis.length_squared() < 0.0001:
		return 0.0
	var forward := axis.normalized().cross(Vector3.UP)
	return atan2(forward.x, forward.z)


func _setup_animation() -> void:
	var library_path := SHARED_LIBRARY_ARP if _is_arp else SHARED_LIBRARY
	var shared: AnimationLibrary = load(library_path)
	if shared == null:
		push_error("NPCCitizen: falta %s" % library_path)
		return
	var wanted: Dictionary = _select_clips(shared)
	var library := AnimationLibrary.new()
	for slot: String in wanted:
		if String(wanted[slot]) == "":
			continue
		var anim: Animation = shared.get_animation(wanted[slot])
		if anim == null:
			push_warning("NPCCitizen: falta el clip %s" % wanted[slot])
			continue
		library.add_animation(slot, anim)
	# Postura (banco/reposera): clips REALES horneados desde UAL1 (sentarse) y UAL2 (tumbarse).
	# Si la librería no los trae (p. ej. el jugador de prueba usa la suya), el ciudadano
	# simplemente no se sienta: nunca se reproduce un estado que no exista.
	_posturas_ok = true
	for slot2: String in ["sit_enter", "sit_idle", "sit_talk", "sit_exit", "lie_down", "lie_up"]:
		var anim2: Animation = shared.get_animation(slot2)
		if anim2 == null:
			_posturas_ok = false
			break
		library.add_animation(slot2, anim2)
	if _posturas_ok:
		_dur_sit_enter = (shared.get_animation("sit_enter") as Animation).length
		_dur_sit_exit = (shared.get_animation("sit_exit") as Animation).length
		_dur_lie_down = (shared.get_animation("lie_down") as Animation).length
		_dur_lie_up = (shared.get_animation("lie_up") as Animation).length
	# La librería por defecto ("") es la que resuelve el AnimationTree al pedir "idle"/"walk".
	_player.add_animation_library("", library)
	_tree.tree_root = load(LOCOMOTION_TREE)
	_tree.active = true
	_playback = _tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
	# La velocidad de avance sale de la animación -> pies sincronizados con el movimiento.
	walk_speed = float((shared.get_animation(wanted["walk"]) as Animation).get_meta("speed", 1.2))
	jog_speed = float((shared.get_animation(wanted["jog"]) as Animation).get_meta("speed", 2.5))
	# La escala personal afecta por igual al avance y a la animación: nunca patina.
	_player.speed_scale = move_scale
	_active_clip = String(wanted["walk"])


## Sortea el repertorio de clips de este ciudadano: qué clip le toca a cada nombre que pide la
## máquina de estados compartida. Se separa del montaje porque es la parte que interesa comprobar.
func _select_clips(shared: AnimationLibrary) -> Dictionary:
	var pool: Dictionary = _pools_from_library(shared)
	if not _is_arp:
		# Los modelos PSX de siempre tienen menos clips: se quedan con sus repertorios civiles por
		# sexo, ya medidos, y de la librería sólo toman las categorías nuevas (los gestos).
		var gender: Dictionary = CLIP_POOLS.get(body_type, CLIP_POOLS["male"])
		for key: String in ["idle", "walk", "jog", "turn_l", "turn_r"]:
			pool[key] = gender[key]
	var walk_clip: String = _pick_clip(pool["walk"])
	var jog_clip: String = _pick_clip(pool["jog"])
	if jog_clip == "":
		jog_clip = walk_clip
	# Cuatro huecos de idle DISTINTOS por ciudadano (la máquina de estados va pasando de uno a otro).
	var idles: Array = _pick_clips(pool["idle"], IDLE_SLOTS.size())
	while idles.size() < IDLE_SLOTS.size():
		idles.append(walk_clip)
	# Cada ciudadano entrega SUS clips a los mismos nombres: un solo recurso de máquina de estados
	# sirve para todos y aun así ninguno se mueve igual que otro.
	return {
		"idle": idles[0],
		"idle_b": idles[1],
		"idle_c": idles[2],
		"idle_d": idles[3],
		"walk": walk_clip,
		"jog": jog_clip,
		"turn_l": _pick_clip(pool["turn_l"]),
		"turn_r": _pick_clip(pool["turn_r"]),
		"react": _pick_clip(pool["react"]),
	}


func _pick_clip(options: Array, avoid := "") -> String:
	if options.is_empty():
		return ""
	if avoid != "" and options.size() > 1:
		var filtered: Array = []
		for option in options:
			if String(option) != avoid:
				filtered.append(option)
		if not filtered.is_empty():
			options = filtered
	return String(options[_rng.randi() % options.size()])


## Saca varios clips DISTINTOS (sin repetir) para los huecos de idle.
func _pick_clips(options: Array, count: int) -> Array:
	var result: Array = []
	var bag: Array = options.duplicate()
	while result.size() < count:
		if bag.is_empty():
			bag = options.duplicate()
			if bag.is_empty():
				return result
		var index := _rng.randi() % bag.size()
		result.append(String(bag[index]))
		bag.remove_at(index)
	return result


## Reparte los clips de la librería por categorías usando el metadato "kind" con el que se
## hornearon. Los clips sin categoría conocida y los de la lista de descartados se quedan fuera.
func _pools_from_library(shared: AnimationLibrary) -> Dictionary:
	var pools := {"idle": [], "walk": [], "jog": [], "turn_l": [], "turn_r": [], "react": []}
	for clip: String in shared.get_animation_list():
		if CLIPS_NOT_USED.has(clip):
			continue
		var anim: Animation = shared.get_animation(clip)
		var pool := String(POOL_OF_KIND.get(String(anim.get_meta("kind", "")), ""))
		if pool == "":
			continue
		if pool == "turn":
			# El lado del giro va en el nombre del clip ("_l" izquierda, "_r" derecha).
			pools["turn_l" if clip.contains("_l") else "turn_r"].append(clip)
		else:
			pools[pool].append(clip)
	return pools


## Pasa a otro hueco de idle, nunca el mismo que el de la vez anterior: un ciudadano que se para
## muchas veces no repite siempre la misma postura.
func _goto_idle_slot(avoid := "") -> void:
	if _playback == null:
		return
	var slot := _pick_clip(IDLE_SLOTS, avoid)
	if slot == "":
		return
	_idle_slot = slot
	_playback.travel(slot)


## Cada ciudadano sortea su propio carácter para que no se comporten como clones.
func _randomize_personality() -> void:
	move_scale = _rng.randf_range(0.85, 1.15)
	hurry_chance = _rng.randf_range(0.05, 0.3)
	pause_chance = _rng.randf_range(0.1, 0.35)
	turn_chance = _rng.randf_range(0.05, 0.3)
	look_chance = _rng.randf_range(0.15, 0.5)
	stay_chance = _rng.randf_range(0.05, 0.25)
	# Apartado al cruzarse con otro peatón: cada uno con su medida y su lado preferido.
	_desvio_pref = _rng.randf_range(0.45, 0.8)
	_lado_pref = 1.0 if _rng.randf() < 0.5 else -1.0
	# Quieto: unos descansan un momento y otros se quedan un buen rato, cada uno con su medida.
	idle_time = Vector2(_rng.randf_range(1.0, 3.5), _rng.randf_range(4.0, 9.0))
	# Reacciones: unos son muy sociables y otros pasan del jugador; también varía cuánto
	# pueden girar la cabeza, así que no todos reaccionan igual ni miran igual.
	reaction_chance = _rng.randf_range(0.35, 0.85)
	head_yaw_limit = _rng.randf_range(30.0, 42.0)
	head_pitch_limit = _rng.randf_range(14.0, 20.0)
	head_stab_fuerza = _rng.randf_range(0.65, 0.85)
	reaction_cooldown = Vector2(_rng.randf_range(10.0, 14.0), _rng.randf_range(22.0, 32.0))


func _setup_agent() -> void:
	_agent.radius = 0.4
	_agent.height = 1.7
	_agent.path_desired_distance = 0.4
	_agent.target_desired_distance = arrival_distance
	_agent.path_max_distance = 3.0
	# En modo red NO se usa el NavigationAgent3D: la evitación entre peatones la lleva el
	# director (aviso_peaton) y el movimiento va por las aristas de la red peatonal.
	_agent.avoidance_enabled = activity == Activity.NEAR and red == null
	_agent.neighbor_distance = 6.0
	_agent.max_neighbors = 6
	_agent.max_speed = _move_speed()
	_agent.velocity_computed.connect(_on_velocity_computed)
	_last_position = global_position
	_trip_start = global_position


# ------------------------------------------- API para el planificador (GdPlanningAI)

## Busca el primer hueso que exista de una lista de candidatos (cada rig usa sus nombres).
func _find_bone(skeleton: Skeleton3D, candidates: Array) -> int:
	for candidate: String in candidates:
		var index := skeleton.find_bone(candidate)
		if index >= 0:
			return index
	return -1


## El planificador opcional con GdPlanningAI quedó FUERA del proyecto (el addon ya no está
## instalado), así que el ciudadano decide siempre con su máquina de estados. `use_goap` se
## mantiene por compatibilidad con escenas antiguas, pero no monta nada.
func _setup_goap() -> void:
	if use_goap:
		push_warning("NPCCitizen (%s): use_goap ya no hace nada (falta el addon GdPlanningAI)" % name)


## ¿Está en condiciones de que el planificador le mande ir a ver al jugador?
func goap_can_seek() -> bool:
	return activity == Activity.NEAR and is_watching() and state != State.NOTICE and state != State.REACT


## ¿Va andando ahora mismo?
func goap_is_walking() -> bool:
	return state == State.WALK or state == State.PAUSE or state == State.TURN


## ¿Se quedó quieto esperando a alguien (o descansando)?
func goap_is_resting() -> bool:
	return state == State.IDLE or state == State.DECIDE


## ¿El planificador le mandó ir a ver al jugador? (ya no hay planificador: siempre false)
func goap_is_seeking() -> bool:
	return false


## Orden externa: pasear a un destino nuevo.
func wander_to_new_destination() -> bool:
	if state == State.NOTICE or state == State.REACT or state == State.POSTURA:
		return false
	if not _pick_destination():
		_enter_idle()
		return false
	_enter_walk()
	return true


## Orden externa: quedarse quieto un rato.
func rest_for(seconds: float) -> void:
	if state == State.POSTURA:
		return
	_enter_idle()
	_idle_timer = maxf(seconds, 0.5)


## ¿Hay jugador en la escena?
func has_player() -> bool:
	return _look_target != null


## Posición del jugador (la usa el planificador para valorar si merece la pena acercarse).
func player_position() -> Vector3:
	return _look_target.global_position if _look_target != null else Vector3.ZERO


## Orden externa: acercarse al jugador hasta quedarse a `stop_distance`. En modo red no se
## sale de la red peatonal: la calzada no es una superficie válida ni para curiosear.
func approach_player(stop_distance := 2.6) -> bool:
	if _look_target == null or red != null:
		return false
	var to_player := _look_target.global_position - global_position
	to_player.y = 0.0
	if to_player.length() <= stop_distance + 0.5:
		return false
	_agent.target_position = _look_target.global_position - to_player.normalized() * stop_distance
	if not _agent.is_target_reachable():
		return false
	_enter_walk()
	return true


# ------------------------------------------------------------------ estados

func _enter_idle(first := false) -> void:
	state = State.IDLE
	_looking = false
	_idle_timer = _rng.randf_range(0.6, 2.0) if first else _rng.randf_range(idle_time.x, idle_time.y)
	# En esperas largas se sortea una variación de idle (una sola vez por espera):
	# el ciudadano pasa a otro clip de idle y vuelve, así no se ve congelado.
	_variant_pending = _idle_timer > 3.0
	_variant_at = _idle_timer * 0.45
	if _rng.randf() < look_chance:
		_looking = true
		_look_yaw = rotation.y + _rng.randf_range(-1.1, 1.1)
	_goto_idle_slot(_idle_slot)


## Se queda quieto un momento (en mitad de un trayecto) y luego retoma el paso.
func _enter_pause(min_time := 1.0, max_time := 3.0) -> void:
	state = State.PAUSE
	_pause_timer = _rng.randf_range(min_time, max_time)
	_goto_idle_slot(_idle_slot)


## Estado de un solo fotograma: aquí se decide qué hacer después.
func _enter_decide() -> void:
	state = State.DECIDE


func _decide() -> void:
	# En la ciudad (modo red) decide entre sus actividades: pasear, sentarse en un
	# banco, tumbarse en una reposera o (de noche) sólo caminar por sitios seguros.
	if red != null:
		_decidir_red()
		return
	# A veces decide no moverse todavía (Idle -> Idle -> Walk).
	if _rng.randf() < stay_chance:
		_enter_idle()
		return
	if not _pick_destination():
		_enter_idle()
		return
	_enter_walk()


# ------------------------------------------------------------------ modo red peatonal

var _nodo_actual := -1
var _postura_punto_ini := Vector3.ZERO


## Activa el modo ciudad: a partir de aquí el ciudadano se mueve SÓLO por la red peatonal
## (veredas, cruces pintados, plazas, parques, paseo y arena) y puede recibir actividades del
## director (sentarse en un banco, tumbarse en una reposera...). La calzada no es válida.
func activar_red(red_mapa: RedPeatonal, jefe: Node, perfil_zona: String,
		sentarse: bool, recostarse: bool) -> void:
	red = red_mapa
	director = jefe
	perfil = perfil_zona
	puede_sentarse = sentarse
	puede_recostarse = recostarse
	_nodo_actual = red.nodo_mas_cercano(global_position,
			["acera", "plaza", "parque", "paseo", "arena"])
	if _nodo_actual >= 0:
		# Nace EN la red (nunca en la calzada ni dentro de un edificio).
		var p := red.pos(_nodo_actual)
		global_position = Vector3(p.x, global_position.y, p.z)
	_agent.avoidance_enabled = false


## Decide la siguiente actividad. El director lleva la cuenta de bancos y reposeras (reservas)
## y del ciclo día/noche (de noche no se toma el sol), así que aquí sólo se le pregunta.
func _decidir_red() -> void:
	if _rng.randf() < stay_chance:
		_enter_idle()
		return
	if director != null and director.has_method("pedir_actividad"):
		var orden: Dictionary = director.pedir_actividad(self)
		if not orden.is_empty():
			if _ir_a_postura(orden):
				return
			director.liberar(self)     # no hay ruta válida: se suelta la reserva
	if not _pick_destination():
		_enter_idle()
		return
	_enter_walk()


## Va al punto de una actividad: ruta por la red hasta el vértice más cercano al asiento y,
## luego, el último tramo a pie llano (delante de la reposera o dentro de la plaza/parque).
func _ir_a_postura(orden: Dictionary) -> bool:
	if not _posturas_ok:
		return false
	var destino: Vector3 = orden["punto"]
	var tipos: Array = ["arena"] if String(orden["tipo"]) == "reposera" else ["acera", "plaza", "parque"]
	var idx := red.nodo_mas_cercano(destino, tipos)
	if idx < 0:
		return false
	var desde := red.nodo_mas_cercano(global_position, [])
	if desde < 0:
		return false
	var r := red.ruta(desde, idx)
	if r.is_empty():
		return false
	_ruta = r
	_ruta_i = 1 if r.size() > 1 else 0
	_largo_ruta = red.longitud(r)
	_nodo_actual = desde
	state = State.POSTURA
	_postura = "sentarse" if String(orden["tipo"]) == "banco" else "recostarse"
	_postura_fase = "camino"
	_postura_t = 0.0
	_postura_punto = destino
	_postura_punto_ini = orden.get("punto_ini", destino)
	# La orden trae hacia dónde debe MIRAR el mundo; el modelo puede llevar su propio
	# desvío de cara (_face_yaw), así que se corrige aquí.
	_postura_yaw = float(orden["yaw"]) - _face_yaw
	_postura_tilt = float(orden.get("tilt", 0.0))
	_postura_ref = int(orden.get("ref", -1))
	_postura_espera = float(orden.get("espera", 30.0))
	_salida_pendiente = false
	_hablado = false
	# Vigilancia del avance: el trayecto al asiento también se vigila (si no puede llegar,
	# suelta la reserva y sigue con su vida en vez de quedarse empujando).
	_t_viaje = 0.0
	_bloqueos = 0
	_t_ventana = 0.0
	_mov_ventana = 0.0
	_desvio = 0.0
	_desvio_obj = 0.0
	_evita_factor = 1.0
	_tramo_visto = -1
	_limite_viaje = clampf(_largo_ruta / maxf(_move_speed(), 0.4) * 3.0, 20.0, 180.0)
	_set_locomotion()
	return true


## El director pide que se levante (retirada al acercarse la noche, o cualquier orden).
func levantar_ya() -> void:
	if state != State.POSTURA:
		return
	match _postura_fase:
		"camino", "acercarse":
			if director != null:
				director.liberar(self)
			_postura_ref = -1
			_enter_idle()
		"entrar":
			_salida_pendiente = true    # termina de sentarse/tumbarse y se levanta
		"reposar":
			_salir_postura()


func en_postura() -> bool:
	return state == State.POSTURA


## ¿Está bloqueado ahora mismo (intentando avanzar sin conseguirlo)? Para las pruebas.
func bloqueado() -> bool:
	return _bloqueos > 0


## Velocidad REAL de este ciudadano (m/s): con la animación de caminar puesta y esto a cero
## es el fallo de "correr en el sitio". Para las pruebas.
func velocidad_real() -> float:
	return _vel_real


## Trayectos que ha tenido que cancelar por bloqueo (para las pruebas de recuperación).
func viajes_cancelados() -> int:
	return _viajes_cancelados


## Foto del estado interno de la navegación (para diagnosticar bloqueos en las pruebas).
func resumen_debug() -> String:
	var t := tramo_red()
	var clase := String(t[2]) if t.size() >= 3 else "-"
	var objetivo := Vector3.ZERO
	var d := -1.0
	if red != null and not _ruta.is_empty():
		objetivo = _siguiente_punto()
		d = Vector2(objetivo.x, objetivo.z).distance_to(Vector2(global_position.x, global_position.z))
	return "estado=%d fase=%s ruta=%d/%d nodo=%d tramo=%s bloqueos=%d reintentos=%d espera=%.2f factor=%.2f desvio=%.2f/%.2f vel=%.2f obj=%s dist=%.2f" % [
		state, _postura_fase, _ruta_i, _ruta.size(), _nodo_actual, clase, _bloqueos, _reintentos,
		_espera_peaton, _evita_factor, _desvio, _desvio_obj, _vel_real, str(objetivo), d]


func fase_postura() -> String:
	return _postura_fase


func postura_actual() -> String:
	return _postura


## Tramo de red por el que va ahora mismo: [vértice A, vértice B, clase de arista]
## (para la auditoría: al cruzar, la clase es "cruce", el único sitio con calzada).
func tramo_red() -> Array:
	if red == null or _ruta.is_empty():
		return []
	var a: int = _ruta[maxi(_ruta_i - 1, 0)]
	var b: int = _ruta[mini(_ruta_i, _ruta.size() - 1)]
	return [a, b, red.arista(a, b)]


## ¿Tiene los clips de postura horneados? (el montaje puede fallar si a la librería le faltan)
func tiene_posturas() -> bool:
	return _posturas_ok


## Aviso del director sobre el resto de la gente y el mobiliario: apartarse lateralmente (con
## el tope que permite la superficie del tramo), frenar un poco o esperar un momento si alguien
## bloquea el paso. La espera TIENE TOPE y paciencia: si el bloqueo se mantiene, este ciudadano
## se aparta a su lado preferido y sigue, en vez de quedarse plantado esperando al otro.
## Nunca manda salir de la red.
func aviso_peaton(desvio: float, le_bloquean: bool, factor := 1.0) -> void:
	_desvio_obj = clampf(desvio, -_desvio_max, _desvio_max)
	_evita_factor = clampf(factor, 0.3, 1.0)
	if le_bloquean:
		# En un PASO DE PEATONES no se para jamás: dos que se cruzan en la calzada y se
		# quedan esperándose serían lo peor de todo. Se cruza, apartándose un poco, y ya.
		var t := tramo_red()
		if t.size() >= 3 and String(t[2]) == "cruce":
			le_bloquean = false
			_espera_peaton = 0.0
	if not le_bloquean:
		_bloqueo_t = maxf(_bloqueo_t - 0.2, 0.0)
		_espera_peaton = minf(_espera_peaton, 0.8)   # tope duro: nunca una espera eterna
		return
	_bloqueo_t += 0.2                       # el director avisa cada 0,2 s
	if _bloqueo_t <= 1.5:
		_espera_peaton = maxf(_espera_peaton, 0.25)
	else:
		# Enfrentamiento que no se resuelve: se aparta a SU lado y echa a andar.
		_espera_peaton = 0.0
		_desvio_obj = _lado_pref * maxf(_desvio_pref, 0.6)
	_espera_peaton = minf(_espera_peaton, 0.8)    # tope duro: nunca una espera eterna


## Lado preferido de este ciudadano para apartarse (+1 o -1): la mitad se aparta a un lado y
## la otra mitad al otro, así dos que se cruzan no eligen siempre el mismo y no se empujan.
func lado_preferido() -> float:
	return _lado_pref


## Cuánto le gusta apartarse (metros): cada uno con su medida, para que no parezcan clones.
func apartado_pref() -> float:
	return _desvio_pref


## Empieza el clip de salida (levantarse) y devuelve el cuerpo a su sitio.
func _salir_postura() -> void:
	_postura_fase = "salir"
	_postura_t = 0.0
	_salida_pendiente = false
	if _playback:
		_playback.travel("sit_exit" if _postura == "sentarse" else "lie_up")
		_dur_salir = _dur_sit_exit if _postura == "sentarse" else _dur_lie_up


## Fin de la postura: suelta la reserva y vuelve a la vida normal (quieto y a decidir).
func _terminar_postura() -> void:
	if director != null:
		director.liberar(self)
	_postura_ref = -1
	_postura = ""
	_postura_fase = ""
	rotation.x = 0.0
	_enter_idle()


## Velocidad del estado POSTURA: caminar por la red hasta el asiento, acercarse, sentarse o
## tumbarse (con su clip real), esperar el tiempo del descanso y levantarse.
func _postura_desired_velocity(delta: float) -> Vector3:
	_postura_t += delta
	match _postura_fase:
		"camino":
			var fin := _red_llegada()
			if fin:
				_postura_fase = "acercarse"
				_postura_t = 0.0
				return Vector3.ZERO
			return _red_velocidad(delta)
		"acercarse":
			var objetivo := _postura_punto_ini
			var offset := objetivo - global_position
			offset.y = 0.0
			if offset.length() <= 0.25:
				_postura_fase = "entrar"
				_postura_t = 0.0
				if _playback:
					_playback.travel("sit_enter" if _postura == "sentarse" else "lie_down")
				return Vector3.ZERO
			var direction := offset.normalized()
			var speed := _move_speed()
			if offset.length() < 0.9:
				speed *= maxf(offset.length() / 0.9, 0.25)
			var facing := Vector3(sin(rotation.y + _face_yaw), 0.0, cos(rotation.y + _face_yaw))
			speed *= clampf(facing.dot(direction), 0.0, 1.0)
			return direction * speed
		"entrar":
			# Se gira al asiento y se acompaña con el clip; en la reposera además se
			# pasa del punto de pie al punto tumbado, para no dar ningún salto.
			rotation.y = lerp_angle(rotation.y, _postura_yaw, 1.0 - exp(-4.0 * delta))
			var f := clampf(_postura_t / maxf(_dur_entrar, 0.01), 0.0, 1.0)
			if _postura == "recostarse":
				global_position = _postura_punto_ini.lerp(_postura_punto, f)
				rotation.x = _postura_tilt * f
			if _postura_t >= _dur_entrar + 0.05:
				_postura_fase = "reposar"
				_postura_t = 0.0
				if _playback and _postura == "sentarse":
					_playback.travel("sit_idle")
				if _salida_pendiente:
					_salir_postura()
			return Vector3.ZERO
		"reposar":
			# La postura manda: mientras descansa NO se le aplica el giro de caminata (ése era el
			# fallo de los que se sentaban al revés: seguían girando hacia su rumbo de llegada y
			# acababan mirando al respaldo o de costado en la reposera).
			rotation.y = lerp_angle(rotation.y, _postura_yaw, 1.0 - exp(-6.0 * delta))
			if _postura == "recostarse":
				rotation.x = _postura_tilt
			# Mientras descansa puede cambiar a "hablando sentado" una vez (vida en el banco).
			if not _hablado and _postura == "sentarse" and _postura_t > _postura_espera * 0.5:
				_hablado = true
				if _rng.randf() < 0.45 and _playback:
					_playback.travel("sit_talk")
			if _postura_t >= _postura_espera or _salida_pendiente:
				_salir_postura()
			return Vector3.ZERO
		"salir":
			var f2 := clampf(_postura_t / maxf(_dur_salir, 0.01), 0.0, 1.0)
			if _postura == "recostarse":
				global_position = _postura_punto.lerp(_postura_punto_ini, f2)
				rotation.x = _postura_tilt * (1.0 - f2)
			if _postura_t >= _dur_salir + 0.05:
				_postura_fase = ""
				_terminar_postura()
			return Vector3.ZERO
	return Vector3.ZERO


## ¿Se acabó la ruta de red? (llegó al punto al que apunta de verdad, contando el apartado
## lateral: si se mide contra el vértice a secas, un peatón apartado nunca "llega").
func _red_llegada() -> bool:
	if _ruta.is_empty():
		return true
	if _ruta_i < _ruta.size() - 1:
		return false
	var objetivo := _siguiente_punto()
	return Vector2(objetivo.x, objetivo.z).distance_to(Vector2(global_position.x, global_position.z)) <= 0.7


## Siguiente vértice al que apunta (con el apartado lateral para no chocar con otro peatón).
func _siguiente_punto() -> Vector3:
	while _ruta_i < _ruta.size() - 1:
		var p := red.pos(_ruta[_ruta_i])
		if Vector2(p.x, p.z).distance_to(Vector2(global_position.x, global_position.z)) < 0.9:
			_ruta_i += 1
		else:
			break
	_nodo_actual = _ruta[mini(_ruta_i, _ruta.size() - 1)] if not _ruta.is_empty() else _nodo_actual
	var objetivo := red.pos(_ruta[mini(_ruta_i, _ruta.size() - 1)])
	# Apartarse lateralmente (hasta ±0,85 m): sigue dentro de la vereda de 3 m.
	if absf(_desvio) > 0.02 and _ruta_i < _ruta.size():
		var prev := red.pos(_ruta[maxi(_ruta_i - 1, 0)])
		var dir := objetivo - prev
		dir.y = 0.0
		if dir.length_squared() > 0.0001:
			var perp := Vector3(dir.z, 0.0, -dir.x).normalized()
			objetivo += perp * _desvio
	return objetivo


## Velocidad de avance por la red (equivalente a _walk_desired_velocity, sin NavigationAgent).
func _red_velocidad(delta: float) -> Vector3:
	# El apartado sigue a lo que pide el director (gente y mobiliario) con una respuesta
	# rápida: si se tardase mucho en abrirse, el peatón ya estaría dentro del banco.
	_desvio = move_toward(_desvio, _desvio_obj, delta * 2.2)
	_tope_del_tramo()
	var objetivo := _siguiente_punto()
	var offset := objetivo - global_position
	offset.y = 0.0
	# Espera corta por otro peatón. El director la pide porque alguien bloquea el paso y
	# tiene TOPE (el ciudadano nunca se queda plantado esperando indefinidamente).
	if _espera_peaton > 0.0:
		_espera_peaton = maxf(_espera_peaton - delta, 0.0)
		return Vector3.ZERO
	if offset.length_squared() < 0.0001:
		_ruta_i = mini(_ruta_i + 1, _ruta.size() - 1)
		return Vector3.ZERO
	var direction := offset.normalized()
	var speed := _move_speed() * _evita_factor
	var facing := Vector3(sin(rotation.y + _face_yaw), 0.0, cos(rotation.y + _face_yaw))
	var mira := facing.dot(direction)
	# MIRA AL REVÉS (o casi): se gira en el sitio con su clip de giro y luego retoma. Antes
	# esto sólo recortaba la velocidad, y como el giro dependía del propio avance, el peatón
	# se quedaba clavado corriendo en el sitio: era el fallo principal.
	if mira < 0.25:
		if state == State.WALK:
			_enter_turn()
		return Vector3.ZERO
	speed *= clampf(mira, 0.0, 1.0)
	# Sucesos de mitad de trayecto (igual que en el modo libre), sólo en la ciudad.
	if _ruta_i == 1 and _largo_ruta > 8.0:
		var recorrido := _largo_ruta - red.pos(_ruta[_ruta.size() - 1]).distance_to(global_position)
		var progreso := clampf(recorrido / maxf(_largo_ruta, 0.5), 0.0, 1.0)
		if _pause_at > 0.0 and progreso >= _pause_at:
			_pause_at = -1.0
			_enter_pause(1.0, 3.0)
			return Vector3.ZERO
		if _turn_at > 0.0 and progreso >= _turn_at and activity == Activity.NEAR:
			_turn_at = -1.0
			_enter_turn()
			return Vector3.ZERO
	return direction * speed


## Tope de apartado lateral según la superficie del tramo. La calle de arena es una sola
## línea entre el mobiliario y el agua, así que ahí apenas hay sitio para esquivar; en la
## acera el tope deja al peatón dentro de los 3 m de vereda; en plaza y parque hay más.
func _tope_del_tramo() -> void:
	if _ruta_i == _tramo_visto:
		return
	_tramo_visto = _ruta_i
	var t := tramo_red()
	var clase := String(t[2]) if t.size() >= 3 else "acera"
	match clase:
		"arena": _desvio_max = 0.35
		"cruce": _desvio_max = 0.55          # dentro del paso pintado, no salirse de las rayas
		"paseo": _desvio_max = 0.8
		"plaza", "parque": _desvio_max = 1.2
		_: _desvio_max = 0.85                # acera


## Avance en MODO RED: se mueve en horizontal y la altura la marca el propio grafo,
## interpolando la cota de los dos vértices del tramo actual (los dos llevan la cota
## real de la superficie: acera, plaza, parque, paseo o arena). Así el peatón nunca
## depende del motor de colisiones para mantenerse en pie.
func _avanzar_por_red(desired: Vector3, delta: float) -> void:
	var plano := Vector2(desired.x, desired.z)
	if plano.length_squared() > 0.000001:
		var p := global_position
		p.x += plano.x * delta
		p.z += plano.y * delta
		p.y = _altura_red(p)
		global_position = p
	# La velocidad se publica igual (la usan el fundido de animación y los avisos).
	velocity = Vector3(plano.x, 0.0, plano.y)


## Cota del suelo en un punto de la red. En el último tramo a pie (acercarse al banco
## o a la reposera) se pasa suavemente a la cota exacta del punto de la actividad.
func _altura_red(p: Vector3) -> float:
	if state == State.POSTURA and _postura_fase == "acercarse":
		var d := Vector2(_postura_punto_ini.x - p.x, _postura_punto_ini.z - p.z).length()
		if d < 2.5:
			return lerpf(_altura_tramo(p), _postura_punto_ini.y, 1.0 - d / 2.5)
	return _altura_tramo(p)


## Altura interpolada entre los dos vértices del tramo actual.
func _altura_tramo(p: Vector3) -> float:
	if red == null or _ruta.is_empty():
		return global_position.y
	var a := red.pos(_ruta[maxi(_ruta_i - 1, 0)])
	var b := red.pos(_ruta[mini(_ruta_i, _ruta.size() - 1)])
	var ab := Vector2(b.x - a.x, b.z - a.z)
	var t := 0.0
	var largo := ab.length_squared()
	if largo > 0.0001:
		t = clampf(Vector2(p.x - a.x, p.z - a.z).dot(ab) / largo, 0.0, 1.0)
	return lerpf(a.y, b.y, t)


func _enter_walk() -> void:
	state = State.WALK
	_stuck_timer = 0.0
	_last_position = global_position
	_trip_start = global_position
	_trip_length = maxf(_largo_ruta if red != null else global_position.distance_to(_agent.target_position), 0.5)
	_hurrying = _rng.randf() < hurry_chance
	# Vigilancia del avance y apartado: cada trayecto empieza limpio.
	_t_viaje = 0.0
	_bloqueos = 0
	_t_ventana = 0.0
	_mov_ventana = 0.0
	_desvio = 0.0
	_desvio_obj = 0.0
	_evita_factor = 1.0
	_tramo_visto = -1
	# Tope de tiempo: el triple de lo que tardaría a su paso (con un mínimo y un máximo).
	_limite_viaje = clampf(_trip_length / maxf(_move_speed(), 0.4) * 3.0, 20.0, 180.0)
	# Sucesos del trayecto (como mucho uno de cada tipo), en un punto intermedio del camino.
	_pause_at = _rng.randf_range(0.3, 0.7) if _rng.randf() < pause_chance else -1.0
	_turn_at = _rng.randf_range(0.2, 0.6) if _rng.randf() < turn_chance else -1.0
	_set_locomotion()
	_agent.max_speed = _move_speed()


func _resume_walk() -> void:
	state = State.WALK
	_set_locomotion()


func _enter_arrive() -> void:
	state = State.ARRIVE
	_arrive_timer = _rng.randf_range(0.2, 0.8)
	_goto_idle_slot(_idle_slot)


## Giro en el sitio con su propio clip (Caminar -> Girar -> Caminar) antes de retomar el paso.
func _enter_turn() -> void:
	var next := _siguiente_punto() if red != null else _agent.get_next_path_position()
	var offset := next - global_position
	offset.y = 0.0
	if offset.length_squared() < 0.0001:
		_resume_walk()
		return
	state = State.TURN
	_turn_timer = 0.0
	_turn_yaw = atan2(offset.x, offset.z) - _face_yaw
	var yaw_step := wrapf(_turn_yaw - rotation.y, -PI, PI)
	_turn_duration = clampf(absf(yaw_step) / 3.0, 0.35, 0.9)
	if _playback:
		# El signo se midió sobre el clip: "turn_l" es el que acaba el cuerpo girado a la izquierda,
		# y girar hacia la izquierda es restar al ángulo (rotación.y positiva gira a la derecha).
		_playback.travel("turn_r" if yaw_step > 0.0 else "turn_l")


func _set_locomotion() -> void:
	if _playback:
		_playback.travel("jog" if _hurrying else "walk")


## Busca un destino alcanzable. En modo red, el destino es siempre un vértice de la red
## peatonal (nunca un punto libre de la calzada) y la ruta se calcula sobre el grafo.
func _pick_destination() -> bool:
	if red != null:
		return _red_destino()
	var map := _agent.get_navigation_map()
	for attempt in 14:
		var point := Vector3(
			_rng.randf_range(wander_area.position.x, wander_area.end.x),
			0.0,
			_rng.randf_range(wander_area.position.y, wander_area.end.y)
		)
		# 1) el punto debe caer sobre la malla de navegación (no en un tejado ni en el vacío)
		var closest := NavigationServer3D.map_get_closest_point(map, point)
		if point.distance_to(closest) > 2.0:
			continue
		# 2) longitud de viaje razonable (ni dos pasos ni cruzar toda la ciudad)
		var distance := closest.distance_to(global_position)
		if distance < trip_distance.x or distance > trip_distance.y:
			continue
		# 3) debe existir camino hasta él (si está en una isla inalcanzable, se descarta)
		if not _is_reachable(map, closest):
			continue
		_agent.target_position = closest
		return true
	return false


func _is_reachable(map: RID, target: Vector3) -> bool:
	var path := NavigationServer3D.map_get_path(map, global_position, target, true)
	if path.size() < 2:
		return false
	return (path[path.size() - 1] as Vector3).distance_to(target) < 1.5


## Destino aleatorio DENTRO de la red peatonal, según el perfil del ciudadano y con un largo
## de viaje razonable. Se sortea entre vértices válidos y se comprueba que exista ruta (el
## grafo sólo tiene aristas de vereda, cruce pintado, plaza, parque, paseo y arena).
func _red_destino() -> bool:
	var tipos: Array = []
	var minimo := 20.0
	var maximo := 85.0
	match perfil:
		"plaza":
			tipos = ["plaza", "parque", "acera"]
			minimo = 9.0
			maximo = 45.0
		"costa":
			tipos = ["paseo", "arena", "acera"] if puede_arena else ["paseo", "acera"]
			minimo = 18.0
			maximo = 95.0
		_:
			tipos = ["acera", "plaza", "parque"]
	if red.nodos_de_tipo(tipos).is_empty():
		tipos = ["acera"]
	if red.nodos_de_tipo(tipos).is_empty():
		return false
	var desde := red.nodo_mas_cercano(global_position, [])
	if desde < 0:
		return false
	var candidatos: Array = red.nodos_de_tipo(tipos)
	for _intento in 16:
		var idx: int = candidatos[_rng.randi() % candidatos.size()]
		var d := Vector2(red.pos(idx).x, red.pos(idx).z).distance_to(
				Vector2(global_position.x, global_position.z))
		if d < minimo or d > maximo:
			continue
		var r := red.ruta(desde, idx)
		if r.size() < 2:
			continue
		_ruta = r
		_ruta_i = 1
		_largo_ruta = red.longitud(r)
		_nodo_actual = desde
		return true
	return false


func _move_speed() -> float:
	var base := jog_speed if _hurrying else walk_speed
	return base * move_scale


# ------------------------------------------------------------------ física

func _physics_process(delta: float) -> void:
	# Congelado (nivel lejano): se deja terminar el fundido hacia idle y se apaga la animación.
	if _pending_freeze:
		_freeze_timer -= delta
		if _freeze_timer <= 0.0:
			_pending_freeze = false
			_player.process_mode = Node.PROCESS_MODE_DISABLED
			set_physics_process(false)
			return
	if not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = minf(velocity.y, 0.0)

	# Reacciones sociales (mirar al jugador): fundido de la mirada y, si toca, cambio de estado.
	_update_reactions(delta)

	var desired := Vector3.ZERO
	match state:
		State.IDLE:
			_update_looking(delta)
			_idle_timer -= delta
			if _variant_pending and _idle_timer <= _variant_at:
				_variant_pending = false
				# Cambia de postura a mitad de la espera (y nunca a la misma): quieto se le ve
				# moverse sin llegar a caminar.
				_goto_idle_slot(_idle_slot)
			if _idle_timer <= 0.0:
				_enter_decide()
		State.DECIDE:
			_decide()
		State.WALK:
			desired = _walk_desired_velocity(delta)
			if state != State.WALK:
				desired = Vector3.ZERO
		State.PAUSE:
			_pause_timer -= delta
			if _pause_timer <= 0.0:
				_resume_walk()
		State.TURN:
			desired = _turn_desired_velocity(delta)
		State.ARRIVE:
			_arrive_timer -= delta
			if _arrive_timer <= 0.0:
				_enter_idle()
		State.NOTICE:
			# Se ha dado cuenta del jugador: si iba andando sigue andando (mirando de reojo),
			# y al cabo de un instante decide qué hacer.
			if _was_walking:
				desired = _walk_desired_velocity(delta)
				if state != State.NOTICE:
					desired = Vector3.ZERO
			_notice_hold -= delta
			if _notice_hold <= 0.0 and state == State.NOTICE:
				_enter_react()
		State.REACT:
			if _react_kind == REACT_LOOK and _was_walking:
				# Sólo mira de reojo: sigue su camino sin pararse.
				desired = _walk_desired_velocity(delta)
				if state != State.REACT:
					desired = Vector3.ZERO
			else:
				desired = _react_desired_velocity(delta)
		State.POSTURA:
			desired = _postura_desired_velocity(delta)

	var antes := global_position
	if red != null:
		# MODO RED: el suelo es el propio grafo. Cada vértice lleva la cota real del
		# paseo, la acera, la plaza o la arena, así que el peatón avanza en horizontal
		# y la altura se interpola entre los dos vértices del tramo: no depende del
		# motor de colisiones (ni se cae por un hueco de collider ni atraviesa nada) y
		# sólo puede pisar las superficies que la red tiene por buenas.
		_avanzar_por_red(desired, delta)
	elif _agent.avoidance_enabled:
		# La velocidad segura llega por _on_velocity_computed (evita chocar con otros NPCs).
		_agent.set_velocity(desired)
	else:
		_apply_horizontal(desired)
		move_and_slide()

	# Velocidad REAL (lo recorrido de verdad, no lo deseado): gobierna la animación y es
	# la que delata un bloqueo contra mobiliario, otro peatón o un objetivo inalcanzable.
	if delta > 0.0001:
		var recorrido := global_position - antes
		recorrido.y = 0.0
		_vel_real = recorrido.length() / delta

	# Mirar SIEMPRE hacia donde se quiere ir. Si `desired` es cero (todavía no puede
	# avanzar porque mira al revés o está frenado), se gira igualmente hacia el objetivo
	# real: sin esto, un peatón que mira al revés no giraba nunca (el giro dependía del
	# propio avance) y se quedaba clavado con la animación de caminar.
	# Sentado o tumbado, la orientación la lleva la fase de postura: si se le aplica el giro de
	# caminata hacia su rumbo de llegada, el cuerpo queda de costado respecto al banco/reposera.
	if state != State.TURN and state != State.POSTURA:
		_update_facing(delta, desired if desired.length_squared() > 0.0001 else _direccion_objetivo())
	_vigilar_avance(delta)


## Gira despacio hacia el lado que le tocó mirar mientras espera.
func _update_looking(delta: float) -> void:
	if not _looking:
		return
	rotation.y = lerp_angle(rotation.y, _look_yaw, 1.0 - exp(-1.2 * delta))
	if absf(wrapf(_look_yaw - rotation.y, -PI, PI)) < 0.05:
		_looking = false


func _turn_desired_velocity(delta: float) -> Vector3:
	_turn_timer += delta
	rotation.y = lerp_angle(rotation.y, _turn_yaw, 1.0 - exp(-8.0 * delta))
	if _turn_timer >= _turn_duration:
		_resume_walk()
	return Vector3.ZERO


func _walk_desired_velocity(delta: float) -> Vector3:
	# En la ciudad, el avance va por la red peatonal (nunca por la calzada).
	if red != null:
		if _red_llegada():
			_enter_arrive()
			return Vector3.ZERO
		return _red_velocidad(delta)
	var target := _agent.get_next_path_position()
	var offset := target - global_position
	offset.y = 0.0
	var remaining := global_position.distance_to(_agent.target_position)
	if _agent.is_navigation_finished() or remaining <= arrival_distance:
		_enter_arrive()
		return Vector3.ZERO
	# Sucesos de mitad de trayecto: pararse un momento o girar en el sitio (Idle/Walk -> Turn).
	var progress := clampf(1.0 - remaining / _trip_length, 0.0, 1.0)
	if _pause_at > 0.0 and progress >= _pause_at:
		_pause_at = -1.0
		_enter_pause(1.0, 3.0)
		return Vector3.ZERO
	if _turn_at > 0.0 and progress >= _turn_at and activity == Activity.NEAR:
		_turn_at = -1.0
		_enter_turn()
		return Vector3.ZERO
	if offset.length_squared() < 0.0001:
		return Vector3.ZERO
	var direction := offset.normalized()
	# Frena sólo en el último tramo; el resto del recorrido va a la velocidad de la animación.
	var speed := _move_speed()
	if remaining < brake_distance:
		speed *= maxf(remaining / brake_distance, 0.35)
	# Al elegir un destino, el NPC gira suavemente: mientras no mire hacia donde avanza
	# reduce la velocidad, así nunca se desplaza de espaldas ni en diagonal forzada.
	var facing := Vector3(sin(rotation.y + _face_yaw), 0.0, cos(rotation.y + _face_yaw))
	speed *= clampf(facing.dot(direction), 0.0, 1.0)
	return direction * speed


## VIGILANCIA DEL AVANCE REAL (anti-atasco).
##
## Cada 1,2 s se compara lo que el ciudadano HA RECORRIDO con lo que debería haber recorrido
## a su velocidad de paso. Si va muy por debajo, es un bloqueo de verdad (mobiliario, otro
## peatón, un borde de la zona o un objetivo inalcanzable) y se aplica una escalera de rescate.
## Además, si de verdad no se mueve, se FRENA la animación de locomoción: nunca se ve a nadie
## corriendo en el sitio, ni siquiera durante el medio segundo que dura el rescate.
func _vigilar_avance(delta: float) -> void:
	var circulando := state == State.WALK \
			or (state == State.POSTURA and (_postura_fase == "camino" or _postura_fase == "acercarse")) \
			or ((state == State.NOTICE or state == State.REACT) and _was_walking)
	if not circulando:
		_mov_ventana = 0.0
		_t_ventana = 0.0
		_bloqueos = 0
		_restaurar_escala()
		return
	_t_viaje += delta
	_t_ventana += delta
	_mov_ventana += _vel_real * delta
	# --- La animación sigue al avance real (pies sincronizados, nada de patinar) ---
	if _vel_real < walk_speed * 0.25:
		if not _anim_frenada:
			_anim_frenada = true
			if _playback != null and not IDLE_SLOTS.has(_playback.get_current_node()):
				_goto_idle_slot(_idle_slot)
	elif _vel_real > walk_speed * 0.35 and _anim_frenada:
		_anim_frenada = false
		_set_locomotion()
	if _anim_frenada:
		_restaurar_escala()
	elif walk_speed > 0.1:
		# Un peatón al que el director le ha pedido frenar (o que avanza despacio porque
		# está girando) reproduce sus pasos más despacio: así los pies no patinan nunca.
		_player.speed_scale = clampf(move_scale * _vel_real / walk_speed, 0.3, 1.5 * move_scale)
		_escala_tocada = true
	# --- Juicio de bloqueo ---
	if _t_ventana < 0.9:
		return
	var vel_media := _mov_ventana / _t_ventana
	_t_ventana = 0.0
	_mov_ventana = 0.0
	if _move_speed() > 0.2 and vel_media < _move_speed() * 0.35:
		_bloqueos += 1
		_resolver_bloqueo()
	else:
		_bloqueos = 0
		# Si lleva un rato avanzando de verdad, los reintentos anteriores ya no cuentan.
		if _t_viaje > 4.0:
			_reintentos = 0
	# Un trayecto no puede eternizarse: si se pasa del tope, se abandona con calma.
	if _t_viaje > _limite_viaje:
		_abandonar_viaje("se le acabó el tiempo del trayecto")


## Devuelve la escala de animación a su valor normal (el que le tocó por personalidad).
func _restaurar_escala() -> void:
	if _escala_tocada:
		_player.speed_scale = move_scale
		_escala_tocada = false


## Escalera de rescate ante un bloqueo REAL. Nunca es infinita: cada paso o desbloquea o
## pasa al siguiente, y al final el trayecto se cancela y se elige otro destino.
func _resolver_bloqueo() -> void:
	if _bloqueos <= 1:
		# 1) Se acabaron las esperas: se aparta a SU lado y echa a andar. Lo más común es
		#    que llevara un rato esperando a alguien que no se aparta.
		_desvio = 0.0
		_desvio_obj = _lado_pref * maxf(_desvio_pref, 0.65)
		_evita_factor = 1.0
		_espera_peaton = 0.0
		_bloqueo_t = 0.0
		_reapuntar()
		return
	if _bloqueos == 2:
		# 2) Esperar un momento (con su idle): puede ser otro peatón, o gente rodeando el
		#    mobiliario. Es lo que hace una persona antes de buscarle la vuelta.
		_enter_pause(0.7, 1.5)
		return
	if _bloqueos == 3:
		# 3) Recalcular la ruta al MISMO destino desde donde está ahora (A* sobre la red):
		#    el tramo anterior puede haber quedado tapado por otro peatón.
		if red != null and not _ruta.is_empty():
			var destino := red.pos(_ruta[_ruta.size() - 1])
			var desde := red.nodo_mas_cercano(global_position, [])
			var hasta := red.nodo_mas_cercano(destino, [])
			var r := red.ruta(desde, hasta)
			if r.size() >= 2:
				_ruta = r
				_ruta_i = 1 if r.size() > 1 else 0
				_largo_ruta = red.longitud(r)
				_tramo_visto = -1
				_bloqueos = 0
				return
		_cancelar_viaje()
		return
	# 4) Ya ha fallado demasiadas veces en el mismo sitio: se cancela y se busca otra cosa.
	_cancelar_viaje()


## Vuelve a apuntar hacia el objetivo real (sin cambiar de destino) y retoma el paso.
func _reapuntar() -> void:
	var objetivo := _direccion_objetivo()
	if objetivo.length_squared() < 0.0001:
		return
	var yaw := atan2(objetivo.x, objetivo.z) - _face_yaw
	rotation.y = lerp_angle(rotation.y, yaw, 0.8)   # media vuelta decidida, sin clip
	if state == State.PAUSE:
		_resume_walk()


## Cancela el trayecto en curso (soltando la reserva si iba a un banco o a una reposera) y
## elige otro destino. Si ya van varios seguidos, se queda quieto un rato largo: mejor
## parado y creíble que empujando contra algo durante minutos.
func _cancelar_viaje() -> void:
	_reintentos += 1
	_viajes_cancelados += 1
	_bloqueos = 0
	_t_viaje = 0.0
	_desvio = 0.0
	_desvio_obj = 0.0
	_evita_factor = 1.0
	if state == State.POSTURA:
		# Iba a un banco o a una reposera y no ha podido llegar: se suelta la reserva para
		# que otro la aproveche y se vuelve a la vida normal.
		if director != null:
			director.liberar(self)
		_postura_ref = -1
		_postura = ""
		_postura_fase = ""
		state = State.IDLE
	if _reintentos >= 3:
		_reintentos = 0
		_enter_idle()
		_idle_timer = _rng.randf_range(6.0, 12.0)   # cuarentena visible y tranquila
		return
	if not _pick_destination():
		_enter_idle()
		_idle_timer = _rng.randf_range(3.0, 7.0)
		return
	_last_position = global_position
	_enter_walk()


## Igual que _cancelar_viaje, pero dejando el motivo en el registro (para las pruebas).
func _abandonar_viaje(motivo: String) -> void:
	if OS.is_debug_build():
		print("[Peatón] viaje abandonado (%s) en %s" % [motivo, global_position])
	_cancelar_viaje()
	_t_viaje = 0.0


## Dirección hacia la que hay que mirar AHORA, aunque todavía no se pueda avanzar (objetivo
## de la red en modo ciudad, punto de acercamiento al banco o a la reposera). Es la pieza
## que impide que un peatón se quede clavado mirando al revés.
func _direccion_objetivo() -> Vector3:
	if state == State.POSTURA and (_postura_fase == "acercarse" or _postura_fase == "camino"):
		var o := _postura_punto_ini - global_position if _postura_fase == "acercarse" \
				else _siguiente_punto() - global_position
		o.y = 0.0
		return o
	if red != null and not _ruta.is_empty() and _ruta_i < _ruta.size():
		var o2 := _siguiente_punto() - global_position
		o2.y = 0.0
		return o2
	if red == null and _agent != null and not _agent.is_navigation_finished():
		var o3 := _agent.get_next_path_position() - global_position
		o3.y = 0.0
		return o3
	return Vector3.ZERO


func _update_facing(delta: float, hacia: Vector3) -> void:
	if hacia.length_squared() < 0.0001:
		return
	var target_yaw := atan2(hacia.x, hacia.z) - _face_yaw
	# Suavizado exponencial: independiente del framerate y sin giros bruscos.
	rotation.y = lerp_angle(rotation.y, target_yaw, 1.0 - exp(-turn_rate * delta))


func _apply_horizontal(desired: Vector3) -> void:
	velocity.x = desired.x
	velocity.z = desired.z


func _on_velocity_computed(safe_velocity: Vector3) -> void:
	velocity.x = safe_velocity.x
	velocity.z = safe_velocity.z
	move_and_slide()


# ------------------------------------------------------------------ reacciones al jugador

## Comprueba, de vez en cuando, si el jugador anda cerca y si este ciudadano le hace caso.
## Sólo en el nivel NEAR: los que están lejos no gastan nada en mirar a nadie.
func _update_reactions(delta: float) -> void:
	_update_watch(delta)
	if activity != Activity.NEAR or state == State.NOTICE or state == State.REACT \
			or state == State.POSTURA:
		return
	_notice_timer -= delta
	if _notice_timer > 0.0:
		return
	# Cada ciudadano comprueba cada 0,25-0,5 s (desfasados): no todos miran al jugador a la vez.
	_notice_timer = _rng.randf_range(0.25, 0.5)
	if _player_node == null or not is_instance_valid(_player_node):
		_player_node = get_tree().get_first_node_in_group("player") as Node3D
		if _player_node == null:
			return
	var to_player := _player_node.global_position - global_position
	to_player.y = 0.0
	var distance := to_player.length()
	if distance > notice_distance:
		_noticed_inside = false
		return
	var entered := not _noticed_inside
	_noticed_inside = true
	# Si le pasa muy cerca y además se mueve, se fijan en él aunque ya estuvieran dentro.
	var insist := distance <= close_distance and _player_speed() > 0.6
	if not entered and not insist:
		return
	if _rng.randf() > reaction_chance:
		_notice_timer = _rng.randf_range(1.0, 2.0)  # éste pasa del jugador (volverá a mirar luego)
		return
	_enter_notice()


func _player_speed() -> float:
	if _player_node is CharacterBody3D:
		return (_player_node as CharacterBody3D).velocity.length()
	return 0.0


## Fase 1: se ha dado cuenta del jugador y empieza a mirarlo de reojo. Dura un instante
## distinto en cada ciudadano, para que no reaccionen todos a la vez.
func _enter_notice() -> void:
	_was_walking = state == State.WALK or state == State.PAUSE or state == State.TURN
	state = State.NOTICE
	_notice_hold = _rng.randf_range(0.35, 0.9)
	_watching = true


## Fase 2: sortea QUÉ reacción tiene (mirar de reojo, pararse o girarse entero).
func _enter_react() -> void:
	_was_walking = _was_walking or state == State.WALK
	state = State.REACT
	_react_kind = _pick_reaction()
	# Cada reacción dura lo suyo, y lo sortea cada ciudadano: no reaccionan como un coro.
	match _react_kind:
		REACT_GREET:
			# Le dedica un gesto breve en vez de quedarse quieto mirándolo.
			_react_timer = _rng.randf_range(1.4, 2.8)
			if _playback:
				_playback.travel("react")
			return
		REACT_TURN:
			_react_timer = _rng.randf_range(1.6, 3.4)
		_:
			_react_timer = _rng.randf_range(0.9, 2.6)
	# El que sólo mira de reojo mientras camina NO cambia de clip: si no, las piernas patinarían
	# (el cuerpo avanzaría con la animación de quieto).
	var keeps_walking: bool = _was_walking and _react_kind == REACT_LOOK
	if _playback and not keeps_walking and not IDLE_SLOTS.has(_playback.get_current_node()):
		_goto_idle_slot(_idle_slot)


func _pick_reaction() -> int:
	var total := 0.0
	for weight in REACT_WEIGHTS:
		total += float(weight)
	var roll := _rng.randf() * total
	for i in REACT_WEIGHTS.size():
		roll -= float(REACT_WEIGHTS[i])
		if roll <= 0.0:
			return i
	return REACT_LOOK


## Estado REACT cuando el ciudadano se ha parado: mantiene la mirada (y el cuerpo girado si
## le tocó girarse) hasta que se le acaba el tiempo, y luego vuelve a lo que estaba haciendo.
func _react_desired_velocity(delta: float) -> Vector3:
	_react_timer -= delta
	if _react_kind == REACT_TURN and _player_node != null:
		var to_player := _player_node.global_position - global_position
		to_player.y = 0.0
		if to_player.length_squared() > 0.0001:
			# Se gira de cuerpo entero, pero despacio: nunca de golpe.
			var target_yaw := atan2(to_player.x, to_player.z) - _face_yaw
			rotation.y = lerp_angle(rotation.y, target_yaw, 1.0 - exp(-2.2 * delta))
	if _react_timer <= 0.0:
		_finish_reaction()
	return Vector3.ZERO


## Se acaba la reacción: deja de mirar, espera un rato antes de volver a fijarse y retoma lo
## que estaba haciendo (seguir su trayecto o quedarse quieto donde estaba).
func _finish_reaction() -> void:
	_watching = false
	_noticed_inside = true
	_notice_timer = _rng.randf_range(reaction_cooldown.x, reaction_cooldown.y)
	if _was_walking:
		_resume_walk()
	else:
		_enter_idle()


## Fundido de la mirada: la cabeza se gira poco a poco y también vuelve poco a poco (nunca de
## golpe). Es independiente del framerate y se apaga solo si el jugador se aleja.
func _update_watch(delta: float) -> void:
	# El estabilizador de cabeza trabaja cuando el ciudadano va a lo suyo; se aparta cuando está
	# sentado/tumbado (ahí la cabeza la manda el clip) y cuando mira al jugador (ahí manda la mirada).
	if _estabiliza != null:
		_estabiliza.activo = state != State.POSTURA and state != State.NOTICE \
				and state != State.REACT and _watch < 0.05
	if _look == null:
		return
	if _watching and _player_node != null and is_instance_valid(_player_node):
		var distance := global_position.distance_to(_player_node.global_position)
		if distance > notice_distance * 1.8:
			_watching = false
		else:
			_look_target.global_position = _player_node.global_position + Vector3.UP * look_at_height
	_watch = move_toward(_watch, 1.0 if _watching else 0.0, delta * 3.0)
	_look.watch = _watch


# ------------------------------------------------------------------ niveles de actividad (LOD)

## Ajusta cuánto trabajo hace este ciudadano según lo lejos que esté del jugador.
##
##   NEAR  -> navegación completa + animación + evitación entre ciudadanos
##   MID   -> navegación y animación normales, sin evitación (la evitación es lo caro)
##   FAR   -> se queda quieto y su animación se apaga (no navega ni anima)
##
## El reparto lo hace el NPCSpawner por turnos, así que subir o bajar de nivel no provoca
## picos de trabajo en un solo fotograma.
func set_activity(tier: Activity) -> void:
	if tier == activity:
		return
	# Sentado o tumbado no se congela: el director necesita poder levantarlo cuando toque
	# (retirada al anochecer) y una postura congelada no podría animarse.
	if state == State.POSTURA and tier == Activity.FAR:
		tier = Activity.MID
		if activity == Activity.FAR:
			_player.process_mode = Node.PROCESS_MODE_INHERIT
	activity = tier
	match activity:
		Activity.NEAR:
			_pending_freeze = false
			_player.process_mode = Node.PROCESS_MODE_INHERIT
			_agent.avoidance_enabled = true
			set_physics_process(true)
		Activity.MID:
			_pending_freeze = false
			_player.process_mode = Node.PROCESS_MODE_INHERIT
			_agent.avoidance_enabled = false
			_watching = false
			set_physics_process(true)
		Activity.FAR:
			_agent.avoidance_enabled = false
			_watching = false
			# Se deja terminar el fundido hacia Idle antes de congelar la animación.
			_enter_idle()
			_pending_freeze = true
			_freeze_timer = 0.6


func is_frozen() -> bool:
	return _player.process_mode == Node.PROCESS_MODE_DISABLED


# ------------------------------------------------------------------ API para la Etapa 3

## Detiene al ciudadano y lo deja en Idle durante `seconds` (útil para reacciones futuras).
func hold_still(seconds: float) -> void:
	_enter_idle()
	_idle_timer = maxf(_idle_timer, seconds)


func current_clip() -> String:
	return _active_clip


## ¿Está mirando al jugador ahora mismo? (lo usan las reacciones y las pruebas)
func is_watching() -> bool:
	return _watching


## Cuánto mira (0 = nada, 1 = todo lo que le permiten sus límites).
func watch_amount() -> float:
	return _watch


func is_walking() -> bool:
	return state == State.WALK or state == State.PAUSE or state == State.TURN


## Velocidad real de avance (m/s), sin contar el frenado.
func move_speed() -> float:
	return _move_speed()