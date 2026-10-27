import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:queueb_client/src/api.dart';
import 'package:queueb_client/src/app.dart';
import 'package:queueb_client/src/config.dart';
import 'package:queueb_client/src/patient_reservations.dart';
import 'package:queueb_client/src/doctor_professional.dart';
import 'package:queueb_client/src/doctor_schedule_ui.dart';

import 'ui_test.dart' show FakeBackend, uid;

class ReservationBackend extends FakeBackend {
  ReservationBackend() : super('USER') {
    tickets.addAll([
      reservation('one', 'DIPESAN', future),
      reservation('walk', 'MENUNGGU', today),
      reservation('done', 'SELESAI', yesterday),
      reservation('cancelled', 'DIBATALKAN', future),
    ]);
    appointments.addAll([
      for (final t in tickets.where((t) => t['id'] != 'walk')) appointment(t),
    ]);
  }
  String future = '';
  String get nextDay =>
      calendarDate(DateTime.parse(today).add(const Duration(days: 2)));
  String get yesterday =>
      calendarDate(DateTime.parse(today).subtract(const Duration(days: 1)));
  bool rejectCancel = false, failNearest = false, ended = false;
  Completer<void>? cancelGate;
  Json get doctor => {
    'id': uid,
    'nama': 'dr. Indah Suci Permatasari dengan Nama Profesional Panjang',
    'spesialisasi': 'Penyakit Dalam',
    'aktif': true,
    'fotoProfil': null,
    'dokterLayanan': [
      {'id': uid, 'layananId': uid, 'layanan': service, 'aktif': true},
    ],
  };
  Json get practice => {
    'id': uid,
    'aktif': true,
    'tanggal': nextDay,
    'mulaiPada': '${nextDay}T01:00:00Z',
    'selesaiPada': '${nextDay}T05:00:00Z',
    'loket': room,
    'dokterLayanan': {
      'dokterId': uid,
      'layananId': uid,
      'dokter': doctor,
      'layanan': service,
      'aktif': true,
    },
  };
  Json get slot => {
    'id': uid,
    'aktif': true,
    'tersedia': slotsAvailable,
    'sisaKapasitas': slotsAvailable ? 2 : 0,
    'mulaiPada': '${nextDay}T02:00:00Z',
    'selesaiPada': '${nextDay}T02:30:00Z',
    'jadwalPraktik': practice,
  };
  Json reservation(String id, String state, String date) => {
    'id': id,
    'nomorAntrean':
        {
          'one': 'UM-001',
          'walk': 'UM-002',
          'done': 'UM-003',
          'cancelled': 'UM-004',
        }[id] ??
        'UM-005',
    'layanan': service,
    'tanggalPelayanan': date.isEmpty ? nextDay : date,
    'status': state,
  };
  Json appointment(Json t) => {
    'id': 'appointment-${t['id']}',
    'tiket': {...t},
    'slotPraktik': slot,
  };
  @override
  Future<http.Response> handle(http.Request r) async {
    final p = r.url.path.replaceFirst('/api/v1', '');
    if (p == '/dokter') return reply([doctor]);
    if (p == '/jadwal-praktik') {
      return reply([
        {
          ...practice,
          if (ended) ...{
            'tanggal': today,
            'selesaiPada': DateTime.now()
                .subtract(const Duration(hours: 1))
                .toUtc()
                .toIso8601String(),
          },
        },
      ]);
    }
    if (p == '/slot-praktik') {
      if (failNearest) return reply({'message': 'Slot gagal dimuat'}, 503);
      return reply([slot]);
    }
    if (p.contains('/batalkan')) {
      requests.add((r.method, p, {}));
      await cancelGate?.future;
      if (rejectCancel) {
        tickets.firstWhere((t) => t['id'] == 'one')['status'] = 'CHECK_IN';
        return reply({
          'message': 'Status tiket sudah berubah; pembatalan ditolak',
        }, 409);
      }
      tickets.firstWhere((t) => t['id'] == 'one')['status'] = 'DIBATALKAN';
      return reply(appointments.first);
    }
    if (p.startsWith('/tiket/') && p != '/tiket/saya') {
      requests.add((r.method, p, {}));
      final id = p.split('/')[2];
      final t = tickets.where((t) => t['id'] == id).firstOrNull;
      if (t == null) return reply({}, 404);
      if (p.endsWith('/qr')) {
        if (t['status'] != 'DIPESAN') return reply({}, 409);
        return reply({
          'tiketId': id,
          'qrPayload': 'SQ1.fixture',
          'berlakuHingga': DateTime.now()
              .add(const Duration(minutes: 10))
              .toUtc()
              .toIso8601String(),
        });
      }
      return reply(t);
    }
    if (r.method == 'POST' && ['/janji-temu', '/reservasi'].contains(p)) {
      requests.add((r.method, p, object(jsonDecode(r.body))));
      final t = reservation('new', 'DIPESAN', nextDay);
      tickets.add(t);
      if (p == '/janji-temu') {
        final a = appointment(t);
        appointments.add(a);
        return reply({...a, 'tiket': t}, 201);
      }
      return reply(t, 201);
    }
    return super.handle(r);
  }
}

void main() {
  setUpAll(tz.initializeTimeZones);
  Future<void> launch(
    WidgetTester t,
    ReservationBackend b, {
    Size size = const Size(390, 844),
  }) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    final api =
        QueueApi(
            config: AppConfig(
              apiBaseUrl: 'http://localhost/api/v1',
              realtime: false,
            ),
            client: MockClient(b.handle),
          )
          ..accessToken = 'test'
          ..user = b.user;
    await t.pumpWidget(QueueBApp(api: api));
    await t.pumpAndSettle();
    addTearDown(() async {
      await t.pumpWidget(const SizedBox());
      api.dispose();
      t.view.resetPhysicalSize();
      t.view.resetDevicePixelRatio();
    });
    await t.tap(find.widgetWithText(NavigationDestination, 'Reservasi'));
    await t.pumpAndSettle();
  }

  Future<void> press(WidgetTester t, Finder f) async {
    if (f.evaluate().isEmpty) {
      await t.scrollUntilVisible(
        f,
        180,
        scrollable: find.byType(Scrollable).first,
      );
    }
    await t.ensureVisible(f.last);
    await t.pumpAndSettle();
    await t.tap(f.last);
    await t.pumpAndSettle();
  }

  test('projection deduplicates by ticket, preserves status, current metadata and future/history order', () {
    final b = ReservationBackend();
    final list = patientReservations(b.tickets, b.appointments, [
      b.doctor,
    ], b.today);
    expect(list.length, 4);
    expect(list.map((r) => r.id).toSet().length, 4);
    expect(list.first.id, 'walk');
    expect(list[1].id, 'one');
    expect(list.first.appointment, isNull);
    expect(list.first.doctor, isEmpty);
    b.tickets.first['status'] = 'MENUNGGU';
    final fresh = patientReservations(b.tickets, b.appointments, [
      b.doctor,
    ], b.today);
    expect(fresh.firstWhere((r) => r.id == 'one').status, 'MENUNGGU');
    expect(fresh.firstWhere((r) => r.id == 'one').canCancel, isFalse);
    expect(fresh.firstWhere((r) => r.id == 'cancelled').terminal, isTrue);
  });
  for (final size in [
    const Size(360, 800),
    const Size(390, 844),
    const Size(412, 915),
    const Size(768, 1024),
  ]) {
    testWidgets(
      'reservation cards, FAB, bottom sheet and navigation fit $size',
      (t) async {
        await launch(t, ReservationBackend(), size: size);
        expect(find.text('Reservasi Saya'), findsOneWidget);
        expect(
          t.getBottomLeft(find.byType(FloatingActionButton)).dy,
          lessThanOrEqualTo(t.getTopLeft(find.byType(NavigationBar)).dy),
        );
        expect(find.text('Antrean harian / Walk-in'), findsOneWidget);
        expect(find.byType(ProfessionalDoctorAvatar), findsWidgets);
        expect(find.text('Batalkan Reservasi'), findsOneWidget);
        await press(t, find.byType(FloatingActionButton));
        for (final title in [
          'Cari Dokter',
          'Pilih Poliklinik',
          'Jadwal Terdekat',
        ]) {
          expect(find.text(title), findsOneWidget);
        }
        expect(find.widgetWithText(FilledButton, 'Lanjutkan'), findsNothing);
        expect(t.takeException(), isNull);
        await press(t, find.byTooltip('Tutup pilihan reservasi'));
        expect(find.text('Reservasi Saya'), findsOneWidget);
      },
    );
  }
  testWidgets(
    'empty state and status filters/search preserve operational ticket labels',
    (t) async {
      final b = ReservationBackend();
      await launch(t, b);
      await press(t, find.widgetWithText(ChoiceChip, 'Dipesan'));
      expect(find.byType(ReservationCard), findsOneWidget);
      await t.enterText(find.byType(TextField), 'UM-001');
      await t.pumpAndSettle();
      expect(find.byType(ReservationCard), findsOneWidget);
      await t.enterText(find.byType(TextField), 'tidak ada');
      await t.pumpAndSettle();
      expect(find.text('Belum ada reservasi yang sesuai.'), findsOneWidget);
      await t.enterText(find.byType(TextField), '');
      await press(t, find.widgetWithText(ChoiceChip, 'Selesai'));
      expect(find.text('Lihat Detail'), findsOneWidget);
      expect(find.text('Batalkan Reservasi'), findsNothing);
      await press(t, find.widgetWithText(ChoiceChip, 'Dibatalkan'));
      expect(find.byType(ReservationCard), findsOneWidget);
      expect(find.text('Buka Tiket'), findsNothing);
      b.tickets.clear();
      b.appointments.clear();
      await press(t, find.byTooltip('Muat ulang reservasi'));
      expect(find.text('Belum ada reservasi yang sesuai.'), findsOneWidget);
    },
  );
  testWidgets(
    'cancellation awaits server, guards duplicate submit and retains filters',
    (t) async {
      final b = ReservationBackend();
      await launch(t, b);
      await press(t, find.widgetWithText(ChoiceChip, 'Dipesan'));
      await press(t, find.text('Batalkan Reservasi'));
      expect(find.text('Batalkan reservasi?'), findsOneWidget);
      b.cancelGate = Completer<void>();
      await t.tap(find.text('Ya, Batalkan'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(b.tickets.first['status'], 'DIPESAN');
      expect(b.requests.where((r) => r.$2.contains('/batalkan')).length, 1);
      b.cancelGate!.complete();
      await t.pumpAndSettle();
      expect(find.text('Belum ada reservasi yang sesuai.'), findsOneWidget);
      expect(
        t
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Dipesan'))
            .selected,
        isTrue,
      );
      await press(t, find.widgetWithText(ChoiceChip, 'Dibatalkan'));
      expect(find.text('Batalkan Reservasi'), findsNothing);
    },
  );
  testWidgets(
    '409 cancellation reconciles actual CHECK_IN status without fake cancellation',
    (t) async {
      final b = ReservationBackend()..rejectCancel = true;
      await launch(t, b);
      await press(t, find.text('Batalkan Reservasi'));
      await press(t, find.text('Ya, Batalkan'));
      expect(find.textContaining('pembatalan ditolak'), findsOneWidget);
      await t.enterText(find.byType(TextField), 'UM-001');
      await t.pumpAndSettle();
      expect(find.text('Check-in'), findsOneWidget);
      expect(find.text('Batalkan Reservasi'), findsNothing);
    },
  );
  testWidgets('cancelled ticket uses correct ticket id and never issues QR', (
    t,
  ) async {
    final b = ReservationBackend();
    await launch(t, b);
    await press(t, find.widgetWithText(ChoiceChip, 'Dibatalkan'));
    await press(t, find.text('Lihat Detail'));
    expect(find.text('Tiket UM-004'), findsOneWidget);
    expect(b.requests.any((r) => r.$2 == '/tiket/cancelled'), isTrue);
    expect(b.requests.any((r) => r.$2.endsWith('/qr')), isFalse);
  });
  testWidgets(
    'doctor path reuses slot selection and appointment review; produces one ticket',
    (t) async {
      final b = ReservationBackend();
      await launch(t, b);
      await press(t, find.byType(FloatingActionButton));
      await press(t, find.text('Cari Dokter'));
      expect(find.byType(ReservationDoctorChoice), findsOneWidget);
      await press(t, find.text('Pilih Jadwal'));
      await press(t, find.text('Lihat slot'));
      await press(t, find.text('Sisa slot 2'));
      await press(t, find.widgetWithText(FilledButton, 'Lanjutkan'));
      await press(t, find.text('Konfirmasi Janji Temu'));
      expect(
        b.requests.where((r) => r.$1 == 'POST' && r.$2 == '/janji-temu').length,
        1,
      );
      expect(
        find.text('Pendaftaran berhasil.'),
        findsNothing,
      ); // full notice contains ticket identity
      expect(find.textContaining('Pendaftaran berhasil.'), findsOneWidget);
    },
  );
  testWidgets(
    'clinic path retains valid walk-in mode and original booking endpoint',
    (t) async {
      final b = ReservationBackend();
      await launch(t, b);
      await press(t, find.byType(FloatingActionButton));
      await press(t, find.text('Pilih Poliklinik'));
      await press(t, find.text('Poli Umum'));
      await press(t, find.text('Walk-in'));
      await press(t, find.text('Reservasi walk-in'));
      await press(t, find.text('Lanjutkan'));
      expect(
        b.requests.where((r) => r.$1 == 'POST' && r.$2 == '/reservasi').length,
        1,
      );
    },
  );
  testWidgets(
    'nearest uses real available slots, rechecks before confirmation; full slots omitted',
    (t) async {
      final b = ReservationBackend();
      await launch(t, b);
      await press(t, find.byType(FloatingActionButton));
      await press(t, find.text('Jadwal Terdekat'));
      expect(find.byType(ReservationDoctorChoice), findsOneWidget);
      await press(t, find.text('Pilih Jadwal'));
      expect(
        t.widget<ConsultationSlotGrid>(find.byType(ConsultationSlotGrid)).value,
        uid,
      );
      expect(
        b.requests.any((r) => r.$1 == 'POST' && r.$2 == '/janji-temu'),
        isFalse,
      );
      await press(t, find.widgetWithText(NavigationDestination, 'Reservasi'));
      b.slotsAvailable = false;
      await press(t, find.byType(FloatingActionButton));
      await press(t, find.text('Jadwal Terdekat'));
      expect(find.byType(ReservationDoctorChoice), findsNothing);
      expect(find.text('Belum ada slot tersedia yang sesuai.'), findsOneWidget);
    },
  );
  testWidgets('polling refreshes server status in place and preserves search', (
    t,
  ) async {
    final b = ReservationBackend();
    await launch(t, b);
    await t.enterText(find.byType(TextField), 'UM-001');
    await t.pumpAndSettle();
    b.tickets.first['status'] = 'DILEWATI';
    await t.pump(const Duration(seconds: 31));
    await t.pumpAndSettle();
    expect(find.text('Dilewati'), findsOneWidget);
    expect(find.text('Batalkan Reservasi'), findsNothing);
    expect(find.byType(ReservationCard), findsOneWidget);
  });
  test('professional photo metadata is hydrated without inventing a doctor for walk-in', () {
    final b = ReservationBackend();
    final items = patientReservations(b.tickets, b.appointments, [
      {
        ...b.doctor,
        'fotoProfil': '/media/dokter/11111111-1111-4111-8111-111111111111.webp',
      },
    ], b.today);
    expect(
      items.firstWhere((r) => r.id == 'one').doctor['fotoProfil'],
      endsWith('.webp'),
    );
    expect(items.firstWhere((r) => r.id == 'walk').doctor, isEmpty);
    for (final value in [
      'CHECK_IN',
      'MENUNGGU',
      'DIPANGGIL',
      'DILAYANI',
      'DILEWATI',
    ]) {
      expect(reservationStatus(value), isNot('Dipesan'));
    }
  });
  testWidgets(
    'long reservation history is built lazily and remains searchable',
    (t) async {
      final b = ReservationBackend();
      for (var i = 0; i < 150; i++) {
        b.tickets.add({
          ...b.reservation('history-$i', 'SELESAI', b.yesterday),
          'nomorAntrean': 'H-$i',
        });
      }
      await launch(t, b);
      expect(find.byType(ReservationCard).evaluate().length, lessThan(15));
      await t.enterText(find.byType(TextField), 'H-149');
      await t.pumpAndSettle();
      expect(find.byType(ReservationCard), findsOneWidget);
      expect(
        find.byWidgetPredicate((w) => w is Text && w.data == 'H-149'),
        findsOneWidget,
      );
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'nearest read failure stays explicit and never enables fictitious booking',
    (t) async {
      final b = ReservationBackend()..failNearest = true;
      await launch(t, b);
      await press(t, find.byType(FloatingActionButton));
      await press(t, find.text('Jadwal Terdekat'));
      expect(
        find.textContaining('Sebagian slot belum dapat dimuat'),
        findsOneWidget,
      );
      expect(find.byType(ReservationDoctorChoice), findsNothing);
      expect(
        b.requests.any((r) => r.$1 == 'POST' && r.$2 == '/janji-temu'),
        isFalse,
      );
    },
  );
  testWidgets(
    'nearest choice rechecks slot that became full before selection',
    (t) async {
      final b = ReservationBackend();
      await launch(t, b);
      await press(t, find.byType(FloatingActionButton));
      await press(t, find.text('Jadwal Terdekat'));
      b.slotsAvailable = false;
      await press(t, find.text('Pilih Jadwal'));
      expect(
        t.widget<ConsultationSlotGrid>(find.byType(ConsultationSlotGrid)).value,
        isNull,
      );
      await t.ensureVisible(find.widgetWithText(FilledButton, 'Lanjutkan'));
      await t.pumpAndSettle();
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Lanjutkan'),
            )
            .onPressed,
        isNull,
      );
      expect(
        b.requests.any((r) => r.$1 == 'POST' && r.$2 == '/janji-temu'),
        isFalse,
      );
    },
  );
  testWidgets('ended practice is never offered as a future schedule', (
    t,
  ) async {
    final b = ReservationBackend()..ended = true;
    await launch(t, b);
    await press(t, find.byType(FloatingActionButton));
    await press(t, find.text('Cari Dokter'));
    expect(find.text('Belum ada jadwal praktik mendatang.'), findsOneWidget);
    expect(
      t
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Pilih Jadwal'),
          )
          .onPressed,
      isNull,
    );
  });
}
