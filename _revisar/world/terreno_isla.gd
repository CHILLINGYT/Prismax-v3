class_name TerrenoIsla
extends Node3D
## =============================================================================
##  MALLA Y COLISIÓN DE LA ISLA
## =============================================================================
##  Construye, a partir de la matemática compartida de [Relieve]:
##    * una malla POLAR (densa cerca de la isla, gruesa lejos) con normales
##      calculadas de la propia rejilla,
##    * una colisión trimesh decimada para que el jugador camine por todo el
##      terreno (ciudad, bosque, playa y fondo marino).
##
##  Se construye en tiempo de ejecución y NO se guarda en el .tscn: así el
##  archivo de la escena sigue siendo liviano y el editor no se ralentiza.
## =============================================================================

## Número de anillos (radios) de la rejilla polar.
@export var anillos: int = 180
## Número de divisiones angulares.
@export var divisiones: int = 448
## Radio exterior de la malla (m). Más allá sólo queda mar.
@export var radio_max: float = 3200.0
## Hasta este radio los anillos son de paso constante y fino.
@export var radio_denso: float = 900.0
## Fracción de anillos dedicada a la zona densa.
@export var fraccion_densa: float = 0.78
## Material del terreno.
@export var material_terreno: Material
## Crear también la colisión trimesh (sólo en tiempo de ejecución).
@export var construir_colision: bool = true
## Cada cuántos vértices se decima la colisión (2 = mitad de resolución).
@export var paso_colision: int = 2

var _relieve: Relieve


func _ready() -> void:
	_relieve = Relieve.new()
	var t0 := Time.get_ticks_msec()
	var malla := _construir_malla()
	var vista := MeshInstance3D.new()
	vista.name = "Malla"
	vista.mesh = malla
	vista.material_override = material_terreno
	# El terreno no proyecta sombra: es una superficie enorme y sin ello se
	# evitan bandas de sombra propias y se ahorra rellenado lejano.
	vista.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(vista)
	var caras := 0
	if construir_colision:
		var forma := _construir_colision()
		caras = int(float(forma.get_faces().size()) / 3.0)
		var cuerpo := StaticBody3D.new()
		cuerpo.name = "Colision"
		var colisionador := CollisionShape3D.new()
		colisionador.name = "Forma"
		colisionador.shape = forma
		cuerpo.add_child(colisionador)
		add_child(cuerpo)
	print("[Isla] terreno listo: %d vértices visibles, %d caras de colisión, %d ms" % [
			(malla.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(),
			caras, Time.get_ticks_msec() - t0])


# --- Construcción -------------------------------------------------------------

func _construir_malla() -> ArrayMesh:
	var pts := _rejilla(anillos, divisiones)
	var nor := _normales(pts, anillos, divisiones)
	var idx := _indices(anillos, divisiones)
	var matrices: Array = []
	matrices.resize(Mesh.ARRAY_MAX)
	matrices[Mesh.ARRAY_VERTEX] = pts
	matrices[Mesh.ARRAY_NORMAL] = nor
	matrices[Mesh.ARRAY_INDEX] = idx
	var malla := ArrayMesh.new()
	malla.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, matrices)
	return malla


func _construir_colision() -> ConcavePolygonShape3D:
	# La colisión conserva TODA la resolución radial de la malla visible (es la
	# que domina el error en las cuestas) y sólo reduce la angular, donde se nota
	# mucho menos. Así la superficie que pisa el personaje coincide con la que se
	# ve (la diferencia baja de 26 cm a menos de 10 cm en las pendientes fuertes).
	var n_anillos := maxi(anillos, 8)
	var n_div := maxi(floori(float(divisiones) / float(paso_colision)), 8)
	var pts := _rejilla(n_anillos, n_div)
	var idx := _indices(n_anillos, n_div)
	var caras := PackedVector3Array()
	caras.resize(idx.size())
	for t in range(idx.size()):
		caras[t] = pts[idx[t]]
	var forma := ConcavePolygonShape3D.new()
	forma.set_faces(caras)
	forma.backface_collision = true
	return forma


# --- Rejilla polar ------------------------------------------------------------

## Radio del anillo [param i] de [param n]: constante y fino hasta radio_denso y
## luego creciente (exponencial) hasta radio_max.
func _radio_de(i: int, n: int) -> float:
	var n_denso := maxi(int(round(float(n) * fraccion_densa)), 1)
	if i <= n_denso:
		return radio_denso * float(i) / float(n_denso)
	var k := float(i - n_denso) / float(maxi(n - n_denso, 1))
	return radio_denso * pow(radio_max / radio_denso, k)


## Posiciones de la rejilla polar, indexadas [i * divisiones + j].
func _rejilla(n_anillos: int, n_div: int) -> PackedVector3Array:
	var pts := PackedVector3Array()
	pts.resize((n_anillos + 1) * n_div)
	for i in range(n_anillos + 1):
		var r := _radio_de(i, n_anillos)
		for j in range(n_div):
			var a := TAU * float(j) / float(n_div)
			var x := Relieve.CENTRO.x + r * cos(a)
			var z := Relieve.CENTRO.y + r * sin(a)
			pts[i * n_div + j] = Vector3(x, _relieve.altura(x, z), z)
	return pts


## Normales por vértice a partir de los vecinos de la rejilla. El producto
## t_theta x t_radio apunta hacia arriba en todo el relieve.
func _normales(pts: PackedVector3Array, n_anillos: int, n_div: int) -> PackedVector3Array:
	var nor := PackedVector3Array()
	nor.resize(pts.size())
	for i in range(n_anillos + 1):
		var fila := i * n_div
		# En el anillo central (i = 0) todos los puntos coinciden: se usa el
		# anillo 1 para medir el giro tangencial.
		var fila_t := (1 if i == 0 else i) * n_div
		var im := maxi(i - 1, 0)
		var ip := mini(i + 1, n_anillos)
		for j in range(n_div):
			var jm := (j - 1 + n_div) % n_div
			var jp := (j + 1) % n_div
			var t_theta := pts[fila_t + jp] - pts[fila_t + jm]
			var t_radio := pts[ip * n_div + j] - pts[im * n_div + j]
			var n := t_theta.cross(t_radio)
			if n.length_squared() < 0.0000001:
				n = Vector3.UP
			nor[fila + j] = n.normalized()
	return nor


## Triángulos de la rejilla (dos por cuadrante). El orden A-C-B / A-D-C deja
## las caras mirando hacia arriba según la convención de Godot.
func _indices(n_anillos: int, n_div: int) -> PackedInt32Array:
	var idx := PackedInt32Array()
	idx.resize(n_anillos * n_div * 6)
	var k := 0
	for i in range(n_anillos):
		for j in range(n_div):
			var jp := (j + 1) % n_div
			var a := i * n_div + j
			var b := i * n_div + jp
			var c := (i + 1) * n_div + jp
			var d := (i + 1) * n_div + j
			idx[k] = a
			idx[k + 1] = c
			idx[k + 2] = b
			idx[k + 3] = a
			idx[k + 4] = d
			idx[k + 5] = c
			k += 6
	return idx