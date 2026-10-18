import 'package:flutter/material.dart';

import 'api.dart';
import 'config.dart';
import 'mobile_ui.dart';

/// ADMIN-only provisioning; never promotes a patient or reassigns a linked profile.
class DoctorAccountDialog extends StatefulWidget {
  const DoctorAccountDialog({
    super.key,
    required this.api,
    required this.doctor,
  });
  final QueueApi api;
  final Json doctor;
  @override
  State<DoctorAccountDialog> createState() => _DoctorAccountDialogState();
}

class _DoctorAccountDialogState extends State<DoctorAccountDialog> {
  final form = GlobalKey<FormState>();
  final email = TextEditingController(),
      password = TextEditingController(),
      user = TextEditingController();
  bool link = false, busy = false;
  String? error;
  @override
  void dispose() {
    email.dispose();
    password.dispose();
    user.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (busy || !form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.api.request(
        'POST',
        '/dokter/${widget.doctor['id']}/akun',
        body: link
            ? {'penggunaId': user.text.trim()}
            : {'email': email.text.trim(), 'kataSandi': password.text},
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Akun portal dokter'),
    content: SizedBox(
      width: 440,
      child: SingleChildScrollView(
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('${widget.doctor['nama']}'),
              if (widget.doctor['penggunaId'] != null)
                const MobileNotice(
                  'Profil dokter sudah memiliki akun. Penautan ulang tidak tersedia.',
                )
              else ...[
                const Text(
                  'Satu profil hanya dapat memiliki satu akun DOKTER. Registrasi pasien tidak digunakan.',
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Tautkan akun DOKTER existing'),
                  value: link,
                  onChanged: busy ? null : (v) => setState(() => link = v),
                ),
                if (link)
                  TextFormField(
                    controller: user,
                    decoration: const InputDecoration(
                      labelText: 'ID akun DOKTER',
                    ),
                    validator: (v) =>
                        RegExp(
                          r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-[89aAbB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
                        ).hasMatch(v?.trim() ?? '')
                        ? null
                        : 'Masukkan UUID akun DOKTER.',
                  )
                else ...[
                  TextFormField(
                    controller: email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email dokter',
                    ),
                    validator: (v) =>
                        RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                            .hasMatch(v?.trim() ?? '')
                        ? null
                        : 'Masukkan email yang valid.',
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: password,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Kata sandi awal',
                    ),
                    validator: (v) =>
                        v != null && v.length >= 8 && v.length <= 72
                        ? null
                        : 'Kata sandi 8–72 karakter.',
                  ),
                ],
              ],
              if (error != null) MobileNotice(error!, error: true),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: busy ? null : () => Navigator.pop(context),
        child: const Text('Tutup'),
      ),
      if (widget.doctor['penggunaId'] == null)
        FilledButton(
          onPressed: busy ? null : submit,
          child: Text(
            busy
                ? 'Memproses…'
                : link
                ? 'Tautkan akun'
                : 'Buat akun DOKTER',
          ),
        ),
    ],
  );
}
