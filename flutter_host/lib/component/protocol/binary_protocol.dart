import 'dart:typed_data';
import 'package:flutter/foundation.dart';

/// Binary protocol for Dual_Closed-LOOP_Driver
/// Frame format: [0xAA 0x55][Command 1byte][Length 1byte][Data N bytes][Checksum 1byte]
/// Checksum = additive sum of Command + Length + all Data bytes, low 8 bits

@immutable
class ProtocolPacket {
  final int command;
  final Uint8List payload;
  final int? checksum;

  const ProtocolPacket({
    required this.command,
    required this.payload,
    this.checksum,
  });

  Uint8List encode() {
    final length = payload.length;
    final buffer = BytesBuilder();

    // Header
    buffer.addByte(0xAA);
    buffer.addByte(0x55);

    // Command
    buffer.addByte(command);

    // Length
    buffer.addByte(length);

    // Payload
    buffer.add(payload);

    // Checksum (additive sum of all bytes from command to payload end)
    final cs = checksum ?? _calculateChecksum(command, length, payload);
    buffer.addByte(cs);

    return buffer.toBytes();
  }

  static int _calculateChecksum(int cmd, int len, Uint8List data) {
    int cs = 0;
    cs += cmd;
    cs += len;
    for (final byte in data) {
      cs += byte;
    }
    return cs & 0xFF;
  }

  @override
  String toString() {
    return 'Packet(cmd: 0x\${command.toRadixString(16).padLeft(2, '0')}, '
        'len: \${payload.length}, payload: \${_bytesToHex(payload)})';
  }

  static String _bytesToHex(Uint8List bytes) {
    return bytes.map((b) => '0x\${b.toRadixString(16).padLeft(2, '0')}').join(' ');
  }
}

class ProtocolParser {
  final List<int> _buffer = [];

  List<ProtocolPacket> parse(Uint8List data) {
    _buffer.addAll(data);
    final packets = <ProtocolPacket>[];

    while (_buffer.length >= 5) { // Minimum: header(2) + cmd(1) + len(1) + cs(1)
      final headerIndex = _findHeader();
      if (headerIndex == -1) break;

      if (headerIndex > 0) {
        _buffer.removeRange(0, headerIndex);
      }

      if (_buffer.length < 5) break;

      final length = _buffer[3];
      final totalLength = 2 + 1 + 1 + length + 1; // header + cmd + len + payload + cs

      if (_buffer.length < totalLength) break;

      final command = _buffer[2];
      final payload = Uint8List.fromList(_buffer.sublist(4, 4 + length));
      final checksum = _buffer[4 + length];

      final calculatedCs = ProtocolPacket._calculateChecksum(command, length, payload);
      if (checksum != calculatedCs) {
        _buffer.removeAt(0);
        continue;
      }

      packets.add(ProtocolPacket(
        command: command,
        payload: payload,
        checksum: checksum,
      ));

      _buffer.removeRange(0, totalLength);
    }

    return packets;
  }

  int _findHeader() {
    for (int i = 0; i < _buffer.length - 1; i++) {
      if (_buffer[i] == 0xAA && _buffer[i + 1] == 0x55) {
        return i;
      }
    }
    return -1;
  }

  void clear() {
    _buffer.clear();
  }
}

/// Actual driver command codes (Dual_Closed-LOOP_Driver binary-only protocol)
class CommandCodes {
  // Downstream (Host → Driver)
  static const int CMD_SET_TARGET = 0x01;      // Set motor target params
  static const int CMD_SET_PID = 0x02;         // Set single motor PID
  static const int CMD_CONTROL = 0x03;         // Control: enable/disable/stop/home/clear_fault
  static const int CMD_REQ_STATUS = 0x04;      // Request status frame
  static const int CMD_HEARTBEAT = 0x05;       // Heartbeat keepalive
  static const int CMD_SET_PID_BOTH = 0x07;    // Set both motors PID
  static const int CMD_CALIBRATE = 0x08;         // Calibration mode

  // Upstream (Driver → Host)
  static const int CMD_STATUS = 0x81;          // Periodic status report (100Hz, 25 bytes)
  static const int CMD_ACK = 0x82;             // General acknowledgement
}

/// Control sub-commands (for CMD_CONTROL payload)
class ControlSubCommands {
  static const int CTRL_ENABLE = 0x01;
  static const int CTRL_DISABLE = 0x02;
  static const int CTRL_EMERGENCY_STOP = 0x03;
  static const int CTRL_HOME = 0x04;
  static const int CTRL_CLEAR_FAULT = 0x05;
}

/// Response status codes
class ResponseCodes {
  static const int SUCCESS = 0x00;
  static const int INVALID_CMD = 0x01;
  static const int INVALID_PARAM = 0x02;
  static const int BUSY = 0x03;
  static const int ERROR = 0x04;
  static const int NOT_CALIBRATED = 0x05;
}
