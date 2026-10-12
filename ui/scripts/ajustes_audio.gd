class_name AjustesAudioService
extends Node

## Ajustes de AUDIO (autoload, nombre global `AjustesAudio`).
##
## Es el ÚNICO punto donde se guardan y (en el futuro) se aplican los ajustes de
## la categoría AUDIO. El menú de configuración solo pide cambios y este nodo los
## ejecuta:
##   · Volumen general   (0..100): será el control MAESTRO de todo el audio.
##   · Volumen de música (0..100): bus "Musica".
##   · Volumen de efectos(0..100): bus "Efectos".
##   · Desactivar diálogos (SÍ/NO): bus "Dialogos".
##
## -----------------------------------------------------------------------------
## ETAPA ACTUAL: SIN SONIDO
## -----------------------------------------------------------------------------
## PRISMAX todavía no tiene archivos de audio. Por eso estas cuatro preferencias
## son, de momento, SOLO valores guardados: los controles de la interfaz se mueven,
## muestran su número y persisten, pero NO modifican ningún bus ni reproducen nada.
##
## Toda la preparación para el futuro está concentrada en _aplicar() y en la
## constante APLICAR_VOLUMEN_REAL. Cuando llegue el audio real basta con:
##   1) poner APLICAR_VOLUMEN_REAL = true, y
##   2) enrutar cada reproductor (música/efectos/diálogos) a su bus correspondiente.
## No hay que rehacer ni la interfaz ni el guardado.
##
## La lista de buses vive en res://default_bus_layout.tres (Master ya existe;
## se añaden Musica, Efectos y Dialogos, todos inertes: ningún sonido los usa aún).
##
## Persistencia: un ConfigFile propio (user://ajustes_audio.cfg) con solo la
## sección "audio". No toca otros guardados del proyecto.

signal cambiado

const RUTA := "user://ajustes_audio.cfg"
const SECCION := "audio"

# --- Rango y valores por defecto -------------------------------------------------
const VOL_MIN := 0
const VOL_MAX := 100
const VOL_GENERAL_DEFECTO := 100
const VOL_MUSICA_DEFECTO := 80
const VOL_EFECTOS_DEFECTO := 80
const DESACTIVAR_DIALOGOS_DEFECTO := false

## Nivel de decibelios que se considera silencio absoluto (mismo valor que usa
## Godot para el mínimo del bus). Se usa al convertir un porcentaje de 0.
const DB_SILENCIO := -80.0

# --- Nombres de bus (estructura preparada, ver default_bus_layout.tres) ----------
const BUS_MASTER := &"Master"
const BUS_MUSICA := &"Musica"
const BUS_EFECTOS := &"Efectos"
const BUS_DIALOGOS := &"Dialogos"

## Interruptor de la etapa. En false NADA del audio se toca (etapa actual sin
## sonidos). Cuando exista audio real, ponerlo a true para activar la aplicación.
const APLICAR_VOLUMEN_REAL := false

# --- Estado (lectura directa desde el menú) -------------------------------------
var volumen_general: int = VOL_GENERAL_DEFECTO
var volumen_musica: int = VOL_MUSICA_DEFECTO
var volumen_efectos: int = VOL_EFECTOS_DEFECTO
var desactivar_dialogos: bool = DESACTIVAR_DIALOGOS_DEFECTO

func _ready() -> void:
	_cargar()
	# En la etapa actual esto no cambia nada; queda como punto de enganche futuro.
	_aplicar()

# ---------------------------------------------------------------- conversión
## Convierte un porcentaje 0..100 al volumen en decibelios de Godot.
## 0 -> silencio absoluto; 100 -> 0 dB (nivel máximo, sin atenuación).
## NO es una regla de tres: el volumen percibido es logarítmico.
func porcentaje_a_db(porcentaje: int) -> float:
	var p := clampi(porcentaje, VOL_MIN, VOL_MAX)
	if p <= 0:
		return DB_SILENCIO
	return linear_to_db(float(p) / 100.0)

# ---------------------------------------------------------------- API (menú)
func poner_volumen_general(v: int) -> void:
	v = clampi(v, VOL_MIN, VOL_MAX)
	if v == volumen_general:
		return
	volumen_general = v
	_aplicar()
	_guardar()
	cambiado.emit()

func poner_volumen_musica(v: int) -> void:
	v = clampi(v, VOL_MIN, VOL_MAX)
	if v == volumen_musica:
		return
	volumen_musica = v
	_aplicar()
	_guardar()
	cambiado.emit()

func poner_volumen_efectos(v: int) -> void:
	v = clampi(v, VOL_MIN, VOL_MAX)
	if v == volumen_efectos:
		return
	volumen_efectos = v
	_aplicar()
	_guardar()
	cambiado.emit()

func poner_desactivar_dialogos(v: bool) -> void:
	if v == desactivar_dialogos:
		return
	desactivar_dialogos = v
	_aplicar()
	_guardar()
	cambiado.emit()

func alternar_desactivar_dialogos() -> void:
	poner_desactivar_dialogos(not desactivar_dialogos)

# ---------------------------------------------------------------- aplicación
## Punto ÚNICO donde los ajustes se conectan a los buses de audio. En la etapa
## actual no hace nada porque APLICAR_VOLUMEN_REAL es false: el juego no tiene
## sonido todavía y estas preferencias solo se guardan.
##
## El volumen general actúa como MAESTRO (bus "Master") y no destruye los valores
## individuales de música/efectos/diálogos: cada categoría conserva el suyo.
func _aplicar() -> void:
	if not APLICAR_VOLUMEN_REAL:
		return
	_aplicar_bus(BUS_MASTER, volumen_general)
	_aplicar_bus(BUS_MUSICA, volumen_musica)
	_aplicar_bus(BUS_EFECTOS, volumen_efectos)
	# Los diálogos se controlan por el propio bus: SÍ = silenciado, NO = normal.
	var idx_dialogos := AudioServer.get_bus_index(BUS_DIALOGOS)
	if idx_dialogos >= 0:
		AudioServer.set_bus_mute(idx_dialogos, desactivar_dialogos)

## Aplica un porcentaje a un bus existente. Tolera que el bus no exista (por si
## el layout cambia) sin lanzar errores.
func _aplicar_bus(nombre: StringName, porcentaje: int) -> void:
	var idx := AudioServer.get_bus_index(nombre)
	if idx < 0:
		return
	AudioServer.set_bus_volume_db(idx, porcentaje_a_db(porcentaje))

# ---------------------------------------------------------------- persistencia
func _guardar() -> void:
	var cf := ConfigFile.new()
	# Se carga antes de escribir para no borrar claves ajenas del mismo archivo.
	cf.load(RUTA)
	cf.set_value(SECCION, "volumen_general", volumen_general)
	cf.set_value(SECCION, "volumen_musica", volumen_musica)
	cf.set_value(SECCION, "volumen_efectos", volumen_efectos)
	cf.set_value(SECCION, "desactivar_dialogos", desactivar_dialogos)
	cf.save(RUTA)

func _cargar() -> void:
	var cf := ConfigFile.new()
	if cf.load(RUTA) != OK:
		return
	volumen_general = clampi(
			int(cf.get_value(SECCION, "volumen_general", VOL_GENERAL_DEFECTO)), VOL_MIN, VOL_MAX)
	volumen_musica = clampi(
			int(cf.get_value(SECCION, "volumen_musica", VOL_MUSICA_DEFECTO)), VOL_MIN, VOL_MAX)
	volumen_efectos = clampi(
			int(cf.get_value(SECCION, "volumen_efectos", VOL_EFECTOS_DEFECTO)), VOL_MIN, VOL_MAX)
	desactivar_dialogos = bool(
			cf.get_value(SECCION, "desactivar_dialogos", DESACTIVAR_DIALOGOS_DEFECTO))