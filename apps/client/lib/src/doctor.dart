import 'package:flutter/material.dart';

import 'api.dart';
import 'config.dart';
import 'mobile_ui.dart';
import 'patient_sync.dart';
import 'widgets.dart';

/// Read-only portal. All scope is derived by the server from the authenticated doctor.
class DoctorPage extends StatefulWidget {
  const DoctorPage({super.key, required this.api, this.updates});
  final QueueApi api;
  final PatientUpdates? updates;
  @override
  State<DoctorPage> createState() => _DoctorPageState();
}

class _DoctorPageState extends State<DoctorPage> {
  late final PatientUpdates updates;
  late final RefreshGate gate;
  late String date;
  Json profile = {};
  List<Json> schedules = [], appointments = [], snapshots = [];
  bool loading = true;
  String? error;
  int tab = 0, revision = 0;
  @override
  void initState() {
    super.initState();
    date = widget.api.config.today;
    gate = RefreshGate(load);
    updates =
        widget.updates ??
        PatientUpdates(
          api: widget.api,
          role: 'DOKTER',
          namespace: 'doctor',
          eventKinds: const ['ANTREAN'],
        );
    updates.addListener(refresh);
    gate.refresh();
  }

  void refresh() {
    gate.refresh();
  }

  Future<void> load() async {
    final selected = date, current = ++revision;
    if (mounted) {
      setState(() {
        loading = true;
        error = null;
      });
    }
    try {
      final values = await Future.wait([
        widget.api.request('GET', '/portal-dokter/profil'),
        widget.api.request(
          'GET',
          '/portal-dokter/jadwal',
          query: {'tanggal': selected},
        ),
        widget.api.request(
          'GET',
          '/portal-dokter/janji-temu',
          query: {'tanggal': selected},
        ),
      ]);
      final sessions = rows(values[1]), now = widget.api.config.now;
      final live = sessions.where(
        (s) =>
            s['aktif'] == true &&
            selected == widget.api.config.today &&
            DateTime.tryParse('${s['mulaiPada']}')?.isAfter(now) == false &&
            DateTime.tryParse('${s['selesaiPada']}')?.isAfter(now) == true,
      );
      final monitor = <Json>[];
      for (final s in live) {
        try {
          monitor.add(
            object(
              await widget.api.request(
                'GET',
                '/portal-dokter/antrean/snapshot',
                query: {'jadwalPraktikId': '${s['id']}'},
              ),
            ),
          );
        } on ApiException catch (e) {
          // Schedule may end or be deactivated between the two reads. Never keep stale room data.
          if (e.status != 403) rethrow;
        }
      }
      if (mounted && current == revision && selected == date) {
        setState(() {
          profile = object(values[0]);
          schedules = sessions;
          appointments = rows(values[2]);
          snapshots = monitor;
        });
      }
    } catch (e) {
      if (mounted && current == revision && selected == date) {
        setState(() {
          error = '$e';
          snapshots = [];
          schedules = [];
          appointments = [];
        });
      }
    } finally {
      if (mounted && current == revision && selected == date) {
        setState(() => loading = false);
      }
    }
  }

  Future<void> pickDate() async {
    final selected = DateTime.parse(date),
        today = DateTime.parse(widget.api.config.today);
    final picked = await showDatePicker(
      context: context,
      initialDate: selected,
      firstDate: DateTime(today.year - 5),
      lastDate: DateTime(today.year + 5),
    );
    if (!mounted || picked == null) return;
    setState(() {
      date = dateOnly(picked.toIso8601String());
      revision++;
      schedules = [];
      appointments = [];
      snapshots = [];
    });
    refresh();
  }

  String time(Json s) =>
      '${widget.api.config.instantLabel(s['mulaiPada'])} – ${widget.api.config.instantLabel(s['selesaiPada'])}';
  Widget schedule(Json s) => Section(
    title: label(object(s['poliklinik'])),
    subtitle: '${label(object(s['ruang']))} · ${dateOnly(s['tanggal'])}',
    child: Wrap(
      spacing: 12,
      children: [
        Text(time(s)),
        stateChip(s['aktif'] == true ? 'AKTIF' : 'NONAKTIF'),
      ],
    ),
  );
  Widget monitor(Json s) => Section(
    title: label(object(s['ruang'])),
    subtitle: '${label(object(s['poliklinik']))} · ${time(object(s['sesi']))}',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Menunggu: ${s['totalMenunggu'] ?? 0}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        if (rows(s['aktif']).isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('Belum ada nomor dipanggil.'),
          ),
        for (final t in rows(s['aktif']))
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              '${t['nomorAntrean']}',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: QueueBStyle.teal,
                fontWeight: FontWeight.bold,
              ),
            ),
            trailing: stateChip(t['status']),
          ),
        for (final t in rows(s['menunggu']))
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('${t['nomorAntrean']}'),
            subtitle: Text('${t['jenisAntrean']}'.replaceAll('_', ' ')),
            trailing: stateChip(t['status']),
          ),
      ],
    ),
  );
  @override
  void dispose() {
    revision++;
    updates.removeListener(refresh);
    if (widget.updates == null) updates.dispose();
    gate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final waiting = snapshots.fold<int>(
      0,
      (v, s) => v + ((s['totalMenunggu'] as num?)?.toInt() ?? 0),
    );
    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: gate.refresh,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1000),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          [
                            'Beranda Dokter',
                            'Jadwal Saya',
                            'Janji Temu Saya',
                            'Monitoring Antrean',
                          ][tab],
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Portal baca dokter · Operasional antrean oleh PETUGAS',
                          style: TextStyle(color: QueueBStyle.muted),
                        ),
                        Wrap(
                          spacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            OutlinedButton.icon(
                              onPressed: pickDate,
                              icon: const Icon(Icons.calendar_month_outlined),
                              label: Text('Tanggal: $date'),
                            ),
                            IconButton(
                              tooltip: 'Muat ulang portal',
                              onPressed: loading ? null : refresh,
                              icon: const Icon(Icons.refresh),
                            ),
                          ],
                        ),
                        Text(
                          'Zona pelayanan: ${widget.api.config.serviceTimeZone}',
                        ),
                        ValueListenableBuilder(
                          valueListenable: updates.status,
                          builder: (context, value, _) => Text(
                            value,
                            style: const TextStyle(color: QueueBStyle.muted),
                          ),
                        ),
                        if (loading) const LinearProgressIndicator(),
                        if (error != null) MobileNotice(error!, error: true),
                        if (!loading && error == null) ...[
                          if (tab == 0) ...[
                            Section(
                              title: '${profile['nama'] ?? ''}',
                              subtitle:
                                  '${profile['kode'] ?? ''} · ${profile['spesialisasi'] ?? 'Dokter'}',
                              child: Text(
                                rows(profile['poliklinik'])
                                    .map(label)
                                    .join(' · '),
                              ),
                            ),
                            Wrap(
                              spacing: 12,
                              runSpacing: 8,
                              children: [
                                Chip(
                                  label: Text(
                                    'Appointment: ${appointments.length}',
                                  ),
                                ),
                                Chip(label: Text('Menunggu: $waiting')),
                              ],
                            ),
                            const Text('Jadwal praktik pada tanggal pilihan'),
                            ...schedules.map(schedule),
                            ...snapshots.map(monitor),
                          ],
                          if (tab == 1) ...schedules.map(schedule),
                          if (tab == 2)
                            for (final a in appointments)
                              Section(
                                title: '${a['nomorAntrean']}',
                                subtitle:
                                    '${label(object(a['poliklinik']))} · ${label(object(a['ruang']))}',
                                child: Wrap(
                                  spacing: 12,
                                  runSpacing: 8,
                                  children: [
                                    Text(time(a)),
                                    stateChip(a['status']),
                                  ],
                                ),
                              ),
                          if (tab == 3) ...snapshots.map(monitor),
                          if ((tab == 0 || tab == 1) && schedules.isEmpty)
                            const EmptyState(
                              icon: Icons.calendar_month_outlined,
                              text: 'Tidak ada jadwal untuk tanggal pilihan.',
                            ),
                          if (tab == 2 && appointments.isEmpty)
                            const EmptyState(
                              icon: Icons.event_available_outlined,
                              text: 'Appointment Anda akan muncul pada tanggal pilihan.',
                            ),
                          if (tab == 3 && snapshots.isEmpty)
                            const EmptyState(
                              icon: Icons.monitor_heart_outlined,
                              text: 'Monitoring tersedia selama sesi praktik Anda berlangsung pada hari pelayanan.',
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        NavigationBar(
          selectedIndex: tab,
          labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
          onDestinationSelected: (i) => setState(() => tab = i),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              label: 'Beranda',
            ),
            NavigationDestination(
              icon: Icon(Icons.calendar_month_outlined),
              label: 'Jadwal Saya',
            ),
            NavigationDestination(
              icon: Icon(Icons.event_available_outlined),
              label: 'Janji Temu Saya',
            ),
            NavigationDestination(
              icon: Icon(Icons.monitor_heart_outlined),
              label: 'Monitoring',
            ),
          ],
        ),
      ],
    );
  }
}
