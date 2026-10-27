class_name VehiculoAparcado
extends StaticBody3D
## =============================================================================
##  VEHÍCULO APARCADO (ajuste del modelo importado + caja de colisión)
## =============================================================================
##  Los tres modelos de `res://modelos 3d autos/` vienen de fuera con tamaños y
##  orígenes MUY distintos: uno mide 1,35 m y otro 4,75 m, y sus vértices no están
##  centrados (el del Datsun, por ejemplo, trae nodos a más de 10 m del origen).
##  Aquí se hace siempre lo mismo, sobre el nodo que envuelve al modelo:
##
##   1. se mide la CAJA REAL de la MALLA (sólo MeshInstance3D, componiendo la
##      jerarquía del GLB: se ignoran luces y cámaras, que descolocaban la caja);
##   2. se escala a la LONGITUD pedida con UN solo factor uniforme (un vehículo no
##      se estira: si se escalara por ejes dejaría de parecer un vehículo);
##   3. se centra en planta y se apoya en el suelo (la base queda en y = 0, que es
##      la cota de la calzada);
##   4. se le añade la caja de colisión de la física que ya usa el mundo
##      (StaticBody3D + CollisionShape3D con BoxShape3D), del tamaño real del
##      vehículo ya ajustado, en la capa 1 (el suelo y los edificios).
##
##  No hay conducción: son cuerpos estáticos aparcados, como una farola.

## Longitud (m) que debe medir el eje MAYOR del vehículo ya escalado.
@export var largo_objetivo := 4.7
## Alto (m) de la caja de colisión. Negativo = el alto real de la malla.
@export var alto_colision := -1.0

var _modelo: Node3D
var _largo := 0.0        ## longitud del modelo ya ajustado (m)
var _ancho := 0.0        ## anchura del modelo ya ajustado (m), perpendicular
var _alto := 0.0         ## altura del modelo ya ajustado (m)
var _eje := "z"          ## eje sobre el que corre la longitud: "z" o "x"
var _listo := false


func _ready() -> void:
	_modelo = get_node_or_null("Modelo") as Node3D
	if _modelo == null:
		push_warning("[vehiculo] '%s' no tiene nodo Modelo: queda sin ajustar." % name)
		return
	var caja := _caja_de_malla(_modelo, _modelo.transform)
	if caja.size.length() < 0.0001:
		push_warning("[vehiculo] '%s': la malla del modelo está vacía." % name)
		return
	var tam := caja.size
	_eje = "z" if tam.z >= tam.x else "x"
	var escala := largo_objetivo / maxf(tam.x, tam.z)
	# Un solo factor para los tres ejes + centrado en planta + base en y = 0.
	var centro := caja.position + tam * 0.5
	_modelo.scale = Vector3.ONE * escala
	_modelo.position = Vector3(-centro.x * escala, -caja.position.y * escala, -centro.z * escala)
	_largo = maxf(tam.x, tam.z) * escala
	_ancho = minf(tam.x, tam.z) * escala
	_alto = tam.y * escala
	# Caja de colisión: la física de siempre, con el bulto real del vehículo.
	var alto := alto_colision if alto_colision > 0.0 else _alto
	var forma := CollisionShape3D.new()
	forma.name = "Colision"
	var caja_col := BoxShape3D.new()
	caja_col.size = Vector3(_largo if _eje == "x" else _ancho, alto, _ancho if _eje == "x" else _largo)
	forma.shape = caja_col
	forma.position = Vector3(0.0, alto * 0.5, 0.0)
	add_child(forma)
	collision_layer = 1
	collision_mask = 0
	_listo = true


## Caja envolvente de la MALLA del modelo, en el espacio del nodo que lo envuelve.
## Recorre la jerarquía componiendo transformadas y sólo cuenta MeshInstance3D.
func _caja_de_malla(nodo: Node, t: Transform3D) -> AABB:
	var caja := AABB()
	var primero := true
	if nodo is MeshInstance3D:
		var mi := nodo as MeshInstance3D
		if mi.mesh != null:
			caja = _transformar_aabb(mi.get_aabb(), t)
			primero = false
	for c in nodo.get_children():
		var hijo := c as Node3D
		if hijo == null:
			continue
		var caja_hijo := _caja_de_malla(hijo, t * hijo.transform)
		if caja_hijo.size.length() < 0.0001:
			continue
		caja = caja_hijo if primero else caja.merge(caja_hijo)
		primero = false
	return caja


## AABB de una caja propia transformada por t (las 8 esquinas, reencuadradas).
func _transformar_aabb(caja: AABB, t: Transform3D) -> AABB:
	var resultado := AABB(t * caja.position, Vector3.ZERO)
	var dentro := true
	for i in range(8):
		var esquina := caja.get_endpoint(i)
		var p := t * esquina
		if dentro:
			resultado = AABB(p, Vector3.ZERO)
			dentro = false
		else:
			resultado = resultado.expand(p)
	return resultado


## --- Lecturas para el colocador y las pruebas --------------------------------
func listo() -> bool:
	return _listo


func largo_m() -> float:
	return _largo


func ancho_m() -> float:
	return _ancho


func alto_m() -> float:
	return _alto


## Eje del modelo sobre el que corre la longitud: "z" o "x".
func eje_largo() -> String:
	return _eje