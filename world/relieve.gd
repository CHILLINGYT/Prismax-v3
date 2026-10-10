class_name Relieve
extends RefCounted
## =============================================================================
##  RELIEVE DE LA ISLA (matemática compartida)
## =============================================================================
##  Funciones PURAS que describen la forma del mundo. Las usan la malla del
##  terreno, la colisión y el generador del bosque, así que todos coinciden
##  exactamente: los árboles nunca quedan flotando ni enterrados.
##
##  Distribución del mundo (según la imagen de referencia):
##    * la CIUDAD (252x252 m, centrada en el origen de la escena) queda en la
##      zona central, sobre una meseta PLANA para que ninguna calle ni edificio
##      quede tapado por el relieve,
##    * el BOSQUE con MONTAÑAS ocupa el norte, noroeste y oeste: macizos de
##      hasta ~110 m con crestas, laderas y valles, no meras ondulaciones,
##    * el OCÉANO rodea toda la isla; el terreno baja por debajo del nivel del
##      mar en la periferia.
##
##  Ejes: en Godot el "norte" del mapa es -Z y el "oeste" es -X, así que el
##  centro de la isla se desplaza hacia el noroeste respecto de la ciudad.
## =============================================================================

# --- Medidas del mundo (metros) ---
## Centro de la isla (x, z). Al noroeste de la ciudad: deja el bosque al
## norte/noroeste/oeste y una franja de costa al sureste. Desplazado 127 m del
## centro de la ciudad: cuanto menor sea el desplazamiento, más cerca queda la
## costa en todos los sectores.
const CENTRO := Vector2(-80.0, -80.0)
## Radio medio de la costa (el borde real ondula alrededor de este valor).
const RADIO_COSTA := 410.0
## Cuánto se aparta la costa de ese radio medio según el sector: +12 % hacia el
## noroeste (para que quepan las montañas) y -12 % hacia el sureste (para que el
## mar quede cerca de la ciudad). La isla deja de ser un círculo.
const ASIMETRIA := 0.12
## Dirección (grados) hacia la que la costa se aleja: el noroeste.
const DIR_NO := -135.0
## Cota del mar. El agua (Agua/Scenes/Ocean.tscn) se coloca 5 cm por debajo para
## que la línea de costa no quede coplanaria con la malla del terreno.
const NIVEL_MAR := -2.0
## Fondo del mar lejos de la isla (el terreno nunca baja más que esto).
const FONDO_MAR := -70.0
## Cota de la meseta plana de la ciudad: 30 cm por debajo del suelo urbano
## (el generador de la ciudad usa -0.155..0), así que la ciudad nunca es tapada.
const COTA_CIUDAD := -0.30
## Media extensión de la meseta plana (la ciudad ocupa 126 m de semi-extensión).
## Se deja un margen pequeño sobre el borde urbano: así el terreno natural empieza
## en cuanto se sale de las calles y no queda un anillo plano alrededor.
const SEMI_MESETA := 132.0
## Ancho de la transición entre la meseta y el relieve natural. Corta a propósito:
## la ciudad pasa a paisaje natural en pocos metros.
const TRANSICION_CIUDAD := 40.0
## Distancia (m) sobre la que la tierra sube desde la orilla hasta la cota base.
const ANCHO_COSTA := 38.0
## Distancia (m) sobre la que las colinas del bosque se desvanecen al acercarse a
## la costa. Es mucho mayor que el ancho de playa a propósito: si las colinas se
## apagasen en la misma franja de 40 m, la orilla quedaría con una pendiente de
## 40° (difícil de subir, incluso para el velocista).
const ANCHO_COLINA_COSTA := 180.0
## Distancia (m) sobre la que el mar baja desde la orilla hasta el fondo.
const ANCHO_FONDO := 520.0
## Altura máxima de las colinas suaves (m sobre la cota base). Rellenan el
## paisaje entre los macizos para que no queden llanuras vacías.
const ALTURA_COLINA := 34.0
## Altura del VOLUMEN del macizo (m sobre la cota base): la escala grande.
const ALTURA_SIERRA := 92.0
## Altura de los PICOS y collados (m): la escala media que da perfiles variados.
const ALTURA_PICOS := 30.0
## Relieve suave (m) de la llanura: evita que el terreno fuera de la ciudad y del
## bosque sea un plano perfecto.
const AMPLITUD_SUAVE := 3.0
## Semillas y frecuencias del relieve.
const SEMILLA := 20240
const FRECUENCIA_COLINA := 0.0036
const SEMILLA_SUAVE := 7717
const FRECUENCIA_SUAVE := 0.009
## Macizos: ruido de baja frecuencia que decide DÓNDE hay montaña (y dónde hay
## valles entre macizos). Con ~0.0016 aparecen rasgos de ~600 m.
const SEMILLA_MASA := 8823
const FRECUENCIA_MASA := 0.0016
## Crestas: ruido de cresta (ridged) que da las siluetas de las lomas. La
## frecuencia es baja A PROPÓSITO: el VOLUMEN del macizo son rasgos de ~450 m, es
## decir laderas amplias en lugar de acantilados.
const SEMILLA_CRESTA := 5150
const FRECUENCIA_CRESTA := 0.0013
## Picos y collados: segunda escala de cresta, de ~200 m. Es la que rompe la
## cúpula lisa en VARIOS perfiles dentro del mismo macizo, que es lo que hace que
## una montaña se reconozca como montaña y no como un montículo redondeado.
const SEMILLA_MEDIA := 6104
const FRECUENCIA_MEDIA := 0.0048
## Detalle de ladera: rugosidad suave para que las faldas no sean superficies
## lisas. Su amplitud es FIJA (no crece con la sierra) para que ninguna cumbre
## tenga una pared al lado.
const SEMILLA_FLANCO := 3390
const FRECUENCIA_FLANCO := 0.011
const AMPLITUD_FLANCO := 8.0
## Sector del bosque, en grados de brújula (0 = norte, +90 = este, -90 = oeste):
## peso completo hasta BOSQUE_PLENO del centro y nulo a partir de BOSQUE_FIN.
## Cubre norte, noroeste, oeste y los extremos próximos, y deja libre el sureste
## (el lado de la costa cercana) para que la ciudad conserve su acceso al mar.
const BOSQUE_CENTRO := -35.0
const BOSQUE_PLENO := 70.0
const BOSQUE_FIN := 120.0
## Sector de las montañas: algo más ancho que el bosque para que los macizos
## envuelvan la ciudad sin encerrarla ni bloquear el paso hacia la costa.
const MONTE_CENTRO := -45.0
const MONTE_PLENO := 105.0
const MONTE_FIN := 150.0

var _ruido := FastNoiseLite.new()
var _ruido_suave := FastNoiseLite.new()
var _ruido_masa := FastNoiseLite.new()
var _ruido_cresta := FastNoiseLite.new()
var _ruido_media := FastNoiseLite.new()
var _ruido_flanco := FastNoiseLite.new()


func _init() -> void:
	_ruido.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_ruido.seed = SEMILLA
	_ruido.frequency = FRECUENCIA_COLINA
	_ruido.fractal_octaves = 3
	_ruido.fractal_gain = 0.5
	_ruido.fractal_lacunarity = 2.0
	_ruido_suave.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_ruido_suave.seed = SEMILLA_SUAVE
	_ruido_suave.frequency = FRECUENCIA_SUAVE
	_ruido_suave.fractal_octaves = 2
	_ruido_masa.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_ruido_masa.seed = SEMILLA_MASA
	_ruido_masa.frequency = FRECUENCIA_MASA
	_ruido_masa.fractal_octaves = 1
	_ruido_cresta.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_ruido_cresta.seed = SEMILLA_CRESTA
	_ruido_cresta.frequency = FRECUENCIA_CRESTA
	_ruido_cresta.fractal_octaves = 1
	_ruido_media.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_ruido_media.seed = SEMILLA_MEDIA
	_ruido_media.frequency = FRECUENCIA_MEDIA
	_ruido_media.fractal_octaves = 2
	_ruido_media.fractal_gain = 0.45
	_ruido_flanco.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_ruido_flanco.seed = SEMILLA_FLANCO
	_ruido_flanco.frequency = FRECUENCIA_FLANCO
	_ruido_flanco.fractal_octaves = 2


## Altura del terreno (m) en el punto de mundo ([param x], [param z]).
func altura(x: float, z: float) -> float:
	var dx := x - CENTRO.x
	var dz := z - CENTRO.y
	var r := sqrt(dx * dx + dz * dz)
	var rc := radio_costa(atan2(dz, dx))
	var h := 0.0
	if r <= rc:
		# Tierra: sube de la orilla hacia el interior y suma los relieves.
		# La curva de la costa es suave (derivada nula en la orilla) para que
		# la playa sea transitable y no un acantilado.
		var u := clampf((rc - r) / ANCHO_COSTA, 0.0, 1.0)
		h = lerpf(NIVEL_MAR, COTA_CIUDAD, smoothstep(0.0, 1.0, u))
		var uc := smoothstep(0.0, 1.0, clampf((rc - r) / ANCHO_COLINA_COSTA, 0.0, 1.0))
		h += (_colinas(x, z) + _montanas(x, z)) * uc
		h += maxf(_ruido_suave.get_noise_2d(x, z) * AMPLITUD_SUAVE, -0.4) * uc * peso_interior(x, z, 130.0, 190.0)
	else:
		# Mar: baja de la orilla al fondo, también con perfil suave.
		var m := clampf((r - rc) / ANCHO_FONDO, 0.0, 1.0)
		h = lerpf(NIVEL_MAR, FONDO_MAR, smoothstep(0.0, 1.0, m))
	# Meseta plana de la ciudad. El peso se apaga en la propia franja de playa
	# (smoothstep sobre la altura) para que la meseta no empuje la costa hacia el
	# mar ni aplaste la arena del lado sureste, que es el más cercano a la ciudad.
	var pc := peso_ciudad(x, z) * smoothstep(NIVEL_MAR, COTA_CIUDAD, h)
	return lerpf(h, COTA_CIUDAD, pc)


## Radio de la costa en la dirección [param theta] (radianes). Suma un término
## direccional (la isla se estira hacia el noroeste, donde están las montañas, y
## se acerca al sureste, hacia la ciudad) y armónicos para que la costa no sea un
## círculo ni un cuadrado. La amplitud total (±18 %) se mantiene contenida para
## que el agua no llegue nunca a la ciudad.
func radio_costa(theta: float) -> float:
	return RADIO_COSTA * (1.0
			+ ASIMETRIA * cos(theta - deg_to_rad(DIR_NO))
			+ 0.045 * sin(3.0 * theta + 1.15)
			+ 0.025 * sin(5.0 * theta + 2.60)
			+ 0.012 * sin(8.0 * theta + 0.40))


## Peso de la meseta de la ciudad: 1 dentro (relieve plano) y 0 fuera de su
## transición. Se mide con distancia de Chebyshev porque la ciudad es cuadrada.
func peso_ciudad(x: float, z: float) -> float:
	var d := maxf(absf(x) - SEMI_MESETA, absf(z) - SEMI_MESETA)
	return 1.0 - smoothstep(0.0, TRANSICION_CIUDAD, d)


## Peso del sector del bosque: 1 en el centro del sector y 0 fuera de él.
func peso_bosque(x: float, z: float) -> float:
	return _peso_sector(x, z, BOSQUE_CENTRO, BOSQUE_PLENO, BOSQUE_FIN)


## Peso del sector de las montañas: 1 en el centro del sector y 0 fuera de él.
func peso_montana(x: float, z: float) -> float:
	return _peso_sector(x, z, MONTE_CENTRO, MONTE_PLENO, MONTE_FIN)


## Peso angular genérico alrededor del centro de la isla.
func _peso_sector(x: float, z: float, centro: float, pleno: float, fin: float) -> float:
	var ang := rad_to_deg(atan2(x - CENTRO.x, -(z - CENTRO.y)))
	var dd := absf(fposmod(ang - centro + 180.0, 360.0) - 180.0)
	return 1.0 - smoothstep(pleno, fin, dd)


## 0 pegado a la ciudad, 1 a partir de [param lejos] metros del origen. Evita que
## las colinas levanten un muro alrededor de las calles.
##
## Se mide con distancia de CHEBYSHEV (max de |x|,|z|) porque la ciudad es
## cuadrada: con distancia euclídea el relieve empezaba a entrar por las esquinas
## del recinto urbano y, a la vez, tardaba de más por los lados. Con Chebyshev el
## relieve natural arranca justo pasado el borde de las calles por los cuatro
## lados, sin invadir ninguna manzana.
func peso_interior(x: float, z: float, cerca: float = 136.0, lejos: float = 220.0) -> float:
	var d := maxf(absf(x), absf(z))
	return smoothstep(cerca, lejos, d)


## Relieve de colinas (m). Existe en TODOS los sectores: así no queda ninguna
## franja plana alrededor de la ciudad, que era justo el problema del lado
## sureste. En el sector del bosque las colinas son las que dan el paisaje pleno;
## fuera de él (el lado de la costa cercana) son más bajas, para que el terreno
## ondulado ceda a la playa sin levantar un muro. Se desvanece en la costa porque
## el llamador lo multiplica por u.
func _colinas(x: float, z: float) -> float:
	var w := peso_interior(x, z, 134.0, 230.0)
	if w <= 0.001:
		return 0.0
	var n := _ruido.get_noise_2d(x, z)
	var amplitud := lerpf(ALTURA_COLINA * 0.5, ALTURA_COLINA, peso_bosque(x, z))
	return (n * 0.5 + 0.5) * amplitud * w


## Montañas (m): sierras de tres escalas. La GRANDE (ridged, ~450 m) da el
## volumen del macizo con laderas amplias; la MEDIA (~200 m) rompe ese volumen en
## picos y collados, que es lo que hace reconocible una montaña; y la rugosidad de
## amplitud fija evita que las faldas sean superficies lisas.
## El resultado se recorta con el sector (MONTE_*) y con la distancia a la ciudad,
## así que nunca crece sobre la meseta ni sobre las calles.
func _montanas(x: float, z: float) -> float:
	# Arranca nada más salir de la ciudad (134 m de distancia de Chebyshev, con la
	# ciudad acabando en 126) y llega a su peso pleno en 275 m: el jugador ve el
	# terreno ganar altura enseguida, sin franja plana de por medio, pero la
	# subida sigue repartida para que las laderas no sean paredes.
	var w := peso_montana(x, z) * peso_interior(x, z, 134.0, 275.0)
	if w <= 0.001:
		return 0.0
	var masa := smoothstep(-0.08, 0.62, _ruido_masa.get_noise_2d(x, z) * 0.5 + 0.5)
	if masa <= 0.001:
		return 0.0
	# Exponente > 1: la cumbre queda redondeada (pendiente nula en la cima) en
	# lugar de formar una arista viva con paredes a los lados.
	var grande := pow(1.0 - absf(_ruido_cresta.get_noise_2d(x, z)), 1.6)
	var media := pow(1.0 - absf(_ruido_media.get_noise_2d(x, z)), 1.3)
	var rugosidad := (_ruido_flanco.get_noise_2d(x, z) * 0.5 + 0.5) * AMPLITUD_FLANCO
	return w * masa * (grande * ALTURA_SIERRA + media * ALTURA_PICOS + rugosidad)


## Distancia horizontal al centro de la isla (m).
func distancia_isla(x: float, z: float) -> float:
	var dx := x - CENTRO.x
	var dz := z - CENTRO.y
	return sqrt(dx * dx + dz * dz)


## Distancia al centro de la ciudad (m). La ciudad está centrada en el origen.
func distancia_ciudad(x: float, z: float) -> float:
	return sqrt(x * x + z * z)


## Pendiente del terreno en grados, medida con diferencias finitas. La usan el
## bosque (para no plantar árboles en paredes de roca) y las comprobaciones.
func pendiente(x: float, z: float, paso: float = 4.0) -> float:
	var hx := altura(x + paso, z) - altura(x - paso, z)
	var hz := altura(x, z + paso) - altura(x, z - paso)
	var g := sqrt(hx * hx + hz * hz) / (2.0 * paso)
	return rad_to_deg(atan(g))