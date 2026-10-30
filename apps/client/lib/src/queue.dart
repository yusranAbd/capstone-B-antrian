import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'api.dart';
import 'config.dart';
import 'features/staff/application/staff_queue_bloc.dart';
import 'features/staff/application/staff_queue_event.dart';
import 'features/staff/application/staff_queue_state.dart';
import 'features/staff/data/staff_queue_repository.dart';
import 'features/staff/models/staff_queue_models.dart';
import 'staff_qr_scanner.dart';
import 'widgets.dart';
import 'mobile_ui.dart';
import 'staff_ui.dart';
import 'staff_v4.dart';
import 'queueb_motion.dart';
import 'queueb_value_motion.dart';

class QueuePage extends StatefulWidget {
  const QueuePage({
    super.key,
    required this.api,
    this.headerBuilder,
    this.repository,
  });
  final QueueApi api;
  final StaffQueueRepository? repository;
  final PreferredSizeWidget Function(Widget context)? headerBuilder;
  @override
  State<QueuePage> createState() => _QueuePageState();
}

class _QueuePageState extends State<QueuePage> with WidgetsBindingObserver {
  late final repository = widget.repository ?? StaffQueueRepository(widget.api);
  late final bloc = StaffQueueBloc(repository);
  final search = TextEditingController();
  DialogRoute<void>? _scanRoute;
  DialogRoute<void>? _detailRoute;
  NavigatorState? _scannerNavigator;
  StaffQueueState get state => bloc.state;
  List<Json> get validAssignments => state.assignments;
  Json? get selectedRoom => state.room;
  String? get roomId => state.roomId;
  Json? get snapshot => state.snapshot;
  List<Json> get active => state.active;
  List<Json> get patients => state.patients;
  List<Json> get schedules => state.schedules;
  bool get scheduleLoading => state.scheduleLoading;
  bool get scheduleFailed => state.scheduleFailed;
  bool get loading => state.loading;
  bool get busy => state.blocked;
  String? get error => state.error;
  String? get message => state.message;
  int get followupPage => state.page;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(bloc.refresh(assignments: true));
  }

  Future<void> loadAssignments() => bloc.refresh(assignments: true);
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(bloc.refresh());
  }

  Future<void> action(String path) async {
    final parts = path.split('/');
    final operation = StaffOperation.values
        .where((o) => o.route == parts.last)
        .first;
    try {
      await bloc.execute(
        operation,
        ticketId: parts.length == 4 ? parts[2] : null,
      );
    } on ApiException {
      // Feedback comes from feature state; no transport or snapshot lives here.
    }
  }

  Future<Json> submitQr(String value) =>
      bloc.execute(StaffOperation.scan, qr: value.trim());
  Future<void> scan() async {
    final navigator = Navigator.of(context, rootNavigator: true);
    final route = DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => StaffQrScanner(onScan: submitQr),
    );
    _scanRoute = route;
    _scannerNavigator = navigator;
    try {
      await navigator.push(route);
    } finally {
      if (identical(_scanRoute, route)) _scanRoute = null;
    }
  }

  void _closeDialogs() {
    final routes = [_scanRoute, _detailRoute], navigator = _scannerNavigator;
    _scanRoute = null;
    _detailRoute = null;
    scheduleMicrotask(() {
      for (final route in routes) {
        if (navigator != null && navigator.mounted && route?.isActive == true) {
          navigator.removeRoute(route!);
        }
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _closeDialogs();
    unawaited(bloc.close());
    if (widget.repository == null) repository.dispose();
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
          onChanged: state.busy || loading
              ? null
              : (value) {
                  if (value == null) return;
                  search.clear();
                  bloc.add(StaffRoomSelected(value));
                },
        ),
      ),
      IconButton(
        tooltip: 'Muat ulang penugasan',
        onPressed: state.busy || loading ? null : loadAssignments,
        icon: const Icon(Icons.refresh, size: 20),
      ),
    ],
  );
  @override
  Widget build(BuildContext context) => BlocProvider.value(
    value: bloc,
    child: BlocConsumer<StaffQueueBloc, StaffQueueState>(
      // Connection-only changes rebuild the status selector below.
      buildWhen: (previous, next) =>
          previous.liveStatus == next.liveStatus ||
          previous.roomId != next.roomId ||
          previous.load != next.load ||
          previous.command != next.command,
      listenWhen: (previous, next) =>
          (previous.load != next.load && next.load == StaffLoad.ended) ||
          previous.roomId != next.roomId ||
          previous.date != next.date,
      listener: (context, value) {
        search.clear();
        _closeDialogs();
      },
      builder: (context, _) => buildPortal(context),
    ),
  );
  void rowAction(Json row, String route) {
    if (route == 'detail') {
      final navigator = Navigator.of(context, rootNavigator: true);
      final detail = DialogRoute<void>(
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
      _detailRoute = detail;
      _scannerNavigator = navigator;
      unawaited(
        navigator.push(detail).whenComplete(() {
          if (identical(_detailRoute, detail)) _detailRoute = null;
        }),
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

  Widget buildPortal(BuildContext context) => Theme(
    data: StaffStyle.theme,
    child: Builder(
      builder: (context) => Scaffold(
        appBar: widget.headerBuilder?.call(roomChoice()),
        floatingActionButton: selectedRoom == null
            ? null
            : FloatingActionButton.extended(
                key: const ValueKey('staff-scan-fab'),
                onPressed: busy || loading || snapshot == null ? null : scan,
                tooltip: 'Pindai QR pasien',
                icon: const Icon(Icons.qr_code_scanner_rounded),
                label: const Text('Pindai QR'),
              ),
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
            final mainHeight = (box.maxHeight - 264).clamp(320.0, 560.0);
            return SingleChildScrollView(
              key: const ValueKey('staff-page-scroll'),
              padding: EdgeInsets.fromLTRB(
                wide ? 16 : 12,
                wide ? 16 : 12,
                wide ? 16 : 12,
                room == null ? 16 : 88,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.headerBuilder == null) roomChoice(),
                  if (loading)
                    const LinearProgressIndicator(
                      semanticsLabel: 'Memuat penugasan',
                    ),
                  if (state.busy)
                    const LinearProgressIndicator(
                      semanticsLabel: 'Memproses tindakan',
                    ),
                  if (error != null) MobileNotice(error!, error: true),
                  QueueBConfirmedFeedback(
                    key: const ValueKey('staff-command-feedback'),
                    // Confirmed is emitted only after the existing REST drain.
                    // Do not gate on synchronized/loading: polling changes them
                    // while retaining this same confirmed command feedback.
                    confirmed:
                        state.command == StaffCommandStatus.confirmed &&
                        message != null,
                    child: message == null
                        ? const SizedBox.shrink()
                        : MobileNotice(message!),
                  ),
                  if (room == null && !loading)
                    const StaffPanel(
                      title: 'Ruang pelayanan',
                      icon: Icons.meeting_room_outlined,
                      child: StaffEmpty(
                        'Tidak ada penugasan aktif untuk hari ini. Hubungi ADMIN untuk penugasan loket.',
                      ),
                    ),
                  if (room != null) ...[
                    doctor,
                    const SizedBox(height: 16),
                    if (wide)
                      SizedBox(
                        height: mainHeight,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(flex: 54, child: waitingPanel(context)),
                            const SizedBox(width: 16),
                            Expanded(
                              flex: 46,
                              child: servicePanel(context, height: mainHeight),
                            ),
                          ],
                        ),
                      )
                    else ...[
                      servicePanel(context),
                      const SizedBox(height: 12),
                      SizedBox(height: 450, child: waitingPanel(context)),
                    ],
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
          BlocSelector<StaffQueueBloc, StaffQueueState, String>(
            selector: (state) => state.liveStatus,
            builder: (context, liveStatus) => Tooltip(
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
          ),
          IconButton(
            tooltip: 'Muat ulang antrean',
            onPressed: state.busy ? null : () => bloc.refresh(),
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
                          bloc.add(StaffPageSelected(followupPage - 1));
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
                          bloc.add(StaffPageSelected(followupPage + 1));
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
                  padding: const EdgeInsets.all(12),
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
                            fontSize: 36,
                            height: 1.2,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Belum ada tiket aktif',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
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
                        QueueBValueMotion(
                          value: t['nomorAntrean'],
                          scope: selectedRoom?['id'],
                          child: Text(
                            '${t['nomorAntrean']}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 40,
                              fontWeight: FontWeight.w800,
                            ),
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
    if (!state.busy || !path.endsWith('/${state.pending?.route}')) {
      return Text(text);
    }
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
}
