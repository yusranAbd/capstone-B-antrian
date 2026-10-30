import 'package:flutter/material.dart';

import 'api.dart';
import 'config.dart';
import 'patient_design.dart';
import 'user_profile.dart';
import 'features/patient/models/patient_queue_models.dart';

enum PatientServiceCategory {
  registration,
  pharmacy,
  laboratory,
  radiology,
  billing,
  medicalRecords,
  general,
  dental,
  other,
}

/// Presentation order for supported auxiliary service codes, never catalog data.
const patientDailyServiceOrder = [
  'PENDAFTARAN',
  'APOTEK',
  'LABORATORIUM',
  'RADIOLOGI',
  'KASIR',
  'REKAM_MEDIS',
];

PatientServiceCategory homeServiceCategory(
  Json clinic,
) => switch ('${clinic['kode'] ?? ''}'.trim().toUpperCase()) {
  'PENDAFTARAN' ||
  'REGISTRASI' ||
  'ADMINISTRASI' => PatientServiceCategory.registration,
  'APOTEK' || 'APOTIK' => PatientServiceCategory.pharmacy,
  'LABORATORIUM' => PatientServiceCategory.laboratory,
  'RADIOLOGI' => PatientServiceCategory.radiology,
  'KASIR' => PatientServiceCategory.billing,
  'REKAM_MEDIS' => PatientServiceCategory.medicalRecords,
  'UMUM' || 'POLI_UMUM' || 'POLIKLINIK_UMUM' => PatientServiceCategory.general,
  'GIGI' || 'POLI_GIGI' || 'POLIKLINIK_GIGI' => PatientServiceCategory.dental,
  _ => PatientServiceCategory.other,
};

/// Home priorities only; the remaining catalog rows keep their relative order.
List<Json> registrationFirst(List<Json> services) {
  final priorities = <int>{};
  for (final code in patientDailyServiceOrder) {
    var index = services.indexWhere(
      (c) => '${c['kode']}'.trim().toUpperCase() == code,
    );
    if (index < 0 && (code == 'PENDAFTARAN' || code == 'APOTEK')) {
      final category = code == 'PENDAFTARAN'
          ? PatientServiceCategory.registration
          : PatientServiceCategory.pharmacy;
      index = services.indexWhere((c) => homeServiceCategory(c) == category);
    }
    if (index >= 0) priorities.add(index);
  }
  return [
    for (final index in priorities) services[index],
    for (var i = 0; i < services.length; i++)
      if (!priorities.contains(i)) services[i],
  ];
}

/// Only pass the existing authenticated /tiket/saya projection, never queue rows.
Json? homeServiceTicket(
  List<Json> ownTickets,
  String serviceId,
  String day,
  String? userId,
) {
  if (userId == null || userId.isEmpty) return null;
  return ownTickets
      .where(
        (ticket) =>
            '${ticket['id'] ?? ''}'.trim().isNotEmpty &&
            (ticket['layananId'] ?? object(ticket['layanan'])['id']) ==
                serviceId &&
            (ticket['penggunaId'] == null || ticket['penggunaId'] == userId) &&
            dateOnly(ticket['tanggalPelayanan'] ?? ticket['tanggalAntrean']) ==
                day &&
            const {
              'DIPESAN',
              'CHECK_IN',
              'MENUNGGU',
              'DIPANGGIL',
              'DILAYANI',
              'DILEWATI',
            }.contains(ticket['status']) &&
            '${ticket['nomorAntrean'] ?? ''}'.trim().isNotEmpty,
      )
      .firstOrNull;
}

abstract final class PatientServiceAccent {
  static Color color(PatientServiceCategory category) => switch (category) {
    PatientServiceCategory.registration ||
    PatientServiceCategory.medicalRecords => const Color(0xff10b981),
    PatientServiceCategory.pharmacy ||
    PatientServiceCategory.radiology => const Color(0xff3b82f6),
    PatientServiceCategory.general ||
    PatientServiceCategory.laboratory => const Color(0xff8b5cf6),
    PatientServiceCategory.dental ||
    PatientServiceCategory.billing => const Color(0xfff59e0b),
    PatientServiceCategory.other => PatientDesign.primary,
  };
  static Color ink(PatientServiceCategory category) => switch (category) {
    PatientServiceCategory.registration ||
    PatientServiceCategory.medicalRecords => const Color(0xff047857),
    PatientServiceCategory.pharmacy ||
    PatientServiceCategory.radiology => const Color(0xff1d4ed8),
    PatientServiceCategory.general ||
    PatientServiceCategory.laboratory => const Color(0xff6d28d9),
    PatientServiceCategory.dental ||
    PatientServiceCategory.billing => const Color(0xff92400e),
    PatientServiceCategory.other => PatientDesign.primary,
  };
  static IconData icon(PatientServiceCategory category) => switch (category) {
    PatientServiceCategory.registration => Icons.assignment_outlined,
    PatientServiceCategory.pharmacy => Icons.medication_outlined,
    PatientServiceCategory.laboratory => Icons.science_outlined,
    PatientServiceCategory.radiology => Icons.image_outlined,
    PatientServiceCategory.billing => Icons.payments_outlined,
    PatientServiceCategory.medicalRecords => Icons.medical_information_outlined,
    PatientServiceCategory.general => Icons.medical_services_outlined,
    PatientServiceCategory.dental => Icons.health_and_safety_outlined,
    PatientServiceCategory.other => Icons.local_hospital_outlined,
  };
  static String subtitle(PatientServiceCategory category) => switch (category) {
    PatientServiceCategory.registration => 'Layanan Administrasi',
    PatientServiceCategory.pharmacy => 'Layanan Farmasi',
    PatientServiceCategory.laboratory => 'Layanan Laboratorium',
    PatientServiceCategory.radiology => 'Layanan Radiologi',
    PatientServiceCategory.billing => 'Layanan Pembayaran',
    PatientServiceCategory.medicalRecords => 'Layanan Rekam Medis',
    PatientServiceCategory.general => 'Layanan Pemeriksaan',
    PatientServiceCategory.dental => 'Layanan Kesehatan Gigi',
    PatientServiceCategory.other => 'Layanan antrean harian',
  };
}

class PatientServiceCardV7 extends StatefulWidget {
  const PatientServiceCardV7({
    super.key,
    required this.clinic,
    this.ticket,
    this.queue,
    this.onTap,
  });
  final Json clinic;
  final Json? ticket;
  final PatientQueueView? queue;
  final VoidCallback? onTap;

  @override
  State<PatientServiceCardV7> createState() => _PatientServiceCardV7State();
}

class _PatientServiceCardV7State extends State<PatientServiceCardV7> {
  bool _focused = false;
  Json get clinic => widget.clinic;
  Json? get ticket => widget.ticket;
  VoidCallback? get onTap => widget.onTap;

  @override
  Widget build(BuildContext context) {
    final category = homeServiceCategory(clinic);
    final accent = PatientServiceAccent.color(category),
        ink = PatientServiceAccent.ink(category);
    final description = '${clinic['deskripsi'] ?? ''}'.trim();
    final number = '${ticket?['nomorAntrean'] ?? ''}'.trim();
    final hasTicket = number.isNotEmpty;
    final subtitle = description.isEmpty
        ? PatientServiceAccent.subtitle(category)
        : description;
    final radius = BorderRadius.circular(20);
    final candidate = widget.queue ?? const PatientQueueView();
    final queue =
        candidate.summary == null ||
            candidate.summary!.serviceId == '${clinic['id']}'
        ? candidate
        : const PatientQueueView();
    final summary = queue.summary;
    final servingNumbers = summary?.serving
        .map(
          (s) => summary.serving.length > 1
              ? '${s.roomCode}: ${s.number}'
              : s.number,
        )
        .join('\n');
    final serving = summary == null
        ? 'Belum tersedia'
        : summary.serving.isEmpty
        ? 'Belum ada pelayanan aktif'
        : servingNumbers!;
    final queueSemantics = summary == null
        ? 'Informasi antrean yang sedang dilayani belum tersedia. Total check-in hari ini dan jumlah menunggu belum tersedia.'
        : 'Sedang dilayani: $serving. Total check-in hari ini ${summary.checkedInTotal ?? 'belum tersedia'}. ${summary.waitingCount == null ? 'Jumlah menunggu belum tersedia' : '${summary.waitingCount} menunggu'}. ${queue.freshness}.';
    return Semantics(
      button: true,
      enabled: onTap != null,
      onTap: onTap,
      label:
          '${label(clinic)}. $subtitle. ${hasTicket ? 'Nomor Antreanmu $number' : 'Belum ada tiket untuk hari ini'}. $queueSemantics Pilih layanan.',
      excludeSemantics: true,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: const [
            BoxShadow(
              color: Color(0x080f2a43),
              blurRadius: 10,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Material(
          color: PatientDesign.paper,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: BorderSide(
              color: _focused ? ink : PatientDesign.border,
              width: _focused ? 2 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            onFocusChange: (focused) => setState(() => _focused = focused),
            borderRadius: radius,
            focusColor: accent.withValues(alpha: .18),
            splashColor: accent.withValues(alpha: .12),
            hoverColor: accent.withValues(alpha: .05),
            child: Stack(
              children: [
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(painter: _ServiceGeometry(accent)),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: .13),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              PatientServiceAccent.icon(category),
                              color: ink,
                              size: 27,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  label(clinic),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: PatientDesign.ink,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  subtitle,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    height: 1.3,
                                    color: PatientDesign.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: ink,
                            size: 24,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Color.alphaBlend(
                            accent.withValues(alpha: .06),
                            Colors.white,
                          ),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 3,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Nomor Antreanmu',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: PatientDesign.muted,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Tooltip(
                                    message: hasTicket ? number : 'Belum ada tiket milik Anda untuk layanan hari ini.',
                                    child: Text(
                                      hasTicket ? number : '—',
                                      softWrap: true,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 23,
                                        fontWeight: FontWeight.w800,
                                        color: ink,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: accent.withValues(alpha: .09),
                                      borderRadius: BorderRadius.circular(9),
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 1,
                                          ),
                                          child: Icon(
                                            Icons.support_agent_rounded,
                                            size: 14,
                                            color: ink,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            'Sedang dilayani\n$serving',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              height: 1.3,
                                              color: PatientDesign.ink,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    hasTicket
                                        ? 'Data tiket'
                                        : 'Belum ada tiket',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: PatientDesign.muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              width: 1,
                              height: MediaQuery.textScalerOf(context)
                                  .scale(112),
                              margin: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                              color: accent.withValues(alpha: .2),
                            ),
                            Expanded(
                              flex: 2,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Total hari ini',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: PatientDesign.muted,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${summary?.checkedInTotal ?? '—'}',
                                    key: ValueKey(
                                      'patient-queue-total-${clinic['id']}',
                                    ),
                                    style: const TextStyle(
                                      fontSize: 23,
                                      fontWeight: FontWeight.w700,
                                      color: PatientDesign.ink,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    summary?.waitingCount == null
                                        ? 'Belum tersedia'
                                        : '${summary!.waitingCount} menunggu',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: PatientDesign.muted,
                                    ),
                                  ),
                                  if (widget.queue != null) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      queue.freshness,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: queue.live
                                            ? PatientDesign.success
                                            : PatientDesign.muted,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
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
}

class _ServiceGeometry extends CustomPainter {
  const _ServiceGeometry(this.accent);
  final Color accent;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = accent.withValues(alpha: .055);
    canvas.save();
    canvas.translate(size.width - 30, size.height * .38);
    canvas.rotate(.55);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-30, -40, 29, 100),
        const Radius.circular(18),
      ),
      paint,
    );
    canvas.drawCircle(const Offset(15, 25), 24, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ServiceGeometry oldDelegate) =>
      accent != oldDelegate.accent;
}

class PatientHomeAppBarV7 extends StatelessWidget
    implements PreferredSizeWidget {
  const PatientHomeAppBarV7({
    super.key,
    required this.api,
    required this.height,
    required this.onProfile,
    required this.onNotifications,
  });
  final QueueApi api;
  final double height;
  final VoidCallback onProfile, onNotifications;
  static double heightFor(BuildContext context) =>
      (MediaQuery.textScalerOf(context).scale(30) * 1.2 + 18).clamp(
        66,
        double.infinity,
      );
  @override
  Size get preferredSize => Size.fromHeight(height);
  @override
  Widget build(BuildContext context) => Material(
    color: PatientDesign.background,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ListenableBuilder(
        listenable: api,
        builder: (context, _) {
          final name = '${api.user?['nama'] ?? ''}'.trim();
          return Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Selamat datang,',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.2,
                        color: PatientDesign.muted,
                      ),
                    ),
                    Text(
                      name.isEmpty ? 'Pasien' : name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 17,
                        height: 1.2,
                        fontWeight: FontWeight.w700,
                        color: PatientDesign.ink,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Notifikasi',
                onPressed: onNotifications,
                icon: const Icon(
                  Icons.notifications_none_rounded,
                  color: PatientDesign.primary,
                ),
              ),
              IconButton(
                tooltip: 'Profil pasien',
                onPressed: onProfile,
                icon: ExcludeSemantics(
                  child: AccountAvatar(api: api, radius: 18),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}
