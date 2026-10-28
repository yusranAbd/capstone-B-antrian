import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'features/admin/application/staff_management_cubit.dart';
import 'features/admin/application/admin_catalog_state.dart';
import 'features/admin/models/admin_staff_models.dart';

import 'admin_ui.dart';
import 'api.dart';
import 'config.dart';
import 'widgets.dart';

class AdminStaffAccounts extends StatefulWidget {
  const AdminStaffAccounts({
    super.key,
    required this.api,
    required this.accounts,
    required this.busy,
    required this.onChanged,
    this.cubit,
  });
  final QueueApi api;
  final StaffAccountCubit? cubit;
  final List<Json> accounts;
  final bool busy;
  final Future<void> Function() onChanged;
  @override
  State<AdminStaffAccounts> createState() => _AdminStaffAccountsState();
}

class _AdminStaffAccountsState extends State<AdminStaffAccounts> {
  String search = '', status = '';
  bool saving = false;
  String? error, message;
  List<Json> get accounts => widget.cubit?.rows ?? widget.accounts;

  Future<void> create() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _StaffAccountEditor(
        api: widget.api,
        onCreate: widget.cubit == null
            ? null
            : (body) => widget.cubit!.createAccount(
                name: body['nama'] as String,
                email: body['email'] as String,
                password: body['kataSandi'] as String,
              ),
      ),
    );
    if (!mounted || result != true) return;
    setState(() {
      message = widget.cubit?.state.needsReconciliation == true
          ? 'Akun PETUGAS disimpan. Muat ulang daftar sebelum membuat penugasan.'
          : widget.cubit?.state.recoveredMutation == true
          ? 'Akun PETUGAS terverifikasi di daftar. Akun tersedia di Penugasan Loket.'
          : 'Akun PETUGAS dibuat. Akun langsung tersedia di Penugasan Loket.';
      error = null;
    });
    if (widget.cubit == null) await widget.onChanged();
  }

  Future<void> changeStatus(Json account) async {
    final active = account['aktif'] == true;
    if (!await confirm(
      context,
      active
          ? 'Nonaktifkan akun ${account['nama']}? Seluruh sesi login dicabut. Riwayat dan penugasan tetap tersimpan.'
          : 'Aktifkan kembali akun ${account['nama']}? Petugas harus login ulang. Penugasan yang masih berlaku dapat digunakan kembali.',
    )) {
      return;
    }
    if (!mounted) return;
    setState(() {
      saving = widget.cubit == null;
      error = null;
      message = null;
    });
    try {
      if (widget.cubit != null) {
        await widget.cubit!.setStatus('${account['id']}', !active);
      } else {
        await widget.api.request(
          'PATCH',
          '/akun-petugas/${account['id']}',
          body: {'aktif': !active},
        );
      }
      if (mounted) {
        setState(
          () => message = active
              ? 'Akun dinonaktifkan dan sesi dicabut.'
              : 'Akun diaktifkan. Silakan login ulang.',
        );
      }
      if (widget.cubit == null) await widget.onChanged();
    } catch (e) {
      if (mounted && widget.cubit == null) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => widget.cubit == null
      ? content(context)
      : BlocProvider.value(
          value: widget.cubit!,
          child: BlocBuilder<StaffAccountCubit, AdminCatalogState>(
            bloc: widget.cubit,
            builder: (context, _) => content(context),
          ),
        );
  Widget content(BuildContext context) {
    final busy = saving || widget.busy || widget.cubit?.state.busy == true;
    final operationError = widget.cubit?.state.error?.toString() ?? error;
    final filtered = accounts
        .where(
          (a) =>
              '${a['nama']} ${a['email']}'.toLowerCase().contains(search) &&
              (status.isEmpty || '${a['aktif']}' == status),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Kelola akses login petugas. Penempatan ruang dan periode diatur pada tab Penugasan Loket.',
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 280,
              child: TextField(
                decoration: const InputDecoration(
                  labelText: 'Cari nama atau email petugas',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (v) =>
                    setState(() => search = v.trim().toLowerCase()),
              ),
            ),
            SizedBox(
              width: 160,
              child: ChoiceField(
                label: 'Status akun',
                value: status,
                choices: const [
                  ('', 'Semua status'),
                  ('true', 'Aktif'),
                  ('false', 'Nonaktif'),
                ],
                onChanged: (v) => setState(() => status = v ?? ''),
              ),
            ),
            FilledButton.icon(
              onPressed: busy ? null : create,
              icon: const Icon(Icons.person_add_outlined, size: 18),
              label: const Text('Tambah akun PETUGAS'),
            ),
            OutlinedButton.icon(
              onPressed: busy ? null : widget.onChanged,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Muat ulang'),
            ),
          ],
        ),
        if (operationError != null) Notice(operationError, error: true),
        if (message != null) Notice(message!),
        if (saving) const LinearProgressIndicator(),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            '${filtered.length} dari ${accounts.length} akun PETUGAS',
          ),
        ),
        if (!busy &&
            filtered.isEmpty &&
            widget.cubit?.state.load != CatalogLoadStatus.failure)
          const Notice(
            'Belum ada akun yang sesuai. Tambahkan akun PETUGAS untuk memulai penugasan.',
          ),
        AdminTable(
          key: ValueKey('$search:$status'),
          rows: filtered,
          columns: [
            AdminColumn('Nama petugas', (a) => a['nama']),
            AdminColumn('Email login', (a) => a['email']),
            AdminColumn('Peran', (_) => 'PETUGAS'),
            AdminColumn(
              'Status akun',
              (a) => a['aktif'] == true ? 'Aktif' : 'Nonaktif',
              cell: (a) => stateChip(a['aktif'] == true ? 'AKTIF' : 'NONAKTIF'),
            ),
            AdminColumn(
              'Aksi',
              (_) => '',
              cell: (a) => AdminRowActions(
                tooltip: 'Aksi akun ${a['nama']}',
                busy: busy,
                actions: [
                  AdminRowAction(
                    a['aktif'] == true ? 'Nonaktifkan akun' : 'Aktifkan akun',
                    a['aktif'] == true
                        ? Icons.block_outlined
                        : Icons.check_circle_outline,
                    () => changeStatus(a),
                    danger: a['aktif'] == true,
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StaffAccountEditor extends StatefulWidget {
  const _StaffAccountEditor({required this.api, this.onCreate});
  final QueueApi api;
  final Future<Json> Function(Json)? onCreate;
  @override
  State<_StaffAccountEditor> createState() => _StaffAccountEditorState();
}

class _StaffAccountEditorState extends State<_StaffAccountEditor> {
  final form = GlobalKey<FormState>();
  final name = TextEditingController(),
      email = TextEditingController(),
      password = TextEditingController();
  bool busy = false;
  String? error;
  @override
  void dispose() {
    name.dispose();
    email.dispose();
    password.clear();
    password.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (busy || !form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final body = <String, dynamic>{
        'nama': name.text.trim(),
        'email': email.text.trim(),
        'kataSandi': password.text,
      };
      if (widget.onCreate != null) {
        await widget.onCreate!(body);
      } else {
        await widget.api.request('POST', '/akun-petugas', body: body);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          error = '${safeAccountCreateError(e)}';
        });
      }
    } finally {
      if (mounted) password.clear();
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      title: const Text('Buat akun PETUGAS'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Peran PETUGAS ditetapkan server. Gunakan email petugas dan berikan kata sandi awal melalui saluran aman.',
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: name,
                  enabled: !busy,
                  decoration: const InputDecoration(labelText: 'Nama petugas'),
                  validator: (v) =>
                      (v?.trim().length ?? 0) >= 3 && v!.trim().length <= 150
                      ? null
                      : 'Nama 3–150 karakter.',
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: email,
                  enabled: !busy,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email login'),
                  validator: (v) =>
                      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                              .hasMatch(v?.trim() ?? '') &&
                          (v?.trim().length ?? 0) <= 150
                      ? null
                      : 'Masukkan email yang valid.',
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: password,
                  enabled: !busy,
                  obscureText: true,
                  enableSuggestions: false,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Kata sandi awal',
                  ),
                  validator: (v) => v != null && v.length >= 8 && v.length <= 72
                      ? null
                      : 'Kata sandi 8–72 karakter.',
                ),
                if (error != null) Notice(error!, error: true),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: busy ? null : save,
          child: Text(busy ? 'Menyimpan…' : 'Buat akun PETUGAS'),
        ),
      ],
    ),
  );
}
