import 'package:flutter/material.dart';

import 'config.dart';
import 'mobile_ui.dart';
import 'doctor_professional.dart';
import 'staff_ui.dart';

// Hallmark · operational workbench · QueueB tokens · P5 H5 E4 S5 R5 V4.
class StaffToolbar extends StatelessWidget implements PreferredSizeWidget {
  const StaffToolbar({
    super.key,
    required this.selection,
    required this.avatar,
    required this.name,
    required this.onProfile,
    required this.onLogout,
  });
  final Widget selection, avatar;
  final String name;
  final VoidCallback onProfile, onLogout;
  @override
  Size get preferredSize => const Size.fromHeight(64);
  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 700;
    return AppBar(
      titleSpacing: wide ? 20 : 10,
      title: Row(
        children: [
          if (wide)
            const SizedBox(width: 225, child: QueueBBrand(compact: true))
          else
            const Tooltip(
              message: 'QueueB Hospital',
              child: Icon(
                Icons.local_hospital_rounded,
                color: QueueBStyle.darkTeal,
                size: 30,
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
        PopupMenuButton<String>(
          tooltip: 'Profil petugas',
          onSelected: (v) => v == 'profil' ? onProfile() : onLogout(),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'profil', child: Text('Profil akun')),
            PopupMenuItem(value: 'keluar', child: Text('Keluar akun')),
          ],
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: wide ? 18 : 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                avatar,
                if (wide) ...[
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 160,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Text(
                          'Petugas pelayanan',
                          style: TextStyle(
                            fontSize: 12,
                            color: QueueBStyle.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(width: 6),
                const Icon(Icons.expand_more, size: 18),
              ],
            ),
          ),
        ),
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
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(StaffStyle.radius),
      side: const BorderSide(color: QueueBStyle.border),
    ),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: schedules.isEmpty
          ? SizedBox(
              height: 60,
              child: Row(
                children: [
                  const Icon(
                    Icons.medical_services_outlined,
                    color: QueueBStyle.darkTeal,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      loading
                          ? 'Memuat dokter terjadwal…'
                          : failed
                          ? 'Jadwal belum dapat dimuat. Muat ulang antrean.'
                          : 'Tidak ada jadwal dokter untuk ruang dan tanggal ini.',
                      style: const TextStyle(
                        fontSize: 13,
                        color: QueueBStyle.muted,
                      ),
                    ),
                  ),
                ],
              ),
            )
          : SizedBox(
              height: schedules.length > 1
                  ? 160
                  : MediaQuery.sizeOf(context).width < 700
                  ? 116
                  : 76,
              child: ListView.separated(
                primary: false,
                itemCount: schedules.length,
                separatorBuilder: (_, i) => const Divider(height: 12),
                itemBuilder: (context, i) {
                  final s = schedules[i],
                      doctor = object(object(s['dokterLayanan'])['dokter']);
                  return LayoutBuilder(
                    builder: (context, box) {
                      final horizontal = box.maxWidth >= 600;
                      final identity = Row(
                        children: [
                          ProfessionalDoctorAvatar(
                            config: config,
                            photo: doctor['fotoProfil'],
                            radius: 26,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Dokter terjadwal',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: QueueBStyle.muted,
                                  ),
                                ),
                                Text(
                                  label(doctor),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
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
                                    fontSize: 12,
                                    color: QueueBStyle.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                      final time = Text(
                        '${dateOnly(s['tanggal'])}\n${config.instantLabel(s['mulaiPada']).split(' ').last} – ${config.instantLabel(s['selesaiPada']).split(' ').last} · ${config.serviceTimeZone}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: QueueBStyle.muted,
                        ),
                      );
                      return horizontal
                          ? Row(
                              children: [
                                Expanded(child: identity),
                                const SizedBox(width: 12),
                                const Icon(
                                  Icons.calendar_month_outlined,
                                  color: QueueBStyle.darkTeal,
                                ),
                                const SizedBox(width: 10),
                                SizedBox(width: 190, child: time),
                              ],
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [identity, time],
                            );
                    },
                  );
                },
              ),
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
                  fontSize: 12,
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
            fontSize: 15,
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
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
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
        return Column(
          children: [
            if (table)
              Container(
                height: 34,
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
                          padding: const EdgeInsets.symmetric(vertical: 8),
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
                                          fontSize: 12,
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
                                        fontSize: 12,
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
                  onPressed: page > 0 ? () => setState(() => page--) : null,
                  icon: const Icon(Icons.chevron_left),
                ),
                IconButton(
                  tooltip: 'Halaman antrean berikutnya',
                  onPressed: page < last ? () => setState(() => page++) : null,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
