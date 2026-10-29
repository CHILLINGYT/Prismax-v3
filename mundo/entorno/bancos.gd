class_name Bancos
extends Object
## =============================================================================
##  BANCOS URBANOS DE LAS PLAZAS Y PARQUES
## =============================================================================
##  Banco de calle clásico pero de línea moderna: asiento y respaldo de listones
##  de madera sobre una estructura de acero negro — los mismos materiales que
##  las farolas de la ciudad (world/farolas.gd), para que el mobiliario se vea
##  de una sola familia.
##
##  La geometría se construye UNA vez por llamada con SurfaceTool (cajas y
##  listones; ni un solo cubo de relleno) y se reutiliza para todos los bancos
##  de la ciudad: el generador de ciudad (generador_ciudad.gd) coloca cada
##  banco con Bancos.colocar() dentro de sus parques y solares.
##
##  El banco mira hacia -Z (como la convención de piezas del kit): la persona
##  sentada da la espalda a +Z.  Base del modelo: y = 0 = suelo.
##
##  Colisión: cuerpo estático con DOS cajas envolventes (asiento y respaldo),
##  baratas y suficientes para que el personaje no lo atraviese.
## =============================================================================

# --- Medidas (m) --------------------------------------------------------------
const LARGO := 1.94        ## largo total de la estructura
const ALTO_ASIENTO := 0.465
const ALTO_RESPALDO := 0.89
const PATAS_X := 0.90      ## separación de las patas al eje central

# --- Materiales compartidos (se crean una sola vez) ---------------------------
static var _mat_madera: StandardMaterial3D
static var _mat_metal: StandardMaterial3D


static func material_madera() -> StandardMaterial3D:
	if _mat_madera == null:
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.31, 0.20, 0.11)   # nogal oscuro
		m.roughness = 0.78
		m.metallic = 0.0
		_mat_madera = m
	return _mat_madera


static func material_metal() -> StandardMaterial3D:
	if _mat_metal == null:
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.16, 0.17, 0.18)   # el mismo acero que las farolas
		m.metallic = 0.55
		m.roughness = 0.55
		_mat_metal = m
	return _mat_metal


## Coloca un banco completo (malla + colisión) bajo `padre` con la transformada
## dada. Devuelve el StaticBody3D creado (para marcar owner en el editor).
static func colocar(padre: Node3D, xf: Transform3D) -> StaticBody3D:
	var cuerpo := StaticBody3D.new()
	cuerpo.name = "Banco"
	cuerpo.transform = xf

	var metal := MeshInstance3D.new()
	metal.name = "BancoMetal"
	metal.mesh = _malla_metal()
	metal.material_override = material_metal()
	cuerpo.add_child(metal)

	var madera := MeshInstance3D.new()
	madera.name = "BancoMadera"
	madera.mesh = _malla_madera()
	madera.material_override = material_madera()
	cuerpo.add_child(madera)

	# Colisión: dos cajas envolventes (asiento/patas y respaldo).
	var forma_a := CollisionShape3D.new()
	var caja_a := BoxShape3D.new()
	caja_a.size = Vector3(1.96, 0.50, 0.62)
	forma_a.shape = caja_a
	forma_a.position = Vector3(0.0, 0.25, 0.0)
	cuerpo.add_child(forma_a)

	var forma_b := CollisionShape3D.new()
	var caja_b := BoxShape3D.new()
	caja_b.size = Vector3(1.96, 0.48, 0.12)
	forma_b.shape = caja_b
	forma_b.position = Vector3(0.0, 0.64, 0.34)
	cuerpo.add_child(forma_b)

	padre.add_child(cuerpo)
	return cuerpo


## Estructura de acero: patas laterales, zapatas, travesaño bajo y montantes
## del respaldo. Local: el frente mira a -Z.
static func _malla_metal() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for s: float in [-1.0, 1.0]:
		# Zapata y pata lateral.
		_poner(st, Vector3(0.18, 0.05, 0.58), Transform3D(Basis(), Vector3(s * PATAS_X, 0.025, 0.0)))
		_poner(st, Vector3(0.07, 0.42, 0.54), Transform3D(Basis(), Vector3(s * PATAS_X, 0.26, 0.0)))
		# Montante del respaldo, tumbado hacia atrás 14°.
		var incl := Basis(Vector3.RIGHT, deg_to_rad(14.0))
		var medio := incl * Vector3(0.0, 0.21, 0.0)
		_poner(st, Vector3(0.07, 0.44, 0.05), Transform3D(incl, Vector3(s * PATAS_X, 0.44, 0.22) + medio))
	# Travesaño central bajo el asiento.
	_poner(st, Vector3(1.73, 0.06, 0.06), Transform3D(Basis(), Vector3(0.0, 0.15, 0.0)))
	st.generate_tangents()
	return st.commit()


## Listones de madera: cuatro en el asiento y tres en el respaldo.
static func _malla_madera() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Asiento: listones a lo largo, de delante hacia atrás.
	for i in 4:
		var z := -0.2025 + 0.135 * float(i)
		_poner(st, Vector3(1.80, 0.045, 0.105), Transform3D(Basis(), Vector3(0.0, ALTO_ASIENTO - 0.0225, z)))
	# Respaldo: listones inclinados con el montante.
	var incl := Basis(Vector3.RIGHT, deg_to_rad(14.0))
	for i in 3:
		var y := ALTO_ASIENTO + 0.10 + 0.14 * float(i)
		var z := 0.225 + (y - 0.44) * 0.249
		_poner(st, Vector3(1.80, 0.095, 0.032), Transform3D(incl, Vector3(0.0, y, z)))
	st.generate_tangents()
	return st.commit()


## Añade una caja como superficie 0 de la malla en construcción.
static func _poner(st: SurfaceTool, tam: Vector3, xf: Transform3D) -> void:
	st.append_from(_caja(tam), 0, xf)


static func _caja(tam: Vector3) -> BoxMesh:
	var c := BoxMesh.new()
	c.size = tam
	return c