/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file    pid.c
  * @brief   Position-type PID with anti-windup.
  ******************************************************************************
  */
/* USER CODE END Header */

#include "pid.h"

void PID_Init(PID_t *pid, float kp, float ki, float kd, float out_limit, float int_limit)
{
    pid->Kp = kp;
    pid->Ki = ki;
    pid->Kd = kd;
    pid->output_limit = out_limit;
    pid->integral_limit = int_limit;
    pid->integral = 0.0f;
    pid->prev_error = 0.0f;
    pid->output = 0.0f;
    pid->first_run = 1;

    /* 自适应默认：关闭 */
    pid->adaptive_enabled = 0;
    pid->Kp_base = kp;
    pid->Ki_base = ki;
    pid->Kd_base = kd;
    pid->adaptive_threshold = 0.5f;    /* 默认阈值 */
    pid->Kp_max = kp * 3.0f;
    pid->Kp_min = kp * 0.3f;
    pid->ki_factor = 1.0f;
    pid->kd_factor = 1.0f;
}

float PID_Update(PID_t *pid, float setpoint, float actual)
{
    float error = setpoint - actual;
    float abs_error = fabsf(error);

    if (pid->first_run) {
        pid->prev_error = error;
        pid->first_run = 0;
    }

    /* === 自适应 PID：根据误差大小动态调整增益 === */
    if (pid->adaptive_enabled && pid->Kp_base > 0.0f) {
        float kp_scale, ki_scale, kd_scale;

        if (abs_error > pid->adaptive_threshold) {
            /* 大误差：增大 Kp 快速响应，适度增大 Ki/Kd */
            kp_scale = 1.5f;
            ki_scale = 1.2f;
            kd_scale = 1.0f;
        } else {
            /* 小误差：减小 Kp 抑制超调，减小 Ki 防震荡，增大 Kd 促稳定 */
            kp_scale = 0.8f;
            ki_scale = 0.6f;
            kd_scale = 1.2f;
        }

        pid->Kp = pid->Kp_base * kp_scale;
        pid->Ki = pid->Ki_base * ki_scale * pid->ki_factor;
        pid->Kd = pid->Kd_base * kd_scale * pid->kd_factor;

        /* 限幅 */
        if (pid->Kp > pid->Kp_max) pid->Kp = pid->Kp_max;
        if (pid->Kp < pid->Kp_min) pid->Kp = pid->Kp_min;
        if (pid->Ki > pid->Kp * 2.0f) pid->Ki = pid->Kp * 2.0f;
        if (pid->Ki < 0.0f) pid->Ki = 0.0f;
    }
    /* ============================================= */

    /* Integral accumulation */
    pid->integral += error;

    /* Pre-calculate P+I for anti-windup check */
    float pre_output = pid->Kp * error + pid->Ki * pid->integral;

    /* Anti-windup: clamp integral if output is already saturated */
    if (pre_output > pid->output_limit) {
        pid->integral -= error;
        if (pid->integral > pid->integral_limit) {
            pid->integral = pid->integral_limit;
        }
        pre_output = pid->output_limit;
    } else if (pre_output < -pid->output_limit) {
        pid->integral -= error;
        if (pid->integral < -pid->integral_limit) {
            pid->integral = -pid->integral_limit;
        }
        pre_output = -pid->output_limit;
    }

    /* Integral limit (final guard) */
    if (pid->integral > pid->integral_limit) {
        pid->integral = pid->integral_limit;
    } else if (pid->integral < -pid->integral_limit) {
        pid->integral = -pid->integral_limit;
    }

    /* Re-calculate P+I after integral clamping */
    pre_output = pid->Kp * error + pid->Ki * pid->integral;

    /* Derivative */
    float derivative = error - pid->prev_error;
    pid->prev_error = error;

    pid->output = pre_output + pid->Kd * derivative;

    /* Output limit */
    if (pid->output > pid->output_limit) {
        pid->output = pid->output_limit;
    } else if (pid->output < -pid->output_limit) {
        pid->output = -pid->output_limit;
    }

    return pid->output;
}

void PID_SetAdaptiveMode(PID_t *pid, uint8_t enabled)
{
    pid->adaptive_enabled = enabled;

    if (!enabled) {
        /* 关闭自适应时恢复基准参数 */
        pid->Kp = pid->Kp_base;
        pid->Ki = pid->Ki_base;
        pid->Kd = pid->Kd_base;
    }
}

void PID_ConfigureAdaptive(PID_t *pid, float threshold, float kp_max, float kp_min, float ki_factor, float kd_factor)
{
    if (threshold > 0.0f)    pid->adaptive_threshold = threshold;
    if (kp_max > pid->Kp_min) pid->Kp_max = kp_max;
    if (kp_min > 0.0f && kp_min < pid->Kp_max) pid->Kp_min = kp_min;
    if (ki_factor > 0.0f)    pid->ki_factor = ki_factor;
    if (kd_factor > 0.0f)    pid->kd_factor = kd_factor;
}

void PID_Reset(PID_t *pid)
{
    pid->integral = 0.0f;
    pid->prev_error = 0.0f;
    pid->output = 0.0f;
    pid->first_run = 1;
}
