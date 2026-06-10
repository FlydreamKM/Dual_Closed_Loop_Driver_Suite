# Dual_Closed-LOOP_Driver 固件

双路闭环直流电机驱动器，基于 **STM32F103C8T6**，支持速度/位置双模式闭环控制，配套 Flutter 跨平台桌面端上位机。

> 当前版本为 **仅二进制通信模式**，通过 `0xAA 0x55` 帧格式与上位机通信，支持 SET_TARGET、SET_PID、CONTROL、CALIBRATE 等命令。

---

## 目录

- [硬件平台](#硬件平台)
- [软件架构](#软件架构)
- [通信协议](#通信协议)
- [快速开始](#快速开始)
- [构建与烧录](#构建与烧录)
- [独立协议驱动 Protocol/](#独立协议驱动-protocol)
- [项目结构](#项目结构)
- [默认参数](#默认参数)

---

## 硬件平台

| 参数 | 值 |
|------|-----|
| MCU | STM32F103C8T6 (ARM Cortex-M3, 72 MHz) |
| Flash / RAM | 64 KB / 20 KB |

### 电机与引脚分配

| 电机 | 编码器 | PWM | 方向 GPIO |
|------|--------|-----|-----------|
| **电机 1** | TIM2 (PA0/PA1) | TIM4 CH1 (PB6) | PB7 (高电平=正转) |
| **电机 2** | TIM1 (PA8/PA9) | TIM3 CH1 (PA6) | PA5 (高电平=正转) |

### 其他外设

| 外设 | 引脚 | 用途 |
|------|------|------|
| USART2 | PA2 (TX) / PA3 (RX) | 上位机通信（二进制协议），TX=IT 模式，RX=DMA 环形缓冲 |
| I2C1 | PB8 (SCL) / PB9 (SDA) | 预留（12864 OLED 等） |

### 编码器参数

- 编码器线数：**1024**
- 解码模式：TI12 **四倍频**
- 传动链：电机(16T) → 车轮(68T) → 编码器(30T)
- 等效比：电机转 1 圈，编码器转 **16/30 圈**
- **电机 1 圈 ≈ 2184.5 个 TIM 计数**

```
角度(rad) = encoder_total × 2π / 2184.533...
速度(rad/s) = delta_count × 2π × 1000 / 2184.533...   (控制周期 1 ms)
```

---

## 软件架构

采用**模块化 + 非阻塞**设计，1 kHz 控制周期，所有模块均不阻塞：

| 模块 | 文件 | 职责 |
|------|------|------|
| **Encoder** | `encoder.c/h` | 编码器读取、16 位溢出补偿、速度/角度计算 |
| **Motor** | `motor.c/h` | PWM 输出（TIM3/TIM4）、方向控制、使能/急停 |
| **PID** | `pid.c/h` | 位置式 PID，积分限幅 + 抗积分饱和，支持自适应增益 |
| **Controller** | `controller.c/h` | 状态机、轨迹规划（直接跟踪）、速度/位置串级闭环、校准模式 |
| **Protocol** | `protocol.c/h` | UART RX（DMA 环形缓冲）、二进制帧协议解析 |
| **App** | `app.c/h` | 系统初始化、命令分发、1 kHz 控制调度 |

### 控制时序

- **SysTick 1 ms** → `App_ControlUpdate()`
  - 编码器更新（×2）
  - PID 计算 + 轨迹规划（×2）
  - PWM 输出更新（×2）
  - UART 命令轮询与解析
  - 状态/波形发送

### PWM 频率

TIM3/TIM4 的 ARR 在启动时被动态修改为 **1799**，得到：

```
36 MHz / 1800 = 20 kHz
```

避免电机低频啸叫，同时保留 1800 级分辨率。

---

## 通信协议

当前版本为 **仅二进制协议模式**，固定使用 `0xAA 0x55` 帧格式进行通信。

**帧格式**：

```
[0xAA][0x55][LEN][CMD][DATA...][CHK]
```

- **LEN** = CMD + DATA 的字节数
- **CHK** = LEN + CMD + DATA 所有字节的累加和（低 8 位）
- 小端模式，float 为 IEEE 754 单精度

**下行命令码**（上位机 → 下位机）：

| 命令码 | 名称 | LEN | 功能 |
|--------|------|-----|------|
| `0x01` | SET_TARGET | 20 | 设置目标参数（模式/速度/角度/加减速） |
| `0x02` | SET_PID | 16 | 设置单个电机的 PID 参数 |
| `0x07` | SET_PID_BOTH | 14 | 同时设置两个电机的 PID 参数 |
| `0x03` | CONTROL | 3 | 控制指令（使能/失能/急停/回零/清除故障） |
| `0x04` | REQ_STATUS | 1~2 | 请求状态帧 |
| `0x05` | HEARTBEAT | 1~2 | 心跳包 |
| `0x08` | CALIBRATE | 2 | 校准模式（启动/停止） |

**上行响应码**（下位机 → 上位机）：

| 响应码 | 名称 | LEN | 功能 |
|--------|------|-----|------|
| `0x81` | STATUS | 25 | 周期性状态上报（速度/角度/PWM/编码器等） |
| `0x82` | ACK | 3 | 通用应答（心跳回应等） |

完整帧结构、字段偏移表、校验和算法、状态机说明及通信时序示例见 [COMM_PROTOCOL.md](COMM_PROTOCOL.md)。

---

## 快速开始

### 1. 硬件连接

- USB 转 TTL 连接 **PA2(TX)** 和 **PA3(RX)**，波特率 **115200**。
- 电机驱动器接 **PB6/PB7**（电机1）和 **PA6/PA5**（电机2）。
- 编码器接 **PA0/PA1**（电机1）和 **PA8/PA9**（电机2）。

### 2. 上电调试流程

使用 Flutter 上位机或自定义上位机：

```
# 使能电机1
CONTROL: motor=0, cmd=ENABLE

# 速度模式，目标 5 rad/s
SET_TARGET: motor=0, mode=SPEED, speed=5.0, angle=0.0
```

观察 STATUS 帧中的 `actual_speed` 与 `target_speed` 的跟随情况。

**调 PID**：
```
SET_PID: motor=0, pid_type=SPEED, kp=3.0, ki=0.8, kd=0.0
```

**位置模式**：
```
SET_TARGET: motor=0, mode=POSITION, speed=2.0, angle=3.14
```

**急停**：
```
CONTROL: motor=0, cmd=EMERGENCY
```

**清除故障并重新使能**：
```
CONTROL: motor=0, cmd=CLEAR_FAULT
CONTROL: motor=0, cmd=ENABLE
```

**校准模式**：
```
CALIBRATE: motor=0, sub_cmd=START
# 等待校准完成后
CALIBRATE: motor=0, sub_cmd=STOP
```

---

## 构建与烧录

### 环境要求

- **GNU ARM Embedded Toolchain** (`arm-none-eabi-gcc`)
- **CMake** ≥ 3.16
- **Ninja**（可选）

> **注意**：工具链路径已做自动适配。`cmake/gcc-arm-none-eabi.cmake` 会从 `gcc` 的完整路径自动推断 `objcopy` 和 `size` 的位置。

### 编译

```bash
mkdir build && cd build
cmake .. -DCMAKE_TOOLCHAIN_FILE=../cmake/gcc-arm-none-eabi.cmake
make -j4
```

### 烧录

**ST-Link**：
```bash
st-flash write build/Dual_Closed-LOOP_Driver.bin 0x08000000
```

**OpenOCD**：
```bash
openocd -f interface/stlink.cfg -f target/stm32f1x.cfg -c "program build/Dual_Closed-LOOP_Driver.elf verify reset exit"
```

---

## 独立协议驱动 Protocol/

项目根目录下 `Protocol/` 是一个**独立、高可移植**的二进制通信协议驱动，与 `Core/` 下的业务代码解耦，可随时复制到其他项目中单独使用。

### 文件说明

| 文件 | 职责 | 平台依赖 |
|------|------|----------|
| `bp_def.h` | 命令码、响应码、状态机常量定义 | ❌ 无 |
| `bp_frame.h/.c` | 帧打包/解包（结构体 ↔ 字节流），含校验和计算 | ❌ 无 |
| `bp_parser.h/.c` | 通用字节流解析器（状态机），支持单字节/批量喂入 | ❌ 无 |
| `bp_hal_uart.h/.c` | HAL UART 适配层（DMA Circular 接收 + 阻塞发送） | ✅ 仅此处引用 `stm32f1xx_hal.h` |
| `example/main_example.c` | 完整集成示例（中断回调、命令分发、周期发送 STATUS） | — |

### 架构特点

- **四层解耦**：常量定义 → 帧操作 → 状态机解析器 → HAL 适配层，每层可独立替换
- **零平台依赖**：`bp_def` / `bp_frame` / `bp_parser` 不引用任何 HAL/平台头文件，仅使用标准 C 库
- **小端显式处理**：多字节数据用位移操作拼装，不依赖编译器 struct packing
- **浮点安全**：`memcpy` 直接拷贝 IEEE-754 字节，不做任何数值转换
- **DMA Circular 双缓冲**：HT + TC 双中断保证低延迟，CPU 零拷贝接收

### 使用方式

**方式一：继续使用 HAL（推荐）**

```c
#include "bp_hal_uart.h"

bp_hal_uart_t g_bp_uart;

/* 初始化 */
bp_hal_uart_init(&g_bp_uart, &huart2, my_frame_callback);

/* HAL 回调转发 */
void HAL_UART_RxHalfCpltCallback(UART_HandleTypeDef *huart) {
    if (huart == g_bp_uart.huart) bp_hal_uart_rx_half_callback(&g_bp_uart);
}
void HAL_UART_RxCpltCallback(UART_HandleTypeDef *huart) {
    if (huart == g_bp_uart.huart) bp_hal_uart_rx_cplt_callback(&g_bp_uart);
}
```

**方式二：不使用 HAL（标准库 / LL / 其他 MCU）**

只复制 `bp_def.h` + `bp_frame.h/.c` + `bp_parser.h/.c`，自己实现 UART 层：

```c
#include "bp_parser.h"

bp_parser_t parser;
bp_parser_init(&parser, my_callback);

/* 每收到一个字节 */
bp_parser_feed(&parser, rx_byte);

/* 组帧发送 */
bp_builder_t b;
bp_cmd_control_t cmd = { .motor_id = 0, .ctrl_cmd = BP_CTRL_ENABLE };
uint8_t *frame;
uint8_t len = bp_build_cmd_control(&b, &cmd, &frame);
uart_send(frame, len);
```

### 扩展新命令

如需添加新的命令码或字段：
1. 在 `bp_def.h` 中定义新的 `CMD_XXX` 宏
2. 在 `bp_frame.h` 中新增结构体（如 `bp_cmd_xxx_t`）
3. 在 `bp_frame.c` 中实现对应的 `bp_build_cmd_xxx()` 和 `bp_parse_cmd_xxx()` 函数
4. 解析器状态机 `bp_parser.c` **无需任何修改**

---

## 项目结构

```
.
├── Core/
│   ├── Inc/                    # 头文件
│   │   ├── app.h
│   │   ├── controller.h
│   │   ├── encoder.h
│   │   ├── motor.h
│   │   ├── pid.h
│   │   ├── protocol.h
│   │   └── main.h
│   └── Src/                    # 源文件
│       ├── app.c               # 主调度、命令分发
│       ├── controller.c        # 轨迹规划（直接跟踪）+ 串级 PID + 校准
│       ├── encoder.c           # 编码器读取 + 溢出处理
│       ├── motor.c             # PWM + 方向控制
│       ├── pid.c               # PID 算法（含自适应增益）
│       ├── protocol.c          # UART RX (DMA) + 二进制帧解析
│       └── main.c              # HAL 初始化入口
├── Protocol/                   # 独立二进制协议驱动（可移植到其他项目）
│   ├── bp_def.h                # 协议常量定义
│   ├── bp_frame.h/.c           # 帧打包/解包
│   ├── bp_parser.h/.c          # 通用字节流解析器（状态机）
│   ├── bp_hal_uart.h/.c        # HAL UART 适配层
│   └── example/
│       └── main_example.c      # 驱动集成示例
├── Drivers/                    # STM32 HAL / CMSIS
├── cmake/
├── CMakeLists.txt
├── COMM_PROTOCOL.md            # 二进制通信协议详细文档
└── README.md                   # 本文件
```

---

## 默认参数

| 参数 | 值 |
|------|-----|
| 控制周期 | 1 ms (1 kHz) |
| PWM 频率 | 20 kHz |
| STATUS 上报频率 | 100 Hz |
| 速度环 PID | Kp=18.0, Ki=0.5, Kd=7.0 |
| 位置环 PID | Kp=40.0, Ki=0.0, Kd=1.0 |
| PWM 输出范围 | ±1000（对应 55% 占空比） |
| PID 自适应 | 默认关闭（可通过 `PID_SetAdaptiveMode()` 开启） |

---

## 注意事项

1. **USER CODE 保护**：`main.c`、`stm32f1xx_it.c`、`stm32f1xx_hal_msp.c` 中所有自定义代码均置于 `USER CODE BEGIN/END` 块内，重新生成 CubeMX 代码时不会被覆盖。
2. **不要修改 HAL 源码**：`Drivers/STM32F1xx_HAL_Driver/` 为生成代码，如需修改配置请调整 `.ioc` 文件后重新生成。
3. **编码器溢出**：控制周期 1 ms 内电机不可能溢出 16 位计数器（理论极限约 4000 转/秒），溢出处理仅作为极端工况保险。
4. **高频指令不刹车**：连续发送 `SET_TARGET` 命令时，轨迹直接更新到新目标，电机不会刹停后再加速。
5. **命令队列去重**：同一电机在队列中堆积多条 `SET_TARGET` 指令时，只执行最新的一条，避免滞后和抖动。
