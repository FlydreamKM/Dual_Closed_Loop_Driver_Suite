/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file    app.c
  * @brief   Application layer: hardware init, command dispatch, status feedback.
  *
  * Motor mapping (per AGENTS.md):
  *   Motor 1 : TIM2 encoder, TIM4 PWM (PB6), PB7 direction
  *   Motor 2 : TIM1 encoder, TIM3 PWM (PA6), PA5 direction
  ******************************************************************************
  */
/* USER CODE END Header */

#include "app.h"
#include "main.h"
#include <string.h>
#include <stdio.h>

/* HAL handles declared in main.c */
extern TIM_HandleTypeDef htim1;
extern TIM_HandleTypeDef htim2;
extern TIM_HandleTypeDef htim3;
extern TIM_HandleTypeDef htim4;
extern UART_HandleTypeDef huart2;

App_t g_app;
volatile uint8_t g_app_initialized = 0;

static void App_ProcessCommand(ProtocolCmd_t *cmd);

void App_Init(void)
{
    memset(&g_app, 0, sizeof(g_app));

    /* --- Adjust PWM frequency to ~20 kHz (ARR = 1799) ------------------- */
    __HAL_TIM_SET_AUTORELOAD(&htim3, 1799);
    __HAL_TIM_SET_AUTORELOAD(&htim4, 1799);
    __HAL_TIM_SET_COMPARE(&htim3, TIM_CHANNEL_1, 0);
    __HAL_TIM_SET_COMPARE(&htim4, TIM_CHANNEL_1, 0);

    /* --- Enable encoder update interrupts (overflow tracking) ----------- */
    __HAL_TIM_ENABLE_IT(&htim1, TIM_IT_UPDATE);
    __HAL_TIM_ENABLE_IT(&htim2, TIM_IT_UPDATE);

    /* --- Motor / Encoder / Controller init ------------------------------ */
    /* Motor 1: TIM2 enc, TIM4 PWM, PB7 dir */
    Encoder_Init(&g_app.encoder[0], &htim2);
    Motor_Init(&g_app.motor[0], &htim4, TIM_CHANNEL_1, GPIOB, GPIO_PIN_7, 1000);
    Controller_Init(&g_app.controller[0], &g_app.encoder[0], &g_app.motor[0]);

    /* Motor 2: TIM1 enc, TIM3 PWM, PA5 dir */
    Encoder_Init(&g_app.encoder[1], &htim1);
    g_app.encoder[1].invert = -1;   /* 电机2镜像安装，反转编码器计数方向 */
    Motor_Init(&g_app.motor[1], &htim3, TIM_CHANNEL_1, GPIOA, GPIO_PIN_5, 1000);
    Controller_Init(&g_app.controller[1], &g_app.encoder[1], &g_app.motor[1]);

    /* --- Protocol init -------------------------------------------------- */
    Protocol_Init(&g_app.protocol, &huart2);

    g_app.status_interval_ms = 10;  /* binary STATUS auto-send 100 Hz */
    g_app.vofa_interval_ms = 0;     /* JustFloat disabled（binary-only 模式） */

    /* --- Startup UART debug message (blocking, no DMA dependency) ----- */
    {
        const char *boot_msg =
            "\r\n========================================\r\n"
            "[BOOT] Dual Closed-LOOP Driver started.\r\n"
            "[BOOT] UART2 OK. Baud=115200 8N1.\r\n"
            "[BOOT] Waiting for commands...\r\n"
            "========================================\r\n";
        HAL_UART_Transmit(&huart2, (uint8_t *)boot_msg, strlen(boot_msg), 300);
    }

    g_app_initialized = 1;
}

static void App_ProcessCommand(ProtocolCmd_t *cmd)
{
    uint8_t motor_mask = 0;
    if (cmd->motor_id == MOTOR_ID_1)      motor_mask = 0x01;
    else if (cmd->motor_id == MOTOR_ID_2) motor_mask = 0x02;
    else if (cmd->motor_id == MOTOR_ID_BOTH) motor_mask = 0x03;

    /* 校验模式下屏蔽除 STOP 外的所有命令 */
    uint8_t skip_calib_block = 0;
    for (int i = 0; i < MOTOR_NUM; i++) {
        if (g_app.controller[i].state == STATE_CALIBRATING) {
            if (cmd->cmd != CMD_CALIBRATE || cmd->data.control.ctrl_cmd != 1) {
                skip_calib_block = 1;
            }
            break;
        }
    }

    for (int i = 0; i < MOTOR_NUM; i++) {
        if (!(motor_mask & (1 << i))) continue;
        MotorController_t *ctrl = &g_app.controller[i];

        switch (cmd->cmd) {
            case CMD_SET_TARGET:
                /* 任务5: SET_TARGET 重置 PID 积分和轨迹速度 */
                if (ctrl->braking) {
                    ctrl->braking = 0;
                    ctrl->brake_pwm = 0;
                }
                PID_Reset(&ctrl->speed_pid);
                PID_Reset(&ctrl->pos_pid);
                ctrl->traj_speed = 0.0f;
                Controller_SetMode(ctrl, (ControlMode_t)cmd->data.target.mode);
                Controller_SetTarget(ctrl,
                                     cmd->data.target.target_speed,
                                     cmd->data.target.target_angle,
                                     cmd->data.target.accel,
                                     cmd->data.target.decel);
                break;

            case CMD_SET_PID:
                if (ctrl->braking) {
                    ctrl->braking = 0;
                    ctrl->brake_pwm = 0;
                }
                if (cmd->data.pid.pid_type == 0) {
                    Controller_SetSpeedPID(ctrl, cmd->data.pid.kp,
                                           cmd->data.pid.ki, cmd->data.pid.kd);
                } else {
                    Controller_SetPosPID(ctrl, cmd->data.pid.kp,
                                         cmd->data.pid.ki, cmd->data.pid.kd);
                }
                break;

            case CMD_SET_PID_BOTH:
                {
                    MotorController_t *ctrl0 = &g_app.controller[0];
                    MotorController_t *ctrl1 = &g_app.controller[1];
                    if (cmd->data.pid.pid_type == 0) {
                        Controller_SetSpeedPID(ctrl0, cmd->data.pid.kp,
                                               cmd->data.pid.ki, cmd->data.pid.kd);
                        Controller_SetSpeedPID(ctrl1, cmd->data.pid.kp,
                                               cmd->data.pid.ki, cmd->data.pid.kd);
                    } else {
                        Controller_SetPosPID(ctrl0, cmd->data.pid.kp,
                                             cmd->data.pid.ki, cmd->data.pid.kd);
                        Controller_SetPosPID(ctrl1, cmd->data.pid.kp,
                                             cmd->data.pid.ki, cmd->data.pid.kd);
                    }
                }
                break;

            case CMD_CALIBRATE:
                if (cmd->data.control.ctrl_cmd == 0) {
                    /* 启动校准 */
                    Controller_StartCalibration(ctrl);
                    Protocol_SendAck(&g_app.protocol, CMD_CALIBRATE, 0);
                } else if (cmd->data.control.ctrl_cmd == 1) {
                    /* 停止校准 */
                    Controller_StopCalibration(ctrl);
                    Protocol_SendAck(&g_app.protocol, CMD_CALIBRATE, 1);
                }
                break;

            case CMD_CONTROL:
                if (skip_calib_block) break;
                switch (cmd->data.control.ctrl_cmd) {
                    case CTRL_ENABLE:
                        Controller_Enable(ctrl);
                        break;
                    case CTRL_DISABLE:
                        Controller_Disable(ctrl);
                        break;
                    case CTRL_HOME:
                        Controller_Home(ctrl);
                        break;
                    case CTRL_EMERGENCY:
                        Controller_EmergencyStop(ctrl);
                        break;
                    case CTRL_CLEAR_FAULT:
                        Controller_ClearEmergency(ctrl);
                        break;
                    case CTRL_BRAKE:
                        Controller_Brake(ctrl, cmd->data.control.brake_pwm);
                        break;
                }
                break;
        }
    }

    if (cmd->cmd == CMD_SET_VOFA) {
        g_app.vofa_interval_ms = cmd->data.vofa.interval_ms;
    }

    if (cmd->cmd == CMD_REQ_STATUS) {
        for (int i = 0; i < MOTOR_NUM; i++) {
            if (!(motor_mask & (1 << i))) continue;
            MotorController_t *ctrl = &g_app.controller[i];
            uint8_t mode_state = (ctrl->mode & 0x0F) | ((ctrl->state & 0x0F) << 4);
            Protocol_SendStatus(&g_app.protocol, i, mode_state,
                                ctrl->actual_speed, ctrl->actual_angle,
                                ctrl->traj_speed, ctrl->traj_angle,
                                ctrl->pwm_output, ctrl->encoder->total_count,
                                ctrl->fault_code);
        }
    }

    if (cmd->cmd == CMD_HEARTBEAT) {
        Protocol_SendAck(&g_app.protocol, CMD_HEARTBEAT, 0);
    }
}

/* 检查队列后续是否还有同电机的 CMD_SET_TARGET（尾部去重） */
static uint8_t App_HasLaterSetTarget(uint8_t read_idx, uint8_t motor_id)
{
    uint8_t r = read_idx;
    while (r != g_app.protocol.cmd_write_idx) {
        ProtocolCmd_t *pcmd = &g_app.protocol.cmd_queue[r];
        if (pcmd->cmd == CMD_SET_TARGET && pcmd->motor_id == motor_id) {
            return 1;
        }
        r = (r + 1) % PROTOCOL_CMD_QUEUE_SIZE;
    }
    return 0;
}

void App_ControlUpdate(void)
{
    g_app.control_tick++;

    /* Real-time motor control (1 kHz) */
    Controller_Update(&g_app.controller[0]);
    Controller_Update(&g_app.controller[1]);

    /* Poll UART RX and parse commands (non-blocking) */
    Protocol_Poll(&g_app.protocol);
    Protocol_ProcessRx(&g_app.protocol);

    ProtocolCmd_t cmd;
    while (Protocol_GetCommand(&g_app.protocol, &cmd)) {
        /* 尾部去重：同电机后面还有更新的目标指令时，跳过当前这条 */
        if (cmd.cmd == CMD_SET_TARGET && App_HasLaterSetTarget(g_app.protocol.cmd_read_idx, cmd.motor_id)) {
            continue;
        }
        App_ProcessCommand(&cmd);
    }

    /* Periodic standard binary status transmission */
    if (g_app.status_interval_ms > 0 &&
        (g_app.control_tick % g_app.status_interval_ms) == 0) {
        for (int i = 0; i < MOTOR_NUM; i++) {
            MotorController_t *ctrl = &g_app.controller[i];
            uint8_t mode_state = (ctrl->mode & 0x0F) | ((ctrl->state & 0x0F) << 4);
            Protocol_SendStatus(&g_app.protocol, i, mode_state,
                                ctrl->actual_speed, ctrl->actual_angle,
                                ctrl->traj_speed, ctrl->traj_angle,
                                ctrl->pwm_output, ctrl->encoder->total_count,
                                ctrl->fault_code);
        }
    }

}

void App_Run(void)
{
    while (1) {
        HAL_Delay(1000);

        /* Diagnostic output disabled -- re-enable here if needed for debugging */
#if 0
        char dbg[180];
        int n = snprintf(dbg, sizeof(dbg),
            "[DBG] M0 st=%d en=%d md=%d tgt=%d traj=%d pwm=%d | M1 st=%d en=%d md=%d pwm=%d\r\n",
            (int)g_app.controller[0].state, (int)g_app.controller[0].enabled, (int)g_app.controller[0].mode,
            (int)(g_app.controller[0].target_speed * 100.0f),
            (int)(g_app.controller[0].traj_speed  * 100.0f),
            (int)g_app.controller[0].pwm_output,
            (int)g_app.controller[1].state, (int)g_app.controller[1].enabled, (int)g_app.controller[1].mode,
            (int)g_app.controller[1].pwm_output);
        HAL_UART_Transmit(&huart2, (uint8_t *)dbg, n, 100);
#endif
    }
}

/* HAL UART Tx Complete callback */
void App_UART_TxCpltCallback(UART_HandleTypeDef *huart)
{
    if (huart == g_app.protocol.huart) {
        Protocol_TxCompleteCallback(&g_app.protocol);
    }
}


