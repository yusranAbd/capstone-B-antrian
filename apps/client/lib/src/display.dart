import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'api.dart';
import 'config.dart';
import 'realtime.dart';
import 'widgets.dart';

class AnnouncementGate {
  bool _initialized = false;
  String? _last;
  String? observe(Json? announcement, {required bool callSignal}) {
    final id = announcement?['peristiwaId'] as String?;
    if (!_initialized) {
      _initialized = true;
      _last = id;
      return null;
    }
    if (id == null || id == _last) return null;
    _last = id;
    return callSignal ? (announcement?['teks'] as String?) : null;
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
  AnnouncementGate gate = AnnouncementGate();
  SnapshotLoader? loader;
  RealtimeFeed? feed;
  Timer? poll;
  Json? snapshot;
  String? error, audioError;
  String status = 'Menghubungkan…';
  bool connected = false, audio = false, audioBusy = false;
  int speechEpoch = 0;
  int callSignals = 0, fetchedSignals = 0, consumedSignals = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    tts.setErrorHandler((message) {
      // Cancelling the preceding announcement is expected during RECALL/mute.
      if (!['canceled', 'interrupted'].contains('$message')) speechFailed();
    });
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
      speechEpoch++;
      callSignals = fetchedSignals = consumedSignals = 0;
      gate = AnnouncementGate();
    });
    loader = SnapshotLoader(
      fetch: () async {
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
        if (mounted) setState(() => error = '$e');
        if (e is ApiException && [401, 403].contains(e.status)) {
          feed?.dispose();
          poll?.cancel();
        }
      },
    );
    feed = RealtimeFeed(
      api: widget.api,
      layananId: id,
      displayToken: credential,
      onRefresh: () => loader?.refresh(),
      onStatus: (s) {
        if (mounted) setState(() => status = s);
      },
      onEvent: (e) {
        if (e['perluPeriksaPengumuman'] == true) callSignals++;
      },
    );
    loader!.refresh();
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
    try {
      await tts.stop();
      final available = await tts.isLanguageAvailable('id-ID');
      if (available != true && available != 1) {
        throw StateError('Indonesian voice is unavailable');
      }
      await tts.setLanguage('id-ID');
      final result = await tts.speak(text);
      if (result == 0 || result == false) throw StateError('Speech rejected');
      return mounted && epoch == speechEpoch;
    } catch (_) {
      speechFailed();
      return false;
    }
  }

  Future<void> toggleAudio() async {
    if (audioBusy) return;
    setState(() => audioBusy = true);
    try {
      if (audio) {
        speechEpoch++;
        await tts.stop();
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
    tts.stop();
    setState(() {
      connected = false;
      snapshot = null;
      callSignals = fetchedSignals = consumedSignals = 0;
      audio = false;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) loader?.refresh();
  }

  @override
  void dispose() {
    speechEpoch++;
    WidgetsBinding.instance.removeObserver(this);
    feed?.dispose();
    loader?.dispose();
    poll?.cancel();
    tts.stop();
    service.dispose();
    token.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
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
    body: !connected
        ? Center(
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
                                !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(v.trim())
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
          )
        : ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                label(object(snapshot?['layanan'])),
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              Text('$status · ${dateOnly(snapshot?['tanggalPelayanan'])}'),
              if (error != null || audioError != null)
                Notice(error ?? audioError!, error: true),
              Wrap(
                spacing: 16,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'Menunggu: ${snapshot?['totalMenunggu'] ?? '—'}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  OutlinedButton.icon(
                    onPressed: () => loader?.refresh(),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Muat ulang'),
                  ),
                  OutlinedButton.icon(
                    onPressed: audioBusy ? null : toggleAudio,
                    icon: Icon(audio ? Icons.volume_up : Icons.volume_off),
                    label: Text(audio ? 'Matikan suara' : 'Aktifkan suara'),
                  ),
                ],
              ),
              if (snapshot == null) const LinearProgressIndicator(),
              if (snapshot?['pengumumanTerakhir'] != null)
                Section(
                  title: 'Pengumuman',
                  child: Text(
                    '${object(snapshot!['pengumumanTerakhir'])['teks']}',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
              Wrap(
                spacing: 20,
                runSpacing: 20,
                children: [
                  for (final room in rows(snapshot?['loket']))
                    SizedBox(
                      width: 300,
                      child: Section(
                        title: label(room),
                        subtitle: 'Loket ${room['kode']}',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (rows(room['tiketAktif']).isEmpty)
                              const Text('Siap melayani'),
                            for (final t in rows(room['tiketAktif'])) ...[
                              Text(
                                '${t['nomorAntrean']}',
                                style: Theme.of(context)
                                    .textTheme
                                    .displayMedium,
                              ),
                              stateChip(t['status']),
                            ],
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
  );
}
