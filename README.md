# Dual Closed-Loop Driver Suite

双路闭环直流电机驱动套件，基于 STM32F103C8T6，配套 Flutter 跨平台桌面端上位机。

## 特性概览

- **双路独立闭环控制**：1kHz 控制周期，串级 PID（位置环 + 速度环）
- **仅二进制通信**：`0xAA 0x55` 帧格式，累加和校验，高可靠 UART 通信
- **无加减速限制**：速度模式直接跟踪目标，位置模式直接设定目标角度
- **校准模式**：自动正反行程标定，记录编码器零点和行程边界
- **PID 自适应**：分段增益策略，误差大时快速响应，误差小时抑制超调
- **Flutter 上位机**：跨平台 Linux/Windows 桌面应用，支持串口通信、控制、配置、可视化

## 仓库结构

```
Dual_Closed_Loop_Driver_Suite/
├── firmware/              # STM32 固件源码
│   ├── Core/              # 核心控制代码（PID、轨迹规划、状态机、协议解析）
│   ├── Protocol/          # 独立二进制协议驱动（可移植到其他 MCU）
│   ├── Drivers/           # STM32 HAL / CMSIS
│   ├── CMakeLists.txt
│   ├── README.md          # 固件详细说明
│   └── COMM_PROTOCOL.md   # 二进制通信协议完整规范
├── flutter_host/          # Flutter 跨平台上位机
│   ├── lib/               # Dart 源码
│   ├── linux/             # Linux 桌面配置
│   ├── windows/           # Windows 桌面配置
│   ├── pubspec.yaml
│   └── README.md          # 上位机构建说明
├── docs/                  # 项目文档
│   ├── CHANGELOG.md       # 修改记录
│   └── ARCHITECTURE.md    # 架构设计文档
├── .github/workflows/     # GitHub Actions CI/CD
├── .gitignore
└── README.md              # 本文件
```

## 快速开始

### 固件构建

```bash
cd firmware
mkdir build && cd build
cmake .. -DCMAKE_TOOLCHAIN_FILE=../cmake/gcc-arm-none-eabi.cmake
make -j4
```

烧录：
```bash
st-flash write build/Dual_Closed-LOOP_Driver.bin 0x08000000
```

详见 [firmware/README.md](firmware/README.md)。

### Flutter 上位机构建

```bash
cd flutter_host
flutter pub get
flutter run -d linux      # Linux
flutter run -d windows    # Windows
```

发布构建：
```bash
flutter build linux
flutter build windows
```

详见 [flutter_host/README.md](flutter_host/README.md)。

## 通信协议

二进制帧格式：
```
[0xAA 0x55][Command 1byte][Length 1byte][Data N bytes][Checksum 1byte]
```

校验和 = 累加和（Command + Length + Data 所有字节），取低 8 位。

### 命令码

| 命令码 | 方向 | 说明 |
|--------|------|------|
| 0x01 | 下行 | SET_TARGET — 设置电机目标参数（19 bytes） |
| 0x02 | 下行 | SET_PID — 设置单路 PID 参数（16 bytes） |
| 0x03 | 下行 | CONTROL — 控制指令（使能/失能/急停/回零/清除故障，2 bytes） |
| 0x04 | 下行 | REQ_STATUS — 请求状态帧（1 byte） |
| 0x05 | 下行 | HEARTBEAT — 心跳保活 |
| 0x07 | 下行 | SET_PID_BOTH — 设置双路 PID 参数（32 bytes） |
| 0x08 | 下行 | CALIBRATE — 校准模式（1 byte） |
| 0x81 | 上行 | STATUS — 周期性状态上报（25 bytes，默认 100Hz） |
| 0x82 | 上行 | ACK — 通用应答（1 byte） |

完整协议定义见 [firmware/COMM_PROTOCOL.md](firmware/COMM_PROTOCOL.md)。

## CI/CD

GitHub Actions 自动构建：
- Push 到 main 分支：自动构建 Linux + Windows（CI 检查）
- 打 `v*` 标签：自动构建并发布 Release

Release 页面：https://github.com/FlydreamKM/Dual_Closed_Loop_Driver_Suite/releases

## 修改记录

| 日期 | 版本 | 说明 |
|------|------|------|
| 2026-06-05 | v2.0 | 仅二进制通信，取消加减速，新增校准/自适应 PID，Flutter 上位机，统一仓库 |

## 许可证

MIT
