import 'package:flutter/material.dart';

import 'app.dart';
import 'config/app_config.dart';
import 'platform/desktop_bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await bootstrapDesktopShell();
  runApp(MutandeApp(config: AppConfig.fromEnvironment()));
}
