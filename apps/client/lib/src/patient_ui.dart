import 'package:flutter/material.dart';

import 'config.dart';
import 'mobile_ui.dart';
import 'patient_design.dart';
import 'doctor_professional.dart';
import 'queueb_motion.dart';

// Tokens remain in QueueBStyle; no changes to shared themes or other roles.
String patientDate(String value) {
  final day = DateTime.tryParse(dateOnly(value));
  if (day == null) return '—';
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
  const days = ['Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu'];
  return '${days[day.weekday - 1]}, ${day.day} ${months[day.month - 1]} ${day.year}';
}

String patientCompactDate(String value) {
  final date = DateTime.tryParse(dateOnly(value));
  if (date == null) return 'Tanggal belum tersedia';
  const days = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'Mei',
    'Jun',
    'Jul',
    'Agu',
    'Sep',
    'Okt',
    'Nov',
    'Des',
  ];
  return '${days[date.weekday - 1]}, ${date.day} ${months[date.month - 1]}';
}

String patientTime(Json value, AppConfig config) =>
    '${clockOnly(config.localInput(value['mulaiPada']))} – ${clockOnly(config.localInput(value['selesaiPada']))}';

IconData clinicIcon(String name) {
  final text = name.toLowerCase();
  if (text.contains('mata')) return Icons.visibility_outlined;
  if (text.contains('anak')) return Icons.child_care_outlined;
  if (text.contains('gigi')) return Icons.health_and_safety_outlined;
  if (text.contains('jantung')) return Icons.monitor_heart_outlined;
  if (text.contains('tht')) return Icons.hearing_outlined;
  if (text.contains('saraf')) return Icons.psychology_outlined;
  if (text.contains('kandungan')) return Icons.pregnant_woman_outlined;
  if (text.contains('bedah')) return Icons.healing_outlined;
  if (text.contains('rehabilitasi')) return Icons.accessibility_new;
  if (text.contains('kulit')) return Icons.back_hand_outlined;
  if (text.contains('urologi')) return Icons.water_drop_outlined;
  return Icons.medical_services_outlined;
}

/// Compact patient-only navigation; no changes to shared role themes.
class PatientBottomNavigation extends StatelessWidget {
  static const activeColor = Color(0xff0968d8);
  const PatientBottomNavigation({
    super.key,
    required this.selectedIndex,
    this.onSelected,
  });
  final int selectedIndex;
  final ValueChanged<int>? onSelected;

  @override
  Widget build(BuildContext context) => Align(
    heightFactor: 1,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 680),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: PatientDesign.paper,
          border: Border(top: BorderSide(color: PatientDesign.border)),
        ),
        child: SafeArea(
          top: false,
          child: NavigationBarTheme(
            data: NavigationBarTheme.of(context).copyWith(
              iconTheme: WidgetStateProperty.resolveWith(
                (states) => IconThemeData(
                  size: 25,
                  color: states.contains(WidgetState.selected)
                      ? activeColor
                      : PatientDesign.muted,
                ),
              ),
              labelTextStyle: WidgetStateProperty.resolveWith(
                (states) => TextStyle(
                  fontSize: 12,
                  fontWeight: states.contains(WidgetState.selected)
                      ? FontWeight.w700
                      : FontWeight.w500,
                  color: states.contains(WidgetState.selected)
                      ? activeColor
                      : PatientDesign.muted,
                ),
              ),
            ),
            child: NavigationBar(
              height: (MediaQuery.textScalerOf(context).scale(12) * 1.2 + 52)
                  .clamp(68, double.infinity),
              animationDuration: QueueBMotion.duration(
                context,
                QueueBMotion.component,
              ),
              backgroundColor: PatientDesign.paper,
              indicatorColor: Colors.transparent,
              selectedIndex: selectedIndex,
              onDestinationSelected: onSelected,
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home),
                  label: 'Beranda',
                ),
                NavigationDestination(
                  icon: Icon(Icons.history_rounded),
                  label: 'Riwayat',
                ),
                NavigationDestination(
                  icon: Icon(Icons.info_outline_rounded),
                  label: 'Informasi',
                ),
                NavigationDestination(
                  icon: Icon(Icons.person_outline),
                  selectedIcon: Icon(Icons.person),
                  label: 'Profil',
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class PatientHeading extends StatelessWidget {
  const PatientHeading({
    super.key,
    required this.title,
    this.onBack,
    this.caption,
  });
  final String title;
  final String? caption;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Row(
      children: [
        if (onBack != null) ...[
          IconButton(
            tooltip: 'Kembali',
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back),
          ),
          const SizedBox(width: 4),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: PatientDesign.navy,
                ),
              ),
              if (caption != null)
                Text(
                  caption!,
                  style: const TextStyle(
                    color: PatientDesign.muted,
                    fontSize: 12,
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

class PatientDoctorCard extends StatelessWidget {
  const PatientDoctorCard({
    super.key,
    required this.doctor,
    required this.config,
    required this.schedule,
    required this.onDetails,
  });
  final Json doctor;
  final AppConfig config;
  final String schedule;
  final VoidCallback? onDetails;

  @override
  Widget build(BuildContext context) => AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ProfessionalDoctorAvatar(
              config: config,
              photo: doctor['fotoProfil'],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label(doctor),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: PatientDesign.navy,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${doctor['spesialisasi'] ?? 'Spesialisasi belum dicantumkan'}',
                    style: const TextStyle(
                      color: PatientDesign.muted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          rows(doctor['dokterLayanan'])
              .where((link) => link['aktif'] != false)
              .map((link) => label(object(link['layanan'])))
              .join(', '),
          style: const TextStyle(color: PatientDesign.muted, fontSize: 12),
        ),
        Text(
          schedule,
          style: const TextStyle(color: PatientDesign.darkTeal, fontSize: 12),
        ),
        const SizedBox(height: 4),
        TextButton.icon(
          onPressed: onDetails,
          icon: const Icon(Icons.arrow_forward, size: 18),
          label: const Text('Lihat Detail Dokter'),
        ),
      ],
    ),
  );
}

class PatientInfoRow extends StatelessWidget {
  const PatientInfoRow({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
  });
  final IconData icon;
  final String title, value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: PatientDesign.mint,
          foregroundColor: PatientDesign.darkTeal,
          child: Icon(icon, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: PatientDesign.muted,
                  fontSize: 12,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  color: PatientDesign.navy,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class AppointmentReview extends StatelessWidget {
  const AppointmentReview({
    super.key,
    required this.doctor,
    required this.clinic,
    required this.session,
    required this.slot,
    required this.config,
  });
  final Json doctor, clinic, session, slot;
  final AppConfig config;
  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(16),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const PatientHeading(title: 'Konfirmasi Janji Temu'),
            PatientInfoRow(
              icon: Icons.person_outline,
              title: 'Dokter',
              value: label(doctor),
            ),
            PatientInfoRow(
              icon: Icons.local_hospital_outlined,
              title: 'Poliklinik',
              value: label(clinic),
            ),
            PatientInfoRow(
              icon: Icons.room_outlined,
              title: 'Ruang / Loket',
              value:
                  '${object(session['loket'])['kode'] ?? ''} · ${label(object(session['loket']))}',
            ),
            PatientInfoRow(
              icon: Icons.calendar_month_outlined,
              title: 'Tanggal',
              value: patientDate('${session['tanggal']}'),
            ),
            PatientInfoRow(
              icon: Icons.schedule,
              title: 'Waktu',
              value: '${patientTime(slot, config)} · ${config.serviceTimeZone}',
            ),
            const SizedBox(height: 12),
            const MobileNotice(
              'Nomor tiket diterbitkan setelah booking berhasil. Ketersediaan diperiksa kembali oleh server.',
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Konfirmasi Janji Temu'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Kembali'),
            ),
          ],
        ),
      ),
    ),
  );
}
