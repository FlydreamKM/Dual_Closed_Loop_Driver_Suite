/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file    pid.h
  * @brief   PID controller module header.
  ******************************************************************************
  */
/* USER CODE END Header */

#ifndef __PID_H
#define __PID_H

#ifdef __cplusplus
extern "C" {
#endif

#include <stdint.h>

typedef struct {
    float Kp;
    float Ki;
    float Kd;
    float integral;
    float prev_error;
    float output_limit;
    float integral_limit;
    float output;
    uint8_t first_run;

    /* 自适应 PID 参数 */
    uint8_t adaptive_enabled;        /* 1=开启自适应 */
    float Kp_base;                   /* 基础 Kp */
    float Ki_base;                   /* 基础 Ki */
    float Kd_base;                   /* 基础 Kd */
    float adaptive_threshold;        /* 误差阈值（rad 或 rad/s），大于此值视为大误差 */
    float Kp_max;                    /* Kp 上限 */
    float Kp_min;                    /* Kp 下限 */
    float ki_factor;                 /* Ki 调整因子 */
    float kd_factor;                 /* Kd 调整因子 */
} PID_t;

void PID_Init(PID_t *pid, float kp, float ki, float kd, float out_limit, float int_limit);
float PID_Update(PID_t *pid, float setpoint, float actual);
void PID_Reset(PID_t *pid);

/* 自适应 PID */
void PID_SetAdaptiveMode(PID_t *pid, uint8_t enabled);
void PID_ConfigureAdaptive(PID_t *pid, float threshold, float kp_max, float kp_min, float ki_factor, float kd_factor);

#ifdef __cplusplus
}
#endif

#endif /* __PID_H */
