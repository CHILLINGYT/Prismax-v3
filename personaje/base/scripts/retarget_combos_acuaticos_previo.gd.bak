extends SceneTree

const COMBAT_LIBRARY_PATH: String = "res://personaje/transformaciones/transformacion ataque/animations/player_anim_library.tres"
const AQUATIC_MODEL_PATH: String = "res://personaje/transformaciones/acuatica/models/futuristic_armor_character.tscn"
const OUTPUT_PATH: String = "user://combos_acuaticos.tres"
const CLIPS: Array[String] = ["jab", "dos", "cros", "gancho"]

func _init() -> void:
	var combat_library: AnimationLibrary = load(COMBAT_LIBRARY_PATH) as AnimationLibrary
	var aquatic_scene: PackedScene = load(AQUATIC_MODEL_PATH) as PackedScene
	var root: Node = aquatic_scene.instantiate()
	var skeleton: Skeleton3D = root.find_child("Skeleton3D", true, false) as Skeleton3D
	var output: AnimationLibrary = AnimationLibrary.new()
	for clip: String in CLIPS:
		var source: Animation = combat_library.get_animation(clip)
		var animation: Animation = source.duplicate() as Animation
		for track: int in animation.get_track_count():
			var source_path: String = String(animation.track_get_path(track))
			var parts: PackedStringArray = source_path.split(":")
			if parts.size() < 2:
				continue
			var bone: String = parts[1]
			if skeleton.find_bone(bone) < 0:
				push_error("No existe el hueso %s en el esqueleto acuático" % bone)
				quit(1)
				return
			animation.track_set_path(track, NodePath("Visual/CharacterModel/Skeleton3D:" + bone))
		output.add_animation(clip, animation)
	root.free()
	var err: Error = ResourceSaver.save(output, OUTPUT_PATH)
	if err != OK:
		push_error("No se pudo guardar la librería retargeteada: %s" % error_string(err))
		quit(1)
		return
	print("Librería acuática retargeteada: ", output.get_animation_list())
	quit()
