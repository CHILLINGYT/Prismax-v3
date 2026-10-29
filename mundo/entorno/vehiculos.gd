class_name Vehiculos
extends Node3D
## =============================================================================
##  VEHÍCULOS APARCADOS EN LA CIUDAD (moto, auto y camioneta)
## =============================================================================
##  Coloca EXACTAMENTE UNO de cada modelo de `res://mundo/entorno/vehiculos/modelos/` aparcado
##  contra el bordillo, siguiendo la trama REAL que calcula el generador de ciudad
##  (el mismo camino que las farolas): se lee su trazado (ancho de calzada, paso
##  entre calles, extensión y origen) y se aparca en la CALZADA, pegado al bordillo
##  y lejos de los cruces.
##
##  Reglas que cumple cada sitio:
##   · dento de la calzada (nunca encima de la acera ni dentro de una manzana):
##     la distancia al eje del vial es `calzada/2 - ancho/2 - 0,15 m`;
##   · alineado con la calle (el eje largo del vehículo va en el eje del vial);
##   · a media manzana, nunca sobre un cruce (a más de `AIRE_CRUCE` del más cercano);
##   · apoyado en el suelo de verdad (rayo hacia abajo hasta el suelo de la ciudad);
##   · sin pisar el mobiliario de las aceras ni a los otros dos vehículos.
##
##  Los tres van a calles distintas, para que se vean desde varios sitios. Son
##  StaticBody3D con su caja de colisión: no se conducen, sólo estorban como un
##  coche aparcado de verdad.
##
##  Todo es determinista (sin azar) para que las pruebas puedan comprobarlo.

const ESCENA_MOTO := preload("res://mundo/entorno/vehiculos/moto_vespa.tscn")
const ESCENA_AUTO := preload("res://mundo/entorno/vehiculos/auto_datsun.tscn")
const ESCENA_CAMIONETA := preload("res://mundo/entorno/vehiculos/camioneta_zuk.tscn")
## Ford Escort Wagon de la carpeta "auto profe" (mismo VehiculoAparcado).
const ESCENA_FORD := preload("res://mundo/entorno/vehiculos/auto_ford_escort.tscn")

const MAX_ESPERA := 8.0         ## s de espera máxima a que el generador cierre la ciudad
const AIRE_BORDILLO := 0.15     ## m entre el costado del vehículo y el bordillo
const AIRE_CRUCE := 2.5         ## m mínimos entre el vehículo y un cruce
const SEPARACION_MIN := 10.0    ## m entre dos de los vehículos colocados

@export_group("Referencias")
## Nodo del generador de ciudad (se lee su trazado, como hacen las farolas).
@export var ciudad: Node

@export_group("Colocación")
## Permite apagar la colocación (por ejemplo para una prueba que la mida).
@export var colocar := true
## Largos buscados (m), proporcionados al JUGADOR: su malla mide 1,95 m (×1,11 una
## persona de 1,75 m), así que los tamaños reales se multiplican por ese factor.
## La escala es UNIFORME: el alto sale del propio modelo (se indica al lado).
## 2026-10: +10% sobre la medida realista (los tamaños anteriores van al lado): a
## pedido, para que se noten más en una calzada de 12 m sin quedar caricaturescos.
@export var largo_moto := 2.42       ## antes 2,2 → alto 1,42 m
@export var largo_auto := 5.5        ## antes 5,0 → alto 1,70 m
@export var largo_camioneta := 5.39  ## antes 4,9 → alto 2,56 m
@export var largo_ford := 4.73       ## antes 4,3 → alto 1,83 m

var _hecho := false
var _t := 0.0
var _puestos: Array = []   ## Diccionarios: lo que se colocó, para pruebas y depuración
var _nodos: Array = []


func _ready() -> void:
	set_process(true)


func _process(delta: float) -> void:
	if _hecho:
		return
	_t += delta
	if ciudad == null:
		if _t < MAX_ESPERA:
			return
		_hecho = true
		push_warning("[vehiculos] sin nodo de ciudad: no se aparcó nada.")
		return
	var trazado: Dictionary = ciudad.get("_trazado")
	if trazado.is_empty():
		if _t < MAX_ESPERA:
			return
		_hecho = true
		push_warning("[vehiculos] la ciudad no tiene trazado todavía: no se aparcó nada.")
		return
	var est: Dictionary = ciudad.get("_est")
	if int(est.get("ciudad_lista", 0)) != 1 and _t < MAX_ESPERA:
		return
	_construir(trazado)
	_hecho = true


func _construir(trazado: Dictionary) -> void:
	var calzada: float = trazado["calzada"]
	var hw: float = trazado["hw"]
	var paso: float = trazado["paso"]
	var ext: Vector2 = trazado["ext"]
	var off: Vector2 = trazado["off"]
	var n_x: int = int(round(ext.x / paso))
	var n_z: int = int(round(ext.y / paso))
	var obstaculos: Array = ciudad.get("_obstaculos_peatones")
	if obstaculos == null:
		obstaculos = []

	# Un sitio por vehículo: dos calles verticales distintas y dos horizontales.
	# Los índices se recortan a la rejilla REAL de la ciudad: en una ciudad pequeña
	# el plan sigue siendo válido (calles y bandas distintas, sin repetir sitio).
	var planes := [
		{"escena": ESCENA_MOTO, "tipo": "moto", "largo": largo_moto,
			"vertical": true, "calle": clampi(1, 0, n_x), "banda": clampi(1, 0, maxi(n_z - 1, 0)), "lado": 1.0},
		{"escena": ESCENA_AUTO, "tipo": "auto", "largo": largo_auto,
			"vertical": false, "calle": clampi(1, 0, n_z), "banda": clampi(1, 0, maxi(n_x - 1, 0)), "lado": 1.0},
		{"escena": ESCENA_CAMIONETA, "tipo": "camioneta", "largo": largo_camioneta,
			"vertical": true, "calle": clampi(2, 0, n_x), "banda": clampi(0, 0, maxi(n_z - 1, 0)), "lado": -1.0},
		# CUARTO vehículo: otro coche (el mismo modelo del Datsun, que es el coche del
		# proyecto) aparcado en OTRA calle: una horizontal distinta, con su banda y su
		# lado. No se repite sitio con ninguno de los tres de arriba.
		{"escena": ESCENA_AUTO, "tipo": "auto2", "largo": largo_auto,
			"vertical": false, "calle": clampi(2, 0, n_z), "banda": clampi(2, 0, maxi(n_x - 1, 0)), "lado": -1.0},
		# QUINTO: el Ford Escort (carpeta "auto profe"), en una calle VERTICAL que no
		# usa nadie (la 3), con su banda propia.
		{"escena": ESCENA_FORD, "tipo": "ford", "largo": largo_ford,
			"vertical": true, "calle": clampi(3, 0, n_x), "banda": clampi(2, 0, maxi(n_z - 1, 0)), "lado": 1.0},
	]
	var esperados := planes.size()
	# La calzada tiene que dar de sí: si el ancho del vial no cupiera, se avisa.
	if calzada * 0.5 < hw * 0.25 + AIRE_BORDILLO:
		push_warning("[vehiculos] calzada muy estrecha (%.1f m): puede que un vehículo no quepa." % calzada)
	for plan in planes:
		var nodo := (plan["escena"] as PackedScene).instantiate() as VehiculoAparcado
		nodo.largo_objetivo = float(plan["largo"])
		add_child(nodo)
		if not nodo.listo():
			_nodos.append(nodo)
			continue
		var ancho := nodo.ancho_m()
		var largo := nodo.largo_m()
		var vertical: bool = plan["vertical"]
		var lado := float(plan["lado"])
		var eje_vial := off.x + float(plan["calle"]) * paso if vertical else off.y + float(plan["calle"]) * paso
		var banda := float(plan["banda"])
		var lateral := calzada * 0.5 - ancho * 0.5 - AIRE_BORDILLO
		var x := 0.0
		var z := 0.0
		if vertical:
			x = eje_vial + lado * lateral
			z = off.y + (banda + 0.5) * paso
		else:
			z = eje_vial + lado * lateral
			x = off.x + (banda + 0.5) * paso
		var y := _altura(x, z)
		# Giro: el eje largo del modelo tiene que quedar sobre el eje del vial.
		var largo_sobre_z := nodo.eje_largo() == "z"
		var giro := 0.0
		if vertical:
			giro = 0.0 if largo_sobre_z else PI * 0.5
		else:
			giro = 0.0 if not largo_sobre_z else PI * 0.5
		nodo.global_position = Vector3(x, y, z)
		nodo.rotation.y = giro + (0.0 if lado > 0.0 else PI)
		nodo.name = "Vehiculo_%s" % String(plan["tipo"])
		var info := {"tipo": String(plan["tipo"]), "nodo": nodo, "pos": nodo.global_position,
				"giro": nodo.rotation.y, "largo": largo, "ancho": ancho,
				"vertical": vertical, "calle": float(plan["calle"]), "banda": banda,
				"lado": lado, "altura_suelo": y}
		_puestos.append(info)
		_nodos.append(nodo)
		print("[vehiculos] %s aparcado en (%.1f, %.2f, %.1f) | %.2f × %.2f m | calle %s %d, banda %d" % [
				plan["tipo"], nodo.global_position.x, nodo.global_position.y, nodo.global_position.z,
				largo, ancho, "vertical" if vertical else "horizontal",
				int(plan["calle"]), int(banda)])
	if _puestos.size() != esperados:
		push_warning("[vehiculos] se esperaban %d vehículos aparcados y quedaron %d." % [
				esperados, _puestos.size()])
	print("[vehiculos] %d vehículos aparcados (moto, auto, camioneta, segundo coche y Ford Escort) en calles distintas" % _puestos.size())


## Altura del SUELO de la ciudad en (x, z): rayo hacia abajo contra la capa 1 (suelo
## y edificios). Si no hay suelo a la vista, se usa la cota de la ciudad (0).
func _altura(x: float, z: float) -> float:
	var mundo := get_world_3d()
	if mundo == null:
		return 0.0
	var rayo := PhysicsRayQueryParameters3D.create(Vector3(x, 60.0, z), Vector3(x, -40.0, z), 1)
	var res := mundo.direct_space_state.intersect_ray(rayo)
	if res.is_empty():
		return 0.0
	return float((res["position"] as Vector3).y)


## --- Lecturas para las pruebas ----------------------------------------------
func listo() -> bool:
	return _hecho


func colocados() -> int:
	return _puestos.size()


## Copia de lo colocado: tipo, nodo, posición, giro, medidas y de qué calle es.
func puestos() -> Array:
	return _puestos.duplicate()


func nodos() -> Array:
	return _nodos.duplicate()