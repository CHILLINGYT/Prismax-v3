## leo_muerte.gd - Fase 3 - Sistema de muerte
## Extraído de controlador_leo.gd

class_name LeoMuerte

const ESC_MUERTE := "res://personaje/transformaciones/Muerte.fbx"
const ESC_MORIDO := "res://personaje/transformaciones/Morido.fbx"
const CLIP_MUERTE := &"muerte"
const CLIP_MORIDO := &"morido"
const ANIM_MUERTE_VUELO := "Death01"
const MUERTE_ESPERA_FUNDIDO := 1.1

static func retarget_muerte_mixamo(esqueleto_origen: Skeleton3D, esqueleto_destino: Skeleton3D, anim_player: AnimationPlayer) -> void:
	# Retarget de animación de muerte Mixamo a maniquí Godot
	# Usa MAPA_MIXAMO_MANIQUE de LeoConstants
	if esqueleto_origen == null or esqueleto_destino == null or anim_player == null:
		return
	
	var mapa := LeoConstants.MAPA_MIXAMO_MANIQUE
	# Crear animación retargeteada
	var anim_muerte: Animation = anim_player.get_animation(CLIP_MUERTE) if anim_player.has_animation(CLIP_MUERTE) else null
	if anim_muerte == null:
		return
	
	# Copiar tracks por nombre de hueso usando mapa
	for track_idx in anim_muerte.get_track_count():
		var path: String = anim_muerte.track_get_path(track_idx)
		# path formato "Skeleton3D:bone_name"
		var parts := path.split(":")
		if parts.size() < 2:
			continue
		var bone_name: String = parts[1]
		if not mapa.has(bone_name):
			continue
		var dest_bone: String = mapa[bone_name]
		# Buscar índice de hueso destino
		var dest_idx := esqueleto_destino.find_bone(dest_bone)
		if dest_idx == -1:
			continue
		# Aquí se copiaría la animación - simplificado
		print("[Muerte] Retarget %s -> %s" % [bone_name, dest_bone])

static func procesar_muerte(leo: CharacterBody3D, delta: float, estado_muerte: int, t_muerte: float) -> Dictionary:
	match estado_muerte:
		LeoEnums.Muerte.CAYENDO:
			# Caída libre al morir
			leo.velocity.y -= 22.0 * delta
			leo.move_and_slide()
			if leo.is_on_floor():
				return {"estado": LeoEnums.Muerte.MUERTO, "t": 0.0}
			return {"estado": LeoEnums.Muerte.CAYENDO, "t": t_muerte + delta}
		LeoEnums.Muerte.MUERTO:
			var nuevo_t := t_muerte + delta
			if nuevo_t > MUERTE_ESPERA_FUNDIDO:
				return {"estado": LeoEnums.Muerte.RESPAWN, "t": nuevo_t}
			return {"estado": LeoEnums.Muerte.MUERTO, "t": nuevo_t}
		LeoEnums.Muerte.RESPAWN:
			# Respawn logic manejado por controlador principal
			return {"estado": LeoEnums.Muerte.VIVO, "t": 0.0}
		_:
			return {"estado": LeoEnums.Muerte.VIVO, "t": 0.0}

static func mostrar_pantalla_muerte(leo: Node3D) -> void:
	var escena_muerte := preload("res://ui/scenes/DeathScreen.tscn") if ResourceLoader.exists("res://ui/scenes/DeathScreen.tscn") else null
	if escena_muerte == null:
		print("[Muerte] DeathScreen no encontrado")
		return
	var canvas := leo.get_tree().current_scene as Node
	if canvas == null:
		return
	var pantalla := escena_muerte.instantiate()
	canvas.add_child(pantalla)
