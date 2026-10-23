import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'config.dart';
import 'mobile_ui.dart';
import 'doctor_visual.dart';

// Hallmark · doctor web workbench · existing QueueB tokens · P5 H5 E4 S5 R5 V4.
/// Presentation model only. Waiting order and eligibility come from REST.
class DoctorDashboardData {
  DoctorDashboardData(this.appointments, this.snapshots) {
    final byKey = <String, Json>{};
    for (final a in appointments) {
      byKey[key(a)] = {...a, 'jenisAntrean': 'JANJI_TEMU'};
    }
    final ordered = <String>[];
    for (final s in snapshots) {
      for (final group in ['aktif', 'menunggu']) {
        for (final t in rows(s[group])) {
          final row = <String, dynamic>{
            ...t,
            'poliklinik': s['poliklinik'],
            'ruang': s['ruang'],
            'jadwalPraktikId': object(s['sesi'])['id'],
          };
          final id = key(row);
          byKey[id] = {...?byKey[id], ...row, 'dariSnapshot': true};
          if (!ordered.contains(id)) ordered.add(id);
          if (group == 'aktif') active.add(byKey[id]!);
          if (group == 'menunggu') waiting.add(byKey[id]!);
        }
      }
    }
    entries = [
      for (final id in ordered) byKey[id]!,
      for (final e in byKey.entries)
        if (!ordered.contains(e.key)) e.value,
    ];
  }
  final List<Json> appointments, snapshots;
  final List<Json> active = [], waiting = [];
  late final List<Json> entries;
  static String key(Json row) {
    String scope(Json value) =>
        '${value['id'] ?? value['kode'] ?? value['nama'] ?? ''}';
    return '${scope(object(row['poliklinik']))}|${scope(object(row['ruang']))}|${row['nomorAntrean']}';
  }

  int get queueTotal => snapshots.fold<int>(
    0,
    (n, s) =>
        n +
        ((s['totalMenunggu'] as num?)?.toInt() ?? 0) +
        rows(s['aktif']).length,
  );
  int get completed =>
      appointments.where((a) => a['status'] == 'SELESAI').length;
  Json? get nextEligible =>
      waiting.where((a) => a['layakDipanggil'] == true).firstOrNull;
}

String doctorStatus(Object? value) => switch ('$value') {
  'DIPESAN' => 'Dipesan',
  'CHECK_IN' => 'Check-In',
  'MENUNGGU' => 'Menunggu',
  'DIPANGGIL' => 'Dipanggil',
  'DILAYANI' => 'Dilayani',
  'SELESAI' => 'Selesai',
  'DILEWATI' => 'Dilewati',
  'DIBATALKAN' => 'Dibatalkan',
  _ => '${value ?? '—'}',
};
Color doctorStatusColor(Object? status) => switch ('$status') {
  'SELESAI' => QueueBStyle.success,
  'DIPANGGIL' || 'DILAYANI' => QueueBStyle.darkTeal,
  'DIBATALKAN' || 'DILEWATI' => QueueBStyle.danger,
  _ => QueueBStyle.warning,
};
Widget doctorBadge(String text, {Color color = QueueBStyle.darkTeal}) =>
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
String doctorTime(Json row, AppConfig config) {
  if (DateTime.tryParse('${row['mulaiPada']}') == null) return '—';
  return '${clockOnly(config.localInput(row['mulaiPada']))}–${clockOnly(config.localInput(row['selesaiPada']))}';
}

class DoctorPanel extends StatelessWidget {
  const DoctorPanel({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: DoctorStyle.panel,
    child: child,
  );
}

class DoctorDashboard extends StatelessWidget {
  const DoctorDashboard({
    super.key,
    required this.config,
    required this.date,
    required this.profile,
    required this.schedules,
    required this.appointments,
    required this.snapshots,
    required this.loading,
    required this.available,
    required this.status,
    required this.onRefresh,
    required this.onPickDate,
    this.error,
  });
  final AppConfig config;
  final String date;
  final Json profile;
  final List<Json> schedules, appointments, snapshots;
  final bool loading, available;
  final ValueListenable<String> status;
  final AsyncCallback onRefresh;
  final VoidCallback onPickDate;
  final String? error;
  @override
  Widget build(BuildContext context) {
    final data = DoctorDashboardData(appointments, snapshots);
    final current = date == config.today;
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 16,
            runSpacing: 12,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Dashboard Dokter',
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    available
                        ? 'Selamat datang, ${profile['nama'] ?? 'Dokter'}'
                        : 'Ringkasan praktik dan antrean Anda.',
                    style: const TextStyle(color: QueueBStyle.muted),
                  ),
                ],
              ),
              Wrap(
                spacing: 8,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ValueListenableBuilder<String>(
                    valueListenable: status,
                    builder: (context, value, _) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: value == 'Realtime terhubung'
                            ? QueueBStyle.mint
                            : QueueBStyle.background,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            value == 'Realtime terhubung'
                                ? Icons.wifi
                                : Icons.wifi_off,
                            size: 20,
                            color: value == 'Realtime terhubung'
                                ? QueueBStyle.success
                                : QueueBStyle.muted,
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              value,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: loading ? null : onPickDate,
                    icon: const Icon(Icons.calendar_month_outlined, size: 18),
                    label: Text('Tanggal: $date'),
                  ),
                  IconButton(
                    tooltip: 'Muat ulang portal',
                    onPressed: loading ? null : onRefresh,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 4,
            child: loading ? const LinearProgressIndicator() : null,
          ),
          error == null
              ? const SizedBox.shrink()
              : MobileNotice(error!, error: true),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, box) {
              final profileCard = DoctorPanel(child: _profile(context));
              final metrics = <(String, String, String, IconData, Color)>[
                (
                  current ? 'Janji Hari Ini' : 'Janji Tanggal Pilihan',
                  available ? '${appointments.length}' : '—',
                  'Seluruh status appointment',
                  Icons.calendar_month_outlined,
                  QueueBStyle.darkTeal,
                ),
                (
                  'Dalam Antrean',
                  available && current && snapshots.isNotEmpty
                      ? '${data.queueTotal}'
                      : '—',
                  snapshots.isEmpty
                      ? 'Belum ada sesi live yang dapat dipantau'
                      : 'Menunggu + aktif pada sesi live',
                  Icons.groups_outlined,
                  QueueBStyle.danger,
                ),
                (
                  'Konsultasi Selesai',
                  available ? '${data.completed}' : '—',
                  'Janji temu; walk-in selesai tidak tercakup',
                  Icons.task_alt,
                  QueueBStyle.success,
                ),
              ];
              Widget kpi((String, String, String, IconData, Color) m) =>
                  DoctorPanel(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        DoctorIconTile(icon: m.$4, color: m.$5, size: 52),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                m.$1,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                m.$2,
                                style: const TextStyle(
                                  fontSize: 34,
                                  height: 1.1,
                                  fontWeight: FontWeight.w800,
                                  color: QueueBStyle.navy,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                available ? m.$3 : 'Data belum tersedia',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: QueueBStyle.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
              if (box.maxWidth >= 1152) {
                return IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(flex: 5, child: profileCard),
                      const SizedBox(width: 12),
                      for (var i = 0; i < metrics.length; i++) ...[
                        Expanded(flex: 2, child: kpi(metrics[i])),
                        if (i < metrics.length - 1) const SizedBox(width: 12),
                      ],
                    ],
                  ),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  profileCard,
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final m in metrics)
                        SizedBox(
                          width: box.maxWidth < 560
                              ? box.maxWidth
                              : box.maxWidth < 850
                              ? (box.maxWidth - 12) / 2
                              : (box.maxWidth - 24) / 3,
                          child: kpi(m),
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, box) {
              final queue = DoctorQueuePanel(
                key: ValueKey(date),
                entries: data.entries,
                config: config,
                date: date,
                available: available,
              );
              final live = DoctorLivePanel(
                data: data,
                config: config,
                available: available && current && snapshots.isNotEmpty,
                loading: loading,
                status: status,
              );
              if (box.maxWidth < 1100) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [queue, const SizedBox(height: 16), live],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 7, child: queue),
                  const SizedBox(width: 16),
                  Expanded(flex: 4, child: live),
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, box) {
              final practice = DoctorPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DoctorSectionTitle(
                      icon: Icons.calendar_month_outlined,
                      title: current
                          ? 'Jadwal Praktik Hari Ini'
                          : 'Jadwal Praktik Tanggal Pilihan',
                    ),
                    const SizedBox(height: 12),
                    if (!available)
                      const Text('Data jadwal belum tersedia.')
                    else if (schedules.isEmpty)
                      const DoctorInfoBlock(
                        icon: Icons.calendar_month_outlined,
                        child: Text(
                          'Tidak ada jadwal untuk tanggal pilihan.',
                          style: TextStyle(color: QueueBStyle.muted),
                        ),
                      )
                    else
                      for (final s in schedules) _schedule(context, s),
                  ],
                ),
              );
              final notes = DoctorPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const DoctorSectionTitle(
                      title: 'Catatan Klinis Dokter',
                      icon: Icons.description_outlined,
                    ),
                    const SizedBox(height: 12),
                    const DoctorInfoBlock(
                      icon: Icons.info_outline,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Pencatatan klinis belum tersedia di QueueB.',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Portal ini tidak menyediakan data SOAP atau rekam medis. Tidak ada catatan yang disimpan dari halaman ini.',
                            style: TextStyle(color: QueueBStyle.muted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
              if (box.maxWidth < 1000) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [practice, const SizedBox(height: 16), notes],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 6, child: practice),
                  const SizedBox(width: 16),
                  Expanded(flex: 5, child: notes),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          Text(
            'Zona pelayanan: ${config.serviceTimeZone} · Operasional antrean oleh PETUGAS',
            style: const TextStyle(fontSize: 12, color: QueueBStyle.muted),
          ),
        ],
      ),
    );
  }

  Widget _profile(BuildContext context) {
    final name = available ? '${profile['nama'] ?? 'Dokter'}' : 'Profil dokter';
    final clinics = rows(profile['poliklinik']).map(label).join(' · ');
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DoctorAvatar(size: MediaQuery.sizeOf(context).width < 600 ? 64 : 96),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                available
                    ? '${profile['spesialisasi'] ?? 'Dokter'}'
                    : 'Data belum tersedia',
                style: const TextStyle(color: QueueBStyle.muted),
              ),
              const SizedBox(height: 10),
              if (available)
                Text(
                  clinics.isEmpty ? 'Belum ada poliklinik terkait.' : clinics,
                  style: const TextStyle(fontSize: 12),
                ),
              const SizedBox(height: 10),
              doctorBadge(
                available && snapshots.isNotEmpty && date == config.today
                    ? 'Praktik Aktif'
                    : 'Tidak ada sesi live aktif',
                color: available && snapshots.isNotEmpty
                    ? QueueBStyle.darkTeal
                    : QueueBStyle.muted,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _schedule(BuildContext context, Json s) {
    final start = DateTime.tryParse('${s['mulaiPada']}'),
        end = DateTime.tryParse('${s['selesaiPada']}');
    final state = s['aktif'] != true
        ? 'Nonaktif'
        : end != null && !end.isAfter(config.now)
        ? 'Selesai'
        : start != null && start.isAfter(config.now)
        ? 'Akan datang'
        : 'Berlangsung';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Wrap(
        spacing: 16,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 114,
            child: Text(
              doctorTime(s, config),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          SizedBox(
            width: 180,
            child: Text(
              '${object(s['ruang'])['kode'] ?? ''} · ${label(object(s['ruang']))}',
            ),
          ),
          Text(
            label(object(s['poliklinik'])),
            style: const TextStyle(color: QueueBStyle.muted),
          ),
          doctorBadge(
            state,
            color: state == 'Berlangsung'
                ? QueueBStyle.darkTeal
                : QueueBStyle.muted,
          ),
        ],
      ),
    );
  }
}

void showDoctorQueueDetail(BuildContext context, Json row, AppConfig config) =>
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Detail antrean ${row['nomorAntrean']}'),
        content: SizedBox(
          width: 430,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label(object(row['poliklinik']))),
              Text(label(object(row['ruang']))),
              const SizedBox(height: 12),
              Text('Waktu slot: ${doctorTime(row, config)}'),
              Text('Status: ${doctorStatus(row['status'])}'),
              if (row['layakDipanggil'] is bool)
                Text(
                  row['layakDipanggil'] == true
                      ? 'Layak dipanggil menurut antrean saat ini.'
                      : 'Belum layak dipanggil menurut antrean saat ini.',
                ),
              const SizedBox(height: 16),
              const Text(
                'Nama pasien, keluhan dan catatan klinis tidak disediakan pada portal ini.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Tutup'),
          ),
        ],
      ),
    );

class DoctorQueuePanel extends StatefulWidget {
  const DoctorQueuePanel({
    super.key,
    required this.entries,
    required this.config,
    required this.date,
    required this.available,
  });
  final List<Json> entries;
  final AppConfig config;
  final String date;
  final bool available;
  @override
  State<DoctorQueuePanel> createState() => _DoctorQueuePanelState();
}

class _DoctorQueuePanelState extends State<DoctorQueuePanel> {
  String search = '', status = '';
  int page = 0;
  @override
  Widget build(BuildContext context) {
    final filtered = widget.entries
        .where(
          (e) =>
              (status.isEmpty || e['status'] == status) &&
              '${e['nomorAntrean']} ${label(object(e['poliklinik']))} ${label(object(e['ruang']))}'
                  .toLowerCase()
                  .contains(search),
        )
        .toList();
    final pages = math.max(1, (filtered.length / 10).ceil());
    page = page.clamp(0, pages - 1);
    final shown = filtered.skip(page * 10).take(10).toList();
    return DoctorPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DoctorSectionTitle(
            title: 'Daftar Antrean Poli',
            icon: Icons.calendar_month_outlined,
            subtitle: widget.date,
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, box) => Wrap(
              spacing: 12,
              runSpacing: 10,
              children: [
                SizedBox(
                  width: box.maxWidth >= 620
                      ? (box.maxWidth - 12) * .67
                      : box.maxWidth,
                  child: TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Cari nomor antrean, poli, atau ruang',
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() {
                      search = v.trim().toLowerCase();
                      page = 0;
                    }),
                  ),
                ),
                SizedBox(
                  width: box.maxWidth >= 620
                      ? (box.maxWidth - 12) * .33
                      : box.maxWidth,
                  child: DropdownButtonFormField<String>(
                    initialValue: '',
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Status antrean',
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('Semua status'),
                      ),
                      for (final s in [
                        'DIPESAN',
                        'CHECK_IN',
                        'MENUNGGU',
                        'DIPANGGIL',
                        'DILAYANI',
                        'SELESAI',
                        'DILEWATI',
                        'DIBATALKAN',
                      ])
                        DropdownMenuItem(
                          value: s,
                          child: Text(doctorStatus(s)),
                        ),
                    ],
                    onChanged: (v) => setState(() {
                      status = v ?? '';
                      page = 0;
                    }),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (!widget.available)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Data antrean belum tersedia.'),
            )
          else if (shown.isEmpty)
            const DoctorQueueEmpty()
          else
            LayoutBuilder(
              builder: (context, box) => SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: math.max(700, box.maxWidth),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: QueueBStyle.background,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Row(
                          children: [
                            Expanded(flex: 2, child: Text('No. Antrean')),
                            Expanded(flex: 2, child: Text('Jenis / slot')),
                            Expanded(
                              flex: 3,
                              child: Text('Poliklinik / ruang'),
                            ),
                            Expanded(flex: 2, child: Text('Status')),
                            SizedBox(width: 60, child: Text('Detail')),
                          ],
                        ),
                      ),
                      for (final row in shown) _row(row),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${widget.available ? filtered.length : '—'} antrean · halaman ${page + 1}/$pages',
                  style: const TextStyle(
                    fontSize: 12,
                    color: QueueBStyle.muted,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Antrean sebelumnya',
                onPressed: page == 0 ? null : () => setState(() => page--),
                icon: const Icon(Icons.chevron_left),
              ),
              IconButton(
                tooltip: 'Antrean berikutnya',
                onPressed: page + 1 >= pages
                    ? null
                    : () => setState(() => page++),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          const Text(
            'Nama pasien dan keluhan tidak tersedia. Urutan menunggu mengikuti snapshot sesi; daftar juga mencakup appointment tanggal pilihan.',
            style: TextStyle(fontSize: 11, color: QueueBStyle.muted),
          ),
        ],
      ),
    );
  }

  Widget _row(Json row) {
    final active = ['DIPANGGIL', 'DILAYANI'].contains(row['status']);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: active ? QueueBStyle.mint : Colors.white,
        border: const Border(bottom: BorderSide(color: QueueBStyle.border)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: doctorBadge('${row['nomorAntrean'] ?? '—'}'),
            ),
          ),
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row['jenisAntrean'] == 'WALK_IN'
                      ? 'Walk-in'
                      : row['jenisAntrean'] == 'JANJI_TEMU'
                      ? 'Janji temu'
                      : 'Antrean',
                  style: const TextStyle(fontSize: 12),
                ),
                Text(
                  doctorTime(row, widget.config),
                  style: const TextStyle(
                    fontSize: 11,
                    color: QueueBStyle.muted,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label(object(row['poliklinik'])),
                  style: const TextStyle(fontSize: 12),
                ),
                Text(
                  '${object(row['ruang'])['kode'] ?? label(object(row['ruang']))}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: QueueBStyle.muted,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: doctorBadge(
                doctorStatus(row['status']),
                color: doctorStatusColor(row['status']),
              ),
            ),
          ),
          SizedBox(
            width: 60,
            child: TextButton(
              onPressed: () =>
                  showDoctorQueueDetail(context, row, widget.config),
              child: const Text('Lihat'),
            ),
          ),
        ],
      ),
    );
  }
}

class DoctorLivePanel extends StatefulWidget {
  const DoctorLivePanel({
    super.key,
    required this.data,
    required this.config,
    required this.available,
    required this.loading,
    required this.status,
  });
  final DoctorDashboardData data;
  final AppConfig config;
  final bool available, loading;
  final ValueListenable<String> status;
  @override
  State<DoctorLivePanel> createState() => _DoctorLivePanelState();
}

class _DoctorLivePanelState extends State<DoctorLivePanel> {
  String? selected;
  @override
  Widget build(BuildContext context) {
    final active = widget.available ? widget.data.active : <Json>[];
    final ticket =
        active
            .where((a) => DoctorDashboardData.key(a) == selected)
            .firstOrNull ??
        active.firstOrNull;
    final next = widget.available ? widget.data.nextEligible : null;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [DoctorStyle.deepNavy, DoctorStyle.deepTeal],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: DefaultTextStyle(
        style: const TextStyle(color: Colors.white, fontSize: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Icon(
                  Icons.connected_tv_outlined,
                  color: Colors.white,
                  size: 30,
                ),
                SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'Pemanggilan Antrean Live',
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ValueListenableBuilder<String>(
              valueListenable: widget.status,
              builder: (context, value, _) => Text(
                value,
                style: const TextStyle(
                  color: DoctorStyle.liveMuted,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              widget.loading ? 'MEMPERBARUI SNAPSHOT' : 'ANTREAN SAAT INI',
              style: const TextStyle(
                fontSize: 12,
                color: DoctorStyle.liveMuted,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 10),
            if (ticket == null) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Row(
                  children: [
                    CircleAvatar(
                      radius: 25,
                      backgroundColor: Colors.white24,
                      child: Icon(
                        Icons.person_outline,
                        color: Colors.white,
                        size: 30,
                      ),
                    ),
                    SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '—',
                            style: TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            'Belum ada antrean',
                            style: TextStyle(color: DoctorStyle.liveMuted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Text(
                !widget.available
                    ? 'Monitoring tersedia selama sesi praktik Anda berlangsung pada hari pelayanan.'
                    : 'Belum ada nomor dipanggil.',
              ),
            ] else ...[
              Text(
                '${ticket['nomorAntrean']}',
                style: const TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.w800,
                  color: DoctorStyle.liveNumber,
                ),
              ),
              Text(
                doctorStatus(ticket['status']),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 14),
              Text(label(object(ticket['poliklinik']))),
              Text(
                '${object(ticket['ruang'])['kode'] ?? ''} · ${label(object(ticket['ruang']))}',
              ),
              if (object(ticket['ruang'])['lokasi'] != null)
                Text('${object(ticket['ruang'])['lokasi']}'),
              const SizedBox(height: 10),
              Text(
                'Slot: ${doctorTime(ticket, widget.config)} · ${widget.config.serviceTimeZone}',
                style: const TextStyle(fontSize: 12),
              ),
              if (active.length > 1)
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final row in active)
                      ActionChip(
                        label: Text('${row['nomorAntrean']}'),
                        onPressed: () => setState(
                          () => selected = DoctorDashboardData.key(row),
                        ),
                      ),
                  ],
                ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: () =>
                    showDoctorQueueDetail(context, ticket, widget.config),
                icon: const Icon(Icons.visibility_outlined),
                label: const Text('Lihat detail antrean'),
              ),
            ],
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Divider(color: Colors.white24),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                next == null
                    ? 'Belum ada antrean berikutnya yang layak dipanggil pada snapshot.'
                    : 'Berikutnya yang layak: ${next['nomorAntrean']}',
                style: const TextStyle(color: DoctorStyle.liveMuted),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Pemantauan saja. Pemanggilan, mulai, dan penyelesaian pelayanan dilakukan PETUGAS.',
              style: TextStyle(fontSize: 12, color: Colors.white70),
            ),
            if (widget.available && widget.data.snapshots.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                'Snapshot: ${widget.config.instantLabel(widget.data.snapshots.first['diperolehPada'])}',
                style: const TextStyle(fontSize: 11, color: Colors.white70),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
