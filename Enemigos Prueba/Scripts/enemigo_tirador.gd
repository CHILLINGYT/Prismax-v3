class_name EnemigoTirador
# Se extiende por RUTA a propósito: no depende de la caché de clases global del
# editor (el mismo motivo por el que el gerente resuelve su enemigo con preload).
extends "res://Enemigos Prueba/Scripts/base/enemigo_base.gd"

## Enemigo tirador con esqueleto: mantiene una DISTANCIA PREFERIDA configurable
## al jugador (avanza si está lejos, retrocede si está demasiado cerca), se
## reposiciona y dispara proyectiles pequeños, rápidos y configurables.
##
## No usa el anillo de cerco del CombatFormation (ese queda a 2.5 m, demasiado
## cerca para un tirador): gestiona su propia distancia. Sí se registra en el
## CombatManager para que el FreeFlow del jugador pueda seleccionarlo.
##
## Todo el contrato de daño/registro/barra/animation viene de EnemigoBase.

const ESCENA_PROYECTIL := preload("res://Enemigos Prueba/Scenes/proyectil_enemigo.tscn")

@export_group("Distancia")
## Distancia (m) a la que intenta quedarse del jugador (rango útil 8-12 m).
@export var distancia_preferida: float = 10.0
## Banda de tolerancia (m): dentro de [pref - margen, pref + margen] sólo se
## recoloca lateralmente y dispara.
@export var margen: float = 1.5
## Velocidad (m/s) al retroceder si el jugador se acerca demasiado.
@export var velocidad_retroceso: float = 2.6

@export_group("Disparo")
## Segundos entre disparos.
@export var cadencia_disparo: float = 1.6
## Fracción del clip "disparar" que transcurre antes de soltar el proyectil.
@export var fraccion_apuntar: float = 0.5
## Altura (m) de la boca del arma sobre la base del enemigo.
@export var altura_boca: float = 1.2
## Velocidad (m/s) del proyectil.
@export var velocidad_proyectil: float = 26.0
## Daño de cada proyectil (por EstadisticasJugador.recibir_danio).
@export var dano_proyectil: float = 8.0
## Radio (m) de colisión del proyectil (y tamaño de la bola visible con escala 1).
@export var radio_proyectil: float = 0.14
## Dispersión aleatoria (grados) al disparar.
@export var dispersion_grados: float = 2.5
## Distancia (m) máxima a la que dispara.
@export var alcance_disparo: float = 22.0

var _t_disparo: float = 0.0
var _disparo_hecho: bool = false
var _t_resto: float = 0.0
## Lado hacia el que se desplaza para buscar línea de visión (-1/1).
var _lado_lateral: float = 1.0
## Marcador "BocaArma" del arma anclada a la mano derecha (si la lleva).
var _boca_marcador: Node3D = null
var _boca_buscada: bool = false
## Arma anclada a la mano (nodo "ArmaTirador") y si ya se buscó: la usa el disparo
## para pedirle sus efectos (sonido + fogonazo).
var _arma: Node = null
var _arma_buscada: bool = false

func _ready() -> void:
	super()
	# Desfase inicial: varios tiradores no disparan todos en el mismo fotograma.
	_t_disparo = randf_range(0.6, 1.4)
	_lado_lateral = 1.0 if randf() < 0.5 else -1.0

func _pensar(delta: float, jugador: Node3D, stats: EstadisticasJugador, jugador_vivo: bool) -> void:
	match _estado:
		Estado.ATACAR:
			_fase_disparar(delta, jugador, stats, jugador_vivo)
		Estado.RECUPERAR:
			_fase_recuperar(delta)
		_:
			_fase_reposicionar(delta, jugador, jugador_vivo)

# =============================================================== Reposicionamiento
func _fase_reposicionar(delta: float, jugador: Node3D, jugador_vivo: bool) -> void:
	var distancia := _distancia_plana(jugador)
	var hacia := _dir_plano_hacia(jugador)
	var en_alcance := distancia <= alcance_disparo
	var ve := en_alcance and _con_linea_de_vision(jugador, altura_boca)
	var dir := Vector3.ZERO
	var vel := _velocidad_propia

	if distancia > distancia_preferida + margen:
		# Demasiado LEJOS: se acerca (bordeando obstáculos) hasta recuperar alcance.
		dir = hacia
	elif distancia < distancia_preferida - margen:
		# Demasiado CERCA: retrocede mirando al jugador.
		dir = -hacia
		vel = velocidad_retroceso
	elif not ve:
		# En la banda correcta pero SIN línea de visión: se desplaza de lado a
		# buscar el hueco que le permita disparar (no empuja contra el muro).
		dir = _dir_lateral(jugador)

	if dir.length_squared() > 0.0001:
		dir = _dir_con_esquiva(delta, dir)
	dir = _con_separacion(dir)
	_fisica(delta, dir, vel)

	_t_disparo = maxf(0.0, _t_disparo - delta)
	# Sólo dispara con el objetivo vivo, en alcance, VISIBLE y dentro del arco.
	if jugador_vivo and _t_disparo <= 0.0 and ve and _en_arco(jugador, -0.25):
		_iniciar_disparo()

## Desplazamiento lateral (perpendicular al jugador) para buscar línea de visión.
## Si el lado elegido está tapado, cambia al otro: nunca se queda empujando contra
## el mismo muro, y mantener el lado evita que oscile de un lado a otro.
func _dir_lateral(jugador: Node3D) -> Vector3:
	var hacia := _dir_plano_hacia(jugador)
	if hacia.length_squared() <= 0.0001:
		return Vector3.ZERO
	var perp := Vector3(-hacia.z, 0.0, hacia.x).normalized()
	var desde := global_position + Vector3.UP * altura_pecho
	if not _rayo_libre(desde, desde + perp * _lado_lateral * sonda_esquiva):
		_lado_lateral = -_lado_lateral
	return perp * _lado_lateral

# =============================================================== Disparo
func _iniciar_disparo() -> void:
	_estado = Estado.ATACAR
	_disparo_hecho = false
	var clip: StringName = &"disparar"
	_animar_una_vez(clip)
	var dur := _duracion_clip(clip)
	_t_fase = maxf(0.08, dur * fraccion_apuntar)
	_t_resto = maxf(0.05, dur - _t_fase)
	_registrar_amenaza(cadencia_disparo, "ranged")

func _fase_disparar(delta: float, jugador: Node3D, stats: EstadisticasJugador, jugador_vivo: bool) -> void:
	# Se detiene para apuntar y disparar.
	_fisica(delta, Vector3.ZERO, 0.0)
	_t_fase -= delta
	if not _disparo_hecho and _t_fase <= 0.0:
		_disparo_hecho = true
		_t_fase = _t_resto
		if jugador_vivo and stats != null:
			_disparar(jugador)
		return
	if _t_fase <= 0.0:
		_limpiar_amenaza()
		_estado = Estado.RECUPERAR
		_t_fase = 0.25

func _fase_recuperar(delta: float) -> void:
	_fisica(delta, Vector3.ZERO, 0.0)
	_t_fase -= delta
	if _t_fase <= 0.0:
		_t_disparo = cadencia_disparo * randf_range(0.9, 1.15)
		_estado = Estado.CERCO

## Crea el proyectil en la boca del arma y lo lanza hacia el pecho del jugador.
func _disparar(jugador: Node3D) -> void:
	# EFECTOS DEL DISPARO REAL (Tarea 3): sonido del arma + fogonazo, UNA vez por
	# disparo, antes de lanzar el proyectil. Van aquí porque este es el ÚNICO punto
	# del enemigo en el que un disparo ocurre de verdad (el fotograma de impacto del
	# clip "disparar"): no hay ningún otro sitio desde el que puedan duplicarse.
	_efectos_del_arma()
	if ESCENA_PROYECTIL == null or not is_inside_tree():
		return
	var padre := get_parent()
	if padre == null:
		return
	var boca := _boca_del_arma()
	var objetivo := jugador.global_position + Vector3.UP * 1.0
	var dir := objetivo - boca
	if dir.length_squared() < 0.0001:
		dir = -global_transform.basis.z
	dir = dir.normalized()
	# Dispersión: gira levemente la dirección alrededor del eje vertical.
	var ang := deg_to_rad(randf_range(-dispersion_grados, dispersion_grados))
	dir = dir.rotated(Vector3.UP, ang)

	var p := ESCENA_PROYECTIL.instantiate()
	if p == null:
		return
	# Los parámetros se fijan ANTES de add_child: el _ready() del proyectil ya
	# construye su bola de colisión y su tamaño visible con estos valores.
	if "radio" in p:
		p.set("radio", radio_proyectil)
	if "velocidad" in p:
		p.set("velocidad", velocidad_proyectil)
	if "dano" in p:
		p.set("dano", dano_proyectil)
	padre.add_child(p)
	# Llamada duck-typed: no depende de la clase global del proyectil.
	if p.has_method("lanzar"):
		p.call("lanzar", boca, dir, self, velocidad_proyectil, dano_proyectil)
	else:
		p.queue_free()

## Pide al ARMA anclada a la mano sus efectos de disparo (sonido + fogonazo).
## El arma se busca UNA vez por nombre de nodo ("ArmaTirador") y se comprueba que
## exponga la API: si no la expone (p. ej. el arma provisional de cajas), el disparo
## sigue funcionando exactamente igual y sin errores.
func _efectos_del_arma() -> void:
	if not _arma_buscada:
		_arma_buscada = true
		_arma = find_child("ArmaTirador", true, false)
	if _arma != null and is_instance_valid(_arma) and _arma.has_method("disparar_efectos"):
		_arma.call("disparar_efectos")


## Origen real del disparo: la boca del cañón (Marker3D "BocaArma" del arma
## anclada a la mano derecha) si el tirador lleva arma; si no, el origen de
## siempre sobre el pecho. Se busca una sola vez y se recuerda.
func _boca_del_arma() -> Vector3:
	if not _boca_buscada:
		_boca_buscada = true
		_boca_marcador = find_child("BocaArma", true, false) as Node3D
	if _boca_marcador != null and is_instance_valid(_boca_marcador):
		return _boca_marcador.global_position
	return global_position + Vector3.UP * altura_boca + (-global_transform.basis.z) * 0.5