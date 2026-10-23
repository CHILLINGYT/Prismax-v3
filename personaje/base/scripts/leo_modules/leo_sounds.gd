## leo_sounds.gd - Fase 3 - Sistema de sonidos
## Extraído de controlador_leo.gd

class_name LeoSounds

static func configurar_sonidos_velocista(leo: Node3D) -> void:
	# Configurar AudioStreamPlayers del velocista
	var audios := {
		"AudioCarga": "res://Audio/personaje/transformacion/velocidad/carga.wav",
		"AudioTrazado": "res://Audio/personaje/transformacion/velocidad/trazado.wav",
		"AudioDash": "res://Audio/personaje/transformacion/velocidad/dash.wav",
		"AudioGolpe": "res://Audio/personaje/transformacion/velocidad/golpe click.wav",
	}
	for nombre in audios:
		var player := leo.get_node_or_null(nombre) as AudioStreamPlayer
		if player != null:
			player.bus = &"Efectos"

static func sonar_carga(leo: Node3D) -> void:
	var p := leo.get_node_or_null("AudioCarga") as AudioStreamPlayer
	if p != null and not p.playing:
		p.play()

static func parar_carga(leo: Node3D) -> void:
	var p := leo.get_node_or_null("AudioCarga") as AudioStreamPlayer
	if p != null and p.playing:
		p.stop()

static func sonar_trazado(leo: Node3D) -> void:
	var p := leo.get_node_or_null("AudioTrazado") as AudioStreamPlayer
	if p != null and not p.playing:
		p.play()

static func parar_trazado(leo: Node3D) -> void:
	var p := leo.get_node_or_null("AudioTrazado") as AudioStreamPlayer
	if p != null and p.playing:
		p.stop()

static func sonar_dash(leo: Node3D) -> void:
	var p := leo.get_node_or_null("AudioDash") as AudioStreamPlayer
	if p != null:
		p.play()

static func sonar_golpe(leo: Node3D) -> void:
	var p := leo.get_node_or_null("AudioGolpe") as AudioStreamPlayer
	if p != null:
		p.play()

static func sonar_fuerza_salto(leo: Node3D) -> void:
	var p := leo.get_node_or_null("AudioFuerzaSalto") as AudioStreamPlayer
	if p != null:
		p.play()

static func sonar_fuerza_impacto(leo: Node3D) -> void:
	var p := leo.get_node_or_null("AudioFuerzaImpacto") as AudioStreamPlayer
	if p != null:
		p.play()

static func sonar_fuerza_agarre(leo: Node3D) -> void:
	var p := leo.get_node_or_null("AudioFuerzaAgarre") as AudioStreamPlayer
	if p != null:
		p.play()

static func sonar_fuerza_tirada(leo: Node3D) -> void:
	var p := leo.get_node_or_null("AudioFuerzaTirada") as AudioStreamPlayer
	if p != null:
		p.play()

static func sonar_fuerza_golpe(leo: Node3D, es_patada: bool) -> void:
	var nombre := "AudioFuerzaPatada" if es_patada else "AudioFuerzaGolpe"
	var p := leo.get_node_or_null(nombre) as AudioStreamPlayer
	if p != null:
		p.play()

# Acuática
static func preparar_sonidos_agua(leo: Node3D) -> void:
	var nado := leo.get_node_or_null("AudioNado") as AudioStreamPlayer
	if nado != null:
		nado.bus = &"Efectos"

static func sonar_golpe_agua(leo: Node3D) -> void:
	var p := leo.get_node_or_null("AudioGolpeAgua") as AudioStreamPlayer
	if p == null:
		p = leo.get_node_or_null("AudioGolpeFisico") as AudioStreamPlayer
	if p != null:
		p.play()

static func sonar_habilidad_agua(leo: Node3D) -> void:
	var p := leo.get_node_or_null("AudioHabilidadAgua") as AudioStreamPlayer
	if p != null:
		p.play()

static func sonar_golpe_combate(leo: Node3D) -> void:
	var p := leo.get_node_or_null("AudioGolpeCombate") as AudioStreamPlayer
	if p == null:
		p = leo.get_node_or_null("AudioCombate") as AudioStreamPlayer
	if p != null:
		p.play()

static func actualizar_sonido_nado(leo: Node3D, nadando: bool, rapido: bool) -> void:
	var p := leo.get_node_or_null("AudioNado") as AudioStreamPlayer
	if p == null:
		return
	if nadando:
		if not p.playing:
			p.play()
		p.pitch_scale = 1.3 if rapido else 1.0
	else:
		if p.playing:
			p.stop()

static func parar_sonido_nado(leo: Node3D) -> void:
	var p := leo.get_node_or_null("AudioNado") as AudioStreamPlayer
	if p != null and p.playing:
		p.stop()
