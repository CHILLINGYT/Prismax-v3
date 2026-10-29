class_name NPCSpawner
extends Node3D

## Genera y administra a los ciudadanos de la escena.
##
##   - Coloca `npc_count` ciudadanos sobre la zona caminable (nunca dos en el mismo punto).
##   - Cada uno recibe un modelo distinto y una personalidad sorteada, así no se ven clones.
##   - Cada `activity_interval` segundos revisa la distancia al jugador y ajusta el nivel de
##     actividad (LOD) de unos pocos por turno, de modo que se pueden tener cientos de
##     ciudadanos en la ciudad pagando sólo por los que se ven de cerca.
##
## Los ciudadanos se agregan como hijos de este nodo.

const MALE_DIR := "res://NPCs/Characters/PSX/Male/"
const FEMALE_DIR := "res://NPCs/Characters/PSX/Female/"

## Modelos de los packs nuevos (City Folks + Urban Man). Comparten rig de Auto-Rig Pro, así que el
## ciudadano los ensambla con piezas sorteadas de ellos (ver NPCCitizenModel): de ahí sale la
## variedad de caras, cuerpos y ropa. Son los que dan el salto de calidad visual.
## "Dough Sensei" no está: su cabeza resultó ser una caja con un logotipo pintado (ver NPCCitizenModel).
const POLY_MODELS := [
	"res://Assets NPCS/UrbanMan_PolyMate_alstrainfinite/GLB/UrbanMan_CityFolks_PolyMate.glb",
	"res://Assets NPCS/CityFolks_PolyMate_alstrainfinite/GLB/Deportista/Deportista_CityFolks_PolyMate.glb",
	"res://Assets NPCS/CityFolks_PolyMate_alstrainfinite/GLB/Muscle Man/MuscleMan_CityFolks_PolyMate.glb",
]

## Modelos del pack que se dejan fuera: este FBX no tiene textura en el ZIP original
## (falta Character_Female_01.png), así que aparecería en blanco.
const EXCLUDED_MODELS := ["Character_Female_01.fbx"]

@export_group("Generación")
## Escena base del ciudadano (NPC_Citizen.tscn).
@export var npc_scene: PackedScene
## Modelos disponibles. Si queda vacío se detectan automáticamente de las carpetas PSX.
@export var citizen_models: Array[PackedScene] = []
@export_range(0, 400) var npc_count := 10
## Zona donde aparecen (coordenadas XZ).
@export var spawn_area := Rect2(-26.0, -26.0, 52.0, 52.0)
## Distancia mínima (m) a la que aparecen del origen de este nodo.
@export var spawn_min_distance := 5.0
## Distancia máxima (m) a la que aparecen del origen; 0 = sin límite.
@export var spawn_max_distance := 0.0
## Separación mínima (m) entre ciudadanos al aparecer.
@export var min_spacing := 2.5
## Zona por la que deambulan.
@export var wander_area := Rect2(-34.0, -34.0, 68.0, 68.0)
## No aparecen a menos de esta distancia (m) del jugador.
@export var player_clearance := 6.0
@export var spawn_on_ready := true
## Proporción de ciudadanos que se monta con el rig nuevo (City Folks / Urban Man) en vez de con
## los modelos PSX. Por defecto 0: al compararlos uno al lado del otro (sonda de aspecto) los PSX
## son los que tienen cara de verdad —ojos, barba, arrugas, ropa con pliegues pintados— mientras
## que los del rig nuevo vienen facetados y con la cabeza lisa, de modo que se ven como recortes
## planos. Súbelo a 1 para ver el ensamblaje modular, que sigue funcionando igual.
@export_range(0.0, 1.0) var poly_share := 0.0
## Proporción de ciudadanos con planificador de objetivos (addon GdPlanningAI). El planificador
## cuesta CPU por agente, así que sólo se monta en unos pocos y siempre en el nivel NEAR.
@export_range(0.0, 1.0) var goap_share := 0.34

@export_group("Niveles de actividad (LOD)")
## Distancia (m) al jugador a la que el ciudadano pasa a comportamiento simplificado.
@export var mid_distance := 30.0
## Distancia (m) al jugador a la que el ciudadano se congela (no navega ni anima).
@export var far_distance := 70.0
## Cada cuántos segundos se revisa la distancia al jugador.
@export var activity_interval := 0.5

## Ciudadanos creados por este generador (en el orden en que aparecieron).
var citizens: Array[NPCCitizen] = []

var _rng := RandomNumberGenerator.new()
var _model_bag: Array[PackedScene] = []
var _psx_models: Array[PackedScene] = []
var _poly_models: Array[PackedScene] = []
var _bag_psx: Array[PackedScene] = []
var _bag_poly: Array[PackedScene] = []
var _player: Node3D
var _activity_timer := 0.0
var _activity_cursor := -1


func _ready() -> void:
	_rng.randomize()
	if goap_share > 0.0:
		_setup_goap_world()
	if spawn_on_ready:
		_spawn_when_navigation_ready()


## Espera a que el servidor de navegación haya sincronizado el mapa (la malla se hornea en el
## _ready de la NavigationRegion3D) antes de colocar a nadie: si no, las consultas de
## navegación devuelven datos vacíos y los ciudadanos podrían aparecer fuera de la zona.
func _spawn_when_navigation_ready() -> void:
	# Espera a que el mapa no sólo tenga regiones, sino a que las consultas respondan:
	# si no, los primeros ciudadanos caerían fuera de la malla de navegación.
	var map := get_world_3d().navigation_map
	for attempt in 60:
		await get_tree().physics_frame
		NavigationServer3D.map_force_update(map)
		if NavigationServer3D.map_get_iteration_id(map) > 0:
			var probe := global_position + Vector3(0.0, 0.5, 0.0)
			if NavigationServer3D.map_get_closest_point(map, probe).distance_to(probe) < 3.0:
				break
	spawn_citizens()


func _process(delta: float) -> void:
	# Reparto de niveles de actividad por turnos: nunca se revisan todos en el mismo fotograma.
	if citizens.is_empty():
		return
	_activity_timer += delta
	if _activity_timer < activity_interval:
		return
	_activity_timer = 0.0
	if _player == null or not is_instance_valid(_player):
		_player = _find_player()
	var slice := maxi(1, ceili(citizens.size() / 4.0))
	for i in slice:
		_activity_cursor = (_activity_cursor + 1) % citizens.size()
		var citizen := citizens[_activity_cursor]
		if not is_instance_valid(citizen):
			continue
		var distance := 0.0 if _player == null else citizen.global_position.distance_to(_player.global_position)
		citizen.set_activity(_tier_for(distance))


## Crea `npc_count` ciudadanos y devuelve la lista.
func spawn_citizens() -> Array[NPCCitizen]:
	var created: Array[NPCCitizen] = []
	var models := _resolve_models()
	if models.is_empty():
		push_warning("NPCSpawner: no hay modelos de ciudadano disponibles")
		return created
	if _player == null:
		_player = _find_player()
	var used: Array[Vector2] = []
	for i in npc_count:
		var model: PackedScene = _choose_model(models)
		var citizen := _build_citizen(model)
		if citizen == null:
			continue
		citizen.position = _find_spawn_point(used)
		used.append(Vector2(citizen.position.x, citizen.position.z))
		add_child(citizen)
		citizens.append(citizen)
		created.append(citizen)
	return created


## Borra los ciudadanos actuales y genera otros tantos (útil para probar 10, 50, 200...).
func respawn(count: int) -> Array[NPCCitizen]:
	clear_citizens()
	npc_count = count
	return spawn_citizens()


func clear_citizens() -> void:
	for citizen in citizens:
		if is_instance_valid(citizen):
			citizen.queue_free()
	citizens.clear()
	_activity_cursor = -1


func _build_citizen(model: PackedScene) -> NPCCitizen:
	if npc_scene == null:
		push_error("NPCSpawner: falta npc_scene")
		return null
	var citizen := npc_scene.instantiate() as NPCCitizen
	if citizen == null:
		return null
	citizen.model_scene = model
	var path := String(model.resource_path)
	if path.contains("PolyMate"):
		# Packs nuevos: rig Auto-Rig Pro (el ciudadano lo detecta solo) y piezas sorteadas.
		citizen.body_type = "male"
	else:
		citizen.body_type = "female" if path.contains("Female") else "male"
	citizen.wander_area = wander_area
	citizen.use_goap = goap_share > 0.0 and _rng.randf() < goap_share
	return citizen


## Elige el modelo del próximo ciudadano: con probabilidad `poly_share` uno de los packs nuevos y
## si no uno de los PSX. Dentro de cada grupo se recorre la lista en orden aleatorio para no
## repetir el mismo aspecto seguido.
func _choose_model(models: Array[PackedScene]) -> PackedScene:
	if not citizen_models.is_empty():
		return _pick_model(models)
	var use_poly := not _poly_models.is_empty() and _rng.randf() < poly_share
	var source: Array[PackedScene] = _poly_models if use_poly else _psx_models
	if source.is_empty():
		return _pick_model(models)
	return _pick_from(source, _bag_poly if use_poly else _bag_psx)


func _pick_from(source: Array[PackedScene], bag: Array[PackedScene]) -> PackedScene:
	if bag.is_empty():
		bag.append_array(source)
		bag.shuffle()
	return bag.pop_back()


## Crea el nodo de mundo que necesita el planificador de objetivos (addon GdPlanningAI).
## Sin él, los ciudadanos con `use_goap` siguen funcionando con su máquina de estados de siempre.
func _setup_goap_world() -> void:
	if get_tree().root.find_child("GoapWorld", true, false) != null:
		return
	var world := GdPAIWorldNode.new()
	world.name = "GoapWorld"
	world.blackboard_plan = GdPAIBlackboardPlan.new()
	add_child(world)


func _pick_model(models: Array[PackedScene]) -> PackedScene:
	# Se recorre la lista en orden aleatorio para no repetir el mismo aspecto seguido.
	if _model_bag.is_empty():
		_model_bag = models.duplicate()
		_model_bag.shuffle()
	return _model_bag.pop_back()


## Devuelve los modelos cargados (los del inspector o, si no hay, los detectados en disco).
## OJO: en NPCs/Characters/PSX sólo hay personas corrientes; los zombis y monstruos del ZIP
## original nunca se extrajeron, así que no pueden entrar en el sorteo.
func _resolve_models() -> Array[PackedScene]:
	if not citizen_models.is_empty():
		return citizen_models
	var found: Array[PackedScene] = []
	for dir: String in [MALE_DIR, FEMALE_DIR]:
		var files := DirAccess.get_files_at(dir)
		if files.is_empty():
			continue
		var names: Array[String] = []
		for f in files:
			if f.ends_with(".fbx") and not EXCLUDED_MODELS.has(f):
				names.append(f)
		names.sort()
		for f in names:
			var res: Resource = load(dir + f)
			if res is PackedScene:
				found.append(res)
	_psx_models = found
	_poly_models.clear()
	for path: String in POLY_MODELS:
		var res: Resource = load(path)
		if res is PackedScene:
			_poly_models.append(res)
	var all: Array[PackedScene] = []
	all.append_array(found)
	all.append_array(_poly_models)
	return all


func _find_player() -> Node3D:
	return get_tree().get_first_node_in_group("player") as Node3D


func _tier_for(distance: float) -> NPCCitizen.Activity:
	if distance >= far_distance:
		return NPCCitizen.Activity.FAR
	if distance >= mid_distance:
		return NPCCitizen.Activity.MID
	return NPCCitizen.Activity.NEAR


## Busca una posición libre sobre la zona caminable, a la distancia pedida del origen y
## separada de las demás. Si el sitio se va estrechando, va relajando la separación exigida
## (nunca por debajo de 1 m, para que no haya dos ciudadanos en el mismo punto).
func _find_spawn_point(used: Array[Vector2]) -> Vector3:
	var map := get_world_3d().navigation_map
	# Asegura que el mapa ya está sincronizado; si no, las consultas devuelven datos vacíos.
	NavigationServer3D.map_force_update(map)
	var origin := Vector2(global_position.x, global_position.z)
	var attempts := 300
	for attempt in attempts:
		var relax := float(attempt) / float(attempts)
		var spacing := maxf(1.0, min_spacing * (1.0 - 0.5 * relax))
		var point := Vector2(
			_rng.randf_range(spawn_area.position.x, spawn_area.end.x),
			_rng.randf_range(spawn_area.position.y, spawn_area.end.y)
		)
		var from_origin := point.distance_to(origin)
		if from_origin < spawn_min_distance:
			continue
		if spawn_max_distance > 0.0 and from_origin > spawn_max_distance:
			continue
		var free := true
		for u in used:
			if point.distance_to(u) < spacing:
				free = false
				break
		if not free:
			continue
		# El punto debe estar sobre la malla de navegación; si no, el ciudadano quedaría fuera.
		var world := Vector3(point.x, 0.0, point.y)
		var closest := NavigationServer3D.map_get_closest_point(map, world)
		if world.distance_to(closest) > 1.5:
			continue
		if _player != null and is_instance_valid(_player) and closest.distance_to(_player.global_position) < player_clearance:
			continue
		return closest + Vector3(0.0, 0.05, 0.0)
	# Último recurso: el mejor de varios puntos caminables, es decir, el más lejano de los
	# ya usados. Así nunca quedan dos ciudadanos en el mismo sitio, aunque la zona esté llena.
	var best := Vector3.ZERO
	var best_score := -1.0
	var have_best := false
	for attempt in 96:
		var point := Vector2(
			_rng.randf_range(spawn_area.position.x, spawn_area.end.x),
			_rng.randf_range(spawn_area.position.y, spawn_area.end.y)
		)
		var world := Vector3(point.x, 0.0, point.y)
		var closest := NavigationServer3D.map_get_closest_point(map, world)
		if world.distance_to(closest) > 1.5:
			continue
		var score := 1e9
		for u in used:
			score = minf(score, point.distance_to(u))
		if not have_best or score > best_score:
			have_best = true
			best_score = score
			best = closest
	if have_best:
		if best_score < min_spacing:
			# Aleja el punto del ciudadano más cercano: nunca deben quedar dos NPCs pegados.
			var nearest := Vector2(1.0, 0.0)
			var nearest_dist := 1e9
			for u in used:
				var distance: float = Vector2(best.x, best.z).distance_to(u)
				if distance < nearest_dist:
					nearest_dist = distance
					nearest = u
			var away: Vector2 = Vector2(best.x, best.z) - nearest
			if away.length() < 0.001:
				away = Vector2(1.0, 0.0)
			var pushed: Vector2 = nearest + away.normalized() * 1.2
			var pushed_world := Vector3(pushed.x, 0.0, pushed.y)
			var pushed_closest := NavigationServer3D.map_get_closest_point(map, pushed_world)
			if pushed_world.distance_to(pushed_closest) <= 1.5:
				best = pushed_closest
			push_warning("NPCSpawner: quedaban %.1f m de separación; se apartó al ciudadano del más cercano" % best_score)
		return best + Vector3(0.0, 0.05, 0.0)
	push_warning("NPCSpawner: no hubo sitio libre; se usa el punto caminable más cercano")
	var fallback := NavigationServer3D.map_get_closest_point(map, global_position + Vector3(0.0, 0.5, 0.0))
	if used.is_empty():
		return fallback + Vector3(0.0, 0.05, 0.0)
	# Aun en el peor caso, nunca se deja al ciudadano encima de otro.
	var anchor: Vector2 = used[0]
	var anchor_dist := 1e9
	for u in used:
		var gap: float = Vector2(fallback.x, fallback.z).distance_to(u)
		if gap < anchor_dist:
			anchor_dist = gap
			anchor = u
	var offset: Vector2 = Vector2(fallback.x, fallback.z) - anchor
	if offset.length() < 0.001:
		offset = Vector2(1.0, 0.0)
	offset = offset.normalized() * 1.2
	return Vector3(anchor.x + offset.x, fallback.y, anchor.y + offset.y) + Vector3(0.0, 0.05, 0.0)