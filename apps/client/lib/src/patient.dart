import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'features/patient/data/patient_repository.dart';
import 'features/patient/application/patient_overview_cubit.dart';
import 'features/patient/application/patient_booking_cubit.dart';
import 'features/patient/data/patient_booking_repository.dart';
import 'features/patient/models/patient_models.dart';
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
import 'patient_home.dart';
import 'patient_home_v6.dart';
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
  });
  final QueueApi api;

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
  int tab = 0;
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
  bool reservationCreating = false;
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
    await loadSchedules();
  }

  void chooseDate(String value) {
    if (busy || loading || value == date.text) return;
    date.text = value;
    loadSchedules();
  }

  @override
  void initState() {
    super.initState();
    repository = widget.repository ?? PatientRepository(widget.api);
    overviewCubit = PatientOverviewCubit(repository);
    booking = PatientBookingCubit(PatientBookingRepository(repository));
    reservations = PatientReservationsCubit(repository);
    repository.addListener(_scopeChanged);
    load();
  }

  void _scopeChanged() {
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
    booking.change({'date': date.text.trim()});
    setState(() => bookingStage = true);
    await booking.loadSchedules();
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
                builder: (_) => AppointmentReview(
                  doctor: request.doctor,
                  clinic: request.clinic,
                  session: request.session,
                  slot: request.slot,
                  config: widget.api.config,
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
            'Pendaftaran berhasil.${issued['nomorAntrean'] == null ? '' : ' Tiket ${issued['nomorAntrean']}.'} Tiket tersedia di Tiket Saya.';
        tab = 1;
      });
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
    setState(() => doctorDetail = false);
    if (session != null && schedules.any((s) => s['id'] == session['id'])) {
      await loadSlots('${session['id']}');
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
    final bookedDoctor = object(
      object(
        object(object(visit?['slotPraktik'])['jadwalPraktik'])['dokterLayanan'],
      )['dokter'],
    );
    final doctor = {
      ...?doctors.where((d) => d['id'] == bookedDoctor['id']).firstOrNull,
      ...bookedDoctor,
    };
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
                PatientHomeHeaderV6(
                  name: '${widget.api.user?['nama'] ?? 'Pasien'}',
                ),
                if (loading)
                  const LinearProgressIndicator(
                    semanticsLabel: 'Memuat data pelayanan',
                  ),
                const SizedBox(height: 14),
                PatientHomeWelcome(
                  name: '${widget.api.user?['nama'] ?? 'Pasien'}',
                  controller: homeSearch,
                  onSearch: (v) =>
                      setState(() => homeQuery = v.toLowerCase().trim()),
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
                if (active != null) ...[
                  const SizedBox(height: 10),
                  PatientHomeSectionTitle(
                    'Kunjungan Terdekat',
                    action: 'Lihat Semua',
                    onPressed: busy ? null : () => setState(() => tab = 1),
                  ),
                  const SizedBox(height: 4),
                  PatientHomeVisit(
                    ticket: active,
                    doctor: doctor,
                    appointment: visit,
                    config: widget.api.config,
                    onTicket: busy ? null : () => openTicket(active),
                    onQr: busy
                        ? null
                        : () => openTicket(active, issueQrOnOpen: true),
                  ),
                ],
                const SizedBox(height: 16),
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
                  itemBuilder: (context, index) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: PatientHomeService(
                      clinic: walkIns[index],
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
                const SizedBox(height: 8),
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
                              tab == 2) {
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
          child: PatientScrollShell(
            pageKey:
                '$tab:$reservationCreating:$serviceId:$bookingStage:$doctorDetail',
            // Home owns its compact identity; no duplicate app bar or notification.
            header: null,
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
            floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
            bottomNavigationBar: PatientBottomNavigation(
              selectedIndex: tab == 4 ? 0 : [0, 2, 1, 3, 5].indexOf(tab),
              onSelected: busy
                  ? null
                  : (i) => setState(() {
                      tab = [0, 2, 1, 3, 5][i];
                      if (tab == 5) profileVisited = true;
                      reservationFlowVersion++;
                      booking.invalidateNearest();
                      if (tab == 2) reservationCreating = false;
                    }),
            ),
            body: ColoredBox(
              color: tab == 0
                  ? PatientHomeStyle.background
                  : PatientDesign.background,
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: IndexedStack(
                    index: tab == 5
                        ? 2
                        : tab == 2 && !reservationCreating
                        ? 0
                        : 1,
                    children: [
                      ReservationList(
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
                        onTicket: (r) =>
                            openTicket(r.ticket, issueQrOnOpen: !r.terminal),
                        onCancel: (r) => cancel(r.appointment!),
                      ),
                      tab == 0
                          ? _home(context)
                          : tab == 1
                          ? _tickets(context)
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
                          : ListView(
                              key: PageStorageKey(
                                '$tab:$serviceId:$bookingStage:$doctorDetail',
                              ),
                              padding: const EdgeInsets.all(16),
                              children: [
                                if (error != null) ...[
                                  MobileNotice(error!, error: true),
                                  TextButton.icon(
                                    onPressed: busy || loading ? null : load,
                                    icon: const Icon(Icons.refresh),
                                    label: const Text('Coba lagi'),
                                  ),
                                ],
                                if (message != null) MobileNotice(message!),
                                if (loading)
                                  const LinearProgressIndicator(
                                    semanticsLabel: 'Memuat data pelayanan',
                                  ),
                                if (tab == 2) _registration(context),
                                if (tab == 4) _history(context),
                              ],
                            ),
                      if (profileVisited)
                        UserProfilePage(
                          api: widget.api,
                          onReturnToPatient: () => setState(() => tab = 0),
                        )
                      else
                        const SizedBox(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );

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
              ? (doctorDetail ? 'Detail Dokter' : 'Pilih Jadwal Praktik')
              : serviceId == null
              ? (reservationMode == 'clinics'
                    ? 'Buat Reservasi'
                    : 'Poliklinik & Dokter')
              : clinicName,
          onBack: serviceId == null
              ? showReservations
              : busy || loading
              ? null
              : () => setState(() {
                  booking.invalidate();
                  if (bookingStage && !doctorDetail) {
                    doctorDetail = true;
                    slotId = null;
                  } else if (bookingStage) {
                    bookingStage = false;
                    doctorDetail = false;
                    doctorId = sessionId = slotId = null;
                  } else {
                    serviceId = null;
                    search = '';
                  }
                }),
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
          DoctorBiography(text: doctor['tentangDokter']),
          const SizedBox(height: 16),
          Text(
            'Jadwal praktik mendatang',
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          for (final session in clinicSchedules.where(
            (s) =>
                s['aktif'] != false &&
                dateOnly(s['tanggal']).compareTo(widget.api.config.today) >=
                    0 &&
                (object(s['dokterLayanan'])['dokterId'] == doctorId ||
                    object(object(s['dokterLayanan'])['dokter'])['id'] ==
                        doctorId),
          ))
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    patientDate('${session['tanggal']}'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(patientTime(session, widget.api.config)),
                  PatientInfoRow(
                    icon: Icons.room_outlined,
                    title: 'Ruang / Loket',
                    value:
                        '${object(session['loket'])['kode'] ?? ''} · ${label(object(session['loket']))}',
                  ),
                ],
              ),
            ),
          if (dates.isEmpty && !loading)
            const EmptyState(
              text: 'Dokter belum memiliki jadwal praktik mendatang.',
            ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed:
                busy ||
                    loading ||
                    dates.isEmpty ||
                    selectedService?['modeReservasi'] == 'ANTREAN_HARIAN'
                ? null
                : () => setState(() => doctorDetail = false),
            child: const Text('Buat Janji Temu'),
          ),
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
        if (bookingStage && !doctorDetail) ...[
          PatientInfoRow(
            icon: Icons.person_outline,
            title: clinicName,
            value: label(doctor),
          ),
          const SizedBox(height: 8),
          Text(clinicName, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          const Text(
            'Tanggal praktik',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          if (dates.isNotEmpty) ...[
            PracticeDateStrip(
              dates: dates,
              value: date.text,
              enabled: !busy && !loading,
              onChanged: chooseDate,
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: busy || loading
                  ? null
                  : () async {
                      final chosen = await showDatePicker(
                        context: context,
                        initialDate: DateTime.parse(
                          dates.contains(date.text) ? date.text : dates.first,
                        ),
                        firstDate: DateTime.parse(dates.first),
                        lastDate: DateTime.parse(dates.last),
                        selectableDayPredicate: (day) =>
                            dates.contains(calendarDate(day)),
                      );
                      if (chosen != null && mounted) {
                        chooseDate(calendarDate(chosen));
                      }
                    },
              icon: const Icon(Icons.calendar_month_outlined),
              label: Text('Kalender · ${date.text}'),
            ),
          ],
          if (!loading && (dates.isEmpty || schedules.isEmpty))
            const EmptyState(
              text: 'Dokter belum memiliki jadwal pada tanggal ini. Pilih tanggal lain atau muat ulang.',
            ),
          const SizedBox(height: 16),
          const Text(
            'Sesi & ruang praktik',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          for (final s in schedules)
            AppCard(
              color: sessionId == s['id'] ? PatientDesign.mint : null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${widget.api.config.localInput(s['mulaiPada']).split('T').last} – ${widget.api.config.localInput(s['selesaiPada']).split('T').last}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text('Ruang: ${label(object(s['loket']))}'),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: busy || loading
                        ? null
                        : () => loadSlots('${s['id']}'),
                    child: Text(
                      sessionId == s['id'] ? 'Muat ulang slot' : 'Lihat slot',
                    ),
                  ),
                ],
              ),
            ),
          if (sessionId != null && !loading && slots.isEmpty)
            const EmptyState(text: 'Belum ada slot konsultasi pada sesi ini.'),
          if (slots.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text(
              'Slot konsultasi',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            const Text(
              'Pilih jam tersedia. Kapasitas mengikuti data terbaru dari server.',
              style: TextStyle(fontSize: 12, color: PatientDesign.muted),
            ),
            const SizedBox(height: 12),
            if (!slots.any((s) => s['tersedia'] == true))
              EmptyState(
                text: slots.every((s) => consultationSlotStatus(s) == 'Penuh')
                    ? 'Seluruh slot penuh. Pilih sesi atau tanggal lain.'
                    : 'Tidak ada slot tersedia untuk dipesan. Pilih sesi atau tanggal lain.',
              ),
            ConsultationSlotGrid(
              slots: slots,
              config: widget.api.config,
              value: slotId,
              enabled: !busy && !loading,
              onChanged: (v) => setState(() => slotId = v),
            ),
            const SizedBox(height: 12),
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
        if (selectedService != null &&
            ((!appointment && !bookingStage) ||
                (appointment && bookingStage && !doctorDetail))) ...[
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

  Widget _tickets(BuildContext context) {
    final items = patientReservations(
      tickets,
      appointments,
      doctors,
      widget.api.config.today,
    );
    return ListView.builder(
      key: const PageStorageKey('patient-tickets'),
      padding: const EdgeInsets.all(16),
      itemCount: 1 + (items.isEmpty ? 1 : items.length),
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Tiket Saya',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Muat ulang tiket',
                      onPressed: busy || loading ? null : load,
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
                if (error != null) MobileNotice(error!, error: true),
                if (message != null) MobileNotice(message!),
                if (loading) const LinearProgressIndicator(),
              ],
            ),
          );
        }
        if (items.isEmpty) {
          return const EmptyState(
            text: 'Belum ada tiket. Daftar janji temu atau walk-in terlebih dahulu.',
            icon: Icons.confirmation_number_outlined,
          );
        }
        final item = items[index - 1];
        return PatientTicketCard(
          item: item,
          config: widget.api.config,
          onOpen: busy ? null : () => openTicket(item.ticket),
        );
      },
    );
  }
}

class _TicketDialog extends StatefulWidget {
  const _TicketDialog({
    required this.api,
    required this.ticket,
    required this.repository,
    this.appointment,
    this.issueQrOnOpen = false,
  });
  final QueueApi api;
  final Json ticket;
  final PatientRepository repository;
  final Json? appointment;
  final bool issueQrOnOpen;
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
    controller = PatientTicketCubit(
      widget.repository,
      '${widget.ticket['id']}',
    );
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
    initialize();
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
    controller.close();
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
                      semanticsLabel: widget.issueQrOnOpen
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
