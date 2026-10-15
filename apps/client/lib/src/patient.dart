import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'api.dart';
import 'config.dart';
import 'widgets.dart';

String appointmentDetails(Json appointment, AppConfig config) {
  final slot = object(appointment['slotPraktik']);
  final session = object(slot['jadwalPraktik']);
  final doctor = object(object(session['dokterLayanan'])['dokter']);
  return 'Janji temu: ${label(doctor)}\nRuang: ${label(object(session['loket']))}\nSlot: ${config.instantLabel(slot['mulaiPada'])} – ${config.instantLabel(slot['selesaiPada'])}';
}

class PatientPage extends StatefulWidget {
  const PatientPage({super.key, required this.api});
  final QueueApi api;
  @override
  State<PatientPage> createState() => _PatientPageState();
}

class _PatientPageState extends State<PatientPage> {
  int tab = 0, catalogRevision = 0;
  bool busy = false, loading = true;
  String? error, message, serviceId, doctorId, sessionId, slotId;
  bool appointment = true;
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

  @override
  Widget build(BuildContext context) => Column(
    children: [
      NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: busy ? null : (i) => setState(() => tab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.event_available),
            label: 'Pendaftaran',
          ),
          NavigationDestination(
            icon: Icon(Icons.confirmation_number_outlined),
            label: 'Tiket Saya',
          ),
        ],
      ),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (error != null) Notice(error!, error: true),
            if (message != null) Notice(message!),
            if (loading) const LinearProgressIndicator(),
            if (tab == 0)
              Section(
                title: 'Daftar pelayanan',
                subtitle:
                    'Pilih poli, tanggal dan kanal pendaftaran. Zona: ${widget.api.config.serviceTimeZone}.',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ChoiceField(
                      label: 'Poliklinik',
                      choices: choicesOf(services),
                      value: serviceId,
                      onChanged: busy || loading
                          ? null
                          : (v) => setState(() {
                              catalogRevision++;
                              serviceId = v;
                              doctorId = null;
                              sessionId = null;
                              slotId = null;
                              schedules = [];
                              slots = [];
                              appointment =
                                  selectedService?['modeReservasi'] !=
                                  'ANTREAN_HARIAN';
                            }),
                    ),
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
                                    firstDate: DateTime.parse(
                                      widget.api.config.today,
                                    ),
                                    lastDate: DateTime.parse(
                                      widget.api.config.today,
                                    ).add(const Duration(days: 365)),
                                  );
                                  if (chosen != null && mounted) {
                                    setState(() {
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
                        schedules = [];
                        slots = [];
                        sessionId = null;
                        slotId = null;
                      }),
                    ),
                    if (selectedService != null) ...[
                      const SizedBox(height: 16),
                      SegmentedButton<bool>(
                        segments: [
                          if (selectedService!['modeReservasi'] !=
                              'ANTREAN_HARIAN')
                            const ButtonSegment(
                              value: true,
                              label: Text('Janji temu'),
                            ),
                          if (selectedService!['modeReservasi'] !=
                              'JANJI_TEMU_DOKTER')
                            const ButtonSegment(
                              value: false,
                              label: Text('Walk-in'),
                            ),
                        ],
                        selected: {appointment},
                        onSelectionChanged: busy || loading
                            ? null
                            : (v) => setState(() => appointment = v.first),
                      ),
                      if (appointment) ...[
                        const SizedBox(height: 16),
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
                        for (final s in slots)
                          ListTile(
                            title: Text(
                              '${widget.api.config.instantLabel(s['mulaiPada'])}–${widget.api.config.instantLabel(s['selesaiPada'])}',
                            ),
                            subtitle: Text(
                              '${s['tersedia'] == true ? 'Tersedia' : 'Tidak tersedia'} · Sisa slot ${s['sisaKapasitas']}',
                            ),
                            selected: slotId == s['id'],
                            leading: Icon(
                              slotId == s['id']
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_off,
                            ),
                            onTap: busy || loading || s['tersedia'] != true
                                ? null
                                : () => setState(() => slotId = '${s['id']}'),
                          ),
                      ] else
                        const Notice(
                          'Walk-in mengikuti kuota harian poli. Bawa tiket QR pada tanggal pelayanan.',
                        ),
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed:
                            busy || loading || (appointment && slotId == null)
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
              ),
            if (tab == 1)
              Section(
                title: 'Tiket Saya',
                action: OutlinedButton.icon(
                  onPressed: busy || loading ? null : load,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Muat ulang tiket'),
                ),
                child: Column(
                  children: [
                    if (tickets.isEmpty)
                      const Text(
                        'Belum ada tiket. Daftar janji temu atau walk-in terlebih dahulu.',
                      ),
                    for (final t in tickets)
                      Card(
                        color: const Color(0xfff4f6fa),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${t['nomorAntrean']}',
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineSmall,
                              ),
                              Text(
                                '${label(object(t['layanan']))} · ${dateOnly(t['tanggalPelayanan'] ?? t['tanggalAntrean'])}',
                              ),
                              stateChip(t['status']),
                              Wrap(
                                spacing: 12,
                                children: [
                                  OutlinedButton(
                                    onPressed: busy
                                        ? null
                                        : () => openTicket(t),
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
              ),
          ],
        ),
      ),
    ],
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
      title: Text('Tiket ${data['nomorAntrean']}'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.appointment != null)
                Notice(
                  appointmentDetails(widget.appointment!, widget.api.config),
                ),
              Text(
                '${label(object(data['layanan']))} · ${dateOnly(data['tanggalPelayanan'] ?? data['tanggalAntrean'])}',
              ),
              stateChip(data['status']),
              SelectableText('ID tiket: ${data['id']}'),
              if (error != null) Notice(error!, error: true),
              if (qr != null && remaining > 0) ...[
                QrImageView(
                  data: '${qr!['qrPayload']}',
                  size: 240,
                  backgroundColor: Colors.white,
                  semanticsLabel: 'QR check-in tiket ${data['nomorAntrean']}',
                ),
                Text('Berlaku $remaining detik · sekali pakai'),
                const Text('Tempel payload hanya kepada petugas berwenang.'),
                SelectableText('${qr!['qrPayload']}'),
              ],
              if (canIssue) ...[
                const Notice(
                  'QR diterbitkan pada hari pelayanan, berlaku 10 menit. QR baru menggantikan QR sebelumnya.',
                ),
                FilledButton(
                  onPressed: busy ? null : issue,
                  child: Text(qr == null ? 'Terbitkan QR' : 'Perbarui QR'),
                ),
              ] else
                const Notice(
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
