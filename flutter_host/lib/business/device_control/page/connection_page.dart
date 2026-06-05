import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smt_host_app/business/device_control/view_model/device_viewmodels.dart';
import 'package:smt_host_app/component/serial/serial_service.dart';

class ConnectionPage extends ConsumerStatefulWidget {
  const ConnectionPage({super.key});

  @override
  ConsumerState<ConnectionPage> createState() => _ConnectionPageState();
}

class _ConnectionPageState extends ConsumerState<ConnectionPage> {
  String? _selectedPort;
  int _baudRate = 115200;
  bool _useMock = false;

  final List<int> _baudRates = [9600, 19200, 38400, 57600, 115200, 230400, 460800];

  @override
  Widget build(BuildContext context) {
    final connectionState = ref.watch(connectionStateProvider);
    final availablePorts = ref.read(connectionStateProvider.notifier).availablePorts;
    final isConnected = connectionState == SerialConnectionState.connected;

    return Scaffold(
      appBar: AppBar(title: const Text('Connection Settings')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Connection status
            _buildStatusCard(connectionState),
            const SizedBox(height: 32),
            
            // Port selection
            Text('Serial Port', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            if (!_useMock) ...[
              DropdownButtonFormField<String>(
                value: _selectedPort,
                hint: const Text('Select Port'),
                items: availablePorts.map((port) => DropdownMenuItem(
                  value: port,
                  child: Text(port),
                )).toList(),
                onChanged: isConnected ? null : (value) => setState(() => _selectedPort = value),
              ),
              const SizedBox(height: 16),
            ],
            
            // Baud rate
            Text('Baud Rate', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              value: _baudRate,
              items: _baudRates.map((rate) => DropdownMenuItem(
                value: rate,
                child: Text('$rate'),
              )).toList(),
              onChanged: isConnected ? null : (value) => setState(() => _baudRate = value!),
            ),
            const SizedBox(height: 24),
            
            // Mock mode toggle
            SwitchListTile(
              title: Text('Use Mock Device', style: Theme.of(context).textTheme.titleLarge),
              subtitle: const Text('Simulate device without hardware'),
              value: _useMock,
              onChanged: isConnected ? null : (value) => setState(() {
                _useMock = value;
                if (value) _selectedPort = 'MOCK_PORT';
              }),
            ),
            
            const Spacer(),
            
            // Connect/Disconnect button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: isConnected 
                    ? () => ref.read(connectionStateProvider.notifier).disconnect()
                    : (_selectedPort != null || _useMock)
                        ? () => _connect()
                        : null,
                icon: Icon(isConnected ? Icons.disconnect : Icons.usb),
                label: Text(isConnected ? 'Disconnect' : 'Connect'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isConnected ? Colors.red : Colors.green,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard(SerialConnectionState state) {
    Color color;
    String title;
    String subtitle;
    IconData icon;

    switch (state) {
      case SerialConnectionState.connected:
        color = Colors.green;
        title = 'Connected';
        subtitle = 'Device communication active';
        icon = Icons.check_circle;
        break;
      case SerialConnectionState.connecting:
        color = Colors.orange;
        title = 'Connecting...';
        subtitle = 'Establishing connection';
        icon = Icons.hourglass_top;
        break;
      case SerialConnectionState.error:
        color = Colors.red;
        title = 'Error';
        subtitle = 'Connection failed';
        icon = Icons.error;
        break;
      default:
        color = Colors.grey;
        title = 'Disconnected';
        subtitle = 'Select port and connect';
        icon = Icons.usb_off;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Row(
          children: [
            Icon(icon, size: 48, color: color),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: color)),
                Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _connect() async {
    final success = await ref.read(connectionStateProvider.notifier).connect(
      _selectedPort ?? 'MOCK_PORT',
      baudRate: _baudRate,
      useMock: _useMock,
    );

    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Connection failed')),
      );
    }
  }
}
