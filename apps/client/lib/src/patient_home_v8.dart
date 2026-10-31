import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'api.dart';
import 'config.dart';
import 'features/patient/models/patient_queue_models.dart';
import 'mobile_ui.dart';
import 'patient_design.dart';
import 'patient_home_v7.dart';
import 'patient_reservations.dart' show reservationStatus;
import 'patient_ui.dart';
import 'queueb_interaction_motion.dart';
import 'queueb_value_motion.dart';
import 'user_profile.dart';

abstract final class PatientHomeV8Style {
  static const blue = PatientBottomNavigation.activeColor;
  static const background = Color(0xffedf5fc);
  static Color accent(PatientServiceCategory category) => switch (category) {
    PatientServiceCategory.registration => blue,
    PatientServiceCategory.pharmacy => const Color(0xff087c70),
    PatientServiceCategory.billing => const Color(0xffb95420),
    PatientServiceCategory.laboratory => const Color(0xffb55149),
    PatientServiceCategory.radiology => const Color(0xff7952b5),
    PatientServiceCategory.medicalRecords => const Color(0xff087f64),
    _ => PatientDesign.primary,
  };
}

/// Public service-hours catalog only. DB TIME is a wall clock, not an instant:
/// extracting HH:mm must not apply an Asia/Jakarta/browser offset a second time.
String patientServiceHours(
  List<Json> rows,
  String serviceId,
  String date, {
  bool available = true,
}) {
  if (!available) return 'Jam belum tersedia';
  final day = DateTime.tryParse(dateOnly(date));
  if (day == null) return 'Jam belum tersedia';
  const weekdays = [
    'SENIN',
    'SELASA',
    'RABU',
    'KAMIS',
    'JUMAT',
    'SABTU',
    'MINGGU',
  ];
  final times = <String>[];
  var hasMatchingSchedule = false;
  for (final row in rows) {
    if (row['aktif'] != true ||
        (row['layananId'] ?? object(row['layanan'])['id']) != serviceId ||
        row['hari'] != weekdays[day.weekday - 1]) {
      continue;
    }
    hasMatchingSchedule = true;
    final open = clockOnly(row['jamBuka']), close = clockOnly(row['jamTutup']);
    bool valid(String value) =>
        RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$').hasMatch(value);
    if (valid(open) && valid(close)) {
      times.add('${open.replaceAll(':', '.')}–${close.replaceAll(':', '.')}');
    }
  }
  return times.isEmpty
      ? hasMatchingSchedule
            ? 'Jam belum tersedia'
            : 'Tidak ada jadwal hari ini'
      : (times.toSet().toList()..sort()).join(', ');
}

/// A single physical paper contour is shared by shadow, clipping and border.
/// The cutouts are actual holes, including hit testing; no background circles.
class PatientTicketClipper extends CustomClipper<Path> {
  const PatientTicketClipper(this.stubWidth);
  final double stubWidth;
  static const notch = 7.0;
  @override
  Path getClip(Size size) {
    final paper = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(16)),
      );
    final cutouts = Path();
    for (final center in [
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      Offset(size.width - stubWidth, 0),
      Offset(size.width - stubWidth, size.height),
    ]) {
      cutouts.addOval(Rect.fromCircle(center: center, radius: notch));
    }
    return Path.combine(PathOperation.difference, paper, cutouts);
  }

  @override
  bool shouldReclip(covariant PatientTicketClipper oldClipper) =>
      stubWidth != oldClipper.stubWidth;
}

class _TicketPerforation extends CustomPainter {
  const _TicketPerforation(this.stubWidth, this.color, this.focused);
  final double stubWidth;
  final Color color;
  final bool focused;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: .28)
      ..strokeWidth = 1;
    final x = size.width - stubWidth;
    for (double y = 11; y < size.height - 11; y += 8) {
      canvas.drawLine(
        Offset(x, y),
        Offset(x, math.min(y + 4, size.height - 11)),
        paint,
      );
    }
    paint
      ..color = focused ? PatientHomeV8Style.blue : color.withValues(alpha: .12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = focused ? 2 : 1;
    canvas.drawPath(PatientTicketClipper(stubWidth).getClip(size), paint);
  }

  @override
  bool shouldRepaint(covariant _TicketPerforation oldDelegate) =>
      stubWidth != oldDelegate.stubWidth ||
      color != oldDelegate.color ||
      focused != oldDelegate.focused;
}

class PatientServiceTicketV8 extends StatefulWidget {
  const PatientServiceTicketV8({
    super.key,
    required this.clinic,
    this.ticket,
    this.queue,
    this.hours = 'Jam belum tersedia',
    this.onTap,
  });
  final Json clinic;
  final Json? ticket;
  final PatientQueueView? queue;
  final String hours;
  final VoidCallback? onTap;
  @override
  State<PatientServiceTicketV8> createState() => _PatientServiceTicketV8State();
}

class _PatientServiceTicketV8State extends State<PatientServiceTicketV8> {
  bool _focused = false;
  @override
  Widget build(BuildContext context) {
    final clinic = widget.clinic;
    final category = homeServiceCategory(clinic),
        accent = PatientHomeV8Style.accent(homeServiceCategory(clinic));
    final candidate = widget.queue ?? const PatientQueueView();
    final queue =
        candidate.summary == null ||
            candidate.summary!.serviceId == '${clinic['id']}'
        ? candidate
        : const PatientQueueView();
    final summary = queue.summary;
    final scope = (clinic['id'], summary?.date);
    final servingValue = summary?.serving
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
        : servingValue!;
    final number = '${widget.ticket?['nomorAntrean'] ?? ''}'.trim();
    final metadata = widget.hours == 'Jam belum tersedia'
        ? 'Jam & petugas belum tersedia'
        : '${widget.hours} · Petugas belum tersedia';
    final queueSemantics = summary == null
        ? 'Informasi antrean yang sedang dilayani belum tersedia. Total check-in hari ini dan jumlah menunggu belum tersedia.'
        : 'Sedang dilayani: $serving. Total check-in hari ini ${summary.checkedInTotal ?? 'belum tersedia'}. ${summary.waitingCount == null ? 'Jumlah menunggu belum tersedia' : '${summary.waitingCount} menunggu'}. ${queue.freshness}.';
    return Semantics(
      button: true,
      enabled: widget.onTap != null,
      onTap: widget.onTap,
      label:
          '${label(clinic)}. $metadata. ${number.isEmpty ? 'Belum ada tiket untuk hari ini' : 'Nomor Antreanmu $number'}. $queueSemantics Pilih layanan.',
      excludeSemantics: true,
      child: QueueBPressMotion(
        enabled: widget.onTap != null,
        builder: (highlight) => LayoutBuilder(
          builder: (context, bounds) {
            final stubWidth = (bounds.maxWidth * .23).clamp(76.0, 108.0);
            final largeText = MediaQuery.textScalerOf(context).scale(12) >= 18;
            Widget field(String title, Widget value) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.25,
                    color: title == 'Nomor Antreanmu'
                        ? accent
                        : PatientDesign.muted,
                  ),
                ),
                const SizedBox(height: 3),
                value,
              ],
            );
            final personal = field(
              'Nomor Antreanmu',
              Text(
                number.isEmpty ? '—' : number,
                key: ValueKey('patient-personal-ticket-${clinic['id']}'),
                style: TextStyle(
                  fontSize: 28,
                  height: 1.1,
                  letterSpacing: -.6,
                  fontWeight: FontWeight.w800,
                  color: accent,
                ),
              ),
            );
            final current = field(
              'Sedang dilayani',
              QueueBValueMotion(
                scope: scope,
                available: summary != null,
                value: servingValue,
                child: Text(
                  serving,
                  key: ValueKey('patient-serving-${clinic['id']}'),
                  style: TextStyle(
                    fontSize: summary?.serving.isNotEmpty == true ? 22 : 12,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                    color: PatientDesign.muted,
                  ),
                ),
              ),
            );
            return PhysicalShape(
              clipper: PatientTicketClipper(stubWidth),
              color: Colors.white,
              elevation: _focused ? 5 : 3,
              shadowColor: const Color(0x441c4266),
              clipBehavior: Clip.antiAlias,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: widget.onTap,
                  onHighlightChanged: highlight,
                  onFocusChange: (value) => setState(() => _focused = value),
                  focusColor: accent.withValues(alpha: .12),
                  child: CustomPaint(
                    foregroundPainter: _TicketPerforation(
                      stubWidth,
                      accent,
                      _focused,
                    ),
                    child: IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                14,
                                12,
                                14,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        width: 44,
                                        height: 44,
                                        decoration: BoxDecoration(
                                          color: accent.withValues(alpha: .12),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        child: Icon(
                                          PatientServiceAccent.icon(category),
                                          color: accent,
                                          size: 27,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              label(clinic),
                                              style: const TextStyle(
                                                fontSize: 16,
                                                height: 1.2,
                                                fontWeight: FontWeight.w800,
                                                color: PatientDesign.ink,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              metadata,
                                              style: const TextStyle(
                                                fontSize: 11.5,
                                                height: 1.3,
                                                color: PatientDesign.muted,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  if (largeText) ...[
                                    personal,
                                    const SizedBox(height: 10),
                                    current,
                                  ] else
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(child: personal),
                                        const SizedBox(width: 12),
                                        Expanded(child: current),
                                      ],
                                    ),
                                  if (!queue.live) ...[
                                    const SizedBox(height: 7),
                                    Text(
                                      queue.freshness,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: PatientDesign.muted,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          Container(
                            width: stubWidth,
                            padding: const EdgeInsets.fromLTRB(7, 14, 3, 14),
                            color: accent.withValues(alpha: .07),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Tooltip(
                                    message: 'Total check-in hari ini',
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.groups_rounded,
                                          color: accent.withValues(alpha: .75),
                                          size: 23,
                                        ),
                                        const SizedBox(height: 5),
                                        QueueBValueMotion(
                                          scope: scope,
                                          value: summary?.checkedInTotal,
                                          available:
                                              summary?.checkedInTotal != null,
                                          highlight: true,
                                          highlightColor: accent,
                                          child: Text(
                                            '${summary?.checkedInTotal ?? '—'}',
                                            key: ValueKey(
                                              'patient-queue-total-${clinic['id']}',
                                            ),
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              fontSize: 27,
                                              height: 1.1,
                                              fontWeight: FontWeight.w800,
                                              color: accent,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        const Text(
                                          'Antrean',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: PatientDesign.muted,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                Icon(
                                  Icons.chevron_right_rounded,
                                  size: 18,
                                  color: accent,
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
            );
          },
        ),
      ),
    );
  }
}

class PatientHomeAppBarV8 extends StatelessWidget
    implements PreferredSizeWidget {
  const PatientHomeAppBarV8({
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
      math.max(60, MediaQuery.textScalerOf(context).scale(18) * 2.4 + 12);
  @override
  Size get preferredSize => Size.fromHeight(height);
  @override
  Widget build(BuildContext context) => Material(
    color: PatientHomeV8Style.background,
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: ListenableBuilder(
            listenable: api,
            builder: (context, _) => Row(
              children: [
                Expanded(
                  child: Semantics(
                    container: true,
                    label: 'QueueB Hospital',
                    child: const ExcludeSemantics(
                      child: QueueBBrand(compact: true),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: 'Notifikasi',
                  onPressed: onNotifications,
                  icon: const Icon(
                    Icons.notifications_none_rounded,
                    color: PatientHomeV8Style.blue,
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
            ),
          ),
        ),
      ),
    ),
  );
}

class PatientHomeWelcomeV8 extends StatelessWidget {
  const PatientHomeWelcomeV8({
    super.key,
    required this.name,
    required this.now,
    required this.controller,
    required this.onSearch,
  });
  final String name;
  final DateTime now;
  final TextEditingController controller;
  final ValueChanged<String> onSearch;
  @override
  Widget build(BuildContext context) {
    final greeting = now.hour < 11
        ? 'Selamat pagi,'
        : now.hour < 15
        ? 'Selamat siang,'
        : now.hour < 18
        ? 'Selamat sore,'
        : 'Selamat malam,';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: ExcludeSemantics(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Opacity(
                      opacity: .24,
                      child: Image.asset(
                        'assets/illustrations/patient_hospital.png',
                        width: 230,
                        fit: BoxFit.contain,
                        cacheWidth: 640,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    greeting,
                    style: const TextStyle(
                      fontSize: 23,
                      height: 1.2,
                      fontWeight: FontWeight.w800,
                      color: PatientDesign.ink,
                    ),
                  ),
                  Text(
                    name.trim().isEmpty ? 'Pasien' : name,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 24,
                      height: 1.2,
                      fontWeight: FontWeight.w800,
                      color: PatientDesign.ink,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Semoga harimu sehat dan lancar',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: PatientDesign.muted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(17),
            boxShadow: const [
              BoxShadow(
                color: Color(0x07173b66),
                blurRadius: 10,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: TextField(
            controller: controller,
            onChanged: onSearch,
            decoration: InputDecoration(
              hintText: 'Cari layanan, poli, atau informasi...',
              prefixIcon: const Icon(
                Icons.search_rounded,
                color: PatientDesign.muted,
              ),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(17),
                borderSide: const BorderSide(color: PatientDesign.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(17),
                borderSide: const BorderSide(color: PatientDesign.border),
              ),
              suffixIcon: controller.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Bersihkan pencarian',
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        controller.clear();
                        onSearch('');
                      },
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

class PatientHomeVisitV8 extends StatelessWidget {
  const PatientHomeVisitV8({
    super.key,
    required this.config,
    this.ticket,
    this.appointment,
    this.onOpen,
    this.loading = false,
    this.unavailable = false,
  });
  final AppConfig config;
  final Json? ticket, appointment;
  final VoidCallback? onOpen;
  final bool loading, unavailable;
  @override
  Widget build(BuildContext context) {
    final slot = object(appointment?['slotPraktik']);
    final when = ticket == null
        ? loading
              ? 'Memuat kunjungan…'
              : unavailable
              ? 'Kunjungan belum dapat dimuat.'
              : 'Belum ada kunjungan mendatang.'
        : [
            patientDate(
              '${ticket!['tanggalPelayanan'] ?? ticket!['tanggalAntrean']}',
            ),
            if (slot['mulaiPada'] != null) patientTime(slot, config),
          ].join(' · ');
    final status = ticket == null
        ? null
        : reservationStatus('${ticket!['status']}');
    return Material(
      key: const ValueKey('patient-nearest-visit'),
      color: Colors.white.withValues(alpha: .88),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Colors.white),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(
          builder: (context, bounds) {
            final detail = TextButton(
              onPressed: onOpen,
              style: TextButton.styleFrom(
                foregroundColor: PatientHomeV8Style.blue,
                backgroundColor: const Color(0xffe5f0ff),
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(child: Text('Lihat Detail')),
                  Icon(Icons.chevron_right, size: 17),
                ],
              ),
            );
            final narrow =
                bounds.maxWidth < 280 ||
                MediaQuery.textScalerOf(context).scale(12) > 17;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xffe6f0ff),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.calendar_month_outlined,
                    color: PatientHomeV8Style.blue,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Kunjungan Terdekat',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: PatientDesign.ink,
                        ),
                      ),
                      if (ticket != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          label(object(ticket!['layanan'])),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: PatientDesign.ink,
                          ),
                        ),
                      ],
                      const SizedBox(height: 3),
                      Text(
                        when,
                        style: const TextStyle(
                          fontSize: 12,
                          height: 1.3,
                          color: PatientDesign.muted,
                        ),
                      ),
                      if (status != null && narrow) ...[
                        const SizedBox(height: 3),
                        Text(
                          status,
                          style: TextStyle(
                            fontSize: 11,
                            color: PatientDesign.statusInk(
                              '${ticket!['status']}',
                            ),
                          ),
                        ),
                      ],
                      if (ticket != null && narrow)
                        Padding(
                          padding: const EdgeInsets.only(top: 5),
                          child: detail,
                        ),
                    ],
                  ),
                ),
                if (ticket != null && !narrow) ...[
                  const SizedBox(width: 8),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      detail,
                      if (status != null)
                        Text(
                          status,
                          style: TextStyle(
                            fontSize: 11,
                            color: PatientDesign.statusInk(
                              '${ticket!['status']}',
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
