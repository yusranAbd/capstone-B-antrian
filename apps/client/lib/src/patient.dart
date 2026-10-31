import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

import 'routing/route_policy.dart';

import 'package:flutter_bloc/flutter_bloc.dart';

import 'features/patient/data/patient_repository.dart';
import 'features/patient/application/patient_overview_cubit.dart';
import 'features/patient/application/patient_booking_cubit.dart';
import 'features/patient/data/patient_booking_repository.dart';
import 'features/patient/models/patient_models.dart';
import 'features/patient/models/patient_queue_models.dart';
import 'features/patient/application/patient_reservations_cubit.dart';
import 'features/patient/application/patient_ticket_cubit.dart';

import 'package:qr_flutter/qr_flutter.dart';

import 'api.dart';
import 'config.dart';
import 'widgets.dart';
import 'mobile_ui.dart';
import 'patient_design.dart';
import 'patient_agenda.dart';
import 'patient_sync.dart';
import 'doctor_schedule_ui.dart';
import 'doctor_professional.dart';
import 'patient_ui.dart';
import 'queueb_motion.dart';
import 'queueb_interaction_motion.dart';
import 'queueb_content_motion.dart';
import 'patient_home.dart';
import 'patient_home_v6.dart';
import 'patient_home_v7.dart';
import 'patient_home_v8.dart';
import 'patient_information.dart';
import 'patient_navigation.dart';
import 'user_profile.dart';
import 'patient_reservations.dart';
import 'patient_mobile_v5.dart';
import 'patient_scroll_shell.dart';

class PatientPage extends StatefulWidget {
  const PatientPage({
    super.key,
    required this.api,
    this.onDisplay,
    this.headerBuilder,
    this.repository,
    this.navigationShell,
    this.location,
  });
  final QueueApi api;
  final StatefulNavigationShell? navigationShell;
  final Uri? location;

  /// Optional externally-owned scope, useful for dependency injection.
  final PatientRepository? repository;
  final VoidCallback? onDisplay;
  final PreferredSizeWidget Function(bool home, VoidCallback activity)?
  headerBuilder;
  @override
  State<PatientPage> createState() => _PatientPageState();
}

class _PatientPageState extends State<PatientPage> {
  late final PatientRepository repository;
  late final PatientOverviewCubit overviewCubit;
  PatientUpdates get updates => repository.updates;
  late final PatientBookingCubit booking;
  late final PatientReservationsCubit reservations;
  int _tab = 0;
  int get tab => widget.navigationShell == null
      ? _tab
      : patientBranchTabs[widget.navigationShell!.currentIndex];
  set tab(int value) {
    if (widget.navigationShell == null) {
      _tab = value;
    } else if (value != 2) {
      final branch = patientBranchTabs.indexOf(value);
      if (branch >= 0) widget.navigationShell!.goBranch(branch);
    }
  }

  void _go(String path) {
    if (widget.navigationShell != null) context.go(path);
  }

  bool get _routedBooking =>
      widget.location?.path == '/patient/reservations/new' ||
      widget.location?.path.startsWith('/patient/reservations/doctors/') ==
          true;
  String? _hydratingUri, _routeError;
  bool _routeLoading = false;

  int get catalogRevision => booking.revision;
  bool profileVisited = false;
  bool get busy => reservations.busy || booking.busy;
  bool get loading =>
      [
        PatientLoad.initial,
        PatientLoad.loading,
        PatientLoad.refreshing,
      ].contains(overviewCubit.state.load) ||
      booking.state.loading;
  bool ticketDialogOpen = false, cancelReviewing = false;
  bool _reservationCreating = false;
  bool get reservationCreating =>
      widget.navigationShell == null ? _reservationCreating : _routedBooking;
  set reservationCreating(bool value) => _reservationCreating = value;
  bool get nearestLoading => booking.state.values['nearestLoading'] == true;
  set nearestLoading(bool value) => booking.change({'nearestLoading': value});
  String reservationMode = 'legacy', reservationQuery = '';
  String? reservationClinicId;
  String? get nearestError => booking.state.values['nearestError'] as String?;
  set nearestError(String? value) => booking.change({'nearestError': value});
  int reservationFlowVersion = 0;
  List<Json> get nearestChoices => booking.state.rows('nearestChoices');
  String? _error, message;
  String? get error =>
      _error ??
      booking.state.error ??
      reservations.state.error ??
      overviewCubit.state.error;
  set error(String? value) => _error = value;
  String? get serviceId => booking.serviceId;
  set serviceId(String? value) => booking.change({'serviceId': value});
  String? get doctorId => booking.doctorId;
  set doctorId(String? value) => booking.change({'doctorId': value});
  String? get sessionId => booking.sessionId;
  set sessionId(String? value) => booking.change({'sessionId': value});
  String? get slotId => booking.slotId;
  set slotId(String? value) => booking.change({'slotId': value});
  bool get appointment => booking.appointment;
  set appointment(bool value) => booking.change({'appointment': value});
  bool bookingStage = false, doctorDetail = false;
  bool reviewing = false;
  String search = '', channel = 'Semua';
  String homeQuery = '';
  final _homeEntrances = <String, QueueBMotionOnce>{};
  List<String>? _entranceServices;
  Widget _homeEntrance(Json service, Widget child) {
    final id = '${service['id']}';
    final ordinal = _entranceServices?.indexOf(id) ?? -1;
    if (ordinal < 0) return child;
    return QueueBContentEntrance(
      key: ValueKey(('home-service-motion', id)),
      once: _homeEntrances.putIfAbsent(id, QueueBMotionOnce.new),
      index: ordinal,
      child: child,
    );
  }

  PatientHomeMode homeMode = PatientHomeMode.walkIn;
  final homeSearch = TextEditingController();
  String? homeClinicId;
  List<Json> get clinicSchedules => booking.state.rows('clinicSchedules');
  set clinicSchedules(List<Json> value) =>
      booking.change({'clinicSchedules': value});
  List<Json> get homeSchedules => overviewCubit.state.snapshot.schedules;
  String? get homeScheduleError => overviewCubit.state.scheduleError;
  Map<String, String> get clinicAvailability =>
      (booking.state.values['availability'] as Map? ?? const {})
          .cast<String, String>();
  List<Json> get services => overviewCubit.state.snapshot.services
      .where((s) => s['aktif'] != false)
      .toList();
  List<Json> get serviceHours => overviewCubit.state.snapshot.serviceHours;
  bool get hoursAvailable =>
      overviewCubit.state.snapshot.collections.containsKey('/jadwal-layanan') &&
      !overviewCubit.state.errors.containsKey('/jadwal-layanan');
  List<Json> get doctors => overviewCubit.state.snapshot.doctors
      .where((d) => d['aktif'] != false)
      .toList();
  List<Json> get schedules => booking.state.rows('schedules');
  set schedules(List<Json> value) => booking.change({'schedules': value});
  List<Json> get slots => booking.state.rows('slots');
  set slots(List<Json> value) => booking.change({'slots': value});
  List<Json> get tickets => reservations.state.snapshot.tickets;
  List<Json> get appointments => reservations.state.snapshot.appointments;
  late final date = TextEditingController(text: widget.api.config.today);
  Json? get selectedService =>
      services.where((s) => s['id'] == serviceId).firstOrNull;
  List<Json> get matchingDoctors => doctors
      .where(
        (d) =>
            d['aktif'] != false &&
            rows(d['dokterLayanan']).any(
              (l) =>
                  l['layananId'] == serviceId &&
                  l['aktif'] == true &&
                  object(l['layanan'])['aktif'] != false,
            ),
      )
      .toList();
  List<String> get practiceDates =>
      clinicSchedules
          .where(
            (s) =>
                s['aktif'] != false &&
                (object(s['dokterLayanan'])['dokterId'] == doctorId ||
                    object(object(s['dokterLayanan'])['dokter'])['id'] ==
                        doctorId),
          )
          .map((s) => dateOnly(s['tanggal']))
          .where((d) => d.compareTo(widget.api.config.today) >= 0)
          .toSet()
          .toList()
        ..sort();

  String doctorAvailability(Json doctor) {
    final future =
        clinicSchedules
            .where(
              (s) =>
                  s['aktif'] != false &&
                  (object(s['dokterLayanan'])['dokterId'] == doctor['id'] ||
                      object(object(s['dokterLayanan'])['dokter'])['id'] ==
                          doctor['id']) &&
                  dateOnly(s['tanggal']).compareTo(widget.api.config.today) >=
                      0,
            )
            .toList()
          ..sort((a, b) => '${a['mulaiPada']}'.compareTo('${b['mulaiPada']}'));
    if (loading) return 'Memuat jadwal praktik…';
    if (error != null) return 'Jadwal belum dapat dimuat. Coba lagi.';
    if (future.isEmpty) return 'Belum ada jadwal praktik mendatang.';
    return '${patientDate('${future.first['tanggal']}')} · ${patientTime(future.first, widget.api.config)}\n${clinicAvailability['${doctor['id']}'] ?? 'Lihat slot untuk ketersediaan aktual'}';
  }

  Future<void> loadClinicSchedules() => booking.loadClinicSchedules();

  Future<void> chooseDoctor(Json doctor) async {
    setState(() {
      doctorId = '${doctor['id']}';
      doctorDetail = true;
      appointment = selectedService?['modeReservasi'] != 'ANTREAN_HARIAN';
      final dates = practiceDates;
      if (!dates.contains(date.text) && dates.isNotEmpty) {
        date.text = dates.first;
      }
    });
    _go(
      Uri(
        path: '/patient/reservations/doctors/${doctor['id']}',
        queryParameters: serviceId == null ? null : {'clinic': serviceId!},
      ).toString(),
    );
    await loadSchedules();
  }

  @override
  void initState() {
    super.initState();
    repository = widget.repository ?? PatientRepository(widget.api);
    overviewCubit = PatientOverviewCubit(repository);
    booking = PatientBookingCubit(PatientBookingRepository(repository));
    reservations = PatientReservationsCubit(repository);
    repository.addListener(_scopeChanged);
    unawaited(load().then((_) => _hydrateRoute()));
  }

  @override
  void didUpdateWidget(covariant PatientPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.location != widget.location) {
      _routeLoading = false;
      _routeError = null;
      _hydratingUri = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_hydrateRoute());
      });
    }
  }

  Future<void> _hydrateRoute() async {
    final uri = widget.location;
    if (uri == null ||
        !_routedBooking ||
        !repository.active ||
        _hydratingUri == uri.toString()) {
      return;
    }
    _hydratingUri = uri.toString();
    final isDoctor = uri.path.startsWith('/patient/reservations/doctors/');
    final id = isDoctor ? uri.pathSegments.last : null;
    // An explicit UI selection is already validated by the feature.
    if (id != null &&
        doctorId == id &&
        serviceId == uri.queryParameters['clinic']) {
      return;
    }
    if (!isDoctor &&
        serviceId != null &&
        uri.queryParameters['clinic'] == serviceId) {
      return;
    }
    setState(() {
      _routeLoading = true;
      _routeError = null;
    });
    final expected = uri.toString();
    bool current() =>
        mounted && repository.active && widget.location?.toString() == expected;
    try {
      if (services.isEmpty || (isDoctor && doctors.isEmpty)) {
        await readOverview();
      }
      if (!current()) return;
      final clinic = uri.queryParameters['clinic'];
      if (isDoctor) {
        final doctor = doctors.where((d) => d['id'] == id).firstOrNull;
        final links = doctor == null
            ? <Json>[]
            : rows(doctor['dokterLayanan'])
                  .where(
                    (l) =>
                        l['aktif'] == true &&
                        services.any((s) => s['id'] == l['layananId']) &&
                        (clinic == null || l['layananId'] == clinic),
                  )
                  .toList();
        if (doctor == null || links.length != 1) {
          throw const ApiException(
            404,
            'Dokter atau poliklinik tidak tersedia. Pilih kembali dari daftar.',
          );
        }
        await _selectService('${links.single['layananId']}');
        if (!current()) return;
        setState(() {
          doctorId = id;
          doctorDetail = true;
          final dates = practiceDates;
          if (!dates.contains(date.text) && dates.isNotEmpty) {
            date.text = dates.first;
          }
        });
        await loadSchedules();
      } else {
        if (clinic != null) {
          if (!services.any((s) => s['id'] == clinic)) {
            throw const ApiException(404, 'Poliklinik tidak tersedia.');
          }
          await _selectService(clinic);
        } else {
          setState(() {
            _reservationCreating = true;
            reservationMode = uri.queryParameters['mode'] ?? 'clinics';
          });
        }
      }
    } catch (_) {
      if (current()) {
        setState(
          () => _routeError = 'Pilihan tidak tersedia. Kembali ke daftar reservasi dan pilih kembali.',
        );
      }
    } finally {
      if (current()) setState(() => _routeLoading = false);
    }
  }

  void _scopeChanged() {
    if (mounted && repository.active) {
      repository.configureQueueScope(
        homeWalkInClinics(
          repository.snapshot.services,
          repository.snapshot.doctors,
          '',
        ).map((s) => '${s['id']}'),
        widget.api.config.today,
      );
    }
    if (mounted && !repository.active) {
      setState(() {
        _error = message = null;
        reservationCreating = reviewing = cancelReviewing = false;
        homeSearch.clear();
        date.clear();
        homeQuery = search = reservationQuery = '';
      });
    }
  }

  Future<void> load() async {
    if (!mounted) return;
    setState(() {
      error = null;
    });
    await readOverview();
  }

  Future<void> readOverview() async {
    await overviewCubit.refresh(
      paths: [1, 2, 3, 4].contains(tab) && !reservationCreating
          ? patientVisitPaths
          : patientOverviewPaths,
    );
    if (reservationCreating) await booking.refreshSelection();
    if (!mounted || !repository.active) return;
    setState(() => error = overviewCubit.state.error);
  }

  Future<void> loadSchedules() async {
    final requestedDate = date.text.trim();
    final requestedDoctor = doctorId;
    booking.change({'date': requestedDate});
    setState(() => bookingStage = true);
    await booking.loadSchedules();
    // One available session needs no second selection step. Load its slots
    // through the existing Cubit, never from a preview or a mock value.
    if (!mounted ||
        !repository.active ||
        !doctorDetail ||
        !appointment ||
        doctorId != requestedDoctor ||
        date.text.trim() != requestedDate ||
        booking.state.error != null) {
      return;
    }
    final validSessions = schedules
        .where((s) => dateOnly(s['tanggal']) == requestedDate)
        .toList();
    if (validSessions.length == 1 &&
        sessionId != '${validSessions.single['id']}') {
      await loadSlots('${validSessions.single['id']}');
    }
  }

  Future<void> loadSlots(String id) => booking.loadSlots(id);

  Future<void> book() async {
    if (busy || reviewing) return;
    PatientBookingRequest request;
    try {
      request = booking.prepare(date.text.trim());
    } catch (e) {
      setState(() => error = '$e');
      return;
    }
    reviewing = true;
    final accepted = request.appointment
        ? await showDialog<bool>(
                context: context,
                animationStyle: QueueBMotion.modalStyle(context),
                builder: (_) => QueueBModalMotion(
                  child: AppointmentReview(
                    doctor: request.doctor,
                    clinic: request.clinic,
                    session: request.session,
                    slot: request.slot,
                    config: widget.api.config,
                  ),
                ),
              ) ==
              true
        : await confirm(
            context,
            'Daftarkan walk-in pada ${label(request.clinic)} tanggal ${request.date}?',
          );
    reviewing = false;
    if (!mounted || !accepted) return;
    setState(() {
      error = null;
      message = null;
    });
    try {
      final issued = await booking.submit(request);
      if (!mounted || !repository.active) return;
      setState(() {
        message =
            '${request.appointment ? 'Janji temu berhasil dibuat.' : 'Pendaftaran berhasil.'}${issued['nomorAntrean'] == null ? '' : ' Tiket ${issued['nomorAntrean']}.'} Tiket dapat dilihat di Riwayat.';
        // Legacy non-routed patient view uses its own tab state.
        if (widget.navigationShell == null) {
          tab = 2;
          reservationCreating = false;
        }
      });
      // The routed app keeps booking, QR and ticket detail routes intact,
      // but uses Riwayat as the single visible ticket/reservation list.
      if (widget.navigationShell != null) {
        context.go('/patient/reservations');
      }
    } catch (e) {
      if (mounted && repository.active) {
        setState(() => error = booking.state.error == null ? '$e' : null);
      }
    }
  }

  Future<void> cancel(Json appt) async {
    if (busy || cancelReviewing) return;
    cancelReviewing = true;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Batalkan reservasi?'),
        content: const Text(
          'Reservasi yang dibatalkan tidak dapat digunakan untuk check-in.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Kembali'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Ya, Batalkan'),
          ),
        ],
      ),
    );
    cancelReviewing = false;
    if (!mounted || accepted != true || busy) return;
    setState(() {
      error = null;
      message = null;
    });
    try {
      await reservations.cancel('${appt['id']}');
      if (mounted && repository.active) {
        setState(() => message = 'Reservasi dibatalkan.');
      }
    } catch (e) {
      if (mounted && repository.active) {
        setState(() => error = reservations.state.error == null ? '$e' : null);
      }
    }
  }

  Future<void> openTicket(Json ticket, {bool issueQrOnOpen = false}) async {
    if (ticketDialogOpen) return;
    ticketDialogOpen = true;
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => _TicketDialog(
          api: widget.api,
          repository: repository,
          ticket: ticket,
          issueQrOnOpen: issueQrOnOpen,
          appointment: appointments
              .where((a) => object(a['tiket'])['id'] == ticket['id'])
              .firstOrNull,
        ),
      );
    } finally {
      ticketDialogOpen = false;
    }
    if (mounted) await load();
  }

  @override
  void dispose() {
    reservations.close();
    booking.close();
    overviewCubit.close();
    repository.removeListener(_scopeChanged);
    if (widget.repository == null) repository.dispose();
    date.dispose();
    homeSearch.dispose();
    super.dispose();
  }

  Future<void> selectService(String? value) {
    final pending = _selectService(value);
    _go(
      Uri(
        path: '/patient/reservations/new',
        queryParameters: value == null ? null : {'clinic': value},
      ).toString(),
    );
    return pending;
  }

  Future<void> _selectService(String? value) {
    setState(() {
      booking.invalidate();
      serviceId = value;
      reservationCreating = true;
      booking.clearAvailability();
      search = '';
      tab = 2;
      doctorDetail = false;
      doctorId = sessionId = slotId = null;
      schedules = [];
      slots = [];
      bookingStage = false;
      clinicSchedules = [];
      appointment = selectedService?['modeReservasi'] != 'ANTREAN_HARIAN';
      if (channel == 'Walk-in' &&
          selectedService?['modeReservasi'] != 'JANJI_TEMU_DOKTER') {
        appointment = false;
      }
    });
    return loadClinicSchedules();
  }

  void startRegistration(bool isAppointment) {
    setState(() {
      reservationCreating = true;
      reservationMode = 'legacy';
      booking.invalidateNearest();
      reservationFlowVersion++;
      tab = 2;
      channel = isAppointment ? 'Janji temu' : 'Walk-in';
      booking.clearAvailability();
      appointment = isAppointment;
      bookingStage = false;
      doctorDetail = false;
      serviceId = doctorId = sessionId = slotId = null;
      booking.invalidate();
      schedules = [];
      slots = [];
      search = '';
      clinicSchedules = [];
    });
  }

  void showReservations() {
    if (busy) return;
    setState(() {
      tab = 2;
      reservationCreating = false;
      booking.invalidate();
      booking.invalidateNearest();
      reservationFlowVersion++;
    });
    widget.navigationShell?.goBranch(1, initialLocation: true);
  }

  Future<void> createReservation() async {
    if (busy || loading) return;
    final method = await chooseReservationMethod(context);
    if (!mounted || method == null || busy) return;
    setState(() {
      tab = 2;
      reservationCreating = true;
      reservationMode = method;
      nearestLoading = false;
      nearestError = null;
      reservationQuery = '';
      reservationClinicId = null;
      serviceId = doctorId = sessionId = slotId = null;
      bookingStage = doctorDetail = false;
      channel = 'Semua';
      search = '';
      error = message = null;
      clinicSchedules = schedules = slots = [];
      booking.invalidate();
      booking.invalidateNearest();
      reservationFlowVersion++;
    });
    _go(
      Uri(
        path: '/patient/reservations/new',
        queryParameters: {'mode': method},
      ).toString(),
    );
    if (method == 'nearest') await loadNearest();
  }

  Future<void> loadNearest() => booking.loadNearest();

  Future<void> chooseReservationDoctor(
    Json doctor,
    Json clinic, {
    Json? session,
    Json? slot,
  }) async {
    if (busy || loading) return;
    final version = ++reservationFlowVersion;
    booking.invalidateNearest();
    await selectService('${clinic['id']}');
    if (!mounted || version != reservationFlowVersion || tab != 2) return;
    if (session != null) date.text = dateOnly(session['tanggal']);
    await chooseDoctor(doctor);
    if (!mounted || version != reservationFlowVersion || tab != 2) return;
    // Keep the nearest booking on the doctor detail route. A single session
    // may already have been loaded automatically by loadSchedules().
    if (session != null && schedules.any((s) => s['id'] == session['id'])) {
      if (sessionId != '${session['id']}') {
        await loadSlots('${session['id']}');
      }
      if (mounted &&
          version == reservationFlowVersion &&
          slot != null &&
          slots.any((s) => s['id'] == slot['id'] && s['tersedia'] == true)) {
        setState(() => slotId = '${slot['id']}');
      }
    }
  }

  Widget reservationDoctors(BuildContext context) {
    final nearest = reservationMode == 'nearest';
    final choices = <Json>[];
    if (nearest) {
      choices.addAll(nearestChoices);
    } else {
      for (final doctor in doctors) {
        for (final link in rows(
          doctor['dokterLayanan'],
        ).where((l) => l['aktif'] == true)) {
          final clinic = services
              .where(
                (c) =>
                    c['id'] ==
                        (link['layananId'] ?? object(link['layanan'])['id']) &&
                    c['modeReservasi'] != 'ANTREAN_HARIAN',
              )
              .firstOrNull;
          if (clinic == null) continue;
          final sessions = booking.reservableSessions.where((s) {
            final pair = object(s['dokterLayanan']);
            return (pair['dokterId'] ?? object(pair['dokter'])['id']) ==
                    doctor['id'] &&
                (pair['layananId'] ?? object(pair['layanan'])['id']) ==
                    clinic['id'];
          });
          choices.add({
            'doctor': doctor,
            'clinic': clinic,
            'session': sessions.firstOrNull,
          });
        }
      }
    }
    final visible = choices
        .where(
          (c) =>
              (reservationClinicId == null ||
                  object(c['clinic'])['id'] == reservationClinicId) &&
              ('${label(object(c['doctor']))} ${object(c['doctor'])['spesialisasi'] ?? ''} ${label(object(c['clinic']))}')
                  .toLowerCase()
                  .contains(reservationQuery),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PatientHeading(
          title: nearest ? 'Jadwal Terdekat' : 'Buat Reservasi',
          onBack: showReservations,
        ),
        TextField(
          key: ValueKey(reservationMode),
          onChanged: (v) =>
              setState(() => reservationQuery = v.toLowerCase().trim()),
          decoration: const InputDecoration(
            hintText: 'Cari dokter, poliklinik, atau spesialisasi...',
            hintStyle: TextStyle(fontSize: 12),
            prefixIcon: Icon(Icons.search),
          ),
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final c in [
                <String, dynamic>{'id': null, 'nama': 'Semua'},
                ...services.where(
                  (c) => c['modeReservasi'] != 'ANTREAN_HARIAN',
                ),
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(label(c)),
                    showCheckmark: false,
                    selected: reservationClinicId == c['id'],
                    onSelected: (_) =>
                        setState(() => reservationClinicId = c['id']),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (nearestLoading)
          const LinearProgressIndicator(semanticsLabel: 'Membaca slot aktual'),
        if (nearestError != null && nearest)
          MobileNotice(nearestError!, error: true),
        if (homeScheduleError != null && !nearest)
          MobileNotice(homeScheduleError!, error: true),
        if (visible.isEmpty && !nearestLoading && !loading)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              nearest
                  ? 'Belum ada slot tersedia yang sesuai.'
                  : 'Tidak ada dokter yang sesuai.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: PatientDesign.muted),
            ),
          ),
        // The outer booking list owns scrolling. Only the nearest view is bounded
        // locally; a limited page avoids eagerly building every available slot.
        ReservationChoices(
          choices: visible,
          config: widget.api.config,
          busy: busy || loading,
          onSelect: (c) => chooseReservationDoctor(
            object(c['doctor']),
            object(c['clinic']),
            session: c['slot'] == null ? null : object(c['session']),
            slot: c['slot'] == null ? null : object(c['slot']),
          ),
        ),
        OutlinedButton.icon(
          onPressed: busy || loading || nearestLoading
              ? null
              : () async {
                  await load();
                },
          icon: const Icon(Icons.refresh),
          label: const Text('Muat ulang pilihan'),
        ),
      ],
    );
  }

  List<Widget> _catalog(BuildContext context) {
    final visible = services
        .where(
          (s) =>
              (channel != 'Walk-in' ||
                  s['modeReservasi'] != 'JANJI_TEMU_DOKTER') &&
              (channel != 'Janji temu' ||
                  s['modeReservasi'] != 'ANTREAN_HARIAN') &&
              (label(s).toLowerCase().contains(search) ||
                  doctors.any(
                    (d) =>
                        label(d).toLowerCase().contains(search) &&
                        rows(d['dokterLayanan']).any(
                          (l) =>
                              l['layananId'] == s['id'] && l['aktif'] == true,
                        ),
                  )),
        )
        .toList();
    return [
      TextField(
        decoration: const InputDecoration(
          hintText: 'Cari poliklinik atau dokter',
          prefixIcon: Icon(Icons.search),
        ),
        onChanged: (v) => setState(() => search = v.toLowerCase().trim()),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        children: [
          for (final c in ['Semua', 'Janji temu', 'Walk-in'])
            FilterChip(
              label: Text(c),
              selected: channel == c,
              onSelected: busy || loading
                  ? null
                  : (_) => setState(() => channel = c),
            ),
        ],
      ),
      const SizedBox(height: 12),
      if (visible.isEmpty && !loading)
        const EmptyState(text: 'Tidak ada poliklinik yang sesuai pencarian.'),
      LayoutBuilder(
        builder: (context, box) => Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final s in visible)
              SizedBox(
                width: (box.maxWidth - 12) / 2,
                height: 112,
                child: ClinicCard(
                  name: label(s),
                  selected: serviceId == s['id'],
                  onTap: busy || loading
                      ? null
                      : () => selectService('${s['id']}'),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 20),
    ];
  }

  List<Json> clinicsForQuery(String query) => services
      .where(
        (clinic) =>
            label(clinic).toLowerCase().contains(query) ||
            doctors.any(
              (doctor) =>
                  ('${label(doctor)} ${doctor['spesialisasi'] ?? ''}')
                      .toLowerCase()
                      .contains(query) &&
                  rows(doctor['dokterLayanan']).any(
                    (link) =>
                        link['layananId'] == clinic['id'] &&
                        link['aktif'] == true,
                  ),
            ),
      )
      .toList();

  Widget _home(BuildContext context) {
    final active = nearestHomeTicket(
      tickets,
      appointments,
      widget.api.config.today,
    );
    final visit = appointments
        .where((a) => object(a['tiket'])['id'] == active?['id'])
        .firstOrNull;
    final appointmentClinics = services.where(supportsHomeAppointment).toList();
    final previews = homeDoctorPreviews(
      doctors,
      appointmentClinics,
      homeSchedules,
      widget.api.config,
      homeQuery,
      clinicId: appointmentClinics.any((c) => c['id'] == homeClinicId)
          ? homeClinicId
          : null,
    );
    final walkIns = homeWalkInClinics(services, doctors, homeQuery);
    if (!loading && walkIns.isNotEmpty) {
      _entranceServices ??= walkIns.take(5).map((s) => '${s['id']}').toList();
    }
    return PatientHomeTabs(
      value: homeMode,
      onChanged: busy ? null : (mode) => setState(() => homeMode = mode),
      headerSlivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (loading)
                  const LinearProgressIndicator(
                    semanticsLabel: 'Memuat data pelayanan',
                  ),
                ListenableBuilder(
                  listenable: widget.api,
                  builder: (_, _) => PatientHomeWelcomeV8(
                    name: '${widget.api.user?['nama'] ?? 'Pasien'}',
                    now: DateTime.now(),
                    controller: homeSearch,
                    onSearch: (v) =>
                        setState(() => homeQuery = v.toLowerCase().trim()),
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  MobileNotice(error!, error: true),
                  TextButton.icon(
                    onPressed: busy || loading ? null : load,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Coba lagi'),
                  ),
                ],
                ValueListenableBuilder<String>(
                  valueListenable: updates.status,
                  builder: (_, status, _) =>
                      status.contains('terputus') ||
                          status.contains('belum tersambung')
                      ? const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text(
                            'Koneksi terputus. Data terakhir ditampilkan; pembaruan berkala tetap berjalan.',
                            style: TextStyle(
                              fontSize: 12,
                              color: PatientDesign.muted,
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
                const SizedBox(height: 12),
                PatientHomeVisitV8(
                  ticket: active,
                  appointment: visit,
                  config: widget.api.config,
                  loading: loading,
                  unavailable: error != null,
                  onOpen: busy || active == null
                      ? null
                      : () => openTicket(active),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ],
      walkInSlivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          sliver: loading
              ? const SliverToBoxAdapter(child: PatientHomeLoading())
              : walkIns.isEmpty
              ? const SliverToBoxAdapter(
                  child: PatientHomeEmpty(
                    text: 'Tidak ada layanan antrean harian yang sesuai pencarian.',
                  ),
                )
              : SliverList.builder(
                  itemCount: walkIns.length,
                  itemBuilder: (context, index) => _homeEntrance(
                    walkIns[index],
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: ValueListenableBuilder<PatientQueueState>(
                        valueListenable: overviewCubit.queueState,
                        builder: (context, queue, _) => PatientHomeService(
                          clinic: walkIns[index],
                          hours: patientServiceHours(
                            serviceHours,
                            '${walkIns[index]['id']}',
                            widget.api.config.today,
                            available: hoursAvailable,
                          ),
                          queue: queue.forService(
                            '${walkIns[index]['id']}',
                            widget.api.config.today,
                          ),
                          ticket: homeServiceTicket(
                            tickets,
                            '${walkIns[index]['id']}',
                            widget.api.config.today,
                            widget.api.user?['id']?.toString(),
                          ),
                          onTap: busy
                              ? null
                              : () {
                                  startRegistration(false);
                                  selectService('${walkIns[index]['id']}');
                                },
                        ),
                      ),
                    ),
                  ),
                ),
        ),
      ],
      appointmentSlivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final clinic in <Json>[
                        {'nama': 'Semua'},
                        ...appointmentClinics,
                      ])
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(label(clinic)),
                            selected: clinic['id'] == homeClinicId,
                            showCheckmark: false,
                            selectedColor: PatientDesign.primary,
                            labelStyle: TextStyle(
                              fontSize: 12,
                              color: clinic['id'] == homeClinicId
                                  ? Colors.white
                                  : PatientDesign.ink,
                            ),
                            onSelected: busy
                                ? null
                                : (_) => setState(
                                    () =>
                                        homeClinicId = clinic['id'] as String?,
                                  ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    'Dokter hari ini',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: PatientDesign.navy,
                    ),
                  ),
                ),
                if (homeScheduleError != null)
                  PatientHomeEmpty(
                    text: homeScheduleError!,
                    action: 'Muat ulang jadwal',
                    onPressed: busy || loading ? null : load,
                  ),
                if (loading)
                  const PatientHomeLoading()
                else if (homeScheduleError == null && previews.isEmpty)
                  PatientHomeEmpty(
                    text: homeQuery.isEmpty && homeClinicId == null
                        ? 'Belum ada dokter dengan jadwal praktik hari ini.'
                        : 'Tidak ada dokter praktik hari ini yang sesuai pencarian atau poliklinik.',
                  ),
              ],
            ),
          ),
        ),
        if (!loading && homeScheduleError == null)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            sliver: SliverList.builder(
              itemCount: previews.length,
              itemBuilder: (context, index) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: PatientHomeDoctorV6(
                  preview: previews[index],
                  config: widget.api.config,
                  scheduleUnavailable: homeScheduleError != null,
                  onTap: busy
                      ? null
                      : () async {
                          startRegistration(true);
                          final pending = selectService(
                            '${previews[index].clinic['id']}',
                          );
                          final revision = catalogRevision;
                          await pending;
                          if (mounted &&
                              revision == catalogRevision &&
                              error == null &&
                              (widget.navigationShell == null
                                  ? tab == 2
                                  : GoRouter.of(this.context)
                                        .routeInformationProvider
                                        .value
                                        .uri
                                        .path
                                        .startsWith(
                                          '/patient/reservations/',
                                        ))) {
                            await chooseDoctor(previews[index].doctor);
                          }
                        },
                ),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => MultiBlocProvider(
    providers: [
      BlocProvider.value(value: overviewCubit),
      BlocProvider.value(value: booking),
      BlocProvider.value(value: reservations),
    ],
    child: BlocBuilder<PatientOverviewCubit, PatientOverviewState>(
      builder: (context, _) =>
          BlocConsumer<PatientBookingCubit, PatientBookingState>(
            listener: (context, state) {
              if (bookingStage && (serviceId == null || doctorId == null)) {
                setState(() {
                  bookingStage = doctorDetail = false;
                });
              }
            },
            builder: (context, _) =>
                BlocBuilder<PatientReservationsCubit, PatientReservationsState>(
                  builder: (context, _) => content(context),
                ),
          ),
    ),
  );

  Widget content(BuildContext context) => !repository.active
      ? const SizedBox.shrink()
      : Theme(
          data: PatientMobileV5.theme,
          child: _PatientViewScope(
            owner: this,
            child: PopScope(
              canPop:
                  kIsWeb ||
                  widget.navigationShell == null ||
                  (!busy &&
                      (tab == 0 ||
                          !RoutePolicy.patientPaths.contains(
                            widget.location?.path,
                          ))),
              onPopInvokedWithResult: (didPop, _) {
                if (!didPop &&
                    !kIsWeb &&
                    !busy &&
                    widget.navigationShell != null) {
                  widget.navigationShell!.goBranch(0);
                }
              },
              child: PatientScrollShell(
                pageKey:
                    '$tab:${tab == 0 ? homeMode.name : ''}:$reservationCreating:$serviceId:$bookingStage:$doctorDetail',
                header: tab == 0
                    ? PatientHomeAppBarV8(
                        api: widget.api,
                        height: PatientHomeAppBarV8.heightFor(context),
                        onProfile: () {
                          if (widget.navigationShell == null) {
                            setState(() => tab = 5);
                          } else {
                            _go('/patient/profile');
                          }
                        },
                        onNotifications: () => showDialog<void>(
                          context: context,
                          builder: (c) => AlertDialog(
                            title: const Text('Notifikasi'),
                            content: const Text(
                              'Notifikasi belum tersedia. Periksa status terbaru melalui Riwayat.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(c),
                                child: const Text('Tutup'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : null,
                acceptNestedScrolls: tab == 0,
                floatingActionButton: tab == 2 && !reservationCreating
                    ? FloatingActionButton.extended(
                        heroTag: 'create-reservation',
                        onPressed: busy || loading ? null : createReservation,
                        backgroundColor: PatientDesign.darkTeal,
                        foregroundColor: Colors.white,
                        elevation: 2,
                        icon: const Icon(Icons.add),
                        label: const Text(
                          'Buat Reservasi',
                          style: TextStyle(fontSize: 13),
                        ),
                      )
                    : null,
                floatingActionButtonLocation:
                    FloatingActionButtonLocation.endFloat,
                bottomNavigationBar: PatientBottomNavigation(
                  selectedIndex: patientBottomIndex(tab),
                  onSelected: busy
                      ? null
                      : (i) {
                          if (widget.navigationShell case final shell?) {
                            reservationFlowVersion++;
                            booking.invalidateNearest();
                            if (i == 1) {
                              showReservations();
                            } else {
                              shell.goBranch(patientBottomBranches[i]);
                            }
                          } else {
                            setState(() {
                              tab = patientBottomTabs[i];
                              if (tab == 5) profileVisited = true;
                              reservationFlowVersion++;
                              booking.invalidateNearest();
                              if (tab == 2) reservationCreating = false;
                            });
                          }
                        },
                ),
                body: ColoredBox(
                  color: tab == 0
                      ? PatientHomeV8Style.background
                      : PatientDesign.background,
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: tab == 0 ? 680 : 760,
                      ),
                      child:
                          widget.navigationShell ??
                          IndexedStack(
                            index: tab == 5
                                ? 2
                                : tab == 2 && !reservationCreating
                                ? 0
                                : 1,
                            children: [
                              _reservationHistory(),
                              tab == 0
                                  ? _home(context)
                                  : tab == 1
                                  ? _reservationHistory()
                                  : tab == 3
                                  ? PatientAgenda(
                                      appointments: appointments,
                                      config: widget.api.config,
                                      loading: loading,
                                      busy: busy,
                                      error: error,
                                      message: message,
                                      onRefresh: load,
                                      onTicket: (ticket) => openTicket(ticket),
                                    )
                                  : tab == 6
                                  ? _information()
                                  : ListView(
                                      key: PageStorageKey(
                                        '$tab:$serviceId:$bookingStage:$doctorDetail',
                                      ),
                                      padding: const EdgeInsets.all(16),
                                      children: [
                                        if (error != null) ...[
                                          MobileNotice(error!, error: true),
                                          TextButton.icon(
                                            onPressed: busy || loading
                                                ? null
                                                : load,
                                            icon: const Icon(Icons.refresh),
                                            label: const Text('Coba lagi'),
                                          ),
                                        ],
                                        if (message != null)
                                          MobileNotice(message!),
                                        if (loading)
                                          const LinearProgressIndicator(
                                            semanticsLabel:
                                                'Memuat data pelayanan',
                                          ),
                                        if (tab == 2) _registration(context),
                                        if (tab == 4) _history(context),
                                      ],
                                    ),
                              if (profileVisited)
                                UserProfilePage(
                                  api: widget.api,
                                  onReturnToPatient: () =>
                                      setState(() => tab = 0),
                                )
                              else
                                const SizedBox(),
                            ],
                          ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

  Widget branch(BuildContext context, int index, {bool bookingView = false}) {
    if (!repository.active) return const SizedBox.shrink();
    return switch (index) {
      0 => _home(context),
      1 =>
        bookingView
            ? ListView(
                key: const PageStorageKey('booking-route'),
                padding: const EdgeInsets.all(16),
                children: [
                  if (_routeLoading) const LinearProgressIndicator(),
                  if (error != null) ...[
                    MobileNotice(error!, error: true),
                    TextButton.icon(
                      onPressed: busy || loading ? null : load,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Coba lagi'),
                    ),
                  ],
                  if (loading) const LinearProgressIndicator(),
                  if (message != null) MobileNotice(message!),
                  if (_routeError != null) ...[
                    MobileNotice(_routeError!, error: true),
                    TextButton(
                      onPressed: showReservations,
                      child: const Text('Kembali ke reservasi'),
                    ),
                  ] else if (!_routeLoading)
                    _registration(context),
                ],
              )
            : _reservationHistory(),
      // Kept for legacy branch identity and ticket-detail deep links only.
      2 => _reservationHistory(),
      3 => PatientAgenda(
        appointments: appointments,
        config: widget.api.config,
        loading: loading,
        busy: busy,
        error: error,
        message: message,
        onRefresh: load,
        onTicket: (ticket) => openTicket(ticket),
      ),
      4 => UserProfilePage(
        api: widget.api,
        onReturnToPatient: () => widget.navigationShell!.goBranch(0),
      ),
      5 => _information(),
      _ => const SizedBox.shrink(),
    };
  }

  Widget _information() => PatientInformation(
    services: services,
    hours: serviceHours,
    date: widget.api.config.today,
    timeZone: widget.api.config.serviceTimeZone,
    hoursAvailable: hoursAvailable,
    loading: loading,
    error: error,
    hoursError: overviewCubit.state.errors.containsKey('/jadwal-layanan')
        ? 'Jam operasional belum dapat dimuat. Coba muat ulang informasi.'
        : null,
    onRefresh: busy || loading ? null : load,
  );

  /// Booking controls live inside the *same* schedule card as the month/day
  /// picker. The Cubit remains authoritative for sessions, slots and mutation.
  Widget _doctorScheduleBooking(BuildContext context) {
    final day = date.text.trim();
    final availableSessions =
        schedules.where((s) => dateOnly(s['tanggal']) == day).toList()..sort(
          (a, b) =>
              '${a['mulaiPada'] ?? ''}'.compareTo('${b['mulaiPada'] ?? ''}'),
        );
    final sessionIds = availableSessions.map((s) => '${s['id']}').toSet();
    final selected = sessionId != null && sessionIds.contains(sessionId);
    final availableSlots = selected ? slots : <Json>[];
    final hasChosenAvailableSlot =
        selected &&
        slotId != null &&
        availableSlots.any((s) => s['id'] == slotId && s['tersedia'] == true);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (loading)
          const LinearProgressIndicator(
            semanticsLabel: 'Memuat jadwal dan slot konsultasi',
          ),
        if (!loading && availableSessions.isEmpty && error == null)
          const Text('Tidak ada sesi konsultasi pada tanggal ini.'),
        if (availableSessions.length > 1) ...[
          const Text(
            'Pilih sesi praktik',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: PatientDesign.navy,
            ),
          ),
          const SizedBox(height: 8),
        ],
        // A session is represented exactly once: time, room and its selection.
        for (final session in availableSessions) ...[
          OutlinedButton(
            onPressed: busy || loading
                ? null
                : () => loadSlots('${session['id']}'),
            style: OutlinedButton.styleFrom(
              alignment: Alignment.centerLeft,
              backgroundColor: sessionId == '${session['id']}'
                  ? PatientDesign.mint
                  : Colors.white,
              padding: const EdgeInsets.all(12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PatientInfoRow(
                  icon: Icons.schedule_outlined,
                  title: 'Waktu praktik',
                  value: patientTime(session, widget.api.config),
                ),
                const Divider(height: 18),
                PatientInfoRow(
                  icon: Icons.room_outlined,
                  title: 'Ruang / Loket',
                  value: _doctorRoomLabel(object(session['loket'])),
                ),
                if (availableSessions.length > 1) ...[
                  const SizedBox(height: 6),
                  Text(
                    sessionId == '${session['id']}'
                        ? 'Sesi terpilih'
                        : 'Ketuk untuk melihat slot',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (selected && !loading && availableSlots.isEmpty)
          const EmptyState(text: 'Belum ada slot konsultasi pada sesi ini.'),
        if (selected && availableSlots.isNotEmpty) ...[
          const SizedBox(height: 10),
          const Text(
            'Pilih slot konsultasi',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: PatientDesign.navy,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Ketersediaan mengikuti data terbaru dari server.',
            style: TextStyle(fontSize: 12, color: PatientDesign.muted),
          ),
          const SizedBox(height: 10),
          if (!availableSlots.any((s) => s['tersedia'] == true))
            EmptyState(
              text:
                  availableSlots.every(
                    (s) => consultationSlotStatus(s) == 'Penuh',
                  )
                  ? 'Seluruh slot penuh. Pilih tanggal atau sesi lain.'
                  : 'Tidak ada slot yang dapat dipesan pada sesi ini.',
            ),
          ConsultationSlotGrid(
            slots: availableSlots,
            config: widget.api.config,
            value: slotId,
            enabled: !busy && !loading,
            onChanged: (value) => setState(() => slotId = value),
          ),
        ],
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: busy || loading || !hasChosenAvailableSlot ? null : book,
          icon: const Icon(Icons.arrow_forward),
          label: Text(busy ? 'Memproses…' : 'Lanjutkan Reservasi'),
        ),
      ],
    );
  }

  String _doctorRoomLabel(Json room) {
    if (room.isEmpty) return 'Belum ditentukan';
    final code = '${room['kode'] ?? ''}'.trim();
    final name = label(room).trim();
    if (code.isEmpty) return name.isEmpty ? 'Belum ditentukan' : name;
    return name.isEmpty || name == code ? code : '$code · $name';
  }

  Widget _registration(BuildContext context) {
    if (serviceId == null && ['doctors', 'nearest'].contains(reservationMode)) {
      return reservationDoctors(context);
    }
    final doctor =
        doctors.where((d) => d['id'] == doctorId).firstOrNull ??
        <String, dynamic>{};
    final dates = practiceDates;
    final clinicName = label(selectedService ?? {});
    final visibleDoctors = matchingDoctors
        .where(
          (d) =>
              clinicName.toLowerCase().contains(search) ||
              ('${label(d)} ${d['spesialisasi'] ?? ''}').toLowerCase().contains(
                search,
              ),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PatientHeading(
          title: bookingStage
              ? 'Detail Dokter'
              : serviceId == null
              ? (reservationMode == 'clinics'
                    ? 'Buat Reservasi'
                    : 'Poliklinik & Dokter')
              : clinicName,
          onBack: serviceId == null
              ? showReservations
              : busy || loading
              ? null
              : () {
                  if (widget.location?.path.startsWith(
                        '/patient/reservations/doctors/',
                      ) ==
                      true) {
                    setState(() {
                      booking.invalidate();
                      bookingStage = doctorDetail = false;
                      doctorId = sessionId = slotId = null;
                    });
                    _go(
                      Uri(
                        path: '/patient/reservations/new',
                        queryParameters: serviceId == null
                            ? null
                            : {'clinic': serviceId!},
                      ).toString(),
                    );
                    return;
                  }
                  setState(() {
                    booking.invalidate();
                    if (bookingStage) {
                      bookingStage = false;
                      doctorDetail = false;
                      doctorId = sessionId = slotId = null;
                    } else {
                      serviceId = null;
                      search = '';
                    }
                  });
                },
        ),
        if (!bookingStage) ...[
          if (serviceId == null) ..._catalog(context),
          if (selectedService != null) ...[
            SegmentedButton<bool>(
              segments: [
                if (selectedService!['modeReservasi'] != 'ANTREAN_HARIAN')
                  const ButtonSegment(value: true, label: Text('Janji temu')),
                if (selectedService!['modeReservasi'] != 'JANJI_TEMU_DOKTER')
                  const ButtonSegment(value: false, label: Text('Walk-in')),
              ],
              selected: {appointment},
              onSelectionChanged: busy || loading
                  ? null
                  : (v) {
                      setState(() {
                        booking.invalidate();
                        appointment = v.first;
                        doctorId = sessionId = slotId = null;
                        schedules = [];
                        slots = [];
                      });
                      if (appointment) loadClinicSchedules();
                    },
            ),
            const SizedBox(height: 16),
            ...[
              TextField(
                decoration: const InputDecoration(
                  hintText: 'Cari nama dokter atau spesialisasi',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (v) =>
                    setState(() => search = v.toLowerCase().trim()),
              ),
              const SizedBox(height: 16),
              if (visibleDoctors.isEmpty && !loading)
                EmptyState(
                  text: matchingDoctors.isEmpty
                      ? 'Belum ada dokter pada poliklinik ini.'
                      : 'Tidak ada dokter yang sesuai pencarian.',
                ),
              for (final d in visibleDoctors)
                PatientDoctorCard(
                  doctor: d,
                  config: widget.api.config,
                  schedule: doctorAvailability(d),
                  onDetails: busy || loading ? null : () => chooseDoctor(d),
                ),
            ],
          ],
        ],
        if (bookingStage && doctorDetail) ...[
          DoctorProfileCard(
            doctor: doctor,
            config: widget.api.config,
            clinics: clinicName,
            detail: true,
          ),
          _ExpandablePatientDoctorBiography(
            key: ValueKey(('doctor-biography', doctorId)),
            text: doctor['tentangDokter'],
          ),
          const SizedBox(height: 16),
          _PatientDoctorSchedulePicker(
            key: ValueKey(('doctor-schedule', doctorId)),
            dates: dates,
            sessions: clinicSchedules
                .where(
                  (s) =>
                      s['aktif'] != false &&
                      dateOnly(s['tanggal'])
                              .compareTo(widget.api.config.today) >=
                          0 &&
                      (object(s['dokterLayanan'])['dokterId'] == doctorId ||
                          object(object(s['dokterLayanan'])['dokter'])['id'] ==
                              doctorId),
                )
                .toList(),
            value: date.text,
            config: widget.api.config,
            enabled: !busy && !loading,
            loading: loading,
            showSessionDetails:
                selectedService?['modeReservasi'] == 'ANTREAN_HARIAN',
            footer: selectedService?['modeReservasi'] == 'ANTREAN_HARIAN'
                ? null
                : _doctorScheduleBooking(context),
            onChanged: (day) {
              if (busy || loading || day == date.text) return;
              // Clear old selections immediately. Never render a slot from
              // another day as a selection for the newly displayed date.
              setState(() {
                date.text = day;
                sessionId = slotId = null;
                schedules = [];
                slots = [];
              });
              unawaited(loadSchedules());
            },
          ),
          const SizedBox(height: 12),
          if (selectedService?['modeReservasi'] == 'ANTREAN_HARIAN') ...[
            const MobileNotice(
              'Poliklinik ini menggunakan antrean harian, bukan booking slot dokter.',
            ),
            OutlinedButton.icon(
              onPressed: busy || loading
                  ? null
                  : () => setState(() {
                      bookingStage = doctorDetail = appointment = false;
                      doctorId = sessionId = slotId = null;
                    }),
              icon: const Icon(Icons.confirmation_number_outlined),
              label: const Text('Daftar antrean poliklinik'),
            ),
          ],
          OutlinedButton.icon(
            onPressed: busy || loading ? null : load,
            icon: const Icon(Icons.refresh),
            label: const Text('Muat ulang jadwal'),
          ),
        ],
        if (selectedService != null && !appointment && !bookingStage) ...[
          const SizedBox(height: 16),
          TextField(
            controller: date,
            enabled: !busy && !loading,
            decoration: InputDecoration(
              labelText: 'Tanggal pelayanan (YYYY-MM-DD)',
              suffixIcon: IconButton(
                tooltip: 'Pilih tanggal pelayanan',
                onPressed: busy || loading
                    ? null
                    : () async {
                        final chosen = await showDatePicker(
                          context: context,
                          initialDate: initialServiceDate(
                            date.text,
                            widget.api.config.today,
                          ),
                          firstDate: DateTime.parse(widget.api.config.today),
                          lastDate: DateTime.parse(widget.api.config.today)
                              .add(const Duration(days: 365)),
                        );
                        if (chosen != null && mounted) {
                          setState(() => date.text = calendarDate(chosen));
                        }
                      },
                icon: const Icon(Icons.calendar_month),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const MobileNotice(
            'Walk-in mengikuti kuota harian poli. Bawa tiket QR pada tanggal pelayanan.',
          ),
        ],
        if (selectedService != null && !appointment && !bookingStage) ...[
          const SizedBox(height: 16),
          if (slotId != null)
            Text(
              'Tanggal terpilih: ${date.text}',
              style: const TextStyle(color: PatientDesign.darkTeal),
            ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: busy || loading || (appointment && slotId == null)
                ? null
                : book,
            icon: const Icon(Icons.arrow_forward),
            label: Text(
              busy
                  ? 'Memproses…'
                  : appointment
                  ? 'Lanjutkan'
                  : 'Reservasi walk-in',
            ),
          ),
        ],
      ],
    );
  }

  Widget _history(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      PatientHeading(
        title: 'Riwayat kunjungan',
        onBack: () => setState(() => tab = 0),
      ),
      if (!tickets.any(
        (t) =>
            ['SELESAI', 'DIBATALKAN'].contains(t['status']) ||
            dateOnly(t['tanggalPelayanan'] ?? t['tanggalAntrean'])
                    .compareTo(widget.api.config.today) <
                0,
      ))
        const EmptyState(text: 'Belum ada riwayat kunjungan.'),
      for (final t in tickets.where(
        (t) =>
            ['SELESAI', 'DIBATALKAN'].contains(t['status']) ||
            dateOnly(t['tanggalPelayanan'] ?? t['tanggalAntrean'])
                    .compareTo(widget.api.config.today) <
                0,
      ))
        AppCard(
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              '${t['nomorAntrean']} · ${label(object(t['layanan']))}',
            ),
            subtitle: Text(
              patientDate('${t['tanggalPelayanan'] ?? t['tanggalAntrean']}'),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => openTicket(t),
          ),
        ),
    ],
  );

  Widget _reservationHistory() => ReservationList(
    items: patientReservations(
      tickets,
      appointments,
      doctors,
      widget.api.config.today,
    ),
    config: widget.api.config,
    loading: loading,
    busy: busy,
    error: error,
    message: message,
    onRefresh: load,
    onCreate: createReservation,
    onTicket: (r) => openTicket(r.ticket, issueQrOnOpen: !r.terminal),
    onCancel: (r) => cancel(r.appointment!),
  );
}

/// Compact doctor biography. The existing DoctorBiography retains all of its
/// copy and fallback logic; only visibility is controlled locally.
class _ExpandablePatientDoctorBiography extends StatefulWidget {
  const _ExpandablePatientDoctorBiography({super.key, required this.text});

  final dynamic text;

  @override
  State<_ExpandablePatientDoctorBiography> createState() =>
      _ExpandablePatientDoctorBiographyState();
}

class _ExpandablePatientDoctorBiographyState
    extends State<_ExpandablePatientDoctorBiography> {
  bool expanded = true;

  @override
  Widget build(BuildContext context) => AnimatedSize(
    duration: QueueBMotion.duration(context, QueueBMotion.component),
    alignment: Alignment.topCenter,
    curve: Curves.easeOutCubic,
    child: expanded
        ? Stack(
            children: [
              DoctorBiography(text: widget.text),
              Positioned(
                top: 0,
                right: 4,
                child: IconButton(
                  tooltip: 'Sembunyikan tentang dokter',
                  onPressed: () => setState(() => expanded = false),
                  icon: const Icon(Icons.keyboard_arrow_up_rounded),
                ),
              ),
            ],
          )
        : AppCard(
            child: InkWell(
              onTap: () => setState(() => expanded = true),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Tentang Dokter',
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const Icon(Icons.keyboard_arrow_down_rounded),
                ],
              ),
            ),
          ),
  );
}

/// Read-only preview of upcoming practice sessions. The selected date is
/// owned by PatientPage; this widget owns only the visible month.
class _PatientDoctorSchedulePicker extends StatefulWidget {
  const _PatientDoctorSchedulePicker({
    super.key,
    required this.dates,
    required this.sessions,
    required this.value,
    required this.config,
    required this.enabled,
    required this.loading,
    this.showSessionDetails = true,
    this.footer,
    required this.onChanged,
  });

  final List<String> dates;
  final List<Json> sessions;
  final String value;
  final AppConfig config;
  final bool enabled, loading;
  final bool showSessionDetails;
  final Widget? footer;
  final ValueChanged<String> onChanged;

  @override
  State<_PatientDoctorSchedulePicker> createState() =>
      _PatientDoctorSchedulePickerState();
}

class _PatientDoctorSchedulePickerState
    extends State<_PatientDoctorSchedulePicker> {
  static const _months = <String>[
    'Januari',
    'Februari',
    'Maret',
    'April',
    'Mei',
    'Juni',
    'Juli',
    'Agustus',
    'September',
    'Oktober',
    'November',
    'Desember',
  ];
  static const _weekdays = <String>[
    'Sen',
    'Sel',
    'Rab',
    'Kam',
    'Jum',
    'Sab',
    'Min',
  ];

  String? month;

  String _monthOf(String day) => day.substring(0, 7);

  String _monthLabel(String value) {
    final parsed = DateTime.parse('$value-01');
    return '${_months[parsed.month - 1]} ${parsed.year}';
  }

  @override
  void initState() {
    super.initState();
    month = widget.value.length >= 7 ? _monthOf(widget.value) : null;
  }

  @override
  void didUpdateWidget(covariant _PatientDoctorSchedulePicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value && widget.value.length >= 7) {
      month = _monthOf(widget.value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final days = widget.dates.toSet().toList()..sort();
    final months = days.map(_monthOf).toSet().toList()..sort();
    if (months.isEmpty) {
      return AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Jadwal praktik',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            if (widget.loading)
              const LinearProgressIndicator()
            else
              const Text('Dokter belum memiliki jadwal praktik mendatang.'),
          ],
        ),
      );
    }

    final chosenMonth = months.contains(month)
        ? month!
        : months.contains(
            widget.value.length >= 7 ? _monthOf(widget.value) : '',
          )
        ? _monthOf(widget.value)
        : months.first;
    final monthDays = days.where((d) => _monthOf(d) == chosenMonth).toList();
    final selectedDay = monthDays.contains(widget.value)
        ? widget.value
        : monthDays.first;
    final visibleSessions =
        widget.sessions
            .where((s) => dateOnly(s['tanggal']) == selectedDay)
            .toList()
          ..sort(
            (a, b) =>
                '${a['mulaiPada'] ?? ''}'.compareTo('${b['mulaiPada'] ?? ''}'),
          );
    final animation = QueueBMotion.duration(context, QueueBMotion.component);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 8,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Jadwal praktik',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              Semantics(
                label: 'Pilih bulan jadwal praktik',
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: PatientDesign.border),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: chosenMonth,
                      isDense: true,
                      icon: const Icon(Icons.keyboard_arrow_down_rounded),
                      items: [
                        for (final entry in months)
                          DropdownMenuItem(
                            value: entry,
                            child: Text(
                              _monthLabel(entry),
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                      ],
                      onChanged: !widget.enabled
                          ? null
                          : (next) {
                              if (next == null || next == chosenMonth) return;
                              final first = days.firstWhere(
                                (day) => _monthOf(day) == next,
                              );
                              setState(() => month = next);
                              widget.onChanged(first);
                            },
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 92,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: monthDays.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final day = monthDays[index];
                final parsed = DateTime.parse(day);
                final selected = day == selectedDay;
                return Semantics(
                  button: true,
                  selected: selected,
                  label:
                      '${_weekdays[parsed.weekday - 1]}, ${patientDate(day)}',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: !widget.enabled || selected
                        ? null
                        : () => widget.onChanged(day),
                    child: AnimatedContainer(
                      duration: animation,
                      curve: Curves.easeOutCubic,
                      width: 68,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: selected
                            ? PatientDesign.primary
                            : PatientDesign.background,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: selected
                              ? PatientDesign.primary
                              : PatientDesign.border,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _weekdays[parsed.weekday - 1],
                            style: TextStyle(
                              fontSize: 12,
                              color: selected
                                  ? Colors.white
                                  : PatientDesign.muted,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${parsed.day}',
                            style: TextStyle(
                              fontSize: 23,
                              fontWeight: FontWeight.w800,
                              color: selected
                                  ? Colors.white
                                  : PatientDesign.navy,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 14),
          AnimatedSwitcher(
            duration: animation,
            switchInCurve: Curves.easeOutCubic,
            child: Column(
              key: ValueKey(('practice-date', selectedDay)),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  patientDate(selectedDay),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: PatientDesign.navy,
                  ),
                ),
                if (widget.showSessionDetails) ...[
                  const SizedBox(height: 10),
                  if (visibleSessions.isEmpty)
                    const Text('Belum ada sesi pada tanggal ini.')
                  else
                    for (final session in visibleSessions) ...[
                      Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: PatientDesign.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            PatientInfoRow(
                              icon: Icons.schedule_outlined,
                              title: 'Waktu praktik',
                              value: patientTime(session, widget.config),
                            ),
                            const Divider(height: 20),
                            PatientInfoRow(
                              icon: Icons.room_outlined,
                              title: 'Ruang / Loket',
                              value: _roomLabel(object(session['loket'])),
                            ),
                          ],
                        ),
                      ),
                    ],
                ],
              ],
            ),
          ),
          if (widget.footer != null) ...[
            const SizedBox(height: 12),
            widget.footer!,
          ],
        ],
      ),
    );
  }

  String _roomLabel(Json room) {
    if (room.isEmpty) return 'Belum ditentukan';
    final code = '${room['kode'] ?? ''}'.trim();
    final name = label(room).trim();
    if (code.isEmpty) return name.isEmpty ? 'Belum ditentukan' : name;
    return name.isEmpty || name == code ? code : '$code · $name';
  }
}

class PatientBranchView extends StatelessWidget {
  const PatientBranchView({
    super.key,
    required this.index,
    this.bookingView = false,
  });
  final int index;
  final bool bookingView;
  @override
  Widget build(BuildContext context) {
    final owner = context
        .dependOnInheritedWidgetOfExactType<_PatientViewScope>()!
        .owner;
    return PopScope(
      canPop: kIsWeb || !bookingView || !owner.busy,
      child: owner.branch(context, index, bookingView: bookingView),
    );
  }
}

class _PatientViewScope extends InheritedWidget {
  const _PatientViewScope({required this.owner, required super.child});
  final _PatientPageState owner;
  @override
  bool updateShouldNotify(_PatientViewScope oldWidget) => true;
}

/// Read-only destination. QR issuance remains an explicit, transient dialog action.
class PatientTicketRoute extends StatefulWidget {
  const PatientTicketRoute({super.key, required this.ticketId});
  final String ticketId;
  @override
  State<PatientTicketRoute> createState() => _PatientTicketRouteState();
}

class _PatientTicketRouteState extends State<PatientTicketRoute> {
  static const unavailable = 'Tiket tidak tersedia atau tidak dapat diakses.';
  PatientTicketCubit? controller;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final owner = context
        .dependOnInheritedWidgetOfExactType<_PatientViewScope>()!
        .owner;
    controller ??= PatientTicketCubit(owner.repository, widget.ticketId)
      ..refresh();
  }

  @override
  void dispose() {
    controller?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<PatientTicketCubit, PatientTicketState>(
        bloc: controller!,
        builder: (context, state) {
          final ticket = controller!.ticket;
          final owner = context
              .dependOnInheritedWidgetOfExactType<_PatientViewScope>()!
              .owner;
          return Scaffold(
            appBar: AppBar(
              title: const Text('Detail Tiket'),
              leading: BackButton(
                onPressed: () => context.go('/patient/tickets'),
              ),
            ),
            body: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (state.load == PatientLoad.loading ||
                    state.load == PatientLoad.initial)
                  const LinearProgressIndicator()
                else if (state.error != null || ticket == null)
                  Semantics(
                    label: unavailable,
                    excludeSemantics: true,
                    child: const MobileNotice(unavailable, error: true),
                  )
                else ...[
                  Text(
                    'Tiket ${ticket['nomorAntrean']}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Text(label(object(ticket['layanan']))),
                  ReservationStatus('${ticket['status']}'),
                  FilledButton(
                    onPressed: () => showDialog<void>(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) => _TicketDialog(
                        api: owner.widget.api,
                        repository: owner.repository,
                        ticket: ticket,
                        controller: controller,
                      ),
                    ),
                    child: const Text('Lihat tiket & QR'),
                  ),
                ],
              ],
            ),
          );
        },
      );
}

class _TicketDialog extends StatefulWidget {
  const _TicketDialog({
    required this.api,
    required this.ticket,
    required this.repository,
    this.appointment,
    this.issueQrOnOpen = false,
    this.controller,
  });
  final QueueApi api;
  final Json ticket;
  final PatientRepository repository;
  final Json? appointment;
  final bool issueQrOnOpen;
  final PatientTicketCubit? controller;
  @override
  State<_TicketDialog> createState() => _TicketDialogState();
}

class _TicketDialogState extends State<_TicketDialog> {
  late final PatientTicketCubit controller;
  Json get data => controller.ticket ?? patientObject(widget.ticket);
  PatientQr? qr;
  String? get error => controller.state.error;
  bool get busy => controller.state.mutation == PatientMutation.submitting;
  bool get loading => [
    PatientLoad.initial,
    PatientLoad.loading,
  ].contains(controller.state.load);
  Timer? countdown;
  Timer? qrExpiry;
  int remaining = 0;
  bool get canIssue => controller.canIssue;
  @override
  void initState() {
    super.initState();
    controller =
        widget.controller ??
        PatientTicketCubit(widget.repository, '${widget.ticket['id']}');
    countdown = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        remaining =
            qr?.expiresAt
                .difference(widget.api.config.now)
                .inSeconds
                .clamp(0, 600) ??
            0;
        if (remaining == 0 || !canIssue) {
          qr?.clear();
          qr = null;
        }
      });
    });
    if (widget.controller == null) initialize();
  }

  Future<void> initialize() async {
    await refresh();
    if (mounted && widget.issueQrOnOpen && error == null && canIssue) {
      await issue();
    }
  }

  Future<void> refresh() => controller.refresh();
  Future<void> issue() async {
    if (busy || loading || !canIssue) return;
    setState(() {
      qrExpiry?.cancel();
      qr?.clear();
      qr = null;
    });
    final result = await controller.issue();
    if (!mounted || !canIssue) {
      result?.clear();
      return;
    }
    setState(() {
      qr = result;
      remaining =
          result?.expiresAt
              .difference(widget.api.config.now)
              .inSeconds
              .clamp(0, 600) ??
          0;
      if (remaining == 0) {
        qr?.clear();
        qr = null;
      } else if (result != null) {
        final lifetime = result.expiresAt.difference(widget.api.config.now);
        qrExpiry = Timer(
          lifetime > const Duration(minutes: 10)
              ? const Duration(minutes: 10)
              : lifetime,
          () {
            if (mounted) {
              setState(() {
                qr?.clear();
                qr = null;
                remaining = 0;
              });
            }
          },
        );
      }
    });
  }

  void changed(PatientTicketState state) {
    if (!canIssue) {
      qrExpiry?.cancel();
      setState(() {
        qr?.clear();
        qr = null;
        remaining = 0;
      });
    }
    if (state.load == PatientLoad.sessionEnded) {
      final route = ModalRoute.of(context);
      if (route?.isCurrent == true) {
        Navigator.of(context).pop();
      } else if (route != null && route.isActive) {
        route.navigator?.removeRoute(route);
      }
    }
  }

  @override
  void dispose() {
    qr?.clear();
    qrExpiry?.cancel();
    countdown?.cancel();
    if (widget.controller == null) controller.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BlocProvider.value(
    value: controller,
    child: BlocConsumer<PatientTicketCubit, PatientTicketState>(
      bloc: controller,
      listener: (context, state) => changed(state),
      builder: (context, _) => content(context),
    ),
  );
  Widget content(BuildContext context) {
    final slot = object(widget.appointment?['slotPraktik']);
    final session = object(slot['jadwalPraktik']);
    final doctor = object(object(session['dokterLayanan'])['dokter']);
    final room = object(session['loket']);
    return PopScope(
      canPop: !busy,
      child: AlertDialog(
        insetPadding: const EdgeInsets.all(16),
        contentPadding: const EdgeInsets.all(16),
        title: Text(
          'Tiket ${data['nomorAntrean']}',
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            letterSpacing: -.4,
          ),
        ),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${label(object(data['layanan']))} · ${patientDate('${data['tanggalPelayanan'] ?? data['tanggalAntrean']}')}',
                ),
                ReservationStatus('${data['status'] ?? '—'}'),
                if (doctor['nama'] != null)
                  Text(
                    label(doctor),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                if (room.isNotEmpty)
                  Text(
                    label(room),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12,
                      color: PatientDesign.muted,
                    ),
                  ),
                if (slot['mulaiPada'] != null)
                  Text(
                    '${patientTime(slot, widget.api.config)} · ${widget.api.config.serviceTimeZone}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12,
                      color: PatientDesign.muted,
                    ),
                  ),
                const SizedBox(height: 8),
                if (error != null) MobileNotice(error!, error: true),
                if (loading || busy)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: LinearProgressIndicator(
                      semanticsLabel: widget.issueQrOnOpen || busy
                          ? 'Memuat QR check-in'
                          : 'Memuat tiket',
                    ),
                  ),
                if (qr != null && remaining > 0) ...[
                  LayoutBuilder(
                    builder: (context, box) => QrImageView(
                      data: qr!.payload ?? '',
                      size: box.maxWidth.clamp(0, 240),
                      backgroundColor: Colors.white,
                      semanticsLabel:
                          'QR check-in tiket ${data['nomorAntrean']}',
                    ),
                  ),
                  Text('Berlaku $remaining detik · sekali pakai'),
                  ExpansionTile(
                    title: const Text(
                      'Detail teknis tiket',
                      style: TextStyle(fontSize: 12),
                    ),
                    children: [
                      SelectableText('ID tiket: ${data['id']}'),
                      SelectableText(
                        qr!.payload ?? '',
                        style: const TextStyle(
                          fontSize: 11,
                          color: PatientDesign.muted,
                        ),
                      ),
                    ],
                  ),
                ],
                if (canIssue) ...[
                  const MobileNotice(
                    'QR diterbitkan pada hari pelayanan, berlaku 10 menit. QR baru menggantikan QR sebelumnya.',
                  ),
                  FilledButton(
                    onPressed: busy || loading ? null : issue,
                    child: Text(qr == null ? 'Terbitkan QR' : 'Perbarui QR'),
                  ),
                ] else
                  MobileNotice(
                    'QR tersedia untuk tiket DIPESAN pada tanggal pelayanan (${dateOnly(data['tanggalPelayanan'] ?? data['tanggalAntrean'])}). Status disinkronkan secara berkala.',
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: busy || loading ? null : refresh,
            child: const Text('Muat ulang status'),
          ),
          TextButton(
            onPressed: busy ? null : () => Navigator.pop(context),
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
  }
}
