class_name EscaleraBarco
extends Node3D
## =============================================================================
##  ESCALERA (punto de agarre para la forma acuática)
## =============================================================================
##  Este nodo NO es una escalera de colisión ni un ascensor: es el "anclaje" que
##  el controlador del personaje consulta cuando el jugador pulsa INTERACTUAR (E).
##  El controlador es quien mueve el cuerpo, y aquí se describe TODO lo que
##  necesita para que el cuerpo siga la estructura REAL de la escalera:
##
##   * Por dónde entra al agua (inicio_local) y por dónde sale a cubierta
##     (tope_local = la boca de salida, fin_local = ya sobre la superficie).
##   * La separación REAL entre peldaños y cuántos avanza el clip de trepada por
##     ciclo, para que manos y pies caigan en los peldaños (sin desfase).
##   * Hacia dónde mira el cuerpo mientras trepa (mirada_local) y el giro extra
##     que necesita el clip nuevo (giro_cuerpo).
##
##  Dos escaleras lo usan: la del barco (barco.gd) y la del muelle (muelle.gd).
## =============================================================================

## Radio (m, sólo horizontal) dentro del cual el cuerpo que nada puede agarrarse.
## Es TAMBIÉN la zona del aviso "Presioná E...": el controlador usa puede_subir()
## para las dos cosas, así que el mensaje aparece exactamente cuando la tecla
## funciona (ni antes ni después) y nunca parpadea.
@export var radio_agarre: float = 2.4
## Texto del aviso contextual para SUBIR (desde el agua).
@export var texto_prompt: String = "Presioná E para subir al barco"
## Texto del aviso contextual para BAJAR (desde la cubierta), en el borde superior
## de la escalera. Mismo criterio: sólo aparece cuando E funciona.
@export var texto_prompt_bajada: String = "Presioná E para bajar al agua"
## Radio (m, horizontal) de la zona de bajada, medida desde el punto de arriba.
@export var radio_bajada: float = 2.1
## Punto LOCAL de agarre en el agua (documentación del pie; usa `inicio_local`).
@export var pie_local: Vector3 = Vector3.ZERO
## Punto LOCAL donde termina la subida (compatibilidad; usa `fin_local`).
@export var cima_local: Vector3 = Vector3(3.0, 5.2, 0.0)
## Dirección LOCAL (horizontal) del casco: hacia donde queda la estructura.
@export var mirada_local: Vector3 = Vector3(1.0, 0.0, 0.0)

# ---------------------------------------------------------------- RECORRIDO
## Cuerpo (origen) al EMPEZAR a trepar: en el agua, a la altura de la superficie.
@export var inicio_local: Vector3 = Vector3(0.0, -0.8, 0.0)
## Cuerpo en la BOCA de salida (arriba, dentro del hueco de la amurada).
@export var tope_local: Vector3 = Vector3(0.0, 3.9, 0.0)
## Cuerpo YA sobre la superficie transitable (cubierta del barco / del muelle).
@export var fin_local: Vector3 = Vector3(1.85, 3.8, 0.0)
## Separación REAL (m) entre peldaños de ESTA escalera.
@export var separacion_peldanos: float = 0.4875
## Cuántos peldaños avanza el cuerpo con UN ciclo completo del clip de trepada.
@export var peldanos_por_ciclo: float = 2.0
## Giro extra (rad) al orientar el cuerpo durante la trepada. MEDIDO con el arnés
## de diagnóstico: el clip de trepada tiene las manos en el lado -Z del modelo, que
## es su frente, igual que el resto de la librería acuática, así que NO hace falta
## ningún giro. Está expuesto por si alguna escalera futura usara otro clip.
@export var giro_cuerpo: float = 0.0

## Fracción del recorrido en la que el cuerpo ya está arriba y pasa hacia dentro.
const U_INGRESO := 0.82

## Pies del clip de trepada por encima del origen del cuerpo (MEDIDO con el arnés de
## diagnóstico: los huesos de los pies caen ~0,35 m sobre el origen). Lo usan los
## constructores (barco.gd, muelle.gd) para colocar el inicio de la trepada cuando
## los pies se apoyan en el primer peldaño.
const AIRE_PIE_TREPADA := 0.35


func _ready() -> void:
	add_to_group("escalera_barco")


## Pie de la escalera en coordenadas GLOBALES (primer punto del recorrido).
func pie() -> Vector3:
	return to_global(inicio_local)


## Punto de coronación en coordenadas GLOBALES (sobre la cubierta).
func cima() -> Vector3:
	return to_global(fin_local)


## Avance (m) del cuerpo con UN ciclo completo del clip de trepada: es lo que ata
## la animación a los peldaños.
func avance_por_ciclo() -> float:
	return maxf(separacion_peldanos * peldanos_por_ciclo, 0.05)


## Punto GLOBAL del cuerpo para el progreso [param u] de la trepada
## (0 = en el agua al pie, 1 = de pie sobre la superficie transitable).
##
## El recorrido tiene dos tramos: la SUBIDA pegada a la escalera (x/z fijos, sólo
## cambia la altura) y, una vez arriba, el PASO hacia dentro por el hueco, que
## termina dejando el cuerpo sobre la cubierta.
func punto_trepada(u: float) -> Vector3:
	var v := clampf(u, 0.0, 1.0)
	var p := inicio_local
	if v <= U_INGRESO:
		p.y = lerpf(inicio_local.y, tope_local.y, v / U_INGRESO)
		return to_global(p)
	var t := (v - U_INGRESO) / (1.0 - U_INGRESO)
	p.y = lerpf(tope_local.y, fin_local.y, t)
	var s := smoothstep(0.0, 1.0, t)
	p.x = lerpf(tope_local.x, fin_local.x, s)
	p.z = lerpf(tope_local.z, fin_local.z, s)
	return to_global(p)


## Altura (m) que sube el cuerpo de un extremo al otro de la escalera.
func altura_trepada() -> float:
	return maxf(absf(tope_local.y - inicio_local.y), 0.1)


## ¿Puede el cuerpo situado en `punto` (global) agarrarse para SUBIR? Debe estar a
## la altura del agua, no por encima de la cubierta ni demasiado hundido, y dentro
## del radio de agarre.
func puede_subir(punto: Vector3) -> bool:
	var p_pie := pie()
	var p_cima := cima()
	if punto.y > p_cima.y - 0.8:
		return false
	if punto.y < p_pie.y - 3.0:
		return false
	var plano := Vector2(punto.x - p_pie.x, punto.z - p_pie.z)
	return plano.length() <= radio_agarre


## ¿Puede el cuerpo situado en `punto` (global) BAJAR por esta escalera? Está de
## pie en la superficie, junto a la boca de salida de la escalera.
func puede_bajar(punto: Vector3) -> bool:
	var p_fin := cima()
	if absf(punto.y - p_fin.y) > 1.4:
		return false
	var plano := Vector2(punto.x - p_fin.x, punto.z - p_fin.z)
	return plano.length() <= radio_bajada


## Dirección horizontal (global) del casco, para orientar el cuerpo al trepar.
func direccion_mirada() -> Vector3:
	var d := to_global(mirada_local) - to_global(Vector3.ZERO)
	d.y = 0.0
	return d.normalized() if d.length_squared() > 0.0001 else Vector3.FORWARD