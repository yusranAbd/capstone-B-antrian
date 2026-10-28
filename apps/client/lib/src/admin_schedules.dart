import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'features/admin/application/schedule_batch_cubit.dart';
import 'features/admin/application/schedule_batch_state.dart';
import 'features/admin/data/admin_catalog_repository.dart';
import 'features/admin/data/admin_schedule_repository.dart';
import 'features/admin/models/admin_schedule_models.dart';
export 'features/admin/models/admin_schedule_models.dart';
export 'features/admin/data/admin_schedule_repository.dart'
    show createScheduleDays;

import 'admin_schema.dart';
import 'admin_ui.dart';
import 'api.dart';
import 'config.dart';
import 'widgets.dart';

String dayLabel(String day) => day[0] + day.substring(1).toLowerCase();

/// Keep the existing selectable appearance and announce ADMIN operation results.
class AdminNotice extends StatelessWidget {
  const AdminNotice(this.text, {super.key, this.error = false});
  final String text;
  final bool error;
  @override
  Widget build(BuildContext context) => Semantics(
    label: text,
    liveRegion: true,
    excludeSemantics: true,
    child: Notice(text, error: error),
  );
}

class ClinicSchedules {
  ClinicSchedules(this.clinic, this.schedules);
  final Json clinic;
  final List<Json> schedules;
  String get name => '${clinic['nama'] ?? 'Poliklinik tidak tersedia'}';
  int get activeDays => schedules
      .where((s) => s['aktif'] == true)
      .map((s) => s['hari'])
      .toSet()
      .length;
  String get status => clinic['aktif'] == false
      ? 'Poliklinik nonaktif'
      : activeDays > 0
      ? 'Jadwal aktif'
      : 'Belum ada hari aktif';
}

List<ClinicSchedules> groupClinicSchedules(
  List<Json> clinics,
  List<Json> schedules,
  String search,
) {
  final all = <String, Json>{
    for (final row in schedules)
      '${row['layananId']}': {
        'id': row['layananId'],
        ...object(row['layanan']),
      },
    for (final clinic in clinics) '${clinic['id']}': clinic,
  };
  final query = search.trim().toLowerCase();
  final groups = [
    for (final entry in all.entries)
      if ('${entry.value['nama'] ?? ''} ${entry.value['kode'] ?? ''}'
          .toLowerCase()
          .contains(query))
        ClinicSchedules(
          entry.value,
          schedules.where((s) => '${s['layananId']}' == entry.key).toList()
            ..sort(
              (a, b) => scheduleDays
                  .indexOf('${a['hari']}')
                  .compareTo(scheduleDays.indexOf('${b['hari']}')),
            ),
        ),
  ];
  groups.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return groups;
}

class GroupedClinicSchedules extends StatelessWidget {
  const GroupedClinicSchedules({
    super.key,
    required this.clinics,
    required this.schedules,
    required this.search,
    required this.onSearch,
    required this.onEdit,
    required this.onDeactivate,
    this.onDelete,
    this.busy = false,
    this.toolbarActions = const [],
  });
  final List<Json> clinics, schedules;
  final String search;
  final ValueChanged<String> onSearch;
  final ValueChanged<Json> onEdit, onDeactivate;
  final ValueChanged<Json>? onDelete;
  final bool busy;
  final List<Widget> toolbarActions;

  Widget dayRow(BuildContext context, String day, Json? row) => LayoutBuilder(
    builder: (context, box) {
      final summary = Row(
        children: [
          SizedBox(
            width: 82,
            child: Text(
              dayLabel(day),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: Text(
              row == null
                  ? 'Belum dikonfigurasi'
                  : '${clockOnly(row['jamBuka'])}–${clockOnly(row['jamTutup'])} · Kuota ${row['kapasitasHarian']}',
            ),
          ),
        ],
      );
      final actions = row == null
          ? const SizedBox()
          : Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                stateChip(row['aktif'] == true ? 'AKTIF' : 'NONAKTIF'),
                AdminRowActions(
                  tooltip: 'Aksi ${dayLabel(day)}',
                  busy: busy,
                  actions: [
                    AdminRowAction(
                      'Ubah',
                      Icons.edit_outlined,
                      () => onEdit(row),
                    ),
                    if (row['aktif'] == true)
                      AdminRowAction(
                        'Nonaktifkan',
                        Icons.block_outlined,
                        () => onDeactivate(row),
                        danger: true,
                      ),
                    if (onDelete != null)
                      AdminRowAction(
                        'Hapus',
                        Icons.delete_outline,
                        () => onDelete!(row),
                        danger: true,
                      ),
                  ],
                ),
              ],
            );
      return Column(
        children: [
          if (box.maxWidth >= 680)
            Row(
              children: [
                Expanded(child: summary),
                actions,
              ],
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [summary, actions],
            ),
          if (day != scheduleDays.last) const Divider(height: 1),
        ],
      );
    },
  );
  @override
  Widget build(BuildContext context) {
    final groups = groupClinicSchedules(clinics, schedules, search);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: LayoutBuilder(
            builder: (context, box) => Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: box.maxWidth < 560 ? box.maxWidth : 320,
                  child: Semantics(
                    container: true,
                    child: TextFormField(
                      initialValue: search,
                      decoration: const InputDecoration(
                        labelText: 'Cari poliklinik',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: onSearch,
                    ),
                  ),
                ),
                ...toolbarActions,
              ],
            ),
          ),
        ),
        if (groups.isEmpty) const Notice('Tidak ada poliklinik yang sesuai.'),
        for (final group in groups)
          Card(
            margin: const EdgeInsets.symmetric(vertical: 4),
            clipBehavior: Clip.antiAlias,
            child: ExpansionTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              tilePadding: const EdgeInsets.symmetric(horizontal: 12),
              key: PageStorageKey('clinic-schedules-${group.clinic['id']}'),
              expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
              initiallyExpanded: groups.length == 1,
              title: Text(
                group.name,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              subtitle: Text(
                '${group.activeDays} hari aktif · ${group.status}',
              ),
              children: [
                for (final day in scheduleDays)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    child: Builder(
                      builder: (context) {
                        final row = group.schedules
                            .where((r) => r['hari'] == day)
                            .firstOrNull;
                        return dayRow(context, day, row);
                      },
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class BulkScheduleEditor extends StatefulWidget {
  const BulkScheduleEditor({
    super.key,
    required this.api,
    required this.clinics,
    this.repository,
  });
  final QueueApi api;
  final List<Json> clinics;
  final AdminScheduleRepository? repository;
  @override
  State<BulkScheduleEditor> createState() => _BulkScheduleEditorState();
}

class _BulkScheduleEditorState extends State<BulkScheduleEditor> {
  late final AdminCatalogRepository? ownedCatalog;
  late final ScheduleBatchCubit batch;
  List<Json> get clinics =>
      widget.repository?.catalog.snapshot.rowsFor('/layanan') ?? widget.clinics;
  final form = GlobalKey<FormState>();
  final opens = TextEditingController(text: '08:00');
  final closes = TextEditingController(text: '16:00');
  final capacity = TextEditingController(text: '24');
  final days = scheduleDays.take(5).toSet();
  String? clinic, validationError;
  String? get error => validationError ?? batch.state.error;
  bool get busy => batch.state.busy;
  bool get finished => batch.state.finished;
  List<ScheduleResult> get results => batch.state.results;
  @override
  void initState() {
    super.initState();
    ownedCatalog = widget.repository == null
        ? AdminCatalogRepository(widget.api)
        : null;
    batch = ScheduleBatchCubit(
      widget.repository ?? AdminScheduleRepository(ownedCatalog!),
    );
  }

  bool get locked => busy || finished;
  Future<void> save() async {
    if (locked) return;
    final valid = form.currentState!.validate();
    if (!valid || days.isEmpty) {
      setState(
        () =>
            validationError = days.isEmpty ? 'Pilih minimal satu hari.' : null,
      );
      return;
    }
    setState(() => validationError = null);
    await batch.submit(
      clinicId: clinic!,
      days: days,
      opens: opens.text.trim(),
      closes: closes.text.trim(),
      capacity: int.parse(capacity.text.trim()),
    );
  }

  @override
  void dispose() {
    batch.close();
    ownedCatalog?.dispose();
    opens.dispose();
    closes.dispose();
    capacity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BlocProvider.value(
    value: batch,
    child: BlocBuilder<ScheduleBatchCubit, ScheduleBatchState>(
      builder: (context, _) => _dialog(context),
    ),
  );
  Widget _dialog(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      title: const Text('Tambah Jam & Kapasitas'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (clinics.length > 10)
                  AdminSearchChoice(
                    label: 'Poliklinik',
                    choices: choicesOf(
                      clinics.where((c) => c['aktif'] == true).toList(),
                    ),
                    value: clinic,
                    onChanged: locked
                        ? null
                        : (value) => setState(() => clinic = value),
                  )
                else
                  ChoiceField(
                    label: 'Poliklinik',
                    choices: choicesOf(
                      clinics.where((c) => c['aktif'] == true).toList(),
                    ),
                    value: clinic,
                    required: true,
                    onChanged: locked
                        ? null
                        : (value) => setState(() => clinic = value),
                  ),
                const SizedBox(height: 16),
                Text(
                  'Pilih hari',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: locked
                          ? null
                          : () => setState(() {
                              days.clear();
                              days.addAll(scheduleDays.take(5));
                            }),
                      child: const Text('Pilih Senin–Jumat'),
                    ),
                    TextButton(
                      onPressed: locked
                          ? null
                          : () => setState(() => days.addAll(scheduleDays)),
                      child: const Text('Pilih Semua'),
                    ),
                    TextButton(
                      onPressed: locked ? null : () => setState(days.clear),
                      child: const Text('Hapus Pilihan'),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final day in scheduleDays)
                      FilterChip(
                        label: Text(dayLabel(day)),
                        selected: days.contains(day),
                        onSelected: locked
                            ? null
                            : (selected) => setState(() {
                                selected ? days.add(day) : days.remove(day);
                              }),
                      ),
                  ],
                ),
                const AdminNotice(
                  'Hari yang sudah dikonfigurasi akan dilewati, termasuk jadwal nonaktif. Untuk mengubahnya, gunakan Ubah pada daftar.',
                ),
                for (final (controller, key, title) in [
                  (opens, 'jamBuka', 'Jam buka (HH:mm)'),
                  (closes, 'jamTutup', 'Jam tutup (HH:mm)'),
                  (capacity, 'kapasitasHarian', 'Kapasitas harian'),
                ])
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: TextFormField(
                      controller: controller,
                      enabled: !locked,
                      decoration: InputDecoration(
                        labelText: title,
                        suffixIcon: key == 'kapasitasHarian'
                            ? null
                            : IconButton(
                                tooltip: 'Pilih $title',
                                onPressed: locked
                                    ? null
                                    : () async {
                                        final parts = controller.text.split(
                                          ':',
                                        );
                                        final hour =
                                                int.tryParse(parts.first) ?? 8,
                                            minute = parts.length > 1
                                                ? int.tryParse(parts[1]) ?? 0
                                                : 0;
                                        final chosen = await showTimePicker(
                                          context: context,
                                          initialTime: TimeOfDay(
                                            hour: hour.clamp(0, 23),
                                            minute: minute.clamp(0, 59),
                                          ),
                                          builder: (context, child) =>
                                              MediaQuery(
                                                data: MediaQuery.of(context)
                                                    .copyWith(
                                                      alwaysUse24HourFormat:
                                                          true,
                                                    ),
                                                child: child!,
                                              ),
                                        );
                                        if (chosen != null && mounted) {
                                          setState(
                                            () => controller.text =
                                                '${two(chosen.hour)}:${two(chosen.minute)}',
                                          );
                                        }
                                      },
                                icon: const Icon(Icons.schedule),
                              ),
                      ),
                      keyboardType: key == 'kapasitasHarian'
                          ? TextInputType.number
                          : TextInputType.datetime,
                      validator: (v) {
                        final field = resources
                            .firstWhere((r) => r.path == '/jadwal-layanan')
                            .fields
                            .firstWhere((f) => f.key == key);
                        final invalid = validateAdminField(
                          field,
                          v?.trim() ?? '',
                          widget.api.config,
                        );
                        if (invalid != null) return invalid;
                        if (key == 'jamTutup' &&
                            !scheduleClosesAfter(
                              opens.text.trim(),
                              closes.text.trim(),
                            )) {
                          return 'Jam tutup harus sesudah jam buka.';
                        }
                        return null;
                      },
                    ),
                  ),
                if (error != null) AdminNotice(error!, error: true),
                if (busy) const LinearProgressIndicator(),
                if (results.isNotEmpty) ...[
                  AdminNotice(
                    '${results.where((r) => r.outcome == ScheduleOutcome.created).length} berhasil · '
                    '${results.where((r) => r.outcome == ScheduleOutcome.existing).length} dilewati · '
                    '${results.where((r) => r.outcome == ScheduleOutcome.failed || r.outcome == ScheduleOutcome.uncertain).length} gagal/belum terverifikasi',
                  ),
                  for (final result in results)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(switch (result.outcome) {
                        ScheduleOutcome.created => Icons.check_circle_outline,
                        ScheduleOutcome.existing => Icons.info_outline,
                        _ => Icons.error_outline,
                      }),
                      title: Text(dayLabel(result.day)),
                      subtitle: Text(result.message),
                    ),
                  if (finished)
                    const Text(
                      'Daftar akan dimuat ulang saat ditutup. Hari yang berhasil tidak dikirim ulang; periksa hasil sebelum membuat jadwal berikutnya.',
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context, finished),
          child: Text(finished ? 'Tutup & muat ulang' : 'Kembali'),
        ),
        if (!finished)
          FilledButton(
            onPressed: busy ? null : save,
            child: Text(busy ? 'Menyimpan…' : 'Simpan Jadwal Terpilih'),
          ),
      ],
    ),
  );
}

bool scheduleClosesAfter(String opens, String closes) =>
    RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$').hasMatch(opens) &&
    RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$').hasMatch(closes) &&
    closes.compareTo(opens) > 0;
