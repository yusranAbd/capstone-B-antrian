import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:timezone/data/latest.dart' as tz;

import 'src/api.dart';
import 'src/app.dart';
import 'src/config.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();
  SemanticsBinding.instance.ensureSemantics();
  runApp(QueueBApp(api: QueueApi(config: AppConfig.fromEnvironment())));
}
