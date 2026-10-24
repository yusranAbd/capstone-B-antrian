import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'api.dart';
import 'config.dart';
import 'widgets.dart';
import 'mobile_ui.dart';
import 'patient_sync.dart';
import 'doctor_schedule_ui.dart';
import 'doctor_professional.dart';
import 'patient_ui.dart';
import 'patient_home.dart';
import 'user_profile.dart';

String appointmentDetails(Json appointment, AppConfig config) {
  final slot = object(appointment['slotPraktik']);
  final session = object(slot['jadwalPraktik']);
  final doctor = object(object(session['dokterLayanan'])['dokter']);
  return 'Janji temu: ${label(doctor)}\nRuang: ${label(object(session['loket']))}\nSlot: ${config.instantLabel(slot['mulaiPada'])} – ${config.instantLabel(slot['selesaiPada'])}';
}

class PatientPage extends StatefulWidget {
  const PatientPage({
    super.key,
    required this.api,
    this.onDisplay,
    this.headerBuilder,
  });
  final QueueApi api;
  final VoidCallback? onDisplay;
  final PreferredSizeWidget Function(bool home, VoidCallback activity)?
  headerBuilder;
  @override
  State<PatientPage> createState() => _PatientPageState();
}

class _PatientPageState extends State<PatientPage> {
  late final PatientUpdates updates;
  late final RefreshGate overview;
  int tab = 0, catalogRevision = 0;
  bool busy = false, loading = true;
  String? error, message, serviceId, doctorId, sessionId, slotId;
  bool appointment = true, bookingStage = false, doctorDetail = false;
  bool reviewing = false;
  String search = '', channel = 'Semua';
  String? homeClinicId;
  List<Json> clinicSchedules = [], homeSchedules = [];
  String? homeScheduleError;
  final Map<String, String> clinicAvailability = {};
  List<Json> services = [],
      doctors = [],
      schedules = [],
      slots = [],
      tickets = [],
      appointments = [];
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

  // One nearest dated session per doctor, with bounded parallel reads. This is
  // a preview only: the chosen session is always fetched again before booking.
  Future<void> readAvailability(List<Json> sessions, int revision) async {
    final nearest = <String, Json>{};
    final ordered = [...sessions]
      ..sort((a, b) => '${a['mulaiPada']}'.compareTo('${b['mulaiPada']}'));
    for (final s in ordered) {
      final doctor =
          object(s['dokterLayanan'])['dokterId'] ??
          object(object(s['dokterLayanan'])['dokter'])['id'];
      if (doctor is String &&
          s['aktif'] != false &&
          dateOnly(s['tanggal']).compareTo(widget.api.config.today) >= 0) {
        nearest.putIfAbsent(doctor, () => s);
      }
    }
    final entries = nearest.entries.toList();
    for (var i = 0; i < entries.length; i += 4) {
      if (!mounted || revision != catalogRevision) return;
      await Future.wait(
        entries.skip(i).take(4).map((entry) async {
          String status;
          try {
            final items = rows(
              await widget.api.request(
                'GET',
                '/slot-praktik',
                query: {'jadwalPraktikId': '${entry.value['id']}'},
              ),
            );
            final available = items
                .where((s) => s['aktif'] != false && s['tersedia'] == true)
                .length;
            status = available > 0
                ? '$available slot tersedia pada sesi terdekat'
                : 'Belum ada slot tersedia pada sesi terdekat';
          } catch (_) {
            status = 'Ketersediaan slot belum dapat dimuat';
          }
          if (mounted && revision == catalogRevision) {
            setState(() => clinicAvailability[entry.key] = status);
          }
        }),
      );
    }
  }

  Future<List<Json>> fetchClinicSchedules(String clinic) async => rows(
    await widget.api.request(
      'GET',
      '/jadwal-praktik',
      query: {'layananId': clinic},
    ),
  );

  Future<void> loadClinicSchedules() async {
    final clinic = serviceId;
    if (clinic == null) return;
    final current = ++catalogRevision;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await fetchClinicSchedules(clinic);
      if (mounted && current == catalogRevision) {
        setState(() => clinicSchedules = result);
        await readAvailability(result, current);
      }
    } catch (e) {
      if (mounted && current == catalogRevision) setState(() => error = '$e');
    } finally {
      if (mounted && current == catalogRevision) {
        setState(() => loading = false);
      }
    }
  }

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
    overview = RefreshGate(readOverview);
    updates = PatientUpdates(api: widget.api)..addListener(autoRefresh);
    load();
  }

  Future<void> load() async {
    if (!mounted) return;
    setState(() {
      loading = true;
      error = null;
    });
    await overview.refresh();
    if (mounted) setState(() => loading = false);
  }

  void autoRefresh() {
    overview.refresh();
  }

  Future<void> readOverview() async {
    final errors = <String>[];
    await Future.wait([
      (() async {
        try {
          final values = await Future.wait(
            [
              '/tiket/saya',
              '/janji-temu',
            ].map((p) async => rows(await widget.api.request('GET', p))),
          );
          if (mounted) {
            setState(() {
              tickets = values[0];
              appointments = values[1];
            });
          }
        } catch (e) {
          errors.add('$e');
        }
      })(),
      (() async {
        try {
          final result = rows(
            await widget.api.request('GET', '/jadwal-praktik'),
          );
          if (mounted) {
            setState(() {
              homeSchedules = result;
              homeScheduleError = null;
            });
          }
        } catch (_) {
          if (mounted) {
            setState(
              () => homeScheduleError = 'Jadwal praktik belum dapat dimuat.',
            );
          }
        }
      })(),
      readCatalog().catchError((Object e) {
        errors.add('$e');
      }),
    ]);
    if (mounted) setState(() => error = errors.firstOrNull);
  }

  Future<void> readCatalog() async {
    final current = catalogRevision;
    final selectedDoctor = doctorId,
        selectedClinic = serviceId,
        selectedSession = sessionId;
    try {
      final values = await Future.wait(
        [
          '/layanan',
          '/dokter',
        ].map((p) async => rows(await widget.api.request('GET', p))),
      );
      if (mounted) {
        setState(() {
          services = values[0].where((s) => s['aktif'] != false).toList();
          doctors = values[1].where((d) => d['aktif'] != false).toList();
          if (current == catalogRevision &&
              selectedClinic != null &&
              (!services.any((s) => s['id'] == selectedClinic) ||
                  (selectedDoctor != null &&
                      !matchingDoctors.any(
                        (d) => d['id'] == selectedDoctor,
                      )))) {
            serviceId = services.any((s) => s['id'] == selectedClinic)
                ? selectedClinic
                : null;
            doctorId = sessionId = slotId = null;
            schedules = [];
            slots = [];
            clinicSchedules = [];
            bookingStage = false;
            loading = false;
            catalogRevision++;
          }
        });
      }
      if (mounted && current == catalogRevision && selectedClinic != null) {
        final nextCalendar = await fetchClinicSchedules(selectedClinic);
        if (mounted && current == catalogRevision) {
          setState(() => clinicSchedules = nextCalendar);
          await readAvailability(nextCalendar, current);
        }
      }
      if (!mounted ||
          current != catalogRevision ||
          !bookingStage ||
          selectedDoctor == null ||
          selectedClinic == null) {
        return;
      }
      final nextSchedules = rows(
        await widget.api.request(
          'GET',
          '/jadwal-praktik',
          query: {
            'layananId': selectedClinic,
            'dokterId': selectedDoctor,
            'tanggal': date.text.trim(),
          },
        ),
      );
      final sessionExists = nextSchedules.any(
        (s) => s['id'] == selectedSession,
      );
      final nextSlots = !sessionExists
          ? <Json>[]
          : rows(
              await widget.api.request(
                'GET',
                '/slot-praktik',
                query: {'jadwalPraktikId': selectedSession!},
              ),
            );
      if (mounted && current == catalogRevision) {
        setState(() {
          schedules = nextSchedules;
          slots = nextSlots;
          if (!sessionExists) sessionId = null;
          if (!slots.any((s) => s['id'] == slotId && s['tersedia'] == true)) {
            slotId = null;
          }
        });
      }
    } catch (_) {
      rethrow;
    }
  }

  Future<void> loadSchedules() async {
    if (serviceId == null || doctorId == null) return;
    final current = ++catalogRevision;
    setState(() {
      loading = true;
      bookingStage = true;
      schedules = [];
      slots = [];
      sessionId = null;
      slotId = null;
      error = null;
    });
    try {
      final result = rows(
        await widget.api.request(
          'GET',
          '/jadwal-praktik',
          query: {
            'layananId': serviceId!,
            'dokterId': doctorId!,
            'tanggal': date.text.trim(),
          },
        ),
      );
      if (mounted && current == catalogRevision) {
        setState(() => schedules = result);
      }
    } catch (e) {
      if (mounted && current == catalogRevision) setState(() => error = '$e');
    } finally {
      if (mounted && current == catalogRevision) {
        setState(() => loading = false);
      }
    }
  }

  Future<void> loadSlots(String id) async {
    final current = ++catalogRevision;
    setState(() {
      loading = true;
      sessionId = id;
      slots = [];
      slotId = null;
      error = null;
    });
    try {
      final result = rows(
        await widget.api.request(
          'GET',
          '/slot-praktik',
          query: {'jadwalPraktikId': id},
        ),
      );
      if (mounted && current == catalogRevision) setState(() => slots = result);
    } catch (e) {
      if (mounted && current == catalogRevision) setState(() => error = '$e');
    } finally {
      if (mounted && current == catalogRevision) {
        setState(() => loading = false);
      }
    }
  }

  Future<void> book() async {
    if (busy || reviewing) return;
    if (serviceId == null || (appointment && slotId == null)) {
      setState(
        () => error = 'Pilih poli dan slot yang tersedia terlebih dahulu.',
      );
      return;
    }
    final parsed = DateTime.tryParse(date.text.trim());
    if (parsed == null || calendarDate(parsed) != date.text.trim()) {
      setState(() => error = 'Tanggal pelayanan harus YYYY-MM-DD yang valid.');
      return;
    }
    final chosenSlot = slotId,
        chosenService = serviceId,
        chosenDate = date.text.trim();
    final isAppointment = appointment;
    final session = schedules.where((s) => s['id'] == sessionId).firstOrNull;
    final slot = slots
        .where(
          (s) =>
              s['id'] == chosenSlot &&
              s['aktif'] != false &&
              s['tersedia'] == true,
        )
        .firstOrNull;
    if (isAppointment && (session == null || slot == null)) {
      setState(() => error = 'Slot berubah. Pilih kembali slot yang tersedia.');
      return;
    }
    reviewing = true;
    final accepted = isAppointment
        ? await showDialog<bool>(
                context: context,
                builder: (_) => AppointmentReview(
                  doctor:
                      doctors.where((d) => d['id'] == doctorId).firstOrNull ??
                      {},
                  clinic: selectedService!,
                  session: session!,
                  slot: slot!,
                  config: widget.api.config,
                ),
              ) ==
              true
        : await confirm(
            context,
            'Daftarkan walk-in pada ${label(selectedService!)} tanggal $chosenDate?',
          );
    reviewing = false;
    if (!mounted || !accepted) return;
    if (serviceId != chosenService ||
        date.text.trim() != chosenDate ||
        appointment != isAppointment ||
        (isAppointment &&
            (slotId != chosenSlot ||
                !slots.any(
                  (s) =>
                      s['id'] == chosenSlot &&
                      s['tersedia'] == true &&
                      s['aktif'] != false,
                )))) {
      setState(
        () => error = 'Pilihan berubah selama konfirmasi. Periksa jadwal dan pilih slot kembali.',
      );
      return;
    }
    setState(() {
      busy = true;
      error = null;
      message = null;
    });
    try {
      final result = object(
        await widget.api.request(
          'POST',
          appointment ? '/janji-temu' : '/reservasi',
          body: appointment
              ? {'slotPraktikId': slotId}
              : {'layananId': serviceId, 'tanggalAntrean': date.text.trim()},
        ),
      );
      if (mounted) {
        setState(() {
          final issued = appointment ? object(result['tiket']) : result;
          message =
              'Pendaftaran berhasil.${issued['nomorAntrean'] == null ? '' : ' Tiket ${issued['nomorAntrean']}.'} Tiket tersedia di Tiket Saya.';
          tab = 1;
          slotId = null;
        });
      }
      await load();
    } catch (e) {
      // Never retry POST after an uncertain response. Reconcile owned tickets and
      // invalidate the selected slot, including when another patient fills it.
      if (mounted) setState(() => slotId = null);
      await readOverview();
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> cancel(Json appt) async {
    if (!await confirm(
      context,
      'Batalkan janji temu ini? Hanya tiket DIPESAN dapat dibatalkan.',
    )) {
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.api.request(
        'POST',
        '/janji-temu/${appt['id']}/batalkan',
        body: {},
      );
      if (mounted) setState(() => message = 'Janji temu dibatalkan.');
      await load();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> openTicket(Json ticket) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _TicketDialog(
        api: widget.api,
        updates: updates,
        ticket: ticket,
        appointment: appointments
            .where((a) => object(a['tiket'])['id'] == ticket['id'])
            .firstOrNull,
      ),
    );
    if (mounted) await load();
  }

  @override
  void dispose() {
    updates.removeListener(autoRefresh);
    updates.dispose();
    overview.dispose();
    date.dispose();
    super.dispose();
  }

  Future<void> selectService(String? value) {
    setState(() {
      catalogRevision++;
      serviceId = value;
      clinicAvailability.clear();
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
      tab = 2;
      channel = isAppointment ? 'Janji temu' : 'Walk-in';
      clinicAvailability.clear();
      appointment = isAppointment;
      bookingStage = false;
      doctorDetail = false;
      serviceId = doctorId = sessionId = slotId = null;
      catalogRevision++;
      schedules = [];
      slots = [];
      search = '';
      clinicSchedules = [];
    });
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

  List<Json> get visibleClinics => services
      .where(
        (clinic) =>
            label(clinic).toLowerCase().contains(search) ||
            doctors.any(
              (doctor) =>
                  ('${label(doctor)} ${doctor['spesialisasi'] ?? ''}')
                      .toLowerCase()
                      .contains(search) &&
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
    final previews = homeDoctorPreviews(
      doctors,
      services,
      homeSchedules,
      widget.api.config,
      search,
      clinicId: services.any((c) => c['id'] == homeClinicId)
          ? homeClinicId
          : null,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PatientHomeWelcome(
          name: '${widget.api.user?['nama'] ?? 'Pasien'}',
          onSearch: (v) => setState(() => search = v.toLowerCase().trim()),
          avatar: AccountAvatar(api: widget.api, radius: 23),
        ),
        const SizedBox(height: 16),
        if (active != null) ...[
          PatientHomeSectionTitle(
            'Kunjungan Terdekat',
            action: 'Lihat Semua',
            onPressed: busy ? null : () => setState(() => tab = 1),
          ),
          const SizedBox(height: 8),
          PatientHomeVisit(
            ticket: active,
            doctor: doctor,
            appointment: visit,
            config: widget.api.config,
            onTicket: busy ? null : () => openTicket(active),
          ),
          const SizedBox(height: 20),
        ],
        PatientHomeSectionTitle(
          'Cari Dokter Spesialis',
          action: 'Lihat Semua',
          onPressed: busy
              ? null
              : () {
                  startRegistration(true);
                  setState(() => channel = 'Semua');
                },
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final clinic in <Json>[
                {'nama': 'Semua'},
                ...visibleClinics,
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(label(clinic)),
                    selected: clinic['id'] == homeClinicId,
                    showCheckmark: false,
                    selectedColor: QueueBStyle.teal,
                    labelStyle: TextStyle(
                      color: clinic['id'] == homeClinicId
                          ? Colors.white
                          : QueueBStyle.navy,
                      fontSize: 12,
                    ),
                    onSelected: busy
                        ? null
                        : (_) => setState(
                            () => homeClinicId = clinic['id'] as String?,
                          ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        PatientHomeSectionTitle(
          'Dokter Pilihan',
          action: 'Lihat Semua',
          onPressed: busy
              ? null
              : () {
                  startRegistration(true);
                  setState(() => channel = 'Semua');
                },
        ),
        if (loading)
          const PatientHomeLoading()
        else if (previews.isEmpty)
          const PatientHomeEmpty(
            text: 'Belum ada dokter yang sesuai pencarian.',
          )
        else ...[
          if (homeScheduleError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                homeScheduleError!,
                style: const TextStyle(color: QueueBStyle.muted, fontSize: 12),
              ),
            ),
          for (final preview in previews.take(3))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: PatientHomeDoctor(
                preview: preview,
                config: widget.api.config,
                scheduleUnavailable: homeScheduleError != null,
                onTap: busy || loading
                    ? null
                    : () async {
                        final pending = selectService(
                          '${preview.clinic['id']}',
                        );
                        final revision = catalogRevision;
                        await pending;
                        if (mounted &&
                            revision == catalogRevision &&
                            error == null &&
                            tab == 2) {
                          await chooseDoctor(preview.doctor);
                        }
                      },
              ),
            ),
        ],
        const SizedBox(height: 12),
        PatientHomeShortcuts(
          enabled: !busy,
          onClinics: () {
            startRegistration(true);
            setState(() => channel = 'Semua');
          },
          onAppointment: () => startRegistration(true),
          onTickets: () => setState(() => tab = 1),
          onHistory: () => setState(() => tab = 4),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: busy ? null : () => startRegistration(false),
          icon: const Icon(Icons.directions_walk),
          label: const Text('Daftar Walk-in'),
        ),
        TextButton.icon(
          onPressed: busy
              ? null
              : () => showDialog<void>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Public Display'),
                    content: const Text(
                      'Public Display rumah sakit memakai token perangkat dari pengelola. Tiket pribadi tersedia di Tiket Saya.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Tutup'),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.pop(context);
                          widget.onDisplay?.call();
                        },
                        child: const Text('Buka Public Display'),
                      ),
                    ],
                  ),
                ),
          icon: const Icon(Icons.connected_tv_outlined),
          label: const Text('Informasi Antrean'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      if (widget.headerBuilder != null)
        SizedBox(
          height: kToolbarHeight + MediaQuery.paddingOf(context).top,
          child: widget.headerBuilder!(tab == 0, () => setState(() => tab = 1)),
        ),
      Expanded(
        child: ColoredBox(
          color: tab == 0
              ? PatientHomeStyle.background
              : QueueBStyle.background,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: ListView(
                key: ValueKey('$tab:$serviceId:$bookingStage:$doctorDetail'),
                padding: const EdgeInsets.all(16),
                children: [
                  ValueListenableBuilder<String>(
                    valueListenable: updates.status,
                    builder: (context, value, _) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        value,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ),
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
                  if (tab == 0) _home(context),
                  if (tab == 2) _registration(context),
                  if (tab == 1) _tickets(context),
                  if (tab == 4) _history(context),
                  if (tab == 3)
                    Section(
                      title: 'Janji temu saya',
                      action: IconButton(
                        tooltip: 'Muat ulang janji temu',
                        onPressed: busy || loading ? null : load,
                        icon: const Icon(Icons.refresh),
                      ),
                      child: Column(
                        children: [
                          if (appointments.isEmpty && !loading)
                            const EmptyState(text: 'Belum ada janji temu.'),
                          for (final a in appointments)
                            AppCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    appointmentDetails(a, widget.api.config),
                                  ),
                                  StatusBadge(object(a['tiket'])['status']),
                                  TextButton(
                                    onPressed: () => setState(() => tab = 1),
                                    child: const Text('Lihat tiket'),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
      SafeArea(
        top: false,
        child: NavigationBar(
          height: tab == 0 ? 68 : null,
          selectedIndex: tab == 4 ? 0 : [0, 2, 1, 3].indexOf(tab),
          onDestinationSelected: busy
              ? null
              : (i) => setState(() => tab = [0, 2, 1, 3][i]),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Beranda',
            ),
            NavigationDestination(
              icon: Icon(Icons.add_circle_outline),
              label: 'Pendaftaran',
            ),
            NavigationDestination(
              icon: Icon(Icons.confirmation_number_outlined),
              label: 'Tiket Saya',
            ),
            NavigationDestination(
              icon: Icon(Icons.calendar_month_outlined),
              label: 'Janji Temu',
            ),
          ],
        ),
      ),
    ],
  );

  Widget _registration(BuildContext context) {
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
              ? 'Poliklinik & Dokter'
              : clinicName,
          caption: 'Waktu pelayanan: ${widget.api.config.serviceTimeZone}',
          onBack: serviceId == null
              ? null
              : busy || loading
              ? null
              : () => setState(() {
                  catalogRevision++;
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
                        catalogRevision++;
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
              color: sessionId == s['id'] ? QueueBStyle.mint : null,
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
              style: TextStyle(fontSize: 12, color: QueueBStyle.muted),
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
              style: const TextStyle(color: QueueBStyle.darkTeal),
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

  Widget _tickets(BuildContext context) => Section(
    title: 'Tiket Saya',
    action: OutlinedButton.icon(
      onPressed: busy || loading ? null : load,
      icon: const Icon(Icons.refresh),
      label: const Text('Muat ulang tiket'),
    ),
    child: Column(
      children: [
        if (tickets.isEmpty)
          const EmptyState(
            text: 'Belum ada tiket. Daftar janji temu atau walk-in terlebih dahulu.',
            icon: Icons.confirmation_number_outlined,
          ),
        for (final t in tickets)
          Card(
            color: QueueBStyle.mint,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${t['nomorAntrean']}',
                    style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: QueueBStyle.navy,
                    ),
                  ),
                  PatientInfoRow(
                    icon: Icons.local_hospital_outlined,
                    title: 'Poliklinik',
                    value: label(object(t['layanan'])),
                  ),
                  Text(
                    patientDate(
                      '${t['tanggalPelayanan'] ?? t['tanggalAntrean']}',
                    ),
                  ),
                  for (final a in appointments.where(
                    (a) => object(a['tiket'])['id'] == t['id'],
                  ))
                    Text(
                      appointmentDetails(a, widget.api.config),
                      style: const TextStyle(
                        fontSize: 12,
                        color: QueueBStyle.muted,
                      ),
                    ),
                  StatusBadge(t['status']),
                  Wrap(
                    spacing: 12,
                    children: [
                      OutlinedButton(
                        onPressed: busy ? null : () => openTicket(t),
                        child: const Text('Lihat tiket / QR'),
                      ),
                      for (final a in appointments.where(
                        (a) =>
                            object(a['tiket'])['id'] == t['id'] &&
                            t['status'] == 'DIPESAN',
                      ))
                        TextButton(
                          onPressed: busy ? null : () => cancel(a),
                          child: const Text('Batalkan janji temu'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}

class _TicketDialog extends StatefulWidget {
  const _TicketDialog({
    required this.api,
    required this.ticket,
    required this.updates,
    this.appointment,
  });
  final QueueApi api;
  final Json ticket;
  final PatientUpdates updates;
  final Json? appointment;
  @override
  State<_TicketDialog> createState() => _TicketDialogState();
}

class _TicketDialogState extends State<_TicketDialog> {
  late final RefreshGate reader;
  late Json data = widget.ticket;
  Json? qr;
  String? error;
  bool busy = false;
  Timer? countdown;
  int remaining = 0;
  bool get canIssue =>
      data['status'] == 'DIPESAN' &&
      dateOnly(data['tanggalPelayanan'] ?? data['tanggalAntrean']) ==
          widget.api.config.today;
  @override
  void initState() {
    super.initState();
    reader = RefreshGate(readTicket);
    widget.updates.addListener(refresh);
    countdown = Timer.periodic(const Duration(seconds: 1), (_) {
      final expiry = DateTime.tryParse('${qr?['berlakuHingga']}');
      if (mounted) {
        setState(() {
          remaining = expiry == null
              ? 0
              : expiry.difference(DateTime.now()).inSeconds.clamp(0, 600);
          if (remaining == 0) qr = null;
        });
      }
    });
    refresh();
  }

  Future<void> refresh() => reader.refresh();
  Future<void> readTicket() async {
    try {
      final next = object(
        await widget.api.request('GET', '/tiket/${data['id']}'),
      );
      if (mounted) {
        setState(() {
          data = next;
          error = null;
          if (data['status'] != 'DIPESAN') qr = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  Future<void> issue() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
      qr = null;
    });
    try {
      final result = object(
        await widget.api.request('POST', '/tiket/${data['id']}/qr', body: {}),
      );
      if (mounted) {
        setState(() {
          qr = result;
          remaining = DateTime.parse('${result['berlakuHingga']}')
              .difference(DateTime.now())
              .inSeconds
              .clamp(0, 600);
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
      await refresh();
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    widget.updates.removeListener(refresh);
    reader.dispose();
    countdown?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      insetPadding: const EdgeInsets.all(16),
      contentPadding: const EdgeInsets.all(16),
      title: Text('Tiket ${data['nomorAntrean']}'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const QueueBBrand(compact: true),
              const SizedBox(height: 24),
              Text(
                '${data['nomorAntrean']}',
                style: Theme.of(context).textTheme.displayLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: QueueBStyle.navy,
                ),
              ),
              Text(
                '${label(object(data['layanan']))} · ${dateOnly(data['tanggalPelayanan'] ?? data['tanggalAntrean'])}',
              ),
              StatusBadge(data['status']),
              SelectableText(
                'ID tiket: ${data['id']}',
                style: const TextStyle(fontSize: 11, color: QueueBStyle.muted),
              ),
              if (error != null) MobileNotice(error!, error: true),
              if (qr != null && remaining > 0) ...[
                LayoutBuilder(
                  builder: (context, box) => QrImageView(
                    data: '${qr!['qrPayload']}',
                    size: box.maxWidth.clamp(0, 240),
                    backgroundColor: Colors.white,
                    semanticsLabel: 'QR check-in tiket ${data['nomorAntrean']}',
                  ),
                ),
                Text('Berlaku $remaining detik · sekali pakai'),
                const Text('Tempel payload hanya kepada petugas berwenang.'),
                SelectableText(
                  '${qr!['qrPayload']}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: QueueBStyle.muted,
                  ),
                ),
              ],
              if (widget.appointment != null)
                MobileNotice(
                  appointmentDetails(widget.appointment!, widget.api.config),
                ),
              if (canIssue) ...[
                const MobileNotice(
                  'QR diterbitkan pada hari pelayanan, berlaku 10 menit. QR baru menggantikan QR sebelumnya.',
                ),
                FilledButton(
                  onPressed: busy ? null : issue,
                  child: Text(qr == null ? 'Terbitkan QR' : 'Perbarui QR'),
                ),
              ] else
                const MobileNotice(
                  'QR tersedia untuk tiket DIPESAN pada tanggal pelayanan. Status disinkronkan secara berkala.',
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : refresh,
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
