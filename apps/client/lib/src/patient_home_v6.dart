import 'package:flutter/material.dart';

import 'config.dart';
import 'doctor_professional.dart';
import 'patient_design.dart';
import 'patient_home.dart';
import 'patient_ui.dart';

/// Home presentation only; booking and invalidation remain in PatientPage.
enum PatientHomeMode { walkIn, appointment }

abstract final class PatientHomeV6Style {
  static const walkIn = PatientDesign.primary;
  static const visit = PatientDesign.hero;
  static const soft = PatientDesign.soft;
}

// The existing API has no service-category field. These explicit service codes
// identify auxiliary desks, independently of the booking mode. No catalog rows
// are invented here; administrators still own the actual records in the API.
bool isAuxiliaryHomeService(Json clinic) => const {
  'PENDAFTARAN',
  'REGISTRASI',
  'ADMINISTRASI',
  'APOTEK',
  'APOTIK',
}.contains('${clinic['kode'] ?? ''}'.toUpperCase());

bool supportsHomeWalkIn(Json clinic) =>
    clinic['aktif'] != false &&
    isAuxiliaryHomeService(clinic) &&
    ['ANTREAN_HARIAN', 'HIBRIDA'].contains(clinic['modeReservasi']);

bool supportsHomeAppointment(Json clinic) =>
    clinic['aktif'] != false &&
    !isAuxiliaryHomeService(clinic) &&
    [
      'ANTREAN_HARIAN',
      'JANJI_TEMU_DOKTER',
      'HIBRIDA',
    ].contains(clinic['modeReservasi']);

List<Json> homeWalkInClinics(
  List<Json> clinics,
  List<Json> doctors,
  String query,
) => clinics.where((clinic) {
  if (!supportsHomeWalkIn(clinic)) return false;
  if ('${label(clinic)} ${clinic['deskripsi'] ?? ''} ${clinic['kode'] ?? ''}'
      .toLowerCase()
      .contains(query)) {
    return true;
  }
  return doctors.any(
    (doctor) =>
        doctor['aktif'] != false &&
        '${label(doctor)} ${doctor['spesialisasi'] ?? ''}'
            .toLowerCase()
            .contains(query) &&
        rows(doctor['dokterLayanan']).any(
          (link) => link['aktif'] == true && link['layananId'] == clinic['id'],
        ),
  );
}).toList();

class PatientHomeHeaderV6 extends StatelessWidget {
  const PatientHomeHeaderV6({super.key, required this.name});
  final String name;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: PatientHomeV6Style.walkIn,
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(
              Icons.local_hospital_rounded,
              size: 22,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 9),
          const Flexible(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'QueueB ',
                    style: TextStyle(color: PatientDesign.ink),
                  ),
                  TextSpan(
                    text: 'Hospital',
                    style: TextStyle(color: PatientHomeV6Style.walkIn),
                  ),
                ],
              ),
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      const Text(
        'Selamat datang,',
        style: TextStyle(fontSize: 12, color: PatientDesign.muted),
      ),
      Text(
        name,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: PatientDesign.ink,
        ),
      ),
    ],
  );
}

class PatientHomeModes extends StatelessWidget {
  const PatientHomeModes({
    super.key,
    required this.value,
    required this.onChanged,
  });
  final PatientHomeMode value;
  final ValueChanged<PatientHomeMode>? onChanged;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final mode in PatientHomeMode.values) ...[
        if (mode == PatientHomeMode.appointment) const SizedBox(width: 8),
        Expanded(
          child: Semantics(
            selected: value == mode,
            child: OutlinedButton(
              key: ValueKey('home-mode-${mode.name}'),
              onPressed: onChanged == null ? null : () => onChanged!(mode),
              style: OutlinedButton.styleFrom(
                backgroundColor: value != mode
                    ? PatientDesign.paper
                    : mode == PatientHomeMode.walkIn
                    ? PatientHomeV6Style.walkIn
                    : PatientDesign.primary,
                foregroundColor: value == mode
                    ? Colors.white
                    : PatientDesign.ink,
                side: BorderSide(
                  color: value == mode
                      ? Colors.transparent
                      : PatientDesign.border,
                ),
                minimumSize: const Size(0, 48),
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    mode == PatientHomeMode.walkIn
                        ? Icons.groups_outlined
                        : Icons.calendar_month_outlined,
                    size: 18,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      mode == PatientHomeMode.walkIn
                          ? 'Ambil Antrean'
                          : 'Janji Temu',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    ],
  );
}

class PatientHomeService extends StatelessWidget {
  const PatientHomeService({super.key, required this.clinic, this.onTap});
  final Json clinic;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => _HomeListTile(
    onTap: onTap,
    leading: Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: PatientHomeV6Style.soft,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Icon(
        clinicIcon(label(clinic)),
        color: PatientHomeV6Style.walkIn,
        size: 23,
      ),
    ),
    title: label(clinic),
    subtitle: 'Antrean harian · Pilih tanggal pelayanan',
    accent: PatientHomeV6Style.walkIn,
  );
}

class PatientHomeDoctorV6 extends StatelessWidget {
  const PatientHomeDoctorV6({
    super.key,
    required this.preview,
    required this.config,
    this.onTap,
    this.scheduleUnavailable = false,
  });
  final HomeDoctorPreview preview;
  final AppConfig config;
  final VoidCallback? onTap;
  final bool scheduleUnavailable;
  @override
  Widget build(BuildContext context) => _HomeListTile(
    onTap: onTap,
    leading: ProfessionalDoctorAvatar(
      config: config,
      photo: preview.doctor['fotoProfil'],
      radius: 22,
    ),
    title: label(preview.doctor),
    subtitle: [
      if (preview.doctor['spesialisasi'] != null)
        '${preview.doctor['spesialisasi']}',
      label(preview.clinic),
    ].join(' · '),
    note: preview.clinic['modeReservasi'] == 'ANTREAN_HARIAN'
        ? 'Layanan poli ini menggunakan antrean harian.'
        : scheduleUnavailable
        ? 'Jadwal belum dapat dimuat.'
        : preview.session == null
        ? 'Jadwal belum tersedia.'
        : null,
    accent: PatientDesign.primary,
  );
}

class _HomeListTile extends StatelessWidget {
  const _HomeListTile({
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.accent,
    this.note,
    this.onTap,
  });
  final Widget leading;
  final String title, subtitle;
  final String? note;
  final Color accent;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: PatientDesign.paper,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: const BorderSide(color: PatientDesign.border),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            leading,
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: PatientDesign.ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.3,
                      color: PatientDesign.muted,
                    ),
                  ),
                  if (note != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      note!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: PatientDesign.muted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right_rounded, size: 22, color: accent),
          ],
        ),
      ),
    ),
  );
}
