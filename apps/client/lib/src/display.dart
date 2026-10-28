import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'api.dart';
import 'config.dart';
import 'display_board.dart';
import 'display_fullscreen.dart';
import 'display_selection.dart';
import 'features/display/application/display_device_cubit.dart';
import 'features/display/application/display_monitor_bloc.dart';
import 'features/display/data/display_device_repository.dart';
import 'features/display/data/display_monitor_repository.dart';
import 'features/display/models/display_models.dart';
import 'features/display/services/display_audio_controller.dart';
import 'mobile_ui.dart';
import 'widgets.dart';

export 'features/display/services/announcement_gate.dart' show AnnouncementGate;

class DisplayPage extends StatefulWidget {
  const DisplayPage({
    super.key,
    required this.api,
    required this.onExit,
    this.selection,
    this.deviceRepository,
    this.audioController,
    this.feedFactory,
  });
  final QueueApi api;
  final DisplaySelection? selection;
  final DisplayDeviceRepository? deviceRepository;
  final DisplayAudioController? audioController;
  final DisplayFeedFactory? feedFactory;
  final VoidCallback onExit;
  @override
  State<DisplayPage> createState() => _DisplayPageState();
}

class _DisplayPageState extends State<DisplayPage> with WidgetsBindingObserver {
  final service = TextEditingController(),
      token = TextEditingController(),
      activation = TextEditingController();
  final form = GlobalKey<FormState>();
  final fullscreen = DisplayFullscreen();
  late final selection =
      widget.selection ?? createDisplaySelection(widget.api.config.apiBase);
  late final devices =
      widget.deviceRepository ?? DisplayDeviceRepository(widget.api, selection);
  late final device = DisplayDeviceCubit(devices);
  late final audioController =
      widget.audioController ?? DisplayAudioController();
  late final monitor = DisplayMonitorBloc(
    DisplayMonitorRepository(devices, feedFactory: widget.feedFactory),
    audioController,
  );
  late final displayClock = ValueNotifier<DateTime>(widget.api.config.now);
  Timer? clock;
  bool legacy = false;
  bool get connected => device.state.connected;
  bool get activating => device.state.phase == DisplayDevicePhase.pairing;
  bool get pairingBlocked =>
      activating ||
      restoringDevice ||
      device.state.phase == DisplayDevicePhase.uncertain;
  bool get restoringDevice =>
      device.state.phase == DisplayDevicePhase.restoring;
  bool get rejected =>
      device.state.phase == DisplayDevicePhase.rejected ||
      monitor.state.rejected;
  bool get audio => audioController.enabled;
  bool get audioBusy => audioController.busy;
  String? get audioError => audioController.error;
  String? get error => device.state.error ?? monitor.state.error;
  String get status => monitor.state.status;
  Json? get snapshot => identical(device.state.scope, monitor.state.scope)
      ? monitor.state.snapshot
      : null;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    fullscreen.addListener(fullscreenChanged);
    monitor; // Establish listeners before device restoration activates a scope.
    unawaited(device.restore());
    clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && connected) displayClock.value = widget.api.config.now;
    });
  }

  Future<void> restoreDevice() => device.restore();
  Future<void> pairDevice() async {
    if (pairingBlocked || !form.currentState!.validate()) return;
    final pending = device.pair(activation.text.trim());
    activation.clear();
    await pending;
  }

  void connect() {
    if (!form.currentState!.validate()) return;
    device.legacy(service.text.trim(), token.text.trim());
    token.clear();
  }

  Future<void> disconnect() async {
    audioController.context(false);
    await device.disconnect();
    if (!mounted) return;
    if (devices.scope != null) audioController.context(true);
    activation.clear();
    token.clear();
  }

  void fullscreenChanged() {
    if (mounted) setState(() {});
  }

  Future<void> toggleAudio() => audioController.toggle();
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(monitor.resume());
    } else {
      monitor.pause();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(monitor.close());
    unawaited(device.close());
    if (widget.deviceRepository == null) devices.dispose();
    if (widget.audioController == null) audioController.dispose();
    clock?.cancel();
    displayClock.dispose();
    fullscreen.removeListener(fullscreenChanged);
    fullscreen.dispose();
    service.dispose();
    token.dispose();
    activation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MultiBlocProvider(
    providers: [
      BlocProvider.value(value: device),
      BlocProvider.value(value: monitor),
    ],
    child: BlocBuilder<DisplayDeviceCubit, DisplayDeviceState>(
      builder: (context, _) =>
          BlocBuilder<DisplayMonitorBloc, DisplayMonitorState>(
            builder: (context, _) => ListenableBuilder(
              listenable: audioController,
              builder: (context, _) => buildDisplay(context),
            ),
          ),
    ),
  );
  Widget buildDisplay(BuildContext context) => Theme(
    data: QueueBStyle.theme,
    child: connected
        ? Scaffold(
            body: DisplayBoard(
              snapshot: snapshot,
              now: widget.api.config.now,
              clock: displayClock,
              snapshotTime: widget.api.config
                  .instantLabel(snapshot?['diperolehPada'])
                  .split(' ')
                  .last,
              status: status,
              error: error,
              audioError: audioError,
              rejected: rejected,
              audio: audio,
              audioBusy: audioBusy,
              fullscreen: fullscreen.active,
              fullscreenSupported: fullscreen.supported,
              onRefresh: () {
                monitor.refresh(silent: true);
              },
              onAudio: toggleAudio,
              onConfigure: disconnect,
              onFullscreen: () async {
                try {
                  await fullscreen.toggle();
                } catch (_) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Fullscreen tidak tersedia. Gunakan mode layar penuh browser.',
                        ),
                      ),
                    );
                  }
                }
              },
            ),
          )
        : Scaffold(
            appBar: AppBar(
              title: const Text('QueueB · Public Display'),
              leading: IconButton(
                tooltip: 'Kembali ke login',
                onPressed: widget.onExit,
                icon: const Icon(Icons.arrow_back),
              ),
              actions: [
                if (connected)
                  TextButton(
                    onPressed: disconnect,
                    child: const Text('Ganti perangkat'),
                  ),
              ],
            ),
            body: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: SizedBox(
                  width: 520,
                  child: Form(
                    key: form,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.local_hospital_rounded,
                          size: 56,
                          color: QueueBStyle.teal,
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'Aktivasi Public Display',
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Tab ini belum dipasangkan. Setiap monitor/tab menggunakan perangkat sendiri. Minta kode sekali pakai dari ADMIN melalui Manajemen Display.',
                        ),
                        if (restoringDevice || activating)
                          const LinearProgressIndicator(),
                        if (error != null) Notice(error!, error: true),
                        if (!legacy) ...[
                          const SizedBox(height: 24),
                          TextFormField(
                            controller: activation,
                            keyboardType: TextInputType.number,
                            enableSuggestions: false,
                            autocorrect: false,
                            decoration: const InputDecoration(
                              labelText: 'Kode Aktivasi',
                              hintText: '12 digit dari ADMIN',
                              prefixIcon: Icon(Icons.key_outlined),
                            ),
                            validator: (v) =>
                                RegExp(r'^\d{12}$').hasMatch(v?.trim() ?? '')
                                ? null
                                : 'Masukkan 12 digit kode aktivasi.',
                            onFieldSubmitted: (_) => pairDevice(),
                          ),
                          const SizedBox(height: 24),
                          FilledButton.icon(
                            onPressed: pairingBlocked ? null : pairDevice,
                            icon: const Icon(Icons.tv),
                            label: const Text('Hubungkan Perangkat'),
                          ),
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: restoringDevice ? null : restoreDevice,
                            child: const Text('Periksa sesi tersimpan'),
                          ),
                        ],
                        TextButton(
                          onPressed: () => setState(() {
                            legacy = !legacy;
                          }),
                          child: Text(
                            legacy
                                ? 'Gunakan kode aktivasi'
                                : 'Konfigurasi lanjutan (token existing)',
                          ),
                        ),
                        if (legacy) ...[
                          const Notice(
                            'Gunakan ID layanan dan token perangkat dari pengelola server. Token tidak disimpan ke URL atau penyimpanan browser.',
                          ),
                          TextFormField(
                            controller: service,
                            decoration: const InputDecoration(
                              labelText: 'ID layanan',
                            ),
                            validator: (v) =>
                                v == null ||
                                    !RegExp(
                                      r'^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$',
                                    ).hasMatch(v.trim())
                                ? 'ID layanan UUID wajib diisi.'
                                : null,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: token,
                            obscureText: true,
                            enableSuggestions: false,
                            autocorrect: false,
                            decoration: const InputDecoration(
                              labelText: 'Token perangkat',
                            ),
                            validator: (v) =>
                                v == null ||
                                    !RegExp(r'^[a-fA-F0-9]{64}$')
                                        .hasMatch(v.trim())
                                ? 'Token wajib 64 karakter heksadesimal.'
                                : null,
                          ),
                          const SizedBox(height: 24),
                          FilledButton(
                            onPressed: connect,
                            child: const Text('Hubungkan display'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
  );
}
