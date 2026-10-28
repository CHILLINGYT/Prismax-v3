class_name EdicionesCiudad
extends RefCounted
## =============================================================================
##  EDICIONES DEL MUNDO — los cambios a mano sobre la ciudad procedural.
## =============================================================================
##
## La ciudad se genera con semilla fija (ver `world/semilla_mundo.gd`): el mapa
## sale siempre igual. Esta tabla es para lo que NO conviene tocar en el
## generador: reemplazar una casa concreta, cambiar su altura o su material,
## esconder una tapa de alcantarilla, poner una farola en un sitio elegido…
##
## Las reglas de generación viven en `generador_ciudad.gd`; las excepciones
## particulares viven AQUÍ. Por eso las ediciones se conservan al volver a
## generar la ciudad: el generador las lee y las aplica, pero no las escribe.
##
## -----------------------------------------------------------------------------
##  IDENTIFICADORES ESTABLES
## -----------------------------------------------------------------------------
## No dependen del azar, sólo del sitio del elemento en el mapa, así que el mismo
## id señala la misma casa o la misma tapa en cualquier partida:
##
##   · Edificio:            E<manzanaX>_<manzanaZ>_<solarX>_<solarZ>
##                          ej. "E2_3_0_1" = manzana (2,3), solar (0,1)
##   · Tapa de alcantarilla: tapa:V<calle>:<cuadra>   /  tapa:H<calle>:<cuadra>
##                          ej. "tapa:H2:3" = calle horizontal 2, cuadra 3
##   · Sumidero:             sumidero:V<calle>:<cuadra>:<lado>  (lado 0 = izquierda)
##
## CÓMO ENCONTRAR EL ID DE UNA CASA CONCRETA (sin cuentas):
##   1. Abre el juego y camina hasta la casa que quieras cambiar.
##   2. En el editor, con el juego corriendo, mira el árbol *Remota*:
##      `Ciudad/CiudadGenerada/Modulares/` tiene un nodo por edificio y se llama
##      exactamente como su id (ej. `E2_3_0_1`). Su hijo `Colision` está en el
##      centro de la parcela, así que el nodo seleccionado es el edificio.
##   3. Copia ese nombre aquí, en `EDIFICIOS`.
##   Las tapas y los sumideros se cuentan por calle y cuadra desde la esquina
##   noroeste del mapa; el id de la tapa de la cuadra donde estás se puede leer
##   igual en el árbol (nodos `tapa:V2:3`) o calcular con la posición.
##
## -----------------------------------------------------------------------------
##  QUÉ SE PUEDE PONER EN CADA ENTRADA
## -----------------------------------------------------------------------------
##   EDIFICIOS[ id ] = {
##       "ocultar":       true,              # deja el solar vacío (sin edificio)
##       "prefab":        "Building_Large_2",# usa OTRO modelo del kit para esta casa
##       "familia":       "B",               # familia de módulos (A, B, C…) del modular
##       "pisos":         9,                 # nº de plantas del modular
##       "material":      "res://materiales/fachada.tres",  # material para TODAS sus mallas
##       "color":         Color(0.8, 0.2, 0.2),  # tinte plano (si no hay material)
##       "escala":        1.15,              # multiplica su tamaño
##       "giro_grados":   90.0,              # gira esta casa sobre su centro
##       "desplazamiento": Vector3(1, 0, 0), # la mueve (m)
##   }
##   Sólo se aplican las claves que escribas: lo demás se genera como siempre.
##
##   PROPS[ id ] = {
##       "ocultar": true,                    # quita esa tapa / ese sumidero
##       "pieza":   "Prop_ManholeCover_2",   # o cambia su modelo
##       "escala":  1.2,
##       "giro_grados": 45.0,
##   }
##
##   PROPS_EXTRA = [ { …objeto a mano… } ]  # se añaden SIEMPRE, en cada generación
##       {"nombre":   "Farola_de_la_plaza",  # nombre del nodo (para encontrarlo)
##        "pieza":    "Prop_StreetLamp_1",   # nombre del modelo (el del .gltf)
##        "pos":      Vector3(-18.0, 0.0, 12.5),
##        "giro_grados": 90.0,
##        "escala":   1.0,
##        "en_acera": true,                  # se apoya a cota de acera (false = calzada)
##        "apoyar":   true}                  # false = respeta la Y que le des
##
## NADA de esto modifica a los demás: cada edición se aplica SOLO a su id, y la
## casa editada se construye aparte (instanciada), sin tocar el lote compartido
## de las demás. Para probarlo, mira la prueba de `res://.backup_semilla/`.
## =============================================================================

## Edificios: id → cambios (vacío = la ciudad se genera como siempre).
const EDIFICIOS := {
	# Ejemplos (descomenta y ajusta; los ids reales se ven en el árbol Remota):
	# "E2_3_0_1": {"ocultar": true},
	# "E4_1_1_0": {"prefab": "Building_Medium_2"},
	# "E0_0_0_0": {"pisos": 9, "color": Color(0.82, 0.30, 0.26)},
}

## Tapas de alcantarilla, sumideros y demás props generados: id → cambios.
const PROPS := {
	# "tapa:H2:3": {"ocultar": true},
}

## Objetos colocados a mano en una posición exacta. La generación NO los toca:
## se añaden enteros en cada regeneración (nada los sobrescribe ni los borra).
const PROPS_EXTRA: Array[Dictionary] = [
	# {"nombre": "Farola_plaza", "pieza": "Prop_StreetLamp_1",
	#  "pos": Vector3(-18.0, 0.0, 12.5), "giro_grados": 90.0},
]

## Tabla inyectada en caliente (pruebas y ajustes desde código). Se mezcla ENCIMA
## de las de arriba, sin tocarlas: `inyectar({"edificios": {...}, "props": {...}})`.
static var _inyectado: Dictionary = {}


# --- Consultas (las usa el generador) ------------------------------------------

## Cambios pedidos para un edificio ({} si no hay ninguno).
static func edificio(id: String) -> Dictionary:
	var d: Dictionary = {}
	if EDIFICIOS.has(id):
		d.merge(EDIFICIOS[id], true)
	var iny: Dictionary = _inyectado.get("edificios", {})
	if iny.has(id):
		d.merge(iny[id], true)
	return d


## Cambios pedidos para un prop generado (tapa, sumidero…). {} si no hay ninguno.
static func prop(id: String) -> Dictionary:
	var d: Dictionary = {}
	if PROPS.has(id):
		d.merge(PROPS[id], true)
	var iny: Dictionary = _inyectado.get("props", {})
	if iny.has(id):
		d.merge(iny[id], true)
	return d


## Objetos a mano de esta generación: los fijos de `PROPS_EXTRA` más los inyectados.
static func props_extra() -> Array[Dictionary]:
	var lista: Array[Dictionary] = []
	for d: Dictionary in PROPS_EXTRA:
		lista.append(d.duplicate())
	var iny: Array = _inyectado.get("extra", [])
	for d: Dictionary in iny:
		lista.append(d.duplicate())
	return lista


## ¿Está pedido que ese id no se genere?
static func ocultar(id: String) -> bool:
	if bool(edificio(id).get("ocultar", false)):
		return true
	return bool(prop(id).get("ocultar", false))


## Material con el que pintar TODAS las mallas de un edificio editado:
## "material" (una ruta a un Material) o, si no, un tinte plano con "color".
static func material_de(ed: Dictionary) -> Material:
	if ed.has("material"):
		var ruta := String(ed["material"])
		if ResourceLoader.exists(ruta):
			var mat := load(ruta)
			if mat is Material:
				return mat as Material
		push_warning("[EdicionesCiudad] material no encontrado: %s" % ruta)
	if ed.has("color"):
		var m := StandardMaterial3D.new()
		m.albedo_color = ed["color"]
		m.roughness = 1.0
		return m
	return null


## ¿Hay alguna edición? (Lo imprime el generador en su informe.)
static func resumen() -> String:
	var iny_ed: Dictionary = _inyectado.get("edificios", {})
	var iny_pr: Dictionary = _inyectado.get("props", {})
	var n_ed: int = EDIFICIOS.size() + iny_ed.size()
	var n_pr: int = PROPS.size() + iny_pr.size()
	var n_ex: int = props_extra().size()
	if n_ed == 0 and n_pr == 0 and n_ex == 0:
		return "sin ediciones (ciudad 100% procedural)"
	return "edificios %d | props %d | objetos a mano %d" % [n_ed, n_pr, n_ex]


# --- Utilidades ----------------------------------------------------------------

## Id de un edificio a partir de su manzana y de su solar (0,0 = noroeste).
static func id_edificio(manzana: Vector2i, solar: Vector2i) -> String:
	return "E%d_%d_%d_%d" % [manzana.x, manzana.y, solar.x, solar.y]


## Inyecta ediciones en caliente (pruebas o herramientas). No toca las constantes.
static func inyectar(tabla: Dictionary) -> void:
	for clave: String in tabla.keys():
		if clave == "extra":
			var acum: Array = _inyectado.get("extra", [])
			acum.append_array(tabla[clave])
			_inyectado["extra"] = acum
		else:
			var d: Dictionary = _inyectado.get(clave, {})
			d.merge(tabla[clave], true)
			_inyectado[clave] = d


## Olvida lo inyectado (vuelve a las tablas de arriba).
static func limpiar_inyeccion() -> void:
	_inyectado.clear()