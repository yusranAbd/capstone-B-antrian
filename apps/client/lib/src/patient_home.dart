import 'package:flutter/material.dart';

import 'config.dart';
import 'patient_design.dart';
import 'patient_ui.dart';
import 'doctor_professional.dart';

abstract final class PatientHomeStyle {
  static const background = PatientDesign.background;
  static const welcomeTint = PatientDesign.soft;
  static const shadow = Color(0x06172544);
  static const heroStart = PatientDesign.hero, heroEnd = PatientDesign.hero;
  static const clinicSurface = PatientDesign.soft;
  static const appointmentInk = PatientDesign.primary;
  static const appointmentSurface = PatientDesign.soft;
  static const ticketInk = PatientDesign.accent;
  static const ticketSurface = Color(0xffe4f4fc);
  static const historyInk = PatientDesign.success;
  static const historySurface = Color(0xffe6f0e7);
  static const visitSurface = PatientDesign.soft;
}

// Home-only visual layer. Existing booking, session and realtime owners stay in
// PatientPage.
class PatientHomeBrand extends StatelessWidget {
  const PatientHomeBrand({super.key});
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: PatientDesign.teal,
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(
          Icons.local_hospital_rounded,
          color: Colors.white,
          size: 26,
        ),
      ),
      const SizedBox(width: 8),
      const Flexible(
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(text: 'QueueB\n'),
              TextSpan(
                text: 'Hospital',
                style: TextStyle(color: PatientDesign.darkTeal),
              ),
            ],
          ),
          style: TextStyle(
            fontSize: 17,
            height: 1.05,
            fontWeight: FontWeight.w800,
            color: PatientDesign.navy,
          ),
        ),
      ),
    ],
  );
}

class PatientHomeSurface extends StatelessWidget {
  const PatientHomeSurface({
    super.key,
    required this.child,
    this.color = PatientDesign.paper,
  });
  final Widget child;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: PatientDesign.border.withValues(alpha: .6)),
      boxShadow: const [
        BoxShadow(
          color: PatientHomeStyle.shadow,
          blurRadius: 16,
          offset: Offset(0, 4),
        ),
      ],
    ),
    padding: const EdgeInsets.all(16),
    child: child,
  );
}

class PatientHomeWelcome extends StatelessWidget {
  const PatientHomeWelcome({
    super.key,
    required this.name,
    required this.onSearch,
    this.avatar,
    this.controller,
  });
  final String name;
  final ValueChanged<String> onSearch;
  final Widget? avatar;
  final TextEditingController? controller;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (avatar != null) ...[
        Row(
          children: [
            avatar!,
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Selamat datang,',
                    style: TextStyle(color: PatientDesign.muted, fontSize: 13),
                  ),
                  Text(
                    name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: PatientDesign.navy,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
      ],
      const Text(
        'Bagaimana kabar Anda hari ini?',
        style: TextStyle(
          fontSize: 20,
          height: 1.25,
          fontWeight: FontWeight.w600,
          color: PatientDesign.navy,
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: controller,
        onChanged: onSearch,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Cari dokter, poliklinik, atau layanan...',
          suffixIcon: controller != null && controller!.text.isNotEmpty
              ? IconButton(
                  tooltip: 'Bersihkan pencarian',
                  onPressed: () {
                    controller!.clear();
                    onSearch('');
                  },
                  icon: const Icon(Icons.close_rounded, size: 18),
                )
              : null,
          hintStyle: const TextStyle(fontSize: 12, color: PatientDesign.muted),
          prefixIcon: const Icon(
            Icons.search_rounded,
            color: PatientDesign.navy,
          ),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: PatientDesign.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: PatientDesign.border),
          ),
        ),
      ),
    ],
  );
}

/// Shared patient identity. Branding on other roles remains unchanged.
class PatientHomeIdentity extends StatelessWidget {
  const PatientHomeIdentity({
    super.key,
    required this.name,
    required this.avatar,
  });
  final String name;
  final Widget avatar;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      avatar,
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Selamat datang,',
              style: TextStyle(color: PatientDesign.muted, fontSize: 11),
            ),
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: PatientDesign.navy,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class PatientHomeBanner extends StatelessWidget {
  const PatientHomeBanner({super.key, required this.onRegister});
  final VoidCallback? onRegister;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(22),
      gradient: const LinearGradient(
        colors: [PatientHomeStyle.heroStart, PatientHomeStyle.heroEnd],
        begin: Alignment.bottomLeft,
        end: Alignment.topRight,
      ),
    ),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(18, 20, 8, 18),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Daftar antrean lebih cepat dari mana saja',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    height: 1.15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 9),
                const Text(
                  'Pilih poliklinik dan dokter, dapatkan nomor antrean secara online.',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 14),
                FilledButton(
                  onPressed: onRegister,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: PatientDesign.darkTeal,
                    minimumSize: const Size(0, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          'Ambil Antrean',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      SizedBox(width: 6),
                      Icon(Icons.arrow_forward_rounded, size: 17),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            flex: 2,
            child: ExcludeSemantics(
              child: Image.asset(
                'assets/illustrations/patient_ticket.webp',
                fit: BoxFit.contain,
                errorBuilder: (_, error, stack) => const Icon(
                  Icons.confirmation_number_rounded,
                  size: 64,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class PatientHomeShortcuts extends StatelessWidget {
  const PatientHomeShortcuts({
    super.key,
    required this.enabled,
    required this.onClinics,
    required this.onAppointment,
    required this.onTickets,
    required this.onHistory,
  });
  final bool enabled;
  final VoidCallback onClinics, onAppointment, onTickets, onHistory;
  @override
  Widget build(BuildContext context) => PatientHomeSurface(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Akses cepat',
          style: TextStyle(fontSize: 12, color: PatientDesign.muted),
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, box) {
            final columns = box.maxWidth < 270 ? 2 : 4;
            return Wrap(
              spacing: 8,
              runSpacing: 12,
              children: [
                for (final item
                    in <(String, IconData, Color, Color, VoidCallback)>[
                      (
                        'Poliklinik dan Dokter',
                        Icons.medical_services_outlined,
                        PatientDesign.darkTeal,
                        PatientHomeStyle.clinicSurface,
                        onClinics,
                      ),
                      (
                        'Janji Temu Dokter',
                        Icons.calendar_month_outlined,
                        PatientHomeStyle.appointmentInk,
                        PatientHomeStyle.appointmentSurface,
                        onAppointment,
                      ),
                      (
                        'Antrean Saya',
                        Icons.confirmation_number_outlined,
                        PatientHomeStyle.ticketInk,
                        PatientHomeStyle.ticketSurface,
                        onTickets,
                      ),
                      (
                        'Riwayat Kunjungan',
                        Icons.history_rounded,
                        PatientHomeStyle.historyInk,
                        PatientHomeStyle.historySurface,
                        onHistory,
                      ),
                    ])
                  SizedBox(
                    width: (box.maxWidth - (columns - 1) * 8) / columns,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: enabled ? item.$5 : null,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Column(
                            children: [
                              Container(
                                width: 52,
                                height: 50,
                                decoration: BoxDecoration(
                                  color: item.$4,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Icon(item.$2, color: item.$3, size: 27),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                item.$1,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 11,
                                  height: 1.35,
                                  fontWeight: FontWeight.w600,
                                  color: PatientDesign.navy,
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
      ],
    ),
  );
}

class PatientHomeSectionTitle extends StatelessWidget {
  const PatientHomeSectionTitle(
    this.title, {
    super.key,
    this.action,
    this.onPressed,
  });
  final String title;
  final String? action;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: PatientDesign.navy,
          ),
        ),
      ),
      if (action != null)
        TextButton(
          onPressed: onPressed,
          child: Text(action!, style: const TextStyle(fontSize: 12)),
        ),
    ],
  );
}

class PatientHomeVisit extends StatelessWidget {
  const PatientHomeVisit({
    super.key,
    required this.ticket,
    required this.doctor,
    required this.onTicket,
    required this.onQr,
    required this.config,
    this.appointment,
  });
  final Json ticket, doctor;
  final Json? appointment;
  final AppConfig config;
  final VoidCallback? onTicket;
  final VoidCallback? onQr;
  Json get room {
    final booked = object(
      object(object(appointment?['slotPraktik'])['jadwalPraktik'])['loket'],
    );
    return booked.isNotEmpty ? booked : object(ticket['loket']);
  }

  @override
  Widget build(BuildContext context) {
    final clinic = label(object(ticket['layanan']));
    final day = '${ticket['tanggalPelayanan'] ?? ticket['tanggalAntrean']}';
    final status = '${ticket['status'] ?? '—'}';
    final slot = object(appointment?['slotPraktik']);
    final when = Tooltip(
      message: config.serviceTimeZone,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${patientCompactDate(day)} ${DateTime.tryParse(dateOnly(day))?.year ?? ''}',
            style: const TextStyle(
              fontSize: 12,
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (slot['mulaiPada'] != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                patientTime(slot, config),
                style: const TextStyle(fontSize: 13, color: Colors.white),
              ),
            ),
          if (room.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                [
                  room['kode'],
                  room['nama'],
                ].whereType<String>().where((v) => v.isNotEmpty).join(' · '),
                style: const TextStyle(fontSize: 11, color: Colors.white),
              ),
            ),
        ],
      ),
    );
    final number = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Nomor antrean',
          style: TextStyle(fontSize: 11, color: Colors.white),
        ),
        const SizedBox(height: 3),
        Text(
          '${ticket['nomorAntrean'] ?? 'Nomor belum tersedia'}',
          style: const TextStyle(
            fontSize: 34,
            letterSpacing: -1,
            height: 1.1,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
      ],
    );
    return Container(
      key: const ValueKey('patient-nearest-visit'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: PatientDesign.hero,
        borderRadius: BorderRadius.circular(24),
      ),
      child: DefaultTextStyle.merge(
        style: const TextStyle(color: Colors.white, fontSize: 13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (doctor['id'] != null) ...[
                  ProfessionalDoctorAvatar(
                    config: config,
                    photo: doctor['fotoProfil'],
                    radius: 22,
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        doctor['nama'] != null
                            ? label(doctor)
                            : 'Kunjungan poliklinik',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        [
                          if (doctor['spesialisasi'] != null)
                            '${doctor['spesialisasi']}',
                          clinic,
                        ].join(' · '),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      status.replaceAll('_', ' '),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: PatientDesign.statusInk(status),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Divider(color: Color(0x44ffffff)),
            ),
            LayoutBuilder(
              builder: (context, box) =>
                  box.maxWidth >= 290 &&
                      MediaQuery.textScalerOf(context).scale(13) < 17
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(child: number),
                        const SizedBox(width: 12),
                        Expanded(child: when),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [number, const SizedBox(height: 10), when],
                    ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onTicket,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Color(0xffc9bccf)),
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    child: const Text(
                      'Lihat Detail',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onQr,
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: PatientDesign.hero,
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    icon: const Icon(Icons.qr_code_rounded, size: 18),
                    label: const Text(
                      'QR Code',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class PatientHomeEmpty extends StatelessWidget {
  const PatientHomeEmpty({
    super.key,
    required this.text,
    this.action,
    this.onPressed,
  });
  final String text;
  final String? action;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => PatientHomeSurface(
    child: Row(
      children: [
        const Icon(
          Icons.event_note_outlined,
          color: PatientDesign.teal,
          size: 27,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                text,
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: PatientDesign.muted,
                ),
              ),
              if (action != null)
                TextButton(
                  onPressed: onPressed,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    alignment: Alignment.centerLeft,
                  ),
                  child: Text(action!),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

class PatientHomeLoading extends StatelessWidget {
  const PatientHomeLoading({super.key});
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Memuat ringkasan pelayanan',
    child: ExcludeSemantics(
      child: PatientHomeSurface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 12,
              decoration: BoxDecoration(
                color: PatientDesign.border,
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            const SizedBox(height: 10),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: .6,
              child: Container(
                height: 12,
                decoration: BoxDecoration(
                  color: PatientDesign.border,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class HomeDoctorPreview {
  const HomeDoctorPreview(this.doctor, this.clinic, this.session);
  final Json doctor, clinic;
  final Json? session;
}

// Derive display-only data without mutating server lists or booking selections.
List<HomeDoctorPreview> homeDoctorPreviews(
  List<Json> doctors,
  List<Json> clinics,
  List<Json> sessions,
  AppConfig config,
  String search, {
  String? clinicId,
}) {
  final result = <HomeDoctorPreview>[];
  for (final doctor in doctors.where((d) => d['aktif'] != false)) {
    final doctorMatches = '${label(doctor)} ${doctor['spesialisasi'] ?? ''}'
        .toLowerCase()
        .contains(search);
    final links = rows(doctor['dokterLayanan']).where(
      (l) =>
          l['aktif'] == true &&
          (clinicId == null || l['layananId'] == clinicId) &&
          clinics.any(
            (c) =>
                c['id'] == l['layananId'] &&
                c['aktif'] != false &&
                (doctorMatches || label(c).toLowerCase().contains(search)),
          ),
    );
    if (links.isEmpty) continue;
    final upcoming =
        sessions.where((s) {
            final link = object(s['dokterLayanan']);
            return s['aktif'] != false &&
                object(s['loket'])['aktif'] != false &&
                link['aktif'] != false &&
                (link['dokterId'] ?? object(link['dokter'])['id']) ==
                    doctor['id'] &&
                links.any(
                  (l) =>
                      (l['id'] != null && l['id'] == s['dokterLayananId']) ||
                      l['layananId'] == link['layananId'] ||
                      l['layananId'] == object(link['layanan'])['id'],
                ) &&
                dateOnly(s['tanggal']).compareTo(config.today) >= 0 &&
                (DateTime.tryParse('${s['selesaiPada']}')
                        ?.isAfter(config.now) ??
                    false);
          }).toList()
          ..sort((a, b) => '${a['mulaiPada']}'.compareTo('${b['mulaiPada']}'));
    final session = upcoming.firstOrNull;
    final sl = object(session?['dokterLayanan']);
    final previewClinicId =
        sl['layananId'] ??
        object(sl['layanan'])['id'] ??
        links.first['layananId'];
    final clinic = clinics.where((c) => c['id'] == previewClinicId).firstOrNull;
    if (clinic == null) continue;
    if (!('${label(doctor)} ${doctor['spesialisasi'] ?? ''} ${label(clinic)}')
        .toLowerCase()
        .contains(search)) {
      continue;
    }
    result.add(HomeDoctorPreview(doctor, clinic, session));
  }
  result.sort((a, b) {
    if (a.session == null) {
      return b.session == null ? label(a.doctor).compareTo(label(b.doctor)) : 1;
    }
    if (b.session == null) return -1;
    return '${a.session!['mulaiPada']}'.compareTo('${b.session!['mulaiPada']}');
  });
  return result;
}

Json? nearestHomeTicket(
  List<Json> tickets,
  List<Json> appointments,
  String today,
) {
  final byId = <Object?, Json>{
    for (final a in appointments)
      if (object(a['tiket'])['id'] != null)
        object(a['tiket'])['id']: {
          ...object(a['tiket']),
          if (a['nomorAntrean'] != null) 'nomorAntrean': a['nomorAntrean'],
          if (a['tanggalPelayanan'] != null)
            'tanggalPelayanan': a['tanggalPelayanan'],
        },
    for (final t in tickets)
      if (t['id'] != null) t['id']: t,
  };
  final candidates = byId.values
      .where(
        (t) =>
            !['SELESAI', 'DIBATALKAN'].contains(t['status']) &&
            dateOnly(t['tanggalPelayanan'] ?? t['tanggalAntrean'])
                    .compareTo(today) >=
                0,
      )
      .toList();
  candidates.sort((a, b) {
    final day = dateOnly(a['tanggalPelayanan'] ?? a['tanggalAntrean'])
        .compareTo(dateOnly(b['tanggalPelayanan'] ?? b['tanggalAntrean']));
    if (day != 0) return day;
    // Display priority only; this never changes the server queue order.
    int status(Json t) => switch (t['status']) {
      'DILAYANI' => 0,
      'DIPANGGIL' => 1,
      'MENUNGGU' => 2,
      'CHECK_IN' => 3,
      'DILEWATI' => 4,
      _ => 5,
    };
    final state = status(a).compareTo(status(b));
    if (state != 0) return state;
    String start(Json ticket) =>
        '${object(appointments.where((a) => object(a['tiket'])['id'] == ticket['id']).firstOrNull?['slotPraktik'])['mulaiPada'] ?? ''}';
    final slot = start(a).compareTo(start(b));
    return slot != 0 ? slot : '${a['id']}'.compareTo('${b['id']}');
  });
  return candidates.firstOrNull;
}

class PatientHomeDoctor extends StatelessWidget {
  const PatientHomeDoctor({
    super.key,
    required this.preview,
    required this.config,
    required this.onTap,
    this.scheduleUnavailable = false,
  });
  final HomeDoctorPreview preview;
  final AppConfig config;
  final VoidCallback? onTap;
  final bool scheduleUnavailable;
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
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            ProfessionalDoctorAvatar(
              config: config,
              photo: preview.doctor['fotoProfil'],
              radius: 24,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label(preview.doctor),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: PatientDesign.navy,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${preview.doctor['spesialisasi'] ?? 'Spesialisasi belum dicantumkan'} · ${label(preview.clinic)}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: PatientDesign.muted,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    scheduleUnavailable
                        ? 'Jadwal belum dapat dimuat.'
                        : preview.session == null
                        ? 'Jadwal belum tersedia.'
                        : '${patientDate('${preview.session!['tanggal']}')}\n${patientTime(preview.session!, config)} · ${config.serviceTimeZone}',
                    style: const TextStyle(
                      fontSize: 11,
                      height: 1.4,
                      color: PatientDesign.darkTeal,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Detail Dokter',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: PatientDesign.darkTeal,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.chevron_right_rounded,
              color: PatientDesign.darkTeal,
              size: 20,
            ),
          ],
        ),
      ),
    ),
  );
}

class PatientHomeTip extends StatelessWidget {
  const PatientHomeTip({super.key});
  @override
  Widget build(BuildContext context) => PatientHomeSurface(
    color: PatientDesign.mint,
    child: const Row(
      children: [
        Icon(
          Icons.lightbulb_outline_rounded,
          color: PatientDesign.darkTeal,
          size: 30,
        ),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tips Cepat',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: PatientDesign.navy,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Datang sebelum jadwal pelayanan dan siapkan tiket QR Anda.',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: PatientDesign.muted,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
