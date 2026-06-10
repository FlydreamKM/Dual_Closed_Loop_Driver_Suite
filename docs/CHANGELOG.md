# 驱动修改说明（v2.0 binary-only 重构）

## 概述

基于原 Dual_Closed-LOOP_Driver 项目，完成固件重构和配套 Flutter 上位机开发。

---

## 修改内容

### 1. 仅二进制通信模式

- `Core/Inc/protocol.h`：固定 `#define PROTOCOL_VOFA_ONLY 0`
- 删除 VOFA 相关代码：
  - 移除 `Core/Inc/vofa.h` 和 `Core/Src/vofa.c`
  - 移除 `protocol.c` 中的 `simple_atof()` 和 `Protocol_ParseTextLine()`
  - 移除 `protocol.c` 中的 `Protocol_SendVofaJustFloat()`
  - 移除 `protocol.h` 中的 VOFA 协议函数声明
  - 移除 `app.c` / `main.c` 中的 VOFA 调用和引用
- 通信完全使用 `0xAA 0x55` 二进制帧格式
- 校验和算法：累加和（LEN + CMD + DATA），取低 8 位

### 2. 取消加减速度特性

`Core/Src/controller.c` - `TrajectoryPlanner()`：
- **速度模式**：直接 `traj_speed = target_speed`，去除 accel 限幅逻辑
- **位置模式**：直接 `traj_angle = target_angle`，去除梯形规划（decel_dist、加速/巡航/减速判断等）
- `accel` 和 `decel` 字段保留在结构体中（向后兼容上位机），但不再使用

### 3. 新增校准模式

新增命令码 `CMD_CALIBRATE 0x08`，支持 start/stop 子命令。

**接口**：
- `Controller_StartCalibration()` / `Controller_StopCalibration()`
- `Controller_IsCalibrated()` / `Controller_GetCalibrationProgress()`

**流程**：
1. 正向旋转，记录最大行程角度
2. 反向旋转，记录最小行程角度
3. 校准完成，将编码器零点偏移到行程中点
4. 校准期间屏蔽其他控制命令

**状态机**：
- 新增 `STATE_CALIBRATING` 状态
- 状态机处理在 `Controller_Update()` 中优先于制动和正常控制

### 4. PID 自适应

`Core/Src/pid.c` - `PID_Update()`：
- 新增 `PID_SetAdaptiveMode()` 开启/关闭自适应
- 新增 `PID_ConfigureAdaptive()` 配置阈值和限幅
- 自适应策略：
  - 误差 > 阈值：Kp *= 1.5，Ki *= 1.2，Kd *= 1.0（快速响应）
  - 误差 < 阈值：Kp *= 0.8，Ki *= 0.6，Kd *= 1.2（抑制超调）
- 参数范围限幅：Kp 上限 = base * 3.0，下限 = base * 0.3
- Ki 限幅 <= Kp * 2.0
- 默认关闭自适应模式

### 5. SET_TARGET 重置

`Core/Src/app.c` - `App_ProcessCommand()` 的 `CMD_SET_TARGET` 分支：
- 添加 `PID_Reset(&ctrl->speed_pid)`
- 添加 `PID_Reset(&ctrl->pos_pid)`
- 添加 `ctrl->traj_speed = 0.0f`

### 6. Flutter 跨平台上位机

开发配套 Flutter 桌面端应用，支持 Linux 和 Windows：
- 串口二进制通信（`0xAA 0x55` 帧格式，累加和校验）
- 模拟模式（无需硬件即可验证）
- 设备连接/断开、控制指令、PID 配置、校准模式、数据可视化
- 协议命令码与固件完全对齐

### 7. 编译修复

编译验证过程中修复的问题：
- `pid.c` 缺少 `#include <math.h>`（`fabsf()` 需要）
- `controller.c` 添加 `Controller_CalibrateUpdate()` 前向声明
- `controller.c` 修复 `encoder->angle_per_count` 为正确公式
- 工具链配置：Debian 新版 GCC 改用 picolibc 替代 newlib，调整 linker flags
- `CMakeLists.txt` 移除已删除的 `vofa.c` 引用

---

## 文件变更统计

| 文件 | 变更 |
|------|------|
| `Core/Inc/controller.h` | +17 行（校准字段+接口） |
| `Core/Inc/pid.h` | +15 行（自适应参数+接口） |
| `Core/Inc/protocol.h` | -11 行（VOFA 删除，+CMD_CALIBRATE） |
| `Core/Inc/app.h` | -1 行（VOFA 相关） |
| `Core/Src/controller.c` | +165/-35 行（校准+简化轨迹） |
| `Core/Src/pid.c` | +61 行（自适应逻辑） |
| `Core/Src/protocol.c` | -130 行（VOFA 代码清理） |
| `Core/Src/app.c` | ±64 行（校准命令+SET_TARGET修复） |
| `Core/Src/main.c` | -2 行（VOFA 引用清除） |
| `Core/Inc/vofa.h` | 删除（47 行） |
| `Core/Src/vofa.c` | 删除（50 行） |
| `flutter_host/` | 新增（Flutter 上位机完整项目） |
| `cmake/gcc-arm-none-eabi.cmake` | 修改（picolibc 适配） |
| `CMakeLists.txt` | 修改（移除 vofa.c 引用） |

---

## 仓库结构

```
Dual_Closed_Loop_Driver_Suite/
├── firmware/          # 修改后的固件代码
│   ├── Core/          # 核心驱动代码
│   ├── Protocol/      # 独立二进制协议驱动
│   ├── Drivers/       # STM32 HAL / CMSIS
│   ├── CMakeLists.txt
│   ├── README.md
│   └── COMM_PROTOCOL.md
├── flutter_host/      # Flutter 跨平台上位机
│   ├── lib/           # Dart 源码
│   ├── linux/         # Linux 桌面配置
│   ├── windows/       # Windows 桌面配置
│   └── README.md
├── docs/              # 项目文档
│   ├── CHANGELOG.md
│   └── ARCHITECTURE.md
└── README.md          # 项目总说明
```
