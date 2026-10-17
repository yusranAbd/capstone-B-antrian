import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'api.dart';
import 'config.dart';
import 'realtime.dart';
import 'widgets.dart';
import 'mobile_ui.dart';

class QueuePage extends StatefulWidget {
  const QueuePage({super.key, required this.api});
  final QueueApi api;
  @override
  State<QueuePage> createState() => _QueuePageState();
}

class _QueuePageState extends State<QueuePage> with WidgetsBindingObserver {
  List<Json> assignments = [];
  Json? snapshot;
  String? roomId, error, message;
  String liveStatus = 'Menghubungkan realtime…';
  bool loading = true, busy = false;
  final qr = TextEditingController(), ticket = TextEditingController();
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1000),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Panel petugas',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          Text(
            '${widget.api.config.today} · ${widget.api.config.serviceTimeZone} · $liveStatus',
          ),
          const SizedBox(height: 12),
          AppCard(
            color: QueueBStyle.mint,
            child: Row(
              children: [
                const CircleAvatar(
                  backgroundColor: Colors.white,
                  foregroundColor: QueueBStyle.darkTeal,
                  child: Icon(Icons.desktop_windows_outlined),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${widget.api.user?['nama'] ?? 'Petugas'}',
                        style: const TextStyle(color: QueueBStyle.muted),
                      ),
                      Text(
                        selectedRoom == null
                            ? 'Pilih ruang pelayanan'
                            : label(selectedRoom!),
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      if (selectedRoom != null)
                        Text(label(object(selectedRoom!['layanan']))),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (loading)
            const LinearProgressIndicator(semanticsLabel: 'Memuat penugasan'),
          if (error != null) MobileNotice(error!, error: true),
          if (message != null) MobileNotice(message!),
          Section(
            title: 'Ruang pelayanan',
            action: TextButton(
              onPressed: busy || loading ? null : loadAssignments,
              child: const Text('Muat ulang penugasan'),
            ),
            child: validAssignments.isEmpty
                ? const Text(
                    'Tidak ada penugasan aktif untuk hari ini. Salin ID akun dari profil dan hubungi ADMIN.',
                  )
                : ChoiceField(
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
                            setupRoom();
                          }),
                  ),
          ),
          if (selectedRoom != null) ...[
            Section(
              title: 'QR Check-In',
              subtitle: 'Pindai atau tempel QR pasien. Check-In dan Masuk Antrean adalah dua tindakan terpisah.',
              child: Column(
                children: [
                  TextField(
                    controller: qr,
                    enabled: !busy,
                    decoration: const InputDecoration(
                      labelText: 'Payload QR (SQ1…)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    children: [
                      OutlinedButton.icon(
                        onPressed: busy ? null : scan,
                        icon: const Icon(Icons.qr_code_scanner),
                        label: const Text('Pindai kamera'),
                      ),
                      FilledButton(
                        onPressed: busy
                            ? null
                            : () {
                                if (qr.text.trim().isEmpty) {
                                  setState(
                                    () => error = 'Payload QR wajib diisi.',
                                  );
                                  return;
                                }
                                action(
                                  '/check-in',
                                  body: {
                                    'qrPayload': qr.text.trim(),
                                    'loketId': roomId,
                                  },
                                );
                              },
                        child: const Text('Check-In'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Section(
              title: 'Pelayanan ruang ini',
              action: FilledButton.icon(
                onPressed: busy || snapshot == null || active.isNotEmpty
                    ? null
                    : () => action('/queue/panggil'),
                icon: const Icon(Icons.campaign_outlined),
                label: const Text('Panggil berikutnya'),
              ),
              child: active.isEmpty
                  ? const Text(
                      'Belum ada tiket aktif. Backend menentukan tiket berikutnya sesuai prioritas.',
                    )
                  : Column(
                      children: active
                          .map(
                            (t) => Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${t['nomorAntrean']}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .displaySmall,
                                ),
                                StatusBadge(t['status']),
                                Wrap(
                                  spacing: 12,
                                  runSpacing: 8,
                                  children: [
                                    if (t['status'] == 'DIPANGGIL') ...[
                                      OutlinedButton(
                                        onPressed: busy
                                            ? null
                                            : () => action(
                                                '/queue/${t['tiketId']}/panggil-ulang',
                                              ),
                                        child: const Text('Panggil Ulang'),
                                      ),
                                      OutlinedButton(
                                        onPressed: busy
                                            ? null
                                            : () => action(
                                                '/queue/${t['tiketId']}/lewati',
                                              ),
                                        child: const Text('Lewati'),
                                      ),
                                      FilledButton(
                                        onPressed: busy
                                            ? null
                                            : () => action(
                                                '/queue/${t['tiketId']}/mulai-pelayanan',
                                              ),
                                        child: const Text('Mulai Pelayanan'),
                                      ),
                                    ],
                                    if (t['status'] == 'DILAYANI')
                                      FilledButton(
                                        onPressed: busy
                                            ? null
                                            : () => action(
                                                '/queue/${t['tiketId']}/selesaikan-pelayanan',
                                              ),
                                        child: const Text(
                                          'Selesaikan Pelayanan',
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          )
                          .toList(),
                    ),
            ),
            Section(
              title: 'Tiket diterima / dilewati',
              subtitle: 'Daftar sementara berasal dari tindakan sesi ini dan event SKIP. Untuk memulihkan pekerjaan setelah membuka ulang aplikasi, masukkan ID tiket yang sah.',
              child: Column(
                children: [
                  for (final r in receipts.values)
                    ListTile(
                      title: Text('${r['nomorAntrean']} · ${r['status']}'),
                      subtitle: SelectableText('${r['tiketId']}'),
                      trailing: TextButton(
                        onPressed: busy
                            ? null
                            : () => action(
                                '/queue/${r['tiketId']}/${r['status'] == 'CHECK_IN' ? 'masuk' : 'antre-ulang'}',
                              ),
                        child: Text(
                          r['status'] == 'CHECK_IN'
                              ? 'Masuk Antrean'
                              : 'Antre Ulang',
                        ),
                      ),
                    ),
                  TextField(
                    controller: ticket,
                    enabled: !busy,
                    decoration: const InputDecoration(
                      labelText: 'ID tiket untuk masuk / antre ulang',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    children: [
                      OutlinedButton(
                        onPressed: busy ? null : () => manual('masuk'),
                        child: const Text('Masuk Antrean'),
                      ),
                      OutlinedButton(
                        onPressed: busy ? null : () => manual('antre-ulang'),
                        child: const Text('Antre Ulang'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Section(
              title:
                  'Menunggu · ${object(snapshot?['menunggu'])['total'] ?? '—'}',
              subtitle:
                  'Urutan dari server. Diperbarui: ${widget.api.config.instantLabel(snapshot?['diperolehPada'])}',
              action: OutlinedButton.icon(
                onPressed: busy ? null : () => loader?.refresh(),
                icon: const Icon(Icons.refresh),
                label: const Text('Muat ulang antrean'),
              ),
              child: Column(
                children: [
                  if (snapshot == null) const Text('Menunggu snapshot…'),
                  for (final t in rows(object(snapshot?['menunggu'])['tiket']))
                    ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: QueueBStyle.mint,
                        foregroundColor: QueueBStyle.darkTeal,
                        child: Icon(Icons.confirmation_number_outlined),
                      ),
                      title: Text(
                        '${t['nomorAntrean']}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        '${t['jenisAntrean'] ?? 'Antrean harian'}${t['layakDipanggil'] == false ? ' · ${t['alasanTidakLayak'] ?? 'Belum layak'}' : ''}${t['slotMulaiPada'] == null ? '' : '\nSlot: ${widget.api.config.instantLabel(t['slotMulaiPada'])}'}',
                      ),
                      trailing: t['layakDipanggil'] == false
                          ? const Icon(Icons.schedule)
                          : const Icon(Icons.check_circle_outline),
                    ),
                  if (snapshot != null &&
                      rows(object(snapshot!['menunggu'])['tiket']).isEmpty)
                    const EmptyState(
                      text: 'Belum ada pasien menunggu.',
                      icon: Icons.people_outline,
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
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
