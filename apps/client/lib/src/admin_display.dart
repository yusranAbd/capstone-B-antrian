import 'admin_delete.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'features/admin/application/admin_catalog_state.dart';
import 'features/admin/application/display_management_cubit.dart';
import 'features/admin/application/display_management_state.dart';
import 'features/admin/data/admin_catalog_repository.dart';
import 'features/admin/data/admin_display_repository.dart';
import 'features/admin/models/admin_display_models.dart';

import 'api.dart';
import 'admin_ui.dart';
import 'config.dart';
import 'widgets.dart';

class AdminDisplayPage extends StatefulWidget {
  const AdminDisplayPage({super.key, required this.api, this.cubit});
  final QueueApi api;
  final DisplayManagementCubit? cubit;
  @override
  State<AdminDisplayPage> createState() => _AdminDisplayPageState();
}

class _AdminDisplayPageState extends State<AdminDisplayPage> {
  late final DisplayManagementCubit controller;
  AdminCatalogRepository? ownedCatalog;
  List<Json> get devices => controller.devices;
  List<Json> get clinics => controller.clinics;
  bool get busy => controller.state.busy;
  String search = '';
  String? clinic;
  String? get error => controller.state.error?.toString();
  @override
  void initState() {
    super.initState();
    ownedCatalog = widget.cubit == null
        ? AdminCatalogRepository(widget.api)
        : null;
    controller =
        widget.cubit ??
        DisplayManagementCubit(AdminDisplayRepository(ownedCatalog!));
    if (controller.state.load == CatalogLoadStatus.initial) {
      controller.refresh();
    }
  }

  @override
  void dispose() {
    if (ownedCatalog != null) controller.close();
    ownedCatalog?.dispose();
    super.dispose();
  }

  Future<void> addDevice() async {
    await showDialog<bool>(
      context: context,
      builder: (_) => _DeviceEditor(cubit: controller),
    );
  }

  Future<void> activateDevice(Json device) async {
    if (!await confirm(
      context,
      '${controller.state.uncertainActivations.contains(device['id']) ? 'Hasil rotasi sebelumnya belum pasti. Kode sekali tampil tidak dapat dipulihkan dari metadata. Penerbitan ini adalah rotasi baru. ' : ''}Buat kode aktivasi untuk ${device['nama']}? Koneksi dan kredensial lama langsung dicabut. Kode sebelumnya tidak berlaku.',
    )) {
      return;
    }
    if (!mounted) return;
    DisplayActivation? activation;
    try {
      activation = await controller.activate(
        '${device['id']}',
        confirmedReplacement: true,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => _ActivationScope(
          api: widget.api,
          activation: activation!,
          child: AlertDialog(
            title: const Text('Kode aktivasi sekali pakai'),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${device['nama']} · ${label(object(device['layanan']))}',
                  ),
                  const SizedBox(height: 20),
                  SelectableText(
                    activation.code ?? '',
                    style: Theme.of(ctx).textTheme.headlineLarge?.copyWith(
                      letterSpacing: 3,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Berlaku hingga ${widget.api.config.instantLabel(activation.expiresAt.toIso8601String())} (${widget.api.config.serviceTimeZone}), maksimal 5 menit.',
                  ),
                  const Text(
                    'Berikan melalui saluran aman. Kode hanya ditampilkan sekarang; jangan bagikan tangkapan layar atau menaruhnya dalam URL.',
                  ),
                ],
              ),
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Selesai'),
              ),
            ],
          ),
        ),
      );
    } catch (_) {
      // The Cubit publishes only a safe error, never the one-time response.
    } finally {
      activation?.clear();
      controller.finishDisclosure();
    }
  }

  Future<void> deactivateDevice(Json device) async {
    if (!await confirm(
      context,
      'Nonaktifkan ${device['nama']}? Seluruh kredensial dan koneksi perangkat ini akan dicabut.',
    )) {
      return;
    }
    if (!mounted) return;
    try {
      await controller.revoke('${device['id']}');
    } catch (_) {
      /* Safe operation state is rendered below. */
    }
  }

  Future<void> editDevice(Json device) async {
    await showDialog<bool>(
      context: context,
      builder: (_) => _DeviceEditor(device: device, cubit: controller),
    );
  }

  Future<void> deleteDevice(Json device) async {
    final result = await showAdminDelete(
      context,
      widget.api,
      '/perangkat-display',
      device,
      onDelete: () => controller.delete('${device['id']}'),
    );
    if (!mounted) return;
    if (result == AdminDeleteResult.deactivate) {
      await deactivateDevice(device);
      return;
    }
    if (result == AdminDeleteResult.deleted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Perangkat berhasil dihapus permanen.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => BlocProvider.value(
    value: controller,
    child: BlocBuilder<DisplayManagementCubit, DisplayManagementState>(
      bloc: controller,
      builder: (context, _) => content(context),
    ),
  );
  Widget content(BuildContext context) {
    final filtered = devices
        .where(
          (d) =>
              (clinic == null || d['layananId'] == clinic) &&
              '${d['nama']} ${label(object(d['layanan']))}'
                  .toLowerCase()
                  .contains(search.toLowerCase()),
        )
        .toList();
    return ListView(
      padding: const EdgeInsets.all(AdminStyle.pagePadding),
      children: [
        Text(
          'Manajemen Display',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 4),
        const Text(
          'Siapkan satu TV untuk satu poliklinik. Beberapa TV dapat menggunakan poliklinik yang sama.',
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, box) => Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: box.maxWidth < 560 ? box.maxWidth : 280,
                child: TextField(
                  decoration: const InputDecoration(
                    labelText: 'Cari perangkat atau poliklinik',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (v) => setState(() => search = v),
                ),
              ),
              SizedBox(
                width: box.maxWidth < 560 ? box.maxWidth : 220,
                child: DropdownButtonFormField<String>(
                  initialValue: clinic,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Poliklinik display',
                  ),
                  items: [
                    const DropdownMenuItem<String>(
                      value: null,
                      child: Text('Semua poliklinik'),
                    ),
                    for (final c in clinics)
                      DropdownMenuItem(
                        value: '${c['id']}',
                        child: Text(label(c)),
                      ),
                  ],
                  onChanged: (v) => setState(() => clinic = v),
                ),
              ),
              FilledButton.icon(
                onPressed: busy ? null : addDevice,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Tambah perangkat'),
              ),
              OutlinedButton.icon(
                onPressed: busy ? null : controller.refresh,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Muat ulang'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: busy ? 4 : 0,
          child: busy ? const LinearProgressIndicator() : null,
        ),
        error != null ? Notice(error!, error: true) : const SizedBox.shrink(),
        !busy && error == null && filtered.isEmpty
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Belum ada perangkat yang sesuai. Tambahkan perangkat untuk memulai aktivasi.',
                ),
              )
            : const SizedBox.shrink(),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'Status aktif adalah izin perangkat, bukan indikator online.',
            style: TextStyle(fontSize: 12),
          ),
        ),
        AdminTable(
          key: ValueKey('$clinic:$search'),
          rows: filtered,
          columns: [
            AdminColumn('Nama perangkat', (d) => d['nama']),
            AdminColumn('Poliklinik', (d) => label(object(d['layanan']))),
            AdminColumn(
              'Status akses',
              (d) => d['aktif'] == true ? 'Aktif' : 'Nonaktif',
            ),
            AdminColumn(
              'Terakhir terhubung',
              (d) => d['terakhirAktifPada'] == null
                  ? 'Belum tersedia'
                  : widget.api.config.instantLabel(d['terakhirAktifPada']),
            ),
            AdminColumn(
              'Aksi',
              (_) => '',
              cell: (d) => AdminRowActions(
                tooltip: 'Aksi display ${d['nama']}',
                busy: busy,
                actions: [
                  AdminRowAction(
                    d['aktif'] == true
                        ? 'Kode aktivasi / rotasi'
                        : 'Reaktivasi',
                    Icons.key,
                    () => activateDevice(d),
                    enabled: object(d['layanan'])['aktif'] == true,
                  ),
                  AdminRowAction(
                    'Ubah',
                    Icons.edit_outlined,
                    () => editDevice(d),
                  ),
                  if (d['aktif'] == true)
                    AdminRowAction(
                      'Nonaktifkan',
                      Icons.block_outlined,
                      () => deactivateDevice(d),
                      danger: true,
                    ),
                  AdminRowAction(
                    'Hapus',
                    Icons.delete_outline,
                    () => deleteDevice(d),
                    danger: true,
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

class _DeviceEditor extends StatefulWidget {
  const _DeviceEditor({this.device, required this.cubit});
  final Json? device;
  final DisplayManagementCubit cubit;
  @override
  State<_DeviceEditor> createState() => _DeviceEditorState();
}

class _DeviceEditorState extends State<_DeviceEditor> {
  final form = GlobalKey<FormState>();
  final name = TextEditingController();
  String? clinic, error;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    name.text = widget.device?['nama'] as String? ?? '';
  }

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (!form.currentState!.validate() || busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (widget.device == null) {
        await widget.cubit.create({
          'nama': name.text.trim(),
          'layananId': clinic,
        });
      } else {
        await widget.cubit.update('${widget.device!['id']}', name.text.trim());
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          error = '${safeDisplayError(e)}';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.cubit.repository.catalog,
    builder: (context, _) => dialog(context),
  );
  Widget dialog(BuildContext context) => AlertDialog(
    title: Text(
      widget.device == null
          ? 'Tambah perangkat display'
          : 'Ubah nama perangkat display',
    ),
    content: SizedBox(
      width: 440,
      child: Form(
        key: form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (error != null) Notice(error!, error: true),
              TextFormField(
                controller: name,
                maxLength: 100,
                decoration: const InputDecoration(labelText: 'Nama perangkat'),
                validator: (v) => (v?.trim().length ?? 0) < 3
                    ? 'Nama minimal 3 karakter.'
                    : null,
              ),
              if (widget.device == null)
                DropdownButtonFormField<String>(
                  key: ValueKey(
                    widget.cubit.clinics
                        .where((c) => c['aktif'] == true)
                        .map((c) => c['id'])
                        .join(','),
                  ),
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Poliklinik'),
                  items: [
                    for (final c in widget.cubit.clinics.where(
                      (c) => c['aktif'] == true,
                    ))
                      DropdownMenuItem(
                        value: '${c['id']}',
                        child: Text(label(c)),
                      ),
                  ],
                  onChanged: busy ? null : (v) => clinic = v,
                  validator: (v) =>
                      widget.cubit.clinics.any(
                        (c) => c['id'] == v && c['aktif'] == true,
                      )
                      ? null
                      : 'Pilih poliklinik aktif.',
                ),
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
        child: const Text('Simpan perangkat'),
      ),
    ],
  );
}

/// Ephemeral presentation scope: clears the one-time code on close, expiry or
/// account/role change. This timer is cleanup, not device polling.
class _ActivationScope extends StatefulWidget {
  const _ActivationScope({
    required this.api,
    required this.activation,
    required this.child,
  });
  final QueueApi api;
  final DisplayActivation activation;
  final Widget child;
  @override
  State<_ActivationScope> createState() => _ActivationScopeState();
}

class _ActivationScopeState extends State<_ActivationScope> {
  late final (Object?, Object?) identity;
  Timer? expiry;
  bool closing = false;
  @override
  void initState() {
    super.initState();
    identity = (widget.api.user?['id'], widget.api.user?['peran']);
    widget.api.addListener(sessionChanged);
    final remaining = widget.activation.expiresAt.difference(
      widget.api.config.now,
    );
    expiry = Timer(
      remaining.isNegative
          ? Duration.zero
          : remaining > const Duration(minutes: 5)
          ? const Duration(minutes: 5)
          : remaining,
      dismiss,
    );
  }

  void sessionChanged() {
    if (identity != (widget.api.user?['id'], widget.api.user?['peran']) ||
        widget.api.sessionPhase != SessionPhase.ready) {
      dismiss();
    }
  }

  void dismiss() {
    widget.activation.clear();
    if (!mounted || closing) return;
    closing = true;
    final route = ModalRoute.of(context);
    if (route?.isCurrent == true) {
      Navigator.of(context).pop();
    } else if (route != null && route.isActive) {
      route.navigator?.removeRoute(route);
    }
  }

  @override
  void dispose() {
    expiry?.cancel();
    widget.api.removeListener(sessionChanged);
    widget.activation.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
