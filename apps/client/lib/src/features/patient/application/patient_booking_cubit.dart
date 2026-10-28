import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../api.dart';
import '../../../config.dart';
import '../../../patient_sync.dart';
import '../data/patient_booking_repository.dart';
import '../data/patient_repository.dart';
import '../models/patient_models.dart';

class PatientBookingState {
  PatientBookingState(
    Json values, {
    this.mutation = PatientMutation.idle,
    this.error,
  }) : values = patientObject(values);
  final Json values;
  final PatientMutation mutation;
  final String? error;
  bool get busy => mutation == PatientMutation.submitting;
  bool get loading => values['loading'] == true;
  List<Json> rows(String key) =>
      (values[key] as List? ?? const []).cast<Json>();
}

class PatientBookingRequest {
  PatientBookingRequest({
    required this.clinic,
    required this.doctor,
    required this.session,
    required this.slot,
    required this.date,
    required this.appointment,
    required this.revision,
  });
  final Json clinic, doctor, session, slot;
  final String date;
  final bool appointment;
  final int revision;
  Json get body => appointment
      ? {'slotPraktikId': slot['id']}
      : {'layananId': clinic['id'], 'tanggalAntrean': date};
}

class PatientBookingCubit extends Cubit<PatientBookingState> {
  PatientBookingCubit(this.repository)
    : super(
        PatientBookingState({
          'date': repository.patient.api.config.today,
          'appointment': true,
        }),
      ) {
    _references = RefreshGate(refreshSelection);
    patient.addListener(_catalogChanged);
    patient.invalidations.addListener(_invalidated);
  }
  final PatientBookingRepository repository;
  PatientRepository get patient => repository.patient;
  late final RefreshGate _references;
  bool _closing = false, _commandRunning = false;
  bool get busy => _commandRunning || state.busy;
  bool get _overviewFailed =>
      patient.errors.keys.any(patientOverviewPaths.contains);
  int revision = 0, _nearestRevision = 0;
  Future<void>? _referencePending;
  Future<void> get referencesSettled => _referencePending ?? Future.value();
  PatientBookingRequest? _uncertain;
  Set<Object?> _beforeIds = {};
  bool get current => !_closing && !isClosed && patient.active;
  String? get serviceId => state.values['serviceId'] as String?;
  String? get doctorId => state.values['doctorId'] as String?;
  String? get sessionId => state.values['sessionId'] as String?;
  String? get slotId => state.values['slotId'] as String?;
  bool get appointment => state.values['appointment'] != false;
  String get date => '${state.values['date']}';
  Json? get selectedService =>
      patient.snapshot.services.where((c) => c['id'] == serviceId).firstOrNull;
  void _set(
    Json values, {
    PatientMutation? mutation,
    String? error,
    bool clearError = false,
  }) {
    if (!current) return;
    emit(
      PatientBookingState(
        {...state.values, ...values},
        mutation: mutation ?? state.mutation,
        error: clearError ? null : error ?? state.error,
      ),
    );
  }

  void change(Json values) {
    if (!current || busy) return;
    revision++;
    _set(values, clearError: _uncertain == null);
  }

  void invalidate() {
    revision++;
    _nearestRevision++;
    _set({'loading': false, 'nearestActive': false});
  }

  void invalidateNearest() {
    _nearestRevision++;
    _set({'nearestLoading': false, 'nearestActive': false});
  }

  void clearAvailability() => _set({'availability': <String, dynamic>{}});
  void _catalogChanged() {
    if (_closing || isClosed) return;
    if (!patient.active) {
      invalidate();
      _uncertain = null;
      emit(
        PatientBookingState({
          'date': patient.api.config.today,
          'appointment': true,
        }),
      );
      return;
    }
    if (serviceId != null &&
        (selectedService == null || selectedService?['aktif'] == false)) {
      change({
        'serviceId': null,
        'doctorId': null,
        'sessionId': null,
        'slotId': null,
        'schedules': [],
        'slots': [],
        'clinicSchedules': [],
        'loading': false,
      });
    } else if (doctorId != null &&
        !patient.snapshot.doctors.any(
          (d) =>
              d['id'] == doctorId &&
              d['aktif'] != false &&
              rows(
                d['dokterLayanan'],
              ).any((l) => l['layananId'] == serviceId && l['aktif'] == true),
        )) {
      change({
        'doctorId': null,
        'sessionId': null,
        'slotId': null,
        'schedules': [],
        'slots': [],
        'loading': false,
      });
    }
    _recover();
    if (_uncertain == null &&
        state.values['needsReconciliation'] == true &&
        !_overviewFailed) {
      _set({'needsReconciliation': false});
    }
  }

  void _invalidated() {
    if (current && patient.invalidations.value.$2.contains('KATALOG')) {
      _referencePending = _references.refresh();
    }
  }

  Future<void> loadClinicSchedules() async {
    if (serviceId == null || !current) return;
    final epoch = ++revision, clinic = serviceId!;
    _set({'loading': true}, clearError: _uncertain == null);
    try {
      final list = await repository.read('/jadwal-praktik', {
        'layananId': clinic,
      });
      if (!current || epoch != revision) return;
      _set({'clinicSchedules': list});
      final nearest = <String, Json>{};
      final sorted = [...list]
        ..sort((a, b) => '${a['mulaiPada']}'.compareTo('${b['mulaiPada']}'));
      for (final session in sorted) {
        final link = object(session['dokterLayanan']);
        final id = link['dokterId'] ?? object(link['dokter'])['id'];
        if (id is String &&
            session['aktif'] != false &&
            dateOnly(session['tanggal']).compareTo(patient.api.config.today) >=
                0) {
          nearest.putIfAbsent(id, () => session);
        }
      }
      final entries = nearest.entries.toList();
      final availability = <String, String>{};
      for (var i = 0; i < entries.length; i += 4) {
        if (!current || epoch != revision) return;
        await Future.wait(
          entries.skip(i).take(4).map((entry) async {
            try {
              final items = await repository.read('/slot-praktik', {
                'jadwalPraktikId': '${entry.value['id']}',
              });
              final count = items
                  .where((s) => s['aktif'] != false && s['tersedia'] == true)
                  .length;
              availability[entry.key] = count > 0
                  ? '$count slot tersedia pada sesi terdekat'
                  : 'Belum ada slot tersedia pada sesi terdekat';
            } catch (_) {
              availability[entry.key] = 'Ketersediaan slot belum dapat dimuat';
            }
          }),
        );
      }
      if (current && epoch == revision) _set({'availability': availability});
    } catch (error) {
      if (current && epoch == revision) {
        _set({}, error: '${patientError(error)}');
      }
    } finally {
      if (current && epoch == revision) _set({'loading': false});
    }
  }

  Future<void> loadSchedules({bool preserve = false}) async {
    if (!current || serviceId == null || doctorId == null) return;
    final epoch = ++revision, selected = sessionId, selectedSlot = slotId;
    _set({
      'loading': true,
      if (!preserve) ...{
        'sessionId': null,
        'slotId': null,
        'schedules': [],
        'slots': [],
      },
    }, clearError: _uncertain == null);
    try {
      final list = await repository.read('/jadwal-praktik', {
        'layananId': serviceId!,
        'dokterId': doctorId!,
        'tanggal': date,
      });
      if (!current || epoch != revision) return;
      _set({'schedules': list});
      if (preserve) {
        if (list.any((s) => s['id'] == selected)) {
          final options = await repository.read('/slot-praktik', {
            'jadwalPraktikId': selected!,
          });
          if (current && epoch == revision) {
            _set({
              'slots': options,
              'slotId':
                  options.any(
                    (s) =>
                        s['id'] == selectedSlot &&
                        s['tersedia'] == true &&
                        s['aktif'] != false,
                  )
                  ? selectedSlot
                  : null,
            });
          }
        } else {
          _set({'sessionId': null, 'slotId': null, 'slots': []});
        }
      }
    } catch (error) {
      if (current && epoch == revision) {
        _set({}, error: '${patientError(error)}');
      }
    } finally {
      if (current && epoch == revision) _set({'loading': false});
    }
  }

  Future<void> loadSlots(String id) async {
    if (!current || busy) return;
    final epoch = ++revision;
    _set({
      'loading': true,
      'sessionId': id,
      'slotId': null,
      'slots': [],
    }, clearError: _uncertain == null);
    try {
      final list = await repository.read('/slot-praktik', {
        'jadwalPraktikId': id,
      });
      if (current && epoch == revision) _set({'slots': list});
    } catch (error) {
      if (current && epoch == revision) {
        _set({}, error: '${patientError(error)}');
      }
    } finally {
      if (current && epoch == revision) _set({'loading': false});
    }
  }

  Future<void> refreshSelection() async {
    await patient.refresh(const []);
    if (!current || state.busy) return;
    if (serviceId == null) {
      if (state.values['nearestActive'] == true) await loadNearest();
      return;
    }
    await loadClinicSchedules();
    if (current && doctorId != null) await loadSchedules(preserve: true);
  }

  List<Json> get reservableSessions =>
      patient.snapshot.schedules.where((s) {
        final link = object(s['dokterLayanan']);
        final clinic = link['layananId'] ?? object(link['layanan'])['id'];
        final doctor = link['dokterId'] ?? object(link['dokter'])['id'];
        return s['aktif'] != false &&
            link['aktif'] != false &&
            object(s['loket'])['aktif'] != false &&
            dateOnly(s['tanggal']).compareTo(patient.api.config.today) >= 0 &&
            (DateTime.tryParse('${s['selesaiPada']}')
                    ?.isAfter(patient.api.config.now) ??
                false) &&
            patient.snapshot.services.any(
              (c) =>
                  c['id'] == clinic &&
                  c['aktif'] != false &&
                  ['HIBRIDA', 'JANJI_TEMU_DOKTER'].contains(c['modeReservasi']),
            ) &&
            patient.snapshot.doctors.any(
              (d) => d['id'] == doctor && d['aktif'] != false,
            );
      }).toList()..sort(
        (a, b) => '${a['mulaiPada']}'.compareTo('${b['mulaiPada']}'),
      );
  Future<void> loadNearest() async {
    if (!current) return;
    final epoch = ++_nearestRevision, sessions = reservableSessions;
    final snapshot = patient.snapshot, found = <Json>[];
    bool failed = false;
    _set({
      'nearestLoading': true,
      'nearestActive': true,
      'nearestChoices': [],
      'nearestError': null,
    });
    for (var i = 0; i < sessions.length; i += 4) {
      if (!current || epoch != _nearestRevision) return;
      await Future.wait(
        sessions.skip(i).take(4).map((session) async {
          try {
            final options = await repository.read('/slot-praktik', {
              'jadwalPraktikId': '${session['id']}',
            });
            final link = object(session['dokterLayanan']);
            final clinic = link['layananId'] ?? object(link['layanan'])['id'];
            final doctor = link['dokterId'] ?? object(link['dokter'])['id'];
            for (final slot in options.where(
              (s) =>
                  s['aktif'] != false &&
                  s['tersedia'] == true &&
                  (DateTime.tryParse('${s['mulaiPada']}')
                          ?.isAfter(patient.api.config.now) ??
                      false),
            )) {
              found.add({
                'doctor': snapshot.doctors.firstWhere((d) => d['id'] == doctor),
                'clinic': snapshot.services.firstWhere(
                  (c) => c['id'] == clinic,
                ),
                'session': session,
                'slot': slot,
              });
            }
          } catch (_) {
            failed = true;
          }
        }),
      );
    }
    if (!current || epoch != _nearestRevision) return;
    found.sort(
      (a, b) => '${object(a['slot'])['mulaiPada']}'.compareTo(
        '${object(b['slot'])['mulaiPada']}',
      ),
    );
    _set({
      'nearestLoading': false,
      'nearestChoices': found,
      'nearestError': failed
          ? 'Sebagian slot belum dapat dimuat. Muat ulang untuk mencoba lagi.'
          : patient.errors['/jadwal-praktik'] == null
          ? null
          : 'Jadwal praktik belum dapat dimuat.',
    });
  }

  PatientBookingRequest prepare(String value) {
    patient.check();
    if (!patientVisitPaths.every(patient.snapshot.collections.containsKey) ||
        patient.errors.keys.any(patientVisitPaths.contains)) {
      throw const ApiException(
        409,
        'Daftar reservasi belum terverifikasi. Muat ulang sebelum mendaftar.',
      );
    }
    if (busy ||
        state.loading ||
        _uncertain != null ||
        state.values['needsReconciliation'] == true) {
      throw const ApiException(
        409,
        'Periksa hasil pendaftaran sebelumnya sebelum melanjutkan.',
      );
    }
    if (value != date) change({'date': value});
    final parsed = DateTime.tryParse(value), clinic = selectedService;
    if (parsed == null || calendarDate(parsed) != value) {
      throw const ApiException(
        400,
        'Tanggal pelayanan harus YYYY-MM-DD yang valid.',
      );
    }
    if (clinic == null ||
        clinic['aktif'] == false ||
        !(appointment
                ? ['HIBRIDA', 'JANJI_TEMU_DOKTER']
                : ['HIBRIDA', 'ANTREAN_HARIAN'])
            .contains(clinic['modeReservasi'])) {
      throw const ApiException(
        400,
        'Kanal pendaftaran tidak diizinkan untuk poliklinik ini.',
      );
    }
    final session = state
        .rows('schedules')
        .where((s) => s['id'] == sessionId && s['aktif'] != false)
        .firstOrNull;
    final slot = state
        .rows('slots')
        .where(
          (s) =>
              s['id'] == slotId && s['aktif'] != false && s['tersedia'] == true,
        )
        .firstOrNull;
    if (appointment && (session == null || slot == null)) {
      throw const ApiException(
        409,
        'Slot berubah. Pilih kembali slot yang tersedia.',
      );
    }
    return PatientBookingRequest(
      clinic: clinic,
      doctor:
          patient.snapshot.doctors
              .where((d) => d['id'] == doctorId)
              .firstOrNull ??
          const {},
      session: session ?? const {},
      slot: slot ?? const {},
      date: value,
      appointment: appointment,
      revision: revision,
    );
  }

  Json? _match(PatientBookingRequest request) {
    if (patient.errors.keys.any(patientVisitPaths.contains)) return null;
    if (request.appointment) {
      final matches = patient.snapshot.appointments
          .where(
            (a) =>
                (a['slotPraktikId'] ?? object(a['slotPraktik'])['id']) ==
                    request.slot['id'] &&
                object(a['tiket'])['status'] != 'DIBATALKAN' &&
                !_beforeIds.contains(object(a['tiket'])['id']),
          )
          .toList();
      return matches.length == 1 &&
              object(matches.single['tiket'])['id'] is String
          ? patientObject(matches.single['tiket'])
          : null;
    }
    final matches = patient.snapshot.tickets
        .where(
          (t) =>
              (t['layananId'] ?? object(t['layanan'])['id']) ==
                  request.clinic['id'] &&
              dateOnly(t['tanggalPelayanan'] ?? t['tanggalAntrean']) ==
                  request.date &&
              t['status'] != 'DIBATALKAN' &&
              !_beforeIds.contains(t['id']),
        )
        .toList();
    return matches.length == 1 ? matches.single : null;
  }

  void _recover() {
    if (_uncertain == null) return;
    final ticket = _match(_uncertain!);
    if (ticket == null) return;
    _uncertain = null;
    _set(
      {'resultId': ticket['id'], 'needsReconciliation': false},
      mutation: PatientMutation.success,
      clearError: true,
    );
  }

  Future<Json> submit(PatientBookingRequest request) async {
    if (!current ||
        request.revision != revision ||
        busy ||
        _uncertain != null ||
        state.values['needsReconciliation'] == true) {
      throw const ApiException(
        409,
        'Pilihan berubah selama konfirmasi. Periksa jadwal dan pilih slot kembali.',
      );
    }
    prepare(request.date);
    _commandRunning = true;
    try {
      _beforeIds = patient.snapshot.tickets.map((t) => t['id']).toSet();
      _set({}, mutation: PatientMutation.submitting, clearError: true);
      Json? result;
      Object? failure;
      try {
        result = await repository.book(request.appointment, request.body);
      } catch (error) {
        failure = patientError(error);
      }
      if (!current) throw const ApiException(401, 'Sesi pasien berubah.');
      if (failure != null && uncertainPatient(failure)) {
        _uncertain = request;
        _set(
          {},
          mutation: PatientMutation.unknown,
          error: 'Hasil pendaftaran belum pasti. Periksa reservasi; pendaftaran tidak diulang otomatis.',
        );
      }
      await patient.refresh();
      if (!current) throw const ApiException(401, 'Sesi pasien berubah.');
      if (failure == null) {
        final ticket = request.appointment
            ? patientObject(result!['tiket'])
            : result!;
        _set(
          {
            'resultId': ticket['id'],
            'slotId': null,
            'needsReconciliation': _overviewFailed,
          },
          mutation: PatientMutation.success,
          clearError: true,
        );
        return ticket;
      }
      if (_uncertain == null && state.mutation == PatientMutation.success) {
        return patient.snapshot.ticket('${state.values['resultId']}') ??
            _match(request)!;
      }
      _set(
        {'slotId': null},
        mutation: _uncertain == null
            ? PatientMutation.failure
            : PatientMutation.unknown,
        error: _uncertain == null ? '$failure' : state.error,
      );
      await refreshSelection();
      throw failure;
    } finally {
      _commandRunning = false;
      _catalogChanged();
    }
  }

  @override
  Future<void> close() {
    _closing = true;
    invalidate();
    _references.dispose();
    patient.removeListener(_catalogChanged);
    patient.invalidations.removeListener(_invalidated);
    return super.close();
  }
}
