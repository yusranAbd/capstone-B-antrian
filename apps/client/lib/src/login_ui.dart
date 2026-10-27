import 'package:flutter/material.dart';

import 'patient_design.dart';

// Scoped presentation tokens. Authentication stays in the existing LoginPage.
abstract final class LoginStyle {
  static const paper = PatientDesign.background;
  static const rule = PatientDesign.border;
  static const white = PatientDesign.paper;
  static const shadow = Color(0x100f2a43);
  static const cardWidth = 420.0;
  static const cardRadius = 18.0;
  static const fieldRadius = 12.0;
  static const inputText = TextStyle(fontSize: 14, color: PatientDesign.ink);
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
      builder: (context, box) => SingleChildScrollView(
        key: const ValueKey('login-scroll'),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: box.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: box.maxWidth >= 960 ? 1000 : LoginStyle.cardWidth,
                ),
                child: box.maxWidth >= 960
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Expanded(child: _LoginWelcome()),
                          const SizedBox(width: 64),
                          SizedBox(width: LoginStyle.cardWidth, child: child),
                        ],
                      )
                    : child,
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
            labelStyle: LoginStyle.inputText.copyWith(
              color: PatientDesign.muted,
            ),
            hintStyle: LoginStyle.inputText.copyWith(
              color: PatientDesign.muted,
            ),
            prefixIconColor: PatientDesign.muted,
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

class _LoginWelcome extends StatelessWidget {
  const _LoginWelcome();
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      const Text(
        'KESEHATAN, LEBIH TERENCANA',
        style: TextStyle(
          fontSize: 11,
          letterSpacing: 1.5,
          color: PatientDesign.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 20),
      const Text(
        'Lebih tenang.\nDari awal kunjungan.',
        style: TextStyle(
          fontSize: 42,
          height: 1.1,
          letterSpacing: -1.4,
          fontWeight: FontWeight.w700,
          color: PatientDesign.ink,
        ),
      ),
      const SizedBox(height: 20),
      const Text(
        'Atur kunjungan, simpan tiket, dan ikuti antrean dalam satu tempat.',
        style: TextStyle(fontSize: 16, height: 1.5, color: PatientDesign.muted),
      ),
      const SizedBox(height: 32),
      for (final item in [
        ('01', 'Temukan dokter dan poliklinik'),
        ('02', 'Pilih jadwal yang tersedia'),
        ('03', 'Siapkan tiket QR saat datang'),
      ])
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: PatientDesign.soft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  item.$1,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: PatientDesign.primary,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  item.$2,
                  style: const TextStyle(
                    fontSize: 14,
                    color: PatientDesign.ink,
                  ),
                ),
              ),
            ],
          ),
        ),
    ],
  );
}
