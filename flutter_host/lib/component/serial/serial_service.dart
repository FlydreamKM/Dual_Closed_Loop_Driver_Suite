import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:smt_host_app/component/protocol/binary_protocol.dart';
import 'package:logger/logger.dart';

/// Abstract serial service interface
/// Implementations: [SerialPortService] (real hardware), [MockSerialService] (simulation)
abstract class ISerialService {
  Stream<ProtocolPacket> get packetStream;
  Stream<SerialConnectionState> get connectionStateStream;

  Future<bool> connect(String portName, {int baudRate = 115200});
  Future<void> disconnect();
  Future<bool> sendPacket(ProtocolPacket packet);
  bool get isConnected;
  List<String> get availablePorts;
}

enum SerialConnectionState { disconnected, connecting, connected, error }

/// Real serial port service using flutter_libserialport
class SerialPortService implements ISerialService {
  final Logger _logger = Logger();
  SerialPort? _port;
  SerialPortReader? _reader;
  StreamSubscription<Uint8List>? _subscription;

  final _packetController = StreamController<ProtocolPacket>.broadcast();
  final _stateController = StreamController<SerialConnectionState>.broadcast();
  final _parser = ProtocolParser();

  SerialConnectionState _state = SerialConnectionState.disconnected;

  @override
  Stream<ProtocolPacket> get packetStream => _packetController.stream;

  @override
  Stream<SerialConnectionState> get connectionStateStream => _stateController.stream;

  @override
  bool get isConnected => _state == SerialConnectionState.connected && _port != null;

  @override
  List<String> get availablePorts => SerialPort.availablePorts;

  @override
  Future<bool> connect(String portName, {int baudRate = 115200}) async {
    try {
      _setState(SerialConnectionState.connecting);
      _parser.clear();

      _port = SerialPort(portName);

      if (!_port!.openReadWrite()) {
        _logger.e('Failed to open port: $portName');
        _setState(SerialConnectionState.error);
        return false;
      }

      final config = SerialPortConfig();
      config.baudRate = baudRate;
      config.bits = 8;
      config.parity = SerialPortParity.none;
      config.stopBits = 1;
      config.setFlowControl(SerialPortFlowControl.none);
      _port!.config = config;

      _reader = SerialPortReader(_port!);
      _subscription = _reader!.stream.listen(
        _onData,
        onError: (error) {
          _logger.e('Serial read error: $error');
          _setState(SerialConnectionState.error);
        },
      );

      _setState(SerialConnectionState.connected);
      _logger.i('Connected to $portName @ $baudRate baud');
      return true;

    } catch (e) {
      _logger.e('Connection error: $e');
      _setState(SerialConnectionState.error);
      return false;
    }
  }

  void _onData(Uint8List data) {
    final packets = _parser.parse(data);
    for (final packet in packets) {
      _packetController.add(packet);
    }
  }

  @override
  Future<void> disconnect() async {
    await _subscription?.cancel();
    _reader?.close();
    _port?.close();
    _port?.dispose();

    _subscription = null;
    _reader = null;
    _port = null;

    _setState(SerialConnectionState.disconnected);
    _logger.i('Disconnected');
  }

  @override
  Future<bool> sendPacket(ProtocolPacket packet) async {
    if (!isConnected || _port == null) {
      _logger.w('Cannot send packet: not connected');
      return false;
    }

    try {
      final data = packet.encode();
      final written = _port!.write(data);

      if (written == data.length) {
        _logger.d('Sent: $packet');
        return true;
      } else {
        _logger.w('Incomplete write: $written/${data.length} bytes');
        return false;
      }
    } catch (e) {
      _logger.e('Send error: $e');
      _setState(SerialConnectionState.error);
      return false;
    }
  }

  void _setState(SerialConnectionState state) {
    _state = state;
    _stateController.add(state);
  }

  void dispose() {
    disconnect();
    _packetController.close();
    _stateController.close();
  }
}

/// Mock serial service simulating Dual_Closed-LOOP_Driver (dual motor)
class MockSerialService implements ISerialService {
  final Logger _logger = Logger();
  final _packetController = StreamController<ProtocolPacket>.broadcast();
  final _stateController = StreamController<SerialConnectionState>.broadcast();

  bool _connected = false;
  Timer? _streamTimer;
  SerialConnectionState _state = SerialConnectionState.disconnected;

  // Motor A state
  double _motorAPos = 0.0;
  double _motorATargetPos = 0.0;
  double _motorASpeed = 0.0;
  double _motorATargetSpeed = 0.0;
  int _motorAEncoder = 0;
  int _motorAPwm = 0;
  bool _motorAEnabled = false;
  bool _motorAFault = false;

  // Motor B state
  double _motorBPos = 0.0;
  double _motorBTargetPos = 0.0;
  double _motorBSpeed = 0.0;
  double _motorBTargetSpeed = 0.0;
  int _motorBEncoder = 0;
  int _motorBPwm = 0;
  bool _motorBEnabled = false;
  bool _motorBFault = false;

  // PID params
  double _kpA = 18.0, _kiA = 0.5, _kdA = 7.0;
  double _kpB = 18.0, _kiB = 0.5, _kdB = 7.0;

  // Calibration state
  bool _isCalibrated = false;
  bool _isCalibrating = false;
  bool _isStreaming = false;

  // Movement timers
  Timer? _moveTimer;

  @override
  Stream<ProtocolPacket> get packetStream => _packetController.stream;

  @override
  Stream<SerialConnectionState> get connectionStateStream => _stateController.stream;

  @override
  bool get isConnected => _connected;

  @override
  List<String> get availablePorts => ['MOCK_PORT_A', 'MOCK_PORT_B', 'MOCK_VIRTUAL'];

  @override
  Future<bool> connect(String portName, {int baudRate = 115200}) async {
    await Future.delayed(const Duration(milliseconds: 300));
    _connected = true;
    _setState(SerialConnectionState.connected);
    _logger.i('Mock connected to $portName');
    _sendAck(ResponseCodes.SUCCESS);
    return true;
  }

  @override
  Future<void> disconnect() async {
    _stopStream();
    _moveTimer?.cancel();
    _connected = false;
    _setState(SerialConnectionState.disconnected);
    _logger.i('Mock disconnected');
  }

  @override
  Future<bool> sendPacket(ProtocolPacket packet) async {
    if (!_connected) return false;

    _logger.d('Mock received: $packet');
    _processCommand(packet);
    return true;
  }

  void _processCommand(ProtocolPacket packet) {
    switch (packet.command) {
      case CommandCodes.CMD_SET_TARGET:
        _processSetTarget(packet.payload);
        _sendAck(ResponseCodes.SUCCESS);
        break;

      case CommandCodes.CMD_SET_PID:
        _processSetPID(packet.payload);
        _sendAck(ResponseCodes.SUCCESS);
        break;

      case CommandCodes.CMD_SET_PID_BOTH:
        _processSetPIDBoth(packet.payload);
        _sendAck(ResponseCodes.SUCCESS);
        break;

      case CommandCodes.CMD_CONTROL:
        _processControl(packet.payload);
        _sendAck(ResponseCodes.SUCCESS);
        break;

      case CommandCodes.CMD_REQ_STATUS:
        _sendStatus();
        break;

      case CommandCodes.CMD_HEARTBEAT:
        _sendAck(ResponseCodes.SUCCESS);
        break;

      case CommandCodes.CMD_CALIBRATE:
        _processCalibrate(packet.payload);
        _sendAck(ResponseCodes.SUCCESS);
        break;

      default:
        _sendAck(ResponseCodes.INVALID_CMD);
    }
  }

  void _processSetTarget(Uint8List payload) {
    if (payload.length >= 19) {
      final motorId = payload[0];
      final speed = _bytesToFloat(payload.sublist(1, 5));
      final angle = _bytesToFloat(payload.sublist(5, 9));
      final accel = _bytesToFloat(payload.sublist(9, 13));
      final decel = _bytesToFloat(payload.sublist(13, 17));

      if (motorId == 0 || motorId == 2) { // 0=A, 2=both
        _motorATargetSpeed = speed;
        _motorATargetPos = angle;
      }
      if (motorId == 1 || motorId == 2) { // 1=B, 2=both
        _motorBTargetSpeed = speed;
        _motorBTargetPos = angle;
      }

      _startMoveSimulation();
    }
  }

  void _processSetPID(Uint8List payload) {
    if (payload.length >= 16) {
      final motorId = payload[0];
      final pidType = payload[1]; // 0=speed, 1=position
      final kp = _bytesToFloat(payload.sublist(2, 6));
      final ki = _bytesToFloat(payload.sublist(6, 10));
      final kd = _bytesToFloat(payload.sublist(10, 14));

      if (motorId == 0 || motorId == 2) {
        _kpA = kp; _kiA = ki; _kdA = kd;
      }
      if (motorId == 1 || motorId == 2) {
        _kpB = kp; _kiB = ki; _kdB = kd;
      }
    }
  }

  void _processSetPIDBoth(Uint8List payload) {
    if (payload.length >= 32) {
      // Motor A speed PID
      _kpA = _bytesToFloat(payload.sublist(0, 4));
      _kiA = _bytesToFloat(payload.sublist(4, 8));
      _kdA = _bytesToFloat(payload.sublist(8, 12));
      // Motor B speed PID
      _kpB = _bytesToFloat(payload.sublist(16, 20));
      _kiB = _bytesToFloat(payload.sublist(20, 24));
      _kdB = _bytesToFloat(payload.sublist(24, 28));
    }
  }

  void _processControl(Uint8List payload) {
    if (payload.length >= 2) {
      final motorId = payload[0];
      final ctrlCmd = payload[1];

      switch (ctrlCmd) {
        case ControlSubCommands.CTRL_ENABLE:
          if (motorId == 0 || motorId == 2) _motorAEnabled = true;
          if (motorId == 1 || motorId == 2) _motorBEnabled = true;
          break;
        case ControlSubCommands.CTRL_DISABLE:
          if (motorId == 0 || motorId == 2) _motorAEnabled = false;
          if (motorId == 1 || motorId == 2) _motorBEnabled = false;
          break;
        case ControlSubCommands.CTRL_EMERGENCY_STOP:
          _motorAEnabled = false;
          _motorBEnabled = false;
          _motorASpeed = 0;
          _motorBSpeed = 0;
          _motorAPwm = 0;
          _motorBPwm = 0;
          break;
        case ControlSubCommands.CTRL_HOME:
          _motorATargetPos = 0;
          _motorBTargetPos = 0;
          _startMoveSimulation();
          break;
        case ControlSubCommands.CTRL_CLEAR_FAULT:
          _motorAFault = false;
          _motorBFault = false;
          break;
      }
    }
  }

  void _processCalibrate(Uint8List payload) {
    if (payload.length >= 1) {
      final subCmd = payload[0];
      if (subCmd == 1) {
        _isCalibrating = true;
        _isCalibrated = false;
        // Simulate calibration
        Future.delayed(const Duration(seconds: 5), () {
          _isCalibrating = false;
          _isCalibrated = true;
          _motorAEncoder = 0;
          _motorBEncoder = 0;
          _motorAPos = 0;
          _motorBPos = 0;
        });
      } else {
        _isCalibrating = false;
      }
    }
  }

  void _startMoveSimulation() {
    _moveTimer?.cancel();
    _moveTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      // Motor A
      if (_motorAEnabled) {
        final speedErr = _motorATargetSpeed - _motorASpeed;
        _motorASpeed += speedErr * 0.3;
        final posErr = _motorATargetPos - _motorAPos;
        _motorAPos += _motorASpeed * 0.05 + posErr * 0.1;
        _motorAEncoder = (_motorAPos * 1000).toInt();
        _motorAPwm = (_motorASpeed * 10).clamp(-1000, 1000).toInt();
      }

      // Motor B
      if (_motorBEnabled) {
        final speedErr = _motorBTargetSpeed - _motorBSpeed;
        _motorBSpeed += speedErr * 0.3;
        final posErr = _motorBTargetPos - _motorBPos;
        _motorBPos += _motorBSpeed * 0.05 + posErr * 0.1;
        _motorBEncoder = (_motorBPos * 1000).toInt();
        _motorBPwm = (_motorBSpeed * 10).clamp(-1000, 1000).toInt();
      }

      // Check if both reached target
      final aDone = (_motorAPos - _motorATargetPos).abs() < 0.01 && (_motorASpeed).abs() < 0.1;
      final bDone = (_motorBPos - _motorBTargetPos).abs() < 0.01 && (_motorBSpeed).abs() < 0.1;
      if (aDone && bDone && _motorASpeed.abs() < 0.1 && _motorBSpeed.abs() < 0.1) {
        _motorASpeed = 0;
        _motorBSpeed = 0;
        timer.cancel();
      }
    });
  }

  void _sendStatus() {
    final buffer = BytesBuilder();

    // 4 bytes: Motor A speed
    buffer.add(_floatToBytes(_motorASpeed));
    // 4 bytes: Motor A position
    buffer.add(_floatToBytes(_motorAPos));
    // 4 bytes: Motor B speed
    buffer.add(_floatToBytes(_motorBSpeed));
    // 4 bytes: Motor B position
    buffer.add(_floatToBytes(_motorBPos));
    // 2 bytes: Motor A encoder
    buffer.add(_int16ToBytes(_motorAEncoder));
    // 2 bytes: Motor B encoder
    buffer.add(_int16ToBytes(_motorBEncoder));
    // 2 bytes: Motor A PWM
    buffer.add(_int16ToBytes(_motorAPwm));
    // 2 bytes: Motor B PWM
    buffer.add(_int16ToBytes(_motorBPwm));
    // 1 byte: status flags
    int flags = 0;
    if (_motorAEnabled) flags |= 0x01;
    if (_motorBEnabled) flags |= 0x02;
    if (_isCalibrated) flags |= 0x04;
    if (_motorAFault || _motorBFault) flags |= 0x08;
    buffer.addByte(flags);

    _sendResponse(CommandCodes.CMD_STATUS, buffer.toBytes());
  }

  void _sendAck(int statusCode) {
    _sendResponse(CommandCodes.CMD_ACK, Uint8List.fromList([statusCode]));
  }

  void _sendResponse(int command, Uint8List data) {
    Future.delayed(const Duration(milliseconds: 10), () {
      _packetController.add(ProtocolPacket(command: command, payload: data));
    });
  }

  void _setState(SerialConnectionState state) {
    _state = state;
    _stateController.add(state);
  }

  Uint8List _floatToBytes(double value) {
    final buffer = ByteData(4);
    buffer.setFloat32(0, value, Endian.little);
    return Uint8List.view(buffer.buffer);
  }

  double _bytesToFloat(Uint8List bytes) {
    final buffer = ByteData.sublistView(bytes);
    return buffer.getFloat32(0, Endian.little);
  }

  Uint8List _int16ToBytes(int value) {
    final buffer = ByteData(2);
    buffer.setInt16(0, value, Endian.little);
    return Uint8List.view(buffer.buffer);
  }

  void dispose() {
    _moveTimer?.cancel();
    _stopStream();
    _packetController.close();
    _stateController.close();
  }

  void _stopStream() {
    _streamTimer?.cancel();
    _streamTimer = null;
  }
}
