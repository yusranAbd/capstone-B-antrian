import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'config.dart';
import 'mobile_ui.dart';

// Hallmark · monitor QueueB · existing palette/type · focus on live information.
// Hallmark · pre-emit critique: P5 H5 E4 S5 R5 V4.
/// Renders only the allowlisted, privacy-filtered display snapshot.
class DisplayBoard extends StatelessWidget {
  const DisplayBoard({
    super.key,
    required this.snapshot,
    required this.now,
    required this.status,
    required this.onRefresh,
    required this.onAudio,
    required this.onConfigure,
    required this.onFullscreen,
    this.error,
    this.audioError,
    this.audio = false,
    this.audioBusy = false,
    this.fullscreen = false,
    this.fullscreenSupported = false,
    this.rejected = false,
    this.snapshotTime,
    this.clock,
  });
  final Json? snapshot;
  final DateTime now;
  final ValueListenable<DateTime>? clock;
  final String status;
  final String? error, audioError, snapshotTime;
  final bool audio, audioBusy, fullscreen, fullscreenSupported, rejected;
  final VoidCallback onRefresh, onAudio, onConfigure, onFullscreen;

  bool get live => status == 'Realtime terhubung';
  List<Json> get rooms => rows(snapshot?['loket']);

  static ({Json room, Json ticket})? currentCall(Json? snapshot) {
    final calls = <({Json room, Json ticket})>[
      for (final room in rows(snapshot?['loket']))
        for (final ticket in rows(room['tiketAktif']))
          if (ticket['status'] == 'DIPANGGIL') (room: room, ticket: ticket),
    ];
    final announcement = object(snapshot?['pengumumanTerakhir']);
    for (final call in calls) {
      if (call.room['kode'] == announcement['kodeLoket'] &&
          call.ticket['nomorAntrean'] == announcement['nomorAntrean']) {
        return call;
      }
    }
    calls.sort((a, b) {
      final left = DateTime.tryParse('${a.ticket['dipanggilPada']}');
      final right = DateTime.tryParse('${b.ticket['dipanggilPada']}');
      return (right?.millisecondsSinceEpoch ?? 0).compareTo(
        left?.millisecondsSinceEpoch ?? 0,
      );
    });
    return calls.firstOrNull;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      // Portrait is a scaled monitor preview; the monitor itself never scrolls.
      if (bounds.maxWidth < 900 || bounds.maxHeight < 500) {
        return ColoredBox(
          color: QueueBStyle.background,
          child: Center(
            child: FittedBox(
              fit: BoxFit.contain,
              child: SizedBox(
                width: 1280,
                height: 720,
                child: _monitor(context, const Size(1280, 720)),
              ),
            ),
          ),
        );
      }
      return _monitor(context, bounds.biggest);
    },
  );

  Widget _monitor(BuildContext context, Size size) {
    final large = size.height >= 950;
    final gap = large ? 20.0 : 12.0;
    return ColoredBox(
      color: QueueBStyle.background,
      child: Padding(
        padding: EdgeInsets.all(large ? 28 : 20),
        child: Column(
          children: [
            _header(large),
            SizedBox(height: gap),
            if (error != null || rejected) ...[
              _connection(),
              SizedBox(height: gap),
            ],
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(flex: 8, child: _hero(large)),
                  SizedBox(width: gap),
                  Expanded(flex: 5, child: _waiting(large)),
                ],
              ),
            ),
            SizedBox(height: gap),
            SizedBox(
              height: large ? 136 : 98,
              child: _RoomStrip(rooms: rooms),
            ),
            SizedBox(height: gap),
            _announcement(large),
            _controls(),
          ],
        ),
      ),
    );
  }

  Widget _header(bool large) => Row(
    children: [
      const SizedBox(width: 200, child: QueueBBrand()),
      Container(width: 1, height: 52, color: QueueBStyle.border),
      const SizedBox(width: 20),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${object(snapshot?['layanan'])['nama'] ?? 'Public Display'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: large ? 36 : 28,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  live && error == null ? Icons.sensors : Icons.sensors_off,
                  size: 16,
                  color: live && error == null
                      ? QueueBStyle.success
                      : QueueBStyle.warning,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    rejected ? 'Akses ditolak' : status,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: QueueBStyle.muted,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(width: 20),
      if (clock == null)
        _clock(now, large)
      else
        ValueListenableBuilder<DateTime>(
          valueListenable: clock!,
          builder: (_, value, _) => _clock(value, large),
        ),
    ],
  );

  Widget _clock(DateTime value, bool large) => Column(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Text(
        '${two(value.hour)}:${two(value.minute)}:${two(value.second)}',
        key: const ValueKey('display-clock'),
        style: TextStyle(
          fontSize: large ? 40 : 30,
          height: 1.1,
          fontWeight: FontWeight.w800,
        ),
      ),
      Text(
        _date(value),
        style: TextStyle(fontSize: large ? 18 : 14, color: QueueBStyle.muted),
      ),
    ],
  );

  Widget _connection() => Row(
    children: [
      const Icon(Icons.info_outline, size: 16, color: QueueBStyle.danger),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          rejected
              ? error ?? 'Akses display ditolak · periksa konfigurasi perangkat'
              : 'Snapshot belum tersinkron · menampilkan data terakhir',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: QueueBStyle.danger, fontSize: 14),
        ),
      ),
    ],
  );

  Widget _hero(bool large) {
    final call = currentCall(snapshot);
    final clinic = '${object(snapshot?['layanan'])['nama'] ?? ''}';
    return Container(
      key: const ValueKey('display-call-panel'),
      padding: EdgeInsets.all(large ? 32 : 22),
      decoration: BoxDecoration(
        color: QueueBStyle.navy,
        borderRadius: BorderRadius.circular(20),
      ),
      child: DefaultTextStyle.merge(
        style: const TextStyle(color: Colors.white, fontSize: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.campaign_outlined,
                  color: Colors.white,
                  size: 24,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    call == null ? 'INFORMASI PANGGILAN' : 'SEDANG DIPANGGIL',
                    style: TextStyle(
                      fontSize: large ? 22 : 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            if (call != null) ...[
              Expanded(
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '${call.ticket['nomorAntrean']}',
                      key: const ValueKey('display-call-number'),
                      style: TextStyle(
                        fontSize: large ? 270 : 190,
                        height: 1,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: -4,
                      ),
                    ),
                  ),
                ),
              ),
              if (call.ticket['namaPasien'] is String)
                Text(
                  '${call.ticket['namaPasien']}',
                  key: const ValueKey('display-call-name'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: large ? 42 : 30,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                clinic,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: large ? 28 : 22,
                  color: QueueBStyle.mint,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.meeting_room_outlined,
                      color: Colors.white,
                      size: 26,
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        '${call.room['nama']} · Loket ${call.room['kode']}',
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: large ? 30 : 24,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              const Spacer(),
              if (snapshot == null && !rejected && error == null)
                const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              const SizedBox(height: 16),
              Text(
                rejected
                    ? 'Akses display ditolak'
                    : snapshot == null
                    ? error == null
                          ? 'Memuat antrean…'
                          : 'Menunggu koneksi'
                    : 'Belum ada nomor dipanggil.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: large ? 44 : 32,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Perhatikan layar dan dengarkan panggilan petugas.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, color: QueueBStyle.mint),
              ),
              const Spacer(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _waiting(bool large) =>
      _PatientQueue(snapshot: snapshot, large: large);

  Widget _announcement(bool large) => Container(
    padding: EdgeInsets.symmetric(horizontal: 18, vertical: large ? 18 : 12),
    decoration: BoxDecoration(
      color: QueueBStyle.mint,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      children: [
        const Icon(
          Icons.volume_up_outlined,
          color: QueueBStyle.darkTeal,
          size: 26,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            '${object(snapshot?['pengumumanTerakhir'])['teks'] ?? 'Pengumuman panggilan akan tampil di sini.'}',
            key: const ValueKey('display-announcement'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: large ? 26 : 20,
              height: 1.2,
              fontWeight: FontWeight.w600,
              color: QueueBStyle.navy,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _controls() => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Row(
      children: [
        Expanded(
          child: Text(
            audioError ??
                (audio ? 'Audio aktif · Bahasa Indonesia' : 'Audio nonaktif'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: audioError == null
                  ? QueueBStyle.muted
                  : QueueBStyle.danger,
            ),
          ),
        ),
        if (!rejected) ...[
          TextButton.icon(
            onPressed: audioBusy ? null : onAudio,
            icon: Icon(audio ? Icons.volume_up : Icons.volume_off, size: 18),
            label: Text(audio ? 'Matikan suara' : 'Aktifkan suara'),
          ),
          TextButton.icon(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Muat ulang'),
          ),
        ],
        if (fullscreenSupported)
          TextButton.icon(
            onPressed: onFullscreen,
            icon: Icon(
              fullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
              size: 18,
            ),
            label: Text(fullscreen ? 'Keluar fullscreen' : 'Layar penuh'),
          ),
        TextButton.icon(
          onPressed: onConfigure,
          icon: const Icon(Icons.settings_outlined, size: 18),
          label: const Text('Ganti perangkat'),
        ),
      ],
    ),
  );
}

/// Read-only patient list. Paging includes skipped tickets without changing CALL order.
class _PatientQueue extends StatefulWidget {
  const _PatientQueue({required this.snapshot, required this.large});
  final Json? snapshot;
  final bool large;
  @override
  State<_PatientQueue> createState() => _PatientQueueState();
}

class _PatientQueueState extends State<_PatientQueue> {
  int page = 0, pagesAvailable = 1;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 12), (_) {
      if (mounted && pagesAvailable > 1) setState(() => page++);
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.snapshot;
    final large = widget.large;
    final patients = snapshot?['antrianPasien'] is List
        ? rows(snapshot?['antrianPasien'])
        : [
            for (final row in rows(snapshot?['menunggu']))
              {...row, 'status': 'MENUNGGU'},
          ];
    final total =
        (snapshot?['totalAntrianPasien'] ?? snapshot?['totalMenunggu']) as int?;
    return Container(
      key: const ValueKey('display-waiting-panel'),
      padding: EdgeInsets.all(large ? 24 : 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: QueueBStyle.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.groups_outlined,
                color: QueueBStyle.darkTeal,
                size: 28,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Antrian pasien',
                  style: TextStyle(
                    fontSize: large ? 28 : 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                '${total ?? '—'}',
                key: const ValueKey('display-waiting-count'),
                style: TextStyle(
                  fontSize: large ? 40 : 32,
                  fontWeight: FontWeight.w900,
                  color: QueueBStyle.darkTeal,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: QueueBStyle.background,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const SizedBox(
                  width: 100,
                  child: Text(
                    'NOMOR',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: QueueBStyle.muted,
                    ),
                  ),
                ),
                const Expanded(
                  child: Text(
                    'NAMA PASIEN',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: QueueBStyle.muted,
                    ),
                  ),
                ),
                SizedBox(
                  width: large ? 112 : 94,
                  child: const Text(
                    'STATUS',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: QueueBStyle.muted,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (_, bounds) {
                if (patients.isEmpty) {
                  pagesAvailable = 1;
                  return Center(
                    child: Text(
                      snapshot == null
                          ? 'Menunggu snapshot…'
                          : total == 0
                          ? 'Belum ada antrian pasien.'
                          : 'Daftar pasien belum tersedia.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: large ? 24 : 20,
                        color: QueueBStyle.muted,
                      ),
                    ),
                  );
                }
                final extent = large ? 62.0 : 45.0;
                final capacity = math.max(
                  1,
                  ((bounds.maxHeight - 28) / extent).floor(),
                );
                final pages = (patients.length / capacity).ceil();
                pagesAvailable = pages;
                final currentPage = page % pages;
                final shown = patients
                    .skip(currentPage * capacity)
                    .take(capacity);
                final remaining = math.max(
                  0,
                  (total ?? patients.length) - patients.length,
                );
                return Column(
                  children: [
                    for (final row in shown)
                      SizedBox(
                        height: extent,
                        child: DecoratedBox(
                          decoration: const BoxDecoration(
                            border: Border(
                              bottom: BorderSide(color: QueueBStyle.border),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 100,
                                  child: Text(
                                    '${row['nomorAntrean']}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: large ? 27 : 22,
                                      fontWeight: FontWeight.w800,
                                      color: QueueBStyle.darkTeal,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: Text(
                                      '${row['namaPasien'] ?? '—'}',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: large ? 24 : 18,
                                        height: 1.1,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  width: large ? 112 : 94,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: row['status'] == 'DILEWATI'
                                          ? const Color(0xFFFFF3DF)
                                          : QueueBStyle.mint,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      row['status'] == 'DILEWATI'
                                          ? 'Dilewati'
                                          : row['status'] == 'MENUNGGU'
                                          ? 'Menunggu'
                                          : '—',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: large ? 18 : 14,
                                        fontWeight: FontWeight.w600,
                                        color: row['status'] == 'DILEWATI'
                                            ? const Color(0xFF945800)
                                            : QueueBStyle.darkTeal,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    const Spacer(),
                    if (pages > 1 || remaining > 0)
                      SizedBox(
                        height: 28,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '${currentPage + 1}/$pages · ${total ?? patients.length} pasien'
                            '${remaining > 0 ? ' · +$remaining di luar batas snapshot' : ''}',
                            key: const ValueKey('display-more-waiting'),
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: QueueBStyle.muted,
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Fixed-height room cards, paged automatically without any scroll surface.
class _RoomStrip extends StatefulWidget {
  const _RoomStrip({required this.rooms});
  final List<Json> rooms;
  @override
  State<_RoomStrip> createState() => _RoomStripState();
}

class _RoomStripState extends State<_RoomStrip> {
  int page = 0, pagesAvailable = 1;
  Timer? timer;
  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 12), (_) {
      if (mounted && pagesAvailable > 1) setState(() => page++);
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (_, bounds) {
      final rooms = widget.rooms;
      if (rooms.isEmpty) {
        return Center(
          child: Text(
            'Belum ada ruang pelayanan aktif.',
            style: const TextStyle(color: QueueBStyle.muted, fontSize: 18),
          ),
        );
      }
      final capacity = (bounds.maxWidth / 204).floor().clamp(1, 8);
      final pages = (rooms.length / capacity).ceil();
      pagesAvailable = pages;
      final offset = (page % pages) * capacity;
      final shown = rooms.skip(offset).take(capacity).toList();
      return Row(
        children: [
          for (var n = 0; n < shown.length; n++) ...[
            if (n > 0) const SizedBox(width: 10),
            Expanded(child: _room(shown[n])),
          ],
          if (pages > 1)
            Padding(
              padding: const EdgeInsets.only(left: 10),
              child: Text(
                '${page % pages + 1}/$pages',
                style: const TextStyle(color: QueueBStyle.muted),
              ),
            ),
        ],
      );
    },
  );
  Widget _room(Json room) {
    final tickets = rows(room['tiketAktif']);
    final called = tickets.any((t) => t['status'] == 'DIPANGGIL');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: called ? QueueBStyle.mint : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: called ? QueueBStyle.teal : QueueBStyle.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${room['nama']}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  tickets.isEmpty
                      ? 'Siap melayani'
                      : tickets.map((t) => '${t['nomorAntrean']}').join(' · '),
                  style: TextStyle(
                    fontSize: tickets.isEmpty ? 17 : 30,
                    fontWeight: FontWeight.w800,
                    color: QueueBStyle.darkTeal,
                  ),
                ),
              ),
            ),
          ),
          Text(
            'Loket ${room['kode']} · ${tickets.isEmpty
                ? 'Tersedia'
                : called
                ? 'Dipanggil'
                : 'Sedang dilayani'}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, color: QueueBStyle.muted),
          ),
        ],
      ),
    );
  }
}

String _date(DateTime date) {
  const days = ['Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu'];
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
  return '${days[date.weekday - 1]}, ${date.day} ${months[date.month - 1]} ${date.year}';
}
