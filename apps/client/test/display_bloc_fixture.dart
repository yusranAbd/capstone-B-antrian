import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:queueb_client/src/api.dart';
import 'package:queueb_client/src/config.dart';
import 'package:queueb_client/src/display_selection.dart';
import 'package:queueb_client/src/features/display/application/display_device_cubit.dart';
import 'package:queueb_client/src/features/display/application/display_monitor_bloc.dart';
import 'package:queueb_client/src/features/display/data/display_device_repository.dart';
import 'package:queueb_client/src/features/display/data/display_monitor_repository.dart';
import 'package:queueb_client/src/features/display/models/display_models.dart';
import 'package:queueb_client/src/features/display/services/display_audio_controller.dart';

const displayA = '00000000-0000-4000-8000-000000000001';
const displayB = '00000000-0000-4000-8000-000000000002';
const displayC = '00000000-0000-4000-8000-000000000003';
const clinicA = '10000000-0000-4000-8000-000000000001';
const clinicB = '10000000-0000-4000-8000-000000000002';
const activationFixture = '123456789012';

class DisplayGate {
  final entered = Completer<void>(), release = Completer<void>();
}

class FakeDisplaySpeech implements DisplaySpeechEngine {
  void Function(dynamic)? callback;
  final spoken = <String>[], languages = <String>[];
  int stops = 0;
  bool fail = false, noVoice = false;
  Completer<void>? voiceGate, speechGate;
  @override
  void errors(void Function(dynamic)? value) => callback = value;
  @override
  Future<dynamic> stop() async {
    stops++;
    return 1;
  }

  @override
  Future<dynamic> available(String value) async {
    languages.add(value);
    await voiceGate?.future;
    return !noVoice;
  }

  @override
  Future<dynamic> language(String value) async {
    languages.add(value);
    return 1;
  }

  @override
  Future<dynamic> speak(String text) async {
    if (fail) throw StateError('fixture synthesis failed');
    spoken.add(text);
    await speechGate?.future;
    return 1;
  }
}

class FakeDisplayFeed {
  FakeDisplayFeed(
    this.scope,
    this.refresh,
    this.status,
    this.event,
    this.onDispose,
  );
  final DisplayScope scope;
  final VoidCallback refresh, onDispose;
  final ValueChanged<String> status;
  final ValueChanged<Json> event;
  bool disposed = false;
  void ready() {
    status('Realtime terhubung');
    refresh();
  }

  void changed(String id, String action, {String? service}) {
    event({
      'versiSkema': 1,
      'layananId': service ?? scope.serviceId,
      'eventId': id,
      'aksi': action,
      'perluPeriksaPengumuman': ['CALL', 'RECALL'].contains(action),
    });
    refresh();
  }

  void dispose() {
    if (disposed) return;
    disposed = true;
    onDispose();
  }
}

class FakeDisplayTimer implements Timer {
  Duration? interval;
  void Function(Timer)? callback;
  @override
  bool isActive = true;
  @override
  int tick = 0;
  void fire() {
    if (isActive) {
      tick++;
      callback?.call(this);
    }
  }

  @override
  void cancel() => isActive = false;
}

class DisplayBackend {
  final calls = <http.Request>[];
  final codes = <String, String>{
    activationFixture: displayA,
    '223456789012': displayB,
    '323456789012': displayC,
  };
  final clinics = <String, String>{
    displayA: clinicA,
    displayB: clinicB,
    displayC: clinicA,
  };
  final denied = <String>{};
  final failures = <String, int>{};
  final _gates = <String, Queue<DisplayGate>>{};
  final snapshots = <String, Json>{};
  final activeReads = <String, int>{}, maxReads = <String, int>{};
  String? ambient;
  bool losePair = false, malformedPair = false;
  Json device(String id) => {
    'id': id,
    'layananId': clinics[id],
    'nama': 'TV $id',
    'aktif': true,
    'layanan': {
      'id': clinics[id],
      'nama': 'Poli ${clinics[id] == clinicA ? 'A' : 'B'}',
      'aktif': true,
    },
  };
  Json snapshot(String id) => snapshots[id] ??= {
    'versiSkema': 1,
    'tanggalPelayanan': '2026-10-29',
    'diperolehPada': '2026-10-29T01:00:00Z',
    'layanan': {
      'id': clinics[id],
      'nama': 'Poli ${clinics[id] == clinicA ? 'A' : 'B'}',
    },
    'modeNama': 'SAMAR',
    'totalMenunggu': 1,
    'totalAntrianPasien': 2,
    'menunggu': [
      {'nomorAntrean': 'A-001', 'namaPasien': 'Pasien A.'},
    ],
    'antrianPasien': [
      {
        'nomorAntrean': 'A-001',
        'namaPasien': 'Pasien A.',
        'status': 'MENUNGGU',
      },
      {
        'nomorAntrean': 'A-002',
        'namaPasien': 'Pasien B.',
        'status': 'DILEWATI',
      },
    ],
    'loket': [
      {
        'kode': 'R1',
        'nama': 'Ruang 1',
        'tiketAktif': [
          {
            'nomorAntrean': 'A-003',
            'namaPasien': 'Pasien C.',
            'status': 'DIPANGGIL',
          },
        ],
      },
    ],
    'pengumumanTerakhir': {
      'peristiwaId': 'history',
      'aksi': 'CALL',
      'teks': 'Panggilan historis.',
      'kodeLoket': 'R1',
      'nomorAntrean': 'A-003',
    },
  };
  void announcement(String device, String id, {String action = 'CALL'}) {
    snapshot(device)['pengumumanTerakhir'] = {
      'peristiwaId': id,
      'aksi': action,
      'teks': 'Panggilan $id untuk Pasien C.',
      'kodeLoket': 'R1',
      'nomorAntrean': 'A-003',
    };
  }

  DisplayGate block(String path, [String method = 'GET']) {
    final gate = DisplayGate();
    (_gates['$method $path'] ??= Queue()).add(gate);
    return gate;
  }

  int count(String path, [String method = 'GET']) => calls
      .where((r) => r.method == method && r.url.path == '/api/v1$path')
      .length;
  Future<http.Response> handle(http.Request request) async {
    calls.add(request);
    final path = request.url.path.replaceFirst('/api/v1', ''),
        key =
            '${request.method} ${request.url.path.replaceFirst('/api/v1', '')}';
    final id = request.headers['x-display-device-id'] ?? ambient;
    final gates = _gates[key], failure = failures[key];
    final gate = gates != null && gates.isNotEmpty ? gates.removeFirst() : null;
    dynamic data;
    var code = failure ?? 200;
    if (path == '/display/pairing') {
      final body = object(jsonDecode(request.body)),
          selected = codes[object(jsonDecode(request.body))['kode']];
      if (selected == null) {
        code = 401;
      } else {
        ambient = selected;
        if (body['isolasiSesi'] == true) ambient = null;
        data = malformedPair ? {} : device(selected);
      }
    } else if (path == '/display/sesi') {
      if (id == null || denied.contains(id)) {
        code = 401;
      } else {
        data = device(id);
      }
    } else if (path == '/display/putuskan') {
      if (id != null && failure == null) denied.add(id);
      data = {'ok': true};
    } else if (path.endsWith('/snapshot')) {
      final selected = id ?? displayA;
      if (denied.contains(selected)) code = 401;
      data = jsonDecode(jsonEncode(snapshot(selected)));
      activeReads[selected] = (activeReads[selected] ?? 0) + 1;
      if ((maxReads[selected] ?? 0) < activeReads[selected]!) {
        maxReads[selected] = activeReads[selected]!;
      }
    }
    gate?.entered.complete();
    try {
      await gate?.release.future;
      if (path == '/display/pairing' && losePair) {
        throw http.ClientException('fixture response lost');
      }
      return http.Response(
        jsonEncode(
          code == 200
              ? data
              : {'message': 'PRIVATE ERROR token $activationFixture'},
        ),
        code,
      );
    } finally {
      if (path.endsWith('/snapshot')) {
        final selected = id ?? displayA;
        activeReads[selected] = activeReads[selected]! - 1;
      }
    }
  }
}

class DisplayFixture {
  DisplayFixture({
    DisplayBackend? backend,
    String? id = displayA,
    bool realtime = false,
    FakeDisplayTimer? timer,
  }) {
    this.backend = backend ?? DisplayBackend();
    selection = MemoryDisplaySelection(value: id);
    api = QueueApi(
      config: AppConfig(
        apiBaseUrl: 'http://fixture.invalid/api/v1',
        realtime: realtime,
      ),
      client: MockClient(this.backend.handle),
    );
    devices = DisplayDeviceRepository(api, selection);
    device = DisplayDeviceCubit(devices);
    audio = DisplayAudioController(engine: speech);
    repository = DisplayMonitorRepository(devices, feedFactory: feedFactory);
    monitor = DisplayMonitorBloc(
      repository,
      audio,
      polling: timer != null,
      periodicTimer: timer == null
          ? null
          : (duration, callback) {
              timer.interval = duration;
              timer.callback = callback;
              return timer;
            },
    );
  }
  late final DisplayBackend backend;
  late final QueueApi api;
  late final MemoryDisplaySelection selection;
  late final DisplayDeviceRepository devices;
  late final DisplayDeviceCubit device;
  late final DisplayMonitorRepository repository;
  late final DisplayMonitorBloc monitor;
  late final DisplayAudioController audio;
  final speech = FakeDisplaySpeech();
  final feeds = <FakeDisplayFeed>[];
  int activeFeeds = 0;
  VoidCallback feedFactory(
    DisplayScope scope,
    VoidCallback refresh,
    ValueChanged<String> status,
    ValueChanged<Json> event,
  ) {
    activeFeeds++;
    final feed = FakeDisplayFeed(
      scope,
      refresh,
      status,
      event,
      () => activeFeeds--,
    );
    feeds.add(feed);
    return feed.dispose;
  }

  Future<void> load() async {
    await device.restore();
    if (devices.scope != null) {
      await until((s) => s.snapshot != null || s.error != null);
    }
  }

  Future<DisplayMonitorState> until(
    bool Function(DisplayMonitorState) predicate,
  ) {
    if (predicate(monitor.state)) return Future.value(monitor.state);
    return monitor.stream.firstWhere(predicate);
  }

  Future<void> dispose() async {
    await monitor.close();
    await device.close();
    devices.dispose();
    audio.dispose();
    api.dispose();
  }
}
