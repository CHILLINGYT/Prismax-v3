class_name ContactoGolpe
extends RefCounted

## CONTACTO DE GOLPES — criterios COMPARTIDOS por todas las transformaciones
## (Tarea 6). No es un sistema de daño nuevo: cada forma sigue usando SU contrato
## (take_hit del módulo de combate, take_damage de Fuerza, apply_damage de agua).
## Lo que se comparte es DÓNDE y a QUÉ DISTANCIA se considera que un golpe alcanza,
## para que todas midan igual:
##
##   · PUNTO DE CONTACTO: sobre la SUPERFICIE del objetivo que mira al atacante
##     (`get_hit_center()` + `get_hit_radius()`), nunca en su origen. Los enemigos
##     del proyecto tienen el origen en los PIES y el centro de golpe a la altura del
##     torso: medir contra los pies hacía que un puñetazo al pecho contase como lejano
##     en objetivos altos, voladores o en movimiento.
##   · DISTANCIA DE CONTACTO: entre las dos SUPERFICIES (se descuentan los radios de
##     golpe), de modo que "alcanza" significa lo mismo para un enemigo gordo que para
##     uno delgado. Con `peso_altura` se puede atenuar la componente vertical (lo usan
##     los golpes acuáticos, que llegan más por delante que por arriba).
##   · ARCO: sólo cuenta lo que está DELANTE del cuerpo del atacante (producto punto
##     contra su adelante horizontal) y dentro de una BANDA VERTICAL.
##   · VIVO: un objetivo ya derrotado no recibe golpes ni efectos.
##
## Estos son EXACTAMENTE los criterios con los que se mejoró la transformación de
## combate (distancia al centro de golpe, arco frontal y tolerancia vertical): aquí
## quedan escritos una sola vez para que las demás formas no los reinventen.

## Radio (m) de golpe que se supone a un objetivo que no expone `get_hit_radius()`.
const RADIO_POR_DEFECTO := 0.5
## Altura (m) del centro de golpe de un objetivo que no expone `get_hit_center()`.
const ALTURA_POR_DEFECTO := 1.0


## Centro de golpe del objetivo: su contrato si lo tiene, o su origen + la altura
## por defecto (los pies + 1 m) si no.
static func centro(objetivo: Node3D) -> Vector3:
	if objetivo == null:
		return Vector3.ZERO
	if objetivo.has_method("get_hit_center"):
		var c: Variant = objetivo.call("get_hit_center")
		if c is Vector3:
			return c
	return objetivo.global_position + Vector3.UP * ALTURA_POR_DEFECTO


## Radio de golpe del objetivo (0 si no expone el contrato, para no inventar volumen).
static func radio(objetivo: Node3D) -> float:
	if objetivo == null or not objetivo.has_method("get_hit_radius"):
		return 0.0
	return maxf(float(objetivo.call("get_hit_radius")), 0.0)


## Punto de CONTACTO real: sobre la superficie del objetivo que mira al atacante.
## `desde` es el punto del atacante (o el centro de su golpe). Igual que el efecto de
## impacto de los enemigos: centro menos dirección por 0,9 del radio, un pelín hacia
## arriba y hacia el atacante para que no quede enterrado.
static func punto_de_contacto(objetivo: Node3D, desde: Vector3) -> Vector3:
	if objetivo == null:
		return desde
	var c := centro(objetivo)
	var r := radio(objetivo)
	var d := c - desde
	d.y = 0.0
	if d.length_squared() > 0.0001:
		d = d.normalized()
	else:
		d = Vector3.FORWARD
	return c - d * r * 0.9 + Vector3.UP * 0.05 - d * 0.05


## Distancia de CONTACTO (m): de superficie a superficie, midiendo desde `punto`
## (el centro del golpe) hasta el centro de golpe del objetivo. `peso_altura` (0-1)
## atenúa la componente vertical; `radio_propio` añade el volumen del atacante.
## Devuelve `INF` si el objetivo no es válido.
static func distancia_de_contacto(objetivo: Node3D, punto: Vector3,
		peso_altura: float = 1.0, radio_propio: float = 0.0) -> float:
	if objetivo == null:
		return INF
	var d := centro(objetivo) - punto
	d.y *= clampf(peso_altura, 0.0, 1.0)
	return maxf(0.0, d.length() - radio(objetivo) - radio_propio)


## ¿El objetivo está DENTRO del arco frontal del atacante? `adelante` debe ser el
## adelante horizontal (ya normalizado o no: se normaliza aquí). `dot_min` es el
## coseno mínimo: 1 = justo enfrente, 0 = 90°, negativo = también lo de los lados.
static func en_arco(objetivo: Node3D, desde: Vector3, adelante: Vector3,
		dot_min: float) -> bool:
	if objetivo == null:
		return false
	var a := Vector3(adelante.x, 0.0, adelante.z)
	if a.length_squared() <= 0.0001:
		return false
	a = a.normalized()
	var hacia := centro(objetivo) - desde
	hacia.y = 0.0
	if hacia.length_squared() <= 0.0001:
		return true
	return hacia.normalized().dot(a) >= dot_min


## ¿El objetivo está dentro de la banda VERTICAL del atacante (±tolerancia)?
## Se mide CENTRO DE GOLPE contra CENTRO DE GOLPE: así un cuerpo y su objetivo al
## mismo nivel dan 0 (igual que medir pies contra pies) y un objetivo levantado se
## compara por su masa real, no por su origen.
static func en_banda_vertical(objetivo: Node3D, atacante: Node3D, tolerancia: float) -> bool:
	if objetivo == null or atacante == null:
		return false
	return absf(centro(objetivo).y - centro(atacante).y) <= tolerancia


## ¿El objetivo puede recibir el golpe ahora mismo? (derrotado = no)
static func objetivo_valido(objetivo: Node3D, atacante: Node = null) -> bool:
	if objetivo == null or objetivo == atacante or not objetivo.is_inside_tree():
		return false
	if objetivo.has_method("is_alive") and not bool(objetivo.call("is_alive")):
		return false
	return true


## ¿Alcanza el golpe? Reúne los cuatro criterios: objetivo válido + alcance de
## contacto desde el punto del golpe + arco frontal + banda vertical (centro contra
## centro del atacante y del objetivo). Es la comprobación que usan las formas al
## aplicar daño: `punto` es el centro del golpe (por delante del cuerpo) y
## `radio_golpe` el volumen del puño/pie, que se suma al radio del objetivo.
static func alcanza(objetivo: Node3D, atacante: Node3D, punto: Vector3, radio_golpe: float,
		adelante: Vector3, dot_min: float, tolerancia_vertical: float,
		peso_altura: float = 1.0) -> bool:
	if not objetivo_valido(objetivo, atacante):
		return false
	if distancia_de_contacto(objetivo, punto, peso_altura, radio_golpe) > 0.0:
		return false
	if not en_arco(objetivo, punto, adelante, dot_min):
		return false
	return en_banda_vertical(objetivo, atacante, tolerancia_vertical)


## Dirección horizontal del empuje: del atacante hacia el objetivo (nunca una
## dirección fija del mundo). Cae al `adelante` si los dos cuerpos coinciden.
static func direccion_de_empuje(objetivo: Node3D, desde: Vector3, adelante: Vector3) -> Vector3:
	var d := objetivo.global_position - desde
	d.y = 0.0
	if d.length_squared() > 0.0001:
		return d.normalized()
	var a := Vector3(adelante.x, 0.0, adelante.z)
	return a.normalized() if a.length_squared() > 0.0001 else Vector3.FORWARD