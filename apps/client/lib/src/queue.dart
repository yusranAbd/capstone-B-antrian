import 'dart:async';

import 'package:flutter/material.dart';

import 'staff_qr_scanner.dart';

import 'api.dart';
import 'config.dart';
import 'realtime.dart';
import 'widgets.dart';
import 'mobile_ui.dart';
import 'staff_ui.dart';
import 'staff_v4.dart';

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
  int followupPage = 1;
  String? roomId, error, message;
  String liveStatus = 'Menghubungkan realtime…';
  bool loading = true, busy = false;
  String? pendingPath;
  final qr = TextEditingController();
  final search = TextEditingController();
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
        final previous = roomId;
        assignments = list;
        roomId = validAssignments.any((a) => a['loketId'] == previous)
            ? previous
            : validAssignments.firstOrNull?['loketId'];
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
    followupPage = 1;
    schedules = [];
    scheduleLoading = true;
    scheduleFailed = false;
    scheduleVersion++;
    lastScan = null;
    manualQrOpen = false;
    qr.clear();
    message = null;
    final room = selectedRoom;
    if (room == null) return;
    final selected = roomId!;
    loader = SnapshotLoader(
      fetch: () async {
        final data = object(
          await widget.api.request(
            'GET',
            '/queue/snapshot',
            query: {
              'loketId': selected,
              'halamanTindakLanjut': '$followupPage',
            },
          ),
        );
        if (mounted && selected == roomId) {
          unawaited(
            loadSchedules(selected, data['tanggalPelayanan'].toString()),
          );
        }
        return data;
      },
      onData: (data) {
        final pages =
            object(data['daftarPasien'])['jumlahHalamanTindakLanjut'] ?? 1;
        if (mounted && selected == roomId && followupPage > pages) {
          setState(() => followupPage = pages);
          loader?.refresh();
          return;
        }
        if (mounted &&
            selected == roomId &&
            (object(data['daftarPasien'])['halamanTindakLanjut'] ??
                    followupPage) ==
                followupPage) {
          setState(() {
            snapshot = data;
            error = null;
          });
        }
      },
      onError: (e) {
        if (mounted && selected == roomId) {
          setState(() {
            error = e.toString();
            if (e is ApiException && [401, 403].contains(e.status)) {
              snapshot = null;
              schedules = [];
              scheduleLoading = false;
              scheduleVersion++;
              lastScan = null;
            }
          });
        }
      },
    );
    feed = RealtimeFeed(
      api: widget.api,
      layananId: '${object(room['layanan'])['id']}',
      onRefresh: () => loader?.refresh(),
      onStatus: (status) {
        if (mounted) setState(() => liveStatus = status);
      },
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
            message = 'Penugasan berubah tanggal. Muat ulang penugasan.';
          });
        }
      } else {
        loader?.refresh();
      }
    });
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
      if (mounted) {
        setState(() {
          message = '${result['nomorAntrean']} · ${result['status']}';
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

  Json? lastScan;
  bool manualQrOpen = false;

  Future<Json> submitQr(String value) async {
    if (!mounted) {
      throw const ApiException(
        401,
        'Sesi petugas telah berakhir. Tutup pemindai dan login kembali.',
      );
    }
    final payload = value.trim();
    if (busy || selectedRoom == null) {
      throw const ApiException(409, 'Tunggu proses sebelumnya selesai.');
    }
    if (!validCheckInQr(payload)) {
      const message = 'Format QR tidak lengkap atau tidak valid.';
      setState(() => error = message);
      throw const ApiException(400, message);
    }
    setState(() {
      busy = true;
      pendingPath = '/check-in/auto-antrean';
      error = null;
      message = null;
      lastScan = null;
    });
    String? failure;
    try {
      final result = object(
        await widget.api.request(
          'POST',
          '/check-in/auto-antrean',
          body: {'qrPayload': payload, 'loketId': roomId},
        ),
      );
      if (!mounted) {
        throw const ApiException(
          401,
          'Sesi petugas telah berakhir. Tutup pemindai dan login kembali.',
        );
      }
      if (result['status'] != 'MENUNGGU') {
        throw const ApiException(
          409,
          'Status belum MENUNGGU. Periksa antrean sebelum mencoba kembali.',
        );
      }
      if (mounted) {
        setState(() {
          lastScan = result;
          qr.clear();
        });
      }
      return result;
    } catch (e) {
      failure = '$e';
      if (mounted) setState(() => error = failure);
      rethrow;
    } finally {
      await loader?.refresh();
      if (mounted) {
        setState(() {
          busy = false;
          pendingPath = null;
          if (failure != null) error = failure;
        });
      }
    }
  }

  Future<void> scan() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => StaffQrScanner(onScan: submitQr),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    feed?.dispose();
    loader?.dispose();
    poll?.cancel();
    qr.dispose();
    search.dispose();
    super.dispose();
  }

  Widget roomChoice() => Row(
    children: [
      Expanded(
        child: ChoiceField(
          label: 'Ruang yang ditugaskan',
          choices: {
            for (final a in validAssignments)
              '${a['loketId']}':
                  '${label(object(a['loket']))} · ${label(object(object(a['loket'])['layanan']))}',
          }.entries.map((e) => (e.key, e.value)).toList(),
          value: roomId,
          onChanged: busy || loading
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
        icon: const Icon(Icons.refresh, size: 20),
      ),
    ],
  );

  List<Json> schedules = [];
  bool scheduleLoading = false, scheduleFailed = false;
  int scheduleVersion = 0;
  Future<void> loadSchedules(String selected, String date) async {
    final version = ++scheduleVersion;
    try {
      final list = rows(
        await widget.api.request(
          'GET',
          '/jadwal-praktik',
          query: {
            'layananId': '${object(selectedRoom?['layanan'])['id']}',
            'tanggal': date,
          },
        ),
      );
      if (mounted && selected == roomId && version == scheduleVersion) {
        setState(() {
          schedules = list
              .where(
                (s) =>
                    (s['loketId'] ?? object(s['loket'])['id']) == selected &&
                    dateOnly(s['tanggal']) == date &&
                    s['aktif'] != false,
              )
              .toList();
          scheduleLoading = false;
          scheduleFailed = false;
        });
      }
    } catch (_) {
      if (mounted && selected == roomId && version == scheduleVersion) {
        setState(() {
          schedules = [];
          scheduleLoading = false;
          scheduleFailed = true;
        });
      }
    }
  }

  List<Json> get patients {
    final source = snapshot?['daftarPasien'] is Map
        ? rows(object(snapshot?['daftarPasien'])['tiket'])
        : rows(object(snapshot?['menunggu'])['tiket'])
              .map((t) => {'status': 'MENUNGGU', ...t})
              .toList();
    final unique = <String, Json>{};
    for (final t in source) {
      unique.putIfAbsent('${t['tiketId']}', () => t);
    }
    return unique.values.toList();
  }

  void rowAction(Json row, String route) {
    if (route == 'detail') {
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('${row['nomorAntrean']}'),
          content: Text(
            '${row['namaPasien'] ?? 'Nama belum tersedia'}\nStatus: ${row['status']}\nCheck-in: ${widget.api.config.instantLabel(row['checkInPada'])}${row['layakDipanggil'] == false ? '\n${row['alasanTidakLayak'] ?? 'Belum layak dipanggil'}' : ''}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Tutup'),
            ),
          ],
        ),
      );
    } else if (row['status'] == 'DILEWATI' &&
            row['bisaAntreUlang'] == true &&
            route == 'antre-ulang' ||
        row['status'] == 'CHECK_IN' &&
            row['bisaMasukAntrean'] == true &&
            route == 'masuk') {
      action('/queue/${row['tiketId']}/$route');
    }
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: StaffStyle.theme,
    child: Builder(
      builder: (context) => Scaffold(
        appBar: widget.headerBuilder?.call(roomChoice()),
        body: LayoutBuilder(
          builder: (context, box) {
            final wide = box.maxWidth >= 1000;
            final room = selectedRoom;
            final doctor = StaffScheduledDoctors(
              config: widget.api.config,
              schedules: schedules,
              clinic: label(object(room?['layanan'])),
              loading: scheduleLoading,
              failed: scheduleFailed,
            );
            final mainHeight = (box.maxHeight - 202).clamp(390.0, 900.0);
            return SingleChildScrollView(
              key: const ValueKey('staff-page-scroll'),
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.headerBuilder == null) roomChoice(),
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
                      SizedBox(
                        height: mainHeight,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              flex: 65,
                              child: Column(
                                children: [
                                  doctor,
                                  const SizedBox(height: 12),
                                  Expanded(child: waitingPanel(context)),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 35,
                              child: servicePanel(context, height: mainHeight),
                            ),
                          ],
                        ),
                      )
                    else ...[
                      doctor,
                      const SizedBox(height: 12),
                      servicePanel(context),
                      const SizedBox(height: 12),
                      SizedBox(height: 450, child: waitingPanel(context)),
                    ],
                    const SizedBox(height: 12),
                    checkInPanel(),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    ),
  );

  Widget waitingPanel(BuildContext context) {
    final query = search.text.trim().toLowerCase();
    final visible = patients
        .where(
          (t) => '${t['nomorAntrean'] ?? ''} ${t['namaPasien'] ?? ''}'
              .toLowerCase()
              .contains(query),
        )
        .toList();
    return StaffPanel(
      title: 'Daftar antrean poli',
      icon: Icons.format_list_numbered_rounded,
      expand: true,
      action: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message: liveStatus,
            child: Icon(
              liveStatus == 'Realtime terhubung'
                  ? Icons.wifi_rounded
                  : Icons.sync_rounded,
              size: 16,
              color: liveStatus == 'Realtime terhubung'
                  ? QueueBStyle.success
                  : QueueBStyle.warning,
            ),
          ),
          IconButton(
            tooltip: 'Muat ulang antrean',
            onPressed: busy ? null : () => loader?.refresh(),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: search,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Cari nomor antrean atau nama pasien',
              prefixIcon: Icon(Icons.search_rounded, size: 20),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: snapshot == null
                ? const StaffEmpty('Menunggu snapshot…')
                : StaffPatientList(
                    key: ValueKey(query),
                    rows: visible,
                    config: widget.api.config,
                    busy: busy,
                    onAction: rowAction,
                  ),
          ),
          if ((object(snapshot?['daftarPasien'])['jumlahHalamanTindakLanjut'] ??
                  1) >
              1)
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Tindak lanjut: $followupPage/${object(snapshot?['daftarPasien'])['jumlahHalamanTindakLanjut']}',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
                IconButton(
                  tooltip: 'Tindak lanjut sebelumnya',
                  onPressed: busy || followupPage <= 1
                      ? null
                      : () {
                          setState(() => followupPage--);
                          loader?.refresh();
                        },
                  icon: const Icon(Icons.chevron_left),
                ),
                IconButton(
                  tooltip: 'Tindak lanjut berikutnya',
                  onPressed:
                      busy ||
                          followupPage >=
                              (object(
                                    snapshot?['daftarPasien'],
                                  )['jumlahHalamanTindakLanjut'] ??
                                  1)
                      ? null
                      : () {
                          setState(() => followupPage++);
                          loader?.refresh();
                        },
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          Text(
            'Urutan menunggu dari server · ${object(snapshot?['daftarPasien'])['ditampilkan'] ?? patients.length}/${object(snapshot?['daftarPasien'])['total'] ?? object(snapshot?['menunggu'])['total'] ?? '—'} tiket dimuat',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10, color: QueueBStyle.muted),
          ),
        ],
      ),
    );
  }

  Widget servicePanel(BuildContext context, {double? height}) => SizedBox(
    height: height,
    child: StaffPanel(
      title: 'Pelayanan ruang ini',
      icon: Icons.campaign_outlined,
      dark: true,
      expand: height != null,
      child: LayoutBuilder(
        builder: (context, box) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: box.hasBoundedHeight ? box.maxHeight : 0,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${selectedRoom?['kode'] ?? ''} · ${label(selectedRoom ?? {})}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      label(object(selectedRoom?['layanan'])),
                      style: const TextStyle(
                        color: QueueBStyle.mint,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: .12),
                    ),
                  ),
                  child: Column(
                    children: [
                      if (active.isEmpty) ...[
                        const Text(
                          '—',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 52,
                            height: 1.2,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Belum ada tiket aktif',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Panggil pasien berikutnya untuk memulai pelayanan.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: QueueBStyle.mint,
                            fontSize: 12,
                          ),
                        ),
                      ],
                      for (final t in active) ...[
                        Text(
                          '${t['nomorAntrean']}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 44,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (t['namaPasien'] != null)
                          Tooltip(
                            message: '${t['namaPasien']}',
                            child: Text(
                              '${t['namaPasien']}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        const SizedBox(height: 8),
                        StatusBadge(t['status']),
                      ],
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (active.isEmpty)
                      FilledButton.icon(
                        onPressed: busy || snapshot == null
                            ? null
                            : () => action('/queue/panggil'),
                        icon: const Icon(Icons.campaign_outlined, size: 20),
                        label: operationLabel(
                          '/queue/panggil',
                          'Panggil berikutnya',
                        ),
                      ),
                    for (final t in active) ...[
                      if (t['status'] == 'DIPANGGIL')
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            lightButton(
                              'Panggil Ulang',
                              '/queue/${t['tiketId']}/panggil-ulang',
                            ),
                            lightButton(
                              'Lewati',
                              '/queue/${t['tiketId']}/lewati',
                            ),
                            FilledButton(
                              onPressed: busy
                                  ? null
                                  : () => action(
                                      '/queue/${t['tiketId']}/mulai-pelayanan',
                                    ),
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
                              : () => action(
                                  '/queue/${t['tiketId']}/selesaikan-pelayanan',
                                ),
                          child: operationLabel(
                            '/queue/${t['tiketId']}/selesaikan-pelayanan',
                            'Selesaikan Pelayanan',
                          ),
                        ),
                    ],
                    const SizedBox(height: 10),
                    const Text(
                      'Pemilihan tiket mengikuti prioritas Queue Engine.',
                      style: TextStyle(color: QueueBStyle.mint, fontSize: 11),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
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

  Widget checkInPanel() => RepaintBoundary(
    key: const ValueKey('staff-qr-panel'),
    child: StaffPanel(
      title: 'QR Check-in Otomatis',
      icon: Icons.qr_code_scanner_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Pindai QR pasien untuk langsung memasukkannya ke antrean.',
            style: TextStyle(fontSize: 12, color: QueueBStyle.muted),
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, box) {
              final scanButton = FilledButton.icon(
                onPressed: busy ? null : scan,
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Mulai Pindai QR'),
              );
              final manual = ExpansionTile(
                key: const ValueKey('staff-manual-qr'),
                initiallyExpanded: manualQrOpen,
                onExpansionChanged: (v) => setState(() => manualQrOpen = v),
                tilePadding: EdgeInsets.zero,
                title: const Text(
                  'Input Manual',
                  style: TextStyle(fontSize: 13),
                ),
                children: [
                  TextField(
                    controller: qr,
                    enabled: !busy,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(
                      labelText: 'Payload QR (SQ1…)',
                      prefixIcon: Icon(Icons.qr_code),
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: busy
                        ? null
                        : () async {
                            try {
                              await submitQr(qr.text);
                            } catch (_) {
                              /* Visible error; no optimistic status. */
                            }
                          },
                    child: const Text('Proses QR & Masuk Antrean'),
                  ),
                ],
              );
              return box.maxWidth >= 850
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 4, child: scanButton),
                        const SizedBox(width: 32),
                        Expanded(flex: 6, child: manual),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [scanButton, manual],
                    );
            },
          ),
          if (busy && pendingPath == '/check-in/auto-antrean')
            const LinearProgressIndicator(),
          if (lastScan != null) ...[
            const SizedBox(height: 8),
            StaffScanResult(result: lastScan!),
          ],
        ],
      ),
    ),
  );
}
