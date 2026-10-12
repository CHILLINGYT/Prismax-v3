class_name VueloDano
extends RefCounted

## Puente de daño compartido del personaje VUELO (águila).
##
## Problema real que resuelve: los ataques del águila (combate terrestre,
## plumas, palmazo) sólo conocían el contrato de los maniquíes de práctica
## HARPY (`recibir_golpe` + grupo "maniqui"), así que los enemigos reales del
## proyecto (enemigo_base: `take_hit`/`apply_damage`/`take_damage`, grupo
## "damageable", capa de física 16) eran inmunes aunque el golpe los rozara.
##
## Reglas (estrictas, sin fuego amigo):
##  - sólo se daña a nodos con ALGÚN contrato de daño real y VIVOS;
##  - `recibir_golpe` (maniquíes) se llama igual que antes (mismo contrato);
##  - enemigos del proyecto usan el MISMO orden de la cadena Free Flow que
##    usa el resto del juego: take_hit -> apply_damage -> take_damage;
##  - el jugador, aliados y peatones no implementan esos métodos: nunca
##    reciben daño de este puente.

## ¿Puede este nodo recibir daño de un ataque de combate?
static func aplicable(nodo: Object) -> bool:
	if not (nodo is Node3D):
		return false
	var n := nodo as Node3D
	if not n.is_inside_tree():
		return false
	if n.has_method("recibir_golpe"):
		return true
	if n.has_method("is_alive") and not bool(n.call("is_alive")):
		return false
	return (
		n.has_method("take_hit")
		or n.has_method("apply_damage")
		or n.has_method("take_damage")
	)


## Aplica daño al nodo por el contrato que implemente. `dir` es la dirección
## atacante -> objetivo (unitaria); `empuje` la fuerza del empujón/km.
## Devuelve true si el golpe conectó de verdad.
static func aplicar(
	nodo: Object,
	danio: float,
	dir: Vector3,
	empuje: float = 0.0,
	aturdimiento: float = 0.0
) -> bool:
	var n := nodo as Node3D
	if n == null or danio <= 0.0 or not n.is_inside_tree():
		return false
	var dir_u := dir.normalized() if dir.length_squared() > 0.0001 else Vector3.FORWARD

	# 1) Maniquíes de práctica HARPY: mismo contrato que ya usaban los ataques.
	if n.has_method("recibir_golpe"):
		n.call("recibir_golpe", danio, dir_u, empuje)
		return true

	# 2) Enemigos reales del proyecto: cadena Free Flow del propio enemigo.
	if n.has_method("is_alive") and not bool(n.call("is_alive")):
		return false
	var desde := n.global_position - dir_u
	if n.has_method("take_hit"):
		n.call("take_hit", danio, dir_u, empuje, aturdimiento)
		return true
	if n.has_method("apply_damage"):
		n.call("apply_damage", danio, desde, &"melee")
		return true
	if n.has_method("take_damage"):
		n.call("take_damage", danio, desde, dir_u * empuje + Vector3.UP * empuje * 0.2)
		return true
	return false