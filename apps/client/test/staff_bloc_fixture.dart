import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:queueb_client/src/api.dart';
import 'package:queueb_client/src/config.dart';
import 'package:queueb_client/src/features/staff/application/staff_queue_bloc.dart';
import 'package:queueb_client/src/features/staff/application/staff_queue_state.dart';
import 'package:queueb_client/src/features/staff/data/staff_queue_repository.dart';
import 'package:queueb_client/src/features/staff/models/staff_queue_models.dart';

const staffRoomA = 'room-a', staffRoomB = 'room-b', staffTicket = 'ticket-a';
final staffQr = 'SQ1.${'A' * 43}';

class StaffGate {
  final entered = Completer<void>(), release = Completer<void>();
}

class StaffManualTimer implements Timer {
  Duration? interval;
  void Function(Timer)? callback;
  @override
  bool isActive = true;
  @override
  int tick = 0;
  void fire() {
    if (!isActive) return;
    tick++;
    callback?.call(this);
  }

  @override
  void cancel() => isActive = false;
}

class StaffFakeFeed {
  StaffFakeFeed(this.refresh, this.status, this.onDispose);
  final VoidCallback refresh, onDispose;
  final ValueChanged<String> status;
  bool disposed = false;
  void dispose() {
    if (disposed) return;
    disposed = true;
    onDispose();
  }
}

class StaffFixtureApi extends QueueApi {
  StaffFixtureApi()
    : super(
        config: AppConfig(
          apiBaseUrl: 'http://fixture.invalid/api/v1',
          realtime: false,
        ),
      ) {
    user = {'id': 'staff-a', 'peran': 'PETUGAS'};
    accessToken = 'fixture-only';
  }
  final calls =
      <({String method, String path, Json body, Map<String, String> query})>[];
  final failures = <String, Object>{};
  final _gates = <String, Queue<StaffGate>>{};
  final _waiters = <(String, int), Completer<void>>{};
  final activeReads = <String, int>{}, maxReads = <String, int>{};
  int snapshotSequence = 0;
  bool noAssignments = false, noSchedules = false, malformed = false;
  bool loseMutation = false, loseWithoutCommit = false;
  int pages = 1;
  String status = 'MENUNGGU', ticketRoom = staffRoomA;
  int version = 1;
  String? snapshotDate;
  Json room(String id) => {
    'id': id,
    'nama': id,
    'aktif': true,
    'layanan': {'id': 'clinic', 'nama': 'Poli Uji', 'aktif': true},
  };
  Json get ticket => {
    'tiketId': staffTicket,
    'nomorAntrean': 'U-001',
    'namaPasien': 'Pasien Uji',
    'status': status,
    'versi': version,
    'loketId': ticketRoom,
    'bisaAntreUlang': status == 'DILEWATI',
    'bisaMasukAntrean': status == 'CHECK_IN',
  };
  int count(String path, [String method = 'GET']) =>
      calls.where((c) => c.path == path && c.method == method).length;
  StaffGate block(String path, [String method = 'GET']) {
    final gate = StaffGate();
    (_gates['$method $path'] ??= Queue()).add(gate);
    return gate;
  }

  Future<void> waitCount(String path, int count) {
    if (this.count(path) >= count) return Future.value();
    return (_waiters[(path, count)] ??= Completer()).future;
  }

  void changeIdentity(String id, {String role = 'PETUGAS'}) {
    user = {'id': id, 'peran': role};
    notifyListeners();
  }

  @override
  Future<dynamic> request(
    String method,
    String path, {
    Json? body,
    Map<String, String>? query,
    bool authenticated = true,
    String? displayToken,
    String? displayDeviceId,
    List<int>? photoBytes,
    bool binary = false,
  }) async {
    final key = '$method $path';
    calls.add((
      method: method,
      path: path,
      body: body ?? {},
      query: query ?? {},
    ));
    for (final entry in _waiters.entries) {
      if (entry.key.$1 == path &&
          count(path) >= entry.key.$2 &&
          !entry.value.isCompleted) {
        entry.value.complete();
      }
    }
    final readKey = '$path:${query?['loketId']}';
    if (method == 'GET') {
      activeReads[readKey] = (activeReads[readKey] ?? 0) + 1;
      if ((maxReads[readKey] ?? 0) < activeReads[readKey]!) {
        maxReads[readKey] = activeReads[readKey]!;
      }
    }
    dynamic data;
    if (path == '/penugasan-petugas') {
      data = noAssignments
          ? <Json>[]
          : [
              for (final id in [staffRoomA, staffRoomB])
                {
                  'id': id,
                  'loketId': id,
                  'loket': room(id),
                  'aktif': true,
                  'tanggalMulai': config.today,
                },
            ];
    } else if (path == '/queue/snapshot') {
      final selected = query!['loketId']!,
          page = int.parse(query['halamanTindakLanjut']!);
      data = malformed
          ? {'unexpected': true}
          : {
              'tanggalPelayanan': snapshotDate ?? config.today,
              'sequence': ++snapshotSequence,
              'loketPeminta': {'id': selected},
              'menunggu': {
                'total': status == 'MENUNGGU' ? 1 : 0,
                'tiket': [
                  if (status == 'MENUNGGU') {...ticket},
                ],
              },
              'daftarPasien': {
                'halamanTindakLanjut': page,
                'jumlahHalamanTindakLanjut': pages,
                'tiket': [
                  if (['MENUNGGU', 'DILEWATI', 'CHECK_IN'].contains(status))
                    {...ticket},
                ],
              },
              'loket': [
                {
                  ...room(selected),
                  'tiketAktif': [
                    if (['DIPANGGIL', 'DILAYANI'].contains(status) &&
                        ticketRoom == selected)
                      {...ticket},
                  ],
                },
              ],
            };
    } else if (path == '/jadwal-praktik') {
      data = noSchedules
          ? <Json>[]
          : [
              for (final id in [staffRoomA, staffRoomB])
                {
                  'id': id,
                  'loketId': id,
                  'tanggal': query!['tanggal'],
                  'aktif': true,
                  'dokterLayanan': {
                    'dokter': {'nama': 'Dokter $id'},
                  },
                },
            ];
    }
    final gates = _gates[key];
    final gate = gates != null && gates.isNotEmpty ? gates.removeFirst() : null;
    gate?.entered.complete();
    try {
      await gate?.release.future;
      if (failures.containsKey(key)) throw failures[key]!;
      if (method == 'POST') {
        if (!loseWithoutCommit) {
          final op = StaffOperation.values.firstWhere(
            (o) => path.endsWith('/${o.route}'),
          );
          status = op.expectedStatus;
          version++;
          ticketRoom = body!['loketId'];
          if (op == StaffOperation.complete) pages = 1;
          data = {...ticket, 'sudahTerdaftar': false};
        }
        if (loseMutation || loseWithoutCommit) {
          throw TimeoutException('fixture transport lost');
        }
      }
      return data;
    } finally {
      if (method == 'GET') activeReads[readKey] = activeReads[readKey]! - 1;
    }
  }
}

class StaffFixture {
  StaffFixture({bool polling = false, StaffManualTimer? timer}) {
    repository = StaffQueueRepository(
      api,
      feedFactory: (service, refresh, status) {
        feedCount++;
        final feed = StaffFakeFeed(refresh, status, () => feedCount--);
        feeds.add(feed);
        return feed.dispose;
      },
    );
    bloc = StaffQueueBloc(
      repository,
      polling: polling,
      periodicTimer: timer == null
          ? null
          : (duration, callback) {
              timer.interval = duration;
              timer.callback = callback;
              return timer;
            },
    );
  }
  final api = StaffFixtureApi();
  late final StaffQueueRepository repository;
  late final StaffQueueBloc bloc;
  final feeds = <StaffFakeFeed>[];
  int feedCount = 0;
  Future<void> load() => bloc.refresh(assignments: true);
  Future<StaffQueueState> until(bool Function(StaffQueueState) predicate) {
    if (predicate(bloc.state)) return Future.value(bloc.state);
    return bloc.stream.firstWhere(predicate);
  }

  Future<void> dispose() async {
    await bloc.close();
    repository.dispose();
    api.dispose();
  }
}
