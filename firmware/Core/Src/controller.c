/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file    controller.c
  * @brief   Motion controller with trapezoidal trajectory and cascaded PID.
  *
  * Control period: 1 ms (1 kHz).
  ******************************************************************************
  */
/* USER CODE END Header */

#include "controller.h"
#include <math.h>

#define CONTROL_DT_MS   1.0f
#define CONTROL_DT_S    0.001f
#define POS_DEADBAND    0.01f   /* rad, ~0.57 deg */
#define SPEED_DEADBAND  0.1f    /* rad/s */

static void TrajectoryPlanner(MotorController_t *ctrl)
{
    if (ctrl->mode == MODE_POSITION) {
        /* 简化：直接设置目标角度，不做梯形规划（取消加减速度特性） */
        ctrl->traj_angle = ctrl->target_angle;
        ctrl->traj_speed = 0.0f;
    } else {
        /* 速度模式：直接跟踪目标速度，不再限幅（取消加减速度特性） */
        ctrl->traj_speed = ctrl->target_speed;
    }
}

void Controller_Init(MotorController_t *ctrl, Encoder_t *enc, Motor_t *motor)
{
    ctrl->encoder = enc;
    ctrl->motor = motor;
    ctrl->mode = MODE_SPEED;
    ctrl->state = STATE_IDLE;
    ctrl->target_speed = 0.0f;
    ctrl->target_angle = 0.0f;
    ctrl->accel = 10.0f;    /* default 10 rad/s^2 */
    ctrl->decel = 10.0f;
    ctrl->traj_speed = 0.0f;
    ctrl->traj_angle = 0.0f;
    ctrl->actual_speed = 0.0f;
    ctrl->actual_angle = 0.0f;
    ctrl->pwm_output = 0;
    ctrl->fault_code = FAULT_NONE;
    ctrl->enabled = 0;
    ctrl->homing_done = 0;
    ctrl->braking = 0;
    ctrl->brake_pwm = 0;
    ctrl->brake_initial_speed = 0.0f;

    /* 校准字段初始化 */
    ctrl->calibrated = 0;
    ctrl->calib_phase = 0;
    ctrl->calib_start_angle = 0.0f;
    ctrl->calib_fwd_limit = 0.0f;
    ctrl->calib_bwd_limit = 0.0f;
    ctrl->calib_tick = 0;

    PID_Init(&ctrl->speed_pid, 18.0f, 0.5f, 7.0f, 1000.0f, 300.0f);
    PID_Init(&ctrl->pos_pid,  40.0f, 0.0f, 1.0f, 100.0f,  50.0f);
}

void Controller_SetMode(MotorController_t *ctrl, ControlMode_t mode)
{
    if (ctrl->state == STATE_EMERGENCY) return;
    if (ctrl->mode == mode) return;   /* 模式未变：不重置 PID，不清零 traj_speed，避免刹车 */
    ctrl->mode = mode;
    PID_Reset(&ctrl->speed_pid);
    PID_Reset(&ctrl->pos_pid);
    /* 模式切换时保持当前 traj_speed，让轨迹自然过渡，不强制刹车 */
    if (mode == MODE_POSITION) {
        ctrl->traj_angle = ctrl->actual_angle;  /* 位置模式起点对齐当前实际位置，避免跳变 */
    }
}

void Controller_SetTarget(MotorController_t *ctrl, float speed, float angle, float accel, float decel)
{
    if (ctrl->state == STATE_EMERGENCY) return;
    ctrl->target_speed = speed;
    if (ctrl->mode == MODE_POSITION) {
        ctrl->target_angle = angle;
    }
    if (accel > 0.0f) ctrl->accel = accel;
    if (decel > 0.0f) ctrl->decel = decel;
}

void Controller_SetSpeedPID(MotorController_t *ctrl, float kp, float ki, float kd)
{
    PID_Init(&ctrl->speed_pid, kp, ki, kd, 1000.0f, 500.0f);
}

void Controller_SetPosPID(MotorController_t *ctrl, float kp, float ki, float kd)
{
    PID_Init(&ctrl->pos_pid, kp, ki, kd, 100.0f, 50.0f);
}

void Controller_Enable(MotorController_t *ctrl)
{
    ctrl->enabled = 1;
    Motor_Enable(ctrl->motor);
    if (ctrl->state == STATE_IDLE || ctrl->state == STATE_FAULT) {
        ctrl->state = STATE_RUNNING;
        ctrl->fault_code = FAULT_NONE;
    }
}

void Controller_Disable(MotorController_t *ctrl)
{
    ctrl->enabled = 0;
    Motor_Disable(ctrl->motor);
    ctrl->state = STATE_IDLE;
    ctrl->traj_speed = 0.0f;
    ctrl->braking = 0;
    ctrl->brake_pwm = 0;
    PID_Reset(&ctrl->speed_pid);
    PID_Reset(&ctrl->pos_pid);
}

void Controller_EmergencyStop(MotorController_t *ctrl)
{
    Motor_EmergencyStop(ctrl->motor);
    ctrl->state = STATE_EMERGENCY;
    ctrl->traj_speed = 0.0f;
    ctrl->enabled = 0;
    ctrl->braking = 0;
    ctrl->brake_pwm = 0;
}

void Controller_ClearEmergency(MotorController_t *ctrl)
{
    Motor_ClearEmergency(ctrl->motor);
    ctrl->state = STATE_IDLE;
    ctrl->fault_code = FAULT_NONE;
    ctrl->braking = 0;
    ctrl->brake_pwm = 0;
    PID_Reset(&ctrl->speed_pid);
    PID_Reset(&ctrl->pos_pid);
}

void Controller_Home(MotorController_t *ctrl)
{
    if (ctrl->state == STATE_EMERGENCY) return;
    Encoder_Reset(ctrl->encoder);
    ctrl->traj_angle = 0.0f;
    ctrl->traj_speed = 0.0f;
    ctrl->target_angle = 0.0f;
    ctrl->actual_angle = 0.0f;
    ctrl->homing_done = 1;
    ctrl->braking = 0;
    ctrl->brake_pwm = 0;
    PID_Reset(&ctrl->speed_pid);
    PID_Reset(&ctrl->pos_pid);
    Motor_SetOutput(ctrl->motor, 0);
}

void Controller_Update(MotorController_t *ctrl)
{
    /* Update encoder -> actual_speed / actual_angle */
    Encoder_Update(ctrl->encoder);
    ctrl->actual_speed = ctrl->encoder->actual_speed;
    ctrl->actual_angle = ctrl->encoder->actual_angle;

    if (ctrl->state == STATE_EMERGENCY || ctrl->state == STATE_IDLE || !ctrl->enabled) {
        Motor_SetOutput(ctrl->motor, 0);
        ctrl->pwm_output = 0;
        return;
    }

    /* ---- 校准模式处理（屏蔽其他控制命令） ---- */
    if (ctrl->state == STATE_CALIBRATING) {
        float pwm = PID_Update(&ctrl->speed_pid, ctrl->traj_speed, ctrl->actual_speed);
        ctrl->pwm_output = (int16_t)pwm;
        Motor_SetOutput(ctrl->motor, ctrl->pwm_output);
        Controller_CalibrateUpdate(ctrl);
        return;
    }

    /* ---- Dynamic braking with zero-crossing lockout ---- */
    if (ctrl->braking) {
        /* Check if speed has crossed zero or is very close to stop */
        if ((ctrl->brake_initial_speed > 0.0f && ctrl->actual_speed <= SPEED_DEADBAND) ||
            (ctrl->brake_initial_speed < 0.0f && ctrl->actual_speed >= -SPEED_DEADBAND) ||
            (fabsf(ctrl->actual_speed) < SPEED_DEADBAND)) {
            /* Speed has reached zero: release brake, hold position */
            ctrl->braking = 0;
            ctrl->brake_pwm = 0;
            ctrl->traj_speed = 0.0f;
            ctrl->target_speed = 0.0f;
            if (ctrl->mode == MODE_POSITION) {
                ctrl->traj_angle = ctrl->actual_angle;
                ctrl->target_angle = ctrl->actual_angle;
            }
            PID_Reset(&ctrl->speed_pid);
            PID_Reset(&ctrl->pos_pid);
            Motor_SetOutput(ctrl->motor, 0);
            ctrl->pwm_output = 0;
            return;
        }

        /* Continue braking: apply opposite PWM based on current speed direction */
        int16_t pwm = ctrl->brake_pwm;
        if (ctrl->actual_speed > 0.0f) {
            pwm = -ctrl->brake_pwm;
        } else if (ctrl->actual_speed < 0.0f) {
            pwm = ctrl->brake_pwm;
        } else {
            pwm = 0;
        }
        Motor_Brake(ctrl->motor, pwm);
        ctrl->pwm_output = pwm;
        return;
    }

    /* Trajectory generation */
    TrajectoryPlanner(ctrl);

    float speed_setpoint = ctrl->traj_speed;

    if (ctrl->mode == MODE_POSITION) {
        /* Outer position loop -> speed correction */
        float pos_out = PID_Update(&ctrl->pos_pid, ctrl->traj_angle, ctrl->actual_angle);
        speed_setpoint += pos_out;
    }

    /* Inner speed loop -> PWM */
    float pwm = PID_Update(&ctrl->speed_pid, speed_setpoint, ctrl->actual_speed);

    ctrl->pwm_output = (int16_t)pwm;
    Motor_SetOutput(ctrl->motor, ctrl->pwm_output);
}

/* === 校准模式（任务3） === */
#define CALIBRATION_SPEED_FWD   2.0f    /* rad/s 正向校准速度 */
#define CALIBRATION_SPEED_BWD   -2.0f   /* rad/s 反向校准速度 */
#define CALIBRATION_TIME_FWD    5000    /* 正向行程时间 (ms) */
#define CALIBRATION_TIME_BWD    5000    /* 反向行程时间 (ms) */

void Controller_StartCalibration(MotorController_t *ctrl)
{
    if (!ctrl->enabled) return;

    ctrl->state = STATE_CALIBRATING;
    ctrl->calibrated = 0;
    ctrl->calib_phase = 0;
    ctrl->calib_start_angle = ctrl->actual_angle;
    ctrl->calib_fwd_limit = 0.0f;
    ctrl->calib_bwd_limit = 0.0f;
    ctrl->calib_tick = 0;

    PID_Reset(&ctrl->speed_pid);
    PID_Reset(&ctrl->pos_pid);
    ctrl->traj_speed = 0.0f;
    ctrl->traj_angle = ctrl->actual_angle;
    ctrl->target_speed = CALIBRATION_SPEED_FWD;
}

void Controller_StopCalibration(MotorController_t *ctrl)
{
    if (ctrl->state == STATE_CALIBRATING) {
        ctrl->state = STATE_IDLE;
        ctrl->traj_speed = 0.0f;
        ctrl->target_speed = 0.0f;
        Motor_SetOutput(ctrl->motor, 0);
        ctrl->pwm_output = 0;
        PID_Reset(&ctrl->speed_pid);
        PID_Reset(&ctrl->pos_pid);
    }
}

uint8_t Controller_IsCalibrated(MotorController_t *ctrl)
{
    return ctrl->calibrated;
}

uint8_t Controller_GetCalibrationProgress(MotorController_t *ctrl)
{
    return ctrl->calib_phase;
}

/* 校准状态机更新，在 Controller_Update 中被调用 */
static void Controller_CalibrateUpdate(MotorController_t *ctrl)
{
    ctrl->calib_tick++;

    switch (ctrl->calib_phase) {
        case 0:
            /* 正向运动，记录最大角度 */
            ctrl->traj_speed = ctrl->target_speed;  /* 直接赋值，无限幅 */
            if (ctrl->actual_angle > ctrl->calib_fwd_limit) {
                ctrl->calib_fwd_limit = ctrl->actual_angle;
            }
            if (ctrl->calib_tick >= CALIBRATION_TIME_FWD) {
                ctrl->calib_phase = 1;
                ctrl->calib_tick = 0;
                ctrl->target_speed = CALIBRATION_SPEED_BWD;
                PID_Reset(&ctrl->speed_pid);
            }
            break;

        case 1:
            /* 反向运动，记录最小角度 */
            ctrl->traj_speed = ctrl->target_speed;
            if (ctrl->actual_angle < ctrl->calib_bwd_limit) {
                ctrl->calib_bwd_limit = ctrl->actual_angle;
            }
            if (ctrl->calib_tick >= CALIBRATION_TIME_BWD) {
                ctrl->calib_phase = 2;
                ctrl->calib_tick = 0;
                ctrl->traj_speed = 0.0f;
                ctrl->target_speed = 0.0f;
                ctrl->calibrated = 1;
                ctrl->state = STATE_IDLE;
                Motor_SetOutput(ctrl->motor, 0);
                ctrl->pwm_output = 0;
                PID_Reset(&ctrl->speed_pid);
                PID_Reset(&ctrl->pos_pid);

                /* 如果限位范围合理，将零点设为中间位置 */
                float range = ctrl->calib_fwd_limit - ctrl->calib_bwd_limit;
                if (range > 0.1f) {
                    /* 将编码器零点偏移到行程中点，使实际角度反映相对行程中央的位置 */
                    float mid_angle = (ctrl->calib_fwd_limit + ctrl->calib_bwd_limit) * 0.5f;
                    ctrl->encoder->total_count = (int32_t)(mid_angle / ctrl->encoder->angle_per_count);
                    ctrl->encoder->actual_angle = 0.0f;
                    ctrl->traj_angle = 0.0f;
                    ctrl->target_angle = 0.0f;
                }
            }
            break;

        case 2:
        default:
            break;
    }
}

void Controller_Brake(MotorController_t *ctrl, int16_t brake_pwm)
{
    if (ctrl->state == STATE_EMERGENCY || ctrl->state == STATE_IDLE || !ctrl->enabled) {
        Motor_SetOutput(ctrl->motor, 0);
        ctrl->pwm_output = 0;
        ctrl->braking = 0;
        ctrl->brake_pwm = 0;
        return;
    }

    if (brake_pwm <= 0) {
        /* brake_pwm = 0 means release brake */
        ctrl->braking = 0;
        ctrl->brake_pwm = 0;
        return;
    }

    /* Record initial speed direction for zero-crossing detection */
    ctrl->brake_initial_speed = ctrl->actual_speed;
    ctrl->brake_pwm = brake_pwm;
    ctrl->braking = 1;

    PID_Reset(&ctrl->speed_pid);
    PID_Reset(&ctrl->pos_pid);
    ctrl->traj_speed = 0.0f;
    ctrl->target_speed = 0.0f;

    /* First brake pulse: apply opposite PWM based on current speed direction */
    int16_t pwm = brake_pwm;
    if (ctrl->actual_speed > 0.0f) {
        pwm = -brake_pwm;
    } else if (ctrl->actual_speed < 0.0f) {
        pwm = brake_pwm;
    } else {
        pwm = 0;
        ctrl->braking = 0;  /* already stopped, no need to brake */
    }

    Motor_Brake(ctrl->motor, pwm);
    ctrl->pwm_output = pwm;
}
