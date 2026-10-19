import 'package:flutter/material.dart';

import 'admin_schema.dart';
import 'admin_schedules.dart';
import 'admin_ui.dart';
import 'api.dart';
import 'config.dart';
import 'widgets.dart';

Json clinicOf(Json row, String path) => switch (path) {
  '/layanan' => row,
  '/jadwal-praktik' => object(object(row['dokterLayanan'])['layanan']),
  '/penugasan-petugas' => object(object(row['loket'])['layanan']),
  _ => object(row['layanan']),
};
Json doctorOf(Json row) => object(object(row['dokterLayanan'])['dokter']);

/// Page a loaded REST array locally; never imply unsupported API pagination.
class AdminPagedRows extends StatefulWidget {
  const AdminPagedRows({
    super.key,
    required this.rows,
    required this.builder,
    this.pageSize = 20,
  });
  final List<Json> rows;
  final Widget Function(Json) builder;
  final int pageSize;
  @override
  State<AdminPagedRows> createState() => _AdminPagedRowsState();
}

class _AdminPagedRowsState extends State<AdminPagedRows> {
  int page = 0;
  @override
  Widget build(BuildContext context) {
    final maxPage = widget.rows.isEmpty
        ? 0
        : (widget.rows.length - 1) ~/ widget.pageSize;
    final current = page.clamp(0, maxPage), start = current * widget.pageSize;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final row in widget.rows.skip(start).take(widget.pageSize))
          widget.builder(row),
        if (widget.rows.length > widget.pageSize)
          Wrap(
            spacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '${start + 1}–${(start + widget.pageSize).clamp(0, widget.rows.length)} dari ${widget.rows.length}',
              ),
              IconButton(
                tooltip: 'Halaman sebelumnya',
                onPressed: current == 0
                    ? null
                    : () => setState(() => page = current - 1),
                icon: const Icon(Icons.chevron_left),
              ),
              IconButton(
                tooltip: 'Halaman berikutnya',
                onPressed: current >= maxPage
                    ? null
                    : () => setState(() => page = current + 1),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
      ],
    );
  }
}

/// Build child groups/rows only while expanded, rather than rendering hundreds.
class AdminDataGroup extends StatefulWidget {
  const AdminDataGroup({
    super.key,
    required this.title,
    required this.subtitle,
    required this.children,
  });
  final String title, subtitle;
  final List<Widget> Function() children;
  @override
  State<AdminDataGroup> createState() => _AdminDataGroupState();
}

class _AdminDataGroupState extends State<AdminDataGroup> {
  bool expanded = false;
  @override
  Widget build(BuildContext context) => Card(
    child: ExpansionTile(
      title: Text(widget.title),
      subtitle: Text(widget.subtitle),
      expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
      onExpansionChanged: (value) => setState(() => expanded = value),
      childrenPadding: const EdgeInsets.symmetric(horizontal: 12),
      children: expanded ? widget.children() : const [],
    ),
  );
}

class AdminDataView extends StatefulWidget {
  const AdminDataView({
    super.key,
    required this.resource,
    required this.data,
    required this.catalog,
    required this.api,
    required this.busy,
    required this.onEdit,
    required this.onDeactivate,
    required this.onDoctorLinks,
    this.onDoctorAccount,
    required this.detail,
    required this.revision,
  });
  final AdminResource resource;
  final List<Json> data;
  final Map<String, List<Json>> catalog;
  final QueueApi api;
  final bool busy;
  final ValueChanged<Json> onEdit, onDeactivate, onDoctorLinks;
  final ValueChanged<Json>? onDoctorAccount;
  final String Function(Json) detail;
  final int revision;
  @override
  State<AdminDataView> createState() => _AdminDataViewState();
}

class _AdminDataViewState extends State<AdminDataView> {
  String search = '',
      status = '',
      clinic = '',
      doctor = '',
      from = '',
      until = '';
  String? dateError;
  final fromController = TextEditingController(),
      untilController = TextEditingController();
  @override
  void dispose() {
    fromController.dispose();
    untilController.dispose();
    super.dispose();
  }

  Future<void> pickFilterDate(bool first) async {
    final chosen = await showDatePicker(
      context: context,
      initialDate:
          DateTime.tryParse(first ? from : until) ??
          DateTime.parse(widget.api.config.today),
      firstDate: DateTime(1000),
      lastDate: DateTime(9999, 12, 31),
      initialEntryMode: DatePickerEntryMode.calendarOnly,
    );
    if (!mounted || chosen == null) return;
    final value = calendarDate(chosen);
    (first ? fromController : untilController).text = value;
    changeDate(value, first);
  }

  String get path => widget.resource.path;
  bool get sessions => ['/jadwal-praktik', '/slot-praktik'].contains(path);
  List<Json> get source => path == '/slot-praktik'
      ? widget.catalog['/jadwal-praktik'] ?? []
      : widget.data;
  String clinicId(Json r) =>
      '${clinicOf(r, path == '/slot-praktik' ? '/jadwal-praktik' : path)['id'] ?? r['layananId'] ?? object(r['dokterLayanan'])['layananId'] ?? object(r['loket'])['layananId'] ?? ''}';
  String clinicName(Json r) {
    final id = clinicId(r),
        direct = clinicOf(
          r,
          path == '/slot-praktik' ? '/jadwal-praktik' : path,
        );
    final actual = (widget.catalog['/layanan'] ?? [])
        .where((c) => c['id'] == id)
        .firstOrNull;
    return '${actual?['nama'] ?? direct['nama'] ?? 'Poliklinik tidak tersedia'}';
  }

  bool matches(Json r) {
    if (status.isNotEmpty &&
        path != '/slot-praktik' &&
        '${r['aktif']}' != status) {
      return false;
    }
    if (clinic.isNotEmpty) {
      if (path == '/dokter') {
        if (!rows(r['dokterLayanan'])
            .any((l) => l['layananId'] == clinic && l['aktif'] == true)) {
          return false;
        }
      } else if (clinicId(r) != clinic) {
        return false;
      }
    }
    if (sessions) {
      final doc = doctorOf(r), date = dateOnly(r['tanggal']);
      if (doctor.isNotEmpty && doc['id'] != doctor) return false;
      if (from.isNotEmpty && date.compareTo(from) < 0) return false;
      if (until.isNotEmpty && date.compareTo(until) > 0) return false;
    }
    final text = [
      r['nama'],
      r['kode'],
      r['spesialisasi'],
      clinicName(r),
      doctorOf(r)['nama'],
      object(r['petugas'])['nama'],
      object(r['loket'])['nama'],
      r['lokasi'],
      if (path == '/dokter')
        ...rows(r['dokterLayanan']).map((l) => object(l['layanan'])['nama']),
    ].join(' ').toLowerCase();
    return text.contains(search);
  }

  void changeDate(String value, bool first) {
    final input = value.trim(), date = DateTime.tryParse(value.trim());
    setState(() {
      if (input.isNotEmpty &&
          (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(input) ||
              date == null ||
              calendarDate(date) != input)) {
        dateError = 'Gunakan tanggal kalender YYYY-MM-DD.';
        return;
      }
      if (first) {
        from = input;
      } else {
        until = input;
      }
      dateError =
          from.isNotEmpty && until.isNotEmpty && from.compareTo(until) > 0
          ? 'Tanggal akhir harus sama atau sesudah tanggal mulai.'
          : null;
    });
  }

  Widget actions(Json row, {bool showStatus = true}) => Wrap(
    spacing: 8,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      if (showStatus) stateChip(row['aktif'] == true ? 'AKTIF' : 'NONAKTIF'),
      TextButton.icon(
        onPressed: widget.busy ? null : () => widget.onEdit(row),
        icon: const Icon(Icons.edit_outlined),
        label: const Text('Ubah'),
      ),
      if (row['aktif'] == true)
        TextButton(
          onPressed: widget.busy ? null : () => widget.onDeactivate(row),
          child: const Text('Nonaktifkan'),
        ),
      if (path == '/dokter' && widget.onDoctorAccount != null)
        OutlinedButton.icon(
          onPressed: widget.busy || row['aktif'] != true
              ? null
              : () => widget.onDoctorAccount!(row),
          icon: const Icon(Icons.manage_accounts_outlined),
          label: Text(
            row['penggunaId'] == null ? 'Akun dokter' : 'Akun ditautkan',
          ),
        ),
      if (path == '/dokter')
        OutlinedButton(
          onPressed: widget.busy ? null : () => widget.onDoctorLinks(row),
          child: const Text('Hubungkan poliklinik'),
        ),
    ],
  );
  Widget rowCard(Json r) => Section(
    title: switch (path) {
      '/penugasan-petugas' => label(object(r['petugas'])),
      '/jadwal-praktik' => dateOnly(r['tanggal']),
      _ => label(r),
    },
    subtitle: widget.detail(r),
    child: actions(r),
  );

  Widget table(List<Json> items) => AdminTable(
    key: ValueKey('$path:$search:$status:$clinic:$doctor:$from:$until'),
    rows: items,
    columns: [
      if (path == '/jadwal-praktik') ...[
        AdminColumn('Tanggal', (r) => dateOnly(r['tanggal'])),
        AdminColumn('Dokter', (r) => label(doctorOf(r))),
        AdminColumn('Poliklinik', clinicName),
        AdminColumn(
          'Ruang',
          (r) =>
              '${object(r['loket'])['kode'] ?? ''} · ${label(object(r['loket']))}',
        ),
        AdminColumn(
          'Jam praktik',
          (r) =>
              '${clockOnly(widget.api.config.localInput(r['mulaiPada']))} – ${clockOnly(widget.api.config.localInput(r['selesaiPada']))}',
        ),
      ] else if (path == '/penugasan-petugas') ...[
        AdminColumn('Petugas', (r) => label(object(r['petugas']))),
        AdminColumn('Poliklinik', clinicName),
        AdminColumn(
          'Ruang / Loket',
          (r) =>
              '${object(r['loket'])['kode'] ?? ''} · ${label(object(r['loket']))}',
        ),
        AdminColumn('Mulai', (r) => dateOnly(r['tanggalMulai'])),
        AdminColumn(
          'Selesai',
          (r) => r['tanggalSelesai'] == null
              ? 'Tanpa akhir'
              : dateOnly(r['tanggalSelesai']),
        ),
      ] else ...[
        AdminColumn('Nama', label),
        AdminColumn('Kode', (r) => r['kode']),
        if (path == '/dokter') ...[
          AdminColumn('Spesialisasi', (r) => r['spesialisasi'] ?? '—'),
          AdminColumn(
            'Poliklinik',
            (r) =>
                rows(r['dokterLayanan'])
                    .where((l) => l['aktif'] == true)
                    .map((l) => label(object(l['layanan'])))
                    .join(', '),
          ),
          AdminColumn(
            'Akun DOKTER',
            (r) => r['penggunaId'] == null ? 'Belum ditautkan' : 'Tertaut',
          ),
        ],
        if (path == '/layanan') ...[
          AdminColumn(
            'Mode reservasi',
            (r) => switch (r['modeReservasi']) {
              'HIBRIDA' => 'Hibrida',
              'ANTREAN_HARIAN' => 'Walk-in',
              'JANJI_TEMU_DOKTER' => 'Janji temu dokter',
              _ => r['modeReservasi'] ?? '—',
            },
          ),
          AdminColumn(
            'Dokter terkait',
            (r) => (widget.catalog['/dokter'] ?? [])
                .where(
                  (d) => rows(
                    d['dokterLayanan'],
                  ).any((l) => l['layananId'] == r['id'] && l['aktif'] == true),
                )
                .length,
            numeric: true,
          ),
          AdminColumn(
            'Ruang',
            (r) => (widget.catalog['/loket'] ?? [])
                .where((l) => l['layananId'] == r['id'])
                .length,
            numeric: true,
          ),
        ],
        if (path == '/loket') AdminColumn('Lokasi', (r) => r['lokasi'] ?? '—'),
      ],
      AdminColumn(
        'Status',
        (r) => r['aktif'] == true ? 'Aktif' : 'Nonaktif',
        cell: (r) => stateChip(r['aktif'] == true ? 'AKTIF' : 'NONAKTIF'),
      ),
      AdminColumn(
        'Aksi',
        (_) => '',
        cell: (r) => SizedBox(
          width: path == '/dokter' ? 530 : 220,
          child: actions(r, showStatus: false),
        ),
      ),
    ],
  );
  List<Widget> groups(
    List<Json> data,
    String Function(Json) keyOf,
    String Function(Json) titleOf,
    List<Widget> Function(List<Json>) builder,
    String level,
  ) {
    final groups = <String, List<Json>>{};
    for (final row in data) {
      groups.putIfAbsent(keyOf(row), () => []).add(row);
    }
    final entries = groups.entries.toList()
      ..sort(
        (a, b) => titleOf(a.value.first).compareTo(titleOf(b.value.first)),
      );
    return [
      for (final entry in entries)
        AdminDataGroup(
          key: ValueKey('$level:${entry.key}'),
          title: titleOf(entry.value.first),
          subtitle:
              '${entry.value.length} ${path == '/slot-praktik' ? 'sesi praktik' : 'data'}',
          children: () => builder(entry.value),
        ),
    ];
  }

  List<Widget> doctorGroups(List<Json> data) => groups(
    data,
    (r) => '${doctorOf(r)['id'] ?? object(r['dokterLayanan'])['dokterId']}',
    (r) => '${doctorOf(r)['nama'] ?? 'Dokter tidak tersedia'}',
    (items) => path == '/jadwal-praktik'
        ? groups(
            items,
            (r) => dateOnly(r['tanggal']),
            (r) => dateOnly(r['tanggal']),
            (dates) => [
              AdminPagedRows(
                rows: dates
                  ..sort(
                    (a, b) =>
                        '${a['mulaiPada']}'.compareTo('${b['mulaiPada']}'),
                  ),
                builder: rowCard,
              ),
            ],
            'date',
          )
        : [
            AdminPagedRows(
              rows: items
                ..sort(
                  (a, b) => '${a['mulaiPada']}'.compareTo('${b['mulaiPada']}'),
                ),
              builder: (r) => AdminSlotSession(
                key: ValueKey('${r['id']}'),
                revision: widget.revision,
                session: r,
                api: widget.api,
                status: status,
                search: search,
                busy: widget.busy,
                onEdit: widget.onEdit,
                onDeactivate: widget.onDeactivate,
              ),
            ),
          ],
    'doctor',
  );

  @override
  Widget build(BuildContext context) {
    final filtered = source.where(matches).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        Semantics(
          container: true,
          child: TextField(
            decoration: InputDecoration(
              labelText: path == '/dokter'
                  ? 'Cari dokter atau spesialisasi'
                  : 'Cari nama atau kode',
              prefixIcon: const Icon(Icons.search),
            ),
            onChanged: (value) =>
                setState(() => search = value.trim().toLowerCase()),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: 210,
              child: ChoiceField(
                label: 'Status data',
                choices: const [
                  ('', 'Semua status'),
                  ('true', 'Aktif'),
                  ('false', 'Nonaktif'),
                ],
                value: status,
                onChanged: (value) => setState(() => status = value ?? ''),
              ),
            ),
            if (path != '/layanan')
              SizedBox(
                width: 250,
                child: ChoiceField(
                  label: 'Filter poliklinik',
                  choices: [
                    ('', 'Semua poliklinik'),
                    ...choicesOf(widget.catalog['/layanan'] ?? []),
                  ],
                  value: clinic,
                  onChanged: (value) => setState(() => clinic = value ?? ''),
                ),
              ),
            if (sessions)
              SizedBox(
                width: 250,
                child: ChoiceField(
                  label: 'Filter dokter',
                  choices: [
                    ('', 'Semua dokter'),
                    ...choicesOf(widget.catalog['/dokter'] ?? []),
                  ],
                  value: doctor,
                  onChanged: (value) => setState(() => doctor = value ?? ''),
                ),
              ),
            if (sessions) ...[
              SizedBox(
                width: 220,
                child: TextField(
                  controller: fromController,
                  decoration: InputDecoration(
                    labelText: 'Dari tanggal (YYYY-MM-DD)',
                    suffixIcon: IconButton(
                      tooltip: 'Pilih tanggal mulai filter',
                      onPressed: () => pickFilterDate(true),
                      icon: const Icon(Icons.calendar_month_outlined),
                    ),
                  ),
                  onChanged: (v) => changeDate(v, true),
                ),
              ),
              SizedBox(
                width: 220,
                child: TextField(
                  controller: untilController,
                  decoration: InputDecoration(
                    labelText: 'Sampai tanggal (YYYY-MM-DD)',
                    suffixIcon: IconButton(
                      tooltip: 'Pilih tanggal akhir filter',
                      onPressed: () => pickFilterDate(false),
                      icon: const Icon(Icons.calendar_month_outlined),
                    ),
                  ),
                  onChanged: (v) => changeDate(v, false),
                ),
              ),
            ],
          ],
        ),
        if (dateError != null) AdminNotice(dateError!, error: true),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            '${filtered.length} dari ${source.length} ${path == '/slot-praktik' ? 'sesi praktik' : 'data'}',
          ),
        ),
        if (filtered.isEmpty && !widget.busy)
          const AdminNotice('Tidak ada data yang sesuai filter.'),
        if ([
          '/layanan',
          '/dokter',
          '/jadwal-praktik',
          '/penugasan-petugas',
        ].contains(path))
          table(filtered)
        else
          ...groups(
            filtered,
            clinicId,
            clinicName,
            (items) => sessions ? doctorGroups(items) : [table(items)],
            'clinic',
          ),
      ],
    );
  }
}

class AdminSlotSession extends StatefulWidget {
  const AdminSlotSession({
    super.key,
    required this.session,
    required this.api,
    required this.revision,
    required this.status,
    required this.search,
    required this.busy,
    required this.onEdit,
    required this.onDeactivate,
  });
  final Json session;
  final QueueApi api;
  final String status, search;
  final int revision;
  final bool busy;
  final ValueChanged<Json> onEdit, onDeactivate;
  @override
  State<AdminSlotSession> createState() => _AdminSlotSessionState();
}

class _AdminSlotSessionState extends State<AdminSlotSession> {
  List<Json>? slots;
  String? error;
  bool loading = false, expanded = false;
  @override
  void didUpdateWidget(covariant AdminSlotSession oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revision != widget.revision && expanded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) load();
      });
    }
  }

  Future<void> load() async {
    if (loading) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = rows(
        await widget.api.request(
          'GET',
          '/slot-praktik',
          query: {'jadwalPraktikId': '${widget.session['id']}'},
        ),
      );
      if (mounted) setState(() => slots = result);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = (slots ?? [])
        .where((s) => widget.status.isEmpty || '${s['aktif']}' == widget.status)
        .toList();
    return Card(
      child: ExpansionTile(
        title: Text(
          '${dateOnly(widget.session['tanggal'])} · ${widget.api.config.instantLabel(widget.session['mulaiPada']).split(' ').last}–${widget.api.config.instantLabel(widget.session['selesaiPada']).split(' ').last}',
        ),
        subtitle: Text(
          '${label(object(widget.session['loket']))} · ${widget.session['aktif'] == true ? 'Sesi aktif' : 'Sesi nonaktif'}',
        ),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        onExpansionChanged: (v) {
          setState(() => expanded = v);
          if (v && slots == null) load();
        },
        children: !expanded
            ? const []
            : [
                if (loading) const LinearProgressIndicator(),
                if (error != null) AdminNotice(error!, error: true),
                TextButton.icon(
                  onPressed: loading ? null : load,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Muat ulang slot'),
                ),
                if (slots != null && visible.isEmpty)
                  const AdminNotice('Tidak ada slot yang sesuai filter.'),
                AdminTable(
                  rows: visible,
                  columns: [
                    AdminColumn(
                      'Jam slot',
                      (s) =>
                          '${clockOnly(widget.api.config.localInput(s['mulaiPada']))} – ${clockOnly(widget.api.config.localInput(s['selesaiPada']))}',
                    ),
                    AdminColumn(
                      'Kapasitas',
                      (s) => s['kapasitas'],
                      numeric: true,
                    ),
                    AdminColumn(
                      'Terisi',
                      (s) => s['jumlahJanjiTemu'] ?? '—',
                      numeric: true,
                    ),
                    AdminColumn(
                      'Sisa',
                      (s) => s['sisaKapasitas'] ?? '—',
                      numeric: true,
                    ),
                    AdminColumn(
                      'Ketersediaan',
                      (s) =>
                          s['tersedia'] == true ? 'Tersedia' : 'Tidak tersedia',
                    ),
                    AdminColumn(
                      'Status',
                      (s) => s['aktif'] == true ? 'Aktif' : 'Nonaktif',
                    ),
                    AdminColumn(
                      'Aksi',
                      (_) => '',
                      cell: (s) => SizedBox(
                        width: 220,
                        child: Wrap(
                          spacing: 8,
                          children: [
                            stateChip(
                              s['aktif'] == true ? 'AKTIF' : 'NONAKTIF',
                            ),
                            TextButton(
                              onPressed: widget.busy
                                  ? null
                                  : () => widget.onEdit(s),
                              child: const Text('Ubah'),
                            ),
                            if (s['aktif'] == true)
                              TextButton(
                                onPressed: widget.busy
                                    ? null
                                    : () => widget.onDeactivate(s),
                                child: const Text('Nonaktifkan'),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
      ),
    );
  }
}
