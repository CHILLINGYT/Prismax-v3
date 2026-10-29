class_name HornearRelieve
extends RefCounted
## =============================================================================
##  HORNEADOR DEL RELIEVE DE LA ISLA
## =============================================================================
##  Regenera los DOS mapas que consume el nodo `Terreno` (world/terreno3d.gd) a
##  partir de la matemática de `Relieve`:
##
##    * res://world/altura_isla.res  -> mapa de ALTURA (Image FORMAT_RF,
##      1024x1024, 2 m por texel, cubre [-1024,1024]², fila = Z creciente y
##      columna = X creciente, sin invertir).
##    * res://world/control_isla.res -> mapa de CONTROL: qué textura del terreno
##      se pinta en cada texel (arena en playa y fondo marino, suelo de bosque en
##      lo llano, roca en laderas y cumbres).
##
##  Hay que volver a ejecutarlo SIEMPRE que se toque `Relieve`: los árboles, la
##  hierba, las colisiones y el propio relieve se calculan con esas funciones, así
##  que si el mapa no coincide con ellas el mundo entero se descoloca.
##
##  TRAMPA DEL MAPA DE CONTROL (costó una sesión entera): NO es un mapa de pesos
##  RGBA. El canal R guarda un entero de 32 bits EMPAQUETADO (bit 0 = autoshader,
##  bits 14-21 = mezcla, bits 22-26 = overlay, bits 27-31 = base) que el shader del
##  complemento lee con floatBitsToUint. Se codifica con `Terrain3DUtil`
##  (nunca a mano) y se guarda en el canal R de una imagen FORMAT_RF.
##
##  Y la trampa grave: si un texel tiene LA MISMA textura en base y en overlay, el
##  shader compilado del complemento dibuja esa superficie NEGRA. Por eso la arena
##  se pinta como base = ROCA (peso cero) + overlay = ARENA + blend = 255: como la
##  mezcla repartía una textura consigo misma, se ve igual y deja de ser negro.
## =============================================================================

## Índices de las texturas en `res://demo/data/assets.tres` (más la arena, que la
## añade `terreno3d.gd` en tiempo de ejecución).
const ROCA := 0     ## "Cliff" (rock023)
const SUELO := 1    ## "Grass" (ground037), el suelo de bosque
const ARENA := 2    ## la añade terreno3d.gd con res://assets/generated/arena_playa_hd.png

const RUTA_ALTURAS := "res://world/altura_isla.res"
const RUTA_CONTROL := "res://world/control_isla.res"
## Resolución y cobertura del mapa (deben coincidir con terreno3d.gd).
const LADO_PX := 1024
const ORIGEN := -1024.0
const PASO := 2.0
## Pendiente (grados) a la que la roca empieza a ganar peso sobre el suelo.
const ROCA_PENDIENTE_MIN := 30.0
const ROCA_PENDIENTE_MAX := 55.0
## Cota (m) a la que el suelo deja paso a la roca por altura (línea de árboles).
const ROCA_ALTURA_MIN := 68.0
const ROCA_ALTURA_MAX := 92.0
## Cota por debajo de la cual el terreno es arena. El suelo urbano está en -0.30 y
## la cota de arena de Relieve en -0.50: así la playa empieza donde el terreno baja
## de verdad hacia la orilla y no bajo el pavimento de la ciudad.


## Hornea los dos mapas. Devuelve un informe con la comprobación de cada uno.
static func hornear() -> Dictionary:
	var rel := Relieve.new()
	var t0 := Time.get_ticks_msec()
	var alturas := _hornear_alturas(rel)
	var control := _hornear_control(rel)
	var informe := {
		"altura_err": ResourceSaver.save(alturas, RUTA_ALTURAS),
		"control_err": ResourceSaver.save(control, RUTA_CONTROL),
		"ms": Time.get_ticks_msec() - t0,
	}
	# Comprobación: el mapa guardado debe reproducir la matemática de Relieve.
	informe["desvio_max"] = _comprobar(alturas, rel)
	return informe


static func _hornear_alturas(rel: Relieve) -> Image:
	var img := Image.create(LADO_PX, LADO_PX, false, Image.FORMAT_RF)
	for py in LADO_PX:
		var z := ORIGEN + float(py) * PASO
		for px in LADO_PX:
			var x := ORIGEN + float(px) * PASO
			img.set_pixel(px, py, Color(rel.altura(x, z), 0.0, 0.0, 1.0))
	return img


## Pinta cada texel: arena en la playa y el fondo marino, y en tierra suelo de
## bosque en lo llano con roca en laderas y cumbres. Nunca base == overlay.
static func _hornear_control(rel: Relieve) -> Image:
	var img := Image.create(LADO_PX, LADO_PX, false, Image.FORMAT_RF)
	for py in LADO_PX:
		var z := ORIGEN + float(py) * PASO
		for px in LADO_PX:
			var x := ORIGEN + float(px) * PASO
			var h := rel.altura(x, z)
			var en_agua := h < Relieve.NIVEL_MAR
			# Arena: TODO el fondo marino y, en tierra, la franja de playa (cerca de
			# la orilla y por debajo de la cota de arena). Así la arena no sube por
			# las laderas de roca ni aparece bajo el pavimento de la ciudad.
			var playa := h < Relieve.COTA_ARENA and (en_agua or rel.distancia_costa(x, z) < Relieve.ANCHO_PLAYA)
			var base := ROCA
			var overlay := ARENA
			var blend := 255
			if not (en_agua or playa):
				overlay = SUELO
				var pend := rel.pendiente(x, z, 4.0)
				var peso := 1.0 - smoothstep(ROCA_PENDIENTE_MIN, ROCA_PENDIENTE_MAX, pend)
				peso *= 1.0 - smoothstep(ROCA_ALTURA_MIN, ROCA_ALTURA_MAX, h)
				blend = int(round(clampf(peso, 0.0, 1.0) * 255.0))
			# Arena con base distinta y todo el peso en el overlay: ver TRAMPA 2.
			if overlay == ARENA:
				blend = 255
			var v: int = Terrain3DUtil.enc_auto(0) | Terrain3DUtil.enc_base(base) \
					| Terrain3DUtil.enc_overlay(overlay) | Terrain3DUtil.enc_blend(blend)
			img.set_pixel(px, py, Color(Terrain3DUtil.as_float(v), 0.0, 0.0, 1.0))
	return img


## Desvío máximo (m) entre el mapa horneado y `Relieve`, muestreado en una rejilla.
static func _comprobar(img: Image, rel: Relieve) -> float:
	var peor := 0.0
	var i := 0
	while i < LADO_PX:
		var j := 0
		while j < LADO_PX:
			var x := ORIGEN + float(i) * PASO
			var z := ORIGEN + float(j) * PASO
			peor = maxf(peor, absf(img.get_pixel(i, j).r - rel.altura(x, z)))
			j += 37
		i += 37
	return peor