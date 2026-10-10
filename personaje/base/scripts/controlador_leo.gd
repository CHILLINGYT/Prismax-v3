class_name ControladorLeo
extends CharacterBody3D

# Jugador principal del mundo: Leo (forma humana) <-> Velocista (transformación).
#
# Un ÚNICO CharacterBody3D sostiene las dos formas. Sólo cambia lo que se ve
# (modelo humano o modelo velocista) y las capacidades asociadas. La posición,
# el cuerpo físico, la colisión y la cámara son los mismos en ambas formas.
#
# La forma VELOCISTA reutiliza TAL CUAL los sistemas ya existentes de
# personaje/transformaciones/velocidad/: EfectosVelocidad, CapaVelocidad (shader), SistemaCombate,
# TrazadorRuta, RayosVelocidad y la cámara CamaraZiba. La lógica de estados
# (dash, caída-dash, carga de poder, supervelocidad, combate, emote) es la del
# prototipo ziba/scripts/jugador.gd, portada aquí sin cambiar su comportamiento.
#
# La forma HUMANA usa el modelo y las animaciones propias de Leo
# (personaje/transformaciones/humano/), con movimiento/correr/salto y las acciones del proyecto.

enum Forma { HUMANO, VELOCISTA, ACUATICO, FUERZA }

# Estados del sistema de supervelocidad (idénticos a ziba/scripts/jugador.gd).
enum Estado { NORMAL, DASH, CAIDA_DASH, CARGA, PREPARADO, EJECUCION }

## Emitida al cambiar de forma, con el id de la nueva forma (&"humano"/&"velocista").
## El HUD la usa para actualizar el icono central; el resto del juego no cambia.
signal forma_cambiada(id: StringName)

# ------------------------------------------------------------------ Leo: forma humana
const H_VEL_CAMINAR := 3.0
const H_VEL_CORRER := 5.5
const H_ACELERACION := 40.0
const H_DESACELERACION := 50.0
const H_GRAVEDAD := 24.0
const H_SALTO := 7.5
# A partir de esta velocidad horizontal el salto usa el clip "en carrera".
const H_VELOCIDAD_SALTO_CORRIENDO := 3.5
const H_UMBRAL_MOVIMIENTO := 0.15
const H_MEZCLA := 0.15
# Agacharse (misma mecánica que el Leo original de personaje/transformaciones/humano/escenas/leo.tscn):
# velocidad reducida, no se puede correr ni saltar, y la cámara baja un poco.
const H_VEL_AGACHADO := 2.5
const H_ALTURA_AGACHADO := 0.7
const H_MEZCLA_AGACHARSE := 0.25
# Subida de bordillos de acera: escalón bajo (~15 cm). Altura máxima que el
# controlador intenta subir y avance del sondeo de paso libre (metros).
const ALTURA_ESCALON := 0.26
const AVANCE_ESCALON := 0.40
# Metro extra de avance sobre el radio de la cápsula: garantiza que el centro del
# cuerpo quede claramente encima de la superficie de destino (no justo en el canto).
const MARGEN_ESCALON := 0.12
# Desnivel mínimo para considerar que hay un escalón real: un borde que sigue a la
# misma cota (la propia calzada) NO es un escalón y no debe subirse.
const DESNIVEL_MINIMO := 0.02

# Clips de la librería de Leo (personaje/transformaciones/humano/animations/leo_animations.tres).
const ANIM_H_IDLE := "idle"
const ANIM_H_WALK := "walk"
const ANIM_H_RUN := "fast_run"
const ANIM_H_SALTO := "jump_up"
const ANIM_H_SALTO_CORRIENDO := "running_jump"
# Clips de agachado: "crouch_walk" ya existe en leo_animations.tres (no se crea nada).
# "crouch_idle" todavía no existe; si falta, se congela la pose de crouch_walk (como en leo.gd).
const ANIM_H_CROUCH_WALK := "crouch_walk"
const ANIM_H_CROUCH_IDLE := "crouch_idle"

# ------------------------------------------- Acuático / Pes: clips propios
# La librería acuática (personaje/transformaciones/acuatica/animations/player_animations.tres)
# se carga como librería "por defecto" del AnimationPlayer del modelo acuático, así
# que sus clips se reproducen por su nombre simple (idle, walk, run, ...). Son los
# clips originales del módulo acuático: NO se renombran ni se sustituyen por los de Leo.
const ANIM_A_IDLE := "idle"
const ANIM_A_WALK := "walk"
const ANIM_A_RUN := "run"
const ANIM_A_WALK_BACK := "walk_back"
const ANIM_A_JUMP := "jump"
const ANIM_A_FALL := "fall"
const ANIM_A_CROUCH_IDLE := "crouch_idle"
const ANIM_A_CROUCH_WALK := "crouch_walk"
const ANIM_A_ATTACK := "attack"

# ------------------------------------------- Acuático / Pes: 4 habilidades (1-4)
# Tabla única de las cuatro habilidades acuáticas. Reutiliza TAL CUAL los objetos
# de habilidad del módulo (abilities/*.gd): viajan, chocan y hacen daño de verdad a
# cualquier nodo del grupo "damageable", sin depender del Player del módulo.
#   release   segundo del clip en el que sale el efecto (coincide con la pista de
#             método de la animación; aquí sólo es el seguro anti-atasco)
#   carga     radio (m) del agua que se junta en las manos al cargar
const ABIL_AGUA := [
	{
		"nombre": "Proyectil de agua",
		"script": preload("res://personaje/transformaciones/acuatica/abilities/water_projectile.gd"),
		"cooldown": 1.0, "release": 1.3, "carga": 0.34,
		"damage": 12.0, "hit_radius": 0.55, "speed": 18.0, "lifetime": 2.5,
		"knockback": 3.0, "kind": &"light",
	},
	{
		"nombre": "Esfera de agua",
		"script": preload("res://personaje/transformaciones/acuatica/abilities/water_burst.gd"),
		"cooldown": 3.0, "release": 1.85, "carga": 0.42,
		"damage": 8.0, "hit_radius": 0.7, "speed": 12.0, "lifetime": 4.0,
		"knockback": 5.0, "kind": &"heavy",
		"field_radius": 3.2, "field_duration": 2.6,
	},
	{
		"nombre": "Prision de agua",
		"script": preload("res://personaje/transformaciones/acuatica/abilities/water_prison.gd"),
		"cooldown": 5.0, "release": 1.5, "carga": 0.3,
		"damage": 10.0, "hit_radius": 0.9, "speed": 14.0, "lifetime": 3.0,
		"knockback": 0.0, "kind": &"light",
		"trap_duration": 3.0,
	},
	{
		"nombre": "Oleada de agua",
		"script": preload("res://personaje/transformaciones/acuatica/abilities/water_surge.gd"),
		"cooldown": 8.0, "release": 1.62, "carga": 0.55,
		"damage": 45.0, "hit_radius": 2.4, "speed": 7.0, "lifetime": 2.6,
		"knockback": 9.0, "kind": &"heavy",
	},
]

# ------------------------------------------- Fuerza: movimiento y habilidades
# La forma Fuerza reutiliza los scripts/efectos de res://Fuerza/ (Combat, Vfx,
# Rock, Shockwave). En vez de un segundo CharacterBody3D, la lógica vive aquí y
# comparte cuerpo, colisión, cámara y inputs.
# PESADO: anda y corre despacio, con inercia (coincide con el diseño del paquete).
const F_VEL_CAMINAR := 1.6
const F_VEL_CORRER := 4.0
const F_ACELERACION := 12.0
const F_DESACELERACION := 16.0
const F_GRAVEDAD := 25.0
const F_SALTO := 6.5
# Supersalto con carga (mantener ESPACIO en el suelo). Un toque corto conserva
# el salto normal de siempre. Valores heredados del paquete original de Fuerza
# (su gravedad es la MISMA: F_GRAVEDAD = 25, así que el rango 8..21 m/s da las
# mismas alturas de diseño: ~1.3 m al mínimo y ~8.8 m con la carga al tope).
const F_SUPER_CARGA_MIN := 0.25     # s: por debajo, toque corto = salto normal
const F_SUPER_CARGA_MAX := 1.4      # s: carga completa
const F_SUPER_VEL_MIN := 8.0        # m/s al soltar justo pasado el mínimo
const F_SUPER_VEL_MAX := 21.0       # m/s con la carga al tope
const F_SUPER_IMPULSO := 2.0        # empuje horizontal mínimo del despegue
const F_SUPER_SACUDIDA := 0.45      # sacudida de cámara al despegar
const F_SUPER_CAIDA_CAMARA := 0.28  # la cámara baja mientras se carga
const F_SUPER_TEMBLOR := 0.035      # temblor del cuerpo mientras se carga
const F_SUPER_BARRA_LARGO := 220.0  # tamaño del indicador de carga en pantalla
const F_SUPER_BARRA_ALTO := 16.0
# Embestida con el hombro (R).
const F_EMBESTIDA_VEL := 7.0
const F_EMBESTIDA_DUR := 0.5
const F_EMBESTIDA_DANIO := 35.0
const F_EMBESTIDA_RADIO := 1.6
const F_EMBESTIDA_RECUP := 0.3
# Supersalto / pisotón aéreo (E en el aire) con onda expansiva al aterrizar.
const F_SLAM_VEL := 45.0
const F_SLAM_DANIO := 60.0
const F_SLAM_RADIO := 4.5
# Cuerpo a cuerpo (clic izq. = puñetazo / combo, clic der. = patada).
const F_PUNIO_DANIO := 8.0
const F_PATADA_DANIO := 14.0
const F_GOLPE_ALCANCE := 1.1
const F_GOLPE_RADIO := 0.7
const F_GOLPE_ALTURA := 1.2
const F_PATADA_ALTURA := 0.9
const F_COMBO_VENTANA := 0.45
# u (fracción del clip) en la que el puño/el pie alcanzan su extensión MÁXIMA,
# medida sobre el propio esqueleto con los clips reales: mano izquierda al
# frente en Punch_Left u=0.23, mano derecha (cross) en Punch_Right u=0.30 y
# pie al frente en Kick u=0.375. El daño de un golpe cae en ese instante.
const F_IMPACTO_U := {
	"Punch_Left": 0.23,
	"Punch_Right": 0.30,
	"Kick": 0.375,
}
# Roca (Q la arranca del suelo frente al personaje / clic izq. la lanza).
const F_ROCA_TAM := 0.8
const F_ROCA_VEL := 17.0
const F_ROCA_DANIO := 80.0
const F_ROCA_RADIO := 3.0
# Agarre de la roca. Estos valores DEBEN coincidir con el horneado de los
# clips de la roca (animations/libraries/FuerzaUniversal.tres: RockLift,
# RockCarry, RockCarryWalk, RockThrow): animación e IK usan exactamente la
# misma fórmula de trayectoria y de puntos de agarre, así que nunca se pelean.
const F_ROCA_CARRY_H := 1.13   # altura del centro sobre la cabeza, en radios
const F_ROCA_Z0 := 0.62        # dónde nace/apoya la roca (esp. esqueleto, +adelante)
const F_ROCA_U_SUBIDA := 0.55  # fase del levantamiento en la que la roca empieza a subir
const F_ROCA_U_FIN := 0.90     # fase en la que termina de subir
const F_ROCA_GUARDA := 0.25    # margen extra alrededor de la cabeza (en radios)
const F_ROCA_SWAY := 0.008     # balanceo lateral al caminar cargada (esp. esqueleto)
const F_ROCA_POLO_SALIDA := 2.2
const F_ROCA_POLO_ABAJO := 0.0
const F_ROCA_POLO_ATRAS := 0.2
# Mira (crosshair) del modo apuntado de la roca: cruz fina con contorno en el
# centro exacto de la pantalla mientras la piedra está arriba, lista para
# lanzar. El punto objetivo sale de un raycast desde el centro de la cámara.
const F_MIRA_LARGO := 11.0        # longitud de cada brazo de la cruz (px)
const F_MIRA_GROSOR := 2.0        # grosor de cada brazo (px)
const F_MIRA_HUECO := 5.0         # hueco central alrededor del punto (px)
const F_MIRA_PUNTO := 3.0         # tamaño del punto central (px)
const F_MIRA_ALCANCE := 60.0      # alcance máximo del raycast de apuntado (m)
const F_MIRA_COLOR := Color(1.0, 1.0, 1.0, 0.92)
const F_MIRA_SOMBRA := Color(0.0, 0.0, 0.0, 0.55)

# Clips de la nueva librería de Fuerza (UniversalLibrary -> FuerzaUniversal.tres).
# Se reproducen por su nombre simple sobre el AnimationPlayer del nodo $Fuerza.
const ANIM_F_IDLE := "Idle"
const ANIM_F_WALK := "Walk"
const ANIM_F_RUN := "Run"
const ANIM_F_JUMP := "Jump"
const ANIM_F_FALL := "Fall"
const ANIM_F_CROUCH := "Crouch"
const ANIM_F_CROUCHWALK := "CrouchWalk"
const ANIM_F_PUNCH_L := "Punch_Left"
const ANIM_F_PUNCH_R := "Punch_Right"
const ANIM_F_KICK := "Kick"
const ANIM_F_AIRSLAM := "AirSlam"
const ANIM_F_SLAMIMPACT := "SlamImpact"
const ANIM_F_ROCKLIFT := "RockLift"
const ANIM_F_ROCKCARRY := "RockCarry"
const ANIM_F_ROCKCARRYWALK := "RockCarryWalk"
const ANIM_F_ROCKTHROW := "RockThrow"
const ANIM_F_CARGA := "Charge"
const ANIM_F_SUPERJUMP := "SuperJump"
const ANIM_F_SHOULDERPREP := "ShoulderPrep"
const ANIM_F_SHOULDERRUN := "ShoulderRun"
const ANIM_F_SHOULDERECOVER := "ShoulderRecover"

# ------------------------------------------- Velocista: supervelocidad (ziba/)
# Animaciones existentes (librerías del AnimationPlayer del modelo velocista).
const ANIM_INACTIVO := "inactivo"
const ANIM_ADELANTE := "caminar_hacia_adelante"
const ANIM_ATRAS := "caminar_hacia_atras"
const ANIM_CARGA := "cargar_poder_click-derecho"
const ANIM_DASH := "dash-con-shift"
const ANIM_SALTO := "jumping up(1)"
const ANIM_SUPERVELOCIDAD := "superduper_velocidad"
const ANIM_INACTIVO_VELOCIDAD := "inactivo_despues-despues-de-30s-velocidad"
const ANIM_COMBO_1 := "combo-1"
const ANIM_COMBO_2 := "combo-2"
const ANIM_COMBO_3 := "combo-3"
const ANIM_COMBO_4 := "combo-4"
const ANIM_MODO_ATAQUE := "inactivo_modo_ataque"
const ANIM_EMOTE := "calentamiento_ataque"

# Tiempos de blending (idénticos al prototipo).
const BLEND_MARCHA := 0.25
const BLEND_MARCHA_FIN := 0.30
const BLEND_CAMBIO_MARCHA := 0.18
const BLEND_SALTO := 0.10
const BLEND_POST_SALTO := 0.15
const BLEND_DASH := 0.06
const BLEND_POST_DASH := 0.12
const BLEND_CARGA := 0.10
const BLEND_LIBERACION := 0.08
const BLEND_FIN_VELOCIDAD := 0.22
const BLOQUEO_FIN_VELOCIDAD := 0.12
const BLEND_ATAQUE := 0.08
const BLEND_POST_ATAQUE := 0.16
const BLEND_EMOTE := 0.12
# Fundido al entrar/salir de la transformación.
const BLEND_TRANSFORMACION := 0.15

# Colores del efecto visual de transformación existente.
const COLORES_TRANSFORMACION := {
	&"combate": Color(0.6, 0.1, 1.0, 1.0),
	&"velocista": Color(1.0, 0.035, 0.025, 1.0),
	&"pes": Color(0.015, 0.12, 0.72, 1.0),
	&"tanque": Color(1.0, 0.82, 0.015, 1.0),
	&"aguila": Color(0.22, 0.82, 1.0, 1.0),
}

const TIEMPO_MODO_ATAQUE := 10.0
const FACTOR_MOVILIDAD_ATAQUE := 0.35
const IMPULSO_AVANCE := 4.5
const VENTANA_CONTINUACION := 0.5

@export_group("Forma humana")
@export var h_vel_caminar: float = H_VEL_CAMINAR
@export var h_vel_correr: float = H_VEL_CORRER

@export_group("Movimiento velocista")
@export var velocidad_max: float = 7.0
@export var aceleracion: float = 45.0
@export var desaceleracion: float = 55.0
@export var gravedad: float = 24.0
@export var fuerza_salto: float = 7.5

@export_group("Dash")
@export var distancia_dash: float = 10.0
@export var duracion_dash: float = 0.09
@export var distancia_objetivo_dash: float = 9.0

@export_group("Poder supervelocidad")
@export var vel_trayecto_max: float = 60.0
@export var vel_trayecto_min: float = 34.0

# --- Recorrido del poder (clic derecho) ---
## Radio (m) con el que se da por alcanzado un punto de la ruta.
const TRAYECTO_RADIO_PUNTO := 1.2
## Altura (m) a la que se sondea si hay un muro real delante: a esa altura un
## edificio bloquea, pero un bordillo o un desnivel pequeño no.
const TRAYECTO_ALTURA_MURO := 1.4

var forma: int = Forma.HUMANO
var estado: int = Estado.NORMAL
# Verdadero mientras corre la transición visual al cambiar de forma.
var _transformando: bool = false
# Verdadero mientras el menú radial de transformaciones (F) está abierto.
var _menu_abierto: bool = false

@onready var humano: Node3D = $Humano
@onready var anim_humano: AnimationPlayer = $Humano/Animador
@onready var acuatico: Node3D = $Acuatico
@onready var anim_acuatico: AnimationPlayer = $Acuatico/AnimadorAcuatico
@onready var fuerza: Node3D = $Fuerza
@onready var anim_fuerza: AnimationPlayer = $Fuerza/AnimadorFuerza
@onready var vel_modelo: Node3D = $Visual/Pose/Volteo/Modelo
@onready var visual: Node3D = $Visual
@onready var pose: Node3D = $Visual/Pose
@onready var pivote: CamaraZiba = $PivoteCamara
@onready var trazador: TrazadorRuta = $Trazador
@onready var efectos: EfectosVelocidad = $Efectos
@onready var combate: SistemaCombate = $Combate
@onready var efecto_transf: EfectoTransformacion = $EfectoTransformacion
@onready var menu_transf: MenuTransformaciones = $MenuTransformaciones
@onready var estadisticas: EstadisticasJugador = $Estadisticas

# --- Estado forma humana ---
var h_salto_aire: bool = false
var h_anim_salto: String = ANIM_H_SALTO
var h_agachado: bool = false
var h_pivote_y_base: float = 1.6
var h_espera_congelar: float = 0.0

# --- Estado acuático (Pes) ---
var a_salto_aire: bool = false
var a_agachado: bool = false
var a_ataque_activo: bool = false
var a_t_ataque: float = 0.0
# Habilidades acuáticas (teclas 1-4): bloqueo de acción, enfriamientos y carga.
var a_en_habilidad: bool = false
var a_t_habilidad: float = 0.0
var a_pendiente: int = 0
var a_pendiente_t: float = 0.0
var a_cooldowns: Dictionary = {}
var a_carga: Node3D = null
# Dirección (horizontal, mundo) capturada al pulsar una habilidad acuática. Se fija
# en ese instante y NO cambia aunque después se mueva la cámara.
var a_dir_ataque: Vector3 = Vector3.ZERO

# --- Mano de lanzamiento de las habilidades acuáticas ---
# Las cuatro habilidades nacen en la MANO que sostiene el agua, no en el centro
# del cuerpo. Se reutiliza el mismo sistema del módulo acuático original (hueso
# del esqueleto + ligero desplazamiento), pero sobre el modelo integrado de Leo.
# El hueso se busca por nombre en el esqueleto REALMENTE importado: en
# models/futuristic_armor_character.tscn la mano derecha es "mixamorig_RightHand".
const MANO_AGUA := &"RightHand"
# Desplazamiento (m) del agua respecto a la muñeca, EN EL ESPACIO DEL HUESO (no del
# mundo): la lleva a la palma y hace que acompañe al brazo mire donde mire.
const DESPLAZAMIENTO_MANO_AGUA := Vector3(0.0, 0.03, 0.0)
# Cuánto (m) por delante de la mano nace el efecto, en la dirección del ataque:
# evita que la bola quede DENTRO de la mano o del brazo y la deja proyectada.
const ADELANTE_MANO_AGUA := 0.30
# Esqueleto del modelo acuático (cacheado: se pide en cada fotograma).
var _esqueleto_agua: Skeleton3D = null

# --- Estado Fuerza ---
var f_salto_aire: bool = false
var f_agachado: bool = false
var f_embestiendo: bool = false
var f_t_embestida: float = 0.0
var f_embestida_dir: Vector3 = Vector3.ZERO
var f_embestida_golpeados: Array = []
var f_recuperacion: float = 0.0
var f_slam: bool = false
var f_cargando_roca: bool = false
var f_roca: FuerzaRock = null
# IK de agarre de la roca: se crea una sola vez, la primera vez que se pulsa Q.
var _f_ik: FuerzaBrazosIK = null
var _f_esqueleto: Skeleton3D = null
var _f_idx_cabeza: int = -1
var _f_idx_cabeza_top: int = -1
# Supersalto con carga (ESPACIO mantenido en el suelo): estado de la carga,
# indicador visual (reutiliza el anillo del HUD, mismo estilo) y la posición
# base del nodo del modelo para el temblor de esfuerzo.
var f_super_cargando: bool = false
var f_super_carga: float = 0.0
var _f_fondo: ColorRect = null
var _f_relleno: ColorRect = null
var _f_flash_indicador: float = 0.0
var _f_fuerza_pos_base: Vector3 = Vector3.ZERO
# El levantamiento de la roca ha TERMINADO de verdad (fin del clip RockLift):
# sólo entonces se puede apuntar/lanzar.
var f_roca_lista: bool = false
# Última piedra LANZADA: sigue existiendo en el mundo hasta desvanecerse.
# Mientras siga ahí no se puede arrancar otra del suelo.
var _f_roca_lanzada: FuerzaRock = null
var f_ataque: bool = false
# Ventana de combo: instante en el que TERMINÓ el último golpe (no aquel en el
# que empezó): el encadenado 1-2 se mide desde el fin real de la animación.
var f_ultimo_golpe: float = 0.0
# --- Animación Fuerza (librería UniversalLibrary: FuerzaUniversal.tres) ---
var _f_anim_actual: String = ""
var _f_ataque_clip: String = ""
var _f_ataque_dur: float = 0.0
var _f_ataque_impacto_u: float = 0.29
var _f_ataque_golpeado: bool = false
var _f_clip_terminado: String = ""
var _f_combo_pedido: bool = false
var _f_bloqueo_anim: float = 0.0
# Mira del apuntado de la roca (cruz fina en el centro de la pantalla).
var _f_mira: Control = null

# --- Estado velocista ---
var _dir_dash: Vector3 = Vector3.ZERO
var _pos_dash_inicio: Vector3 = Vector3.ZERO
var _objetivo_dash: Vector3 = Vector3.ZERO
var _t_dash: float = 0.0
var _t_carga: float = 0.0
var _t_preparado: float = 0.0
var _puntos: Array[Vector3] = []
var _idx: int = 0
var _vel_trayecto: float = 0.0
var _hubo_combo_atras: bool = false
var _en_ventana_atras: bool = false
var _t_ventana: float = 0.0
var _dir_orient_ventana: Vector3 = Vector3.ZERO
var _ultimo_dir_movimiento: Vector3 = Vector3.ZERO
var _anim: AnimationPlayer = null
var _anim_nombres: Dictionary = {}
var _anim_actual: String = ""
var _bloqueo_anim: float = 0.0
var _ataque_activo: bool = false
var _t_ataque: float = 0.0
var _emote_activo: bool = false
var _t_emote: float = 0.0
var _en_modo_ataque: bool = false
var _t_modo_ataque: float = 0.0
var _salto_forzado: bool = false

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# Sigue el bordillo hacia abajo (0.153 m) sin despegarse del suelo al bajar de
	# la acera a la calzada. Es un ajuste pequeño y localizado (por defecto 0.1).
	floor_snap_length = 0.2
	_configurar_animaciones()
	combate.golpe_realizado.connect(_on_golpe_realizado)
	# Atacar también corta la regeneración de resistencia (sistema de daño/HUD):
	# se reutiliza la señal de combate existente, sin crear un segundo sistema.
	combate.golpe_realizado.connect(estadisticas.notificar_ataque)
	# El menú radial (F) es sólo una NUEVA forma de elegir la transformación:
	# emite qué transformación eligió el jugador y aquí se reutiliza el sistema
	# que ya existía. También avisa al abrir/cerrar para congelar el control.
	menu_transf.menu_abierto.connect(_on_menu_transformaciones_abierto)
	menu_transf.menu_cerrado.connect(_on_menu_transformaciones_cerrado)
	menu_transf.transformacion_elegida.connect(_on_transformacion_elegida)
	# Altura base del pivote de cámara, para bajarla al agacharse y restaurarla después.
	h_pivote_y_base = pivote.position.y
	# Iguala la altura visual de la forma velocista a la de Leo humano.
	_ajustar_escala_velocista()
	# Iguala la altura visual de la forma acuática (Pes) a la de Leo humano.
	_ajustar_escala_acuatico()
	# Iguala la altura visual de la forma Fuerza a la de Leo humano.
	_ajustar_escala_fuerza()
	# El fin REAL del clip de levantar la roca (señal del propio AnimationPlayer,
	# no un temporizador paralelo) es lo que habilita apuntar y lanzar.
	anim_fuerza.animation_finished.connect(_on_animacion_fuerza_terminada)
	# Indicador de carga del supersalto: se reutiliza el anillo del HUD para que
	# quede en el mismo estilo que el resto de la interfaz.
	_preparar_indicador_super()
	# Mira del apuntado de la piedra (se enciende sólo con la roca lista).
	_preparar_mira_roca()
	_f_fuerza_pos_base = fuerza.position
	# Enfriamientos de las 4 habilidades acuáticas (arrancan listas).
	for i in ABIL_AGUA.size():
		a_cooldowns[i + 1] = 0.0
	# La partida arranca SIEMPRE en la forma humana (Leo).
	forma = Forma.HUMANO
	visual.visible = false
	acuatico.visible = false
	fuerza.visible = false
	humano.visible = true
	_reproducir_humano(ANIM_H_IDLE, 0.0)

# Fuerza usada por herramientas/diagnóstico (igual que el prototipo).
func forma_actual() -> int:
	return forma

func esta_transformado() -> bool:
	return forma != Forma.HUMANO

# Id lógico de la forma actual, para sistemas externos (el HUD). Escalable:
# una forma futura sólo añade su caso aquí y su icono en HUDCircular.ICONOS.
func id_forma() -> StringName:
	match forma:
		Forma.VELOCISTA:
			return &"velocista"
		Forma.ACUATICO:
			return &"pes"
		Forma.FUERZA:
			return &"tanque"
		_:
			return &"humano"

func _unhandled_input(event: InputEvent) -> void:
	# Con el menú de transformaciones abierto el ratón debe quedar libre para
	# pulsar los iconos: se anula el "clic para recapturar" durante ese tiempo.
	if _menu_abierto:
		return
	# G: interruptor directo del cambio de forma (alternativa al menú radial F).
	# is_action_pressed ya respeta "just_pressed": mantener G no re-transforma.
	if event.is_action_pressed("transformacion_velocidad"):
		_alternar_forma_con_efecto()
		return
	# K (sólo para probar el HUD): aplica daño al personaje.
	if event.is_action_pressed("dano_prueba"):
		estadisticas.recibir_danio(25.0)
		return
	# Pes (forma acuática): las teclas 1-4 lanzan sus 4 habilidades. Sólo se leen
	# aquí: en las demás formas estas teclas conservan su significado (no se
	# añaden acciones globales, así que no afectan a Leo/velocista/Fuerza).
	if forma == Forma.ACUATICO and event is InputEventKey and event.pressed \
			and not (event as InputEventKey).echo:
		var k := (event as InputEventKey).keycode
		if k == KEY_1 or k == KEY_2 or k == KEY_3 or k == KEY_4:
			_intentar_habilidad_agua(k - KEY_1 + 1)
			get_viewport().set_input_as_handled()
			return
	# Fuerza: R = embestida, E = pisotón (sólo en el aire), Q = arrancar roca.
	if forma == Forma.FUERZA and event is InputEventKey and event.pressed \
			and not (event as InputEventKey).echo:
		var fk := (event as InputEventKey).keycode
		if fk == KEY_R:
			_iniciar_embestida_fuerza()
			get_viewport().set_input_as_handled()
			return
		elif fk == KEY_E:
			_intentar_slam_fuerza()
			get_viewport().set_input_as_handled()
			return
		elif fk == KEY_Q:
			_intentar_roca_fuerza()
			get_viewport().set_input_as_handled()
			return
	if event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(delta: float) -> void:
	# Con el menú radial de transformaciones abierto (F): se congela el control
	# de movimiento (sin tocar la cámara ni la posición de forma brusca) hasta
	# que el menú se cierra. El propio menú gestiona la tecla F.
	if _menu_abierto:
		_congelar_por_menu(delta)
		return

	# Durante la transición visual no hay control horizontal ni nuevas acciones:
	# sólo actúa la gravedad (para no quedar flotando) y se mueve el cuerpo.
	if _transformando:
		velocity.x = 0.0
		velocity.z = 0.0
		if not is_on_floor():
			velocity.y -= gravedad * delta
		elif velocity.y < 0.0:
			velocity.y = -0.1
		move_and_slide()
		return

	if forma == Forma.HUMANO:
		_procesar_humano(delta)
	elif forma == Forma.ACUATICO:
		_procesar_acuatico(delta)
	elif forma == Forma.FUERZA:
		_procesar_fuerza(delta)
		_actualizar_anim_fuerza(delta)
	else:
		match estado:
			Estado.NORMAL:
				_procesar_normal(delta)
			Estado.DASH:
				_procesar_dash(delta)
			Estado.CAIDA_DASH:
				_procesar_caida_dash()
			Estado.CARGA:
				_procesar_carga(delta)
			Estado.PREPARADO:
				_procesar_preparado(delta)
			Estado.EJECUCION:
				_procesar_ejecucion(delta)
		_actualizar_animaciones(delta)
		_actualizar_pose(delta)

	# Subida natural de bordillos para locomoción normal. Durante EJECUCION el
	# recorrido gestiona el bloqueo en _procesar_ejecucion(): ahí primero distingue
	# pared/escalón y, si corresponde, llama a _salvar_escalon(). No ejecutar ambos
	# solucionadores en el mismo fotograma.
	# Subida natural de los bordillos de las aceras (~15 cm): común a las cuatro
	# formas, se ejecuta una vez por frame tras el move_and_slide() de cada una.
	# Durante la EJECUCIÓN del trazado del Velocista NO se ejecuta aquí: ese estado
	# usa _intentar_escalon_ejecucion() sobre su propia colisión con move_and_collide,
	# y encadenar ambos podría provocar dobles ascensos o saltos de posición.
	if estado != Estado.EJECUCION:
		_resolver_escalon()

# Menú abierto: sin control horizontal, sólo gravedad y pose quieta, para que
# el personaje no se mueva ni quede flotando. La cámara no se modifica.
func _congelar_por_menu(delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	if not is_on_floor():
		velocity.y -= gravedad * delta
	elif velocity.y < 0.0:
		velocity.y = -0.1
	move_and_slide()
	if forma == Forma.HUMANO:
		_reproducir_humano(ANIM_H_IDLE)
	elif forma == Forma.ACUATICO:
		_reproducir_acuatico(ANIM_A_IDLE)
	elif forma == Forma.FUERZA:
		_reproducir_fuerza(ANIM_F_IDLE)
	else:
		_reproducir_anim(ANIM_INACTIVO, BLEND_MARCHA)

## Sube el bordillo de una acera (escalón bajo, ~15 cm) sin tocar move_and_slide
## ni la gravedad. Se llama una vez por frame, tras el movimiento de cada forma,
## así que sirve igual a Humano, Velocista, Acuático y Fuerza.
##
## Clave: la dirección de ascenso NO se toma de 'velocity' después de
## move_and_slide(), porque el deslizamiento proyecta esa velocidad A LO LARGO del
## bordillo; sondear con ella hacía que el personaje avanzara en paralelo (el
## deslizamiento lateral observado). En su lugar se usa la INTENCIÓN de movimiento
## del jugador y, para el avance, la normal de la pared real (≈ perpendicular al
## bordillo), de modo que el sondeo CRUZA el escalón.
##
## Sólo actúa contra una pared compatible con un escalón bajo: hay hueco por
## encima, paso libre a esa altura y una superficie transitable más alta (dentro
## del escalón) al otro lado. Un muro alto (un edificio) no supera el sondeo de
## avance y no se sube; un borde que sigue a la misma cota (la propia calzada) se
## rechaza, así que no se produce avance lateral.
func _resolver_escalon() -> void:
	if not is_on_floor() or not is_on_wall():
		return
	# Intención de movimiento horizontal del jugador (no la velocidad tras slide).
	var intencion := _direccion_entrada()
	if intencion.length_squared() < 0.04:
		return
	intencion = intencion.normalized()

	# Dirección de avance: perpendicular a la pared si la conocemos; si no, la
	# intención del jugador. La intención decide SI se sube (hay que empujar hacia
	# la pared), no la dirección exacta del sondeo.
	var normal := _normal_pared()
	var dir := intencion
	if normal != Vector3.ZERO:
		if intencion.dot(normal) > -0.15:
			return
		dir = -normal

	var altura := ALTURA_ESCALON
	# Avance suficiente para que el centro de la cápsula quede sobre el destino.
	var avance_dist := maxf(AVANCE_ESCALON, _radio_capsula() + MARGEN_ESCALON)

	# 1) ¿Cabe la subida? (si hay techo bajo, no)
	if test_move(global_transform, Vector3.UP * altura):
		return

	# 2) ¿Hay paso libre a la altura del escalón? (muro alto -> no es un escalón)
	var elevado := global_transform
	elevado.origin.y += altura
	if test_move(elevado, dir * avance_dist):
		return

	# 3) Suelo de destino: superficie transitable, más alta que la actual pero
	#    dentro del escalón. Distingue calzada (misma cota -> rechazar), escalón
	#    (subir), pared/edificio y ausencia de suelo.
	var desde := elevado.origin + dir * avance_dist + Vector3.UP * 0.05
	var golpe := _rayo_suelo(desde, altura + 0.25)
	if golpe.is_empty():
		return
	var normal_suelo: Vector3 = golpe.get("normal", Vector3.UP)
	if normal_suelo.dot(Vector3.UP) < cos(floor_max_angle):
		return
	var desnivel: float = (golpe["position"] as Vector3).y - global_position.y
	if desnivel <= DESNIVEL_MINIMO or desnivel > altura + 0.03:
		return

	# 4) Ejecuta la subida con movimiento real (sin teletransporte): elevar,
	#    avanzar y volver a apoyarse sobre la superficie de destino.
	move_and_collide(Vector3.UP * (desnivel + 0.03))
	move_and_collide(dir * avance_dist)
	move_and_collide(Vector3.DOWN * (desnivel + 0.08))


## Normal horizontal de la pared en la que se apoya el cuerpo (de las colisiones
## del último move_and_slide), o Vector3.ZERO si no hay pared. Los suelos y techos
## se descartan por su componente vertical.
func _normal_pared() -> Vector3:
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		if col == null:
			continue
		var n := col.get_normal()
		if absf(n.y) < 0.7:
			var horiz := Vector3(n.x, 0.0, n.z)
			if horiz.length_squared() > 0.0001:
				return horiz.normalized()
	return Vector3.ZERO


## Rayo hacia abajo limitado a la máscara del jugador; devuelve {} si no hay
## impacto. Permite conocer la altura y la normal del suelo de destino.
func _rayo_suelo(desde: Vector3, largo: float) -> Dictionary:
	var mundo := get_world_3d()
	if mundo == null:
		return {}
	var q := PhysicsRayQueryParameters3D.create(desde, desde + Vector3.DOWN * largo)
	q.collision_mask = collision_mask
	q.exclude = [get_rid()]
	q.collide_with_areas = false
	q.collide_with_bodies = true
	return mundo.direct_space_state.intersect_ray(q)


## Radio de la cápsula de colisión del jugador (0.4 m por defecto).
func _radio_capsula() -> float:
	var capsula := get_node_or_null("Colision") as CollisionShape3D
	if capsula != null and capsula.shape is CapsuleShape3D:
		return (capsula.shape as CapsuleShape3D).radius
	return 0.4


## Ascenso de bordillos durante la EJECUCIÓN del trazado del Velocista. Usa el
## MISMO criterio y los MISMOS límites que _resolver_escalon() del movimiento
## normal (ALTURA_ESCALON / AVANCE_ESCALON / MARGEN_ESCALON / DESNIVEL_MINIMO),
## pero se dispara con la colisión real del move_and_collide() de la trayectoria
## en lugar de is_on_wall(), porque la ejecución no usa move_and_slide() para
## avanzar. Devuelve true si el obstáculo era un escalón transitable y se subió
## (el recorrido continúa); false si no lo es (pared, edificio, desnivel
## excesivo o ausencia de suelo válido) y debe cancelarse como antes.
func _intentar_escalon_ejecucion(col: KinematicCollision3D, dir_mov: Vector3) -> bool:
	if col == null:
		return false
	# Sólo se sube contra una cara vertical (un bordillo). Un suelo o techo
	# (normal casi vertical) no es un escalón.
	var normal := col.get_normal()
	if absf(normal.y) >= 0.7:
		return false
	var horizontal := Vector3(normal.x, 0.0, normal.z)
	if horizontal.length_squared() < 0.0001:
		return false
	horizontal = horizontal.normalized()

	# Dirección de avance real: perpendicular a la pared. Se exige además que el
	# desplazamiento previsto de la trayectoria apunte hacia la pared (no de lado
	# ni en sentido contrario), para no escalar un borde que sólo roza de refilón.
	var dir := -horizontal
	var intencion := Vector3(dir_mov.x, 0.0, dir_mov.z)
	if intencion.length_squared() > 0.0001 and intencion.normalized().dot(dir) < 0.2:
		return false

	var altura := ALTURA_ESCALON
	# Avance suficiente para que el centro de la cápsula quede sobre el destino.
	var avance_dist := maxf(AVANCE_ESCALON, _radio_capsula() + MARGEN_ESCALON)

	# 1) ¿Cabe la elevación de la cápsula completa? (si hay techo bajo, no)
	if test_move(global_transform, Vector3.UP * altura):
		return false

	# 2) ¿Hay paso libre por encima del borde? (muro/edificio alto -> no es un
	#    escalón y no se intenta subir)
	var elevado := global_transform
	elevado.origin.y += altura
	if test_move(elevado, dir * avance_dist):
		return false

	# 3) Superficie de destino: debe ser transitable, estar más alta que la actual
	#    pero dentro del escalón. Distingue calzada a la misma cota (rechazar) de
	#    bordillo (subir), y descarta pared/edificio o ausencia de suelo.
	var desde := elevado.origin + dir * avance_dist + Vector3.UP * 0.05
	var golpe := _rayo_suelo(desde, altura + 0.25)
	if golpe.is_empty():
		return false
	var normal_suelo: Vector3 = golpe.get("normal", Vector3.UP)
	if normal_suelo.dot(Vector3.UP) < cos(floor_max_angle):
		return false
	var desnivel: float = (golpe["position"] as Vector3).y - global_position.y
	if desnivel <= DESNIVEL_MINIMO or desnivel > altura + 0.03:
		return false

	# 4) Ascenso con movimiento real (sin teletransporte): elevar, avanzar y
	#    volver a apoyarse sobre la superficie de destino.
	move_and_collide(Vector3.UP * (desnivel + 0.03))
	move_and_collide(dir * avance_dist)
	move_and_collide(Vector3.DOWN * (desnivel + 0.08))
	return true


func _on_menu_transformaciones_abierto() -> void:
	_menu_abierto = true
	# Cargar el supersalto y abrir el menú a la vez dejaría la carga a medias:
	# se cancela sin salto (nada se dispara solo al cerrar el menú).
	_cancelar_super()
	# Si la mole está a MEDIO levantar, se cancela limpiamente: con el control
	# congelado el clip no puede completarse y la piedra acabaría colocada mal.
	if _esta_levantando_roca():
		_soltar_roca_interrumpida()

func _on_menu_transformaciones_cerrado() -> void:
	_menu_abierto = false

# Punto único donde el menú conecta con el sistema de transformación existente.
# Añadir una transformación futura = añadir su caso aquí (y marcarla como
# desbloqueada en MenuTransformaciones.TRANSFORMACIONES). El menú no cambia.
func _on_transformacion_elegida(id: StringName) -> void:
	match id:
		&"velocista":
			_cambiar_forma_con_efecto(Forma.VELOCISTA)
		&"pes":
			_cambiar_forma_con_efecto(Forma.ACUATICO)
		&"tanque":
			_cambiar_forma_con_efecto(Forma.FUERZA)
		_:
			pass

# =============================================================== TRANSFORMACIÓN
func _alternar_forma() -> void:
	# La tecla G alterna hacia VELOCISTA (desde humano o acuático) y de vuelta a humano.
	if forma == Forma.VELOCISTA:
		_entrar_humano()
	else:
		_entrar_velocista()

# Transición visual al cambiar de forma. Reproduce el efecto de EfectoTransformacion
# (el MISMO de la transformación velocista), cambia de forma en su pico y espera a
# que el efecto termine antes de devolver el control. No duplica el sistema de efectos.
func _transicionar(destino: int) -> void:
	if _transformando:
		return
	_transformando = true
	var id_destino: StringName = _id_forma(destino)
	if COLORES_TRANSFORMACION.has(id_destino):
		efecto_transf.establecer_color(COLORES_TRANSFORMACION[id_destino])
	efecto_transf.reproducir()
	await efecto_transf.pico_alcanzado
	match destino:
		Forma.VELOCISTA:
			_entrar_velocista()
		Forma.ACUATICO:
			_entrar_acuatico()
		Forma.FUERZA:
			_entrar_fuerza()
		_:
			_entrar_humano()
	await efecto_transf.terminado
	_transformando = false

func _id_forma(id: int) -> StringName:
	match id:
		Forma.VELOCISTA:
			return &"velocista"
		Forma.ACUATICO:
			return &"pes"
		Forma.FUERZA:
			return &"tanque"
		_:
			return &"humano"

# Interruptor directo (tecla G): alterna humano <-> velocista.
func _alternar_forma_con_efecto() -> void:
	var destino := Forma.HUMANO if forma == Forma.VELOCISTA else Forma.VELOCISTA
	_transicionar(destino)

# Elige una forma desde el menú radial (F): si ya se está en esa forma, vuelve
# a humano. Así cualquier transformación se puede "desactivar" desde el HUD.
func _cambiar_forma_con_efecto(destino: int) -> void:
	if forma == destino:
		destino = Forma.HUMANO
	_transicionar(destino)

func _entrar_velocista() -> void:
	forma = Forma.VELOCISTA
	_detener_acuatico()
	_detener_fuerza()
	h_salto_aire = false
	h_agachado = false
	pivote.position.y = h_pivote_y_base
	estado = Estado.NORMAL
	velocity = Vector3.ZERO
	# La representación cambia; el cuerpo, la colisión y la cámara no.
	humano.visible = false
	acuatico.visible = false
	fuerza.visible = false
	visual.visible = true
	_anim_actual = ""
	_salto_forzado = false
	_ataque_activo = false
	_emote_activo = false
	_bloqueo_anim = 0.0
	_reproducir_anim(ANIM_INACTIVO, BLEND_TRANSFORMACION, true)
	estadisticas.aplicar_forma(id_forma())
	forma_cambiada.emit(id_forma())

func _entrar_acuatico() -> void:
	forma = Forma.ACUATICO
	_detener_velocista()
	_detener_fuerza()
	a_salto_aire = false
	a_agachado = false
	a_ataque_activo = false
	a_t_ataque = 0.0
	pivote.position.y = h_pivote_y_base
	estado = Estado.NORMAL
	velocity = Vector3.ZERO
	# La representación cambia; el cuerpo, la colisión y la cámara no.
	humano.visible = false
	visual.visible = false
	fuerza.visible = false
	acuatico.visible = true
	if anim_acuatico != null:
		anim_acuatico.speed_scale = 1.0
	_reproducir_acuatico(ANIM_A_IDLE, BLEND_TRANSFORMACION, true)
	estadisticas.aplicar_forma(id_forma())
	forma_cambiada.emit(id_forma())

func _entrar_humano() -> void:
	forma = Forma.HUMANO
	_detener_velocista()
	_detener_acuatico()
	_detener_fuerza()
	visual.visible = false
	acuatico.visible = false
	fuerza.visible = false
	humano.visible = true
	h_salto_aire = false
	_reproducir_humano(ANIM_H_IDLE, BLEND_TRANSFORMACION)
	estadisticas.aplicar_forma(id_forma())
	forma_cambiada.emit(id_forma())

# Limpia el estado de la forma acuática al salir de ella.
func _detener_acuatico() -> void:
	a_salto_aire = false
	a_agachado = false
	a_ataque_activo = false
	a_t_ataque = 0.0
	# Cancela cualquier habilidad en curso y su carga (no debe quedar nada activo).
	a_en_habilidad = false
	a_t_habilidad = 0.0
	a_pendiente = 0
	a_pendiente_t = 0.0
	a_dir_ataque = Vector3.ZERO
	_cancelar_carga_agua()
	if anim_acuatico != null:
		anim_acuatico.speed_scale = 1.0

func _entrar_fuerza() -> void:
	forma = Forma.FUERZA
	_detener_velocista()
	_detener_acuatico()
	f_salto_aire = false
	f_agachado = false
	f_embestiendo = false
	f_slam = false
	f_ataque = false
	f_recuperacion = 0.0
	f_super_cargando = false
	f_super_carga = 0.0
	f_roca_lista = false
	_limpiar_efectos_carga()
	pivote.position.y = h_pivote_y_base
	estado = Estado.NORMAL
	velocity = Vector3.ZERO
	# La representación cambia; el cuerpo, la colisión y la cámara no.
	humano.visible = false
	visual.visible = false
	acuatico.visible = false
	fuerza.visible = true
	_f_anim_actual = ""
	_f_ataque_clip = ""
	_f_bloqueo_anim = 0.0
	_reproducir_fuerza(ANIM_F_IDLE, BLEND_TRANSFORMACION, true)
	estadisticas.aplicar_forma(id_forma())
	forma_cambiada.emit(id_forma())

# Limpia el estado de la forma Fuerza al salir de ella: cancela embestida,
# pisotón y una roca todavía sujeta (no deja estados activos al cambiar).
func _detener_fuerza() -> void:
	f_embestiendo = false
	f_t_embestida = 0.0
	f_slam = false
	f_ataque = false
	_f_ataque_clip = ""
	_f_combo_pedido = false
	_actualizar_mira_roca(false)
	f_recuperacion = 0.0
	f_embestida_golpeados.clear()
	if f_roca != null and is_instance_valid(f_roca):
		if not f_roca.volando:
			f_roca.queue_free()
	f_roca = null
	f_cargando_roca = false
	f_roca_lista = false
	_f_bloqueo_anim = 0.0
	# Cargar el supersalto no cruza de forma: se cancela sin salto.
	_cancelar_super()
	# El IK de la roca se apaga sin dejar nada activo al cambiar de forma.
	if _f_ik != null:
		_f_ik.peso_objetivo = 0.0
		_f_ik.peso_actual = 0.0
		_f_ik.soltar_roca()
	if anim_fuerza != null:
		anim_fuerza.speed_scale = 1.0
	_f_anim_actual = ""

# Apaga y limpia todo lo que la forma velocista pudiera tener activo, para que
# al volver a humano no quede ningún efecto a medias.
func _detener_velocista() -> void:
	estado = Estado.NORMAL
	velocity = Vector3.ZERO
	efectos.terminar_dash()
	efectos.terminar_carga()
	efectos.terminar_ejecucion()
	efectos.cancelar_ataque()
	trazador.limpiar()
	combate.cancelar_combo()
	pivote.vibracion = 0.0
	pivote.permitir_look = true
	pivote.objetivo_largo = pivote.largo_base
	pivote.objetivo_fov = pivote.fov_base
	pivote.definir_pitch(-0.25)
	pivote.position.y = h_pivote_y_base

# ============================================================== FORMA HUMANA (Leo)
func _direccion_entrada() -> Vector3:
	var base := pivote.global_transform.basis
	var adelante := -base.z
	adelante.y = 0.0
	adelante = adelante.normalized()
	var derecha := base.x
	derecha.y = 0.0
	derecha = derecha.normalized()
	var v := Vector2.ZERO
	if Input.is_action_pressed("mover_adelante"):
		v.y -= 1.0
	if Input.is_action_pressed("mover_atras"):
		v.y += 1.0
	if Input.is_action_pressed("mover_izquierda"):
		v.x -= 1.0
	if Input.is_action_pressed("mover_derecha"):
		v.x += 1.0
	if v == Vector2.ZERO:
		return Vector3.ZERO
	v = v.normalized()
	return (adelante * (-v.y) + derecha * v.x).normalized()

func _procesar_humano(delta: float) -> void:
	if h_salto_aire and is_on_floor():
		h_salto_aire = false

	# Agacharse con CTRL (misma mecánica que el Leo original): no mientras salta.
	h_agachado = Input.is_key_pressed(KEY_CTRL) and not h_salto_aire

	var dir := _direccion_entrada()
	var corriendo := Input.is_key_pressed(KEY_SHIFT) and not h_agachado
	var vel_objetivo := h_vel_caminar
	if h_agachado:
		vel_objetivo = H_VEL_AGACHADO
	elif corriendo:
		vel_objetivo = h_vel_correr

	var horiz := Vector3(velocity.x, 0.0, velocity.z)
	if dir.length() > 0.05:
		horiz = horiz.move_toward(dir * vel_objetivo, H_ACELERACION * delta)
	else:
		horiz = horiz.move_toward(Vector3.ZERO, H_DESACELERACION * delta)
	velocity.x = horiz.x
	velocity.z = horiz.z

	if not is_on_floor():
		velocity.y -= H_GRAVEDAD * delta
	elif velocity.y < 0.0:
		velocity.y = -0.1

	# No se puede saltar agachado.
	if is_on_floor() and Input.is_action_just_pressed("saltar") and not h_agachado:
		velocity.y = H_SALTO
		_iniciar_salto_humano()

	move_and_slide()
	_orientar_humano(delta, dir)
	_actualizar_altura_camara(delta)
	_actualizar_anim_humano(delta)

func _orientar_humano(delta: float, dir: Vector3) -> void:
	if dir.length() < 0.05:
		return
	var objetivo := atan2(-dir.x, -dir.z)
	humano.rotation.y = lerp_angle(humano.rotation.y, objetivo, 12.0 * delta)

func _iniciar_salto_humano() -> void:
	h_salto_aire = true
	var rapidez := Vector2(velocity.x, velocity.z).length()
	h_anim_salto = ANIM_H_SALTO_CORRIENDO if rapidez > H_VELOCIDAD_SALTO_CORRIENDO else ANIM_H_SALTO
	_reproducir_humano(h_anim_salto)

func _actualizar_anim_humano(delta: float) -> void:
	if anim_humano == null:
		return
	if h_salto_aire:
		anim_humano.speed_scale = 1.0
		_reproducir_humano(h_anim_salto)
		return
	var rapidez := Vector2(velocity.x, velocity.z).length()
	if h_agachado:
		if rapidez < H_UMBRAL_MOVIMIENTO:
			_animar_agachado_quieto(delta)
		else:
			_reproducir_humano(ANIM_H_CROUCH_WALK, H_MEZCLA_AGACHARSE)
			anim_humano.speed_scale = clampf(rapidez / H_VEL_AGACHADO, 0.4, 1.8)
		return
	anim_humano.speed_scale = 1.0
	if rapidez < H_UMBRAL_MOVIMIENTO:
		_reproducir_humano(ANIM_H_IDLE)
	elif Input.is_key_pressed(KEY_SHIFT):
		_reproducir_humano(_clip_humano([ANIM_H_RUN, ANIM_H_WALK]))
	else:
		_reproducir_humano(ANIM_H_WALK)

# Reproduce un clip humano sólo si no está ya sonando (no lo reinicia cada frame).
func _reproducir_humano(nombre: String, mezcla: float = H_MEZCLA) -> void:
	if anim_humano == null or not anim_humano.has_animation(nombre):
		return
	if anim_humano.current_animation != nombre or not anim_humano.is_playing():
		anim_humano.speed_scale = 1.0
		anim_humano.play(nombre, mezcla)

# Devuelve el primer clip de la lista que exista en la librería de Leo.
func _clip_humano(opciones: Array) -> String:
	for opcion in opciones:
		if anim_humano.has_animation(opcion):
			return opcion
	return ANIM_H_IDLE

# Baja el pivote de la cámara al agacharse y lo devuelve a su altura al levantarse.
func _actualizar_altura_camara(delta: float) -> void:
	var objetivo := h_pivote_y_base - (H_ALTURA_AGACHADO if h_agachado else 0.0)
	pivote.position.y = lerpf(pivote.position.y, objetivo, 8.0 * delta)

# Agachado y quieto: si existe "crouch_idle" se reproduce; si no, se usa el ciclo de
# crouch_walk y, tras el fundido de entrada, se congela la pose (igual que el Leo humano).
func _animar_agachado_quieto(delta: float) -> void:
	if anim_humano.has_animation(ANIM_H_CROUCH_IDLE):
		anim_humano.speed_scale = 1.0
		_reproducir_humano(ANIM_H_CROUCH_IDLE, H_MEZCLA_AGACHARSE)
		return
	if anim_humano.current_animation != ANIM_H_CROUCH_WALK or not anim_humano.is_playing():
		_reproducir_humano(ANIM_H_CROUCH_WALK, H_MEZCLA_AGACHARSE)
		anim_humano.speed_scale = 1.0
		h_espera_congelar = H_MEZCLA_AGACHARSE
		return
	if h_espera_congelar > 0.0:
		h_espera_congelar -= delta
		return
	anim_humano.speed_scale = 0.0

# ============================================================== FORMA ACUÁTICA (Pes)
# Misma mecánica de locomoción que la forma humana (mismo cuerpo, colisión y cámara),
# pero reproduciendo los clips ORIGINALES del módulo acuático (sin renombrarlos).
func _procesar_acuatico(delta: float) -> void:
	_tick_cooldowns_agua(delta)
	# Mientras corre una habilidad acuática (1-4): sin movimiento horizontal; sólo
	# gravedad y apoyo. La animación la manda la habilidad, no se sobrescribe.
	if a_en_habilidad:
		_actualizar_habilidad_agua(delta)
		velocity.x = 0.0
		velocity.z = 0.0
		if not is_on_floor():
			velocity.y -= H_GRAVEDAD * delta
		elif velocity.y < 0.0:
			velocity.y = -0.1
		move_and_slide()
		return

	if a_salto_aire and is_on_floor():
		a_salto_aire = false

	a_agachado = Input.is_key_pressed(KEY_CTRL) and not a_salto_aire

	var dir := _direccion_entrada()
	var corriendo := Input.is_key_pressed(KEY_SHIFT) and not a_agachado
	var vel_objetivo := h_vel_caminar
	if a_agachado:
		vel_objetivo = H_VEL_AGACHADO
	elif corriendo:
		vel_objetivo = h_vel_correr

	var horiz := Vector3(velocity.x, 0.0, velocity.z)
	if dir.length() > 0.05:
		horiz = horiz.move_toward(dir * vel_objetivo, H_ACELERACION * delta)
	else:
		horiz = horiz.move_toward(Vector3.ZERO, H_DESACELERACION * delta)
	velocity.x = horiz.x
	velocity.z = horiz.z

	if not is_on_floor():
		velocity.y -= H_GRAVEDAD * delta
	elif velocity.y < 0.0:
		velocity.y = -0.1

	if is_on_floor() and Input.is_action_just_pressed("saltar") and not a_agachado:
		velocity.y = H_SALTO
		a_salto_aire = true
		_reproducir_acuatico(ANIM_A_JUMP, H_MEZCLA, true)

	# Ataque propio del personaje acuático: sólo reproduce SU animación. No crea
	# un sistema de combate nuevo ni usa el sistema de combate del velocista.
	if is_on_floor() and Input.is_action_just_pressed("atacar") and not a_ataque_activo and not a_agachado:
		_iniciar_ataque_acuatico()

	move_and_slide()
	# Se orienta TODO el cuerpo hacia la dirección de desplazamiento, igual que la
	# forma Fuerza: hacia atrás (S, S+A, S+D) se camina con el MISMO clip de caminar
	# hacia adelante, girando el cuerpo; no hace falta un clip de retroceso ni se
	# queda postura de guardia. El giro es sobre el nodo visual (Acuatico), así que
	# ni la cámara, ni las colisiones, ni el movimiento general se ven afectados.
	_orientar_acuatico(delta, dir)
	_actualizar_anim_acuatico(delta)

func _iniciar_ataque_acuatico() -> void:
	a_ataque_activo = true
	a_t_ataque = _duracion_clip_acuatico(ANIM_A_ATTACK)
	_reproducir_acuatico(ANIM_A_ATTACK, BLEND_ATAQUE, true)

func _duracion_clip_acuatico(nombre: String) -> float:
	if anim_acuatico == null or not anim_acuatico.has_animation(nombre):
		return 0.3
	var a := anim_acuatico.get_animation(nombre)
	return a.length if a != null else 0.3

func _orientar_acuatico(delta: float, dir: Vector3) -> void:
	if dir.length() < 0.05:
		return
	var objetivo := atan2(-dir.x, -dir.z)
	acuatico.rotation.y = lerp_angle(acuatico.rotation.y, objetivo, 12.0 * delta)

func _actualizar_anim_acuatico(delta: float) -> void:
	if anim_acuatico == null:
		return
	if a_ataque_activo:
		a_t_ataque -= delta
		anim_acuatico.speed_scale = 1.0
		_reproducir_acuatico(ANIM_A_ATTACK)
		if a_t_ataque <= 0.0:
			a_ataque_activo = false
		return
	if a_salto_aire:
		anim_acuatico.speed_scale = 1.0
		if velocity.y > 0.0:
			_reproducir_acuatico(ANIM_A_JUMP)
		else:
			_reproducir_acuatico(ANIM_A_FALL)
		return
	var rapidez := Vector2(velocity.x, velocity.z).length()
	if a_agachado:
		anim_acuatico.speed_scale = 1.0
		if rapidez < H_UMBRAL_MOVIMIENTO:
			_reproducir_acuatico(ANIM_A_CROUCH_IDLE)
		else:
			_reproducir_acuatico(ANIM_A_CROUCH_WALK)
		return
	anim_acuatico.speed_scale = 1.0
	if rapidez < H_UMBRAL_MOVIMIENTO:
		_reproducir_acuatico(ANIM_A_IDLE)
	elif Input.is_key_pressed(KEY_SHIFT):
		_reproducir_acuatico(ANIM_A_RUN)
	else:
		_reproducir_acuatico(ANIM_A_WALK)

# Reproduce un clip acuático por su nombre si no está ya sonando (no lo reinicia cada frame).
func _reproducir_acuatico(nombre: String, mezcla: float = H_MEZCLA, forzar: bool = false) -> void:
	if anim_acuatico == null or not anim_acuatico.has_animation(nombre):
		return
	if forzar or anim_acuatico.current_animation != nombre or not anim_acuatico.is_playing():
		anim_acuatico.speed_scale = 1.0
		anim_acuatico.play(nombre, mezcla)

# ------------------------------------------------ Habilidades acuáticas (1-4)
func _tick_cooldowns_agua(delta: float) -> void:
	for key in a_cooldowns.keys():
		if a_cooldowns[key] > 0.0:
			a_cooldowns[key] = maxf(a_cooldowns[key] - delta, 0.0)

# Arranca la habilidad [param idx] (1..4): enfriamiento, animación y carga en la mano.
func _intentar_habilidad_agua(idx: int) -> void:
	if forma != Forma.ACUATICO or _transformando:
		return
	if idx < 1 or idx > ABIL_AGUA.size():
		return
	if a_en_habilidad or a_pendiente > 0:
		return
	if float(a_cooldowns.get(idx, 0.0)) > 0.0:
		return
	if not is_on_floor():
		return
	var nombre_estado := "ability_%d" % idx
	if anim_acuatico == null or not anim_acuatico.has_animation(nombre_estado):
		return
	a_en_habilidad = true
	a_t_habilidad = _duracion_clip_acuatico(nombre_estado) + 0.15
	a_pendiente = idx
	a_pendiente_t = 0.0
	# La dirección se fija AQUÍ (instante de la pulsación), desde la cámara actual.
	# Queda congelada para este lanzamiento: mover la cámara después no la cambia.
	a_dir_ataque = _direccion_camara_horizontal()
	# El personaje se orienta hacia donde va a salir la habilidad (coherente con la cámara).
	acuatico.rotation.y = atan2(-a_dir_ataque.x, -a_dir_ataque.z)
	anim_acuatico.speed_scale = 1.0
	anim_acuatico.play(nombre_estado, BLEND_ATAQUE)
	_iniciar_carga_agua(idx)

# Dirección horizontal (sin componente Y) hacia la que mira la cámara ahora mismo.
# Es la base de la dirección de las habilidades acuáticas y del movimiento.
func _direccion_camara_horizontal() -> Vector3:
	var f := -pivote.global_transform.basis.z
	f.y = 0.0
	if f.length_squared() < 0.0001:
		return Vector3.FORWARD
	return f.normalized()

func _actualizar_habilidad_agua(delta: float) -> void:
	a_t_habilidad -= delta
	if a_pendiente > 0:
		a_pendiente_t += delta
		# Seguro anti-atasco: si la pista de método no llegara, se libera igual.
		if a_pendiente_t > float(ABIL_AGUA[a_pendiente - 1]["release"]) + 0.35:
			_liberar_habilidad_agua(a_pendiente)
	if a_t_habilidad <= 0.0 and a_pendiente <= 0:
		a_en_habilidad = false

# La pista de método de las animaciones ability_N (nodo Acuatico) llama aquí.
func _notificar_liberacion_agua(nombre_estado: String) -> void:
	if a_pendiente <= 0:
		return
	if nombre_estado != "ability_%d" % a_pendiente:
		return
	_liberar_habilidad_agua(a_pendiente)

# Crea el objeto de la habilidad en la mano, mirando hacia donde mira el personaje.
# Reutiliza el objeto del módulo acuático: vuela, choca y hace daño solo.
func _liberar_habilidad_agua(idx: int) -> void:
	if idx < 1 or idx > ABIL_AGUA.size():
		a_pendiente = 0
		return
	a_pendiente = 0
	a_cooldowns[idx] = float(ABIL_AGUA[idx - 1]["cooldown"])
	_release_charge_agua()
	var def: Dictionary = ABIL_AGUA[idx - 1]
	var ability: WaterAbility = (def["script"] as GDScript).new() as WaterAbility
	if ability == null:
		return
	# Dirección capturada al pulsar la habilidad (no la del cuerpo, que no gira).
	var forward := a_dir_ataque
	if forward.length_squared() < 0.0001:
		forward = _direccion_camara_horizontal()
	forward = forward.normalized()
	# ORIGEN: la mano que lanza, ligeramente por delante de ella y alineada con la
	# dirección del ataque. Sigue la animación (si el clip sube o adelanta la mano,
	# el efecto sube o se adelanta con ella). Si el modelo no tuviera el hueso, cae
	# al plan B de siempre para no perder la habilidad.
	var origin := _origen_ataque_agua(forward)
	ability.damage = float(def["damage"])
	ability.hit_radius = float(def["hit_radius"])
	ability.speed = float(def["speed"])
	ability.lifetime = float(def["lifetime"])
	ability.knockback = float(def["knockback"])
	ability.damage_kind = def["kind"]
	if def.has("field_radius"):
		ability.set("field_radius", float(def["field_radius"]))
	if def.has("field_duration"):
		ability.set("field_duration", float(def["field_duration"]))
	if def.has("trap_duration"):
		ability.set("trap_duration", float(def["trap_duration"]))
	var host := get_parent()
	if host == null:
		host = self
	host.add_child(ability)
	ability.setup(self, origin, forward)
	# Orienta el objeto con la dirección de salida (la oleada arma su muro en
	# local, así que su rotación importa; los proyectiles esféricos no se ven afectados).
	ability.rotation.y = atan2(-forward.x, -forward.z)

# Agua que se junta en las manos mientras carga (reutiliza el VFX del módulo).
func _iniciar_carga_agua(idx: int) -> void:
	_cancelar_carga_agua()
	var host := get_parent()
	if host == null:
		return
	var carga: Node3D = preload("res://personaje/transformaciones/acuatica/vfx/water_charge.gd").new() as Node3D
	if carga == null:
		return
	carga.set("player", self)
	carga.set("duration", float(ABIL_AGUA[idx - 1]["release"]))
	carga.set("underwater", false)
	carga.set("radius", float(ABIL_AGUA[idx - 1]["carga"]))
	host.add_child(carga)
	a_carga = carga

func _release_charge_agua() -> void:
	if a_carga != null and is_instance_valid(a_carga):
		a_carga.call("release")
	a_carga = null

func _cancelar_carga_agua() -> void:
	if a_carga != null and is_instance_valid(a_carga):
		a_carga.queue_free()
	a_carga = null

# --- Mano de lanzamiento (agua) --------------------------------------------
# Esqueleto del modelo acuático (cacheado). Se busca dentro del nodo Visual, que
# es el "slot" del modelo, para no depender de una ruta fija si el modelo cambia.
func _skeleton_agua() -> Skeleton3D:
	if _esqueleto_agua != null and is_instance_valid(_esqueleto_agua):
		return _esqueleto_agua
	var modelo := acuatico.get_node_or_null("Visual")
	if modelo != null:
		_esqueleto_agua = _buscar_esqueleto(modelo)
	return _esqueleto_agua

func _buscar_esqueleto(nodo: Node) -> Skeleton3D:
	for hijo in nodo.get_children():
		if hijo is Skeleton3D:
			return hijo as Skeleton3D
		var profundo := _buscar_esqueleto(hijo)
		if profundo != null:
			return profundo
	return null

# Índice del hueso de una mano, probando los nombres que usan los modelos
# importados (Mixamo con "_" o ":"). -1 si no existe.
func _hueso_mano_agua(esqueleto: Skeleton3D, mano: StringName) -> int:
	if esqueleto == null:
		return -1
	var hueso := esqueleto.find_bone(mano)
	if hueso < 0:
		hueso = esqueleto.find_bone(StringName("mixamorig:" + String(mano)))
	if hueso < 0:
		hueso = esqueleto.find_bone(StringName("mixamorig_" + String(mano)))
	return hueso

# Posición de MUNDO del hueso de una mano. Vector3.INF si no hay esqueleto/hueso.
func _posicion_mano_agua(mano: StringName) -> Vector3:
	var esqueleto := _skeleton_agua()
	var hueso := _hueso_mano_agua(esqueleto, mano)
	if hueso < 0:
		return Vector3.INF
	return esqueleto.global_transform * esqueleto.get_bone_global_pose(hueso).origin

# Sitio del agua que el personaje SOSTIENE en la mano: es el ancla del balón y de
# las cargas de los hechizos. Lo pide water_charge.gd por este nombre.
func get_water_ball_position() -> Vector3:
	var esqueleto := _skeleton_agua()
	var hueso := _hueso_mano_agua(esqueleto, MANO_AGUA)
	if hueso < 0:
		return get_hand_center()
	var ancla: Transform3D = esqueleto.global_transform * esqueleto.get_bone_global_pose(hueso)
	return ancla.origin + ancla.basis * DESPLAZAMIENTO_MANO_AGUA

# Punto medio de las dos manos (plan B / compatibilidad con water_charge.gd).
func get_hand_center() -> Vector3:
	var der := _posicion_mano_agua(&"RightHand")
	var izq := _posicion_mano_agua(&"LeftHand")
	var ok_d := der.is_finite()
	var ok_i := izq.is_finite()
	if ok_d and ok_i:
		return (der + izq) * 0.5
	if ok_d:
		return der
	if ok_i:
		return izq
	return global_position + Vector3.UP * 1.25 + (-global_transform.basis.z) * 0.5

# Origen del proyectil: la mano que lanza, un poco por delante de ella (en la
# dirección del ataque). Si el modelo no tuviera el hueso, plan B: delante del
# pecho, para no romper la habilidad.
func _origen_ataque_agua(adelante: Vector3) -> Vector3:
	var mano := get_water_ball_position()
	if mano.is_finite():
		return mano + adelante * ADELANTE_MANO_AGUA
	return global_position + Vector3.UP * 1.25 + adelante * 0.5

# ============================================================== FORMA FUERZA
# Forma pesada: movimiento lento con inercia + 5 habilidades. Reutiliza los
# scripts/efectos del paquete res://Fuerza/ (FuerzaCombat, FuerzaVfx, FuerzaRock,
# FuerzaShockwave) sobre el MISMO cuerpo, colisión y cámara de Leo.
#
# OJO: el paquete Fuerza no trae su librería de animaciones en este proyecto
# (falta animations/FuerzaUniversal.tres), así que las habilidades se ejecutan a
# nivel de movimiento + efectos + daño, sin clips propios. Ver informe final.
func _procesar_fuerza(delta: float) -> void:
	# El ataque lo gobierna su clip real: dura lo que dura la animación y el
	# daño cae en su extensión (ver _procesar_ataque_fuerza).
	if f_ataque:
		_procesar_ataque_fuerza()
	f_recuperacion = maxf(f_recuperacion - delta, 0.0)

	if f_embestiendo:
		_procesar_embestida_fuerza(delta)
		return
	if f_slam:
		_procesar_slam_fuerza(delta)
		return

	if f_salto_aire and is_on_floor():
		f_salto_aire = false

	f_agachado = Input.is_key_pressed(KEY_CTRL) and not f_salto_aire
	var dir := _direccion_entrada()
	var corriendo := Input.is_key_pressed(KEY_SHIFT) and not f_agachado
	var vel := F_VEL_CAMINAR
	if f_agachado:
		vel = F_VEL_CAMINAR * 0.6
	elif corriendo:
		vel = F_VEL_CORRER
	if f_cargando_roca:
		vel *= 0.65
	# Freno corto mientras el golpe va camino del impacto; después el clip sólo
	# acompaña la recuperación y el control se alivia (Kick dura 1.6 s).
	if f_ataque:
		vel *= 0.2 if not _f_ataque_golpeado else 0.55
	elif f_recuperacion > 0.0:
		vel *= 0.2

	var horiz := Vector3(velocity.x, 0.0, velocity.z)
	if dir.length() > 0.05:
		horiz = horiz.move_toward(dir * vel, F_ACELERACION * delta)
	else:
		horiz = horiz.move_toward(Vector3.ZERO, F_DESACELERACION * delta)
	velocity.x = horiz.x
	velocity.z = horiz.z

	if not is_on_floor():
		velocity.y -= F_GRAVEDAD * delta
	elif velocity.y < 0.0:
		velocity.y = -0.1

	# --- Supersalto con carga (ESPACIO mantenido en el suelo) ---
	# Mantener ESPACIO carga el salto; un toque corto sigue siendo el salto
	# normal de siempre. Durante el levantamiento de la roca el salto se ignora
	# (la mole a medio camino no debe quedar colgada en el aire). La carga se
	# cancela sin salto si algo la rompe: perder el suelo, agacharse, empezar
	# otra habilidad u abrir el menú.
	if f_super_cargando:
		if not is_on_floor() or f_agachado or f_embestiendo or f_slam or f_cargando_roca:
			_cancelar_super()
		elif not Input.is_action_pressed("saltar"):
			_ejecutar_super()
		else:
			f_super_carga = minf(f_super_carga + delta, F_SUPER_CARGA_MAX)
			_actualizar_carga_super()
	elif is_on_floor() and Input.is_action_just_pressed("saltar") and not f_agachado \
			and not _esta_levantando_roca():
		if _puede_cargar_super():
			f_super_cargando = true
			f_super_carga = 0.0
			_f_flash_indicador = 0.0
			_actualizar_carga_super()
		else:
			# Con otra habilidad en curso, el toque de ESPACIO salta como antes.
			velocity.y = F_SALTO
			f_salto_aire = true
			_reproducir_fuerza(ANIM_F_JUMP, BLEND_SALTO, true)

	# El indicador de carga se queda un instante a tope tras el supersalto.
	if _f_flash_indicador > 0.0 and not f_super_cargando:
		_f_flash_indicador = maxf(_f_flash_indicador - delta, 0.0)
		_actualizar_indicador_super(1.0, _f_flash_indicador > 0.0)

	move_and_slide()
	_orientar_fuerza(delta, dir)
	_actualizar_roca_fuerza()

	# Con la roca en las manos (Q), el clic IZQUIERDO lanza; no pega. Hasta que
	# el clip de levantamiento no ha TERMINADO de verdad (señal del
	# AnimationPlayer, con el selector de clips como red de seguridad) no se
	# atiende ningún clic: la mole tiene que estar arriba antes de apuntar.
	if f_cargando_roca and f_roca != null:
		if not f_roca_lista and (anim_fuerza == null \
				or anim_fuerza.current_animation != ANIM_F_ROCKLIFT):
			f_roca_lista = true
		# Modo apuntado: con la mole ya arriba, el crosshair marca el centro de
		# la pantalla y el lanzamiento sale hacia ese punto objetivo.
		_actualizar_mira_roca(f_roca_lista)
		if f_roca_lista and Input.is_action_just_pressed("atacar"):
			_lanzar_roca_fuerza()
		return
	if f_ataque or f_recuperacion > 0.0:
		return
	# Cuerpo a cuerpo: clic izquierdo = puñetazo (doble = combo 1-2), derecho = patada.
	# Golpear cancela una carga de supersalto a medias: la carga nunca decide
	# por el jugador ni se dispara sola más tarde.
	if Input.is_action_just_pressed("atacar"):
		if f_super_cargando:
			_cancelar_super()
		_golpe_fuerza(false)
	elif Input.is_action_just_pressed("cargar_poder"):
		if f_super_cargando:
			_cancelar_super()
		_golpe_fuerza(true)

func _orientar_fuerza(delta: float, dir: Vector3) -> void:
	if dir.length() < 0.05:
		return
	var objetivo := atan2(-dir.x, -dir.z)
	fuerza.rotation.y = lerp_angle(fuerza.rotation.y, objetivo, 8.0 * delta)

# --- Animación Fuerza (librería UniversalLibrary -> FuerzaUniversal.tres) ---
# Reproduce los clips del AnimationPlayer del nodo $Fuerza por su nombre simple.
# La elección del clip sólo refleja el estado que ya calcula la lógica de arriba:
# NO cambia la velocidad, los controles ni las habilidades de la transformación.
func _reproducir_fuerza(nombre: String, mezcla: float = H_MEZCLA, forzar: bool = false) -> void:
	if anim_fuerza == null or not anim_fuerza.has_animation(nombre):
		return
	if forzar or _f_anim_actual != nombre:
		_f_anim_actual = nombre
		anim_fuerza.speed_scale = 1.0
		anim_fuerza.play(nombre, mezcla)

# Elige cada fotograma el clip de Fuerza que corresponde al estado. Los clips de
# golpe/roca/pisotón se sostienen un instante (_f_bloqueo_anim) para que lleguen a
# verse, pero ese bloqueo sólo afecta a la animación: el movimiento nunca se frena.
func _actualizar_anim_fuerza(delta: float) -> void:
	if anim_fuerza == null:
		return
	if _f_bloqueo_anim > 0.0:
		_f_bloqueo_anim = maxf(_f_bloqueo_anim - delta, 0.0)
		return
	_reproducir_fuerza(_clip_fuerza())

func _clip_fuerza() -> String:
	# Cargando el supersalto (ESPACIO mantenido en el suelo): flexión de carga.
	if f_super_cargando:
		return ANIM_F_CARGA
	# Cuerpo a cuerpo: manda el clip fijado al golpear (jab / cross / patada).
	if f_ataque and not _f_ataque_clip.is_empty():
		return _f_ataque_clip
	# Embestida con el hombro, pisotón aéreo y su recuperación.
	if f_embestiendo:
		return ANIM_F_SHOULDERRUN
	if f_slam:
		return ANIM_F_AIRSLAM
	if f_recuperacion > 0.0:
		return ANIM_F_SHOULDERECOVER
	# Llevar la roca (Q): sostenerla quieto o andar con ella.
	if f_cargando_roca:
		return ANIM_F_ROCKCARRYWALK if _rapidez_horizontal() > H_UMBRAL_MOVIMIENTO else ANIM_F_ROCKCARRY
	# En el aire: subir = salto, caer = caída.
	if f_salto_aire:
		return ANIM_F_JUMP if velocity.y > 0.0 else ANIM_F_FALL
	# Agachado: quieto o andando agachado.
	if f_agachado:
		return ANIM_F_CROUCHWALK if _rapidez_horizontal() > H_UMBRAL_MOVIMIENTO else ANIM_F_CROUCH
	# Locomoción normal.
	if _rapidez_horizontal() < H_UMBRAL_MOVIMIENTO:
		return ANIM_F_IDLE
	return ANIM_F_RUN if Input.is_key_pressed(KEY_SHIFT) else ANIM_F_WALK

func _rapidez_horizontal() -> float:
	return Vector2(velocity.x, velocity.z).length()

# --- Embestida con el hombro (R) ---
func _iniciar_embestida_fuerza() -> void:
	# Cargar el supersalto ocupa la habilidad igual que la roca: nada la
	# interrumpe a medias (se suelta ESPACIO y ya se decide).
	if f_embestiendo or f_cargando_roca or f_super_cargando or not is_on_floor():
		return
	f_embestiendo = true
	f_t_embestida = 0.0
	f_embestida_golpeados.clear()
	var d := _direccion_entrada()
	if d.length() < 0.05:
		d = -pivote.global_transform.basis.z
		d.y = 0.0
	f_embestida_dir = d.normalized() if d.length_squared() > 0.0001 else Vector3.FORWARD
	_reproducir_fuerza(ANIM_F_SHOULDERPREP, BLEND_ATAQUE, true)
	_f_bloqueo_anim = 0.18
	FuerzaVfx.polvo(get_parent(), global_position, 1.2, 16, Color(0.62, 0.55, 0.45), 0.7, 2.6)

func _procesar_embestida_fuerza(delta: float) -> void:
	f_t_embestida += delta
	velocity.x = f_embestida_dir.x * F_EMBESTIDA_VEL
	velocity.z = f_embestida_dir.z * F_EMBESTIDA_VEL
	if not is_on_floor():
		velocity.y -= F_GRAVEDAD * delta
	elif velocity.y < 0.0:
		velocity.y = -0.1
	move_and_slide()
	_orientar_fuerza(delta, f_embestida_dir)
	# Golpea a lo que pille delante, una sola vez por oponente.
	var punto := global_position + Vector3.UP * 1.1 + f_embestida_dir * 0.6
	for objetivo in _objetivos_en_esfera(punto, F_EMBESTIDA_RADIO):
		if f_embestida_golpeados.has(objetivo):
			continue
		f_embestida_golpeados.append(objetivo)
		_golpear_objetivo_fuerza(objetivo, punto, F_EMBESTIDA_DANIO, 14.0)
		FuerzaVfx.chispas(get_parent(), punto, 0.9, 20, Color(1.0, 0.8, 0.4), 0.5, 6.0)
	if f_t_embestida >= F_EMBESTIDA_DUR or is_on_wall():
		f_embestiendo = false
		f_recuperacion = F_EMBESTIDA_RECUP
		velocity.x = 0.0
		velocity.z = 0.0

# --- Supersalto con golpe: pisotón aéreo (E en el aire) ---
func _intentar_slam_fuerza() -> void:
	if f_slam or is_on_floor():
		return
	f_slam = true

func _procesar_slam_fuerza(_delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	velocity.y = -F_SLAM_VEL
	move_and_slide()
	if is_on_floor():
		f_slam = false
		f_salto_aire = false
		_reproducir_fuerza(ANIM_F_SLAMIMPACT, BLEND_ATAQUE, true)
		_f_bloqueo_anim = 0.6
		var onda := FuerzaShockwave.new()
		onda.radius = F_SLAM_RADIO
		onda.damage = F_SLAM_DANIO
		onda.autor = self
		var host := get_parent()
		if host == null:
			host = self
		host.add_child(onda)
		# La onda lee su posición al final del fotograma (call_deferred en su
		# _ready), ya con este global_position aplicado: el impacto cae en el
		# punto real del aterrizaje. La normal del suelo tumba la onda en las
		# pendientes en lugar de dejarla flotando.
		onda.normal_suelo = get_floor_normal()
		onda.global_position = global_position + Vector3.UP * 0.05

# --- Arrancar piedra del suelo (Q) ---
# La roca NACE EN EL SUELO delante del personaje: el clip RockLift horneado
# (agacharse, agarrarla, tirón y alzarla sobre la cabeza) recorre con los
# brazos la misma trayectoria que aquí usa el IK, así que las manos acaban
# siempre sobre la superficie de la piedra y la subida sale de una pieza.
func _intentar_roca_fuerza() -> void:
	if f_roca != null or f_super_cargando or not is_on_floor():
		return
	# Mientras la última piedra LANZADA siga existiendo en el mundo no se
	# arranca otra: soltarla de las manos no significa que haya desaparecido.
	if not _puede_levantar_roca():
		return
	if _f_ik == null:
		_preparar_ik_roca()
	var roca := FuerzaRock.new()
	roca.radius = F_ROCA_TAM
	roca.damage = F_ROCA_DANIO
	roca.impact_radius = F_ROCA_RADIO
	roca.autor = self
	var host := get_parent()
	if host == null:
		host = self
	host.add_child(roca)
	roca.global_position = _posicion_roca_nace()
	roca.sujetar()
	f_roca = roca
	f_cargando_roca = true
	f_roca_lista = false
	_reproducir_fuerza(ANIM_F_ROCKLIFT, H_MEZCLA, true)
	# El levantamiento ocupa el clip ENTERO: es el fin real del clip (señal del
	# AnimationPlayer) lo que habilita apuntar y lanzar después.
	_f_bloqueo_anim = maxf(_duracion_fuerza(ANIM_F_ROCKLIFT), 0.2)

func _lanzar_roca_fuerza() -> void:
	# Defensa en profundidad: el tiro sólo existe con el levantamiento TERMINADO
	# (el llamador ya lo comprueba).
	if not f_roca_lista:
		return
	if f_roca == null or not is_instance_valid(f_roca):
		f_roca = null
		f_cargando_roca = false
		f_roca_lista = false
		return
	# El IK suelta primero: la roca sale volando desde donde la dejaron las
	# manos y el clip de lanzamiento recupera los brazos con su mezcla corta.
	if _f_ik != null:
		_f_ik.peso_objetivo = 0.0
		_f_ik.soltar_roca()
	# El tiro sale hacia el PUNTO OBJETIVO de la mira (raycast desde el centro
	# de la cámara), resolviendo el ángulo balístico con la gravedad y la
	# velocidad REALES de la piedra: cae donde apunta el crosshair.
	var objetivo := _punto_objetivo_mira()
	var gravedad_efectiva := float(ProjectSettings.get_setting(
		"physics/3d/default_gravity", 9.8)) * f_roca.gravity_scale
	var dir := _direccion_lanzamiento_roca(
		f_roca.global_position, objetivo, F_ROCA_VEL, gravedad_efectiva)
	f_roca.lanzar(dir, F_ROCA_VEL)
	# La piedra lanzada SIGUE existiendo (vuela, impacta y se desvanece sola):
	# se conserva la referencia hasta que salga del árbol de escena; mientras
	# exista, Q no puede arrancar otra del suelo.
	_f_roca_lanzada = f_roca
	if not _f_roca_lanzada.tree_exited.is_connected(_on_piedra_lanzada_fuera):
		_f_roca_lanzada.tree_exited.connect(_on_piedra_lanzada_fuera)
	f_roca = null
	f_cargando_roca = false
	f_roca_lista = false
	_actualizar_mira_roca(false)
	_reproducir_fuerza(ANIM_F_ROCKTHROW, BLEND_ATAQUE, true)
	_f_bloqueo_anim = maxf(_duracion_fuerza(ANIM_F_ROCKTHROW) - 0.05, 0.2)

# --- Agarre de la roca (trayectoria + IK, compartidos con el horneado) ---
# Mientras la roca está en las manos, cada fotograma se recoloca sobre la
# trayectoria del clip (suelo -> arco por delante -> centrada sobre la cabeza)
# en el espacio del esqueleto, y el IK de brazos lleva las manos a la
# superficie de la piedra. El peso del IK sigue la MISMA curva con la que se
# hornearon los brazos de los clips: cero pelea entre animación e IK.
func _actualizar_roca_fuerza() -> void:
	if f_roca == null or not is_instance_valid(f_roca) or f_roca.volando:
		return
	if _f_ik == null or _f_esqueleto == null:
		return
	var escala := _escala_esqueleto()
	if escala <= 0.0001:
		return
	var r_sk := F_ROCA_TAM / escala
	var c := _centro_roca_sk(r_sk)
	f_roca.global_position = _f_esqueleto.global_transform * c
	_f_ik.peso_objetivo = _peso_ik_roca()
	_f_ik.fijar_roca(c, r_sk)

func _escala_esqueleto() -> float:
	if _f_esqueleto == null:
		return 1.0
	return _f_esqueleto.global_transform.basis.get_scale().x

func _smooth_fuerza(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

## Fase (0..1) del levantamiento mientras suena RockLift; 1 en cualquier otro
## momento (roca ya arriba, en el carry).
func _fase_roca() -> float:
	if anim_fuerza == null:
		return 1.0
	if anim_fuerza.current_animation == ANIM_F_ROCKLIFT and anim_fuerza.current_animation_length > 0.0:
		return clampf(anim_fuerza.current_animation_position / anim_fuerza.current_animation_length,
			0.0, 1.0)
	return 1.0

## Peso del IK: durante el levantamiento sube con la misma curva que los brazos
## horneados (0 mientras el personaje se agacha, 1 al agarrar) y luego se queda.
func _peso_ik_roca() -> float:
	var u := _fase_roca()
	if u < 0.12:
		return 0.0
	if u < 0.46:
		return _smooth_fuerza((u - 0.12) / 0.34)
	return 1.0

## Centro de la roca en el espacio del esqueleto. MISMA trayectoria que el
## horneado: sube por delante mientras el cuerpo se yergue y una guarda la
## aparta de la cabeza en el tramo final. Termina centrada encima de ella.
func _centro_roca_sk(r_sk: float) -> Vector3:
	var u := _fase_roca()
	var ht := _altura_cabeza_sk()
	var fy := _smooth_fuerza((u - F_ROCA_U_SUBIDA) / (F_ROCA_U_FIN - F_ROCA_U_SUBIDA))
	var c := Vector3(0.0, lerpf(r_sk * 0.94, ht + r_sk * F_ROCA_CARRY_H + 0.005, fy),
		lerpf(F_ROCA_Z0, 0.02, fy))
	var hc := _centro_cabeza_sk()
	var min_dist := r_sk * (1.0 + F_ROCA_GUARDA)
	var d := c - hc
	if d.length_squared() > 0.000001 and d.length() < min_dist:
		var w_g := _smooth_fuerza((u - 0.58) / 0.10) * (1.0 - _smooth_fuerza((u - 0.86) / 0.14))
		c = c.lerp(hc + d.normalized() * min_dist, w_g)
	# Balanceo corto y contenido al caminar con la piedra (sólo en el carry).
	if u >= 0.999 and anim_fuerza != null and anim_fuerza.current_animation_length > 0.0 \
			and _rapidez_horizontal() > H_UMBRAL_MOVIMIENTO:
		var uw := anim_fuerza.current_animation_position / anim_fuerza.current_animation_length
		c.x += F_ROCA_SWAY * sin(uw * TAU)
	return c

func _altura_cabeza_sk() -> float:
	if _f_esqueleto == null or _f_idx_cabeza_top < 0:
		return 0.0
	return _f_esqueleto.get_bone_global_pose(_f_idx_cabeza_top).origin.y

func _centro_cabeza_sk() -> Vector3:
	if _f_esqueleto == null or _f_idx_cabeza < 0 or _f_idx_cabeza_top < 0:
		return Vector3.ZERO
	return (_f_esqueleto.get_bone_global_pose(_f_idx_cabeza).origin
		+ _f_esqueleto.get_bone_global_pose(_f_idx_cabeza_top).origin) * 0.5

func _duracion_fuerza(nombre: String) -> float:
	if anim_fuerza != null and anim_fuerza.has_animation(nombre):
		return anim_fuerza.get_animation(nombre).length
	return 0.0

## Dónde nace la roca: en el suelo, delante, justo bajo las manos del primer
## fotograma del levantamiento (mismo sitio que el clip horneado).
func _posicion_roca_nace() -> Vector3:
	if _f_esqueleto == null:
		return global_position + Vector3.UP * F_ROCA_TAM
	var r_sk := F_ROCA_TAM / maxf(_escala_esqueleto(), 0.0001)
	return _f_esqueleto.global_transform * Vector3(0.0, r_sk * 0.94, F_ROCA_Z0)

## Crea (una sola vez, la primera vez que se pulsa Q) el modificador de
## esqueleto que recoloca los brazos para agarrar la piedra. Los huesos y la
## escala se leen del propio rig.
func _preparar_ik_roca() -> void:
	_f_esqueleto = _buscar_esqueleto_fuerza()
	if _f_esqueleto == null:
		return
	_f_ik = FuerzaBrazosIK.new()
	_f_ik.name = "BrazosIKRoca"
	var objetivo_izq := Node3D.new()
	objetivo_izq.name = "LeftHandTarget"
	_f_ik.add_child(objetivo_izq)
	var objetivo_der := Node3D.new()
	objetivo_der.name = "RightHandTarget"
	_f_ik.add_child(objetivo_der)
	_f_ik.polo_salida = F_ROCA_POLO_SALIDA
	_f_ik.polo_abajo = F_ROCA_POLO_ABAJO
	_f_ik.polo_atras = F_ROCA_POLO_ATRAS
	_f_ik.peso_objetivo = 0.0
	_f_ik.peso_actual = 0.0
	_f_esqueleto.add_child(_f_ik)
	_f_idx_cabeza = _f_esqueleto.find_bone(&"mixamorig_Head")
	_f_idx_cabeza_top = _f_esqueleto.find_bone(&"mixamorig_HeadTop_End")
	if _f_idx_cabeza_top < 0:
		_f_idx_cabeza_top = _f_idx_cabeza

func _buscar_esqueleto_fuerza() -> Skeleton3D:
	if fuerza == null:
		return null
	var lista := fuerza.find_children("*", "Skeleton3D", true, false)
	if lista.is_empty():
		return null
	return lista[0] as Skeleton3D

# --- Supersalto con carga: lógica y presentación ------------------------------
# Mantener SPACE en el suelo junta fuerza (clip Charge + cámara que baja +
# temblor creciente, como el paquete original); al soltar, la potencia acumulada
# decide entre el salto normal (toque corto) y el supersalto (8..21 m/s con la
# gravedad real de la forma: F_GRAVEDAD = 25). El indicador reutiliza el mismo
# anillo del HUD, colocado abajo en el centro de la pantalla.

func _puede_cargar_super() -> bool:
	return not f_embestiendo and not f_slam and not f_cargando_roca \
		and not f_ataque and f_recuperacion <= 0.0

func _esta_levantando_roca() -> bool:
	return f_cargando_roca and not f_roca_lista

func _actualizar_carga_super() -> void:
	var fr := clampf(f_super_carga / F_SUPER_CARGA_MAX, 0.0, 1.0)
	# La cámara baja con la flexión y el cuerpo tiembla: se le ve juntando fuerza.
	pivote.position.y = h_pivote_y_base - F_SUPER_CAIDA_CAMARA * fr
	pivote.vibracion = lerpf(0.12, 0.6, fr)
	var t := F_SUPER_TEMBLOR * (0.35 + 0.65 * fr)
	fuerza.position = _f_fuerza_pos_base + Vector3(
		randf_range(-t, t), 0.0, randf_range(-t, t))
	_actualizar_indicador_super(fr, true)

func _cancelar_super() -> void:
	f_super_cargando = false
	f_super_carga = 0.0
	_f_flash_indicador = 0.0
	_limpiar_efectos_carga()

## Devuelve cámara, vibración, temblor e indicador a su sitio. Es seguro
## llamarla aunque no haya carga en curso (todo queda como estaba).
func _limpiar_efectos_carga() -> void:
	pivote.position.y = h_pivote_y_base
	pivote.vibracion = 0.0
	fuerza.position = _f_fuerza_pos_base
	_actualizar_indicador_super(0.0, false)

func _ejecutar_super() -> void:
	var cargado := f_super_carga
	f_super_cargando = false
	f_super_carga = 0.0
	_limpiar_efectos_carga()
	if not is_on_floor():
		# Red de seguridad: sin suelo no hay despegue.
		return
	if cargado < F_SUPER_CARGA_MIN:
		# Toque corto: el salto NORMAL de siempre, sin ceremonial.
		velocity.y = F_SALTO
		f_salto_aire = true
		_reproducir_fuerza(ANIM_F_JUMP, BLEND_SALTO, true)
		return
	var fr := clampf(inverse_lerp(F_SUPER_CARGA_MIN, F_SUPER_CARGA_MAX, cargado), 0.0, 1.0)
	velocity.y = lerpf(F_SUPER_VEL_MIN, F_SUPER_VEL_MAX, fr)
	f_salto_aire = true
	# La carrerilla se conserva tal cual; si salía casi parado, empujón mínimo
	# hacia donde apunta la entrada (o donde mira el modelo).
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if horizontal.length() < F_SUPER_IMPULSO:
		var rumbo := _direccion_entrada()
		if rumbo.length() < 0.05:
			rumbo = -fuerza.global_transform.basis.z
			rumbo.y = 0.0
			rumbo = rumbo.normalized() if rumbo.length_squared() > 0.0001 else Vector3.FORWARD
		velocity.x = rumbo.x * F_SUPER_IMPULSO
		velocity.z = rumbo.z * F_SUPER_IMPULSO
	_reproducir_fuerza(ANIM_F_SUPERJUMP, BLEND_SALTO, true)
	_f_bloqueo_anim = maxf(_duracion_fuerza(ANIM_F_SUPERJUMP), 0.2)
	# El indicador se queda un momento a tope: se ve la fuerza que llevaba.
	_f_flash_indicador = 0.35
	_actualizar_indicador_super(1.0, true)
	# El suelo se agrieta bajo los pies y la cámara lo nota.
	FuerzaVfx.polvo(get_parent(), global_position, 1.5 + fr, 20,
		Color(0.62, 0.55, 0.45), 0.9, 2.6 + fr * 2.0)
	FuerzaCombat.sacudir_camara(get_tree(), F_SUPER_SACUDIDA * (0.45 + 0.55 * fr))

func _preparar_indicador_super() -> void:
	if _f_relleno != null:
		return
	# Se cuelga del CanvasLayer del HUD que el jugador ya usa (mismo estilo que
	# los anillos de vida/escudo). Dos ColorRect DIRECTOS al HUD: el fondo
	# oscuro de la interfaz y el relleno dorado que crece con la carga.
	var capa := get_node_or_null("HUD") as CanvasLayer
	if capa == null:
		capa = CanvasLayer.new()
		capa.name = "HUDSuperSalto"
		capa.layer = 2
		add_child(capa)
	_f_fondo = ColorRect.new()
	_f_fondo.name = "BarraCargaFondo"
	_f_fondo.color = Color(0.08, 0.09, 0.12, 0.7)
	_f_fondo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_f_fondo.size = Vector2(F_SUPER_BARRA_LARGO + 12.0, F_SUPER_BARRA_ALTO + 12.0)
	capa.add_child(_f_fondo)
	_f_relleno = ColorRect.new()
	_f_relleno.name = "BarraCargaRelleno"
	_f_relleno.color = Color(1.0, 0.78, 0.35, 1.0)
	_f_relleno.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_f_relleno.size = Vector2(0.0, F_SUPER_BARRA_ALTO)
	capa.add_child(_f_relleno)
	_posicionar_indicador_super()
	_actualizar_indicador_super(0.0, false)

func _posicionar_indicador_super() -> void:
	if _f_fondo == null or _f_relleno == null:
		return
	var vp := get_viewport().get_visible_rect().size
	# Esquina inferior izquierda: zona siempre libre de la pantalla (el jugador
	# se ve centrado y el HUD de vida está en la derecha).
	var x := 52.0
	var y := vp.y - F_SUPER_BARRA_ALTO - 56.0
	_f_fondo.position = Vector2(x - 6.0, y - 6.0)
	_f_relleno.position = Vector2(x, y)

func _actualizar_indicador_super(valor: float, mostrar: bool) -> void:
	if _f_fondo == null or _f_relleno == null:
		return
	_f_fondo.visible = mostrar
	_f_relleno.visible = mostrar
	if not mostrar:
		return
	_posicionar_indicador_super()
	_f_relleno.size = Vector2(F_SUPER_BARRA_LARGO * clampf(valor, 0.0, 1.0),
		F_SUPER_BARRA_ALTO)
	# Al tope la barra late: avisa de que el salto saldrá a máxima potencia.
	var brillo := 0.0
	if valor >= 1.0:
		brillo = 0.25 + 0.25 * sin(Time.get_ticks_msec() / 1000.0 * 8.0)
	_f_relleno.color = Color(1.0, 0.78, 0.35).lerp(Color(1.0, 0.95, 0.7), brillo)

# --- Mira del apuntado de la roca ---------------------------------------------
# Cruz fina con contorno en el centro EXACTO de la pantalla. Vive en el
# CanvasLayer del HUD, así que queda fija aunque la cámara se mueva; sólo se
# enciende mientras la piedra está arriba, lista para apuntar y lanzar.
func _preparar_mira_roca() -> void:
	if _f_mira != null:
		return
	var capa := get_node_or_null("HUD") as CanvasLayer
	if capa == null:
		capa = CanvasLayer.new()
		capa.name = "HUDMiraRoca"
		capa.layer = 2
		add_child(capa)
	_f_mira = Control.new()
	_f_mira.name = "MiraRoca"
	_f_mira.mouse_filter = Control.MOUSE_FILTER_IGNORE
	capa.add_child(_f_mira)
	# Brazos de la cruz + punto central: [desplazamiento, tamaño] desde (0,0).
	var piezas: Array = [
		[Vector2(-F_MIRA_HUECO - F_MIRA_LARGO, -F_MIRA_GROSOR * 0.5),
			Vector2(F_MIRA_LARGO, F_MIRA_GROSOR)],
		[Vector2(F_MIRA_HUECO, -F_MIRA_GROSOR * 0.5),
			Vector2(F_MIRA_LARGO, F_MIRA_GROSOR)],
		[Vector2(-F_MIRA_GROSOR * 0.5, -F_MIRA_HUECO - F_MIRA_LARGO),
			Vector2(F_MIRA_GROSOR, F_MIRA_LARGO)],
		[Vector2(-F_MIRA_GROSOR * 0.5, F_MIRA_HUECO),
			Vector2(F_MIRA_GROSOR, F_MIRA_LARGO)],
		[Vector2(-F_MIRA_PUNTO * 0.5, -F_MIRA_PUNTO * 0.5),
			Vector2(F_MIRA_PUNTO, F_MIRA_PUNTO)],
	]
	for pieza in piezas:
		var pos: Vector2 = pieza[0]
		var tam: Vector2 = pieza[1]
		var sombra := ColorRect.new()
		sombra.color = F_MIRA_SOMBRA
		sombra.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sombra.position = pos - Vector2.ONE
		sombra.size = tam + Vector2.ONE * 2.0
		_f_mira.add_child(sombra)
		var luz := ColorRect.new()
		luz.color = F_MIRA_COLOR
		luz.mouse_filter = Control.MOUSE_FILTER_IGNORE
		luz.position = pos
		luz.size = tam
		_f_mira.add_child(luz)
	_actualizar_mira_roca(false)

func _actualizar_mira_roca(mostrar: bool) -> void:
	if _f_mira == null:
		return
	_f_mira.visible = mostrar
	if not mostrar:
		return
	var vp := get_viewport().get_visible_rect().size
	_f_mira.position = (vp * 0.5).round()

## Punto del mundo al que apunta el centro de la cámara: raycast sobre el
## escenario y los cuerpos; si no encuentra superficie, un punto lejano en esa
## misma dirección (alcance máximo razonable).
func _punto_objetivo_mira() -> Vector3:
	var origen := pivote.global_position
	var dir := -pivote.global_transform.basis.z
	var mundo := get_world_3d()
	if mundo != null:
		var consulta := PhysicsRayQueryParameters3D.create(
			origen, origen + dir * F_MIRA_ALCANCE, 1, [get_rid()])
		var golpe: Dictionary = mundo.direct_space_state.intersect_ray(consulta)
		if golpe.has("position"):
			return golpe["position"]
	return origen + dir * F_MIRA_ALCANCE

## Dirección inicial para que la piedra (con su velocidad y su gravedad reales)
## caiga en el punto objetivo: solución balística de ángulo bajo. Fuera de
## alcance, tiro directo (la física hará que caiga donde llegue).
func _direccion_lanzamiento_roca(origen: Vector3, objetivo: Vector3,
		velocidad: float, gravedad_tiro: float) -> Vector3:
	var a_objetivo := objetivo - origen
	var horiz := Vector3(a_objetivo.x, 0.0, a_objetivo.z)
	var d := horiz.length()
	if a_objetivo.length_squared() < 0.0001:
		return -pivote.global_transform.basis.z
	if d < 0.25 or gravedad_tiro <= 0.001 or velocidad <= 0.001:
		return a_objetivo.normalized()
	var v2 := velocidad * velocidad
	var raiz := v2 * v2 - gravedad_tiro * (gravedad_tiro * d * d + 2.0 * a_objetivo.y * v2)
	if raiz < 0.0:
		return a_objetivo.normalized()
	var tan_theta := (v2 - sqrt(raiz)) / (gravedad_tiro * d)
	return (horiz / d + Vector3.UP * tan_theta).normalized()

# --- Piedra lanzada: no se puede arrancar otra mientras siga en el mundo ------
## ¿Está el camino libre para arrancar una piedra nueva?
func _puede_levantar_roca() -> bool:
	if _f_roca_lanzada == null:
		return true
	# El objeto puede haberse liberado ya (is_instance_valid) o estar en cola de
	# liberación este mismo fotograma (is_queued_for_deletion): en ambos casos
	# ya no existe para el mundo y la habilidad vuelve a estar disponible.
	if not is_instance_valid(_f_roca_lanzada) or _f_roca_lanzada.is_queued_for_deletion():
		_f_roca_lanzada = null
		return true
	return false

func _on_piedra_lanzada_fuera() -> void:
	# Señal tree_exited: la piedra salió definitivamente del árbol de escena.
	_f_roca_lanzada = null

## Cancela un levantamiento a medias SIN dejar la piedra en mala posición: la
## piedra se retira (no llegó a levantarse) y el IK se apaga, igual que hace
## _detener_fuerza al cambiar de forma.
func _soltar_roca_interrumpida() -> void:
	if f_roca != null and is_instance_valid(f_roca) and not f_roca.volando:
		f_roca.queue_free()
	f_roca = null
	f_cargando_roca = false
	f_roca_lista = false
	_actualizar_mira_roca(false)
	if _f_ik != null:
		_f_ik.peso_objetivo = 0.0
		_f_ik.peso_actual = 0.0
		_f_ik.soltar_roca()

# --- Señal del AnimationPlayer ------------------------------------------------
func _on_animacion_fuerza_terminada(nombre: StringName) -> void:
	# Fin REAL del clip de levantamiento: desde aquí la roca está arriba de
	# verdad (el fin de RockLift es el primer fotograma de RockCarry) y se puede
	# apuntar, andar con ella y lanzarla.
	if nombre == ANIM_F_ROCKLIFT and f_cargando_roca:
		f_roca_lista = true
	# Fin REAL del clip de golpe: el ataque dura lo que dura la animación.
	if f_ataque and not _f_ataque_clip.is_empty() and nombre == _f_ataque_clip:
		_terminar_ataque_fuerza()

# --- Cuerpo a cuerpo (puñetazo / combo / patada) ---
# La duración de cada golpe es la del CLIP REAL: la animación nunca se corta a
# medias y el personaje sólo vuelve a la locomoción cuando el golpe termina.
func _golpe_fuerza(es_patada: bool) -> void:
	if f_ataque:
		# Un puñetazo pedido durante el jab queda ENCOLADO: el cross sale al
		# terminar el golpe en curso, jamás cortándolo a media animación.
		if not es_patada and _f_ataque_clip == ANIM_F_PUNCH_L:
			_f_combo_pedido = true
		return
	if es_patada:
		_f_combo_pedido = false
		_iniciar_ataque_fuerza(ANIM_F_KICK)
		return
	var ahora := Time.get_ticks_msec() / 1000.0
	var combo := _f_clip_terminado == ANIM_F_PUNCH_L and f_ultimo_golpe > 0.0 \
		and (ahora - f_ultimo_golpe < F_COMBO_VENTANA)
	_iniciar_ataque_fuerza(ANIM_F_PUNCH_R if combo else ANIM_F_PUNCH_L)

## Arranca un golpe completo: clip entero desde el principio y daño pendiente
## hasta la extensión real del puño o del pie.
func _iniciar_ataque_fuerza(clip: String) -> void:
	f_ataque = true
	_f_ataque_clip = clip
	_f_ataque_dur = _duracion_fuerza(clip)
	_f_ataque_impacto_u = float(F_IMPACTO_U.get(clip, 0.29))
	_f_ataque_golpeado = false
	_reproducir_fuerza(clip, BLEND_ATAQUE, true)

## Sigue el golpe por la posición REAL del clip: el daño se aplica cuando el
## puño o el pie alcanzan su extensión (u medida sobre los propios clips) y el
## ataque se cierra cuando la animación termina de verdad (posición o señal).
func _procesar_ataque_fuerza() -> void:
	if anim_fuerza == null or _f_ataque_clip.is_empty() \
			or anim_fuerza.current_animation != _f_ataque_clip:
		# Otra cosa tomó el AnimationPlayer (salto, menú, cambio de forma):
		# el golpe ya no está en curso y se suelta sin dejarlo bloqueado.
		_terminar_ataque_fuerza()
		return
	var pos := anim_fuerza.current_animation_position
	if not _f_ataque_golpeado and _f_ataque_dur > 0.0 \
			and pos >= _f_ataque_dur * _f_ataque_impacto_u:
		_f_ataque_golpeado = true
		_aplicar_impacto_golpe_fuerza()
	if pos >= _f_ataque_dur - 0.02 or not anim_fuerza.is_playing():
		_terminar_ataque_fuerza()

func _aplicar_impacto_golpe_fuerza() -> void:
	var es_patada := _f_ataque_clip == ANIM_F_KICK
	var dano := F_PATADA_DANIO if es_patada else F_PUNIO_DANIO
	var altura := F_PATADA_ALTURA if es_patada else F_GOLPE_ALTURA
	var punto := _punto_golpe_fuerza(altura)
	_golpear_esfera_fuerza(punto, F_GOLPE_RADIO, dano, 6.0)
	FuerzaVfx.chispas(get_parent(), punto, 0.7, 16, Color(1.0, 0.85, 0.5), 0.4, 5.0)

func _terminar_ataque_fuerza() -> void:
	if not f_ataque:
		return
	f_ataque = false
	_f_clip_terminado = _f_ataque_clip
	_f_ataque_clip = ""
	_f_ataque_dur = 0.0
	# La ventana de combo se cuenta desde que el golpe TERMINÓ.
	f_ultimo_golpe = Time.get_ticks_msec() / 1000.0
	# Puñetazo encadenado pedido durante el jab: ahora sí, clip nuevo entero.
	if _f_combo_pedido and _f_clip_terminado == ANIM_F_PUNCH_L:
		_f_combo_pedido = false
		_iniciar_ataque_fuerza(ANIM_F_PUNCH_R)

func _punto_golpe_fuerza(altura: float) -> Vector3:
	var adelante := -fuerza.global_transform.basis.z
	adelante.y = 0.0
	adelante = adelante.normalized() if adelante.length_squared() > 0.0001 else Vector3.FORWARD
	return global_position + Vector3.UP * altura + adelante * F_GOLPE_ALCANCE

# --- Daño (reutiliza el contrato del paquete Fuerza: grupo "damageable" + take_damage) ---
func _golpear_esfera_fuerza(centro: Vector3, radio: float, dano: float, empuje: float) -> void:
	var mundo := get_world_3d()
	if mundo == null:
		return
	var excluir: Array = [get_rid()]
	FuerzaCombat.golpear_esfera(mundo.direct_space_state, centro, radio, dano, empuje, excluir, 0.4, 0.3)

func _golpear_objetivo_fuerza(nodo: Node3D, centro: Vector3, dano: float, empuje: float) -> void:
	if not nodo.has_method("take_damage"):
		return
	var dir := nodo.global_position - centro
	dir.y = 0.0
	dir = dir.normalized() if dir.length_squared() > 0.0001 else Vector3.FORWARD
	nodo.call("take_damage", dano, centro, (dir + Vector3.UP * 0.3).normalized() * empuje)

func _objetivos_en_esfera(centro: Vector3, radio: float) -> Array:
	var out: Array = []
	for n in get_tree().get_nodes_in_group("damageable"):
		var t := n as Node3D
		if t == null or t == self or not t.is_inside_tree():
			continue
		if centro.distance_to(t.global_position) <= radio:
			out.append(t)
	return out

# La forma velocista debe verse EXACTAMENTE del mismo tamaño que Leo humano. La causa
# real de la diferencia NO es un nodo padre ni la importación: son escalas base distintas.
# El FBX de Leo viene en unidades diminutas (leo.tscn lo compensa con escala 200 -> ~1.95 m),
# mientras que el FBX del velocista ya viene en metros (~0.98 m). Se normaliza la escala del
# modelo velocista a la altura real de Leo, en lugar de tocar el CharacterBody3D o la colisión.
func _ajustar_escala_velocista() -> void:
	var h_leo := _altura_visual(humano)
	var h_vel := _altura_visual(vel_modelo)
	if h_leo > 0.001 and h_vel > 0.001:
		var s := h_leo / h_vel
		vel_modelo.scale = Vector3(s, s, s)

# La forma acuática (Pes) también debe verse del mismo tamaño que Leo humano. El
# modelo del módulo acuático ya viene en metros (~1.75 m); se normaliza su escala
# a la altura real de Leo en lugar de tocar el CharacterBody3D o la colisión.
func _ajustar_escala_acuatico() -> void:
	var h_leo := _altura_visual(humano)
	var h_ac := _altura_visual(acuatico)
	if h_leo > 0.001 and h_ac > 0.001:
		var s := h_leo / h_ac
		acuatico.scale = Vector3(s, s, s)

# La forma Fuerza también se normaliza a la altura real de Leo (el FBX trae su
# propia escala); no se toca el CharacterBody3D ni la colisión.
func _ajustar_escala_fuerza() -> void:
	var h_leo := _altura_visual(humano)
	var h_f := _altura_visual(fuerza)
	if h_leo > 0.001 and h_f > 0.001:
		var s := h_leo / h_f
		fuerza.scale = Vector3(s, s, s)

# Altura de la caja envolvente de todas las mallas de un subárbol, medida en el espacio
# local del nodo indicado (incluye su propia escala actual).
func _altura_visual(raiz: Node3D) -> float:
	var inv := raiz.global_transform.affine_inverse()
	var caja := AABB()
	var cont := 0
	for nodo in raiz.find_children("*", "MeshInstance3D", true, false):
		var mi := nodo as MeshInstance3D
		if mi.mesh == null:
			continue
		var c: AABB = (inv * mi.global_transform) * mi.mesh.get_aabb()
		caja = c if cont == 0 else caja.merge(c)
		cont += 1
	return caja.size.y

# ============================================================ VELOCISTA (ziba/)
# A partir de aquí el comportamiento es el del prototipo de supervelocidad
# (ziba/scripts/jugador.gd). Los nodos Efectos/Trazador/Combate/CapaVelocidad y
# la cámara CamaraZiba se reutilizan sin cambios.
func _procesar_normal(delta: float) -> void:
	var dir := _direccion_entrada()
	_actualizar_logica_atras(delta, dir)

	var vel_objetivo := velocidad_max
	if _ataque_activo:
		vel_objetivo *= FACTOR_MOVILIDAD_ATAQUE

	var horiz := Vector3(velocity.x, 0.0, velocity.z)
	if dir.length() > 0.05:
		horiz = horiz.move_toward(dir * vel_objetivo, aceleracion * delta)
	else:
		horiz = horiz.move_toward(Vector3.ZERO, desaceleracion * delta)
	velocity.x = horiz.x
	velocity.z = horiz.z

	if not is_on_floor():
		velocity.y -= gravedad * delta
	elif velocity.y < 0.0:
		velocity.y = -0.1

	if is_on_floor() and Input.is_action_just_pressed("saltar"):
		if _ataque_activo:
			_cancelar_ataque_por_salto()
		velocity.y = fuerza_salto

	move_and_slide()

	if _en_ventana_atras:
		_orientar(delta, _dir_orient_ventana)
	else:
		var retrocede := Input.is_action_pressed("mover_atras") and not Input.is_action_pressed("mover_adelante")
		_orientar(delta, -dir if retrocede else dir)

	if is_on_floor() and Input.is_action_just_pressed("atacar"):
		combate.intentar_golpe()
	if Input.is_action_just_pressed("emote"):
		_intentar_emote()
	if Input.is_action_just_pressed("dash"):
		_intentar_dash()
	if Input.is_action_just_pressed("cargar_poder"):
		_iniciar_carga()

func _on_golpe_realizado(indice: int) -> void:
	_en_modo_ataque = true
	_t_modo_ataque = TIEMPO_MODO_ATAQUE
	_emote_activo = false
	_t_emote = 0.0
	_ataque_activo = true
	var clave := _clave_combo(indice)
	_t_ataque = _duracion_anim(clave)
	_reproducir_anim(clave, BLEND_ATAQUE, true)
	efectos.golpe_ataque(indice)
	var adelante := -visual.global_transform.basis.z
	adelante.y = 0.0
	if adelante.length() > 0.001:
		adelante = adelante.normalized()
		var horiz := Vector3(velocity.x, 0.0, velocity.z) + adelante * IMPULSO_AVANCE
		if horiz.length() > velocidad_max:
			horiz = horiz.normalized() * velocidad_max
		velocity.x = horiz.x
		velocity.z = horiz.z

func _cancelar_ataque_por_salto() -> void:
	_ataque_activo = false
	_t_ataque = 0.0
	_salto_forzado = true
	efectos.cancelar_ataque()
	combate.cancelar_combo()
	_reproducir_anim(ANIM_SALTO, BLEND_SALTO, true)

func _intentar_emote() -> void:
	if _ataque_activo:
		return
	_emote_activo = true
	_t_emote = _duracion_anim(ANIM_EMOTE)
	_reproducir_anim(ANIM_EMOTE, BLEND_EMOTE, true)

func _clave_combo(indice: int) -> String:
	match indice:
		1:
			return ANIM_COMBO_1
		2:
			return ANIM_COMBO_2
		3:
			return ANIM_COMBO_3
		4:
			return ANIM_COMBO_4
	return ANIM_COMBO_1

func _duracion_anim(clave: String) -> float:
	var nombre := String(_anim_nombres.get(clave, ""))
	if _anim == null or nombre.is_empty():
		return 0.3
	var anim := _anim.get_animation(nombre)
	return anim.length if anim != null else 0.3

func _actualizar_logica_atras(delta: float, dir: Vector3) -> void:
	var s := Input.is_action_pressed("mover_atras")
	var w := Input.is_action_pressed("mover_adelante")
	var a := Input.is_action_pressed("mover_izquierda")
	var d := Input.is_action_pressed("mover_derecha")

	if not s or w:
		_hubo_combo_atras = false
		_en_ventana_atras = false
		_t_ventana = 0.0
		if dir.length() > 0.05:
			_ultimo_dir_movimiento = dir
		return

	if a or d:
		_hubo_combo_atras = true
		_en_ventana_atras = false
		_t_ventana = 0.0
		_ultimo_dir_movimiento = dir
		return

	if _en_ventana_atras:
		_t_ventana += delta
		if _t_ventana >= VENTANA_CONTINUACION:
			_en_ventana_atras = false
		return

	if _hubo_combo_atras:
		_en_ventana_atras = true
		_t_ventana = 0.0
		_dir_orient_ventana = -_ultimo_dir_movimiento
		_hubo_combo_atras = false

# ---------------- Dash ----------------
func _intentar_dash() -> void:
	var dir := _direccion_entrada()
	if dir.length() < 0.05:
		dir = -pivote.global_transform.basis.z
		dir.y = 0.0
		dir = dir.normalized()
	if is_on_floor():
		_iniciar_dash(dir)
	else:
		estado = Estado.CAIDA_DASH
		_dir_dash = dir
		velocity = Vector3(0.0, -35.0, 0.0)
		efectos.iniciar_caida_dash()

func _iniciar_dash(dir: Vector3) -> void:
	estado = Estado.DASH
	_dir_dash = dir
	_orientar_instant(dir)
	_objetivo_dash = global_position + dir * distancia_objetivo_dash
	_objetivo_dash.y = global_position.y
	_pos_dash_inicio = global_position
	_t_dash = 0.0
	_bloqueo_anim = 0.0
	efectos.iniciar_dash(dir)

func _procesar_dash(delta: float) -> void:
	_t_dash += delta
	var to := _objetivo_dash - global_position
	to.y = 0.0
	if to.length() < 0.4 or _t_dash > 0.5:
		_terminar_dash()
		return
	var dir := to.normalized()
	var col := move_and_collide(dir * (distancia_dash / duracion_dash) * delta)
	if col != null:
		_terminar_dash()
		return
	efectos.actualizar_ejecucion(global_position, dir)

func _terminar_dash() -> void:
	estado = Estado.NORMAL
	velocity = _dir_dash * velocidad_max
	print("[Leo] dash recorrido: ", snappedf((global_position - _pos_dash_inicio).length(), 0.01), " m")
	efectos.terminar_dash()

func _procesar_caida_dash() -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	velocity.y = -35.0
	move_and_slide()
	if is_on_floor():
		_iniciar_dash(_dir_dash)

# ---------------- Carga / trazado ----------------
func _iniciar_carga() -> void:
	estado = Estado.CARGA
	_t_carga = 0.0
	_bloqueo_anim = 0.0
	var cam_fwd := -pivote.global_transform.basis.z
	cam_fwd.y = 0.0
	if cam_fwd.length() > 0.001:
		_orientar_instant(cam_fwd.normalized())
	pivote.permitir_look = false
	pivote.definir_pitch(-0.32)
	pivote.objetivo_largo = pivote.largo_base * 0.6
	pivote.objetivo_fov = pivote.fov_base + 6.0
	var cam := pivote.get_node_or_null("Brazo/Camara") as Camera3D
	trazador.iniciar(global_position, cam, 0.0)
	efectos.iniciar_carga()

func _procesar_carga(delta: float) -> void:
	_t_carga += delta
	velocity = velocity.move_toward(Vector3.ZERO, desaceleracion * delta)
	if not is_on_floor():
		velocity.y -= gravedad * delta
	move_and_slide()

	var t := clampf(_t_carga / 1.8, 0.0, 1.0)
	efectos.actualizar_carga(t)
	pivote.vibracion = lerpf(0.15, 1.0, t)
	pivote.objetivo_largo = pivote.largo_base * lerpf(0.6, 0.42, t)

	if Input.is_action_just_released("cargar_poder"):
		_soltar_carga()

func _soltar_carga() -> void:
	pivote.permitir_look = true
	pivote.vibracion = 0.0
	pivote.objetivo_largo = pivote.largo_base
	pivote.objetivo_fov = pivote.fov_base
	pivote.definir_pitch(-0.25)
	var muestras := trazador.finalizar()
	efectos.terminar_carga()
	if muestras.size() >= 2:
		_puntos = muestras
		_idx = 0
		_vel_trayecto = vel_trayecto_min
		_t_preparado = 0.0
		estado = Estado.PREPARADO
		pivote.objetivo_largo = pivote.largo_base * 0.7
		pivote.objetivo_fov = pivote.fov_base + 12.0
		pivote.vibracion = 0.5
	else:
		trazador.limpiar()
		estado = Estado.NORMAL

func _procesar_preparado(delta: float) -> void:
	_t_preparado += delta
	velocity = velocity.move_toward(Vector3.ZERO, desaceleracion * delta)
	if not is_on_floor():
		velocity.y -= gravedad * delta
	move_and_slide()
	if _t_preparado >= 0.12:
		_iniciar_recorrido()

func _iniciar_recorrido() -> void:
	estado = Estado.EJECUCION
	trazador.set_ejecucion(true)
	efectos.iniciar_ejecucion()
	pivote.objetivo_largo = pivote.largo_base * 0.9
	pivote.objetivo_fov = pivote.fov_base + 20.0
	pivote.vibracion = 0.6

# ---------------- Ejecución de la trayectoria ----------------
# El recorrido se apoya en el terreno REAL de la isla. Antes se hacía con un
# avance horizontal puro (move_and_collide con la Y a cero) y se cancelaba la
# habilidad ante CUALQUIER contacto: en cuanto el suelo subía un centímetro
# dentro del paso del fotograma, la habilidad interpretaba la cuesta como un
# muro y terminaba. Ahora se avanza con move_and_slide (que sube y baja por el
# relieve respetando el límite de inclinación del cuerpo) y sólo se cancela ante
# un obstáculo de verdad sondeado a la altura del pecho; los escalones los sigue
# subiendo _resolver_escalon(), igual que al caminar.
func _procesar_ejecucion(delta: float) -> void:
	if _idx >= _puntos.size():
		_terminar_ejecucion()
		return
	var objetivo := _puntos[_idx]
	var to := objetivo - global_position
	to.y = 0.0
	# A 60 m/s se cruzan varios puntos por fotograma: si sólo se avanzase uno, el
	# personaje acabaría persiguiendo un punto que ya tiene a su espalda (zigzag).
	var guardas := 0
	while _idx < _puntos.size() - 1 and to.length() < TRAYECTO_RADIO_PUNTO and guardas < 64:
		_idx += 1
		guardas += 1
		objetivo = _puntos[_idx]
		to = objetivo - global_position
		to.y = 0.0
	# Se llegó al final de la ruta: la habilidad termina de forma ordenada (antes
	# se exigía una precisión de milímetros sobre el último punto y el personaje
	# se quedaba girando a su alrededor sin acabar nunca).
	if _idx >= _puntos.size() - 1 and to.length() < TRAYECTO_RADIO_PUNTO:
		_terminar_ejecucion()
		return
	if to.length_squared() < 0.0001:
		_idx += 1
		return
	var dir := to.normalized()
	_vel_trayecto = move_toward(_vel_trayecto, vel_trayecto_max, 220.0 * delta)

	velocity.x = dir.x * _vel_trayecto
	velocity.z = dir.z * _vel_trayecto
	if not is_on_floor():
		velocity.y -= gravedad * delta
	elif velocity.y < 0.0:
		velocity.y = -0.1
	var antes := global_position
	move_and_slide()
	_orientar_instant(dir)

	var avance := global_position - antes
	avance.y = 0.0
	var paso := _vel_trayecto * delta
	# Sólo una corrección por fotograma: primero medimos el avance REAL tras
	# move_and_slide. El contacto en sí (incluido un contacto con el suelo) no
	# termina la habilidad; sólo el avance horizontal insuficiente puede hacerlo.
	if paso > 0.001 and avance.length() < paso * 0.35:
		if _muro_al_frente(dir):
			_terminar_ejecucion()
			return
		# Sin pared a la altura del pecho: intentamos resolver únicamente un
		# desnivel bajo. _resolver_escalon() se omite durante EJECUCION para no
		# duplicar esta corrección en el mismo movimiento.
		_salvar_escalon(dir)

	efectos.actualizar_ejecucion(global_position, dir)
	trazador.agregar_estela(global_position)

## ¿Lo que frena el recorrido es un obstáculo real? Se sondea a la altura del
## pecho con el propio cuerpo (misma collision_mask que al caminar): un edificio,
## un muro o un acantilado bloquean ahí; una cuesta, un bordillo o un desnivel
## transitable, no. _terminar_ejecucion() cierra la habilidad de forma ordenada.
func _muro_al_frente(dir: Vector3) -> bool:
	var pecho := global_transform
	pecho.origin.y += TRAYECTO_ALTURA_MURO
	return test_move(pecho, dir * (AVANCE_ESCALON * 2.0))


## Sube a mano un escalón bajo (el bordillo de una acera, ~15 cm) cuando frena el
## recorrido a gran velocidad: eleva el cuerpo ALTURA_ESCALON, avanza un poco y
## vuelve a apoyarse. Sólo lo hace si hay hueco por encima, paso libre a esa altura
## y suelo al otro lado; un muro de verdad ya lo ha descartado _muro_al_frente().
## (Caminando esto lo hace _resolver_escalon(), pero a 34-60 m/s el contacto se
## resuelve dentro del fotograma y move_and_slide no sube el escalón.)
func _salvar_escalon(dir: Vector3) -> void:
	if test_move(global_transform, Vector3.UP * ALTURA_ESCALON):
		return
	var elevado := global_transform
	elevado.origin.y += ALTURA_ESCALON
	var avance := dir * AVANCE_ESCALON
	if test_move(elevado, avance):
		return
	var destino := elevado
	destino.origin += avance
	if not test_move(destino, Vector3.DOWN * (ALTURA_ESCALON + 0.1)):
		return
	global_position.y += ALTURA_ESCALON
	move_and_collide(avance)
	move_and_collide(Vector3.DOWN * (ALTURA_ESCALON + 0.1))

func _terminar_ejecucion() -> void:
	estado = Estado.NORMAL
	velocity = Vector3.ZERO
	pivote.objetivo_largo = pivote.largo_base
	pivote.objetivo_fov = pivote.fov_base
	pivote.vibracion = 0.0
	efectos.terminar_ejecucion()
	trazador.finalizar_ejecucion()
	_bloqueo_anim = BLOQUEO_FIN_VELOCIDAD
	_reproducir_anim(ANIM_INACTIVO, BLEND_FIN_VELOCIDAD)

# ---------------- Animaciones (velocista) ----------------
func _configurar_animaciones() -> void:
	_anim = get_node_or_null("Visual/Pose/Volteo/Modelo/AnimadorVelocista") as AnimationPlayer
	if _anim == null:
		push_warning("[Leo] Sin AnimationPlayer en el modelo velocista: la forma velocista se movera sin animaciones.")
		return
	for lib_nombre in _anim.get_animation_library_list():
		var clave := String(lib_nombre)
		if clave.is_empty():
			continue
		var lib: AnimationLibrary = _anim.get_animation_library(lib_nombre)
		if lib == null or lib.get_animation_list().is_empty():
			continue
		var clip := lib.get_animation_list()[0]
		_anim_nombres[clave] = "%s/%s" % [clave, clip]
		_preparar_bucle(clave, lib.get_animation(clip))

func _preparar_bucle(clave: String, anim: Animation) -> void:
	match clave:
		ANIM_INACTIVO, ANIM_ADELANTE, ANIM_ATRAS, ANIM_SUPERVELOCIDAD, ANIM_MODO_ATAQUE:
			anim.loop_mode = Animation.LOOP_LINEAR
		ANIM_CARGA:
			anim.loop_mode = Animation.LOOP_PINGPONG
		ANIM_COMBO_1, ANIM_COMBO_2, ANIM_COMBO_3, ANIM_COMBO_4, ANIM_EMOTE:
			anim.loop_mode = Animation.LOOP_NONE

func _reproducir_anim(clave: String, blend: float, forzar: bool = false) -> void:
	if _anim == null:
		return
	if clave == _anim_actual and not forzar:
		return
	var nombre := String(_anim_nombres.get(clave, ""))
	if nombre.is_empty():
		return
	_anim_actual = clave
	_anim.play(nombre, blend)

func _blend_para(clave: String) -> float:
	match clave:
		ANIM_SALTO:
			return BLEND_SALTO
		ANIM_DASH:
			return BLEND_DASH
		ANIM_CARGA:
			return BLEND_CARGA
		ANIM_SUPERVELOCIDAD:
			return BLEND_LIBERACION
	match _anim_actual:
		ANIM_DASH:
			return BLEND_POST_DASH
		ANIM_SALTO:
			return BLEND_POST_SALTO
		ANIM_SUPERVELOCIDAD:
			return BLEND_FIN_VELOCIDAD
		ANIM_ADELANTE, ANIM_ATRAS:
			return BLEND_MARCHA_FIN if clave == ANIM_INACTIVO else BLEND_CAMBIO_MARCHA
	return BLEND_MARCHA

func _actualizar_animaciones(delta: float) -> void:
	if _anim == null:
		return
	_bloqueo_anim = maxf(0.0, _bloqueo_anim - delta)
	if _ataque_activo:
		_t_ataque -= delta
		if _t_ataque <= 0.0:
			_ataque_activo = false
	if _emote_activo:
		_t_emote -= delta
		if _t_emote <= 0.0:
			_emote_activo = false
	if _en_modo_ataque:
		_t_modo_ataque -= delta
		if _t_modo_ataque <= 0.0:
			_en_modo_ataque = false
	match estado:
		Estado.NORMAL:
			if _ataque_activo:
				pass
			elif _emote_activo:
				pass
			elif not is_on_floor():
				_reproducir_anim(ANIM_SALTO, _blend_para(ANIM_SALTO))
			elif _salto_forzado:
				_salto_forzado = false
				_reproducir_anim(ANIM_SALTO, BLEND_SALTO)
			elif _bloqueo_anim > 0.0:
				_reproducir_anim(ANIM_INACTIVO, _blend_para(ANIM_INACTIVO))
			elif _en_ventana_atras:
				_reproducir_anim(ANIM_ADELANTE, _blend_para(ANIM_ADELANTE))
			elif Input.is_action_pressed("mover_atras") and not Input.is_action_pressed("mover_adelante"):
				_reproducir_anim(ANIM_ATRAS, _blend_para(ANIM_ATRAS))
			elif _direccion_entrada().length() > 0.05:
				_reproducir_anim(ANIM_ADELANTE, _blend_para(ANIM_ADELANTE))
			elif _en_modo_ataque:
				_reproducir_anim(ANIM_MODO_ATAQUE, BLEND_POST_ATAQUE)
			else:
				_reproducir_anim(ANIM_INACTIVO, _blend_para(ANIM_INACTIVO))
		Estado.DASH, Estado.CAIDA_DASH:
			_reproducir_anim(ANIM_DASH, _blend_para(ANIM_DASH))
		Estado.CARGA:
			_reproducir_anim(ANIM_CARGA, _blend_para(ANIM_CARGA))
		Estado.PREPARADO, Estado.EJECUCION:
			_reproducir_anim(ANIM_SUPERVELOCIDAD, _blend_para(ANIM_SUPERVELOCIDAD))

# ---------------- Pose procedural (velocista) ----------------
func _actualizar_pose(delta: float) -> void:
	var vel_h := Vector3(velocity.x, 0.0, velocity.z).length()
	var inclinacion := 0.0
	var altura := 0.0
	match estado:
		Estado.CARGA:
			inclinacion = -0.55
			altura = 0.0
		Estado.DASH, Estado.EJECUCION:
			inclinacion = -0.6
			altura = -0.05
		_:
			inclinacion = -clampf(vel_h / velocidad_max, 0.0, 1.0) * 0.18
	pose.rotation.x = lerp_angle(pose.rotation.x, inclinacion, 10.0 * delta)
	pose.position.y = lerpf(pose.position.y, altura, 10.0 * delta)

# ---------------- Orientación del modelo (velocista) ----------------
func _orientar(delta: float, dir: Vector3) -> void:
	if dir.length() < 0.05:
		return
	var objetivo := atan2(-dir.x, -dir.z)
	visual.rotation.y = lerp_angle(visual.rotation.y, objetivo, 12.0 * delta)

func _orientar_instant(dir: Vector3) -> void:
	if dir.length() < 0.05:
		return
	visual.rotation.y = atan2(-dir.x, -dir.z)
