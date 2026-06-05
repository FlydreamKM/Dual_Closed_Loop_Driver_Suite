import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smt_host_app/business/device_control/view_model/device_viewmodels.dart';

class PidConfigPage extends ConsumerWidget {
  const PidConfigPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pidParams = ref.watch(pidParamsProvider);
    final isConnected = ref.watch(connectionStateProvider) == ConnectionState.connected;

    return Scaffold(
      appBar: AppBar(title: const Text('PID Configuration')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'PID Parameters',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Tune the Proportional-Integral-Derivative controller parameters',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 32),
            
            // PID Sliders
            _buildSliderCard(
              context,
              'Proportional (Kp)',
              pidParams.kp,
              0.0,
              10.0,
              Colors.blue,
              (value) => ref.read(pidParamsProvider.notifier).updateKp(value),
            ),
            const SizedBox(height: 16),
            _buildSliderCard(
              context,
              'Integral (Ki)',
              pidParams.ki,
              0.0,
              5.0,
              Colors.green,
              (value) => ref.read(pidParamsProvider.notifier).updateKi(value),
            ),
            const SizedBox(height: 16),
            _buildSliderCard(
              context,
              'Derivative (Kd)',
              pidParams.kd,
              0.0,
              1.0,
              Colors.orange,
              (value) => ref.read(pidParamsProvider.notifier).updateKd(value),
            ),
            const SizedBox(height: 16),
            _buildSliderCard(
              context,
              'Setpoint',
              pidParams.setpoint,
              -100.0,
              100.0,
              Colors.purple,
              (value) => ref.read(pidParamsProvider.notifier).updateSetpoint(value),
            ),
            const SizedBox(height: 16),
            _buildSliderCard(
              context,
              'Output Limit',
              pidParams.outputLimit,
              0.0,
              255.0,
              Colors.red,
              (value) => ref.read(pidParamsProvider.notifier).updateOutputLimit(value),
            ),
            
            const Spacer(),
            
            // Action buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: isConnected
                        ? () => ref.read(pidParamsProvider.notifier).load()
                        : null,
                    icon: const Icon(Icons.download),
                    label: const Text('Read from Device'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: isConnected
                        ? () => _showApplyDialog(context, ref, pidParams)
                        : null,
                    icon: const Icon(Icons.upload),
                    label: const Text('Apply to Device'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSliderCard(
    BuildContext context,
    String label,
    double value,
    double min,
    double max,
    Color color,
    ValueChanged<double> onChanged,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(label, style: Theme.of(context).textTheme.titleLarge),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    value.toStringAsFixed(3),
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Slider(
              value: value,
              min: min,
              max: max,
              divisions: ((max - min) * 100).toInt(),
              activeColor: color,
              onChanged: onChanged,
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(min.toStringAsFixed(1)),
                Text(max.toStringAsFixed(1)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showApplyDialog(BuildContext context, WidgetRef ref, dynamic params) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Apply PID Settings'),
        content: Text(
          'Kp: ${params.kp.toStringAsFixed(3)}\n'
          'Ki: ${params.ki.toStringAsFixed(3)}\n'
          'Kd: ${params.kd.toStringAsFixed(3)}\n\n'
          'Send to device?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Apply'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await ref.read(pidParamsProvider.notifier).update(params);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? 'PID parameters applied' : 'Failed to apply PID'),
            backgroundColor: success ? Colors.green : Colors.red,
          ),
        );
      }
    }
  }
}
