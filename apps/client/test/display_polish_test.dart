import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:queueb_client/src/config.dart';
import 'package:queueb_client/src/display_board.dart';
import 'package:queueb_client/src/mobile_ui.dart';

import 'display_v3_test.dart' show monitorSnapshot;

void main() {
  for (final size in [
    const Size(1280, 720),
    const Size(1366, 768),
    const Size(1920, 1080),
  ]) {
    for (final state in [
      'call',
      'empty',
      'loading',
      'offline',
      'rejected',
      'no-name',
    ]) {
      testWidgets(
        'Signage $size $state stays in viewport with accessible controls',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final data = monitorSnapshot(
            waiting: state == 'empty' ? 0 : 30,
            full: true,
          );
          if (state == 'empty') {
            data['loket'] = [
              for (final room in rows(data['loket']))
                {...room, 'tiketAktif': <Json>[]},
            ];
            data['pengumumanTerakhir'] = null;
          }
          if (state == 'no-name') {
            data['modeNama'] = 'TANPA_NAMA';
            data['loket'] = [
              for (final room in rows(data['loket']))
                {
                  ...room,
                  'tiketAktif': [
                    for (final ticket in rows(room['tiketAktif']))
                      {...ticket}..remove('namaPasien'),
                  ],
                },
            ];
            data['menunggu'] = [
              for (final patient in rows(data['menunggu']))
                {...patient}..remove('namaPasien'),
            ];
            data['pengumumanTerakhir'] = {
              ...object(data['pengumumanTerakhir']),
              'teks': 'Nomor antrean AN-001, silakan menuju Poliklinik Anak.',
            };
          }
          if (state == 'call') {
            data['antrianPasien'] = [
              {
                'nomorAntrean': 'POLI-12345',
                'namaPasien': 'Pasien QA',
                'status': 'DILEWATI',
              },
            ];
            data['totalAntrianPasien'] = 1;
          }
          var audio = 0, refresh = 0, configure = 0, fullscreen = 0;
          await tester.pumpWidget(
            MaterialApp(
              theme: QueueBStyle.theme,
              home: Scaffold(
                body: DisplayBoard(
                  snapshot: ['loading', 'rejected'].contains(state)
                      ? null
                      : data,
                  now: DateTime(2026, 10, 27, 10, 45, 12),
                  status: state == 'offline'
                      ? 'Realtime terputus · sinkronisasi berkala aktif'
                      : 'Realtime terhubung',
                  error: state == 'offline'
                      ? 'offline'
                      : state == 'rejected'
                      ? 'Perangkat dinonaktifkan.'
                      : null,
                  rejected: state == 'rejected',
                  audioError: state == 'offline'
                      ? 'Suara tidak tersedia. Gunakan pengumuman visual.'
                      : null,
                  fullscreenSupported: true,
                  onAudio: () => audio++,
                  onRefresh: () => refresh++,
                  onConfigure: () => configure++,
                  onFullscreen: () => fullscreen++,
                ),
              ),
            ),
          );
          await tester.pump();
          expect(tester.takeException(), isNull);
          expect(find.byType(Scrollable), findsNothing);
          if (state == 'call') {
            final number = find.text('POLI-12345');
            expect(
              find.ancestor(of: number, matching: find.byType(FittedBox)),
              findsOneWidget,
            );
            expect(
              tester.widget<Text>(number).overflow,
              isNot(TextOverflow.ellipsis),
            );
            expect(tester.getRect(number).right, lessThanOrEqualTo(size.width));
          }

          for (final label in ['Layar penuh', 'Ganti perangkat']) {
            final rect = tester.getRect(find.text(label));
            expect(rect.left, greaterThanOrEqualTo(0));
            expect(rect.right, lessThanOrEqualTo(size.width));
            expect(rect.bottom, lessThanOrEqualTo(size.height));
            await tester.tap(find.text(label));
          }
          expect(fullscreen, 1);
          expect(configure, 1);
          if (state != 'rejected') {
            await tester.tap(find.text('Aktifkan suara'));
            await tester.tap(find.text('Muat ulang'));
            expect(audio, 1);
            expect(refresh, 1);
          }
          if (['call', 'offline', 'no-name'].contains(state)) {
            final number = tester.getRect(
              find.byKey(const ValueKey('display-call-number')),
            );
            final room = tester.getRect(
              find.byKey(const ValueKey('display-call-destination')),
            );
            // Flutter tests use the wide Ahem font; compare hierarchy, not TV pixels.
            expect(number.height, greaterThan(80));
            expect(number.bottom, lessThanOrEqualTo(room.top));
            expect(room.height, greaterThan(65));
          }
          if (state == 'no-name') {
            expect(
              find.byKey(const ValueKey('display-call-name')),
              findsNothing,
            );
            expect(find.textContaining('Pasien Demonstrasi'), findsNothing);
          }
          await tester.pumpWidget(const SizedBox());
          await tester.pump(const Duration(seconds: 30));
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
