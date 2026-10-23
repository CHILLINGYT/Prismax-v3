## leo_constants.gd - Fase 3 - Constantes extraídas de controlador_leo.gd
## Agrupa constantes por forma para modularización

class_name LeoConstants

# ------------------------------------------------------------------ Humano
const H_VEL_CAMINAR := 3.0
const H_VEL_CORRER := 5.5
const H_ACELERACION := 40.0
const H_DESACELERACION := 50.0
const H_GRAVEDAD := 24.0
const H_SALTO := 7.5
const H_VELOCIDAD_SALTO_CORRIENDO := 3.5
const H_UMBRAL_MOVIMIENTO := 0.15
const H_MEZCLA := 0.15
const H_VEL_AGACHADO := 2.5
const H_ALTURA_AGACHADO := 0.7
const H_MEZCLA_AGACHARSE := 0.25
const ALTURA_ESCALON := 0.26
const AVANCE_ESCALON := 0.40

# ------------------------------------------------------------------ Agua
const PROFUNDIDAD_VADEO := 0.55
const PROFUNDIDAD_NADO := 0.95
const SUPERFICIE_MAR := -2.05
const BLEND_AGUA := 0.22
const A_VEL_NADO := 4.6
const A_ACEL_NADO := 6.0
const A_GIRO_ACUATICO := 12.0
const A_VEL_VERTICAL_NADO := 3.2
const A_FLOTABILIDAD := 9.0
const A_CALADO_FLOTANDO := 1.05
const A_AMORTIGUA_VERTICAL := 4.0
const A_VEL_NADO_RAPIDO := 9.2
const A_ACEL_NADO_RAPIDO := 9.0
const A_FRENO_NADO_RAPIDO := 6.5

# Combate acuático
const A_GOLPE_ALCANCE := 1.1
const A_GOLPE_RADIO := 0.7
const A_GOLPE_ALTURA := 1.2
const A_GOLPE_DANIO := 20.0
const A_GOLPE_EMPUJE := 4.0
const A_GOLPE_ATURDIMIENTO := 0.25
const A_GOLPE_CAIDA := 0.4
const A_GOLPE_ARRIBA := 0.3
const A_COMBO_VENTANA := 0.45
const ANIM_A_ATTACK_2 := "attack_2"
const A_GOLPE_IMPACTO_U := 0.54
const A_GOLPE2_IMPACTO_U := 0.55
const A_MAREA_IMPACTOS := 3
const A_EMPAPADO_DURACION := 5.0
const A_EMPAPADO_MULT := 1.05
const A_VFX_GOLPE := 0.9
const A_VFX_MAREA_RADIO := 1.0
const A_VFX_MAREA_FUERZA := 1.35

# Turbo acuático
const A_TURBO_VELOCIDAD := 14.0
const A_TURBO_DURACION := 1.25
const A_TURBO_ENFRIAMIENTO := 4.0
const A_TURBO_ACEL := 18.0
const A_T_ENTRADA_AGUA := 1.50
const A_T_SALIDA_AGUA := 1.40
const E_VEL_ESCALERA := 1.35
const TEXTO_SIN_AGUA := "Solo puedes ingresar al agua con el personaje acuatico"
const AVISO_AGUA_DURACION := 2.5
const MARGEN_ESCALON := 0.12
const DESNIVEL_MINIMO := 0.02

# ------------------------------------------------------------------ Fuerza
const F_VEL_CAMINAR := 1.6
const F_VEL_CORRER := 4.0
const F_ACELERACION := 12.0
const F_DESACELERACION := 16.0
const F_GRAVEDAD := 25.0
const F_SALTO := 6.5
const F_SUPER_CARGA_MIN := 0.25
const F_SUPER_CARGA_MAX := 1.4
const F_SUPER_VEL_MIN := 8.0
const F_SUPER_VEL_MAX := 21.0
const F_SUPER_IMPULSO := 2.0
const F_SUPER_SACUDIDA := 0.45
const F_SUPER_CAIDA_CAMARA := 0.28
const F_SUPER_TEMBLOR := 0.035
const F_SUPER_BARRA_LARGO := 220.0
const F_SUPER_BARRA_ALTO := 16.0
const F_EMBESTIDA_VEL := 7.0
const F_EMBESTIDA_DUR := 0.5
const F_EMBESTIDA_DANIO := 35.0
const F_EMBESTIDA_RADIO := 1.6
const F_EMBESTIDA_RECUP := 0.3
const F_SLAM_VEL := 45.0
const F_SLAM_DANIO := 30.0 / 0.61
const F_SLAM_RADIO := 4.5
const F_SLAM_RECUP := 0.35
const F_DANIO_ENTREGADO := 30.0
const F_CAIDA_IMPACTO := 0.61
const F_DANIO_ESTANDAR := F_DANIO_ENTREGADO / F_CAIDA_IMPACTO
const F_PUNIO_DANIO := F_DANIO_ESTANDAR
const F_PATADA_DANIO := F_DANIO_ESTANDAR * 1.2
const F_GOLPE_ALCANCE := 1.1
const F_GOLPE_RADIO := 0.7
const F_GOLPE_ALTURA := 1.2
const F_PATADA_ALTURA := 0.9
const F_COMBO_VENTANA := 0.45
const F_ROCA_TAM := 0.8
const F_ROCA_VEL := 17.0
const F_ROCA_DANIO := 80.0
const F_ROCA_RADIO := 3.0
const F_ROCA_CARRY_H := 1.13
const F_ROCA_Z0 := 0.62
const F_ROCA_U_SUBIDA := 0.55
const F_ROCA_U_FIN := 0.90
const F_ROCA_GUARDA := 0.25
const F_ROCA_SWAY := 0.008
const F_ROCA_POLO_SALIDA := 2.2
const F_ROCA_POLO_ABAJO := 0.0
const F_ROCA_POLO_ATRAS := 0.2
const F_MIRA_LARGO := 11.0
const F_MIRA_GROSOR := 2.0
const F_MIRA_HUECO := 5.0
const F_MIRA_PUNTO := 3.0
const F_MIRA_ALCANCE := 60.0

# ------------------------------------------------------------------ Velocista
const VEL_MAX := 7.0
const VEL_ACEL := 45.0
const VEL_DESACEL := 55.0
const VEL_GRAVEDAD := 24.0
const VEL_SALTO := 7.5
const DASH_DIST := 10.0
const DASH_DUR := 0.09
const DASH_OBJETIVO := 9.0
const VEL_TRAYECTO_MAX := 60.0
const VEL_TRAYECTO_MIN := 34.0

# ------------------------------------------------------------------ Combate
const C_VEL_CAMINAR := 6.0
const C_ACELERACION := 30.0
const C_DESACELERACION := 40.0
const C_GRAVEDAD := 22.0
const C_SALTO := 7.0
const C_DOBLE_SALTO := 6.0

# ------------------------------------------------------------------ Muerte
const MUERTE_ESPERA_FUNDIDO := 1.1

# ------------------------------------------------------------------ Audio dB
const AUD_GOLPE_FISICO_DB := 0.0
const AUD_GOLPE_AGUA_DB := -5.0
const AUD_NADO_DB := -7.0
const AUD_HABILIDAD_DB := -4.0
const AUD_COMBATE_DB := 0.0

# ------------------------------------------------------------------ Mapas Mixamo
const MAPA_MIXAMO_MANIQUE := {
	"mixamorig_Hips": "Hips",
	"mixamorig_Spine": "Spine",
	"mixamorig_Spine1": "Chest",
	"mixamorig_Spine2": "UpperChest",
	"mixamorig_Neck": "Neck",
	"mixamorig_Head": "Head",
	"mixamorig_LeftShoulder": "LeftShoulder",
	"mixamorig_LeftArm": "LeftUpperArm",
	"mixamorig_LeftForeArm": "LeftLowerArm",
	"mixamorig_LeftHand": "LeftHand",
	"mixamorig_RightShoulder": "RightShoulder",
	"mixamorig_RightArm": "RightUpperArm",
	"mixamorig_RightForeArm": "RightLowerArm",
	"mixamorig_RightHand": "RightHand",
	"mixamorig_LeftUpLeg": "LeftUpperLeg",
	"mixamorig_LeftLeg": "LeftLowerLeg",
	"mixamorig_LeftFoot": "LeftFoot",
	"mixamorig_RightUpLeg": "RightUpperLeg",
	"mixamorig_RightLeg": "RightLowerLeg",
	"mixamorig_RightFoot": "RightFoot",
}

# Clips por forma
const ANIM_H_IDLE := "idle"
const ANIM_H_WALK := "walk"
const ANIM_H_RUN := "fast_run"
const ANIM_H_SALTO := "jump_up"
const ANIM_H_SALTO_CORRIENDO := "running_jump"
const ANIM_H_CROUCH_WALK := "crouch_walk"
const ANIM_H_CROUCH_IDLE := "crouch_idle"

const ANIM_A_IDLE := "idle_stand"
const ANIM_A_WALK := "walk"
const ANIM_A_RUN := "run"
const ANIM_A_JUMP := "jump"
const ANIM_A_FALL := "fall"
const ANIM_A_ATTACK := "attack"
const ANIM_A_SWIM_IDLE := "swim_idle"
const ANIM_A_SWIM_FORWARD := "swim_forward"
const ANIM_A_ENTER_WATER := "enter_water"
const ANIM_A_EXIT_WATER := "exit_water"
const ANIM_A_CLIMB := "climb_ladder"

const ANIM_F_IDLE := "Idle"
const ANIM_F_WALK := "Walk"
const ANIM_F_RUN := "Run"
const ANIM_F_JUMP := "Jump"
const ANIM_F_FALL := "Fall"
const ANIM_F_PUNCH_L := "Punch_Left"
const ANIM_F_PUNCH_R := "Punch_Right"
const ANIM_F_KICK := "Kick"
const ANIM_F_AIRSLAM := "AirSlam"
const ANIM_F_SLAMIMPACT := "SlamImpact"
const ANIM_F_ROCKLIFT := "RockLift"
const ANIM_F_ROCKCARRY := "RockCarry"
const ANIM_F_ROCKTHROW := "RockThrow"
const ANIM_F_SUPERJUMP := "SuperJump"
const ANIM_F_SHOULDERPREP := "ShoulderPrep"
const ANIM_F_SHOULDERRUN := "ShoulderRun"
const ANIM_F_SHOULDERECOVER := "ShoulderRecover"

const ANIM_C_IDLE := "combat_idle"
const ANIM_C_WALK := "walk"
const ANIM_C_JUMP := "jump"

# Velocista clips
const ANIM_INACTIVO := "inactivo"
const ANIM_ADELANTE := "caminar_hacia_adelante"
const ANIM_ATRAS := "caminar_hacia_atras"
const ANIM_CARGA := "cargar_poder_click-derecho"
const ANIM_DASH := "dash-con-shift"
const ANIM_SUPERVELOCIDAD := "superduper_velocidad"
const ANIM_COMBO_1 := "combo-1"
const ANIM_COMBO_2 := "combo-2"
const ANIM_COMBO_3 := "combo-3"
const ANIM_COMBO_4 := "combo-4"
