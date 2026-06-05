import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smt_host_app/business/device_control/model/device_models.dart';
import 'package:smt_host_app/business/device_control/repository/device_repository.dart';
import 'package:smt_host_app/component/serial/serial_service.dart';

// Global repository provider
final deviceRepositoryProvider = Provider<DeviceRepository>((ref) {
  final repo = DeviceRepository();
  ref.onDispose(() => repo.dispose());
  return repo;
});

// Connection state provider
final connectionStateProvider = StateNotifierProvider<ConnectionNotifier, ConnectionState>((ref) {
  final repo = ref.watch(deviceRepositoryProvider);
  return ConnectionNotifier(repo);
});

class ConnectionNotifier extends StateNotifier<ConnectionState> {
  final DeviceRepository _repo;
  
  ConnectionNotifier(this._repo) : super(ConnectionState.disconnected) {
    _repo.connectionStream.listen((newState) {
      state = newState;
    });
  }
  
  Future<bool> connect(String portName, {int baudRate = 115200, bool useMock = false}) async {
    return await _repo.connect(portName, baudRate: baudRate, useMock: useMock);
  }
  
  Future<void> disconnect() async {
    await _repo.disconnect();
  }
  
  List<String> get availablePorts => _repo.availablePorts;
  bool get isConnected => _repo.isConnected;
}

// Device status provider
final deviceStatusProvider = StreamProvider<DeviceStatus>((ref) {
  final repo = ref.watch(deviceRepositoryProvider);
  return repo.statusStream;
});

// PID parameters provider
final pidParamsProvider = StateNotifierProvider<PIDNotifier, PIDParams>((ref) {
  final repo = ref.watch(deviceRepositoryProvider);
  return PIDNotifier(repo);
});

class PIDNotifier extends StateNotifier<PIDParams> {
  final DeviceRepository _repo;
  
  PIDNotifier(this._repo) : super(const PIDParams());
  
  Future<void> load() async {
    await _repo.getPID();
  }
  
  Future<bool> update(PIDParams params) async {
    state = params;
    return await _repo.setPID(params);
  }
  
  void updateKp(double value) => state = state.copyWith(kp: value);
  void updateKi(double value) => state = state.copyWith(ki: value);
  void updateKd(double value) => state = state.copyWith(kd: value);
  void updateSetpoint(double value) => state = state.copyWith(setpoint: value);
  void updateOutputLimit(double value) => state = state.copyWith(outputLimit: value);
}

// Motor control provider
final motorControlProvider = StateNotifierProvider<MotorControlNotifier, MotorCommand>((ref) {
  final repo = ref.watch(deviceRepositoryProvider);
  return MotorControlNotifier(repo);
});

class MotorControlNotifier extends StateNotifier<MotorCommand> {
  final DeviceRepository _repo;
  
  MotorControlNotifier(this._repo) : super(const MotorCommand());
  
  Future<bool> moveTo(double motorA, double motorB, {double speed = 50.0}) async {
    return await _repo.moveTo(motorA, motorB, speed: speed);
  }
  
  Future<bool> home() => _repo.home();
  Future<bool> stop() => _repo.stop();
  
  void updateCommand({double? motorA, double? motorB, double? speed, bool? relative}) {
    state = state.copyWith(
      motorA: motorA ?? state.motorA,
      motorB: motorB ?? state.motorB,
      speed: speed ?? state.speed,
      relative: relative ?? state.relative,
    );
  }
}

// Calibration state provider
final calibrationProvider = StateNotifierProvider<CalibrationNotifier, CalibrationState>((ref) {
  final repo = ref.watch(deviceRepositoryProvider);
  return CalibrationNotifier(repo);
});

class CalibrationState {
  final bool isCalibrating;
  final List<CalibrationPoint> points;
  final int currentStep;
  
  const CalibrationState({
    this.isCalibrating = false,
    this.points = const [],
    this.currentStep = 0,
  });
  
  CalibrationState copyWith({
    bool? isCalibrating,
    List<CalibrationPoint>? points,
    int? currentStep,
  }) {
    return CalibrationState(
      isCalibrating: isCalibrating ?? this.isCalibrating,
      points: points ?? this.points,
      currentStep: currentStep ?? this.currentStep,
    );
  }
}

class CalibrationNotifier extends StateNotifier<CalibrationState> {
  final DeviceRepository _repo;
  
  CalibrationNotifier(this._repo) : super(const CalibrationState());
  
  Future<bool> enterCalibration() async {
    final result = await _repo.enterCalibration();
    if (result) {
      state = state.copyWith(isCalibrating: true, currentStep: 0);
    }
    return result;
  }
  
  Future<bool> exitCalibration() async {
    final result = await _repo.exitCalibration();
    if (result) {
      state = state.copyWith(isCalibrating: false);
    }
    return result;
  }
  
  void addPoint(CalibrationPoint point) {
    state = state.copyWith(
      points: [...state.points, point],
      currentStep: state.currentStep + 1,
    );
  }
  
  void clearPoints() {
    state = state.copyWith(points: [], currentStep: 0);
  }
}

// Data stream provider
final dataStreamProvider = StateNotifierProvider<DataStreamNotifier, List<DataSample>>((ref) {
  final repo = ref.watch(deviceRepositoryProvider);
  return DataStreamNotifier(repo);
});

class DataStreamNotifier extends StateNotifier<List<DataSample>> {
  final DeviceRepository _repo;
  
  DataStreamNotifier(this._repo) : super([]) {
    _repo.statusStream.listen((status) {
      final now = DateTime.now();
      final newSamples = [
        DataSample(timestamp: now, value: status.motorAPosition, label: 'Motor A'),
        DataSample(timestamp: now, value: status.motorBPosition, label: 'Motor B'),
        DataSample(timestamp: now, value: status.motorAVelocity, label: 'A Speed'),
        DataSample(timestamp: now, value: status.motorBVelocity, label: 'B Speed'),
      ];
      
      // Keep last 1000 samples per channel
      final updated = [...state, ...newSamples];
      if (updated.length > 3000) {
        state = updated.sublist(updated.length - 3000);
      } else {
        state = updated;
      }
    });
  }
  
  Future<bool> startStream() => _repo.startStream();
  Future<bool> stopStream() => _repo.stopStream();
  void clear() => state = [];
}

extension MotorCommandCopy on MotorCommand {
  MotorCommand copyWith({
    double? motorA,
    double? motorB,
    double? speed,
    bool? relative,
  }) {
    return MotorCommand(
      motorA: motorA ?? this.motorA,
      motorB: motorB ?? this.motorB,
      speed: speed ?? this.speed,
      relative: relative ?? this.relative,
    );
  }
}
