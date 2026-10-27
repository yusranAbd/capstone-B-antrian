import 'package:flutter/material.dart';

import 'config.dart';
import 'doctor_professional.dart';
import 'mobile_ui.dart';
import 'patient_design.dart';
import 'patient_ui.dart';

/// Read model only. Ticket identity/status stays authoritative; no booking state.
class PatientReservation {
  const PatientReservation(this.ticket, this.appointment, this.doctor);
  final Json ticket, doctor;
  final Json? appointment;
  Json get slot => object(appointment?['slotPraktik']);
  Json get session => object(slot['jadwalPraktik']);
  Json get clinic => object(ticket['layanan']).isNotEmpty
      ? object(ticket['layanan'])
      : object(object(session['dokterLayanan'])['layanan']);
  String get id => '${ticket['id']}';
  String get status => '${ticket['status'] ?? 'TIDAK_DIKETAHUI'}';
  String get day =>
      dateOnly(ticket['tanggalPelayanan'] ?? ticket['tanggalAntrean']);
  String get number =>
      '${ticket['nomorAntrean'] ?? appointment?['nomorAntrean'] ?? '—'}';
  bool get canCancel => appointment?['id'] != null && status == 'DIPESAN';
  bool get terminal => ['SELESAI', 'DIBATALKAN'].contains(status);
  String get title =>
      appointment == null ? 'Antrean harian / Walk-in' : label(doctor);
  String get searchText =>
      '$title ${doctor['spesialisasi'] ?? ''} ${label(clinic)} $number $day ${patientDate(day)}'
          .toLowerCase();
}

List<PatientReservation> patientReservations(
  List<Json> tickets,
  List<Json> appointments,
  List<Json> doctors,
  String today,
) {
  final byTicket = <String, Json>{
    for (final a in appointments)
      if (object(a['tiket'])['id'] != null) '${object(a['tiket'])['id']}': a,
  };
  final owned = <String, Json>{
    for (final a in appointments)
      if (object(a['tiket'])['id'] != null)
        '${object(a['tiket'])['id']}': {
          ...object(a['tiket']),
          if (a['tanggalPelayanan'] != null)
            'tanggalPelayanan': a['tanggalPelayanan'],
          if (a['nomorAntrean'] != null) 'nomorAntrean': a['nomorAntrean'],
        },
    // A fresh owned-ticket response wins over nested appointment status.
    for (final t in tickets)
      if (t['id'] != null) '${t['id']}': t,
  };
  final result = owned.entries.map((entry) {
    final a = byTicket[entry.key];
    final historical = object(
      object(
        object(object(a?['slotPraktik'])['jadwalPraktik'])['dokterLayanan'],
      )['dokter'],
    );
    final current = doctors
        .where((d) => d['id'] == historical['id'])
        .firstOrNull;
    return PatientReservation(entry.value, a, {
      ...?current,
      ...historical,
      if (historical['fotoProfil'] == null && current?['fotoProfil'] != null)
        'fotoProfil': current!['fotoProfil'],
    });
  }).toList();
  bool upcoming(PatientReservation r) =>
      !r.terminal && r.day.compareTo(today) >= 0;
  result.sort((a, b) {
    if (upcoming(a) != upcoming(b)) return upcoming(a) ? -1 : 1;
    final day = a.day.compareTo(b.day);
    if (day != 0) return upcoming(a) ? day : -day;
    final time = '${a.slot['mulaiPada'] ?? ''}'.compareTo(
      '${b.slot['mulaiPada'] ?? ''}',
    );
    if (time != 0) return upcoming(a) ? time : -time;
    return a.id.compareTo(b.id);
  });
  return result;
}

String reservationStatus(String value) => switch (value) {
  'DIPESAN' => 'Dipesan',
  'CHECK_IN' => 'Check-in',
  'MENUNGGU' => 'Menunggu',
  'DIPANGGIL' => 'Dipanggil',
  'DILAYANI' => 'Dilayani',
  'DILEWATI' => 'Dilewati',
  'SELESAI' => 'Selesai',
  'DIBATALKAN' => 'Dibatalkan',
  _ => value,
};

class ReservationStatus extends StatelessWidget {
  const ReservationStatus(this.value, {super.key});
  final String value;
  @override
  Widget build(BuildContext context) {
    final color = PatientDesign.statusInk(value);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: PatientDesign.statusSurface(value),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(PatientDesign.statusIcon(value), size: 13, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              reservationStatus(value),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ReservationCard extends StatelessWidget {
  const ReservationCard({
    super.key,
    required this.item,
    required this.config,
    required this.busy,
    required this.onTicket,
    required this.onCancel,
  });
  final PatientReservation item;
  final AppConfig config;
  final bool busy;
  final VoidCallback onTicket, onCancel;
  @override
  Widget build(BuildContext context) => Container(
    key: ValueKey('reservation-${item.id}'),
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: PatientDesign.paper,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: PatientDesign.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (item.appointment != null)
              ProfessionalDoctorAvatar(
                config: config,
                photo: item.doctor['fotoProfil'],
                radius: 20,
              )
            else
              const CircleAvatar(
                radius: 20,
                backgroundColor: PatientDesign.mint,
                child: Icon(
                  Icons.local_hospital_outlined,
                  color: PatientDesign.darkTeal,
                ),
              ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: PatientDesign.navy,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [
                      if (item.doctor['spesialisasi'] != null)
                        '${item.doctor['spesialisasi']}',
                      label(item.clinic),
                    ].join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: PatientDesign.muted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            ReservationStatus(item.status),
          ],
        ),
        const Divider(height: 24),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 2),
          decoration: BoxDecoration(
            color: PatientDesign.paper,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              _fact(Icons.calendar_today_outlined, patientDate(item.day)),
              if (item.slot['mulaiPada'] != null)
                _fact(
                  Icons.schedule_outlined,
                  '${patientTime(item.slot, config)} · ${config.serviceTimeZone}',
                ),
              _fact(Icons.confirmation_number_outlined, item.number),
            ],
          ),
        ),
        if (item.appointment == null) ...[
          const SizedBox(height: 6),
          const Text(
            'Tanpa slot konsultasi khusus.',
            style: TextStyle(fontSize: 11, color: PatientDesign.muted),
          ),
        ],
        // Future API versions may have an independent appointment state. Never
        // replace ticket operational state with it.
        if (item.appointment?['status'] != null)
          Text(
            'Status janji temu: ${item.appointment!['status']}',
            style: const TextStyle(fontSize: 11),
          ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, box) {
            final actions = [
              FilledButton.icon(
                onPressed: busy ? null : onTicket,
                icon: Icon(
                  item.terminal
                      ? Icons.description_outlined
                      : Icons.qr_code_rounded,
                  size: 18,
                ),
                label: Text(item.terminal ? 'Lihat Detail' : 'Buka Tiket'),
              ),
              if (item.canCancel)
                OutlinedButton.icon(
                  onPressed: busy ? null : onCancel,
                  icon: const Icon(Icons.cancel_outlined, size: 17),
                  label: const Text('Batalkan Reservasi'),
                ),
            ];
            return (box.maxWidth < 290 ||
                        MediaQuery.textScalerOf(context).scale(13) > 17) &&
                    item.canCancel
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      actions.first,
                      const SizedBox(height: 6),
                      actions.last,
                    ],
                  )
                : Row(
                    children: [
                      Expanded(child: actions.first),
                      if (actions.length == 2) ...[
                        const SizedBox(width: 8),
                        Expanded(child: actions.last),
                      ],
                    ],
                  );
          },
        ),
      ],
    ),
  );
  Widget _fact(IconData icon, String text) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 16, color: PatientDesign.muted),
      const SizedBox(width: 6),
      Flexible(
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: PatientDesign.navy,
          ),
        ),
      ),
    ],
  );
}

class ReservationList extends StatefulWidget {
  const ReservationList({
    super.key,
    required this.items,
    required this.config,
    required this.loading,
    required this.busy,
    required this.onCreate,
    required this.onRefresh,
    required this.onTicket,
    required this.onCancel,
    this.error,
    this.message,
  });
  final List<PatientReservation> items;
  final AppConfig config;
  final bool loading, busy;
  final String? error, message;
  final VoidCallback onCreate;
  final Future<void> Function() onRefresh;
  final ValueChanged<PatientReservation> onTicket, onCancel;
  @override
  State<ReservationList> createState() => _ReservationListState();
}

class _ReservationListState extends State<ReservationList> {
  final search = TextEditingController();
  final scroll = ScrollController();
  String filter = 'Semua';
  @override
  void dispose() {
    search.dispose();
    scroll.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ReservationList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((widget.error != null && widget.error != oldWidget.error) ||
        (widget.message != null && widget.message != oldWidget.message)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && scroll.hasClients) {
          scroll.animateTo(
            0,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = widget.items
        .where(
          (r) =>
              (filter == 'Semua' || reservationStatus(r.status) == filter) &&
              r.searchText.contains(search.text.trim().toLowerCase()),
        )
        .toList();
    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: ListView.builder(
        key: const PageStorageKey('reservation-list'),
        controller: scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        itemCount: 1 + (visible.isEmpty ? 1 : visible.length),
        itemBuilder: (context, index) {
          if (index > 0) {
            return visible.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 28),
                    child: Text(
                      widget.loading
                          ? 'Memuat reservasi…'
                          : widget.error != null && widget.items.isEmpty
                          ? 'Reservasi belum dapat dimuat.'
                          : 'Belum ada reservasi yang sesuai.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: PatientDesign.muted),
                    ),
                  )
                : ReservationCard(
                    item: visible[index - 1],
                    config: widget.config,
                    busy: widget.busy,
                    onTicket: () => widget.onTicket(visible[index - 1]),
                    onCancel: () => widget.onCancel(visible[index - 1]),
                  );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Reservasi Saya',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: PatientDesign.navy,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Muat ulang reservasi',
                    onPressed: widget.busy || widget.loading
                        ? null
                        : widget.onRefresh,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
              const Text(
                'Kelola dan lihat riwayat reservasi Anda',
                style: TextStyle(fontSize: 13, color: PatientDesign.muted),
              ),
              if (widget.error != null) ...[
                const SizedBox(height: 8),
                MobileNotice(widget.error!, error: true),
                TextButton(
                  onPressed: widget.busy || widget.loading
                      ? null
                      : widget.onRefresh,
                  child: const Text('Coba lagi'),
                ),
              ],
              if (widget.message != null) MobileNotice(widget.message!),
              if (widget.loading) const LinearProgressIndicator(),
              const SizedBox(height: 12),
              TextField(
                controller: search,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: 'Cari dokter, poliklinik, nomor, atau tanggal...',
                  hintStyle: TextStyle(fontSize: 12),
                  prefixIcon: Icon(Icons.search_rounded),
                ),
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final status in [
                      'Semua',
                      'Dipesan',
                      'Selesai',
                      'Dibatalkan',
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(status),
                          showCheckmark: false,
                          selected: filter == status,
                          onSelected: (_) => setState(() => filter = status),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
          );
        },
      ),
    );
  }
}

Future<String?> chooseReservationMethod(BuildContext context) =>
    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (context) => SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Buat Reservasi',
                    style: TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.w800,
                      color: PatientDesign.navy,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Tutup pilihan reservasi',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const Text(
              'Pilih cara membuat reservasi.',
              style: TextStyle(color: PatientDesign.muted),
            ),
            const SizedBox(height: 14),
            for (final choice in [
              (
                id: 'doctors',
                icon: Icons.person_outline,
                title: 'Cari Dokter',
                detail: 'Pilih dokter dan jadwal praktik.',
              ),
              (
                id: 'clinics',
                icon: Icons.local_hospital_outlined,
                title: 'Pilih Poliklinik',
                detail: 'Lihat layanan berdasarkan poliklinik.',
              ),
              (
                id: 'nearest',
                icon: Icons.calendar_month_outlined,
                title: 'Jadwal Terdekat',
                detail: 'Temukan slot konsultasi yang tersedia.',
              ),
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Material(
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: const BorderSide(color: PatientDesign.border),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    leading: CircleAvatar(
                      backgroundColor: PatientDesign.mint,
                      child: Icon(choice.icon, color: PatientDesign.darkTeal),
                    ),
                    title: Text(
                      choice.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    subtitle: Text(
                      choice.detail,
                      style: const TextStyle(
                        fontSize: 12,
                        color: PatientDesign.muted,
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right, size: 20),
                    onTap: () => Navigator.pop(context, choice.id),
                  ),
                ),
              ),
          ],
        ),
      ),
    );

/// Pure presentation for the existing booking workflow; callbacks own API reads.
class ReservationDoctorChoice extends StatelessWidget {
  const ReservationDoctorChoice({
    super.key,
    required this.doctor,
    required this.clinic,
    required this.config,
    required this.onSelect,
    required this.schedule,
    this.slot,
  });
  final Json doctor, clinic;
  final Json? schedule, slot;
  final AppConfig config;
  final VoidCallback? onSelect;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    margin: const EdgeInsets.only(bottom: 12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: PatientDesign.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            ProfessionalDoctorAvatar(
              config: config,
              photo: doctor['fotoProfil'],
              radius: 25,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label(doctor),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: PatientDesign.navy,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [
                      if (doctor['spesialisasi'] != null)
                        '${doctor['spesialisasi']}',
                      label(clinic),
                    ].join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: PatientDesign.muted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: PatientDesign.mint.withValues(alpha: .5),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.calendar_month_outlined,
                size: 20,
                color: PatientDesign.darkTeal,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  schedule == null
                      ? 'Belum ada jadwal praktik mendatang.'
                      : '${slot == null ? 'Jadwal terdekat' : 'Slot tersedia'}\n${patientDate('${schedule!['tanggal']}')} · ${patientTime(slot ?? schedule!, config)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: PatientDesign.navy,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        FilledButton(onPressed: onSelect, child: const Text('Pilih Jadwal')),
      ],
    ),
  );
}

class ReservationChoices extends StatefulWidget {
  const ReservationChoices({
    super.key,
    required this.choices,
    required this.config,
    required this.busy,
    required this.onSelect,
  });
  final List<Json> choices;
  final AppConfig config;
  final bool busy;
  final ValueChanged<Json> onSelect;
  @override
  State<ReservationChoices> createState() => _ReservationChoicesState();
}

class _ReservationChoicesState extends State<ReservationChoices> {
  int page = 0;
  @override
  Widget build(BuildContext context) {
    final max = widget.choices.isEmpty ? 0 : (widget.choices.length - 1) ~/ 10;
    if (page > max) page = max;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final c in widget.choices.skip(page * 10).take(10))
          ReservationDoctorChoice(
            doctor: object(c['doctor']),
            clinic: object(c['clinic']),
            config: widget.config,
            schedule: c['session'] == null ? null : object(c['session']),
            slot: c['slot'] == null ? null : object(c['slot']),
            onSelect: widget.busy || c['session'] == null
                ? null
                : () => widget.onSelect(c),
          ),
        if (max > 0)
          Row(
            children: [
              Expanded(
                child: Text(
                  'Halaman ${page + 1}/${max + 1}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: PatientDesign.muted,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Pilihan sebelumnya',
                onPressed: page > 0 ? () => setState(() => page--) : null,
                icon: const Icon(Icons.chevron_left),
              ),
              IconButton(
                tooltip: 'Pilihan berikutnya',
                onPressed: page < max ? () => setState(() => page++) : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
      ],
    );
  }
}
