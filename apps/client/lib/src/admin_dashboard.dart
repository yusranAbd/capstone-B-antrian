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
  });
  final Map<String, List<Json>> catalog;
  final AppConfig config;
  final bool loading;
  final ValueChanged<int> onSelect;
  @override
  Widget build(BuildContext context) {
    final clinics = catalog['/layanan'] ?? [],
        doctors = catalog['/dokter'] ?? [],
        rooms = catalog['/loket'] ?? [],
        sessions = catalog['/jadwal-praktik'] ?? [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Ringkasan master data dan kesiapan layanan rumah sakit.',
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: QueueBStyle.muted),
        ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, box) {
            final columns = box.maxWidth >= 1000
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
                    child: Card(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: loading ? null : () => onSelect(item.$4),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: QueueBStyle.mint,
                                foregroundColor: QueueBStyle.darkTeal,
                                child: Icon(item.$3),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.$1,
                                      style: const TextStyle(
                                        color: QueueBStyle.muted,
                                      ),
                                    ),
                                    Text(
                                      catalog.isEmpty
                                          ? '—'
                                          : '${item.$2.length}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .headlineMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                            color: QueueBStyle.navy,
                                          ),
                                    ),
                                    Text(
                                      catalog.isEmpty
                                          ? 'Data belum tersedia'
                                          : '${item.$2.where((r) => r['aktif'] == true).length} aktif',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: QueueBStyle.darkTeal,
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
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 24),
        Text(
          'Layanan per poliklinik',
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        if (clinics.isEmpty && !loading && catalog.isNotEmpty)
          const Notice(
            'Belum ada poliklinik. Tambahkan master data untuk memulai.',
          ),
        AdminTable(
          rows: clinics,
          columns: [
            AdminColumn('Poliklinik', (r) => label(r)),
            AdminColumn(
              'Dokter terkait',
              (r) => doctors
                  .where(
                    (d) => rows(d['dokterLayanan']).any(
                      (l) => l['layananId'] == r['id'] && l['aktif'] == true,
                    ),
                  )
                  .length,
              numeric: true,
            ),
            AdminColumn(
              'Ruang',
              (r) => rooms.where((room) => room['layananId'] == r['id']).length,
              numeric: true,
            ),
            AdminColumn(
              'Sesi praktik',
              (r) => sessions
                  .where(
                    (s) => object(s['dokterLayanan'])['layananId'] == r['id'],
                  )
                  .length,
              numeric: true,
            ),
            AdminColumn(
              'Status',
              (r) => r['aktif'] == true ? 'Aktif' : 'Nonaktif',
            ),
          ],
        ),
        const SizedBox(height: 20),
        const Notice(
          'Ringkasan berasal dari katalog API. Statistik pasien, antrean live dan rata-rata waktu tunggu belum tersedia untuk role ADMIN.',
        ),
      ],
    );
  }
}
