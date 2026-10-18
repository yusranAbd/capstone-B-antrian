import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'api.dart';
import 'config.dart';
import 'display_board.dart';
import 'display_fullscreen.dart';
import 'mobile_ui.dart';
import 'realtime.dart';
import 'widgets.dart';

class AnnouncementGate {
  bool _initialized = false;
  final _seen = <String>{};

  /// Reconnect/resume/manual refresh establish a silent baseline, even if an
  /// offline CALL is different from the last announcement seen before the gap.
  void rebase() => _initialized = false;

  String? observe(Json? announcement, {required bool callSignal}) {
    final id = announcement?['peristiwaId'] as String?;
    final seen = id != null && _seen.contains(id);
    if (id != null) {
      _seen.add(id);
      if (_seen.length > 256) _seen.remove(_seen.first);
    }
    if (!_initialized) {
      _initialized = true;
      return null;
    }
    if (id == null || seen || !callSignal) return null;
    if (announcement?['aksi'] != null &&
        !['CALL', 'RECALL'].contains(announcement?['aksi'])) {
      return null;
    }
    return announcement?['teks'] as String?;
  }
}

class DisplayPage extends StatefulWidget {
  const DisplayPage({super.key, required this.api, required this.onExit});
  final QueueApi api;
  final VoidCallback onExit;
  @override
  State<DisplayPage> createState() => _DisplayPageState();
}

class _DisplayPageState extends State<DisplayPage> with WidgetsBindingObserver {
  final service = TextEditingController(), token = TextEditingController();
  final form = GlobalKey<FormState>();
  final tts = FlutterTts();
  final fullscreen = DisplayFullscreen();
  AnnouncementGate gate = AnnouncementGate();
  SnapshotLoader? loader;
  RealtimeFeed? feed;
  Timer? poll, clock;
  Json? snapshot;
  String? error, audioError;
  String status = 'Menghubungkan…';
  bool connected = false, audio = false, audioBusy = false, rejected = false;
  int connectionEpoch = 0, fetchedEpoch = 0;
  int speechEpoch = 0;
  int callSignals = 0, fetchedSignals = 0, consumedSignals = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    fullscreen.addListener(fullscreenChanged);
    clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && connected) setState(() {});
    });
    tts.setErrorHandler((message) {
      // Cancelling the preceding announcement is expected during RECALL/mute.
      if (!['canceled', 'interrupted'].contains('$message')) speechFailed();
    });
  }

  void fullscreenChanged() {
    if (mounted) setState(() {});
  }

  Future<void> stopSpeech() async {
    try {
      await tts.stop();
    } catch (_) {
      // An optional/absent speech engine must not break visual display cleanup.
    }
  }

  void rebase() {
    connectionEpoch++;
    gate.rebase();
    callSignals = fetchedSignals = consumedSignals = 0;
    speechEpoch++;
    unawaited(stopSpeech());
  }

  void rejectDevice() {
    rebase();
    feed?.dispose();
    loader?.dispose();
    poll?.cancel();
    if (mounted) {
      setState(() {
        rejected = true;
        audio = false;
        snapshot = null;
        error = 'Token perangkat tidak valid atau akses layanan ditolak.';
      });
    }
  }

  void connect() {
    if (!form.currentState!.validate()) return;
    final id = service.text.trim(), credential = token.text.trim();
    setState(() {
      connected = true;
      snapshot = null;
      error = null;
      audio = false;
      audioError = null;
      rejected = false;
      status = widget.api.config.realtime
          ? 'Menghubungkan…'
          : 'Sinkronisasi berkala';
      connectionEpoch++;
      speechEpoch++;
      callSignals = fetchedSignals = consumedSignals = 0;
      gate = AnnouncementGate();
    });
    loader = SnapshotLoader(
      fetch: () async {
        fetchedEpoch = connectionEpoch;
        fetchedSignals = callSignals;
        return object(
          await widget.api.request(
            'GET',
            '/display/$id/snapshot',
            authenticated: false,
            displayToken: credential,
          ),
        );
      },
      onData: (data) {
        if (fetchedEpoch != connectionEpoch || !connected || rejected) return;
        if (data['versiSkema'] != 1) {
          setState(() => error = 'Versi snapshot tidak didukung.');
          return;
        }
        final announcement = data['pengumumanTerakhir'] == null
            ? null
            : object(data['pengumumanTerakhir']);
        // An event during this fetch belongs to the next dirty refresh.
        final speech = fetchedSignals == callSignals
            ? gate.observe(
                announcement,
                callSignal: fetchedSignals > consumedSignals,
              )
            : null;
        consumedSignals = fetchedSignals;
        if (mounted && connected) {
          setState(() {
            snapshot = data;
            error = null;
          });
        }
        if (audio && speech != null) speak(speech);
      },
      onError: (e) {
        if (!mounted || !connected || fetchedEpoch != connectionEpoch) return;
        if (e is ApiException && [401, 403].contains(e.status)) {
          rejectDevice();
        } else {
          rebase();
          setState(
            () => error =
                'Snapshot belum dapat dimuat. Periksa koneksi perangkat.',
          );
        }
      },
    );
    feed = RealtimeFeed(
      api: widget.api,
      layananId: id,
      displayToken: credential,
      onRefresh: () => loader?.refresh(),
      onStatus: (s) {
        if (!connected || rejected) return;
        rebase();
        if (mounted) setState(() => status = s);
        if (s.startsWith('Token perangkat ditolak')) rejectDevice();
      },
      onEvent: (e) {
        if (e['perluPeriksaPengumuman'] == true) callSignals++;
      },
    );
    // Live bootstrap waits for display:ready. REST polling remains available
    // during a network outage, without announcing offline history.
    if (!widget.api.config.realtime) loader!.refresh();
    poll = Timer.periodic(
      const Duration(seconds: 15),
      (_) => loader?.refresh(),
    );
    token.clear();
  }

  void speechFailed() {
    speechEpoch++;
    if (mounted) {
      setState(() {
        audio = false;
        audioError = 'Suara tidak tersedia. Gunakan pengumuman visual.';
      });
    }
  }

  Future<bool> speak(String text) async {
    final epoch = ++speechEpoch;
    bool current() => mounted && connected && !rejected && epoch == speechEpoch;
    try {
      await stopSpeech();
      if (!current()) return false;
      final available = await tts.isLanguageAvailable('id-ID');
      if (!current()) return false;
      if (available != true && available != 1) {
        throw StateError('Indonesian voice is unavailable');
      }
      final language = await tts.setLanguage('id-ID');
      if (!current()) return false;
      if (language == 0 || language == false) {
        throw StateError('Speech language rejected');
      }
      final result = await tts.speak(text);
      if (result == 0 || result == false) throw StateError('Speech rejected');
      return mounted && epoch == speechEpoch;
    } catch (_) {
      if (current()) speechFailed();
      return false;
    }
  }

  Future<void> toggleAudio() async {
    if (audioBusy) return;
    setState(() => audioBusy = true);
    try {
      if (audio) {
        speechEpoch++;
        await stopSpeech();
        if (mounted) setState(() => audio = false);
      } else if (await speak('Suara pengumuman QueueB aktif.')) {
        if (mounted) {
          setState(() {
            audio = true;
            audioError = null;
          });
        }
      }
    } catch (_) {
      speechFailed();
    } finally {
      if (mounted) setState(() => audioBusy = false);
    }
  }

  void disconnect() {
    speechEpoch++;
    feed?.dispose();
    loader?.dispose();
    poll?.cancel();
    unawaited(stopSpeech());
    setState(() {
      connected = false;
      snapshot = null;
      callSignals = fetchedSignals = consumedSignals = 0;
      audio = false;
      rejected = false;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && connected && !rejected) {
      rebase();
      loader?.refresh();
    } else if (state != AppLifecycleState.resumed && connected) {
      rebase();
    }
  }

  @override
  void dispose() {
    speechEpoch++;
    WidgetsBinding.instance.removeObserver(this);
    feed?.dispose();
    loader?.dispose();
    poll?.cancel();
    clock?.cancel();
    fullscreen.removeListener(fullscreenChanged);
    fullscreen.dispose();
    unawaited(stopSpeech());
    service.dispose();
    token.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: QueueBStyle.theme,
    child: connected
        ? Scaffold(
            body: DisplayBoard(
              snapshot: snapshot,
              now: widget.api.config.now,
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
                rebase();
                loader?.refresh();
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
                    ),
                  ),
                ),
              ),
            ),
          ),
  );
}
