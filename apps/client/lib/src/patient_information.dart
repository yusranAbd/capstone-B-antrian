import 'package:flutter/material.dart';

import 'config.dart';
import 'mobile_ui.dart';
import 'patient_design.dart';
import 'patient_home_v7.dart';
import 'patient_home_v8.dart';

/// A view of the existing USER catalog owned by PatientRepository. No request,
/// subscription, account snapshot, clinical content or second owner lives here.
class PatientInformation extends StatelessWidget {
  const PatientInformation({
    super.key,
    required this.services,
    required this.hours,
    required this.date,
    required this.timeZone,
    required this.hoursAvailable,
    required this.loading,
    required this.onRefresh,
    this.error,
    this.hoursError,
  });
  final List<Json> services, hours;
  final String date;
  final String timeZone;
  final bool hoursAvailable, loading;
  final String? error, hoursError;
  final VoidCallback? onRefresh;
  @override
  Widget build(BuildContext context) => ListView.builder(
    key: const PageStorageKey('patient-information'),
    padding: const EdgeInsets.all(16),
    itemCount: 1 + (services.isEmpty ? 1 : services.length),
    itemBuilder: (context, index) {
      if (index == 0) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Informasi layanan',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                        color: PatientDesign.ink,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Muat ulang informasi',
                    onPressed: onRefresh,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Layanan dan jam operasional dari katalog rumah sakit. Jadwal mengikuti zona pelayanan $timeZone.',
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: PatientDesign.muted,
                ),
              ),
              if (loading)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: LinearProgressIndicator(),
                ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(error!),
                ),
              if (hoursError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(hoursError!),
                ),
            ],
          ),
        );
      }
      if (services.isEmpty) {
        return const EmptyState(
          text: 'Belum ada informasi layanan yang dapat ditampilkan.',
        );
      }
      final service = services[index - 1];
      final category = homeServiceCategory(service),
          accent = PatientHomeV8Style.accent(homeServiceCategory(service));
      final mode = switch (service['modeReservasi']) {
        'ANTREAN_HARIAN' => 'Antrean harian',
        'JANJI_TEMU_DOKTER' => 'Janji temu dokter',
        'HIBRIDA' => 'Antrean harian & janji temu',
        _ => 'Mode reservasi belum tersedia',
      };
      return Card(
        key: ValueKey(('information', service['id'])),
        margin: const EdgeInsets.only(bottom: 10),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(PatientServiceAccent.icon(category), color: accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label(service),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if ('${service['deskripsi'] ?? ''}'.trim().isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text('${service['deskripsi']}'),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      mode,
                      style: const TextStyle(
                        fontSize: 13,
                        color: PatientDesign.muted,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      patientServiceHours(
                        hours,
                        '${service['id']}',
                        date,
                        available: hoursAvailable,
                      ),
                      style: const TextStyle(
                        fontSize: 13,
                        color: PatientDesign.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
