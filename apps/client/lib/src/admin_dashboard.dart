import 'package:flutter/material.dart';

import 'admin_ui.dart';
import 'config.dart';
import 'mobile_ui.dart';
import 'widgets.dart';

class AdminDashboard extends StatelessWidget {
  const AdminDashboard({
    super.key,
    required this.catalog,
    required this.config,
    required this.loading,
    required this.onSelect,
    this.administratorName,
    this.onRefresh,
  });
  final Map<String, List<Json>> catalog;
  final AppConfig config;
  final bool loading;
  final ValueChanged<int> onSelect;
  final String? administratorName;
  final VoidCallback? onRefresh;
  @override
  Widget build(BuildContext context) {
    final clinics = catalog['/layanan'] ?? [],
        doctors = catalog['/dokter'] ?? [],
        rooms = catalog['/loket'] ?? [],
        sessions = catalog['/jadwal-praktik'] ?? [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DashboardWelcome(
          config: config,
          name: administratorName,
          onRefresh: loading ? null : onRefresh,
        ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, box) {
            final columns = box.maxWidth >= 900
                ? 4
                : box.maxWidth >= 520
                ? 2
                : 1;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final item in <(String, List<Json>, IconData, int)>[
                  ('Poliklinik', clinics, Icons.local_hospital_outlined, 0),
                  ('Dokter', doctors, Icons.medical_services_outlined, 1),
                  ('Ruang / Loket', rooms, Icons.meeting_room_outlined, 2),
                  (
                    'Jadwal Praktik',
                    sessions,
                    Icons.calendar_month_outlined,
                    4,
                  ),
                ])
                  SizedBox(
                    width: (box.maxWidth - 12 * (columns - 1)) / columns,
                    child: _MasterMetric(
                      title: item.$1,
                      count: catalog.isEmpty ? null : item.$2.length,
                      active: item.$2.where((r) => r['aktif'] == true).length,
                      icon: item.$3,
                      blue: item.$4 == 1 || item.$4 == 4,
                      onTap: loading ? null : () => onSelect(item.$4),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 24),
        Container(
          decoration: AdminStyle.panel,
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Row(
                children: [
                  CircleAvatar(
                    backgroundColor: QueueBStyle.mint,
                    foregroundColor: QueueBStyle.darkTeal,
                    child: Icon(Icons.meeting_room_outlined),
                  ),
                  SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Layanan per poliklinik',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Daftar layanan poliklinik beserta data pendukungnya.',
                          style: TextStyle(color: QueueBStyle.muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              if (clinics.isEmpty && !loading && catalog.isNotEmpty)
                const Notice(
                  'Belum ada poliklinik. Tambahkan master data untuk memulai.',
                ),
              Theme(
                data: Theme.of(context).copyWith(
                  cardTheme: const CardThemeData(
                    color: Colors.white,
                    elevation: 0,
                    margin: EdgeInsets.zero,
                  ),
                ),
                child: AdminTable(
                  compact: true,
                  decorated: false,
                  rows: clinics,
                  columns: [
                    AdminColumn(
                      'Poliklinik',
                      (r) => label(r),
                      cell: (r) => _ClinicName(name: label(r)),
                    ),
                    AdminColumn(
                      'Dokter terkait',
                      (r) => doctors
                          .where(
                            (d) => rows(d['dokterLayanan']).any(
                              (l) =>
                                  l['layananId'] == r['id'] &&
                                  l['aktif'] == true,
                            ),
                          )
                          .length,
                      numeric: true,
                      icon: Icons.medical_services_outlined,
                    ),
                    AdminColumn(
                      'Ruang',
                      (r) => rooms
                          .where((room) => room['layananId'] == r['id'])
                          .length,
                      numeric: true,
                      icon: Icons.meeting_room_outlined,
                    ),
                    AdminColumn(
                      'Sesi praktik',
                      (r) => sessions
                          .where(
                            (s) =>
                                object(s['dokterLayanan'])['layananId'] ==
                                r['id'],
                          )
                          .length,
                      numeric: true,
                      icon: Icons.calendar_month_outlined,
                    ),
                    AdminColumn(
                      'Status',
                      (r) => r['aktif'] == true ? 'Aktif' : 'Nonaktif',
                      icon: Icons.monitor_heart_outlined,
                      cell: (r) => _ClinicStatus(active: r['aktif'] == true),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

String adminDateLabel(AppConfig config) {
  const days = ['Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu'];
  const months = [
    'Januari',
    'Februari',
    'Maret',
    'April',
    'Mei',
    'Juni',
    'Juli',
    'Agustus',
    'September',
    'Oktober',
    'November',
    'Desember',
  ];
  final now = config.now;
  return '${days[now.weekday - 1]}, ${now.day} ${months[now.month - 1]} ${now.year}';
}

class _DashboardWelcome extends StatelessWidget {
  const _DashboardWelcome({required this.config, this.name, this.onRefresh});
  final AppConfig config;
  final String? name;
  final VoidCallback? onRefresh;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final intro = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Dashboard',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.6,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Muat ulang dashboard',
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh_rounded, size: 21),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.calendar_month_outlined, size: 18),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      adminDateLabel(config),
                      style: const TextStyle(color: QueueBStyle.muted),
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.location_on_outlined, size: 18),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      config.serviceTimeZone,
                      style: const TextStyle(color: QueueBStyle.muted),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Text(
            'Ringkasan master data dan kesiapan layanan rumah sakit.',
            style: TextStyle(color: QueueBStyle.muted, height: 1.5),
          ),
        ],
      );
      final welcome = _WelcomeBanner(name: name);
      return box.maxWidth >= 900
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(flex: 4, child: intro),
                const SizedBox(width: 24),
                Expanded(flex: 6, child: welcome),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [intro, const SizedBox(height: 20), welcome],
            );
    },
  );
}

class _WelcomeBanner extends StatelessWidget {
  const _WelcomeBanner({this.name});
  final String? name;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final displayName = name == null || name!.trim().isEmpty
          ? 'Administrator'
          : name!.trim();
      final compact = box.maxWidth < 440;
      return Container(
        key: const ValueKey('admin-welcome'),
        constraints: const BoxConstraints(minHeight: 160),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: const LinearGradient(
            colors: [AdminStyle.canvas, AdminStyle.sky],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              right: 6,
              bottom: 0,
              width: box.maxWidth * (compact ? .30 : .40),
              height: 156,
              child: ExcludeSemantics(
                child: Image.asset(
                  'assets/illustrations/admin_welcome.png',
                  fit: BoxFit.contain,
                  alignment: Alignment.bottomRight,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(22),
              child: SizedBox(
                width: box.maxWidth * (compact ? .60 : .55),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Selamat datang,',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      '$displayName!',
                      style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                        color: QueueBStyle.darkTeal,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      compact
                          ? 'Kelola poliklinik, dokter, ruang, dan jadwal layanan.'
                          : 'Kelola data poliklinik, dokter, ruang, dan jadwal untuk memastikan pelayanan rumah sakit berjalan dengan tertib dan optimal.',
                      style: const TextStyle(
                        color: QueueBStyle.muted,
                        height: 1.45,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _MasterMetric extends StatelessWidget {
  const _MasterMetric({
    required this.title,
    required this.count,
    required this.active,
    required this.icon,
    required this.blue,
    this.onTap,
  });
  final String title;
  final int? count;
  final int active;
  final IconData icon;
  final bool blue;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Container(
    decoration: AdminStyle.panel,
    child: Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
          child: Row(
            children: [
              CircleAvatar(
                radius: 27,
                backgroundColor: blue ? AdminStyle.sky : QueueBStyle.mint,
                foregroundColor: blue ? AdminStyle.blue : QueueBStyle.darkTeal,
                child: Icon(icon, size: 30),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(color: QueueBStyle.muted),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      count == null ? '—' : '$count',
                      style: const TextStyle(
                        fontSize: 34,
                        height: 1.1,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      count == null ? 'Data belum tersedia' : '$active aktif',
                      style: const TextStyle(
                        color: QueueBStyle.darkTeal,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _ClinicName extends StatelessWidget {
  const _ClinicName({required this.name});
  final String name;
  @override
  Widget build(BuildContext context) {
    final lower = name.toLowerCase();
    final icon = lower.contains('anak')
        ? Icons.child_care_outlined
        : lower.contains('mata')
        ? Icons.visibility_outlined
        : lower.contains('bedah')
        ? Icons.healing_outlined
        : Icons.local_hospital_outlined;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: QueueBStyle.mint,
          foregroundColor: QueueBStyle.darkTeal,
          child: Icon(icon, size: 21),
        ),
        const SizedBox(width: 12),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 220),
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _ClinicStatus extends StatelessWidget {
  const _ClinicStatus({required this.active});
  final bool active;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(
      color: active ? QueueBStyle.mint : QueueBStyle.background,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.circle,
          size: 9,
          color: active ? QueueBStyle.success : QueueBStyle.muted,
        ),
        const SizedBox(width: 7),
        Text(
          active ? 'Aktif' : 'Nonaktif',
          style: TextStyle(
            color: active ? QueueBStyle.darkTeal : QueueBStyle.muted,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
      ],
    ),
  );
}
