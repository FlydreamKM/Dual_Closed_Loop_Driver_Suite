# Dual Closed-Loop Driver Suite

双路闭环直流电机驱动套件。基于 STM32F103C8T6，双路直流电机闭环控制，串口二进制协议通信。

## 仓库结构

```
Dual_Closed_Loop_Driver_Suite/
├── firmware/          # 固件代码（STM32 HAL 项目）
│   └── Core/          # 核心驱动代码
│       ├── Inc/       # 头文件
│       └── Src/       # 源文件
├── flutter_host/      # Flutter 上位机（预留，待 Seele 完成）
│   └── README.md
├── docs/              # 文档
├── .gitignore
└── README.md
```

## 固件构建指南

### 环境要求
- STM32CubeMX（用于重新生成 HAL 初始化代码）
- ARM GCC 工具链（`arm-none-eabi-gcc`）
- CMake >= 3.16

### 构建步骤

```bash
cd firmware
mkdir build && cd build
cmake .. -DCMAKE_TOOLCHAIN_FILE=../cmake/arm-none-eabi-gcc.cmake
make -j4
```

生成的 `.bin` 和 `.hex` 文件在 `build/` 目录下。

### 烧录（ST-Link）

```bash
st-flash write build/Dual_Closed-LOOP_Driver.bin 0x08000000
```

## 通信协议

二进制帧格式：
```
[0xAA 0x55][LEN(1)][CMD(1)][DATA(N)][CHK(1)]
```
校验和 = CMD + DATA 各字节累加和取低 8 位。

详情请见 `docs/` 和 `firmware/COMM_PROTOCOL.md`。

## 主要特性

- 双路电机独立控制
- 串级 PID（位置环 + 速度环），1kHz 控制周期
- 二进制串口协议（115200 8N1 DMA）
- 动态制动
- 校准模式
- PID 自适应增益
- 位置模式和速度模式切换

## 修改记录

| 日期 | 版本 | 说明 |
|------|------|------|
| 2026-06-05 | v2.0 | binary-only 重构，取消加减速，新增校准/自适应PID，统一仓库 |
