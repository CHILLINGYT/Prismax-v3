## controlador_leo_refactored.gd - Fase 3 - Versión modular del controlador
## Orquestador que delega a leo_modules/
## Este archivo es una DEMOSTRACIÓN de cómo quedaría el controlador después de la modularización completa
## Por ahora es un esqueleto; la migración completa es Fase 4
## El archivo original controlador_leo.gd (6066 líneas) sigue siendo el usado por el juego

class_name ControladorLeoRefactored
extends CharacterBody3D

# Módulos Fase 3
const LeoEnums = preload("res://personaje/base/scripts/leo_modules/leo_enums.gd")
const LeoConstants = preload("res://personaje/base/scripts/leo_modules/leo_constants.gd")
const LeoMovement = preload("res://personaje/base/scripts/leo_modules/leo_movement.gd")
const LeoAgua = preload("res://personaje/base/scripts/leo_modules/leo_agua.gd")
const LeoCombate = preload("res://personaje/base/scripts/leo_modules/leo_combate.gd")
const LeoVelocista = preload("res://personaje/base/scripts/leo_modules/leo_velocista.gd")
const LeoFuerza = preload("res://personaje/base/scripts/leo_modules/leo_fuerza.gd")
const LeoTransformation = preload("res://personaje/base/scripts/leo_modules/leo_transformation.gd")
const LeoMuerte = preload("res://personaje/base/scripts/leo_modules/leo_muerte.gd")
const LeoSounds = preload("res://personaje/base/scripts/leo_modules/leo_sounds.gd")

signal forma_cambiada(id: StringName)

# Forma actual - usa enum de módulo
var forma: int = LeoEnums.Forma.HUMANO
var estado: int = LeoEnums.Estado.NORMAL
var _muerte_estado: int = LeoEnums.Muerte.VIVO

# Estado humano (ejemplo de cómo se vería modular)
var h_salto_aire: bool = false
var h_agachado: bool = false

# Estado velocista
var _dir_dash: Vector3 = Vector3.ZERO
var _t_dash: float = 0.0
var _t_carga: float = 0.0

# Estado acuático
var a_nadando: bool = false
var a_turbo_t: float = 0.0

# Estado fuerza
var f_embestiendo: bool = false
var f_t_embestida: float = 0.0

# Estado combate
var c_objetivo: Node3D = null
var c_cadena: int = 0

func _ready() -> void:
	print("[LeoRefactored] Controlador modular iniciado - Forma: %s" % LeoTransformation.id_forma(forma))
	LeoSounds.configurar_sonidos_velocista(self)
	LeoSounds.preparar_sonidos_agua(self)

func _physics_process(delta: float) -> void:
	match _muerte_estado:
		LeoEnums.Muerte.VIVO:
			_procesar_vivo(delta)
		_:
			var res := LeoMuerte.procesar_muerte(self, delta, _muerte_estado, 0.0)
			_muerte_estado = res.estado

func _procesar_vivo(delta: float) -> void:
	match forma:
		LeoEnums.Forma.HUMANO:
			_procesar_humano(delta)
		LeoEnums.Forma.VELOCISTA:
			_procesar_velocista(delta)
		LeoEnums.Forma.ACUATICO:
			_procesar_acuatico(delta)
		LeoEnums.Forma.FUERZA:
			_procesar_fuerza(delta)
		LeoEnums.Forma.COMBATE:
			_procesar_combate(delta)
		LeoEnums.Forma.VUELO:
			_procesar_vuelo(delta)

# --- Humano modular ---
func _procesar_humano(delta: float) -> void:
	var dir := LeoMovement.direccion_entrada(self)
	var vel := LeoConstants.H_VEL_CAMINAR
	if Input.is_action_pressed("correr"):
		vel = LeoConstants.H_VEL_CORRER
	if h_agachado:
		vel = LeoConstants.H_VEL_AGACHADO
	
	# Movimiento con módulo
	var target_vel := dir * vel
	var current := Vector3(velocity.x, 0, velocity.z)
	current = current.move_toward(target_vel, LeoConstants.H_ACELERACION * delta if dir.length_squared() > 0.001 else LeoConstants.H_DESACELERACION * delta)
	velocity.x = current.x
	velocity.z = current.z
	
	if not is_on_floor():
		velocity.y -= LeoConstants.H_GRAVEDAD * delta
	elif velocity.y < 0.0:
		velocity.y = -0.1
	
	# Intentar escalón con módulo
	var col := get_last_slide_collision()
	if col != null and dir.length_squared() > 0.001:
		LeoMovement.intentar_escalon(self, dir, col)
	
	# Restricción agua con módulo
	var antes := global_position
	move_and_slide()
	LeoAgua.restringir_agua(self, antes)

# --- Velocista modular ---
func _procesar_velocista(delta: float) -> void:
	match estado:
		LeoEnums.Estado.NORMAL:
			var dir := LeoMovement.direccion_entrada(self)
			var nuevo_estado := LeoVelocista.procesar_normal(self, delta, dir)
			if nuevo_estado != LeoEnums.Estado.NORMAL:
				estado = nuevo_estado
				if estado == LeoEnums.Estado.DASH:
					_dir_dash = dir
					_t_dash = LeoConstants.DASH_DUR
					set_meta("dash_inicio", global_position)
					LeoSounds.sonar_dash(self)
			move_and_slide()
		LeoEnums.Estado.DASH:
			var res := LeoVelocista.procesar_dash(self, delta, _dir_dash, _t_dash)
			_t_dash = res.t
			estado = res.estado
		LeoEnums.Estado.CARGA:
			var res := LeoVelocista.procesar_carga(self, delta, _t_carga)
			_t_carga = res.t
			estado = res.estado

# --- Acuático modular ---
func _procesar_acuatico(delta: float) -> void:
	# Actualizar estado agua con módulo
	var prof := LeoAgua.profundidad_agua(self, global_position.x, global_position.z)
	a_nadando = prof > LeoConstants.PROFUNDIDAD_NADO
	
	if a_nadando:
		LeoAgua.aplicar_vertical_acuatico(self, delta, a_nadando, 0.0)
		var dir := LeoMovement.direccion_entrada(self)
		var vel := LeoConstants.A_VEL_NADO
		if Input.is_action_pressed("correr"):
			vel = LeoConstants.A_VEL_NADO_RAPIDO
		velocity.x = move_toward(velocity.x, dir.x * vel, LeoConstants.A_ACEL_NADO * delta)
		velocity.z = move_toward(velocity.z, dir.z * vel, LeoConstants.A_ACEL_NADO * delta)
		move_and_slide()
		LeoSounds.actualizar_sonido_nado(self, a_nadando, vel == LeoConstants.A_VEL_NADO_RAPIDO)
	else:
		_procesar_humano(delta) # vadea como humano

# --- Fuerza modular ---
func _procesar_fuerza(delta: float) -> void:
	if f_embestiendo:
		var dir := get_meta("embestida_dir", -global_transform.basis.z) as Vector3
		var golpeados: Array = get_meta("embestida_golpeados", []) as Array
		var res := LeoFuerza.procesar_embestida(self, delta, dir, f_t_embestida, golpeados)
		f_t_embestida = res.t
		set_meta("embestida_golpeados", res.golpeados)
		if res.terminado:
			f_embestiendo = false
			# Recuperación
		move_and_slide()
	else:
		_procesar_humano(delta)
		# Input embestida
		if Input.is_action_just_pressed("fuerza_embestida"):
			f_embestiendo = true
			f_t_embestida = LeoConstants.F_EMBESTIDA_DUR
			set_meta("embestida_dir", -global_transform.basis.z)
			set_meta("embestida_golpeados", [])
			LeoSounds.sonar_fuerza_salto(self)

# --- Combate modular ---
func _procesar_combate(delta: float) -> void:
	# FreeFlow ya está en transformacion ataque/scripts/player.gd
	# Aquí solo integración básica
	_procesar_humano(delta)

func _procesar_vuelo(_delta: float) -> void:
	# Vuelo usa su propio controlador
	pass

# --- Transformación modular ---
func _transicionar(destino: int) -> void:
	LeoTransformation.cambiar_forma_con_efecto(self, destino)
	forma = destino
	forma_cambiada.emit(LeoTransformation.id_forma(destino))

func forma_actual() -> int:
	return forma

func cuerpo_activo() -> Node3D:
	return LeoTransformation.cuerpo_activo(self)

# --- Métodos de entrada/salida (stubs para compatibilidad con LeoTransformation) ---
func _entrar_humano() -> void:
	print("[LeoRefactored] Entrar humano")
	h_agachado = false

func _detener_humano() -> void:
	pass

func _entrar_velocista() -> void:
	print("[LeoRefactored] Entrar velocista")
	estado = LeoEnums.Estado.NORMAL

func _detener_velocista() -> void:
	LeoSounds.parar_carga(self)
	LeoSounds.parar_trazado(self)

func _entrar_acuatico() -> void:
	print("[LeoRefactored] Entrar acuatico")
	a_nadando = false

func _detener_acuatico() -> void:
	LeoSounds.parar_sonido_nado(self)

func _entrar_fuerza() -> void:
	print("[LeoRefactored] Entrar fuerza")
	f_embestiendo = false

func _detener_fuerza() -> void:
	pass

func _entrar_combate() -> void:
	print("[LeoRefactored] Entrar combate")

func _detener_combate() -> void:
	pass

func _entrar_vuelo() -> void:
	print("[LeoRefactored] Entrar vuelo")

func _detener_vuelo() -> void:
	pass
