# Dual Closed-Loop Driver Suite

双路闭环直流电机驱动套件。基于 STM32F103C8T6，双路直流电机闭环控制，串口二进制协议通信，配套 Flutter 跨平台上位机。

## 仓库结构

```
Dual_Closed_Loop_Driver_Suite/
├── firmware/          # 固件代码（STM32 HAL 项目，binary-only 重构）
│   ├── Core/          # 核心驱动代码
│   │   ├── Inc/       # 头文件
│   │   └── Src/       # 源文件
│   ├── Protocol/      # 二进制协议驱动（独立可移植）
│   ├── Drivers/       # STM32 HAL 库
│   ├── CMakeLists.txt
│   └── ...
├── flutter_host/      # Flutter 跨平台上位机（Linux + Windows）
│   ├── lib/           # Dart 源码
│   ├── linux/         # Linux 桌面配置
│   ├── windows/       # Windows 桌面配置
│   ├── pubspec.yaml
│   └── README.md
├── docs/              # 文档
│   ├── COMM_PROTOCOL.md    # 通信协议完整规范
│   └── 修改说明.md         # 驱动修改记录
├── .gitignore
└── README.md          # 本文件
```

## 主要特性

- **双路电机独立控制**：1kHz 控制周期，串级 PID（位置环 + 速度环）
- **仅二进制通信**：0xAA 0x55 帧格式，累加和校验，VOFA 代码已清理
- **无加减速限制**：速度模式直接跟踪目标，位置模式直接设目标角度
- **校准模式**：自动正反行程标定，记录编码器零点和行程边界
- **PID 自适应**：分段增益策略，误差大时快速响应，误差小时抑制超调
- **动态制动**：能耗制动，过零自锁
- **Flutter 上位机**：跨平台（Linux/Windows），支持串口通信、模拟模式、PID 配置、校准、数据可视化

## 固件构建

### 环境要求
- ARM GCC 工具链（`arm-none-eabi-gcc`）
- CMake >= 3.16

### 构建步骤
```bash
cd firmware
mkdir build && cd build
cmake .. -DCMAKE_TOOLCHAIN_FILE=../cmake/arm-none-eabi-gcc.cmake
make -j4
```

### 烧录
```bash
st-flash write build/Dual_Closed-LOOP_Driver.bin 0x08000000
```

## Flutter 上位机构建

### 环境要求
- Flutter SDK 3.19+ (desktop enabled)
- Linux: `flutter config --enable-linux-desktop`
- Windows: `flutter config --enable-windows-desktop`

### 构建步骤
```bash
cd flutter_host
flutter pub get
flutter run -d linux   # Linux
flutter run -d windows # Windows
```

### 发布构建
```bash
flutter build linux    # 输出在 build/linux/x64/release/bundle/
flutter build windows  # 输出在 build/windows/x64/runner/Release/
```

## 通信协议

二进制帧格式：
```
[0xAA 0x55][Command 1byte][Length 1byte][Data N bytes][Checksum 1byte]
```
校验和 = 累加和（Command + Length + Data 所有字节），取低 8 位。

### 命令码

| 命令码 | 方向 | 说明 |
|--------|------|------|
| 0x01 | 下行 | SET_TARGET — 设置电机目标参数 |
| 0x02 | 下行 | SET_PID — 设置单路 PID 参数 |
| 0x03 | 下行 | CONTROL — 控制指令（使能/失能/急停/回零/清除故障）|
| 0x04 | 下行 | REQ_STATUS — 请求状态帧 |
| 0x05 | 下行 | HEARTBEAT — 心跳保活 |
| 0x07 | 下行 | SET_PID_BOTH — 设置双路 PID 参数 |
| 0x08 | 下行 | CALIBRATE — 校准模式 |
| 0x81 | 上行 | STATUS — 周期性状态上报（25 bytes，默认 100Hz）|
| 0x82 | 上行 | ACK — 通用应答 |

详见 `docs/COMM_PROTOCOL.md`。

## 修改记录

| 日期 | 版本 | 说明 |
|------|------|------|
| 2026-06-05 | v2.0 | binary-only 重构，取消加减速，新增校准/自适应 PID，统一仓库，Flutter 上位机 |

## 项目来源

固件基于 [FlydreamKM/Dual_Closed-LOOP_Driver](https://github.com/FlydreamKM/Dual_Closed-LOOP_Driver)，在此感谢原作者的开源贡献。
