import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'config.dart';
import 'mobile_ui.dart';

// Hallmark · Public Display · Stat-Led · QueueB existing tokens · no decoration.
// Hallmark · pre-emit critique: P5 H5 E4 S5 R5 V4.
/// Only fields from the public snapshot are rendered. No patient/master API.
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

  /// The audit announcement identifies RECALL's room; otherwise use the latest
  /// persisted CALL time. A serving/completed ticket never becomes a new call.
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
    builder: (context, constraints) {
      // A fixed 16:9 logical canvas keeps TV type and spacing proportional at
      // 720p/1080p. Portrait setup/preview uses readable scrolling instead.
      if (constraints.maxWidth < 900 || constraints.maxHeight < 500) {
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _header(compact: true),
            const SizedBox(height: 16),
            _connection(),
            SizedBox(height: 430, child: _hero()),
            const SizedBox(height: 16),
            _waiting(),
            const SizedBox(height: 16),
            _rooms(shrinkWrap: true),
            const SizedBox(height: 16),
            _announcement(),
            _controls(),
          ],
        );
      }
      return ColoredBox(
        color: QueueBStyle.background,
        child: Center(
          child: FittedBox(
            fit: BoxFit.contain,
            child: SizedBox(
              width: 1280,
              height: 720,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 22, 28, 14),
                child: Column(
                  children: [
                    _header(),
                    const SizedBox(height: 14),
                    _connection(),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(flex: 7, child: _hero()),
                          const SizedBox(width: 22),
                          Expanded(
                            flex: 5,
                            child: Column(
                              children: [
                                _waiting(),
                                const SizedBox(height: 16),
                                Expanded(child: _rooms()),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _announcement(),
                    _controls(),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );

  Widget _header({bool compact = false}) {
    final clinic = Text(
      '${object(snapshot?['layanan'])['nama'] ?? 'Public Display'}',
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
    );
    final time = clock == null
        ? _clock(now)
        : ValueListenableBuilder<DateTime>(
            valueListenable: clock!,
            builder: (_, value, _) => _clock(value),
          );
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const QueueBBrand(compact: true),
          const SizedBox(height: 16),
          clinic,
          const SizedBox(height: 8),
          time,
        ],
      );
    }
    return Row(
      children: [
        const SizedBox(width: 214, child: QueueBBrand()),
        Container(width: 1, height: 58, color: QueueBStyle.border),
        const SizedBox(width: 24),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'INFORMASI ANTREAN POLIKLINIK',
                style: TextStyle(
                  fontSize: 13,
                  letterSpacing: 1.4,
                  color: QueueBStyle.muted,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              clinic,
            ],
          ),
        ),
        const SizedBox(width: 16),
        time,
      ],
    );
  }

  Widget _clock(DateTime value) => Column(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Text(
        '${two(value.hour)}:${two(value.minute)}:${two(value.second)}',
        key: const ValueKey('display-clock'),
        style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800),
      ),
      Text(_date(value), style: const TextStyle(fontSize: 16)),
      Text(
        value.timeZoneName,
        style: const TextStyle(color: QueueBStyle.muted),
      ),
    ],
  );

  Widget _connection() {
    final text = rejected
        ? 'Akses display ditolak · periksa konfigurasi perangkat'
        : error != null
        ? 'Snapshot belum tersinkron · menampilkan data terakhir'
        : status;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(
            live && error == null ? Icons.sensors : Icons.sensors_off,
            size: 18,
            color: rejected ? QueueBStyle.danger : QueueBStyle.darkTeal,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: rejected ? QueueBStyle.danger : QueueBStyle.muted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (snapshot?['diperolehPada'] != null)
            Text(
              'Snapshot ${snapshotTime ?? clockOnly(snapshot!['diperolehPada'])} ${now.timeZoneName}',
              style: const TextStyle(color: QueueBStyle.muted, fontSize: 12),
            ),
        ],
      ),
    );
  }

  Widget _hero() {
    final call = currentCall(snapshot);
    return Container(
      key: const ValueKey('display-call-panel'),
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: QueueBStyle.navy,
        borderRadius: BorderRadius.circular(24),
      ),
      child: DefaultTextStyle(
        style: const TextStyle(color: Colors.white, fontSize: 22),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.campaign_outlined,
                    color: Colors.white,
                    size: 26,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    call == null ? 'INFORMASI PANGGILAN' : 'SEDANG DIPANGGIL',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (call != null) ...[
              Expanded(
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '${call.ticket['nomorAntrean']}',
                      key: const ValueKey('display-call-number'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 190,
                        height: 1,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -4,
                      ),
                    ),
                  ),
                ),
              ),
              const Text('Silakan menuju', textAlign: TextAlign.center),
              const SizedBox(height: 10),
              Text(
                '${call.room['nama']}',
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Loket ${call.room['kode']}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 22),
              ),
            ] else ...[
              const Spacer(),
              if (snapshot == null && !rejected)
                const Center(
                  child: SizedBox(
                    width: 36,
                    height: 36,
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                ),
              const SizedBox(height: 20),
              Text(
                rejected
                    ? 'Akses display ditolak'
                    : snapshot == null
                    ? error == null
                          ? 'Memuat antrean…'
                          : 'Menunggu koneksi'
                    : 'Belum ada nomor dipanggil.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                rejected
                    ? 'Hubungkan kembali dengan token perangkat yang sah.'
                    : 'Perhatikan layar dan dengarkan panggilan petugas.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 19, height: 1.4),
              ),
              const Spacer(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _waiting() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
    decoration: BoxDecoration(
      color: QueueBStyle.mint,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: QueueBStyle.teal.withValues(alpha: .25)),
    ),
    child: Row(
      children: [
        const Icon(
          Icons.groups_outlined,
          color: QueueBStyle.darkTeal,
          size: 34,
        ),
        const SizedBox(width: 14),
        const Expanded(
          child: Text(
            'Pasien menunggu',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
        ),
        Text(
          '${snapshot?['totalMenunggu'] ?? '—'}',
          key: const ValueKey('display-waiting-count'),
          style: const TextStyle(
            fontSize: 48,
            height: 1,
            fontWeight: FontWeight.w900,
            color: QueueBStyle.darkTeal,
          ),
        ),
      ],
    ),
  );

  Widget _rooms({bool shrinkWrap = false}) {
    if (rooms.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            snapshot == null
                ? 'Menunggu data ruang…'
                : 'Belum ada ruang pelayanan aktif.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, color: QueueBStyle.muted),
          ),
        ),
      );
    }
    return _RoomDeck(
      shrinkWrap: shrinkWrap,
      builder: (controller) => LayoutBuilder(
        builder: (context, bounds) {
          final columns = rooms.length > 4 && bounds.maxWidth >= 460
              ? 3
              : rooms.length > 2 && bounds.maxWidth >= 410
              ? 2
              : 1;
          return GridView.builder(
            controller: controller,
            key: const ValueKey('display-rooms'),
            shrinkWrap: shrinkWrap,
            physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
            itemCount: rooms.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              mainAxisExtent: 138,
            ),
            itemBuilder: (context, index) => _room(rooms[index]),
          );
        },
      ),
    );
  }

  Widget _room(Json room) {
    final tickets = rows(room['tiketAktif']);
    final called = tickets.any((t) => t['status'] == 'DIPANGGIL');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: called ? QueueBStyle.mint : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: called ? QueueBStyle.teal : QueueBStyle.border,
          width: called ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${room['nama']}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
          ),
          Text(
            'Loket ${room['kode']}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: QueueBStyle.muted, fontSize: 15),
          ),
          const Spacer(),
          if (tickets.isEmpty)
            const Text(
              'Siap melayani',
              style: TextStyle(fontSize: 19, color: QueueBStyle.muted),
            )
          else
            Expanded(
              flex: 3,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  children: [
                    for (final ticket in tickets)
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${ticket['nomorAntrean']}',
                              style: const TextStyle(
                                fontSize: 38,
                                height: 1.1,
                                fontWeight: FontWeight.w800,
                                color: QueueBStyle.navy,
                              ),
                            ),
                            Text(
                              ticket['status'] == 'DIPANGGIL'
                                  ? 'Dipanggil'
                                  : 'Sedang dilayani',
                              style: const TextStyle(
                                fontSize: 16,
                                color: QueueBStyle.darkTeal,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _announcement() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: QueueBStyle.border),
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
            style: const TextStyle(
              fontSize: 22,
              height: 1.25,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _controls() => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (audioError != null)
          Text(audioError!, style: const TextStyle(color: QueueBStyle.danger)),
        Wrap(
          spacing: 8,
          alignment: WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (!rejected)
              TextButton.icon(
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Muat ulang'),
              ),
            if (!rejected)
              TextButton.icon(
                onPressed: audioBusy ? null : onAudio,
                icon: Icon(
                  audio ? Icons.volume_up : Icons.volume_off,
                  size: 18,
                ),
                label: Text(audio ? 'Matikan suara' : 'Aktifkan suara'),
              ),
            if (fullscreenSupported)
              TextButton.icon(
                onPressed: onFullscreen,
                icon: Icon(
                  fullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                  size: 20,
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
      ],
    ),
  );
}

/// More rooms than fit on a TV are cycled by complete rows, so a kiosk never
/// requires a mouse to reveal the rest of this same clinic's room cards.
class _RoomDeck extends StatefulWidget {
  const _RoomDeck({required this.builder, required this.shrinkWrap});
  final Widget Function(ScrollController) builder;
  final bool shrinkWrap;
  @override
  State<_RoomDeck> createState() => _RoomDeckState();
}

class _RoomDeckState extends State<_RoomDeck> {
  final controller = ScrollController();
  Timer? timer;
  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 12), (_) {
      if (widget.shrinkWrap ||
          !controller.hasClients ||
          controller.position.maxScrollExtent <= 0) {
        return;
      }
      final position = controller.position;
      final step =
          ((position.viewportDimension + 12) / 150).floor().clamp(1, 100) * 150;
      controller.jumpTo(
        position.pixels >= position.maxScrollExtent
            ? 0
            : (position.pixels + step).clamp(0, position.maxScrollExtent),
      );
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(controller);
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
