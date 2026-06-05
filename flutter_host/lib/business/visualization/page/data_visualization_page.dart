import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:smt_host_app/business/device_control/view_model/device_viewmodels.dart';
import 'package:smt_host_app/business/device_control/model/device_models.dart';
import 'package:smt_host_app/component/serial/serial_service.dart';

class DataVisualizationPage extends ConsumerStatefulWidget {
  const DataVisualizationPage({super.key});

  @override
  ConsumerState<DataVisualizationPage> createState() => _DataVisualizationPageState();
}

class _DataVisualizationPageState extends ConsumerState<DataVisualizationPage> {
  bool _isStreaming = false;
  String _selectedChannel = 'Motor A';

  final List<String> _channels = ['Motor A', 'Motor B', 'A Speed', 'B Speed'];
  final Map<String, Color> _channelColors = {
    'Motor A': Colors.blue,
    'Motor B': Colors.green,
    'A Speed': Colors.orange,
    'B Speed': Colors.purple,
  };

  @override
  Widget build(BuildContext context) {
    final dataSamples = ref.watch(dataStreamProvider);
    final isConnected = ref.watch(connectionStateProvider) == SerialConnectionState.connected;

    // Filter samples by selected channel
    final channelSamples = dataSamples.where((s) => s.label == _selectedChannel).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Data Visualization')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Controls
            Row(
              children: [
                // Channel selector
                SegmentedButton<String>(
                  segments: _channels.map((ch) => ButtonSegment(
                    value: ch,
                    label: Text(ch),
                  )).toList(),
                  selected: {_selectedChannel},
                  onSelectionChanged: (set) => setState(() => _selectedChannel = set.first),
                ),
                const SizedBox(width: 24),
                
                // Stream toggle
                ElevatedButton.icon(
                  onPressed: isConnected
                      ? () => _toggleStream()
                      : null,
                  icon: Icon(_isStreaming ? Icons.stop : Icons.play_arrow),
                  label: Text(_isStreaming ? 'Stop Stream' : 'Start Stream'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isStreaming ? Colors.red : Colors.green,
                  ),
                ),
                const SizedBox(width: 12),
                
                // Clear button
                ElevatedButton.icon(
                  onPressed: () => ref.read(dataStreamProvider.notifier).clear(),
                  icon: const Icon(Icons.clear),
                  label: const Text('Clear'),
                ),
                const SizedBox(width: 12),
                
                // Sample count
                Text(
                  'Samples: ${channelSamples.length}',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ],
            ),
            
            const SizedBox(height: 24),
            
            // Real-time chart
            Expanded(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: _buildChart(channelSamples),
                ),
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Statistics
            _buildStatistics(channelSamples),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleStream() async {
    if (_isStreaming) {
      await ref.read(dataStreamProvider.notifier).stopStream();
      setState(() => _isStreaming = false);
    } else {
      await ref.read(dataStreamProvider.notifier).startStream();
      setState(() => _isStreaming = true);
    }
  }

  Widget _buildChart(List<DataSample> samples) {
    if (samples.isEmpty) {
      return Center(
        child: Text(
          'No data - Start stream to collect',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      );
    }

    // Take last 200 samples for performance
    final displaySamples = samples.length > 200 
        ? samples.sublist(samples.length - 200) 
        : samples;

    final spots = displaySamples.asMap().entries.map((entry) {
      return FlSpot(entry.key.toDouble(), entry.value.value);
    }).toList();

    final minY = displaySamples.map((s) => s.value).reduce((a, b) => a < b ? a : b);
    final maxY = displaySamples.map((s) => s.value).reduce((a, b) => a > b ? a : b);
    final padding = (maxY - minY) * 0.1;

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: (maxY - minY) / 5,
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, meta) => Text(
                value.toStringAsFixed(1),
                style: const TextStyle(fontSize: 10),
              ),
            ),
          ),
          bottomTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
        ),
        borderData: FlBorderData(show: true),
        minX: 0,
        maxX: displaySamples.length.toDouble() - 1,
        minY: minY - padding,
        maxY: maxY + padding,
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: _channelColors[_selectedChannel] ?? Colors.blue,
            barWidth: 2,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: (_channelColors[_selectedChannel] ?? Colors.blue).withOpacity(0.1),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatistics(List<DataSample> samples) {
    if (samples.isEmpty) {
      return const SizedBox.shrink();
    }

    final values = samples.map((s) => s.value).toList();
    final mean = values.reduce((a, b) => a + b) / values.length;
    final min = values.reduce((a, b) => a < b ? a : b);
    final max = values.reduce((a, b) => a > b ? a : b);
    final variance = values.length > 1 ? values.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) / (values.length - 1) : 0.0;
    final stdDev = sqrt(variance);

    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: [
        _buildStatCard('Mean', mean.toStringAsFixed(3), 'mm', Colors.blue),
        _buildStatCard('Min', min.toStringAsFixed(3), 'mm', Colors.green),
        _buildStatCard('Max', max.toStringAsFixed(3), 'mm', Colors.orange),
        _buildStatCard('Std Dev', stdDev.toStringAsFixed(3), 'mm', Colors.purple),
        _buildStatCard('Range', (max - min).toStringAsFixed(3), 'mm', Colors.red),
      ],
    );
  }

  Widget _buildStatCard(String label, String value, String unit, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  value,
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 4),
                Text(unit, style: const TextStyle(fontSize: 12)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}