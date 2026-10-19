import 'package:flutter/material.dart';

import 'api.dart';
import 'config.dart';
import 'doctor_dashboard.dart';
import 'patient_sync.dart';

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
  int revision = 0;
  String? loadedDate;
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
          loadedDate = selected;
        });
      }
    } catch (e) {
      if (mounted && current == revision && selected == date) {
        setState(() {
          error = '$e';
          loadedDate = null;
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
      loadedDate = null;
      revision++;
      schedules = [];
      appointments = [];
      snapshots = [];
    });
    refresh();
  }

  @override
  void dispose() {
    revision++;
    updates.removeListener(refresh);
    if (widget.updates == null) updates.dispose();
    gate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DoctorDashboard(
    config: widget.api.config,
    date: date,
    profile: profile,
    schedules: schedules,
    appointments: appointments,
    snapshots: snapshots,
    loading: loading,
    available: loadedDate == date && error == null,
    status: updates.status,
    error: error,
    onRefresh: gate.refresh,
    onPickDate: pickDate,
  );
}
