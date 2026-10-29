class_name VfxImpacto
extends RefCounted

## EFECTO DE IMPACTO de los golpes sobre los ENEMIGOS (Tarea 4).
##
## Se pide desde los DOS embudos de daño de los enemigos (`_aplicar_dano` de
## `enemigo_base.gd` y de `enemigo_prueba.gd`), o sea EXACTAMENTE cuando el daño
## se confirma:
##  · un golpe al aire, uno a distancia imposible o una colisión que no llega a
##    aplicar daño NO genera ningún efecto;
##  · una llamada = un impacto: el mismo golpe no puede duplicar el efecto por
##    repetirse el chequeo en varios fotogramas (el daño es por evento, no por
##    fotograma) ni por alcanzar a varios enemigos (cada uno tiene su punto);
##  · el efecto nace en el PUNTO DE CONTACTO REAL: sobre la superficie del
##    enemigo que mira al atacante (su `get_hit_center()` + `get_hit_radius()`),
##    nunca en el suelo ni a una distancia arbitraria.
##
## REUTILIZA lo que ya tiene el proyecto — la biblioteca de efectos
## `FuerzaVfx` (chispas de energía + polvo, hechas por código) — y no inventa
## ningún asset nuevo. El tamaño sube con la fuerza del golpe para que los
## remates se noten más que un roce.

## Colores del impacto (chispas cálidas + polvo claro: legibles sobre cualquier
## fondo y coherentes con los demás impactos del proyecto).
const COLOR_CHISPAS := Color(1.0, 0.86, 0.48)
const COLOR_POLVO := Color(0.74, 0.71, 0.67)
## Daño de referencia para escalar el efecto (los golpes de ~20 ya salen al 100 %).
const DANIO_REFERENCIA := 20.0

## Reproduce el impacto en la superficie del enemigo que mira al atacante.
## `dir_empuje` es la dirección del empuje recibido (del atacante hacia el
## enemigo); `cantidad` es el daño real aplicado (escala el efecto).
static func reproducir(enemigo: Node3D, dir_empuje: Vector3, cantidad: float) -> void:
	if enemigo == null or not enemigo.is_inside_tree():
		return
	# Centro y radio de golpe del enemigo (el mismo contrato que usa el combate).
	var centro := enemigo.global_position + Vector3.UP * 1.0
	if enemigo.has_method("get_hit_center"):
		var c: Variant = enemigo.call("get_hit_center")
		if c is Vector3:
			centro = c
	var radio := 0.6
	if enemigo.has_method("get_hit_radius"):
		radio = maxf(float(enemigo.call("get_hit_radius")), 0.2)
	# Punto de contacto: del centro hacia el atacante (el atacante está en -dir).
	var d := dir_empuje
	d.y = 0.0
	if d.length_squared() > 0.0001:
		d = d.normalized()
	else:
		# Sin dirección (p. ej. un remate): se usa el frente del enemigo.
		d = -enemigo.global_transform.basis.z
		d.y = 0.0
		d = d.normalized() if d.length_squared() > 0.0001 else Vector3.FORWARD
	var punto := centro - d * radio * 0.9
	# Un pelín hacia arriba y hacia el atacante, para que no salga del centro.
	punto += Vector3.UP * 0.05 - d * 0.05
	# Las partículas cuelgan del PADRE del enemigo (el mundo/gerente): siguen
	# vivas aunque el enemigo muera en ese mismo golpe.
	var padre := enemigo.get_parent() as Node3D
	if padre == null:
		padre = enemigo
	var fuerza := clampf(cantidad / DANIO_REFERENCIA, 0.35, 1.3)
	FuerzaVfx.chispas(padre, punto, 0.12 + 0.26 * fuerza,
			int(round(10.0 + 16.0 * fuerza)), COLOR_CHISPAS, 0.45, 6.5 * fuerza)
	FuerzaVfx.polvo(padre, punto, 0.18 + 0.20 * fuerza,
			int(round(6.0 + 8.0 * fuerza)), COLOR_POLVO, 0.75, 1.6 + 1.2 * fuerza)