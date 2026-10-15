import 'package:flutter/material.dart';

import 'admin_schema.dart';
import 'api.dart';
import 'config.dart';
import 'widgets.dart';

class AdminPage extends StatefulWidget {
  const AdminPage({super.key, required this.api});
  final QueueApi api;
  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  int selected = 0;
  Map<String, List<Json>> catalog = {};
  List<Json> data = [];
  String? session, error, message;
  bool loading = true;
  int revision = 0;
  AdminResource get resource => resources[selected];
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final current = ++revision;
    final selectedResource = resource;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final paths = resources
          .where((r) => r.path != '/slot-praktik')
          .map((r) => r.path)
          .toList();
      final values = await Future.wait(
        paths.map((path) async => rows(await widget.api.request('GET', path))),
      );
      final next = {for (int i = 0; i < paths.length; i++) paths[i]: values[i]};
      List<Json> items;
      if (selectedResource.path == '/slot-praktik') {
        if (!next['/jadwal-praktik']!.any((v) => v['id'] == session)) {
          session = next['/jadwal-praktik']!.firstOrNull?['id'];
        }
        items = session == null
            ? []
            : rows(
                await widget.api.request(
                  'GET',
                  '/slot-praktik',
                  query: {'jadwalPraktikId': session!},
                ),
              );
      } else {
        items = next[selectedResource.path]!;
      }
      if (mounted && current == revision) {
        setState(() {
          catalog = next;
          data = items;
        });
      }
    } catch (e) {
      if (mounted && current == revision) setState(() => error = '$e');
    } finally {
      if (mounted && current == revision) setState(() => loading = false);
    }
  }

  Future<void> edit([Json? row]) async {
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _AdminEditor(
        api: widget.api,
        resource: resource,
        row: row,
        catalog: catalog,
        initialSession: session,
      ),
    );
    if (changed == true && mounted) {
      setState(() => message = 'Data disimpan.');
      await load();
    }
  }

  Future<void> deactivateRow(Json row) async {
    if (!await confirm(
      context,
      'Nonaktifkan ${label(row)}? Riwayat tetap disimpan.',
    )) {
      return;
    }
    setState(() => loading = true);
    try {
      await widget.api.request('DELETE', '${resource.path}/${row['id']}');
      if (mounted) setState(() => message = 'Data dinonaktifkan.');
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) {
        final previousError = error;
        await load();
        if (mounted && previousError != null) {
          setState(() => error = previousError);
        }
      }
    }
  }

  Future<void> doctorLinks(Json doctor) async {
    await showDialog<void>(
      context: context,
      builder: (context) => _DoctorLinks(
        api: widget.api,
        doctor: doctor,
        services: catalog['/layanan'] ?? [],
      ),
    );
    if (mounted) await load();
  }

  String detail(Json row) => switch (resource.path) {
    '/layanan' =>
      '${row['kode']} · ${row['modeReservasi']} · ${row['durasiDasarMenit']} menit',
    '/dokter' =>
      '${row['kode']} · ${row['spesialisasi'] ?? 'Dokter'}\n${rows(row['dokterLayanan']).where((v) => v['aktif'] == true).map((v) => label(object(v['layanan']))).join(', ')}',
    '/jadwal-praktik' =>
      '${label(object(object(row['dokterLayanan'])['dokter']))} · ${label(object(row['loket']))}\n${widget.api.config.instantLabel(row['mulaiPada'])} – ${widget.api.config.instantLabel(row['selesaiPada'])}',
    '/slot-praktik' =>
      '${widget.api.config.instantLabel(row['mulaiPada'])} – ${widget.api.config.instantLabel(row['selesaiPada'])}\n${row['jumlahJanjiTemu']} terisi / ${row['kapasitas']} · ${row['tersedia'] == true ? 'Tersedia' : 'Tidak tersedia'}',
    '/jadwal-layanan' =>
      '${label(object(row['layanan']))} · ${row['hari']}\n${clockOnly(row['jamBuka'])}–${clockOnly(row['jamTutup'])} · Kuota ${row['kapasitasHarian']}',
    '/penugasan-petugas' =>
      '${label(object(row['petugas']))} · ${label(object(row['loket']))}\n${dateOnly(row['tanggalMulai'])} → ${row['tanggalSelesai'] == null ? 'Tanpa akhir' : dateOnly(row['tanggalSelesai'])}',
    _ => '${label(object(row['layanan']))} · ${row['lokasi'] ?? ''}',
  };
  @override
  Widget build(BuildContext context) {
    final content = ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(resource.title, style: Theme.of(context).textTheme.headlineSmall),
        Text('Zona pelayanan: ${widget.api.config.serviceTimeZone}'),
        if (error != null) Notice(error!, error: true),
        if (message != null) Notice(message!),
        if (resource.path == '/penugasan-petugas')
          const Notice(
            'Akun ADMIN/PETUGAS disediakan pengelola server. Gunakan ID akun dari profil petugas untuk memberikan penugasan.',
          ),
        if (resource.path == '/slot-praktik')
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: ChoiceField(
              label: 'Sesi untuk daftar slot',
              choices: (catalog['/jadwal-praktik'] ?? [])
                  .map(
                    (v) => (
                      '${v['id']}',
                      '${dateOnly(v['tanggal'])} · ${label(object(object(v['dokterLayanan'])['dokter']))} · ${label(object(v['loket']))}',
                    ),
                  )
                  .toList(),
              value: session,
              onChanged: loading
                  ? null
                  : (value) {
                      session = value;
                      load();
                    },
            ),
          ),
        Wrap(
          spacing: 12,
          children: [
            FilledButton.icon(
              onPressed: loading ? null : () => edit(),
              icon: const Icon(Icons.add),
              label: const Text('Tambah'),
            ),
            OutlinedButton.icon(
              onPressed: loading ? null : load,
              icon: const Icon(Icons.refresh),
              label: const Text('Muat ulang'),
            ),
          ],
        ),
        if (loading) const LinearProgressIndicator(),
        if (!loading && data.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Text('Belum ada data.'),
          ),
        ...data.map(
          (row) => Section(
            title: resource.path == '/penugasan-petugas'
                ? label(object(row['petugas']))
                : resource.path == '/jadwal-praktik'
                ? dateOnly(row['tanggal'])
                : resource.path == '/slot-praktik'
                ? 'Slot konsultasi'
                : label(row),
            subtitle: detail(row),
            child: Wrap(
              spacing: 10,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                stateChip(row['aktif'] == true ? 'AKTIF' : 'NONAKTIF'),
                TextButton.icon(
                  onPressed: loading ? null : () => edit(row),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Ubah'),
                ),
                if (row['aktif'] == true)
                  TextButton(
                    onPressed: loading ? null : () => deactivateRow(row),
                    child: const Text('Nonaktifkan'),
                  ),
                if (resource.path == '/dokter')
                  OutlinedButton(
                    onPressed: loading ? null : () => doctorLinks(row),
                    child: const Text('Hubungkan poliklinik'),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth >= 960
          ? Row(
              children: [
                NavigationRail(
                  extended: true,
                  selectedIndex: selected,
                  onDestinationSelected: loading
                      ? null
                      : (i) {
                          setState(() {
                            selected = i;
                            message = null;
                            data = [];
                          });
                          load();
                        },
                  destinations: [
                    for (final r in resources)
                      NavigationRailDestination(
                        icon: Icon(_icon(r.path)),
                        label: Text(r.title),
                      ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: content),
              ],
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: ChoiceField(
                    label: 'Administrasi',
                    choices: [
                      for (int i = 0; i < resources.length; i++)
                        ('$i', resources[i].title),
                    ],
                    value: '$selected',
                    onChanged: loading
                        ? null
                        : (value) {
                            setState(() {
                              selected = int.parse(value!);
                              message = null;
                              data = [];
                            });
                            load();
                          },
                  ),
                ),
                Expanded(child: content),
              ],
            ),
    );
  }

  IconData _icon(String path) => switch (path) {
    '/dokter' => Icons.medical_services_outlined,
    '/loket' => Icons.meeting_room_outlined,
    '/jadwal-layanan' => Icons.access_time,
    '/jadwal-praktik' => Icons.calendar_month_outlined,
    '/slot-praktik' => Icons.event_available,
    '/penugasan-petugas' => Icons.badge_outlined,
    _ => Icons.local_hospital_outlined,
  };
}

class _AdminEditor extends StatefulWidget {
  const _AdminEditor({
    required this.api,
    required this.resource,
    required this.catalog,
    this.row,
    this.initialSession,
  });
  final QueueApi api;
  final AdminResource resource;
  final Map<String, List<Json>> catalog;
  final Json? row;
  final String? initialSession;
  @override
  State<_AdminEditor> createState() => _AdminEditorState();
}

class _AdminEditorState extends State<_AdminEditor> {
  final form = GlobalKey<FormState>();
  final Map<String, TextEditingController> controllers = {};
  final Map<String, String> values = {};
  bool busy = false;
  String? error;
  bool get editing => widget.row != null;
  List<AdminField> get fields => widget.resource.fields
      .where((f) => !(editing && f.createOnly) && !(!editing && f.editOnly))
      .toList();
  @override
  void initState() {
    super.initState();
    for (final f in fields) {
      final v = widget.row?[f.key];
      values[f.key] = v == null
          ? f.key == 'jadwalPraktikId'
                ? widget.initialSession ?? ''
                : f.initial
          : switch (f.kind) {
              FieldKind.instant => widget.api.config.localInput(v),
              FieldKind.clock => clockOnly(v),
              FieldKind.date => dateOnly(v),
              _ => '$v',
            };
      controllers[f.key] = TextEditingController(text: values[f.key]);
    }
  }

  List<(String, String)> options(AdminField field) {
    if (field.options.isNotEmpty) {
      return field.options.map((v) => (v, v.replaceAll('_', ' '))).toList();
    }
    if (field.key == 'layananId') {
      return choicesOf(widget.catalog['/layanan'] ?? []);
    }
    if (field.key == 'loketId') {
      final links = (widget.catalog['/dokter'] ?? []).expand(
        (d) => rows(d['dokterLayanan']),
      );
      final service = links
          .where((v) => v['id'] == values['dokterLayananId'])
          .firstOrNull?['layananId'];
      return choicesOf(
        (widget.catalog['/loket'] ?? [])
            .where((v) => service == null || v['layananId'] == service)
            .toList(),
      );
    }
    if (field.key == 'dokterLayananId') {
      return [
        for (final d in widget.catalog['/dokter'] ?? <Json>[])
          for (final l in rows(
            d['dokterLayanan'],
          ).where((v) => v['aktif'] == true))
            ('${l['id']}', '${label(d)} · ${label(object(l['layanan']))}'),
      ];
    }
    if (field.key == 'jadwalPraktikId') {
      return (widget.catalog['/jadwal-praktik'] ?? [])
          .map(
            (v) => (
              '${v['id']}',
              '${dateOnly(v['tanggal'])} · ${label(object(object(v['dokterLayanan'])['dokter']))} · ${label(object(v['loket']))}',
            ),
          )
          .toList();
    }
    return [];
  }

  Future<void> save() async {
    if (busy || !form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.api.request(
        editing ? 'PATCH' : 'POST',
        '${widget.resource.path}${editing ? '/${widget.row!['id']}' : ''}',
        body: adminPayload(widget.resource, values, editing, widget.api.config),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          error = '$e';
          busy = false;
        });
      }
    }
  }

  @override
  void dispose() {
    for (final c in controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      title: Text('${editing ? 'Ubah' : 'Tambah'} ${widget.resource.title}'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Zona waktu: ${widget.api.config.serviceTimeZone}'),
                if (error != null) Notice(error!, error: true),
                for (final f in fields)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: switch (f.kind) {
                      FieldKind.flag => SwitchListTile(
                        title: Text(f.title),
                        value: values[f.key] == 'true',
                        onChanged: busy
                            ? null
                            : (v) => setState(() => values[f.key] = '$v'),
                      ),
                      FieldKind.choice => ChoiceField(
                        label: f.title,
                        choices: options(f),
                        value: values[f.key],
                        required: f.required,
                        onChanged: busy
                            ? null
                            : (v) => setState(() {
                                values[f.key] = v ?? '';
                                if (f.key == 'dokterLayananId') {
                                  values['loketId'] = '';
                                }
                              }),
                      ),
                      _ => TextFormField(
                        controller: controllers[f.key],
                        enabled: !busy,
                        decoration: InputDecoration(labelText: f.title),
                        keyboardType: f.kind == FieldKind.integer
                            ? TextInputType.number
                            : TextInputType.text,
                        onChanged: (v) => values[f.key] = v.trim(),
                        validator: (v) => validateAdminField(
                          f,
                          v?.trim() ?? '',
                          widget.api.config,
                        ),
                      ),
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context, false),
          child: const Text('Kembali'),
        ),
        FilledButton(
          onPressed: busy ? null : save,
          child: Text(busy ? 'Menyimpan…' : 'Simpan'),
        ),
      ],
    ),
  );
}

class _DoctorLinks extends StatefulWidget {
  const _DoctorLinks({
    required this.api,
    required this.doctor,
    required this.services,
  });
  final QueueApi api;
  final Json doctor;
  final List<Json> services;
  @override
  State<_DoctorLinks> createState() => _DoctorLinksState();
}

class _DoctorLinksState extends State<_DoctorLinks> {
  List<Json> links = [];
  String? service, error;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    links = rows(widget.doctor['dokterLayanan']);
  }

  Future<void> mutate([String? remove]) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final path = '/dokter/${widget.doctor['id']}/layanan';
      await widget.api.request(
        remove == null ? 'POST' : 'DELETE',
        remove == null ? path : '$path/$remove',
        body: remove == null ? {'layananId': service} : null,
      );
      final result = rows(await widget.api.request('GET', path));
      if (mounted) setState(() => links = result);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      title: Text('Poliklinik ${label(widget.doctor)}'),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (error != null) Notice(error!, error: true),
              ...links
                  .where((l) => l['aktif'] == true)
                  .map(
                    (l) => ListTile(
                      title: Text(label(object(l['layanan']))),
                      trailing: IconButton(
                        tooltip: 'Lepaskan poliklinik',
                        onPressed: busy
                            ? null
                            : () => mutate('${l['layananId']}'),
                        icon: const Icon(Icons.link_off),
                      ),
                    ),
                  ),
              ChoiceField(
                label: 'Poliklinik untuk dihubungkan',
                choices: choicesOf(
                  widget.services.where((v) => v['aktif'] == true).toList(),
                ),
                value: service,
                onChanged: busy ? null : (v) => setState(() => service = v),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: busy || service == null ? null : () => mutate(),
                child: const Text('Hubungkan'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('Tutup'),
        ),
      ],
    ),
  );
}
