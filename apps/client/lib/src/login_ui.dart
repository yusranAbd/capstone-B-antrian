import 'package:flutter/material.dart';

import 'mobile_ui.dart';

// Hallmark · modern-minimal · centered authentication card · QueueB teal/navy.
// Pre-emit critique: P5 H5 E4 S5 R5 V4; user-approved centered layout takes priority.
// Scoped presentation tokens. Authentication stays in the existing LoginPage.
abstract final class LoginStyle {
  static const paper = Color(0xfff3f8fc);
  static const rule = Color(0xffdce9ef);
  static const white = Colors.white;
  static const shadow = Color(0x100f2a43);
  static const cardWidth = 420.0;
  static const cardRadius = 18.0;
  static const fieldRadius = 12.0;
  static const inputText = TextStyle(fontSize: 14, color: QueueBStyle.navy);
}

/// Centers the natural-height form; scrolling only becomes possible when the
/// keyboard, accessibility text size, or a short viewport reduces usable space.
class LoginLayout extends StatelessWidget {
  const LoginLayout({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: LoginStyle.paper,
    child: LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        key: const ValueKey('login-scroll'),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: LoginStyle.cardWidth,
                ),
                child: child,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class LoginFormCard extends StatelessWidget {
  const LoginFormCard({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(LoginStyle.fieldRadius),
      borderSide: const BorderSide(color: LoginStyle.rule),
    );
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: LoginStyle.white,
        borderRadius: BorderRadius.circular(LoginStyle.cardRadius),
        border: Border.all(color: LoginStyle.rule),
        boxShadow: const [
          BoxShadow(
            color: LoginStyle.shadow,
            blurRadius: 32,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Theme(
        data: theme.copyWith(
          inputDecorationTheme: theme.inputDecorationTheme.copyWith(
            isDense: true,
            labelStyle: LoginStyle.inputText.copyWith(color: QueueBStyle.muted),
            hintStyle: LoginStyle.inputText.copyWith(color: QueueBStyle.muted),
            prefixIconColor: QueueBStyle.muted,
            prefixIconConstraints: const BoxConstraints(
              minWidth: 44,
              minHeight: 48,
            ),
            suffixIconConstraints: const BoxConstraints(
              minWidth: 44,
              minHeight: 48,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 14,
            ),
            border: border,
            enabledBorder: border,
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              minimumSize: const Size(48, 48),
              textStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(LoginStyle.fieldRadius),
              ),
            ),
          ),
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(
              minimumSize: const Size(44, 44),
              textStyle: const TextStyle(fontSize: 13),
            ),
          ),
        ),
        child: child,
      ),
    );
  }
}
