import 'package:flutter/material.dart';

import 'config.dart';
import 'mobile_ui.dart';
import 'doctor_professional.dart';

// Hallmark · scoped patient journey · QueueB reference · P5 H5 E4 S5 R5 V4.
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
      constraints: const BoxConstraints(maxWidth: 520),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: QueueBStyle.border)),
        ),
        child: SafeArea(
          top: false,
          child: NavigationBarTheme(
            data: NavigationBarTheme.of(context).copyWith(
              iconTheme: WidgetStateProperty.resolveWith(
                (states) => IconThemeData(
                  size: 22,
                  color: states.contains(WidgetState.selected)
                      ? QueueBStyle.darkTeal
                      : QueueBStyle.muted,
                ),
              ),
              labelTextStyle: WidgetStateProperty.resolveWith(
                (states) => TextStyle(
                  fontSize: 11,
                  fontWeight: states.contains(WidgetState.selected)
                      ? FontWeight.w700
                      : FontWeight.w500,
                  color: states.contains(WidgetState.selected)
                      ? QueueBStyle.darkTeal
                      : QueueBStyle.muted,
                ),
              ),
            ),
            child: NavigationBar(
              height: 60,
              selectedIndex: selectedIndex,
              onDestinationSelected: onSelected,
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home),
                  label: 'Beranda',
                ),
                NavigationDestination(
                  icon: Icon(Icons.add_circle_outline),
                  label: 'Pendaftaran',
                ),
                NavigationDestination(
                  icon: Icon(Icons.confirmation_number_outlined),
                  label: 'Tiket Saya',
                ),
                NavigationDestination(
                  icon: Icon(Icons.calendar_month_outlined),
                  label: 'Janji Temu',
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
                  color: QueueBStyle.navy,
                ),
              ),
              if (caption != null)
                Text(
                  caption!,
                  style: const TextStyle(
                    color: QueueBStyle.muted,
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

class PatientWelcome extends StatelessWidget {
  const PatientWelcome({super.key, required this.name, required this.onSearch});
  final String name;
  final ValueChanged<String> onSearch;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: QueueBStyle.darkTeal,
      borderRadius: BorderRadius.circular(24),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'QueueB Hospital',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 20),
        const Text('Selamat datang,', style: TextStyle(color: Colors.white)),
        Text(
          name,
          style: Theme.of(context).textTheme.headlineSmall
              ?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        const Text(
          'Rencanakan kunjungan dengan lebih nyaman.',
          style: TextStyle(color: Colors.white, fontSize: 12),
        ),
        const SizedBox(height: 20),
        TextField(
          decoration: const InputDecoration(
            hintText: 'Cari poliklinik atau dokter',
            filled: true,
            fillColor: Colors.white,
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: onSearch,
        ),
      ],
    ),
  );
}

class PatientClinicGrid extends StatelessWidget {
  const PatientClinicGrid({
    super.key,
    required this.clinics,
    required this.onSelected,
    this.enabled = true,
  });
  final List<Json> clinics;
  final ValueChanged<Json> onSelected;
  final bool enabled;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final count = box.maxWidth < 350 ? 3 : 4;
      return Wrap(
        spacing: 8,
        runSpacing: 12,
        children: [
          for (final clinic in clinics)
            SizedBox(
              width: (box.maxWidth - 8 * (count - 1)) / count,
              child: Semantics(
                button: true,
                label: label(clinic),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: enabled ? () => onSelected(clinic) : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: 26,
                          backgroundColor: QueueBStyle.mint,
                          foregroundColor: QueueBStyle.darkTeal,
                          child: Icon(clinicIcon(label(clinic))),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          label(clinic),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 11,
                            color: QueueBStyle.navy,
                            fontWeight: FontWeight.w600,
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
                      color: QueueBStyle.navy,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${doctor['spesialisasi'] ?? 'Spesialisasi belum dicantumkan'}',
                    style: const TextStyle(
                      color: QueueBStyle.muted,
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
          style: const TextStyle(color: QueueBStyle.muted, fontSize: 12),
        ),
        Text(
          schedule,
          style: const TextStyle(color: QueueBStyle.darkTeal, fontSize: 12),
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
          backgroundColor: QueueBStyle.mint,
          foregroundColor: QueueBStyle.darkTeal,
          child: Icon(icon, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(color: QueueBStyle.muted, fontSize: 12),
              ),
              Text(
                value,
                style: const TextStyle(
                  color: QueueBStyle.navy,
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
