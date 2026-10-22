import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'admin.dart';
import 'admin_ui.dart';
import 'api.dart';
import 'display.dart';
import 'doctor.dart';
import 'patient.dart';
import 'queue.dart';
import 'mobile_ui.dart';
import 'login_ui.dart';

class QueueBApp extends StatelessWidget {
  const QueueBApp({super.key, required this.api});
  final QueueApi api;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'QueueB Hospital',
    debugShowCheckedModeBanner: false,
    locale: const Locale('id'),
    supportedLocales: const [Locale('id'), Locale('en')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff245cdb)),
      scaffoldBackgroundColor: const Color(0xfff4f6fa),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        filled: true,
        fillColor: Colors.white,
      ),
      cardTheme: const CardThemeData(elevation: 0, color: Colors.white),
    ),
    routes: {
      '/display': (context) => DisplayPage(
        api: api,
        onExit: () => Navigator.of(context).popUntil((r) => r.isFirst),
      ),
    },
    home: _Root(api: api),
  );
}

class _Root extends StatefulWidget {
  const _Root({required this.api});
  final QueueApi api;
  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> {
  @override
  void initState() {
    super.initState();
    widget.api.addListener(_sessionChanged);
  }

  void _sessionChanged() {
    if (widget.api.user != null &&
        widget.api.sessionPhase == SessionPhase.ready) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          (widget.api.user == null ||
              widget.api.sessionPhase != SessionPhase.ready)) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    });
  }

  @override
  void didUpdateWidget(covariant _Root oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.api != widget.api) {
      oldWidget.api.removeListener(_sessionChanged);
      widget.api.addListener(_sessionChanged);
    }
  }

  @override
  void dispose() {
    widget.api.removeListener(_sessionChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.api,
    builder: (context, _) {
      final api = widget.api;
      if (api.sessionPhase != SessionPhase.ready) return _SessionGate(api: api);
      if (api.user == null) {
        return LoginPage(
          api: api,
          notice: api.sessionMessage,
          onDisplay: () => Navigator.of(context).pushNamed('/display'),
        );
      }
      final role = api.user!['peran'];
      return Theme(
        data: role == 'ADMIN' ? AdminStyle.theme : QueueBStyle.theme,
        child: Scaffold(
          appBar: AppBar(
            title: const QueueBBrand(compact: true),
            actions: [
              if (role == 'ADMIN' && MediaQuery.sizeOf(context).width >= 700)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Center(
                    child: SizedBox(
                      width: 140,
                      child: Text(
                        '${api.user!['nama']} · ADMIN',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                ),
              IconButton(
                tooltip: 'Profil akun',
                icon: const Icon(Icons.account_circle_outlined),
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text('${api.user!['nama']}'),
                    content: SelectableText(
                      '${api.user!['email']}\nPeran: $role\nID akun: ${api.user!['id']}',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(text: '${api.user!['id']}'),
                          );
                          if (context.mounted) Navigator.pop(context);
                        },
                        child: const Text('Salin ID akun'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Tutup'),
                      ),
                    ],
                  ),
                ),
              ),
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
          ),
          body: SafeArea(
            top: false,
            child: KeyedSubtree(
              key: ValueKey(api.user!['id']),
              child: switch (role) {
                'ADMIN' => AdminPage(api: api),
                'PETUGAS' => QueuePage(api: api),
                'DOKTER' => DoctorPage(api: api),
                _ => PatientPage(
                  api: api,
                  onDisplay: () => Navigator.of(context).pushNamed('/display'),
                ),
              },
            ),
          ),
        ),
      );
    },
  );
}

/// Authentication boundary only; dashboards keep their existing UI.
class _SessionGate extends StatelessWidget {
  const _SessionGate({required this.api});
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
  });
  final QueueApi api;
  final VoidCallback onDisplay;
  final String? notice;
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final form = GlobalKey<FormState>();
  final email = TextEditingController();
  final password = TextEditingController();
  final name = TextEditingController();
  bool register = false, busy = false, obscure = true;
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
            register = false;
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
    data: QueueBStyle.theme,
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
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        register ? 'Daftar' : 'Masuk',
                        style: Theme.of(context).textTheme.headlineLarge
                            ?.copyWith(
                              fontSize: MediaQuery.sizeOf(context).width < 600
                                  ? 32
                                  : 42,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -.8,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        register ? 'Daftar akun pasien' : 'Masuk untuk mengelola pelayanan atau tiket Anda.',
                        style: const TextStyle(
                          color: QueueBStyle.muted,
                          fontSize: 17,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 28),
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
                          liveRegion: true,
                          child: MobileNotice(error!, error: true),
                        ),
                      if (message != null)
                        Semantics(
                          liveRegion: true,
                          child: MobileNotice(message!),
                        ),
                      if (register) ...[
                        TextFormField(
                          key: const ValueKey('login-name'),
                          controller: name,
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
                        const SizedBox(height: 24),
                      ],
                      TextFormField(
                        key: const ValueKey('login-email'),
                        controller: email,
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
                      const SizedBox(height: 24),
                      TextFormField(
                        key: const ValueKey('login-password'),
                        controller: password,
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
                      const SizedBox(height: 30),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(48, 56),
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
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Row(
                          children: [
                            Expanded(child: Divider(color: LoginStyle.rule)),
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: 14),
                              child: Text(
                                'atau',
                                style: TextStyle(color: QueueBStyle.muted),
                              ),
                            ),
                            Expanded(child: Divider(color: LoginStyle.rule)),
                          ],
                        ),
                      ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: QueueBStyle.darkTeal,
                          side: const BorderSide(color: QueueBStyle.darkTeal),
                          minimumSize: const Size(48, 54),
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          textStyle: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        onPressed: busy ? null : widget.onDisplay,
                        icon: const Icon(
                          Icons.desktop_windows_outlined,
                          size: 23,
                        ),
                        label: const Text('Masuk ke Public Display'),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Lihat antrean langsung di layar publik rumah sakit tanpa perlu login.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: QueueBStyle.muted,
                          fontSize: 13,
                          height: 1.5,
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 22),
                        child: Divider(color: LoginStyle.rule),
                      ),
                      TextButton(
                        onPressed: busy
                            ? null
                            : () => setState(() {
                                register = !register;
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
