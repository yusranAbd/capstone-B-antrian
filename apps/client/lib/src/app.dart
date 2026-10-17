import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'admin.dart';
import 'api.dart';
import 'display.dart';
import 'patient.dart';
import 'queue.dart';
import 'mobile_ui.dart';

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
  bool display = false;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.api,
    builder: (context, _) {
      final api = widget.api;
      if (display) {
        return DisplayPage(
          api: api,
          onExit: () => setState(() => display = false),
        );
      }
      if (api.user == null) {
        return LoginPage(
          api: api,
          onDisplay: () => setState(() => display = true),
        );
      }
      final role = api.user!['peran'];
      return Theme(
        data: role == 'ADMIN' ? Theme.of(context) : QueueBStyle.theme,
        child: Scaffold(
          appBar: AppBar(
            title: role == 'ADMIN'
                ? const Text('QueueB · ADMIN')
                : const QueueBBrand(compact: true),
            actions: [
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
                    /* Local session is already cleared. */
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
                _ => PatientPage(
                  api: api,
                  onDisplay: () => setState(() => display = true),
                ),
              },
            ),
          ),
        ),
      );
    },
  );
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.api, required this.onDisplay});
  final QueueApi api;
  final VoidCallback onDisplay;
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
        backgroundColor: QueueBStyle.mint,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: AutofillGroup(
                  child: Form(
                    key: form,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const QueueBBrand(),
                        const SizedBox(height: 24),
                        Text(
                          'Akses mudah untuk\npelayanan lebih baik',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Daftar, dapatkan tiket, dan ikuti antrean rumah sakit dalam satu aplikasi.',
                          style: TextStyle(color: QueueBStyle.muted),
                        ),
                        const HospitalVisual(),
                        Text(
                          register ? 'Daftar akun pasien' : 'Masuk untuk mengelola pelayanan atau tiket Anda.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (error != null)
                                MobileNotice(error!, error: true),
                              if (message != null) MobileNotice(message!),
                              if (register)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 16),
                                  child: TextFormField(
                                    controller: name,
                                    decoration: const InputDecoration(
                                      labelText: 'Nama lengkap',
                                    ),
                                    validator: (v) =>
                                        v == null ||
                                            v.trim().length < 3 ||
                                            v.length > 150
                                        ? 'Nama 3–150 karakter.'
                                        : null,
                                  ),
                                ),
                              TextFormField(
                                controller: email,
                                keyboardType: TextInputType.emailAddress,
                                autofillHints: const [AutofillHints.username],
                                decoration: const InputDecoration(
                                  labelText: 'Email',
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
                                controller: password,
                                obscureText: obscure,
                                autofillHints: const [AutofillHints.password],
                                decoration: InputDecoration(
                                  labelText: 'Kata sandi',
                                  suffixIcon: IconButton(
                                    tooltip: 'Tampilkan kata sandi',
                                    onPressed: () =>
                                        setState(() => obscure = !obscure),
                                    icon: Icon(
                                      obscure
                                          ? Icons.visibility
                                          : Icons.visibility_off,
                                    ),
                                  ),
                                ),
                                onFieldSubmitted: (_) => submit(),
                                validator: (v) => v == null || v.isEmpty
                                    ? 'Kata sandi wajib diisi.'
                                    : register &&
                                          (v.length < 8 || v.length > 72)
                                    ? 'Kata sandi 8–72 karakter.'
                                    : null,
                              ),
                              const SizedBox(height: 24),
                              FilledButton(
                                onPressed: busy ? null : submit,
                                child: Text(
                                  busy
                                      ? 'Memproses…'
                                      : register
                                      ? 'Daftar pasien'
                                      : 'Masuk',
                                ),
                              ),
                              TextButton(
                                onPressed: busy
                                    ? null
                                    : () => setState(() {
                                        register = !register;
                                        error = null;
                                      }),
                                child: Text(
                                  register
                                      ? 'Sudah punya akun? Masuk'
                                      : 'Pasien baru? Daftar',
                                ),
                              ),
                              const Divider(),
                              TextButton.icon(
                                onPressed: busy ? null : widget.onDisplay,
                                icon: const Icon(Icons.tv),
                                label: const Text('Buka Public Display'),
                              ),
                            ],
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
    ),
  );
}
