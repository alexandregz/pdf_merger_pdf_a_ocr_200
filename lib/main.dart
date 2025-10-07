import 'dart:async';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'app.dart';

Future<void> main() async {
  // Necesario para inicializar plugins antes de runApp
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  // Cambiar título da xanela
  await windowManager.setTitle('CIG Combinador PDF - OCR · PDF/A');

  // Fixar tamaño mínimo da xanela
  await windowManager.setMinimumSize(const Size(900, 600));

  runApp(const App());
}
