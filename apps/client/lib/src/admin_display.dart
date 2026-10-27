import 'admin_delete.dart';

import 'package:flutter/material.dart';

import 'api.dart';
import 'admin_ui.dart';
import 'config.dart';
import 'widgets.dart';

class AdminDisplayPage extends StatefulWidget {
  const AdminDisplayPage({super.key, required this.api});
  final QueueApi api;
  @override
  State<AdminDisplayPage> createState() => _AdminDisplayPageState();
}

class _AdminDisplayPageState extends State<AdminDisplayPage> {
  List<Json> devices = [], clinics = [];
  bool busy = false;
  String search = '';
  String? error, clinic;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final data = await Future.wait([
        widget.api.request('GET', '/perangkat-display'),
        widget.api.request('GET', '/layanan'),
      ]);
      if (mounted) {
        setState(() {
          devices = rows(data[0]);
          clinics = rows(data[1]);
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> addDevice() async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _DeviceEditor(
        api: widget.api,
        clinics: clinics.where((c) => c['aktif'] == true).toList(),
      ),
    );
    if (mounted && changed == true) {
      await load();
    }
  }

  Future<void> activateDevice(Json device) async {
    if (!await confirm(
      context,
      'Buat kode aktivasi untuk ${device['nama']}? Koneksi dan kredensial lama langsung dicabut. Kode sebelumnya tidak berlaku.',
    )) {
      return;
    }
    if (!mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = object(
        await widget.api.request(
          'POST',
          '/perangkat-display/${device['id']}/aktivasi',
        ),
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Kode aktivasi sekali pakai'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${device['nama']} · ${label(object(device['layanan']))}'),
                const SizedBox(height: 20),
                SelectableText(
                  '${result['kode']}',
                  style: Theme.of(ctx).textTheme.headlineLarge
                      ?.copyWith(letterSpacing: 3, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                Text(
                  'Berlaku hingga ${widget.api.config.instantLabel(result['berlakuHingga'])} (${widget.api.config.serviceTimeZone}), maksimal 5 menit.',
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
      );
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
    if (mounted && error == null) await load();
  }

  Future<void> deactivateDevice(Json device) async {
    if (!await confirm(
      context,
      'Nonaktifkan ${device['nama']}? Seluruh kredensial dan koneksi perangkat ini akan dicabut.',
    )) {
      return;
    }
    if (!mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.api.request(
        'POST',
        '/perangkat-display/${device['id']}/nonaktifkan',
      );
      await load();
    } catch (e) {
      if (mounted) {
        setState(() {
          error = '$e';
          busy = false;
        });
      }
    }
  }

  Future<void> editDevice(Json device) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) =>
          _DeviceEditor(api: widget.api, clinics: clinics, device: device),
    );
    if (mounted && changed == true) {
      await load();
    }
  }

  Future<void> deleteDevice(Json device) async {
    final result = await showAdminDelete(
      context,
      widget.api,
      '/perangkat-display',
      device,
    );
    if (!mounted) return;
    if (result == AdminDeleteResult.deactivate) {
      await deactivateDevice(device);
      return;
    }
    if (result == AdminDeleteResult.deleted) {
      await load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Perangkat berhasil dihapus permanen.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
                onPressed: busy ? null : load,
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
  const _DeviceEditor({required this.api, required this.clinics, this.device});
  final QueueApi api;
  final List<Json> clinics;
  final Json? device;
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
      await widget.api.request(
        widget.device == null ? 'POST' : 'PATCH',
        widget.device == null
            ? '/perangkat-display'
            : '/perangkat-display/${widget.device!['id']}',
        body: {
          'nama': name.text.trim(),
          if (widget.device == null) 'layananId': clinic,
        },
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
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
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Poliklinik'),
                  items: [
                    for (final c in widget.clinics)
                      DropdownMenuItem(
                        value: '${c['id']}',
                        child: Text(label(c)),
                      ),
                  ],
                  onChanged: busy ? null : (v) => clinic = v,
                  validator: (v) =>
                      v == null ? 'Pilih poliklinik aktif.' : null,
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
