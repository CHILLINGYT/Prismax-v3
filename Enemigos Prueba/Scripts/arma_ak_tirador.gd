class_name ArmaAKTirador
extends Node3D

## ARMA REAL DEL ENEMIGO TIRADOR: el modelo AKM importado (`akmn.glb`) anclado a la
## mano derecha. Sustituye al arma provisional hecha con cajas y cilindros, que se
## conserva en `arma_tirador.tscn` sin usar.
##
## MEDIDAS REALES del modelo (comprobadas con `pruebas/probe_armas.gd` sobre la escena
## importada, componiendo TODA la cadena de padres):
##   · largo total 0.8893 m, eje largo = Z; la BOCA (freno de boca `comp_low`) está en
##     el extremo +Z (z 0.320..0.351) y la culata en -Z (z -0.538);
##   · la EMPUÑADURA (`bGrip_low`) cuelga bajo el receptor, con centro en
##     (0, -0.003, -0.268) y el eje del cañón va a y = 0.085;
##   · 64 mallas, 64 superficies con material, 0 animaciones y 0 skins: es sólo malla
##     rígida, así que no puede pelear con los clips del esqueleto.
##
## CONVENCIÓN DE ESTA ESCENA (la MISMA que el arma provisional, para que el anclaje a
## la mano que ya estaba ajustado siga valiendo y no haya que tocar ninguna animación):
##   · el origen (0,0,0) está en el PUNTO DE AGARRE de la empuñadura;
##   · el cañón apunta hacia -Z y +Y es la vertical del arma.
## Por eso el modelo va girado 180° sobre Y (su boca +Z pasa a -Z) y desplazado para
## que su empuñadura caiga en el origen: RotY(PI) + (0, 0.0034, -0.2685). Con eso la
## boca queda en (0, 0.089, -0.620), prácticamente donde la tenía el arma provisional
## (0, 0.015, -0.600): el marcador `BocaArma` que busca `enemigo_tirador.gd` sigue
## existiendo, en el mismo sitio relativo y con el mismo nombre.
##
## El arma NO trae lógica de IA ni de daño: sólo cuelga del hueso
## `mixamorig_RightHand` (BoneAttachment3D) y acompaña lo que la animación haga con la
## mano. Lo único que hace por sí misma es el DISPARO (Tarea 3): el sonido real del
## proyecto y un fogonazo pequeño, y siempre por petición del tirador.

## Sonido REAL de disparo (el único archivo de `Audio/disparo/`, usado tal cual:
## dura 2,216 s e incluye la cola del disparo; es UN disparo, no una ráfaga).
const AUD_DISPARO := "res://Audio/disparo/freesound_community-ak47-sfx-102801 (mp3cut.net).wav"
## Volumen (dB) del disparo de los enemigos a distancia. Afecta SÓLO a este
## AudioStreamPlayer3D (el bus "Efectos" lo comparten otros sonidos y no se toca).
## Antes -4 dB; bajado 8 dB a -12 dB porque tapaba al resto de la escena.
## Ajustable desde el Inspector de la escena del arma.
@export var volumen_db: float = -12.0
## Alcance del disparo: a qué distancia se oye a plena potencia y hasta dónde llega.
const TAMANO_UNIDAD := 9.0
const DISTANCIA_MAX := 60.0
## Variación leve de tono entre disparos (evita la repetición idéntica sin cambiar el
## sonido: el archivo original no se toca).
const PITCH_MIN := 0.96
const PITCH_MAX := 1.05
## Guarda anti-duplicado (s): dos peticiones dentro de este margen son EL MISMO disparo.
## Con esto, una sola reproducción por disparo queda garantizada aunque alguien llame
## dos veces en el mismo fotograma.
const GUARDA := 0.05

## Fogonazo: NO existía ningún efecto de fogonazo en el proyecto, así que se reutiliza
## el módulo de efectos que sí existe (`FuerzaVfx`, chispas hechas por código).
const COLOR_FOGONAZO := Color(1.0, 0.9, 0.55)
const FOGONAZO_RADIO := 0.07
const FOGONAZO_CHISPAS := 6
const FOGONAZO_DURACION := 0.07
const FOGONAZO_VELOCIDAD := 4.5

## Momento (s de reloj) del último disparo sonado: aplica la guarda.
var _t_ultimo: float = -99.0
## Veces que ha sonado (lo usan las pruebas para contar disparos reales).
var _veces: int = 0

@onready var boca: Marker3D = get_node_or_null("BocaArma") as Marker3D
@onready var sonido: AudioStreamPlayer3D = get_node_or_null("SonidoDisparo") as AudioStreamPlayer3D


func _ready() -> void:
	# Los parámetros del reproductor se fijan también por código: si alguien reusa la
	# escena sin el `.tscn` completo, el disparo sigue saliendo igual.
	if sonido != null:
		sonido.bus = &"Efectos"
		sonido.volume_db = volumen_db
		sonido.unit_size = TAMANO_UNIDAD
		sonido.max_distance = DISTANCIA_MAX
		if sonido.stream == null:
			sonido.stream = load(AUD_DISPARO) as AudioStream


# =============================================================== API del tirador
## Punto REAL de la boca del cañón en coordenadas globales (el mismo marcador que ya
## usaba el tirador para lanzar el proyectil). Si falta el marcador, devuelve el
## origen del arma para no dejar al enemigo sin origen de disparo.
func punto_de_boca() -> Vector3:
	if boca != null:
		return boca.global_position
	return global_position


## EFECTOS DE UN DISPARO: sonido + fogonazo. Se llama UNA vez por disparo (desde
## `_disparar()` del tirador, justo en el fotograma en que suelta el proyectil).
func disparar_efectos() -> void:
	sonar()
	fogonazo()


## Reproduce el sonido del disparo UNA sola vez por evento (guarda anti-duplicado).
func sonar() -> void:
	if sonido == null or sonido.stream == null:
		return
	var ahora := Time.get_ticks_msec() / 1000.0
	if ahora - _t_ultimo < GUARDA:
		return
	_t_ultimo = ahora
	_veces += 1
	sonido.pitch_scale = randf_range(PITCH_MIN, PITCH_MAX)
	sonido.play()


## Fogonazo breve en la boca del cañón, con las chispas que ya genera el proyecto.
## Las partículas cuelgan del MUNDO (no del arma ni del hueso) para que no se queden
## pegadas a la mano mientras dura el efecto.
func fogonazo() -> void:
	var punto := punto_de_boca()
	var padre := _padre_para_efectos()
	if padre == null:
		return
	FuerzaVfx.chispas(padre, punto, FOGONAZO_RADIO, FOGONAZO_CHISPAS,
			COLOR_FOGONAZO, FOGONAZO_DURACION, FOGONAZO_VELOCIDAD)


## Veces que el arma ha disparado (sonido real reproducido). Para las pruebas.
func veces_disparado() -> int:
	return _veces


# =============================================================== interno
## Sube por los ancestros hasta el CUERPO del enemigo (el CharacterBody3D) y devuelve
## su padre: ahí (el mundo/gerente) viven las partículas, así no siguen al hueso.
func _padre_para_efectos() -> Node3D:
	var n: Node = self
	while n != null and not (n is CharacterBody3D):
		n = n.get_parent()
	if n != null and n.get_parent() is Node3D:
		return n.get_parent() as Node3D
	var p := get_parent() as Node3D
	return p