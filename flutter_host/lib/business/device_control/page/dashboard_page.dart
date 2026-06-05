import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smt_host_app/app/router/app_router.dart';
import 'package:smt_host_app/business/device_control/view_model/device_viewmodels.dart';
import 'package:smt_host_app/component/serial/serial_service.dart';
import 'package:smt_host_app/foundation/widgets/metric_display.dart';

class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});

  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage> {
  @override
  Widget build(BuildContext context) {
    final connectionState = ref.watch(connectionStateProvider);
    final deviceStatusAsync = ref.watch(deviceStatusProvider);
    final isConnected = connectionState == ConnectionState.connected;

    return Scaffold(
      appBar: AppBar(
        title: const Text('SMT Host Controller'),
        actions: [
          _buildConnectionIndicator(connectionState),
          const SizedBox(width: 16),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Quick actions row
            _buildQuickActions(context, isConnected),
            const SizedBox(height: 24),
            
            // Status section
            Text('Device Status', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 16),
            
            deviceStatusAsync.when(
              data: (status) => _buildStatusGrid(status),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, stack) => Text('Error: $err', style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
            
            const SizedBox(height: 24),
            
            // Navigation cards
            Text('Modules', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 16),
            Expanded(
              child: _buildModuleGrid(context, isConnected),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionIndicator(ConnectionState state) {
    Color color;
    String label;
    
    switch (state) {
      case ConnectionState.connected:
        color = Colors.green;
        label = 'Connected';
        break;
      case ConnectionState.connecting:
        color = Colors.orange;
        label = 'Connecting...';
        break;
      case ConnectionState.error:
        color = Colors.red;
        label = 'Error';
        break;
      default:
        color = Colors.grey;
        label = 'Disconnected';
    }
    
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontSize: 14)),
      ],
    );
  }

  Widget _buildQuickActions(BuildContext context, bool isConnected) {
    return Row(
      children: [
        ElevatedButton.icon(
          onPressed: () => context.push(AppRouter.connection),
          icon: const Icon(Icons.usb),
          label: const Text('Connection'),
        ),
        const SizedBox(width: 12),
        ElevatedButton.icon(
          onPressed: isConnected 
              ? () => ref.read(motorControlProvider.notifier).home() 
              : null,
          icon: const Icon(Icons.home),
          label: const Text('Home'),
        ),
        const SizedBox(width: 12),
        ElevatedButton.icon(
          onPressed: isConnected 
              ? () => ref.read(motorControlProvider.notifier).stop() 
              : null,
          icon: const Icon(Icons.stop),
          label: const Text('Stop'),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
        ),
        const SizedBox(width: 12),
        ElevatedButton.icon(
          onPressed: isConnected 
              ? () => ref.read(deviceRepositoryProvider).getStatus() 
              : null,
          icon: const Icon(Icons.refresh),
          label: const Text('Refresh'),
        ),
      ],
    );
  }

  Widget _buildStatusGrid(dynamic status) {
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: [
        MetricDisplay(
          label: 'Motor A Position',
          value: status?.motorAPosition?.toStringAsFixed(2) ?? '--',
          unit: 'mm',
          icon: Icons.straighten,
        ),
        MetricDisplay(
          label: 'Motor B Position',
          value: status?.motorBPosition?.toStringAsFixed(2) ?? '--',
          unit: 'mm',
          icon: Icons.straighten,
        ),
        MetricDisplay(
          label: 'Motor A Speed',
          value: status?.motorAVelocity?.toStringAsFixed(2) ?? '--',
          unit: 'mm/s',
          icon: Icons.speed,
        ),
        MetricDisplay(
          label: 'Motor B Speed',
          value: status?.motorBVelocity?.toStringAsFixed(2) ?? '--',
          unit: 'mm/s',
          icon: Icons.speed,
        ),
      ],
    );
  }

  Widget _buildModuleGrid(BuildContext context, bool isConnected) {
    final modules = [
      ('Connection', Icons.usb, AppRouter.connection, Colors.blue),
      ('PID Config', Icons.tune, AppRouter.pidConfig, Colors.purple),
      ('Calibration', Icons.build, AppRouter.calibration, Colors.orange),
      ('Visualization', Icons.show_chart, AppRouter.visualization, Colors.green),
    ];

    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 1.5,
      ),
      itemCount: modules.length,
      itemBuilder: (context, index) {
        final (label, icon, route, color) = modules[index];
        return Card(
          child: InkWell(
            onTap: () => context.push(route),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 48, color: color),
                  const SizedBox(height: 12),
                  Text(label, style: Theme.of(context).textTheme.titleLarge),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
