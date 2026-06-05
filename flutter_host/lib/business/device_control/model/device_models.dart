import 'package:flutter/foundation.dart';

/// Device status model
@immutable
class DeviceStatus {
  final double motorAPosition;
  final double motorBPosition;
  final double motorAVelocity;
  final double motorBVelocity;
  final bool isHomed;
  final bool isCalibrating;
  final bool isStreaming;
  final DateTime timestamp;

  const DeviceStatus({
    this.motorAPosition = 0.0,
    this.motorBPosition = 0.0,
    this.motorAVelocity = 0.0,
    this.motorBVelocity = 0.0,
    this.isHomed = false,
    this.isCalibrating = false,
    this.isStreaming = false,
    required this.timestamp,
  });

  DeviceStatus copyWith({
    double? motorAPosition,
    double? motorBPosition,
    double? motorAVelocity,
    double? motorBVelocity,
    bool? isHomed,
    bool? isCalibrating,
    bool? isStreaming,
    DateTime? timestamp,
  }) {
    return DeviceStatus(
      motorAPosition: motorAPosition ?? this.motorAPosition,
      motorBPosition: motorBPosition ?? this.motorBPosition,
      motorAVelocity: motorAVelocity ?? this.motorAVelocity,
      motorBVelocity: motorBVelocity ?? this.motorBVelocity,
      isHomed: isHomed ?? this.isHomed,
      isCalibrating: isCalibrating ?? this.isCalibrating,
      isStreaming: isStreaming ?? this.isStreaming,
      timestamp: timestamp ?? this.timestamp,
    );
  }
}

/// PID parameters model
@immutable
class PIDParams {
  final double kp; // Proportional gain
  final double ki; // Integral gain
  final double kd; // Derivative gain
  final double setpoint;
  final double outputLimit;

  const PIDParams({
    this.kp = 1.0,
    this.ki = 0.0,
    this.kd = 0.0,
    this.setpoint = 0.0,
    this.outputLimit = 100.0,
  });

  PIDParams copyWith({
    double? kp,
    double? ki,
    double? kd,
    double? setpoint,
    double? outputLimit,
  }) {
    return PIDParams(
      kp: kp ?? this.kp,
      ki: ki ?? this.ki,
      kd: kd ?? this.kd,
      setpoint: setpoint ?? this.setpoint,
      outputLimit: outputLimit ?? this.outputLimit,
    );
  }
}

/// Calibration data point
@immutable
class CalibrationPoint {
  final int step;
  final double expectedValue;
  final double measuredValue;
  final double error;
  final DateTime timestamp;

  const CalibrationPoint({
    required this.step,
    required this.expectedValue,
    required this.measuredValue,
    required this.error,
    required this.timestamp,
  });
}

/// Motor control command - dual motor
@immutable
class MotorCommand {
  final double motorA;
  final double motorB;
  final double speed;
  final bool relative;

  const MotorCommand({
    this.motorA = 0.0,
    this.motorB = 0.0,
    this.speed = 50.0,
    this.relative = false,
  });
}

/// Connection configuration
@immutable
class ConnectionConfig {
  final String portName;
  final int baudRate;
  final bool useMock;

  const ConnectionConfig({
    this.portName = '',
    this.baudRate = 115200,
    this.useMock = false,
  });
}

/// Data stream sample for visualization
@immutable
class DataSample {
  final DateTime timestamp;
  final double value;
  final String label;

  const DataSample({
    required this.timestamp,
    required this.value,
    required this.label,
  });
}
