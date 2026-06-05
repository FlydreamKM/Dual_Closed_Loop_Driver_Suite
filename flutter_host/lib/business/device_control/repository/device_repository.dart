import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:smt_host_app/component/protocol/binary_protocol.dart';
import 'package:smt_host_app/component/serial/serial_service.dart';
import 'package:smt_host_app/business/device_control/model/device_models.dart';
import 'package:logger/logger.dart';

/// Device repository - handles all device communication
class DeviceRepository {
  final Logger _logger = Logger();
  ISerialService? _serialService;
  StreamSubscription? _packetSubscription;
  
  final _statusController = StreamController<DeviceStatus>.broadcast();
  final _connectionController = StreamController<SerialConnectionState>.broadcast();
  
  DeviceStatus _lastStatus = DeviceStatus(timestamp: DateTime.now());
  PIDParams _lastPID = const PIDParams();
  
  Stream<DeviceStatus> get statusStream => _statusController.stream;
  Stream<SerialConnectionState> get connectionStream => _connectionController.stream;
  DeviceStatus get lastStatus => _lastStatus;
  PIDParams get lastPID => _lastPID;
  bool get isConnected => _serialService?.isConnected ?? false;
  List<String> get availablePorts => _serialService?.availablePorts ?? [];

  /// Initialize with serial service (real or mock)
  void setSerialService(ISerialService service) {
    _disposeCurrent();
    _serialService = service;
    
    _packetSubscription = service.packetStream.listen(_handlePacket);
    service.connectionStateStream.listen((state) {
      _connectionController.add(state);
    });
  }

  Future<bool> connect(String portName, {int baudRate = 115200, bool useMock = false}) async {
    try {
      if (useMock) {
        setSerialService(MockSerialService());
      } else if (_serialService == null || _serialService is MockSerialService) {
        setSerialService(SerialPortService());
      }
      
      return await _serialService!.connect(portName, baudRate: baudRate);
    } catch (e) {
      _logger.e('Connection error: $e');
      return false;
    }
  }

  Future<void> disconnect() async {
    await _serialService?.disconnect();
  }

  Future<bool> sendCommand(int command, [Uint8List? payload]) async {
    if (_serialService == null) return false;
    
    final packet = ProtocolPacket(
      command: command,
      payload: payload ?? Uint8List(0),
    );
    
    return await _serialService!.sendPacket(packet);
  }

  // === Command helpers ===
  
  Future<bool> handshake() => sendCommand(CommandCodes.CMD_HANDSHAKE);
  
  Future<bool> getStatus() => sendCommand(CommandCodes.CMD_GET_STATUS);
  
  Future<bool> reset() => sendCommand(CommandCodes.CMD_RESET);
  
  Future<bool> moveTo(double motorA, double motorB, {double speed = 50.0}) async {
    final buffer = BytesBuilder();
    buffer.add(_floatToBytes(motorA));
    buffer.add(_floatToBytes(motorB));
    buffer.add(_floatToBytes(speed));
    
    return sendCommand(CommandCodes.CMD_MOTOR_MOVE, buffer.toBytes());
  }
  
  Future<bool> stop() => sendCommand(CommandCodes.CMD_MOTOR_STOP);
  
  Future<bool> home() => sendCommand(CommandCodes.CMD_MOTOR_HOME);
  
  Future<bool> setPID(PIDParams params) async {
    final buffer = BytesBuilder();
    buffer.add(_floatToBytes(params.kp));
    buffer.add(_floatToBytes(params.ki));
    buffer.add(_floatToBytes(params.kd));
    buffer.add(_floatToBytes(params.setpoint));
    buffer.add(_floatToBytes(params.outputLimit));
    
    return sendCommand(CommandCodes.CMD_SET_PID, buffer.toBytes());
  }
  
  Future<bool> getPID() => sendCommand(CommandCodes.CMD_GET_PID);
  
  Future<bool> enterCalibration() => sendCommand(CommandCodes.CMD_ENTER_CALIB);
  
  Future<bool> exitCalibration() => sendCommand(CommandCodes.CMD_EXIT_CALIB);
  
  Future<bool> startStream() => sendCommand(CommandCodes.CMD_START_STREAM);
  
  Future<bool> stopStream() => sendCommand(CommandCodes.CMD_STOP_STREAM);

  void _handlePacket(ProtocolPacket packet) {
    _logger.d('Received: $packet');
    
    switch (packet.command) {
      case CommandCodes.CMD_GET_STATUS:
      case CommandCodes.CMD_STREAM_DATA:
        _parseStatus(packet.payload);
        break;
        
      case CommandCodes.CMD_GET_PID:
        _parsePID(packet.payload);
        break;
        
      case CommandCodes.CMD_ACK:
        _logger.i('Command acknowledged');
        break;
        
      case CommandCodes.CMD_NACK:
        _logger.w('Command not acknowledged: ${packet.payload.isNotEmpty ? packet.payload[0] : 'unknown'}');
        break;
        
      case CommandCodes.CMD_ERROR:
        _logger.e('Device error: ${packet.payload.isNotEmpty ? packet.payload[0] : 'unknown'}');
        break;
    }
  }

  void _parseStatus(Uint8List payload) {
    if (payload.length < 17) return;
    
    final buffer = ByteData.sublistView(payload);
    
    _lastStatus = DeviceStatus(
      motorAPosition: buffer.getFloat32(0, Endian.little),
      motorBPosition: buffer.getFloat32(4, Endian.little),
      motorAVelocity: buffer.getFloat32(8, Endian.little),
      motorBVelocity: buffer.getFloat32(12, Endian.little),
      isHomed: payload.length > 16 && payload[16] != 0,
      isCalibrating: payload.length > 17 && payload[17] != 0,
      isStreaming: payload.length > 18 && payload[18] != 0,
      timestamp: DateTime.now(),
    );
    
    _statusController.add(_lastStatus);
  }

  void _parsePID(Uint8List payload) {
    if (payload.length < 12) return;
    
    final buffer = ByteData.sublistView(payload);
    
    _lastPID = PIDParams(
      kp: buffer.getFloat32(0, Endian.little),
      ki: buffer.getFloat32(4, Endian.little),
      kd: buffer.getFloat32(8, Endian.little),
    );
  }

  Uint8List _floatToBytes(double value) {
    final buffer = ByteData(4);
    buffer.setFloat32(0, value, Endian.little);
    return Uint8List.view(buffer.buffer);
  }

  void _disposeCurrent() {
    _packetSubscription?.cancel();
    _packetSubscription = null;
  }

  void dispose() {
    _disposeCurrent();
    _serialService?.dispose();
    _statusController.close();
    _connectionController.close();
  }
}
