import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'api.dart';
import 'config.dart';
import 'widgets.dart';
import 'mobile_ui.dart';

String appointmentDetails(Json appointment, AppConfig config) {
  final slot = object(appointment['slotPraktik']);
  final session = object(slot['jadwalPraktik']);
  final doctor = object(object(session['dokterLayanan'])['dokter']);
  return 'Janji temu: ${label(doctor)}\nRuang: ${label(object(session['loket']))}\nSlot: ${config.instantLabel(slot['mulaiPada'])} – ${config.instantLabel(slot['selesaiPada'])}';
}

class PatientPage extends StatefulWidget {
  const PatientPage({super.key, required this.api, this.onDisplay});
  final QueueApi api;
  final VoidCallback? onDisplay;
  @override
  State<PatientPage> createState() => _PatientPageState();
}

class _PatientPageState extends State<PatientPage> {
  int tab = 0, catalogRevision = 0;
  bool busy = false, loading = true;
  String? error, message, serviceId, doctorId, sessionId, slotId;
  bool appointment = true, bookingStage = false;
  String search = '', channel = 'Semua';
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
            rows(d['dokterLayanan'])
                .any((l) => l['layananId'] == serviceId && l['aktif'] == true),
      )
      .toList();
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final values = await Future.wait(
        [
          '/layanan',
          '/dokter',
          '/tiket/saya',
          '/janji-temu',
        ].map((p) async => rows(await widget.api.request('GET', p))),
      );
      if (mounted) {
        setState(() {
          services = values[0];
          doctors = values[1];
          tickets = values[2];
          appointments = values[3];
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => loading = false);
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
    if (busy) return;
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
    if (!await confirm(
      context,
      'Daftarkan ${appointment ? 'janji temu' : 'walk-in'} pada ${label(selectedService!)} tanggal ${date.text.trim()}?',
    )) {
      return;
    }
    setState(() {
      busy = true;
      error = null;
      message = null;
    });
    try {
      await widget.api.request(
        'POST',
        appointment ? '/janji-temu' : '/reservasi',
        body: appointment
            ? {'slotPraktikId': slotId}
            : {'layananId': serviceId, 'tanggalAntrean': date.text.trim()},
      );
      if (mounted) {
        setState(() {
          message = 'Pendaftaran berhasil. Tiket tersedia di Tiket Saya.';
          tab = 1;
          slotId = null;
        });
      }
      await load();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
      // A lost mutation response is uncertain; read owned tickets before another attempt.
      try {
        final current = rows(await widget.api.request('GET', '/tiket/saya'));
        if (mounted) setState(() => tickets = current);
      } catch (_) {}
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
    date.dispose();
    super.dispose();
  }

  void selectService(String? value) {
    setState(() {
      catalogRevision++;
      serviceId = value;
      doctorId = sessionId = slotId = null;
      schedules = [];
      slots = [];
      bookingStage = false;
      appointment = selectedService?['modeReservasi'] != 'ANTREAN_HARIAN';
      if (channel == 'Walk-in' &&
          selectedService?['modeReservasi'] != 'JANJI_TEMU_DOKTER') {
        appointment = false;
      }
    });
  }

  void startRegistration(bool isAppointment) {
    setState(() {
      tab = 2;
      channel = isAppointment ? 'Janji temu' : 'Walk-in';
      appointment = isAppointment;
      bookingStage = false;
      serviceId = doctorId = sessionId = slotId = null;
      catalogRevision++;
      schedules = [];
      slots = [];
      search = '';
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

  Widget _quickAction(
    String title,
    String subtitle,
    IconData icon,
    VoidCallback onTap,
  ) => Card(
    child: InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: busy ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: QueueBStyle.darkTeal, size: 30),
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 12, color: QueueBStyle.muted),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _home(BuildContext context) {
    final upcoming = appointments
        .where(
          (a) =>
              ![
                'SELESAI',
                'DIBATALKAN',
              ].contains(object(a['tiket'])['status']) &&
              (dateOnly(a['tanggalPelayanan']).isNotEmpty &&
                  dateOnly(a['tanggalPelayanan'])
                          .compareTo(widget.api.config.today) >=
                      0),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            CircleAvatar(
              backgroundColor: QueueBStyle.mint,
              foregroundColor: QueueBStyle.darkTeal,
              child: Text(
                '${widget.api.user?['nama'] ?? 'P'}'
                    .substring(0, 1)
                    .toUpperCase(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Selamat datang,',
                    style: TextStyle(color: QueueBStyle.muted),
                  ),
                  Text(
                    '${widget.api.user?['nama'] ?? 'Pasien'}',
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: QueueBStyle.darkTeal,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.health_and_safety_outlined, color: Colors.white),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'QueueB Hospital',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                'Antre lebih mudah.\nBerobat lebih nyaman.',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Rencanakan kunjungan dan pantau tiket Anda dalam satu aplikasi.',
                style: TextStyle(color: Colors.white),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Akses cepat',
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        LayoutBuilder(
          builder: (context, box) => Wrap(
            spacing: 8,
            children: [
              for (final item in <(String, String, IconData, VoidCallback)>[
                (
                  'Daftar Walk-in',
                  'Ambil nomor antrean poli',
                  Icons.directions_walk,
                  () => startRegistration(false),
                ),
                (
                  'Janji Temu Dokter',
                  'Pilih dokter dan jadwal',
                  Icons.calendar_month_outlined,
                  () => startRegistration(true),
                ),
                (
                  'Tiket Saya',
                  'Lihat status dan QR tiket',
                  Icons.confirmation_number_outlined,
                  () => setState(() => tab = 1),
                ),
                (
                  'Informasi Antrean',
                  'Public Display rumah sakit',
                  Icons.connected_tv_outlined,
                  () => showDialog<void>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Public Display'),
                      content: const Text(
                        'Layar informasi rumah sakit memakai token perangkat yang disediakan pengelola. Status tiket pribadi tersedia di Tiket Saya.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () {
                            Navigator.pop(context);
                            setState(() => tab = 1);
                          },
                          child: const Text('Tiket Saya'),
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
                ),
              ])
                SizedBox(
                  width: (box.maxWidth - 8) / 2,
                  child: _quickAction(item.$1, item.$2, item.$3, item.$4),
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: Text(
                'Janji temu mendatang',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            TextButton(
              onPressed: () => setState(() => tab = 3),
              child: const Text('Lihat semua'),
            ),
          ],
        ),
        if (upcoming.isEmpty)
          const EmptyState(
            text: 'Belum ada janji temu mendatang.',
            icon: Icons.event_available_outlined,
          ),
        for (final a in upcoming.take(2))
          AppCard(
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(
                Icons.event_available,
                color: QueueBStyle.darkTeal,
              ),
              title: Text(label(object(object(a['tiket'])['layanan']))),
              subtitle: Text(appointmentDetails(a, widget.api.config)),
              onTap: () => setState(() => tab = 3),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Expanded(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              key: ValueKey('$tab:$bookingStage'),
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
                if (tab == 0) _home(context),
                if (tab == 2) _registration(context),
                if (tab == 1) _tickets(context),
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
                                Text(appointmentDetails(a, widget.api.config)),
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
      SafeArea(
        top: false,
        child: NavigationBar(
          selectedIndex: [0, 2, 1, 3].indexOf(tab),
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

  Widget _registration(BuildContext context) => Section(
    title: bookingStage ? 'Booking janji temu' : 'Pilih poliklinik & dokter',
    subtitle:
        'Pilih poli, tanggal dan kanal pendaftaran. Zona: ${widget.api.config.serviceTimeZone}.',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!bookingStage) ..._catalog(context),
        if (bookingStage) ...[
          TextButton.icon(
            onPressed: busy || loading
                ? null
                : () => setState(() => bookingStage = false),
            icon: const Icon(Icons.arrow_back),
            label: const Text('Kembali ke dokter'),
          ),
          DoctorCard(
            name: label(
              doctors.where((d) => d['id'] == doctorId).firstOrNull ?? {},
            ),
            specialty:
                '${doctors.where((d) => d['id'] == doctorId).firstOrNull?['spesialisasi'] ?? ''}',
            onTap: null,
          ),
        ],
        if (bookingStage)
          Text(
            label(selectedService ?? {}),
            style: Theme.of(context).textTheme.titleMedium,
          ),
        if (!bookingStage)
          ChoiceField(
            label: 'Poliklinik',
            choices: choicesOf(services),
            value: serviceId,
            onChanged: busy || loading ? null : selectService,
          ),
        const SizedBox(height: 16),
        if (bookingStage) ...[
          const Text(
            'Tanggal kunjungan',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 76,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: 7,
              separatorBuilder: (_, index) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final day = DateTime.parse(widget.api.config.today)
                    .add(Duration(days: index));
                final value = calendarDate(day);
                final selected = date.text == value;
                return OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    backgroundColor: selected ? QueueBStyle.mint : null,
                    side: BorderSide(
                      color: selected ? QueueBStyle.teal : QueueBStyle.border,
                    ),
                  ),
                  onPressed: busy || loading
                      ? null
                      : () {
                          setState(() {
                            catalogRevision++;
                            date.text = value;
                            sessionId = slotId = null;
                            schedules = [];
                            slots = [];
                          });
                          loadSchedules();
                        },
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        const [
                          'Sen',
                          'Sel',
                          'Rab',
                          'Kam',
                          'Jum',
                          'Sab',
                          'Min',
                        ][day.weekday - 1],
                      ),
                      Text(
                        '${day.day}/${day.month}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
        ],
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
                        setState(() {
                          catalogRevision++;
                          date.text = calendarDate(chosen);
                          schedules = [];
                          slots = [];
                          sessionId = null;
                          slotId = null;
                        });
                      }
                    },
              icon: const Icon(Icons.calendar_month),
            ),
          ),
          onChanged: (_) => setState(() {
            catalogRevision++;
            schedules = [];
            slots = [];
            sessionId = null;
            slotId = null;
          }),
        ),
        if (selectedService != null) ...[
          const SizedBox(height: 16),
          if (!bookingStage)
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
                  : (v) => setState(() => appointment = v.first),
            ),
          if (appointment) ...[
            const SizedBox(height: 16),
            if (!bookingStage) ...[
              Text(
                'Dokter di poliklinik ini',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (matchingDoctors.isEmpty)
                const EmptyState(
                  text: 'Belum ada dokter terhubung pada poliklinik ini.',
                ),
              for (final d in matchingDoctors.where(
                (d) => ('${label(d)} ${d['spesialisasi'] ?? ''}')
                    .toLowerCase()
                    .contains(search),
              ))
                DoctorCard(
                  name: label(d),
                  specialty: '${d['spesialisasi'] ?? ''}',
                  selected: doctorId == d['id'],
                  onTap: busy || loading
                      ? null
                      : () {
                          setState(() => doctorId = '${d['id']}');
                          loadSchedules();
                        },
                ),
            ],
            if (!bookingStage)
              ChoiceField(
                label: 'Dokter',
                choices: matchingDoctors
                    .map(
                      (d) => (
                        '${d['id']}',
                        '${label(d)} · ${d['spesialisasi'] ?? ''}',
                      ),
                    )
                    .toList(),
                value: doctorId,
                onChanged: busy || loading
                    ? null
                    : (v) => setState(() {
                        doctorId = v;
                        schedules = [];
                        slots = [];
                        sessionId = null;
                        slotId = null;
                      }),
              ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: busy || loading || doctorId == null
                  ? null
                  : loadSchedules,
              child: const Text('Lihat jadwal dokter'),
            ),
            for (final s in schedules)
              ListTile(
                title: Text(
                  '${widget.api.config.instantLabel(s['mulaiPada'])}–${widget.api.config.instantLabel(s['selesaiPada'])}',
                ),
                subtitle: Text(label(object(s['loket']))),
                selected: sessionId == s['id'],
                trailing: OutlinedButton(
                  onPressed: busy || loading
                      ? null
                      : () => loadSlots('${s['id']}'),
                  child: const Text('Lihat slot'),
                ),
              ),
            if (!loading && doctorId != null && schedules.isEmpty)
              const Text(
                'Pilih tanggal, lalu lihat jadwal dokter. Jadwal dapat belum tersedia.',
              ),
            if (sessionId != null && !loading && slots.isEmpty)
              const EmptyState(
                text: 'Belum ada slot konsultasi pada sesi ini.',
              ),
            if (slots.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text(
                'Slot konsultasi',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in slots)
                    SizedBox(
                      width: 132,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          backgroundColor: slotId == s['id']
                              ? QueueBStyle.mint
                              : null,
                          side: BorderSide(
                            color: slotId == s['id']
                                ? QueueBStyle.teal
                                : QueueBStyle.border,
                          ),
                          padding: const EdgeInsets.all(10),
                        ),
                        onPressed: busy || loading || s['tersedia'] != true
                            ? null
                            : () => setState(() => slotId = '${s['id']}'),
                        child: Column(
                          children: [
                            Text(
                              '${widget.api.config.localInput(s['mulaiPada']).split('T').last} – ${widget.api.config.localInput(s['selesaiPada']).split('T').last}',
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${s['tersedia'] == true ? 'Tersedia' : 'Tidak tersedia'} · Sisa slot ${s['sisaKapasitas']}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ] else
            const MobileNotice(
              'Walk-in mengikuti kuota harian poli. Bawa tiket QR pada tanggal pelayanan.',
            ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: busy || loading || (appointment && slotId == null)
                ? null
                : book,
            child: Text(
              busy
                  ? 'Memproses…'
                  : appointment
                  ? 'Booking janji temu'
                  : 'Reservasi walk-in',
            ),
          ),
        ],
      ],
    ),
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
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  Text(
                    '${label(object(t['layanan']))} · ${dateOnly(t['tanggalPelayanan'] ?? t['tanggalAntrean'])}',
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
    this.appointment,
  });
  final QueueApi api;
  final Json ticket;
  final Json? appointment;
  @override
  State<_TicketDialog> createState() => _TicketDialogState();
}

class _TicketDialogState extends State<_TicketDialog> {
  late Json data = widget.ticket;
  Json? qr;
  String? error;
  bool busy = false;
  Timer? poll, countdown;
  int remaining = 0;
  bool get canIssue =>
      data['status'] == 'DIPESAN' &&
      dateOnly(data['tanggalPelayanan'] ?? data['tanggalAntrean']) ==
          widget.api.config.today;
  @override
  void initState() {
    super.initState();
    poll = Timer.periodic(const Duration(seconds: 10), (_) => refresh());
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

  bool fetching = false;
  Future<void> refresh() async {
    if (fetching) return;
    fetching = true;
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
    } finally {
      fetching = false;
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
    poll?.cancel();
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
