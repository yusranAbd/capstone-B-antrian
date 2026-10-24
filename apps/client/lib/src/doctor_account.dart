import 'package:flutter/material.dart';

import 'api.dart';
import 'config.dart';
import 'mobile_ui.dart';
import 'admin_ui.dart';

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
  final email = TextEditingController(), password = TextEditingController();
  String? user;
  List<Json> accounts = [];
  bool loadingAccounts = false;
  bool link = false, busy = false;
  String? error;
  @override
  void dispose() {
    email.dispose();
    password.dispose();
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
            ? {'penggunaId': user}
            : {'email': email.text.trim(), 'kataSandi': password.text},
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> loadAccounts() async {
    setState(() {
      loadingAccounts = true;
      error = null;
    });
    try {
      final result = rows(
        await widget.api.request('GET', '/dokter/akun-tersedia'),
      );
      if (mounted) setState(() => accounts = result);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => loadingAccounts = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
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
                  MobileNotice(
                    'Akun login: ${object(widget.doctor['pengguna'])['email'] ?? 'Tertaut'}. '
                    'Status akun: ${object(widget.doctor['pengguna'])['aktif'] == true
                        ? 'aktif'
                        : object(widget.doctor['pengguna'])['aktif'] == false
                        ? 'nonaktif'
                        : 'belum tersedia'}. '
                    'Status profil: ${widget.doctor['aktif'] == true ? 'aktif' : 'nonaktif'}. '
                    'Pelepasan atau penggantian akun belum didukung. Menonaktifkan profil memblokir akses portal.',
                  )
                else ...[
                  const Text(
                    'Satu profil hanya dapat memiliki satu akun DOKTER. Registrasi pasien tidak digunakan.',
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Tautkan akun DOKTER existing'),
                    value: link,
                    onChanged: busy || loadingAccounts
                        ? null
                        : (v) {
                            setState(() => link = v);
                            if (v) loadAccounts();
                          },
                  ),
                  if (link)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (loadingAccounts) const LinearProgressIndicator(),
                        AdminSearchChoice(
                          label: 'Akun DOKTER (nama / email)',
                          choices: accounts
                              .map(
                                (a) => (
                                  '${a['id']}',
                                  '${a['nama']} · ${a['email']}',
                                ),
                              )
                              .toList(),
                          value: user,
                          onChanged: busy || loadingAccounts
                              ? null
                              : (v) => setState(() => user = v),
                        ),
                        if (!loadingAccounts && accounts.isEmpty)
                          const Text(
                            'Tidak ada akun DOKTER aktif yang belum ditautkan.',
                          ),
                        TextButton(
                          onPressed: busy || loadingAccounts
                              ? null
                              : loadAccounts,
                          child: const Text('Muat ulang akun tersedia'),
                        ),
                      ],
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
            onPressed: busy || loadingAccounts ? null : submit,
            child: Text(
              busy
                  ? 'Memproses…'
                  : link
                  ? 'Tautkan akun'
                  : 'Buat akun DOKTER',
            ),
          ),
      ],
    ),
  );
}
