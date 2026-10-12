class_name NPCCitizenModel

## Ensamblador de ciudadanos con las piezas de los packs "PolyMate" (City Folks + Urban Man).
##
## Los cuatro personajes nuevos vienen con las mallas YA separadas por pieza (1-Head, 2-Torso,
## 3-Hands, 4-Legs, 5-Feet) y todos comparten el mismo rig de Auto-Rig Pro de 59 huesos, así que
## se pueden mezclar entre ellos: cabeza de uno, torso de otro, piernas de otro... De ahí sale la
## variedad de cuerpos y de ropa sin repetir el mismo modelo entero.
##
## Dos cosas medidas que hay que respetar:
##  - "Muscle Man" trae los MISMOS 59 huesos pero en OTRO ORDEN, así que a las mallas hay que
##    reasignarles los huesos por NOMBRE, nunca por índice.
##  - Estos modelos vienen en centésimas de metro y la escala real (0,01) vive en la cadena de
##    nodos por encima del esqueleto: al mover el esqueleto hay que conservar esa escala global.

## Modelo base del ensamblaje: aporta el esqueleto (y su escala). Es el mismo contra el que se
## hornearon las animaciones del rig nuevo.
const BASE_MODEL := "res://Assets NPCS/UrbanMan_PolyMate_alstrainfinite/GLB/UrbanMan_CityFolks_PolyMate.glb"

const DIR_CITY := "res://Assets NPCS/CityFolks_PolyMate_alstrainfinite/GLB/"
const DIR_URBAN := "res://Assets NPCS/UrbanMan_PolyMate_alstrainfinite/GLB/"

## Piezas sortables por hueco del cuerpo. Los cuatro personajes comparten el mismo rig de 59 huesos
## y la misma pose de reposo (medido: peor error 0,056), así que se pueden mezclar entre ellos y de
## ahí sale la variedad de cuerpos, caras y ropa.
##
## Cada pieza lleva lo que se MIDIÓ de su textura, muestreándola en las UV reales de la malla (no
## en el atlas entero, que está casi vacío y engaña):
##
##   "cap" = hasta dónde se puede recolorear la prenda (0 = nada). Si la pieza incluye piel, teñirla
##           entera teñiría la piel: el torso de tirantes de Muscle Man es 57% piel (no se toca), el
##           torso de Deportista 3% y el de Dough Sensei 23% (se recolorean poco).
##   "ref" = luminancia media de la prenda (medida, en sRGB), para que el color nuevo salga con su
##           brillo real: una tela oscura se recolorea igual de viva que una clara.
##
## "Dough Sensei" no entra por la CABEZA: su "cabeza" es una caja con un logotipo pintado (se vio al
## poner los modelos en fila y mirarlos de cerca). Sí entran su torso (con delantal, se añade sólo
## con él), sus piernas, sus manos y sus pies: como la cabeza se elige aparte, sale un ciudadano con
## delantal —un cocinero— con cara normal, que es perfectamente creíble.
const PARTS := {
	"head": [
		{"path": DIR_URBAN + "1-Head_MV1.glb"},
		{"path": DIR_CITY + "Deportista/1-Head_Deportista.glb"},
		{"path": DIR_CITY + "Muscle Man/1-Head_MuscleMan.glb"},
	],
	"torso": [
		{"path": DIR_URBAN + "2-Torso_HoodieV1_Down.glb", "cap": 0.9, "ref": 0.33},
		{"path": DIR_URBAN + "2-Torso_HoodieV1_Up.glb", "cap": 0.9, "ref": 0.33},
		{"path": DIR_CITY + "Deportista/2-Torso_Deportista.glb", "cap": 0.6, "ref": 0.41},
		{"path": DIR_CITY + "Muscle Man/2-Torso_MuscleMan.glb", "cap": 0.0},
		{"path": DIR_CITY + "Dough Sensei/2-Torso_DoughSenseiV1.glb", "cap": 0.45, "ref": 0.20},
	],
	"hands": [
		{"path": DIR_URBAN + "3-Hands_MV1.glb"},
		{"path": DIR_CITY + "Deportista/3-Hands_Deportista.glb"},
		{"path": DIR_CITY + "Muscle Man/3-Hands_MuscleMan.glb"},
		{"path": DIR_CITY + "Dough Sensei/3-Hands_DoughSenseiV1.glb"},
	],
	"legs": [
		{"path": DIR_URBAN + "4-Legs_CargoV1.glb", "cap": 0.9, "ref": 0.23},
		{"path": DIR_CITY + "Deportista/4-Legs_Deportista.glb", "cap": 0.9, "ref": 0.51},
		{"path": DIR_CITY + "Muscle Man/4-Legs_MuscleMan.glb", "cap": 0.9, "ref": 0.17},
		{"path": DIR_CITY + "Dough Sensei/4-Legs_DoughSenseiV1.glb", "cap": 0.9, "ref": 0.15},
	],
	"feet": [
		{"path": DIR_URBAN + "5-Feet_ShoesV1.glb", "cap": 0.85, "ref": 0.36},
		{"path": DIR_CITY + "Deportista/5-Feet_Deportista.glb", "cap": 0.85, "ref": 0.30},
		{"path": DIR_CITY + "Muscle Man/5-Feet_MuscleMan.glb", "cap": 0.85, "ref": 0.75},
		{"path": DIR_CITY + "Dough Sensei/5-Feet_DoughSenseiV1.glb", "cap": 0.85, "ref": 0.30},
	],
}

## Delantal de Dough Sensei (la única prenda extra que traen los paquetes): se añade SÓLO cuando el
## torso elegido es el suyo, porque sobre otro torso quedaría atravesado.
const APRON := {"path": DIR_CITY + "Dough Sensei/2-Torso_DoughSenseiV1_Apron.glb", "cap": 0.0}
const DOUGH_TORSO := DIR_CITY + "Dough Sensei/2-Torso_DoughSenseiV1.glb"

## Shader que recolorea las prendas (ver el propio archivo para el porqué).
const OUTFIT_SHADER := "res://NPCs/Shaders/npc_outfit.gdshader"
## Cuánto se impone el color de la variante sobre la tela, y cuánto se le devuelve de su claro/oscuro.
const OUTFIT_AMOUNT := 0.85
const OUTFIT_DETAIL := 0.8
## Cuánto se tiñe la piel/cabeza: poco, para que el tono cambie sin que la cara se vea rara.
const SKIN_TINT := 0.30

## Paletas de ropa. No son colores al azar: dentro de cada familia los tonos combinan entre sí y
## plan_variants() impide juntar dos prendas llamativas a la vez. Todos los tonos son de ropa de
## calle (variantes clara, oscura y de color de la misma prenda).
const SHIRT_NEUTRAL := [
	Color(0.94, 0.94, 0.92), Color(0.86, 0.85, 0.80), Color(0.70, 0.70, 0.68),
	Color(0.42, 0.42, 0.44), Color(0.20, 0.20, 0.22), Color(0.10, 0.10, 0.11),
	Color(0.78, 0.72, 0.60),
]
const SHIRT_COLORED := [
	Color(0.22, 0.36, 0.72), Color(0.14, 0.20, 0.42), Color(0.34, 0.52, 0.66),
	Color(0.70, 0.18, 0.16), Color(0.44, 0.14, 0.20), Color(0.36, 0.38, 0.22),
	Color(0.72, 0.55, 0.20), Color(0.13, 0.40, 0.36), Color(0.55, 0.28, 0.20),
]
const PANTS_NEUTRAL := [
	Color(0.52, 0.52, 0.52), Color(0.34, 0.34, 0.35), Color(0.18, 0.18, 0.20),
	Color(0.10, 0.10, 0.11), Color(0.30, 0.26, 0.20), Color(0.72, 0.68, 0.58),
]
const PANTS_COLORED := [
	Color(0.20, 0.30, 0.48), Color(0.15, 0.18, 0.34), Color(0.34, 0.33, 0.22),
	Color(0.42, 0.34, 0.22), Color(0.36, 0.24, 0.18), Color(0.24, 0.36, 0.36),
]
const SHOE_COLORS := [
	Color(0.88, 0.88, 0.86), Color(0.60, 0.60, 0.58), Color(0.28, 0.28, 0.30),
	Color(0.12, 0.12, 0.13), Color(0.34, 0.22, 0.14), Color(0.30, 0.12, 0.13),
	Color(0.18, 0.24, 0.42),
]
## Tintes de piel/cabello: multiplican la textura, así que van cerca del blanco (subir de 1 aclara).
const SKIN_TONES := [
	Color(1.06, 1.02, 0.98), Color(1.00, 0.95, 0.89), Color(0.94, 0.87, 0.79),
	Color(0.86, 0.78, 0.70), Color(0.78, 0.70, 0.64), Color(1.00, 0.93, 0.82),
]


## Prepara un ciudadano ya instanciado: deja la jerarquía como "Model/Skeleton3D" (que es lo que
## esperan las pistas de animación) y cambia las piezas por otras sorteadas.
## Devuelve el esqueleto listo para animar, o null si el modelo no traía esqueleto.
static func prepare(
	model: Node,
	rng: RandomNumberGenerator,
	vary: bool = true,
	parts: Dictionary = PARTS,
	plan: Dictionary = {}
) -> Skeleton3D:
	var skeleton := model.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		return null
	# 1) El esqueleto tiene que colgar DIRECTAMENTE del modelo: las pistas horneadas son
	#    "Model/Skeleton3D:<hueso>". Se conserva la transformada global para no perder la
	#    escala de 0,01 que traía la cadena original.
	skeleton.name = "Skeleton3D"
	skeleton.reparent(model, true)
	# 2) Si se pide variedad, fuera las mallas del modelo base: las piezas elegidas ocupan su lugar.
	if vary:
		for child in skeleton.get_children():
			if child is MeshInstance3D:
				skeleton.remove_child(child)
				child.queue_free()
		for slot: String in parts:
			var options: Array = parts[slot]
			var piece: Dictionary = options[rng.randi() % options.size()]
			_add_part(skeleton, piece, slot)
			# El delantal viaja aparte y sólo tiene sentido sobre su propio torso.
			if slot == "torso" and String(piece.get("path", "")) == DOUGH_TORSO:
				_add_part(skeleton, APRON, "torso")
	# 3) Variantes de aspecto (color de la ropa y tono de piel) sobre las mallas que hayan quedado.
	apply_variants(model, plan, {})
	return skeleton


## Añade todas las mallas de una pieza, reasignando sus huesos por nombre al esqueleto base.
## Deja anotado en cada malla a qué hueco pertenece y de qué pieza salió: lo necesita apply_variants
## para saber qué se puede recolorear (y cuánto) sin tener que adivinarlo por el nombre.
static func _add_part(skeleton: Skeleton3D, piece: Dictionary, slot: String) -> void:
	var path := String(piece.get("path", ""))
	var scene: PackedScene = load(path)
	if scene == null:
		push_warning("NPCCitizenModel: no se pudo cargar la pieza %s" % path)
		return
	var node: Node = scene.instantiate()
	for found in node.find_children("*", "MeshInstance3D", true, false):
		var mesh := found as MeshInstance3D
		# La malla deja de pertenecer a la escena de la pieza: si no, Godot avisa de que el
		# propietario queda inconsistente al moverla a otro esqueleto.
		mesh.owner = null
		mesh.reparent(skeleton, false)
		mesh.transform = Transform3D.IDENTITY
		mesh.set_meta("npc_slot", slot)
		mesh.set_meta("npc_piece", piece)
		_rebind_skin(mesh, skeleton)
	node.free()


## Sortea un conjunto de ropa coherente para un ciudadano.
##
## Las reglas existen para que ninguna combinación quede estrafalaria: sólo una prenda llamativa por
## persona (si la camiseta lleva color, el pantalón va en un tono neutro, y al revés), los zapatos
## siempre en tonos discretos, y el tono de piel se sortea aparte (y lo comparten cabeza y manos,
## para que no haya dos pieles distintas en el mismo cuerpo).
static func plan_variants(rng: RandomNumberGenerator) -> Dictionary:
	var bright_shirt := rng.randf() < 0.55
	var shirt := _pick_color(rng, SHIRT_COLORED if bright_shirt else SHIRT_NEUTRAL)
	var pants := _pick_color(rng, PANTS_NEUTRAL if bright_shirt else PANTS_COLORED)
	var skin := _pick_color(rng, SKIN_TONES)
	return {
		"torso": shirt,
		"legs": pants,
		"feet": _pick_color(rng, SHOE_COLORS),
		"head": skin,
		"hands": skin,
	}


static func _pick_color(rng: RandomNumberGenerator, options: Array) -> Color:
	return options[rng.randi() % options.size()] as Color


## Aplica un conjunto de ropa a un ciudadano ya montado. Las prendas se recolorean con el shader
## (conservando el dibujo de la tela) y la piel/cabeza sólo se tiñe un poco, multiplicando la
## textura para no perder nada de la cara.
##
## Todo se trabaja sobre COPIAS y se guarda en caché por (textura, color): los paquetes quedan
## intactos y cientos de ciudadanos no crean cientos de materiales, sólo uno por variante usada.
static func apply_variants(model: Node, plan: Dictionary, cache: Dictionary = {}) -> void:
	if plan.is_empty():
		return
	for found in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := found as MeshInstance3D
		if mesh.mesh == null:
			continue
		var slot := String(mesh.get_meta("npc_slot", _slot_of(mesh.name)))
		if slot == "" or not plan.has(slot):
			continue
		var piece: Dictionary = mesh.get_meta("npc_piece", {})
		var color := plan[slot] as Color
		for surface in mesh.mesh.get_surface_count():
			var source := mesh.get_surface_override_material(surface) as StandardMaterial3D
			if source == null:
				source = mesh.get_active_material(surface) as StandardMaterial3D
			if source == null or source.albedo_texture == null:
				continue
			var material := _variant_material(source, slot, color, piece, cache)
			if material != null:
				mesh.set_surface_override_material(surface, material)


## Deduce el hueco del cuerpo por el nombre de la malla (sirve para los modelos que vienen
## enteros, sin pasar por el ensamblaje modular).
static func _slot_of(mesh_name: String) -> String:
	var lower := mesh_name.to_lower()
	for slot: String in ["torso", "legs", "feet", "hands", "head"]:
		if lower.contains(slot):
			return slot
	return ""


static func _variant_material(
	source: StandardMaterial3D, slot: String, color: Color, piece: Dictionary, cache: Dictionary
) -> Material:
	var texture := source.albedo_texture
	var cap := float(piece.get("cap", 0.0))
	var skin := slot == "head" or slot == "hands"
	var key := "%s|%d|%s" % [texture.resource_path, cap, str(color)]
	if cache.has(key):
		return cache[key]
	var material: Material = null
	if skin:
		# Piel y pelo: se multiplica el color (no se recolorea), así la cara pintada y el pelo se
		# conservan enteros y sólo cambia el tono.
		var copy := source.duplicate() as StandardMaterial3D
		copy.albedo_color = Color.WHITE.lerp(color, SKIN_TINT)
		material = copy
	elif cap > 0.0:
		var shader := load(OUTFIT_SHADER) as Shader
		if shader != null:
			var cloth := ShaderMaterial.new()
			cloth.shader = shader
			cloth.set_shader_parameter("albedo_texture", texture)
			cloth.set_shader_parameter("outfit_color", color)
			cloth.set_shader_parameter("outfit_amount", minf(cap, OUTFIT_AMOUNT))
			cloth.set_shader_parameter("outfit_detail", OUTFIT_DETAIL)
			cloth.set_shader_parameter("outfit_reference", _linear(float(piece.get("ref", 0.35))))
			material = cloth
	# Si la pieza no se puede recolorear (cap 0), se devuelve null y la pule el acabado común.
	cache[key] = material
	return material


## sRGB -> lineal: las referencias de brillo se midieron en sRGB (las de la textura) y el shader
## trabaja en lineal.
static func _linear(srgb: float) -> float:
	if srgb <= 0.04045:
		return maxf(srgb / 12.92, 0.01)
	return maxf(pow((srgb + 0.055) / 1.055, 2.4), 0.01)


## Vuelve a apuntar la piel de una malla a los huesos del esqueleto base, buscándolos por nombre.
## La Skin viene del recurso importado y es COMPARTIDA: hay que copiarla antes de tocarla o se
## estaría reescribiendo el modelo original para todo el juego.
static func _rebind_skin(mesh: MeshInstance3D, skeleton: Skeleton3D) -> void:
	if mesh.skin != null:
		var copy := mesh.skin.duplicate(true) as Skin
		var missing := false
		for i in copy.get_bind_count():
			var idx := skeleton.find_bone(String(copy.get_bind_name(i)))
			if idx < 0:
				missing = true
			else:
				copy.set_bind_bone(i, idx)
		if missing:
			push_warning("NPCCitizenModel: la pieza %s tiene huesos que no existen en el esqueleto" % mesh.name)
		mesh.skin = copy
	mesh.skeleton = mesh.get_path_to(skeleton)


## ¿Este modelo es del rig nuevo (Auto-Rig Pro) o de los PSX (Mixamo)?
static func is_arp_rig(skeleton: Skeleton3D) -> bool:
	return skeleton != null and skeleton.find_bone("root.x") >= 0


## Acabado común de las mallas de un personaje. Los packs traen las texturas a lo bruto y los
## materiales de fábrica con la aspereza al máximo: eso deja la piel y la ropa completamente mates
## y, con una sola luz, el bulto se pierde y el personaje parece recortado de una foto.
##
## Se cambian tres cosas, todas baratas (no hay ni una línea de shader):
##
##   - Aspereza 0,6: deja un brillo suave que sigue la curvatura (frente, hombros, pliegues).
##   - Perfilado (rim) 0,35: un filo de luz en el contorno que separa la silueta del fondo.
##   - Filtrado con mipmaps y anisotrópico: la textura de 512/1024 no hierve al moverse.
##
## Se trabaja SIEMPRE sobre una copia del material: el recurso del paquete queda intacto. Como los
## ciudadanos comparten texturas, la copia se guarda en caché por textura, así que cientos de
## ciudadanos no crean cientos de materiales.
static func polish_materials(root: Node, roughness := 0.6, rim := 0.35) -> void:
	var cache := {}
	for found in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := found as MeshInstance3D
		if mesh.mesh == null:
			continue
		# get_surface_count() es del recurso Mesh, no del nodo MeshInstance3D.
		for surface in mesh.mesh.get_surface_count():
			# Las prendas recoloreadas ya traen su propio shader: no se tocan aquí.
			if mesh.get_surface_override_material(surface) is ShaderMaterial:
				continue
			var source := mesh.get_active_material(surface) as StandardMaterial3D
			if source == null:
				continue
			var material := _polished(source, roughness, rim, cache)
			mesh.set_surface_override_material(surface, material)


static func _polished(
	source: StandardMaterial3D, roughness: float, rim: float, cache: Dictionary
) -> StandardMaterial3D:
	var texture: Texture2D = source.albedo_texture
	var key := texture.resource_path if texture != null else str(source.get_instance_id())
	if cache.has(key):
		return cache[key]
	var material := source.duplicate() as StandardMaterial3D
	material.roughness = roughness
	material.metallic = 0.0
	material.rim_enabled = rim > 0.0
	material.rim = rim
	# Tinte 0,6: el filo coge un poco del color de la ropa y otro poco del de la luz.
	material.rim_tint = 0.6
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	cache[key] = material
	return material


## Lista de nombres de hueso de una pieza (para diagnósticos).
static func part_bones(path: String) -> PackedStringArray:
	var scene: PackedScene = load(path)
	if scene == null:
		return PackedStringArray()
	var piece: Node = scene.instantiate()
	var skeleton := piece.find_child("Skeleton3D", true, false) as Skeleton3D
	var names := PackedStringArray()
	if skeleton != null:
		for i in skeleton.get_bone_count():
			names.append(skeleton.get_bone_name(i))
	piece.free()
	return names
