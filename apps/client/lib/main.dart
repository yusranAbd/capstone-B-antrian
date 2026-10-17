import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:timezone/data/latest.dart' as tz;

import 'src/api.dart';
import 'src/app.dart';
import 'src/config.dart';
import 'src/session_store.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();
  SemanticsBinding.instance.ensureSemantics();
  final config = AppConfig.fromEnvironment();
  final api = QueueApi(
    config: config,
    sessionStore: platformSessionStore('${config.apiBase}'),
  );
  unawaited(api.restoreSession().catchError((Object _) {}));
  runApp(QueueBApp(api: api));
}
