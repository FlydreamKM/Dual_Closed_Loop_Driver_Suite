# Flutter 上位机 — Dual Closed-Loop Driver

跨平台（Linux/Windows）桌面应用，用于控制和验证 Dual_Closed-LOOP_Driver 电机驱动。

## 功能特性

- **串口通信**：二进制协议，支持设备连接/断开/状态读取
- **控制指令**：设置目标速度/位置、使能/失能/急停/回零/清除故障
- **PID 参数配置**：实时调节 Kp/Ki/Kd，支持单路/双路设置
- **校准模式**：启动/停止电机校准流程
- **数据可视化**：实时显示 Motor A/B 速度和位置
- **模拟模式**：无需硬件即可验证上位机功能

## 支持平台

- Linux (Ubuntu/Debian)
- Windows 10/11

## 快速开始

### 环境要求
- Flutter SDK 3.19+ (desktop enabled)
- Linux 构建依赖：`sudo apt-get install clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libstdc++-12-dev`
- Windows 构建依赖：Visual Studio 2022 with Desktop development with C++

### 构建步骤
```bash
cd flutter_host
flutter pub get
flutter run -d linux     # Linux
flutter run -d windows  # Windows
```

### 发布构建
```bash
flutter build linux      # 输出在 build/linux/x64/release/bundle/
flutter build windows    # 输出在 build/windows/x64/runner/Release/
```

## 通信协议

帧格式：`[0xAA 0x55][Command 1byte][Length 1byte][Data N bytes][Checksum 1byte]`

校验和 = 累加和（Command + Length + Data），取低 8 位。

### 命令码

| 命令码 | 方向 | 说明 |
|--------|------|------|
| 0x01 | 下行 | SET_TARGET — 设置目标参数（19 bytes：电机ID + 速度 + 角度 + 加减速）|
| 0x02 | 下行 | SET_PID — 设置单路 PID（16 bytes：电机ID + 环路类型 + Kp/Ki/Kd）|
| 0x03 | 下行 | CONTROL — 控制指令（2 bytes：电机ID + 子命令）|
| 0x04 | 下行 | REQ_STATUS — 请求状态帧（1 byte：电机ID）|
| 0x05 | 下行 | HEARTBEAT — 心跳保活 |
| 0x07 | 下行 | SET_PID_BOTH — 设置双路 PID（32 bytes）|
| 0x08 | 下行 | CALIBRATE — 校准模式（1 byte：子命令）|
| 0x81 | 上行 | STATUS — 周期性状态上报（25 bytes：两路速度/位置/编码器/PWM/标志）|
| 0x82 | 上行 | ACK — 通用应答（1 byte：状态码）|

### 25 bytes STATUS 帧结构

| 偏移 | 长度 | 说明 |
|------|------|------|
| 0 | 4 bytes | Motor A 速度（float32, little-endian）|
| 4 | 4 bytes | Motor A 位置（float32）|
| 8 | 4 bytes | Motor B 速度（float32）|
| 12 | 4 bytes | Motor B 位置（float32）|
| 16 | 2 bytes | Motor A 编码器值（int16）|
| 18 | 2 bytes | Motor B 编码器值（int16）|
| 20 | 2 bytes | Motor A PWM 输出（int16）|
| 22 | 2 bytes | Motor B PWM 输出（int16）|
| 24 | 1 byte | 状态标志（bit0=A使能, bit1=B使能, bit2=校准完成, bit3=故障）|

## 模拟模式

无需硬件即可测试：
1. 打开 Connection 页面
2. 选择 MOCK 端口
3. 点击连接

## 依赖

- `flutter_libserialport`: 跨平台串口通信
- `flutter_riverpod`: 状态管理
- `go_router`: 导航路由
- `fl_chart`: 数据可视化
- `logger`: 日志记录

## 项目结构

```
lib/
├── app/             # 全局配置、路由
├── business/        # 业务模块
│   ├── device_control/   # 设备控制（连接、PID、校准、Dashboard）
│   └── visualization/    # 数据可视化
├── component/       # 功能组件
│   ├── protocol/    # 二进制协议编解码
│   └── serial/      # 串口服务（真实 + 模拟）
└── foundation/      # 基础组件
```
