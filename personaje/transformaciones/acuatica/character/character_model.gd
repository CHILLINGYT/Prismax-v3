class_name CharacterModel
extends Node3D
## =============================================================================
##  MODELO VISUAL DEL PERSONAJE (el "slot" del modelo)
## =============================================================================
##  Este nodo es el UNICO punto de contacto entre la logica del jugador y el
##  modelo 3D. Su unica responsabilidad es:
##
##    * decir cual es el nodo raiz del modelo visual actual,
##    * decir cual es su Skeleton3D y su AnimationPlayer (si los tiene),
##    * traducir nombres de hueso "estandar" a los nombres del modelo actual,
##    * permitir cambiar el modelo en caliente.
##
##  Si manana importas un personaje GLB/GLTF y lo pones como hijo de este nodo,
##  NO hay que tocar el codigo del jugador: el resto del sistema pregunta aqui.
##
##  Nada de este script depende del placeholder: funciona con cualquier modelo.
## =============================================================================

## Se emite cuando cambia el modelo visual (incluye el reemplazo en caliente).
signal model_changed(model: Node3D)

## Ruta al nodo raiz del modelo. Si se deja vacia se usa el primer hijo Node3D.
@export var model_path: NodePath

## Ruta al Skeleton3D del modelo. Si se deja vacia se busca automaticamente.
@export var skeleton_path: NodePath

## Traduccion de nombres de hueso cuando el modelo usa otros nombres.
## Clave = nombre estandar (Root, Hips, Spine, ...) -> Valor = nombre real en
## el modelo importado (por ejemplo "mixamorig:Hips").
## Solo hace falta rellenarlo si tus animaciones apuntan a los nombres
## estandar y tu modelo usa otros. Se pueden anadir filas en el Inspector.
@export var bone_name_map: Dictionary = {}


## Devuelve el nodo raiz del modelo visual actual (o null si no hay ninguno).
func get_model() -> Node3D:
	var explicit := get_node_or_null(model_path) as Node3D
	if explicit != null:
		return explicit
	for child in get_children():
		var candidate := child as Node3D
		if candidate != null:
			return candidate
	return null


## Devuelve el Skeleton3D del modelo actual (o null si el modelo no tiene).
func get_skeleton() -> Skeleton3D:
	var explicit := get_node_or_null(skeleton_path) as Skeleton3D
	if explicit != null:
		return explicit
	var model := get_model()
	if model == null:
		return null
	if model is Skeleton3D:
		return model
	return _find_first_skeleton(model)


## Devuelve el AnimationPlayer que venga DENTRO del modelo (si lo trae).
## Sirve para reutilizar las animaciones que exporta tu personaje importado.
func get_animation_player() -> AnimationPlayer:
	var model := get_model()
	if model == null:
		return null
	return _find_first_animation_player(model)


## Traduce un nombre de hueso estandar al nombre que usa el modelo actual.
func resolve_bone_name(standard_bone: StringName) -> StringName:
	var mapped: Variant = bone_name_map.get(String(standard_bone))
	if mapped == null:
		return standard_bone
	return StringName(mapped)


## Ruta desde [param from_node] hasta el Skeleton3D del modelo (para reescribir
## los tracks de animacion). Devuelve NodePath() si no hay skeleton.
func get_skeleton_path_from(from_node: Node) -> NodePath:
	var skeleton := get_skeleton()
	if skeleton == null or from_node == null:
		return NodePath()
	return from_node.get_path_to(skeleton)


## Reemplaza el modelo visual por otro nodo (por ejemplo, la instancia de tu
## personaje importado). El modelo anterior se elimina.
func set_model(new_model: Node3D) -> void:
	if new_model == null:
		return
	var current := get_model()
	if current != null:
		remove_child(current)
		current.queue_free()
	add_child(new_model)
	model_path = NodePath(new_model.name)
	model_changed.emit(new_model)


func _find_first_skeleton(node: Node) -> Skeleton3D:
	for child in node.get_children():
		var skeleton := child as Skeleton3D
		if skeleton != null:
			return skeleton
		var nested := _find_first_skeleton(child)
		if nested != null:
			return nested
	return null


func _find_first_animation_player(node: Node) -> AnimationPlayer:
	for child in node.get_children():
		var player := child as AnimationPlayer
		if player != null:
			return player
		var nested := _find_first_animation_player(child)
		if nested != null:
			return nested
	return null
