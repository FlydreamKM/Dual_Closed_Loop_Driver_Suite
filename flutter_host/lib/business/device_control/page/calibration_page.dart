import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smt_host_app/business/device_control/view_model/device_viewmodels.dart';
import 'package:smt_host_app/business/device_control/model/device_models.dart';

class CalibrationPage extends ConsumerStatefulWidget {
  const CalibrationPage({super.key});

  @override
  ConsumerState<CalibrationPage> createState() => _CalibrationPageState();
}

class _CalibrationPageState extends ConsumerState<CalibrationPage> {
  final _expectedController = TextEditingController();
  final _measuredController = TextEditingController();

  @override
  void dispose() {
    _expectedController.dispose();
    _measuredController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final calibrationState = ref.watch(calibrationProvider);
    final isConnected = ref.watch(connectionStateProvider) == ConnectionState.connected;

    return Scaffold(
      appBar: AppBar(title: const Text('Calibration')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Calibration Mode',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Calibrate device accuracy by comparing expected and measured values',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),

            // Calibration control buttons
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: isConnected && !calibrationState.isCalibrating
                      ? () => ref.read(calibrationProvider.notifier).enterCalibration()
                      : null,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Start Calibration'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: isConnected && calibrationState.isCalibrating
                      ? () => ref.read(calibrationProvider.notifier).exitCalibration()
                      : null,
                  icon: const Icon(Icons.stop),
                  label: const Text('End Calibration'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: calibrationState.points.isNotEmpty
                      ? () => ref.read(calibrationProvider.notifier).clearPoints()
                      : null,
                  icon: const Icon(Icons.clear_all),
                  label: const Text('Clear Data'),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Status indicator
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: calibrationState.isCalibrating
                    ? Colors.orange.withOpacity(0.2)
                    : Colors.grey.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    calibrationState.isCalibrating ? Icons.build : Icons.build_outlined,
                    color: calibrationState.isCalibrating ? Colors.orange : Colors.grey,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    calibrationState.isCalibrating
                        ? 'Calibration in Progress - Step ${calibrationState.currentStep + 1}'
                        : 'Calibration Idle',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Add calibration point form
            if (calibrationState.isCalibrating) ...[
              Text('Add Calibration Point', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _expectedController,
                      decoration: const InputDecoration(
                        labelText: 'Expected Value',
                        suffixText: 'mm',
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextField(
                      controller: _measuredController,
                      decoration: const InputDecoration(
                        labelText: 'Measured Value',
                        suffixText: 'mm',
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton.icon(
                    onPressed: _addPoint,
                    icon: const Icon(Icons.add),
                    label: const Text('Add'),
                  ),
                ],
              ),
              const SizedBox(height: 24),
            ],

            // Calibration data table
            Text('Calibration Data', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Expanded(
              child: _buildCalibrationTable(calibrationState.points),
            ),
          ],
        ),
      ),
    );
  }

  void _addPoint() {
    final expected = double.tryParse(_expectedController.text);
    final measured = double.tryParse(_measuredController.text);

    if (expected != null && measured != null) {
      final point = CalibrationPoint(
        step: ref.read(calibrationProvider).currentStep + 1,
        expectedValue: expected,
        measuredValue: measured,
        error: measured - expected,
        timestamp: DateTime.now(),
      );

      ref.read(calibrationProvider.notifier).addPoint(point);
      _expectedController.clear();
      _measuredController.clear();
    }
  }

  Widget _buildCalibrationTable(List<CalibrationPoint> points) {
    if (points.isEmpty) {
      return Center(
        child: Text(
          'No calibration data yet',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Step')),
          DataColumn(label: Text('Expected (mm)')),
          DataColumn(label: Text('Measured (mm)')),
          DataColumn(label: Text('Error (mm)')),
          DataColumn(label: Text('Error %')),
          DataColumn(label: Text('Time')),
        ],
        rows: points.map((point) {
          final errorPercent = point.expectedValue != 0
              ? (point.error / point.expectedValue * 100).abs()
              : 0.0;

          return DataRow(
            cells: [
              DataCell(Text('${point.step}')),
              DataCell(Text(point.expectedValue.toStringAsFixed(3))),
              DataCell(Text(point.measuredValue.toStringAsFixed(3))),
              DataCell(
                Text(
                  point.error.toStringAsFixed(3),
                  style: TextStyle(
                    color: point.error.abs() > 0.5 ? Colors.red : Colors.green,
                  ),
                ),
              ),
              DataCell(
                Text(
                  '${errorPercent.toStringAsFixed(2)}%',
                  style: TextStyle(
                    color: errorPercent > 1.0 ? Colors.red : Colors.green,
                  ),
                ),
              ),
              DataCell(Text(
                '${point.timestamp.hour}:${point.timestamp.minute.toString().padLeft(2, '0')}',
              )),
            ],
          );
        }).toList(),
      ),
    );
  }
}
