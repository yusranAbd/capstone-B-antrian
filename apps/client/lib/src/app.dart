import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';

import 'routing/app_router.dart';

import 'admin_ui.dart';
import 'api.dart';
import 'user_profile.dart';
import 'doctor_visual.dart';
import 'mobile_ui.dart';
import 'login_ui.dart';
import 'patient_design.dart';
import 'staff_v4.dart';
import 'queueb_palette.dart';

class QueueBApp extends StatefulWidget {
  const QueueBApp({super.key, required this.api});
  final QueueApi api;
  @override
  State<QueueBApp> createState() => _QueueBAppState();
}

class _QueueBAppState extends State<QueueBApp> {
  late AppRouting routing = AppRouting(widget.api);
  @override
  void didUpdateWidget(covariant QueueBApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.api != widget.api) {
      routing.dispose();
      routing = AppRouting(widget.api);
    }
  }

  @override
  void dispose() {
    routing.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    routerConfig: routing.router,
    title: 'QueueB Hospital',
    debugShowCheckedModeBanner: false,
    locale: const Locale('id'),
    supportedLocales: const [Locale('id'), Locale('en')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: QueueBPalette.primary,
      ).copyWith(primary: QueueBPalette.primary, secondary: QueueBPalette.cyan),
      scaffoldBackgroundColor: QueueBPalette.background,
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        filled: true,
        fillColor: Colors.white,
      ),
      cardTheme: const CardThemeData(elevation: 0, color: Colors.white),
    ),
  );
}

PreferredSizeWidget portalHeader(
  BuildContext context,
  QueueApi api,
  VoidCallback openProfile, {
  VoidCallback? onActivity,
  Widget? staffContext,
}) {
  final role = api.user?['peran'];
  if (role == 'PETUGAS') {
    return StaffToolbar(
      selection: staffContext ?? const SizedBox(),
      avatar: AccountAvatar(api: api, radius: 18),
      name: (api.user?['nama'] ?? 'Petugas').toString(),
      onProfile: openProfile,
    );
  }
  return AppBar(
    automaticallyImplyLeading: role != 'USER',
    toolbarHeight: role == 'USER'
        ? 48
        : role == 'ADMIN'
        ? 52
        : role == 'DOKTER'
        ? 64
        : role == 'PETUGAS'
        ? 60
        : null,
    title: role == 'USER'
        ? null
        : staffContext != null && MediaQuery.sizeOf(context).width >= 700
        ? Row(
            children: [
              const Flexible(child: QueueBBrand(compact: true)),
              Expanded(flex: 3, child: staffContext),
            ],
          )
        : const QueueBBrand(compact: true),
    actions: [
      if (role == 'USER')
        IconButton(
          tooltip: 'Aktivitas tiket',
          onPressed: onActivity,
          icon: const Icon(Icons.notifications_none_rounded),
        ),

      if (['DOKTER', 'PETUGAS'].contains(role) &&
          MediaQuery.sizeOf(context).width >= 700)
        ProfileHeaderIdentity(api: api),
      if (role != 'USER' && role != 'ADMIN')
        IconButton(
          tooltip: 'Profil akun',
          icon: ExcludeSemantics(child: AccountAvatar(api: api, radius: 16)),
          onPressed: openProfile,
        ),
      if (role != 'USER')
        IconButton(
          tooltip: 'Keluar akun',
          icon: const Icon(Icons.logout),
          onPressed: () async {
            try {
              await api.logout();
            } catch (_) {
              /* Session gate reports cleanup failures and server confirmation. */
            }
          },
        ),
    ],
  );
}

class PortalFrame extends StatelessWidget {
  const PortalFrame({
    super.key,
    required this.api,
    required this.role,
    required this.child,
  });
  final QueueApi api;
  final String role;
  final Widget child;
  @override
  Widget build(BuildContext context) => Theme(
    data: role == 'ADMIN'
        ? AdminStyle.theme
        : role == 'DOKTER'
        ? DoctorStyle.theme
        : role == 'USER'
        ? PatientDesign.theme
        : QueueBStyle.theme,
    child: Builder(
      builder: (context) => Scaffold(
        appBar: role == 'USER' || role == 'PETUGAS'
            ? null
            : portalHeader(
                context,
                api,
                () => context.go(
                  '${role == 'ADMIN' ? '/admin' : '/doctor'}/profile',
                ),
              ),
        body: SafeArea(top: false, child: child),
      ),
    ),
  );
}

/// Authentication boundary only; dashboards keep their existing UI.
class SessionGate extends StatelessWidget {
  const SessionGate({super.key, required this.api});
  final QueueApi api;
  @override
  Widget build(BuildContext context) {
    final waiting = [
      SessionPhase.restoring,
      SessionPhase.signingOut,
    ].contains(api.sessionPhase);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (waiting) const CircularProgressIndicator(),
                  const SizedBox(height: 20),
                  Text(
                    waiting
                        ? api.sessionPhase == SessionPhase.signingOut
                              ? 'Menutup sesi…'
                              : 'Memulihkan sesi…'
                        : api.sessionPhase == SessionPhase.storageError
                        ? 'Penyimpanan sesi belum tersedia'
                        : 'Koneksi sesi belum tersedia',
                    style: Theme.of(context).textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  if (api.sessionMessage != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        api.sessionMessage!,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  if (!waiting) ...[
                    FilledButton(
                      onPressed: () async {
                        try {
                          await api.restoreSession();
                        } catch (_) {}
                      },
                      child: const Text('Coba lagi'),
                    ),
                    TextButton(
                      onPressed: () async {
                        try {
                          await api.logout();
                        } catch (_) {}
                      },
                      child: const Text('Hapus sesi & kembali ke login'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    required this.api,
    required this.onDisplay,
    this.notice,
    this.registration,
    this.onRegistrationChanged,
  });
  final QueueApi api;
  final VoidCallback onDisplay;
  final String? notice;
  final bool? registration;
  final ValueChanged<bool>? onRegistrationChanged;
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final form = GlobalKey<FormState>();
  final email = TextEditingController();
  final password = TextEditingController();
  final name = TextEditingController();
  bool _register = false, busy = false, obscure = true;
  bool get register => widget.registration ?? _register;
  void changeRegistration(bool value) {
    if (widget.onRegistrationChanged case final callback?) {
      callback(value);
    } else {
      _register = value;
    }
  }

  String? error, message;
  Future<void> submit() async {
    if (busy || !form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
      message = null;
    });
    try {
      if (register) {
        await widget.api.register(name.text, email.text, password.text);
        if (mounted) {
          setState(() {
            changeRegistration(false);
            message = 'Akun pasien dibuat. Silakan masuk.';
          });
        }
      } else {
        await widget.api.login(email.text, password.text);
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: PatientDesign.theme,
    child: Builder(
      builder: (context) => Scaffold(
        backgroundColor: LoginStyle.paper,
        body: SafeArea(
          child: LoginLayout(
            child: LoginFormCard(
              child: AutofillGroup(
                child: Form(
                  key: form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Center(child: QueueBBrand(compact: true)),
                      const SizedBox(height: 20),
                      Text(
                        register ? 'Daftar' : 'Masuk',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 25,
                          fontWeight: FontWeight.w800,
                          color: PatientDesign.ink,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        register
                            ? 'Daftar akun pasien'
                            : 'Akses sistem antrean rumah sakit',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: PatientDesign.muted,
                          fontSize: 13,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 24),
                      if (widget.notice != null)
                        Semantics(
                          container: true,
                          liveRegion: true,
                          label: widget.notice!,
                          excludeSemantics: true,
                          child: MobileNotice(widget.notice!),
                        ),
                      if (error != null)
                        Semantics(
                          container: true,
                          liveRegion: true,
                          label: error!,
                          excludeSemantics: true,
                          child: MobileNotice(error!, error: true),
                        ),
                      if (message != null)
                        Semantics(
                          container: true,
                          liveRegion: true,
                          label: message!,
                          excludeSemantics: true,
                          child: MobileNotice(message!),
                        ),
                      if (register) ...[
                        TextFormField(
                          key: const ValueKey('login-name'),
                          controller: name,
                          style: LoginStyle.inputText,
                          enabled: !busy,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.name],
                          decoration: const InputDecoration(
                            labelText: 'Nama lengkap',
                            prefixIcon: Icon(Icons.person_outline),
                            alignLabelWithHint: true,
                          ),
                          validator: (v) =>
                              v == null || v.trim().length < 3 || v.length > 150
                              ? 'Nama 3–150 karakter.'
                              : null,
                        ),
                        const SizedBox(height: 16),
                      ],
                      TextFormField(
                        key: const ValueKey('login-email'),
                        controller: email,
                        style: LoginStyle.inputText,
                        enabled: !busy,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.username],
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          hintText: 'nama@email.com',
                          prefixIcon: Icon(Icons.mail_outline),
                        ),
                        validator: (v) =>
                            v == null ||
                                !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                                    .hasMatch(v.trim())
                            ? 'Masukkan email yang valid.'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        key: const ValueKey('login-password'),
                        controller: password,
                        style: LoginStyle.inputText,
                        enabled: !busy,
                        obscureText: obscure,
                        textInputAction: TextInputAction.done,
                        autofillHints: [
                          register
                              ? AutofillHints.newPassword
                              : AutofillHints.password,
                        ],
                        decoration: InputDecoration(
                          labelText: 'Kata sandi',
                          hintText: 'Masukkan kata sandi',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            tooltip: obscure
                                ? 'Tampilkan kata sandi'
                                : 'Sembunyikan kata sandi',
                            onPressed: busy
                                ? null
                                : () => setState(() => obscure = !obscure),
                            icon: Icon(
                              obscure
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                        onFieldSubmitted: (_) => submit(),
                        validator: (v) => v == null || v.isEmpty
                            ? 'Kata sandi wajib diisi.'
                            : register && (v.length < 8 || v.length > 72)
                            ? 'Kata sandi 8–72 karakter.'
                            : null,
                      ),
                      const SizedBox(height: 20),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(48, 48),
                        ),
                        onPressed: busy ? null : submit,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (busy) ...[
                              const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                              const SizedBox(width: 10),
                            ],
                            Flexible(
                              child: Text(
                                busy
                                    ? 'Memproses…'
                                    : register
                                    ? 'Daftar pasien'
                                    : 'Masuk',
                              ),
                            ),
                            if (!busy) ...[
                              const SizedBox(width: 16),
                              const Icon(Icons.arrow_forward_rounded, size: 21),
                            ],
                          ],
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Row(
                          children: [
                            Expanded(child: Divider(color: LoginStyle.rule)),
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: 14),
                              child: Text(
                                'atau',
                                style: TextStyle(
                                  color: PatientDesign.muted,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            Expanded(child: Divider(color: LoginStyle.rule)),
                          ],
                        ),
                      ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: PatientDesign.primary,
                          side: const BorderSide(color: PatientDesign.primary),
                          minimumSize: const Size(48, 48),
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              LoginStyle.fieldRadius,
                            ),
                          ),
                          textStyle: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        onPressed: busy ? null : widget.onDisplay,
                        icon: const Icon(
                          Icons.desktop_windows_outlined,
                          size: 20,
                        ),
                        label: const Text('Masuk ke Public Display'),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: busy
                            ? null
                            : () => setState(() {
                                changeRegistration(!register);
                                error = null;
                                message = null;
                              }),
                        child: Text(
                          register
                              ? 'Sudah punya akun? Masuk'
                              : 'Pasien baru? Daftar',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
