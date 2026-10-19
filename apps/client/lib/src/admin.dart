import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'admin_schema.dart';
import 'admin_display.dart';
import 'admin_practice_form.dart';
import 'doctor_account.dart';
import 'admin_data.dart';
import 'admin_navigation.dart';
import 'admin_ui.dart';
import 'admin_dashboard.dart';
import 'admin_schedules.dart';
import 'api.dart';
import 'config.dart';
import 'widgets.dart';

class AdminPage extends StatefulWidget {
  const AdminPage({super.key, required this.api, this.initialSection = -1})
    : assert(initialSection >= -1 && initialSection < 8);
  final QueueApi api;
  final int initialSection;
  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  int selected = -1;
  bool collapsed = false;
  Map<String, List<Json>> catalog = {};
  List<Json> data = [];
  String? session, error, message;
  String scheduleSearch = '';
  bool loading = true;
  int revision = 0;
  AdminResource get resource =>
      resources[selected >= 0 && selected < resources.length ? selected : 0];
  @override
  void initState() {
    super.initState();
    selected = widget.initialSection;
    load();
  }

  Future<void> load({bool reloadCatalog = false}) async {
    final current = ++revision;
    final selectedResource = resource;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final paths = catalog.isEmpty || reloadCatalog || selected == -1
          ? resources
                .where((r) => r.path != '/slot-praktik')
                .map((r) => r.path)
                .toList()
          : selectedResource.path == '/slot-praktik'
          ? ['/jadwal-praktik', '/dokter', '/layanan', '/loket']
          : [selectedResource.path];
      final values = await Future.wait(
        paths.map((path) async => rows(await widget.api.request('GET', path))),
      );
      final next = {
        ...catalog,
        for (int i = 0; i < paths.length; i++) paths[i]: values[i],
      };
      List<Json> items;
      if (selectedResource.path == '/slot-praktik') {
        if (!next['/jadwal-praktik']!.any((v) => v['id'] == session)) {
          session = next['/jadwal-praktik']!.firstOrNull?['id'];
        }
        items =
            []; // Slots are fetched lazily when a practice session is expanded.
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
    final bulk = resource.path == '/jadwal-layanan' && row == null;
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => bulk
          ? BulkScheduleEditor(
              api: widget.api,
              clinics: catalog['/layanan'] ?? [],
            )
          : resource.path == '/jadwal-praktik'
          ? PracticeScheduleEditor(api: widget.api, catalog: catalog, row: row)
          : _AdminEditor(
              api: widget.api,
              resource: resource,
              row: row,
              catalog: catalog,
              initialSession: session,
            ),
    );
    if (mounted && (changed == true || bulk)) {
      setState(
        () => message = changed != true
            ? null
            : bulk
            ? 'Proses jadwal selesai. Daftar diperbarui; periksa hasil per hari.'
            : 'Data disimpan.',
      );
      await load(reloadCatalog: true);
    }
  }

  Future<void> deactivateRow(Json row) async {
    if (!await confirm(
      context,
      'Nonaktifkan ${resource.path == '/jadwal-layanan' ? '${label(object(row['layanan']))} · ${dayLabel('${row['hari']}')}' : label(row)}? Riwayat tetap disimpan.',
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
        await load(reloadCatalog: true);
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
    if (mounted) await load(reloadCatalog: true);
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
  void selectResource(int value) {
    setState(() {
      selected = value;
      message = null;
      error = null;
      data = [];
    });
    if (value != 7) load();
  }

  Future<void> openMenu() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .8,
          child: AdminNavigation(
            selected: selected,
            onSelect: loading
                ? null
                : (value) {
                    Navigator.pop(sheetContext);
                    selectResource(value);
                  },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = selected == 7
        ? AdminDisplayPage(api: widget.api)
        : selected == -1
        ? ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Dashboard',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          '${widget.api.config.today} · ${widget.api.config.serviceTimeZone}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Muat ulang dashboard',
                    onPressed: loading ? null : () => load(reloadCatalog: true),
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
              if (loading) const LinearProgressIndicator(),
              if (error != null) AdminNotice(error!, error: true),
              const SizedBox(height: 12),
              AdminDashboard(
                catalog: catalog,
                config: widget.api.config,
                loading: loading,
                onSelect: selectResource,
              ),
            ],
          )
        : ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                resource.title,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              Text('Zona pelayanan: ${widget.api.config.serviceTimeZone}'),
              if (error != null) AdminNotice(error!, error: true),
              if (message != null) AdminNotice(message!),
              if (resource.path == '/penugasan-petugas')
                const AdminNotice(
                  'Akun ADMIN/PETUGAS disediakan pengelola server. Gunakan ID akun dari profil petugas untuk memberikan penugasan.',
                ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: loading ? null : () => edit(),
                    icon: const Icon(Icons.add),
                    label: const Text('Tambah'),
                  ),
                  OutlinedButton.icon(
                    onPressed: loading ? null : () => load(reloadCatalog: true),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Muat ulang'),
                  ),
                ],
              ),
              if (loading) const LinearProgressIndicator(),
              if (resource.path == '/jadwal-layanan')
                GroupedClinicSchedules(
                  clinics: catalog['/layanan'] ?? [],
                  schedules: data,
                  search: scheduleSearch,
                  onSearch: (value) => setState(() => scheduleSearch = value),
                  onEdit: edit,
                  onDeactivate: deactivateRow,
                  busy: loading,
                )
              else
                AdminDataView(
                  key: ValueKey(resource.path),
                  resource: resource,
                  data: data,
                  catalog: catalog,
                  api: widget.api,
                  busy: loading,
                  revision: revision,
                  onEdit: edit,
                  onDeactivate: deactivateRow,
                  onDoctorAccount: (doctor) async {
                    final changed = await showDialog<bool>(
                      context: context,
                      builder: (_) =>
                          DoctorAccountDialog(api: widget.api, doctor: doctor),
                    );
                    if (changed == true && mounted) {
                      await load(reloadCatalog: true);
                    }
                  },
                  onDoctorLinks: doctorLinks,
                  detail: detail,
                ),
            ],
          );
    return Theme(
      data: AdminStyle.theme,
      child: Material(
        color: AdminStyle.theme.scaffoldBackgroundColor,
        child: LayoutBuilder(
          builder: (context, box) => box.maxWidth >= 960
              ? Row(
                  children: [
                    SizedBox(
                      width: collapsed ? 80 : 236,
                      child: AdminNavigation(
                        selected: selected,
                        onSelect: loading ? null : selectResource,
                        collapsed: collapsed,
                        onToggle: () => setState(() => collapsed = !collapsed),
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(child: content),
                  ],
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: Row(
                        children: [
                          Tooltip(
                            message: 'Menu administrasi',
                            child: OutlinedButton.icon(
                              onPressed: loading ? null : openMenu,
                              icon: const Icon(Icons.menu),
                              label: Text(
                                box.maxWidth < 375
                                    ? 'Menu'
                                    : 'Menu administrasi',
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              selected == -1
                                  ? 'Dashboard'
                                  : selected == 7
                                  ? 'Manajemen Display'
                                  : resource.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(child: content),
                  ],
                ),
        ),
      ),
    );
  }
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

  Future<void> pick(AdminField f) async {
    if (busy) return;
    var input = values[f.key] ?? '';
    final session = (widget.catalog['/jadwal-praktik'] ?? [])
        .where((s) => s['id'] == values['jadwalPraktikId'])
        .firstOrNull;
    var day =
        DateTime.tryParse(input.split('T').first) ??
        DateTime.tryParse(dateOnly(session?['tanggal'])) ??
        DateTime.parse(widget.api.config.today);
    if (f.kind != FieldKind.clock) {
      final chosen = await showDatePicker(
        context: context,
        initialDate: day,
        firstDate: DateTime(1000),
        lastDate: DateTime(9999, 12, 31),
        initialEntryMode: DatePickerEntryMode.calendarOnly,
      );
      if (!mounted || chosen == null) return;
      day = chosen;
      if (f.kind == FieldKind.date) {
        setState(() {
          values[f.key] = calendarDate(day);
          controllers[f.key]!.text = values[f.key]!;
        });
        return;
      }
    }
    if (!mounted) return;
    final clock = f.kind == FieldKind.clock ? input : input.split('T').last;
    final valid = RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(clock);
    final chosen = await showTimePicker(
      context: context,
      initialTime: valid
          ? TimeOfDay(
              hour: int.parse(clock.substring(0, 2)),
              minute: int.parse(clock.substring(3, 5)),
            )
          : const TimeOfDay(hour: 8, minute: 0),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (!mounted || chosen == null) return;
    setState(() {
      values[f.key] =
          '${f.kind == FieldKind.instant ? '${calendarDate(day)}T' : ''}${two(chosen.hour)}:${two(chosen.minute)}';
      controllers[f.key]!.text = values[f.key]!;
    });
  }

  Widget input(AdminField f) => TextFormField(
    controller: controllers[f.key],
    enabled: !busy,
    readOnly: [
      FieldKind.date,
      FieldKind.clock,
      FieldKind.instant,
    ].contains(f.kind),
    onTap: [FieldKind.date, FieldKind.clock, FieldKind.instant].contains(f.kind)
        ? () => pick(f)
        : null,
    decoration: InputDecoration(
      labelText: f.title,
      suffixIcon:
          [FieldKind.date, FieldKind.clock, FieldKind.instant].contains(f.kind)
          ? IconButton(
              tooltip: 'Pilih ${f.title}',
              onPressed: busy ? null : () => pick(f),
              icon: Icon(
                f.kind == FieldKind.clock
                    ? Icons.schedule
                    : Icons.calendar_month_outlined,
              ),
            )
          : null,
    ),
    keyboardType: f.kind == FieldKind.integer
        ? TextInputType.number
        : TextInputType.text,
    onChanged: (v) => values[f.key] = v.trim(),
    validator: (v) {
      final invalid = validateAdminField(f, v?.trim() ?? '', widget.api.config);
      if (invalid != null) return invalid;
      if (f.key == 'jamTutup' &&
          !scheduleClosesAfter(
            values['jamBuka'] ?? '',
            values['jamTutup'] ?? '',
          )) {
        return 'Jam tutup harus sesudah jam buka.';
      }
      if (f.key == 'selesaiPada' &&
          (values['mulaiPada'] ?? '').isNotEmpty &&
          (values['selesaiPada'] ?? '').compareTo(values['mulaiPada']!) <= 0) {
        return 'Jam selesai harus sesudah jam mulai.';
      }
      return null;
    },
  );

  Widget staffField(AdminField f) {
    final known = <String, String>{
      for (final a in widget.catalog['/penugasan-petugas'] ?? <Json>[])
        if (a['petugasId'] is String)
          '${a['petugasId']}': label(object(a['petugas'])),
    };
    final id = values[f.key] ?? '';
    if (id.isNotEmpty) {
      known.putIfAbsent(id, () => label(object(widget.row?['petugas'])));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminSearchChoice(
          label: 'Petugas dari penugasan existing',
          choices: known.entries.map((e) => (e.key, e.value)).toList(),
          value: id.isEmpty ? null : id,
          required: false,
          onChanged: busy
              ? null
              : (v) => setState(() {
                  values[f.key] = v ?? '';
                  controllers[f.key]!.text = v ?? '';
                }),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: busy
              ? null
              : () async {
                  final imported =
                      (await Clipboard.getData(Clipboard.kTextPlain))?.text
                          ?.trim() ??
                      '';
                  if (!mounted) return;
                  if (validateAdminField(f, imported, widget.api.config) !=
                      null) {
                    setState(
                      () => error = 'Salin ID akun PETUGAS yang valid dari profil petugas terlebih dahulu.',
                    );
                    return;
                  }
                  setState(() {
                    values[f.key] = imported;
                    controllers[f.key]!.text = imported;
                    error = null;
                  });
                },
          icon: const Icon(Icons.content_paste),
          label: const Text('Tempel ID dari profil petugas'),
        ),
        TextFormField(
          controller: controllers[f.key],
          readOnly: true,
          decoration: const InputDecoration(
            labelText: 'ID akun PETUGAS',
            helperText: 'API belum menyediakan direktori akun petugas. Validasi role tetap dilakukan server.',
          ),
          validator: (v) =>
              validateAdminField(f, v?.trim() ?? '', widget.api.config),
        ),
      ],
    );
  }

  Widget field(AdminField f) => f.key == 'petugasId'
      ? staffField(f)
      : switch (f.kind) {
          FieldKind.flag => SwitchListTile(
            title: Text(f.title),
            value: values[f.key] == 'true',
            onChanged: busy
                ? null
                : (v) => setState(() => values[f.key] = '$v'),
          ),
          FieldKind.choice =>
            options(f).length > 10
                ? AdminSearchChoice(
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
                  )
                : ChoiceField(
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
          _ => input(f),
        };

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
          error =
              widget.resource.path == '/layanan' &&
                  e is ApiException &&
                  e.status >= 500
              ? 'Server belum dapat menyimpan poliklinik (${e.status}). Minta pengelola memeriksa log API dan migration database. Periksa daftar sebelum mencoba lagi.'
              : '$e';
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
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${editing ? 'Ubah' : 'Tambah'} ${widget.resource.title}'),
          const SizedBox(height: 8),
          const Text(
            'Kelola data layanan rumah sakit. Periksa isian sebelum menyimpan.',
            style: TextStyle(fontSize: 13),
          ),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Zona waktu: ${widget.api.config.serviceTimeZone}'),
                if (error != null) AdminNotice(error!, error: true),
                for (final f in fields)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: field(f),
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
