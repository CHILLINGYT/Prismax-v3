class_name VocesAparicion
extends AudioStreamPlayer3D

## VOZ DE APARICIÓN de los enemigos.
##
## La carpeta `res://Audio/enemigos/` trae varias grabaciones cortas de alerta
## (frases de aviso). Este nodo se instala UNA vez en cada enemigo REALMENTE
## creado — desde el único embudo de aparición del gerente (teclas G/H/J y la API
## de eventos) — y reproduce UNA voz aleatoria:
##
##  · AUDIO 3D pegado al enemigo: la voz se oye venir de donde está él;
##  · RUEDA MEZCLADA (bolsa barajada): no se repite siempre la misma grabación y
##    nunca sale dos veces seguidas la misma (si hay más de una);
##  · UNA sola vez por aparición: lo dispara la creación, no hay ningún
##    `_process`/`_physics_process` que pueda repetirlo;
##  · con un RETARDO REPARTIDO entre apariciones casi simultáneas, para que cinco
##    enemigos de un grupo no suelten las voces todas de golpe;
##  · con volumen moderado (−6 dB) y caída por distancia: se entiende sin tapar
##    el resto de efectos.
##
## No inventa audio: sólo usa los archivos que existen en la carpeta. Si la
## carpeta se queda sin grabaciones importables, lo dice por consola (con el
## nombre del archivo y el formato que Godot puede importar) y no reproduce nada.

## Carpeta REAL de las grabaciones (se mueve con Tarea 12 a la estructura Audio/).
const CARPETA := "res://Audio/enemigos"
## Volumen propio de la voz (el bus "Efectos" sigue mandando por encima).
const VOLUMEN_DB := -6.0
## Alcance (m) al que la voz deja de oírse.
const DISTANCIA_MAX := 38.0
## Tamaño de unidad (m): a qué distancia se oye a volumen pleno.
const TAMANO_UNIDAD := 7.0
## Separación (s) entre las voces de apariciones casi simultáneas.
const RETARDO_PASO := 0.16
## Tope del retardo repartido (s): un grupo de cinco (la tecla G) se reparte
## entero (0 · 0,16 · 0,32 · 0,48 · 0,64) y a partir de ahí las voces extra ya no
## empujan más la cola, para no retrasar una aparición real.
const RETARDO_MAX := 0.80
## Extensiones que Godot importa como audio y que este sistema acepta.
const EXTENSIONES := ["wav", "ogg", "mp3"]
## Ventana de GRUPO (s): las apariciones que caen dentro de este margen desde la
## anterior son el MISMO grupo (la tecla G crea sus cinco enemigos en el mismo
## fotograma; el director de eventos crea los suyos también de golpe). Pasada la
## ventana, la siguiente aparición abre un grupo NUEVO y sí suelta voz.
const VENTANA_GRUPO := 0.35

## Altura (m) de la voz sobre el origen del enemigo (el torso).
const ALTURA_VOZ := 1.0

# ---------------------------------------------------------------- estado global
## Streams cargados una sola vez para todo el proyecto.
static var _streams: Array[AudioStream] = []
## Rutas reales cargadas (paralelo a `_streams`, para informar y para las pruebas).
static var _rutas: PackedStringArray = PackedStringArray()
## Bolsa barajada de índices (se rellena cuando se vacía).
static var _bolsa: Array[int] = []
## Último índice servido (para no repetir al cambiar de ronda).
static var _ultimo: int = -1
## Momento (s de reloj) en que se programó el último disparo: reparte las voces.
static var _t_ultimo: float = -99.0
## ¿Ya se informó de un problema con la carpeta? (para no repetir el aviso).
static var _avisado: bool = false
## Grupos de aparición anunciados (uno por grupo, no por enemigo) y sello de tiempo
## del último enemigo que se dio de alta: con eso se decide si una aparición abre
## grupo nuevo o pertenece al que ya está en curso.
static var _grupos_anunciados: int = 0
static var _t_grupo: float = -99.0

# ------------------------------------------------------------------- estado nodo
## Se puso en marcha (una vez por aparición).
var _sono: bool = false
## Veces que ha reproducido en ESTA instancia (para las pruebas).
var _veces: int = 0
## Ruta del archivo que le tocó ("" si no sonó).
var _archivo: String = ""


# =============================================================== API de clase
## Carga (una sola vez) los archivos REALES de la carpeta. Devuelve los streams
## importables; si alguno no se puede cargar, lo informa con su formato.
static func streams_disponibles() -> Array[AudioStream]:
	if not _streams.is_empty():
		return _streams
	var dir := DirAccess.open(CARPETA)
	if dir == null:
		_informar_una_vez("[VocesAparicion] No existe la carpeta %s: los enemigos aparecerán sin voz." % CARPETA)
		return _streams
	var nombres := dir.get_files()
	nombres.sort()
	for n in nombres:
		var archivo := String(n)
		if archivo.ends_with(".import"):
			continue
		var ext := archivo.get_extension().to_lower()
		if not EXTENSIONES.has(ext):
			continue
		var ruta := "%s/%s" % [CARPETA, archivo]
		var st := load(ruta) as AudioStream
		if st == null:
			_informar_una_vez("[VocesAparicion] No se pudo importar '%s' (formato .%s): Godot necesita WAV/OGG/MP3 importados." % [ruta, ext])
			continue
		_streams.append(st)
		_rutas.append(ruta)
	if _streams.is_empty():
		_informar_una_vez("[VocesAparicion] La carpeta %s no tiene grabaciones importables (WAV/OGG/MP3): sin voces de aparición." % CARPETA)
	return _streams

## Rutas reales cargadas (paralelo a streams_disponibles()).
static func rutas_disponibles() -> PackedStringArray:
	streams_disponibles()
	return _rutas

## Coloca la voz en un enemigo recién creado. Devuelve el nodo (o null si el
## enemigo no es válido). Sólo lo llama el embudo de aparición: si el enemigo no
## llegó a crearse, esto NO se ejecuta (no hay voz sin aparición).
static func instalar(enemigo: Node3D) -> VocesAparicion:
	if enemigo == null or not enemigo.is_inside_tree():
		return null
	var voces := VocesAparicion.new()
	voces.name = "VozAparicion"
	voces.bus = &"Efectos"
	voces.volume_db = VOLUMEN_DB
	voces.unit_size = TAMANO_UNIDAD
	voces.max_distance = DISTANCIA_MAX
	voces.position = Vector3(0.0, ALTURA_VOZ, 0.0)
	# La voz no necesita procesar nada: es un disparo puntual.
	voces.set_process(false)
	voces.set_physics_process(false)
	enemigo.add_child(voces)
	return voces

## Retardo repartido: si varias apariciones caen en el mismo instante, sus voces
## se espacian RETARDO_PASO segundos, SIN azar (la serie es monótona: nunca una
## voz nueva adelanta a una ya programada) y con tope RETARDO_MAX. Vale igual
## para el grupo de G y para los enemigos que crea un evento.
static func retardo_repartido() -> float:
	var ahora := Time.get_ticks_msec() / 1000.0
	var hueco := clampf(_t_ultimo + RETARDO_PASO - ahora, 0.0, RETARDO_MAX)
	# El sello queda en el instante programado: la próxima voz sale RETARDO_PASO
	# después de ÉSTA, y así el reparto no se desordena.
	_t_ultimo = maxf(ahora + hueco, _t_ultimo + RETARDO_PASO)
	return hueco

## APARICIÓN GRUPAL: el ÚNICO sitio desde el que se decide si suena una voz, y al
## que llama el embudo de aparición del gerente UNA vez por enemigo creado.
##
##   · el PRIMER enemigo de un grupo recibe el nodo de voz y suelta UNA grabación;
##   · los demás enemigos del MISMO grupo (misma ventana `VENTANA_GRUPO`) no reciben
##     nada: ni nodo ni sonido. Así una aparición de cinco enemigos suena UNA vez, no
##     cinco, sin importar si llegaron por la tecla G, por H/J o por el panel/evento;
##   · pasada la ventana, la siguiente aparición abre un grupo nuevo y vuelve a sonar;
##   · la voz sigue siendo el audio 3D pegado a UN enemigo real del grupo (el que
##     anuncia), así que se oye venir de donde están ellos.
##
## Devuelve el nodo de voz del enemigo que anunció, o null si esta aparición calló
## (bien porque pertenece a un grupo ya anunciado, bien porque no se pudo crear).
static func anunciar_aparicion(enemigo: Node3D) -> VocesAparicion:
	if enemigo == null or not enemigo.is_inside_tree():
		return null
	var ahora := Time.get_ticks_msec() / 1000.0
	if ahora - _t_grupo <= VENTANA_GRUPO:
		# Ya hay un grupo abierto: esta aparición pertenece a él y NO añade voz.
		# El sello se refresca para que un grupo que tarda en formarse (varias
		# llamadas seguidas del panel/evento) siga siendo UN solo grupo.
		_t_grupo = ahora
		return null
	_t_grupo = ahora
	_grupos_anunciados += 1
	var voces := instalar(enemigo)
	if voces != null:
		voces.sonar()
	return voces


## Grupos de aparición anunciados desde el último reinicio (lo usan las pruebas).
static func grupos_anunciados() -> int:
	return _grupos_anunciados


## Reinicia los contadores de grupo (pruebas).
static func reiniciar_grupos() -> void:
	_grupos_anunciados = 0
	_t_grupo = -99.0


## Reinicia la rueda, el reparto y los grupos (lo usan las pruebas para medir de cero).
static func reiniciar_rueda() -> void:
	_bolsa.clear()
	_ultimo = -1
	_t_ultimo = -99.0
	reiniciar_grupos()


# =============================================================== API de instancia
## Reproduce UNA voz aleatoria. `retardo` (s) reparte las apariciones
## simultáneas. `forzar` sólo para un evento explícito NUEVO sobre el mismo
## enemigo: por defecto una aparición = una voz.
func sonar(retardo: float = 0.0, forzar: bool = false) -> void:
	if _sono and not forzar:
		return
	var lista := streams_disponibles()
	if lista.is_empty():
		return
	_sono = true
	var indice := _siguiente_indice(lista.size())
	stream = lista[indice]
	_archivo = _rutas[indice] if indice < _rutas.size() else ""
	if retardo <= 0.0 or not is_inside_tree():
		_reproducir()
		return
	var t := get_tree().create_timer(retardo)
	t.timeout.connect(_reproducir)


## ¿Ya soltó su voz esta instancia?
func ya_sono() -> bool:
	return _sono

## Veces que ha sonado esta instancia (las pruebas cuentan con esto).
func veces_sonado() -> int:
	return _veces

## Ruta del archivo que le tocó ("" si aún no sonó).
func archivo_actual() -> String:
	return _archivo


# =============================================================== interno
func _reproducir() -> void:
	# El enemigo puede haber muerto (o el árbol, pausarse) antes de que venza el
	# retardo: en ese caso no suena nada.
	if not is_inside_tree() or stream == null:
		return
	_veces += 1
	play()


## Rueda mezclada: baraja la bolsa al vaciarse y evita repetir la última de la
## ronda anterior. Con una sola grabación válida, siempre sale esa.
static func _siguiente_indice(cantidad: int) -> int:
	if cantidad <= 1:
		_ultimo = 0
		return 0
	if _bolsa.is_empty():
		_bolsa.resize(cantidad)
		for i in cantidad:
			_bolsa[i] = i
		_bolsa.shuffle()
		if _bolsa[0] == _ultimo:
			var j := 1 + (randi() % (cantidad - 1))
			var tmp := _bolsa[0]
			_bolsa[0] = _bolsa[j]
			_bolsa[j] = tmp
	var indice: int = _bolsa.pop_front()
	_ultimo = indice
	return indice


static func _informar_una_vez(texto: String) -> void:
	if _avisado:
		return
	_avisado = true
	push_warning(texto)
	print(texto)