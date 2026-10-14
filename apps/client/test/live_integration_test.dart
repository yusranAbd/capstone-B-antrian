import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:queueb_client/src/api.dart';
import 'package:queueb_client/src/config.dart';
import 'package:queueb_client/src/realtime.dart';

void main() {
  final fixtureText = Platform.environment['FLUTTER_REAL_FIXTURE'];
  test(
    'Live isolated backend: Flutter REST, QR, queue and realtime for appointment/walk-in',
    () async {
      tz.initializeTimeZones();
      final fixture = object(jsonDecode(fixtureText!));
      final config = AppConfig(apiBaseUrl: 'http://127.0.0.1:3001/api/v1');
      final staff = QueueApi(config: config),
          patient1 = QueueApi(config: config),
          patient2 = QueueApi(config: config),
          admin = QueueApi(config: config);
      final apis = [staff, patient1, patient2, admin];
      final events = <String>[];
      RealtimeFeed? queue, display;
      try {
        for (final pair in [
          (admin, 'admin'),
          (staff, 'petugas'),
          (patient1, 'patient1'),
          (patient2, 'patient2'),
        ]) {
          final account = object(fixture[pair.$2]);
          await pair.$1.login('${account['email']}', '${account['password']}');
        }
        expect(admin.user?['peran'], 'ADMIN');
        expect(staff.user?['peran'], 'PETUGAS');
        expect(patient1.user?['peran'], 'USER');
        expect(
          rows(await patient1.request('GET', '/dokter'))
              .any((d) => d['id'] == fixture['doctorId']),
          isTrue,
        );
        final schedules = rows(
          await patient1.request(
            'GET',
            '/jadwal-praktik',
            query: {
              'dokterId': fixture['doctorId'],
              'tanggal': fixture['date'],
            },
          ),
        );
        expect(schedules.any((s) => s['id'] == fixture['scheduleId']), isTrue);
        final slots = rows(
          await patient2.request(
            'GET',
            '/slot-praktik',
            query: {'jadwalPraktikId': fixture['scheduleId']},
          ),
        );
        expect(slots.single['tersedia'], isTrue);
        final appt = object(
          await patient2.request(
            'POST',
            '/janji-temu',
            body: {'slotPraktikId': fixture['slotId']},
          ),
        );
        final walk = object(
          await patient1.request(
            'POST',
            '/reservasi',
            body: {
              'layananId': fixture['serviceId'],
              'tanggalAntrean': fixture['date'],
            },
          ),
        );
        final appointmentId = object(appt['tiket'])['id'] as String;
        final walkId = walk['id'] as String;
        expect(appointmentId, isNot(appt['id']));
        expect(
          rows(await patient2.request('GET', '/tiket/saya'))
              .any((t) => t['id'] == appointmentId),
          isTrue,
        );
        final queueReady = Completer<void>(), displayReady = Completer<void>();
        queue = RealtimeFeed(
          api: staff,
          layananId: fixture['serviceId'],
          onRefresh: () {},
          onStatus: (s) {
            if (s == 'Realtime terhubung' && !queueReady.isCompleted) {
              queueReady.complete();
            }
          },
          onEvent: (e) => events.add('${e['aksi']}'),
        );
        final displayEvents = <String>[];
        display = RealtimeFeed(
          api: staff,
          layananId: fixture['serviceId'],
          displayToken: fixture['displayToken'],
          onRefresh: () {},
          onStatus: (s) {
            if (s == 'Realtime terhubung' && !displayReady.isCompleted) {
              displayReady.complete();
            }
          },
          onEvent: (e) => displayEvents.add('${e['aksi']}'),
        );
        await Future.wait([queueReady.future, displayReady.future])
            .timeout(const Duration(seconds: 15));
        final roomBody = {'loketId': fixture['roomId']};
        for (final pair in [(patient2, appointmentId), (patient1, walkId)]) {
          final qr = object(
            await pair.$1.request('POST', '/tiket/${pair.$2}/qr', body: {}),
          );
          expect(qr['qrPayload'], startsWith('SQ1.'));
          final checked = object(
            await staff.request(
              'POST',
              '/check-in',
              body: {...roomBody, 'qrPayload': qr['qrPayload']},
            ),
          );
          expect(checked['status'], 'CHECK_IN');
          await expectLater(
            staff.request(
              'POST',
              '/check-in',
              body: {...roomBody, 'qrPayload': qr['qrPayload']},
            ),
            throwsA(isA<ApiException>()),
          );
          expect(
            object(
              await staff.request(
                'POST',
                '/queue/${pair.$2}/masuk',
                body: roomBody,
              ),
            )['status'],
            'MENUNGGU',
          );
        }
        final started = DateTime.parse(fixture['slotStart']);
        final wait = started.difference(DateTime.now());
        if (!wait.isNegative) {
          stdout.writeln(
            'Menunggu awal slot sah sebelum CALL: ${wait.inSeconds + 1} detik.',
          );
          await Future<void>.delayed(wait + const Duration(seconds: 1));
        }
        final called = object(
          await staff.request('POST', '/queue/panggil', body: roomBody),
        );
        expect(called['tiketId'], appointmentId);
        final publicSnapshot = object(
          await staff.request(
            'GET',
            '/display/${fixture['serviceId']}/snapshot',
            authenticated: false,
            displayToken: fixture['displayToken'],
          ),
        );
        expect(publicSnapshot['totalMenunggu'], 1);
        final announcement = object(publicSnapshot['pengumumanTerakhir']);
        expect(announcement['aksi'], 'CALL');
        expect(jsonEncode(publicSnapshot).contains('penggunaId'), isFalse);
        expect(jsonEncode(publicSnapshot).contains('tiketId'), isFalse);
        await staff.request(
          'POST',
          '/queue/$appointmentId/panggil-ulang',
          body: roomBody,
        );
        final afterRecall = object(
          await staff.request(
            'GET',
            '/display/${fixture['serviceId']}/snapshot',
            authenticated: false,
            displayToken: fixture['displayToken'],
          ),
        );
        expect(
          object(afterRecall['pengumumanTerakhir'])['peristiwaId'],
          isNot(announcement['peristiwaId']),
        );
        await staff.request(
          'POST',
          '/queue/$appointmentId/lewati',
          body: roomBody,
        );
        await staff.request(
          'POST',
          '/queue/$appointmentId/antre-ulang',
          body: roomBody,
        );
        expect(
          object(
            await staff.request('POST', '/queue/panggil', body: roomBody),
          )['tiketId'],
          appointmentId,
        );
        for (final id in [appointmentId, walkId]) {
          if (id == walkId) {
            expect(
              object(
                await staff.request('POST', '/queue/panggil', body: roomBody),
              )['tiketId'],
              walkId,
            );
          }
          expect(
            object(
              await staff.request(
                'POST',
                '/queue/$id/mulai-pelayanan',
                body: roomBody,
              ),
            )['status'],
            'DILAYANI',
          );
          expect(
            object(
              await staff.request(
                'POST',
                '/queue/$id/selesaikan-pelayanan',
                body: roomBody,
              ),
            )['status'],
            'SELESAI',
          );
        }
        expect(
          object(await patient1.request('GET', '/tiket/$walkId'))['status'],
          'SELESAI',
        );
        expect(
          object(
            await patient2.request('GET', '/tiket/$appointmentId'),
          )['status'],
          'SELESAI',
        );
        await Future<void>.delayed(const Duration(milliseconds: 300));
        expect(
          events.toSet(),
          containsAll([
            'ENQUEUE',
            'CALL',
            'RECALL',
            'SKIP',
            'REQUEUE',
            'START',
            'COMPLETE',
          ]),
        );
        expect(
          displayEvents.toSet(),
          containsAll([
            'ENQUEUE',
            'CALL',
            'RECALL',
            'SKIP',
            'REQUEUE',
            'START',
            'COMPLETE',
          ]),
        );
        await staff.refresh();
        expect(
          object(
            await staff.request(
              'GET',
              '/queue/snapshot',
              query: {'loketId': fixture['roomId']},
            ),
          )['versiSkema'],
          1,
        );
      } finally {
        queue?.dispose();
        display?.dispose();
        for (final api in apis) {
          try {
            await api.logout();
          } catch (_) {}
          api.dispose();
        }
      }
    },
    skip: fixtureText == null
        ? 'Jalankan melalui node tool/run-live.cjs dengan database test tervalidasi.'
        : false,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
