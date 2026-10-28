class_name SemillaMundo
extends RefCounted
## =============================================================================
##  SEMILLA DEL MUNDO — el ÚNICO sitio donde se decide el azar del mapa.
## =============================================================================
##
## Todo lo que el juego reparte al azar (la ciudad entera, los peatones y su
## aspecto…) toma su semilla de aquí. Cada sistema tiene la SUYA, derivada de su
## nombre, con su propio `RandomNumberGenerator`:
##
##     var rng := RandomNumberGenerator.new()
##     rng.seed = SemillaMundo.semilla_de("ciudad")
##
## Ventajas de este reparto:
##   · Dos partidas con la misma `SEMILLA` dan un mundo IDÉNTICO, pieza a pieza.
##   · Lo que sortee un sistema no cambia lo que sortee otro: no se depende del
##     orden en que cada uno pida números aleatorios ni de cuántos pida.
##   · Cambiar el nombre de UN sistema (`"peatones"` → `"peatones_v2"`) cambia
##     sólo ese sistema y deja el resto del mundo igual.
##
## CÓMO CAMBIAR EL MUNDO: toca `SEMILLA` y vuelve a generar. Se reparten de otra
## manera las calles, las manzanas, los edificios, los parques, la playa, las
## tapas de alcantarilla, las marcas viales, la vegetación, los peatones y el
## aspecto de cada peatón, y el resultado sigue siendo idéntico en cada partida.
##
## PARA VOLVER AL AZAR DE ANTES (para experimentar): pon `SEMILLA_ALEATORIA` en
## `true`; entonces cada partida es distinta, como antes de este cambio.
## =============================================================================

## Semilla maestra del mundo. Es lo único que hay que tocar para repartir el mapa
## de otra forma; el resto de sistemas la derivan solos.
const SEMILLA := 20260215

## `false` (por defecto) = mundo FIJO: siempre el mismo mapa.
## `true` = cada partida distinta (azar en cada arranque, como antes).
const SEMILLA_ALEATORIA := false


## Semilla ESTABLE y propia del sistema pedido: la misma cadena da siempre la
## misma semilla, en cualquier partida y en cualquier equipo. No se usa `hash()`
## del motor (podría cambiar entre versiones): se calcula aquí, con aritmética de
## enteros de 64 bits, y luego se mezcla con la semilla maestra.
static func semilla_de(sistema: String) -> int:
	if SEMILLA_ALEATORIA:
		return int(randi())
	# 1) FNV-1a de 32 bits sobre el nombre del sistema.
	var h := 5381
	for i in sistema.length():
		h = (h ^ sistema.unicode_at(i)) * 16777619
	# 2) Mezcla con la semilla maestra: dos rondas (multiplicar y desplazar) para
	#    que un cambio de SEMILLA mueva TODAS las derivadas, no sólo la última.
	var s := SEMILLA
	s = s * 6364136223846793005 + 1442695040888963407
	s = s ^ (s >> 33)
	s = s * 1165197095201016109 + 1
	s = s ^ (s >> 29)
	return absi(h ^ s)


## RNG propio de un sistema, ya sembrado con `semilla_de()`. Es la forma cómoda
## para scripts que sólo necesitan un generador:
##
##     var rng := SemillaMundo.rng("farolas")
static func rng(sistema: String) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = semilla_de(sistema)
	return r


## Texto corto para la consola y los informes.
static func descripcion() -> String:
	return "SEMILLA=%d%s" % [SEMILLA, " (ALEATORIA)" if SEMILLA_ALEATORIA else " (fija)"]