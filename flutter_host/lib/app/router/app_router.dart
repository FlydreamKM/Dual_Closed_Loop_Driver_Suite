import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:smt_host_app/business/device_control/page/dashboard_page.dart';
import 'package:smt_host_app/business/device_control/page/connection_page.dart';
import 'package:smt_host_app/business/device_control/page/pid_config_page.dart';
import 'package:smt_host_app/business/device_control/page/calibration_page.dart';
import 'package:smt_host_app/business/visualization/page/data_visualization_page.dart';

class AppRouter {
  static const String home = '/';
  static const String connection = '/connection';
  static const String pidConfig = '/pid-config';
  static const String calibration = '/calibration';
  static const String visualization = '/visualization';

  static GoRouter createRouter() {
    return GoRouter(
      initialLocation: home,
      routes: [
        GoRoute(
          path: home,
          builder: (context, state) => const DashboardPage(),
        ),
        GoRoute(
          path: connection,
          builder: (context, state) => const ConnectionPage(),
        ),
        GoRoute(
          path: pidConfig,
          builder: (context, state) => const PidConfigPage(),
        ),
        GoRoute(
          path: calibration,
          builder: (context, state) => const CalibrationPage(),
        ),
        GoRoute(
          path: visualization,
          builder: (context, state) => const DataVisualizationPage(),
        ),
      ],
    );
  }
}
