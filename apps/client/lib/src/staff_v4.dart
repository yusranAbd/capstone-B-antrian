import 'package:flutter/material.dart';

import 'config.dart';
import 'mobile_ui.dart';
import 'doctor_professional.dart';
import 'staff_ui.dart';

class StaffToolbar extends StatelessWidget implements PreferredSizeWidget {
  const StaffToolbar({
    super.key,
    required this.selection,
    required this.avatar,
    required this.name,
    required this.onProfile,
  });
  final Widget selection, avatar;
  final String name;
  final VoidCallback onProfile;
  @override
  Size get preferredSize => const Size.fromHeight(56);
  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return AppBar(
      toolbarHeight: preferredSize.height,
      titleSpacing: wide ? 20 : 10,
      title: Row(
        children: [
          if (wide)
            const SizedBox(width: 205, child: QueueBBrand(compact: true))
          else
            const Tooltip(
              message: 'QueueB Hospital',
              child: Icon(
                Icons.local_hospital_rounded,
                color: QueueBStyle.darkTeal,
                size: 28,
              ),
            ),
          SizedBox(width: wide ? 16 : 8),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 430),
                child: selection,
              ),
            ),
          ),
        ],
      ),
      actions: [
        Tooltip(
          message: 'Profil petugas',
          child: TextButton(
            onPressed: onProfile,
            style: TextButton.styleFrom(
              foregroundColor: QueueBStyle.navy,
              padding: EdgeInsets.symmetric(horizontal: wide ? 12 : 8),
              minimumSize: const Size(44, 44),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                avatar,
                if (wide) ...[
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 142,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Text(
                          'Petugas pelayanan',
                          style: TextStyle(
                            fontSize: 11,
                            color: QueueBStyle.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        SizedBox(width: wide ? 8 : 2),
      ],
    );
  }
}

class StaffScheduledDoctors extends StatelessWidget {
  const StaffScheduledDoctors({
    super.key,
    required this.config,
    required this.schedules,
    required this.clinic,
    this.loading = false,
    this.failed = false,
  });
  final AppConfig config;
  final List<Json> schedules;
  final String clinic;
  final bool loading, failed;
  @override
  Widget build(BuildContext context) => Material(
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(StaffStyle.radius),
      side: const BorderSide(color: QueueBStyle.border),
    ),
    color: Colors.white,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: schedules.isEmpty
          ? SizedBox(
              height: 40,
              child: Row(
                children: [
                  const Icon(
                    Icons.medical_services_outlined,
                    color: QueueBStyle.darkTeal,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      loading
                          ? 'Memuat dokter terjadwal…'
                          : failed
                          ? 'Jadwal belum dapat dimuat. Muat ulang antrean.'
                          : 'Tidak ada jadwal dokter untuk ruang dan tanggal ini.',
                      style: const TextStyle(
                        fontSize: 12,
                        color: QueueBStyle.muted,
                      ),
                    ),
                  ),
                ],
              ),
            )
          : LayoutBuilder(
              builder: (context, box) {
                final columns = box.maxWidth >= 1000 && schedules.length > 1
                    ? 2
                    : 1;
                final horizontal =
                    (box.maxWidth - (columns - 1) * 16) / columns >= 540;
                final scale = MediaQuery.textScalerOf(context).scale(12) / 12;
                final rowHeight = (horizontal ? 74.0 : 116.0) * scale;
                final visibleRows =
                    ((schedules.length + columns - 1) ~/ columns).clamp(1, 2);
                return SizedBox(
                  height: visibleRows * rowHeight + (visibleRows - 1) * 8,
                  child: GridView.builder(
                    primary: false,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      mainAxisExtent: rowHeight,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 8,
                    ),
                    itemCount: schedules.length,
                    itemBuilder: (context, i) {
                      final s = schedules[i],
                          doctor = object(object(s['dokterLayanan'])['dokter']);
                      final identity = Row(
                        children: [
                          ProfessionalDoctorAvatar(
                            config: config,
                            photo: doctor['fotoProfil'],
                            radius: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Dokter terjadwal',
                                  style: TextStyle(
                                    fontSize: 11,
                                    height: 1.2,
                                    color: QueueBStyle.muted,
                                  ),
                                ),
                                Text(
                                  label(doctor),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    height: 1.2,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  [
                                    if (doctor['spesialisasi'] != null)
                                      '${doctor['spesialisasi']}',
                                    clinic,
                                  ].join(' · '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    height: 1.2,
                                    color: QueueBStyle.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                      final time = Row(
                        children: [
                          const Icon(
                            Icons.calendar_month_outlined,
                            color: QueueBStyle.darkTeal,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${dateOnly(s['tanggal'])}\n${config.instantLabel(s['mulaiPada']).split(' ').last} – ${config.instantLabel(s['selesaiPada']).split(' ').last} · ${config.serviceTimeZone}',
                              style: const TextStyle(
                                fontSize: 11,
                                height: 1.2,
                                color: QueueBStyle.muted,
                              ),
                            ),
                          ),
                        ],
                      );
                      return horizontal
                          ? Row(
                              children: [
                                Expanded(child: identity),
                                const SizedBox(width: 12),
                                SizedBox(width: 175, child: time),
                              ],
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                identity,
                                const SizedBox(height: 6),
                                time,
                              ],
                            );
                    },
                  ),
                );
              },
            ),
    ),
  );
}

class StaffPatientList extends StatefulWidget {
  const StaffPatientList({
    super.key,
    required this.rows,
    required this.config,
    required this.busy,
    required this.onAction,
  });
  final List<Json> rows;
  final AppConfig config;
  final bool busy;
  final void Function(Json row, String action) onAction;
  @override
  State<StaffPatientList> createState() => _StaffPatientListState();
}

class _StaffPatientListState extends State<StaffPatientList> {
  int page = 0;
  static const size = 5;
  @override
  Widget build(BuildContext context) {
    final total = widget.rows.length;
    final last = total == 0 ? 0 : (total - 1) ~/ size;
    if (page > last) page = last;
    final start = page * size;
    final shown = widget.rows.skip(start).take(size).toList();
    return LayoutBuilder(
      builder: (context, box) {
        final table = box.maxWidth >= 630;
        Widget cell(Widget child, int flex) => Expanded(
          flex: flex,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: child,
          ),
        );
        Widget status(Json t) {
          final state = t['status'];
          final waiting = state == 'MENUNGGU';
          return Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: waiting
                    ? const Color(0xfffff2d3)
                    : state == 'CHECK_IN'
                    ? const Color(0xffe5f2ff)
                    : const Color(0xffedf1f7),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                waiting
                    ? 'Menunggu'
                    : state == 'CHECK_IN'
                    ? 'Check-in'
                    : 'Dilewati',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: waiting ? QueueBStyle.warning : QueueBStyle.navy,
                ),
              ),
            ),
          );
        }

        Widget menu(Json t) => SizedBox(
          width: 36,
          height: table ? 32 : 44,
          child: PopupMenuButton<String>(
            padding: EdgeInsets.zero,
            tooltip: 'Aksi ${t['nomorAntrean']}',
            enabled: !widget.busy,
            onSelected: (a) => widget.onAction(t, a),
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'detail', child: Text('Detail tiket')),
              if (t['status'] == 'DILEWATI' && t['bisaAntreUlang'] == true)
                const PopupMenuItem(
                  value: 'antre-ulang',
                  child: Text('Kembalikan ke Antrean'),
                ),
              if (t['status'] == 'CHECK_IN' && t['bisaMasukAntrean'] == true)
                const PopupMenuItem(
                  value: 'masuk',
                  child: Text('Masuk Antrean'),
                ),
            ],
            icon: const Icon(Icons.more_horiz, size: 22),
          ),
        );
        Widget number(Json t) => Text(
          '${t['nomorAntrean']}',
          style: const TextStyle(
            color: QueueBStyle.darkTeal,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        );
        Widget name(Json t) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${t['namaPasien'] ?? 'Nama belum tersedia'}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
            ),
            if (t['layakDipanggil'] == false)
              Text(
                '${t['alasanTidakLayak'] ?? 'Belum layak dipanggil'}'
                    .replaceAll('_', ' '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10,
                  color: QueueBStyle.warning,
                ),
              ),
          ],
        );
        final content = Column(
          children: [
            if (table)
              Container(
                height: 30,
                color: QueueBStyle.background,
                child: Row(
                  children: [
                    cell(const Text('#'), 5),
                    cell(const Text('No. Antrean'), 17),
                    cell(const Text('Nama Pasien'), 29),
                    cell(const Text('Status'), 19),
                    cell(const Text('Waktu Check-in'), 23),
                    cell(const Text('Aksi'), 7),
                  ],
                ),
              ),
            Expanded(
              child: shown.isEmpty
                  ? const StaffEmpty('Belum ada antrean yang sesuai.')
                  : ListView.separated(
                      primary: false,
                      itemCount: shown.length,
                      separatorBuilder: (_, i) =>
                          const Divider(height: 1, color: QueueBStyle.border),
                      itemBuilder: (context, i) {
                        final t = shown[i];
                        final time = widget.config.instantLabel(
                          t['checkInPada'],
                        );
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: table
                              ? Row(
                                  children: [
                                    cell(Text('${start + i + 1}'), 5),
                                    cell(number(t), 17),
                                    cell(name(t), 29),
                                    cell(status(t), 19),
                                    cell(
                                      Text(
                                        time,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: QueueBStyle.muted,
                                        ),
                                      ),
                                      23,
                                    ),
                                    cell(menu(t), 7),
                                  ],
                                )
                              : Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        number(t),
                                        const SizedBox(width: 10),
                                        Expanded(child: status(t)),
                                        menu(t),
                                      ],
                                    ),
                                    name(t),
                                    Text(
                                      'Check-in: $time',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: QueueBStyle.muted,
                                      ),
                                    ),
                                  ],
                                ),
                        );
                      },
                    ),
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '$total tiket · halaman ${page + 1}/${last + 1}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: QueueBStyle.muted,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Halaman antrean sebelumnya',
                  constraints: const BoxConstraints.tightFor(
                    width: 36,
                    height: 36,
                  ),
                  padding: EdgeInsets.zero,
                  onPressed: page > 0 ? () => setState(() => page--) : null,
                  icon: const Icon(Icons.chevron_left),
                ),
                IconButton(
                  tooltip: 'Halaman antrean berikutnya',
                  constraints: const BoxConstraints.tightFor(
                    width: 36,
                    height: 36,
                  ),
                  padding: EdgeInsets.zero,
                  onPressed: page < last ? () => setState(() => page++) : null,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ],
        );
        final minimum = MediaQuery.textScalerOf(context)
            .scale(table ? 140 : 160);
        return box.hasBoundedHeight && box.maxHeight < minimum
            ? SingleChildScrollView(
                child: SizedBox(height: minimum, child: content),
              )
            : content;
      },
    );
  }
}
