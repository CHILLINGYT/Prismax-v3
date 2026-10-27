extends Node3D
## Sonda diagnóstica: qué esqueletos hay realmente en el jugador y con qué huesos.

const JUGADOR := "res://personaje/base/escenas/leo_jugador.tscn"

func _ready() -> void:
	var ps := load(JUGADOR) as PackedScene
	var jug := ps.instantiate() as Node3D
	add_child(jug)
	await get_tree().process_frame
	await get_tree().process_frame
	print("[diag] === ANTES de transformar ===")
	_listar(jug)
	jug.call("_on_transformacion_elegida", &"aguila")
	await get_tree().create_timer(2.0).timeout
	print("[diag] === DESPUÉS de transformar (águila) ===")
	_listar(jug)
	get_tree().quit()

func _listar(raiz: Node) -> void:
	var pilas: Array[Node] = [raiz]
	while not pilas.is_empty():
		var n: Node = pilas.pop_back()
		if n is Skeleton3D:
			var sk := n as Skeleton3D
			var nombres: Array[String] = []
			for i in mini(sk.get_bone_count(), 12):
				nombres.append(String(sk.get_bone_name(i)))
			print("[diag] Skeleton en '%s': %d huesos; primeros: %s" % [
					String(raiz.get_path_to(sk)), sk.get_bone_count(), str(nombres)])
			for buscado in ["Hips", "LeftFoot", "LeftToes", "RightToes", "Root"]:
				print("[diag]   find_bone('%s') = %d" % [buscado, sk.find_bone(StringName(buscado))])
		for hijo in n.get_children():
			pilas.push_back(hijo)