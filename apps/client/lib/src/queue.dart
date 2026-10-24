import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'api.dart';
import 'config.dart';
import 'realtime.dart';
import 'widgets.dart';
import 'mobile_ui.dart';
import 'staff_ui.dart';

class QueuePage extends StatefulWidget {
  const QueuePage({super.key, required this.api, this.headerBuilder});
  final QueueApi api;
  final PreferredSizeWidget Function(Widget context)? headerBuilder;
  @override
  State<QueuePage> createState() => _QueuePageState();
}

class _QueuePageState extends State<QueuePage> with WidgetsBindingObserver {
  List<Json> assignments = [];
  Json? snapshot;
  String? roomId, error, message;
  String liveStatus = 'Menghubungkan realtime…';
  bool loading = true, busy = false;
  String? pendingPath;
  final qr = TextEditingController(), ticket = TextEditingController();
  final search = TextEditingController();
  final Map<String, Json> receipts = {};
  SnapshotLoader? loader;
  RealtimeFeed? feed;
  Timer? poll;
  List<Json> get validAssignments => assignments
      .where((a) => assignmentValid(a, widget.api.config.today))
      .toList();
  Json? get selectedRoom => validAssignments
      .where((a) => a['loketId'] == roomId)
      .map((a) => object(a['loket']))
      .firstOrNull;
  List<Json> get active =>
      rows(snapshot?['loket'])
          .where((l) => l['id'] == roomId)
          .expand((l) => rows(l['tiketAktif']))
          .toList();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    loadAssignments();
  }

  Future<void> loadAssignments() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final list = rows(await widget.api.request('GET', '/penugasan-petugas'));
      if (!mounted) return;
      setState(() {
        assignments = list;
        roomId = validAssignments.firstOrNull?['loketId'];
      });
      setupRoom();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void setupRoom() {
    feed?.dispose();
    loader?.dispose();
    poll?.cancel();
    snapshot = null;
    receipts.clear();
    ticket.clear();
    qr.clear();
    message = null;
    final room = selectedRoom;
    if (room == null) return;
    final selected = roomId!;
    loader = SnapshotLoader(
      fetch: () async => object(
        await widget.api.request(
          'GET',
          '/queue/snapshot',
          query: {'loketId': selected},
        ),
      ),
      onData: (data) {
        if (mounted && selected == roomId) {
          setState(() {
            snapshot = data;
            error = null;
            receipts.removeWhere(
              (_, r) => r['date'] != data['tanggalPelayanan'],
            );
          });
        }
      },
      onError: (e) {
        if (mounted && selected == roomId) setState(() => error = '$e');
      },
    );
    feed = RealtimeFeed(
      api: widget.api,
      layananId: '${object(room['layanan'])['id']}',
      onRefresh: () => loader?.refresh(),
      onStatus: (status) {
        if (mounted) setState(() => liveStatus = status);
      },
      onEvent: rememberEvent,
    );
    loader!.refresh();
    poll = Timer.periodic(const Duration(seconds: 15), (_) {
      if (selectedRoom == null) {
        feed?.dispose();
        loader?.dispose();
        poll?.cancel();
        if (mounted) {
          setState(() {
            roomId = null;
            snapshot = null;
            receipts.clear();
            message = 'Penugasan berubah tanggal. Muat ulang penugasan.';
          });
        }
      } else {
        loader?.refresh();
      }
    });
  }

  void rememberEvent(Json event) {
    final id = '${event['tiketId']}';
    if (event['loketId'] == roomId && event['aksi'] == 'SKIP') {
      receipts[id] = {...event, 'date': widget.api.config.today};
    } else if (event['aksi'] != 'RECALL') {
      receipts.remove(id);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) loader?.refresh();
  }

  Future<void> action(String path, {Json? body}) async {
    if (busy || selectedRoom == null) return;
    setState(() {
      busy = true;
      pendingPath = path;
      error = null;
      message = null;
    });
    try {
      final result = object(
        await widget.api.request(
          'POST',
          path,
          body: body ?? {'loketId': roomId},
        ),
      );
      final id = '${result['tiketId']}';
      if (mounted) {
        setState(() {
          message = '${result['nomorAntrean']} · ${result['status']}';
          if (['CHECK_IN', 'DILEWATI'].contains(result['status'])) {
            receipts[id] = {...result, 'date': widget.api.config.today};
          } else {
            receipts.remove(id);
          }
          if (result['status'] == 'CHECK_IN') {
            qr.clear();
            ticket.text = id;
          }
          if (['MENUNGGU', 'SELESAI'].contains(result['status'])) {
            ticket.clear();
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      final actionError = error;
      await loader?.refresh();
      if (mounted) {
        setState(() {
          busy = false;
          pendingPath = null;
          if (actionError != null) error = actionError;
        });
      }
    }
  }

  Future<void> scan() async {
    final payload = await showDialog<String>(
      context: context,
      builder: (context) => const _Scanner(),
    );
    if (payload != null && mounted) setState(() => qr.text = payload);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    feed?.dispose();
    loader?.dispose();
    poll?.cancel();
    qr.dispose();
    ticket.dispose();
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: StaffStyle.theme,
    child: Builder(
      builder: (context) => Scaffold(
        appBar: widget.headerBuilder?.call(
          StaffHeaderContext(
            name: '${widget.api.user?['nama'] ?? 'Petugas'}',
            room: selectedRoom,
            status: liveStatus,
          ),
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 1000;
            final room = selectedRoom;
            final stats = [
              StaffMetric(
                title: 'Pasien menunggu',
                value: '${object(snapshot?['menunggu'])['total'] ?? '—'}',
                detail: 'Poliklinik terpilih',
                icon: Icons.groups_outlined,
              ),
              StaffMetric(
                title: 'Dipanggil / dilayani',
                value: snapshot == null ? '—' : '${active.length}',
                detail: 'Ruang ini',
                icon: Icons.campaign_outlined,
              ),
              const StaffMetric(
                title: 'Pasien selesai',
                value: '—',
                detail: 'Total belum tersedia dari API',
                icon: Icons.task_alt_rounded,
              ),
            ];
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Wrap(
                  spacing: 16,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Panel petugas',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          '${widget.api.config.today} · ${widget.api.config.serviceTimeZone}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: QueueBStyle.muted,
                          ),
                        ),
                        if (constraints.maxWidth < 700)
                          Text(
                            '${widget.api.user?['nama'] ?? 'Petugas'}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: QueueBStyle.muted,
                            ),
                          ),
                      ],
                    ),
                    if (validAssignments.isNotEmpty)
                      SizedBox(
                        width: wide
                            ? 430
                            : (constraints.maxWidth - 32).clamp(0, 430),
                        child: ChoiceField(
                          label: 'Ruang yang ditugaskan',
                          choices: {
                            for (final a in validAssignments)
                              '${a['loketId']}':
                                  '${label(object(a['loket']))} · ${label(object(object(a['loket'])['layanan']))}',
                          }.entries.map((e) => (e.key, e.value)).toList(),
                          value: roomId,
                          onChanged: busy
                              ? null
                              : (v) => setState(() {
                                  roomId = v;
                                  error = null;
                                  search.clear();
                                  setupRoom();
                                }),
                        ),
                      ),
                    IconButton(
                      tooltip: 'Muat ulang penugasan',
                      onPressed: busy || loading ? null : loadAssignments,
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                    if (!wide) StaffLiveStatus(liveStatus),
                  ],
                ),
                if (loading)
                  const LinearProgressIndicator(
                    semanticsLabel: 'Memuat penugasan',
                  ),
                if (busy)
                  const LinearProgressIndicator(
                    semanticsLabel: 'Memproses tindakan',
                  ),
                if (error != null) MobileNotice(error!, error: true),
                if (message != null) MobileNotice(message!),
                const SizedBox(height: 12),
                if (constraints.maxWidth >= 640)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < stats.length; i++) ...[
                        if (i > 0) const SizedBox(width: 12),
                        Expanded(child: stats[i]),
                      ],
                    ],
                  )
                else ...[
                  for (final stat in stats)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: stat,
                    ),
                ],
                const SizedBox(height: 12),
                if (room == null && !loading)
                  const StaffPanel(
                    title: 'Ruang pelayanan',
                    icon: Icons.meeting_room_outlined,
                    child: StaffEmpty(
                      'Tidak ada penugasan aktif untuk hari ini. Hubungi ADMIN untuk penugasan loket.',
                    ),
                  ),
                if (room != null) ...[
                  if (wide)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 3,
                          child: waitingPanel(context, height: 294),
                        ),
                        const SizedBox(width: 12),
                        Expanded(flex: 2, child: servicePanel(context)),
                      ],
                    )
                  else ...[
                    servicePanel(context),
                    const SizedBox(height: 12),
                    waitingPanel(context, height: 300),
                  ],
                  const SizedBox(height: 12),
                  if (wide)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 3, child: checkInPanel()),
                        const SizedBox(width: 12),
                        Expanded(flex: 2, child: recoveryPanel()),
                      ],
                    )
                  else ...[
                    checkInPanel(),
                    const SizedBox(height: 12),
                    recoveryPanel(),
                  ],
                ],
              ],
            );
          },
        ),
      ),
    ),
  );

  Widget waitingPanel(BuildContext context, {required double height}) {
    final waiting = rows(object(snapshot?['menunggu'])['tiket']);
    // Filtering only hides rows; server order and eligibility stay untouched.
    final visible = waiting
        .where(
          (t) => '${t['nomorAntrean']}'.toLowerCase().contains(
            search.text.trim().toLowerCase(),
          ),
        )
        .toList();
    return StaffPanel(
      title: 'Daftar antrean poli',
      icon: Icons.format_list_numbered_rounded,
      action: IconButton(
        tooltip: 'Muat ulang antrean',
        onPressed: busy ? null : () => loader?.refresh(),
        icon: const Icon(Icons.refresh_rounded),
      ),
      child: SizedBox(
        height: height - 76,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: search,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Cari nomor antrean',
                prefixIcon: Icon(Icons.search_rounded, size: 20),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: snapshot == null
                  ? const StaffEmpty('Menunggu snapshot…')
                  : visible.isEmpty
                  ? StaffEmpty(
                      search.text.trim().isEmpty
                          ? 'Belum ada pasien menunggu.'
                          : 'Nomor antrean tidak ditemukan.',
                    )
                  : ListView.separated(
                      itemCount: visible.length,
                      separatorBuilder: (_, _) =>
                          const Divider(height: 1, color: QueueBStyle.border),
                      itemBuilder: (context, index) {
                        final t = visible[index];
                        final eligible = t['layakDipanggil'] != false;
                        final kind = switch (t['jenisAntrean']) {
                          'JANJI_TEMU' => 'Appointment',
                          'WALK_IN' => 'Walk-in',
                          _ => 'Antrean harian',
                        };
                        final reason = t['alasanTidakLayak'] == null
                            ? 'Belum layak dipanggil'
                            : '${t['alasanTidakLayak']}'.replaceAll('_', ' ');
                        final detail = [
                          kind,
                          if (!eligible) reason,
                          if (t['slotMulaiPada'] != null)
                            'Slot ${widget.api.config.instantLabel(t['slotMulaiPada'])}',
                        ].join(' · ');
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 7,
                                ),
                                decoration: BoxDecoration(
                                  color: QueueBStyle.mint,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '${t['nomorAntrean']}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: QueueBStyle.darkTeal,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  detail,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: QueueBStyle.muted,
                                  ),
                                ),
                              ),
                              Tooltip(
                                message: eligible ? 'Menunggu' : reason,
                                child: Icon(
                                  eligible
                                      ? Icons.check_circle_outline
                                      : Icons.schedule,
                                  size: 18,
                                  color: eligible
                                      ? QueueBStyle.success
                                      : QueueBStyle.warning,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 6),
            Text(
              'Urutan server · ${visible.length}/${waiting.length} tiket ditampilkan · ${widget.api.config.instantLabel(snapshot?['diperolehPada'])}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: QueueBStyle.muted),
            ),
          ],
        ),
      ),
    );
  }

  Widget servicePanel(BuildContext context) => StaffPanel(
    title: 'Pelayanan ruang ini',
    icon: Icons.campaign_outlined,
    dark: true,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${selectedRoom?['kode'] ?? ''} · ${label(selectedRoom ?? {})}',
          style: const TextStyle(color: QueueBStyle.mint, fontSize: 12),
        ),
        if (active.isEmpty) ...[
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              '—',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 48,
                height: 1.2,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const Text(
            'Belum ada tiket aktif',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontSize: 13),
          ),
          const SizedBox(height: 12),
        ],
        for (final t in active) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Wrap(
              spacing: 16,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  '${t['nomorAntrean']}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 44,
                    height: 1.15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                StatusBadge(t['status']),
              ],
            ),
          ),
          const SizedBox(height: 10),
          if (t['status'] == 'DIPANGGIL')
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                lightButton(
                  'Panggil Ulang',
                  '/queue/${t['tiketId']}/panggil-ulang',
                ),
                lightButton('Lewati', '/queue/${t['tiketId']}/lewati'),
                FilledButton(
                  onPressed: busy
                      ? null
                      : () => action('/queue/${t['tiketId']}/mulai-pelayanan'),
                  child: operationLabel(
                    '/queue/${t['tiketId']}/mulai-pelayanan',
                    'Mulai Pelayanan',
                  ),
                ),
              ],
            ),
          if (t['status'] == 'DILAYANI')
            FilledButton(
              onPressed: busy
                  ? null
                  : () => action('/queue/${t['tiketId']}/selesaikan-pelayanan'),
              child: operationLabel(
                '/queue/${t['tiketId']}/selesaikan-pelayanan',
                'Selesaikan Pelayanan',
              ),
            ),
        ],
        if (active.isEmpty)
          FilledButton.icon(
            onPressed: busy || snapshot == null
                ? null
                : () => action('/queue/panggil'),
            icon: const Icon(Icons.campaign_outlined, size: 20),
            label: operationLabel('/queue/panggil', 'Panggil berikutnya'),
          ),
        const SizedBox(height: 10),
        const Text(
          'Pemilihan tiket mengikuti prioritas Queue Engine.',
          style: TextStyle(color: QueueBStyle.mint, fontSize: 11),
        ),
      ],
    ),
  );

  Widget lightButton(String text, String path) => OutlinedButton(
    style: OutlinedButton.styleFrom(
      foregroundColor: Colors.white,
      disabledForegroundColor: QueueBStyle.muted,
    ),
    onPressed: busy ? null : () => action(path),
    child: operationLabel(path, text),
  );

  Widget operationLabel(String path, String text, {bool onLight = false}) {
    if (!busy || pendingPath != path) return Text(text);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: onLight ? QueueBStyle.darkTeal : QueueBStyle.mint,
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }

  Widget checkInPanel() => StaffPanel(
    title: 'QR Check-In',
    icon: Icons.qr_code_scanner_rounded,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: qr,
          enabled: !busy,
          decoration: const InputDecoration(
            labelText: 'Payload QR (SQ1…)',
            prefixIcon: Icon(Icons.qr_code_rounded, size: 20),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: busy ? null : scan,
              icon: const Icon(Icons.qr_code_scanner, size: 20),
              label: const Text('Pindai kamera'),
            ),
            FilledButton(
              onPressed: busy
                  ? null
                  : () {
                      if (qr.text.trim().isEmpty) {
                        setState(() => error = 'Payload QR wajib diisi.');
                        return;
                      }
                      action(
                        '/check-in',
                        body: {'qrPayload': qr.text.trim(), 'loketId': roomId},
                      );
                    },
              child: operationLabel('/check-in', 'Check-In', onLight: true),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          '1. Check-In QR → 2. Masuk Antrean dari tiket diterima.',
          style: TextStyle(fontSize: 12, color: QueueBStyle.muted),
        ),
      ],
    ),
  );

  Widget recoveryPanel() => StaffPanel(
    title: 'Tiket diterima / dilewati',
    icon: Icons.move_to_inbox_outlined,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (receipts.isEmpty)
          const Text(
            'Belum ada tiket untuk ditindaklanjuti.',
            style: TextStyle(fontSize: 13, color: QueueBStyle.muted),
          ),
        if (receipts.isNotEmpty)
          SizedBox(
            height: (receipts.length * 58.0).clamp(58, 116),
            child: ListView(
              children: [
                for (final r in receipts.values)
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${r['nomorAntrean']}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              '${r['status']}'.replaceAll('_', ' '),
                              style: const TextStyle(
                                fontSize: 11,
                                color: QueueBStyle.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: busy
                            ? null
                            : () => action(
                                '/queue/${r['tiketId']}/${r['status'] == 'CHECK_IN' ? 'masuk' : 'antre-ulang'}',
                              ),
                        child: operationLabel(
                          '/queue/${r['tiketId']}/${r['status'] == 'CHECK_IN' ? 'masuk' : 'antre-ulang'}',
                          r['status'] == 'CHECK_IN'
                              ? 'Masuk Antrean'
                              : 'Antre Ulang',
                          onLight: true,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        const SizedBox(height: 6),
        const Text(
          'Daftar sementara sesi ini dan event SKIP. Setelah membuka ulang, gunakan pemulihan ID tiket.',
          style: TextStyle(fontSize: 11, color: QueueBStyle.muted),
        ),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 4),
          title: const Text(
            'Pemulihan ID tiket',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          children: [
            TextField(
              controller: ticket,
              enabled: !busy,
              decoration: const InputDecoration(
                labelText: 'ID tiket untuk masuk / antre ulang',
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: busy ? null : () => manual('masuk'),
                  child: operationLabel(
                    '/queue/${ticket.text.trim()}/masuk',
                    'Masuk Antrean',
                    onLight: true,
                  ),
                ),
                OutlinedButton(
                  onPressed: busy ? null : () => manual('antre-ulang'),
                  child: operationLabel(
                    '/queue/${ticket.text.trim()}/antre-ulang',
                    'Antre Ulang',
                    onLight: true,
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  );
  void manual(String route) {
    if (!RegExp(r'^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$')
        .hasMatch(ticket.text.trim())) {
      setState(() => error = 'Masukkan ID tiket UUID yang sah.');
      return;
    }
    action('/queue/${ticket.text.trim()}/$route');
  }
}

class _Scanner extends StatefulWidget {
  const _Scanner();
  @override
  State<_Scanner> createState() => _ScannerState();
}

class _ScannerState extends State<_Scanner> {
  bool detected = false;
  final controller = MobileScannerController(formats: [BarcodeFormat.qrCode]);
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Pindai QR tiket'),
    content: SizedBox(
      width: 480,
      height: 360,
      child: MobileScanner(
        controller: controller,
        onDetect: (capture) {
          final raw = capture.barcodes.firstOrNull?.rawValue;
          if (!detected && raw != null && raw.startsWith('SQ1.')) {
            detected = true;
            Navigator.pop(context, raw);
          }
        },
        errorBuilder: (context, error) => const Center(
          child: Text(
            'Kamera tidak tersedia atau izin ditolak. Tutup lalu tempel payload QR.',
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Tutup'),
      ),
    ],
  );
}
