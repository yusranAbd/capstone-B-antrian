import 'package:flutter/material.dart';

/// Shared QueueB colors. Each portal retains its own type scale and layout.
abstract final class QueueBPalette {
  static const primary = Color(0xff4c60cc);
  static const hero = Color(0xff4169d5);
  static const cyan = Color(0xff007ca8);
  static const background = Color(0xfff2f5ff);
  static const paper = Colors.white;
  static const ink = Color(0xff172544);
  static const muted = Color(0xff52617a);
  static const border = Color(0xffd9e1f2);
  static const soft = Color(0xffeef1ff);
  // Darker blue surfaces keep operational text readable at a distance.
  static const console = Color(0xff1d3270);
  static const consoleEnd = Color(0xff314da3);
  static const onConsole = Colors.white;
  static const onConsoleMuted = Color(0xffe6edff);
}
