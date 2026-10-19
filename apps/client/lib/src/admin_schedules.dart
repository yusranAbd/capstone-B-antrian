import 'package:flutter/material.dart';

import 'admin_schema.dart';
import 'admin_ui.dart';
import 'api.dart';
import 'config.dart';
import 'widgets.dart';

const scheduleDays = [
  'SENIN',
  'SELASA',
  'RABU',
  'KAMIS',
  'JUMAT',
  'SABTU',
  'MINGGU',
];
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
    this.busy = false,
  });
  final List<Json> clinics, schedules;
  final String search;
  final ValueChanged<String> onSearch;
  final ValueChanged<Json> onEdit, onDeactivate;
  final bool busy;

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
                TextButton.icon(
                  onPressed: busy ? null : () => onEdit(row),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Ubah'),
                ),
                if (row['aktif'] == true)
                  TextButton(
                    onPressed: busy ? null : () => onDeactivate(row),
                    child: const Text('Nonaktifkan'),
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
          padding: const EdgeInsets.symmetric(vertical: 16),
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
        if (groups.isEmpty) const Notice('Tidak ada poliklinik yang sesuai.'),
        for (final group in groups)
          Card(
            margin: const EdgeInsets.symmetric(vertical: 8),
            clipBehavior: Clip.antiAlias,
            child: ExpansionTile(
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
                      horizontal: 20,
                      vertical: 10,
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

enum ScheduleOutcome { created, existing, failed, uncertain }

class ScheduleResult {
  const ScheduleResult(this.day, this.outcome, this.message);
  final String day, message;
  final ScheduleOutcome outcome;
}

/// Fresh preflight includes inactive records. Never overwrites or retries POST.
/// The database unique key also protects against a concurrent ADMIN save.
Future<List<ScheduleResult>> createScheduleDays(
  QueueApi api, {
  required String clinicId,
  required Set<String> days,
  required String opens,
  required String closes,
  required int capacity,
  void Function(List<ScheduleResult>)? onProgress,
}) async {
  final existing = rows(await api.request('GET', '/jadwal-layanan'));
  final results = <ScheduleResult>[];
  for (final day in scheduleDays.where(days.contains)) {
    if (existing.any((r) => r['layananId'] == clinicId && r['hari'] == day)) {
      results.add(
        ScheduleResult(
          day,
          ScheduleOutcome.existing,
          'Jadwal sudah ada (termasuk yang nonaktif). Gunakan Ubah pada daftar.',
        ),
      );
    } else {
      try {
        await api.request(
          'POST',
          '/jadwal-layanan',
          body: {
            'layananId': clinicId,
            'hari': day,
            'jamBuka': opens,
            'jamTutup': closes,
            'kapasitasHarian': capacity,
          },
        );
        results.add(
          ScheduleResult(day, ScheduleOutcome.created, 'Berhasil disimpan.'),
        );
      } catch (error) {
        // A timeout/5xx can happen after COMMIT. Reconcile before any new action.
        bool found = false;
        try {
          final latest = rows(await api.request('GET', '/jadwal-layanan'));
          found = latest.any(
            (r) => r['layananId'] == clinicId && r['hari'] == day,
          );
        } catch (_) {
          /* Report unverified; never retry the mutation here. */
        }
        final uncertain =
            error is! ApiException || error.status == 0 || error.status >= 500;
        results.add(
          ScheduleResult(
            day,
            found
                ? ScheduleOutcome.existing
                : uncertain
                ? ScheduleOutcome.uncertain
                : ScheduleOutcome.failed,
            found
                ? 'Jadwal ditemukan setelah pemeriksaan ulang. Gunakan Ubah untuk memeriksanya.'
                : uncertain
                ? '$error Hasil belum terverifikasi. Muat ulang daftar sebelum mencoba lagi.'
                : '$error',
          ),
        );
      }
    }
    onProgress?.call(List.unmodifiable(results));
  }
  return results;
}

class BulkScheduleEditor extends StatefulWidget {
  const BulkScheduleEditor({
    super.key,
    required this.api,
    required this.clinics,
  });
  final QueueApi api;
  final List<Json> clinics;
  @override
  State<BulkScheduleEditor> createState() => _BulkScheduleEditorState();
}

class _BulkScheduleEditorState extends State<BulkScheduleEditor> {
  final form = GlobalKey<FormState>();
  final opens = TextEditingController(text: '08:00');
  final closes = TextEditingController(text: '16:00');
  final capacity = TextEditingController(text: '24');
  final days = scheduleDays.take(5).toSet();
  String? clinic, error;
  bool busy = false, finished = false;
  List<ScheduleResult> results = [];
  bool get locked => busy || finished;
  Future<void> save() async {
    if (locked) return;
    final valid = form.currentState!.validate();
    if (!valid || days.isEmpty) {
      setState(() => error = days.isEmpty ? 'Pilih minimal satu hari.' : null);
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await createScheduleDays(
        widget.api,
        clinicId: clinic!,
        days: days,
        opens: opens.text.trim(),
        closes: closes.text.trim(),
        capacity: int.parse(capacity.text.trim()),
        onProgress: (next) {
          if (mounted) setState(() => results = next);
        },
      );
      if (mounted) setState(() => finished = true);
    } catch (e) {
      if (mounted) {
        setState(
          () => error =
              'Tidak dapat memeriksa jadwal. Tidak ada jadwal baru dikirim. $e',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    opens.dispose();
    closes.dispose();
    capacity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
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
                Text('Zona pelayanan: ${widget.api.config.serviceTimeZone}'),
                const SizedBox(height: 16),
                if (widget.clinics.length > 10)
                  AdminSearchChoice(
                    label: 'Poliklinik',
                    choices: choicesOf(
                      widget.clinics.where((c) => c['aktif'] == true).toList(),
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
                      widget.clinics.where((c) => c['aktif'] == true).toList(),
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
                    padding: const EdgeInsets.symmetric(vertical: 8),
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
