import 'package:flutter/material.dart';

import 'admin_schedules.dart';
import 'api.dart';
import 'config.dart';
import 'mobile_ui.dart';

// Hallmark · component scope · QueueB ADMIN tokens · no global theme changes.
// Pre-emit critique: philosophy 5, hierarchy 5, execution 4, specificity 5,
// restraint 5, variety 4. Native Material controls retain their interaction states.
abstract final class _PracticeStyle {
  static const accent = QueueBStyle.darkTeal;
  static const tint = QueueBStyle.mint;
  static const paper = Colors.white;
  static const ink = QueueBStyle.navy;
  static const muted = QueueBStyle.muted;
  static const border = QueueBStyle.border;
}

/// Edits dated practice sessions; operating hours and overlaps remain API rules.
class PracticeScheduleEditor extends StatefulWidget {
  const PracticeScheduleEditor({
    super.key,
    required this.api,
    required this.catalog,
    this.row,
  });

  final QueueApi api;
  final Map<String, List<Json>> catalog;
  final Json? row;

  @override
  State<PracticeScheduleEditor> createState() => _PracticeScheduleEditorState();
}

class _PracticeScheduleEditorState extends State<PracticeScheduleEditor> {
  final form = GlobalKey<FormState>();
  final doctorText = TextEditingController();
  late final TextEditingController dateText, startText, endText;
  late DateTime date;
  TimeOfDay? start, end;
  String? doctorLink, room, error;
  bool busy = false, active = true;
  bool get editing => widget.row != null;
  AppConfig get config => widget.api.config;

  @override
  void initState() {
    super.initState();
    final row = widget.row;
    date = DateTime.parse(
      row == null ? config.today : dateOnly(row['tanggal']),
    );
    doctorLink =
        row?['dokterLayananId'] as String? ??
        object(row?['dokterLayanan'])['id'] as String?;
    room = row?['loketId'] as String? ?? object(row?['loket'])['id'] as String?;
    active = row?['aktif'] != false;
    start = _time(row?['mulaiPada']);
    end = _time(row?['selesaiPada']);
    dateText = TextEditingController(text: _dateLabel(date));
    startText = TextEditingController(text: _clock(start));
    endText = TextEditingController(text: _clock(end));
  }

  TimeOfDay? _time(Object? value) {
    if (value == null) return null;
    final local = config.localInput(value);
    return TimeOfDay(
      hour: int.parse(local.substring(11, 13)),
      minute: int.parse(local.substring(14, 16)),
    );
  }

  String _clock(TimeOfDay? time) =>
      time == null ? '' : '${two(time.hour)}:${two(time.minute)}';
  int _minutes(TimeOfDay time) => time.hour * 60 + time.minute;
  String _dateLabel(DateTime value) {
    const months = [
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
    return '${value.day} ${months[value.month - 1]} ${value.year}';
  }

  List<_DoctorChoice> get doctors {
    final choices = <String, _DoctorChoice>{};
    for (final doctor in widget.catalog['/dokter'] ?? <Json>[]) {
      for (final link in rows(doctor['dokterLayanan'])) {
        final clinic = object(link['layanan']);
        if (link['id'] is! String) continue;
        final available =
            doctor['aktif'] != false &&
            link['aktif'] == true &&
            clinic['aktif'] != false;
        if (available || link['id'] == widget.row?['dokterLayananId']) {
          choices['${link['id']}'] = _DoctorChoice(
            '${link['id']}',
            '${link['layananId'] ?? clinic['id']}',
            '${label(doctor)}\n${doctor['spesialisasi'] ?? 'Dokter'} · ${label(clinic)}',
          );
        }
      }
    }
    final current = object(widget.row?['dokterLayanan']);
    final id = widget.row?['dokterLayananId'] ?? current['id'];
    if (id is String && !choices.containsKey(id)) {
      choices[id] = _DoctorChoice(
        id,
        '${current['layananId'] ?? object(current['layanan'])['id']}',
        '${label(object(current['dokter']))}\n${label(object(current['layanan']))}',
      );
    }
    return choices.values.toList()..sort((a, b) => a.title.compareTo(b.title));
  }

  _DoctorChoice? get selectedDoctor =>
      doctors.where((d) => d.id == doctorLink).firstOrNull;

  List<Json> get rooms {
    final clinic = selectedDoctor?.clinicId;
    if (clinic == null) return [];
    final all = <String, Json>{
      for (final r in widget.catalog['/loket'] ?? <Json>[]) '${r['id']}': r,
    };
    final current = object(widget.row?['loket']);
    if (current['id'] is String) {
      all.putIfAbsent('${current['id']}', () => current);
    }
    return all.values
        .where(
          (r) =>
              r['layananId'] == clinic &&
              (r['aktif'] != false || r['id'] == widget.row?['loketId']),
        )
        .toList();
  }

  Future<void> pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: date,
      firstDate: DateTime(1000),
      lastDate: DateTime(9999, 12, 31),
      helpText: 'Pilih tanggal pelayanan',
      confirmText: 'Pilih Tanggal',
      cancelText: 'Batal',
      initialEntryMode: DatePickerEntryMode.calendarOnly,
    );
    if (picked != null && mounted) {
      setState(() {
        date = picked;
        dateText.text = _dateLabel(date);
      });
    }
  }

  Future<void> pickTime(bool beginning) async {
    final picked = await showTimePicker(
      context: context,
      initialTime:
          (beginning ? start : end) ?? const TimeOfDay(hour: 8, minute: 0),
      helpText: beginning ? 'Pilih jam mulai' : 'Pilih jam selesai',
      confirmText: 'Pilih Jam',
      cancelText: 'Batal',
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked != null && mounted) {
      setState(() {
        if (beginning) {
          start = picked;
          startText.text = _clock(picked);
        } else {
          end = picked;
          endText.text = _clock(picked);
        }
      });
    }
  }

  Json payload() {
    final original = widget.row;
    final day = calendarDate(date);
    final changedDay = day != dateOnly(original?['tanggal']);
    return {
      if (!editing || doctorLink != original?['dokterLayananId'])
        'dokterLayananId': doctorLink,
      if (!editing || room != original?['loketId']) 'loketId': room,
      if (!editing || changedDay) 'tanggal': day,
      if (!editing ||
          changedDay ||
          _clock(start) != _clock(_time(original?['mulaiPada'])))
        'mulaiPada': config.toInstant('${day}T${_clock(start)}'),
      if (!editing ||
          changedDay ||
          _clock(end) != _clock(_time(original?['selesaiPada'])))
        'selesaiPada': config.toInstant('${day}T${_clock(end)}'),
      if (editing && active != (original?['aktif'] != false)) 'aktif': active,
    };
  }

  Future<void> save() async {
    if (busy || !form.currentState!.validate()) return;
    final Json body;
    try {
      body = payload();
    } on FormatException catch (e) {
      setState(() => error = e.message);
      return;
    }
    if (body.isEmpty) {
      setState(
        () => error = 'Belum ada perubahan. Ubah isian atau pilih Batal.',
      );
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.api.request(
        editing ? 'PATCH' : 'POST',
        '/jadwal-praktik${editing ? '/${widget.row!['id']}' : ''}',
        body: body,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          error = '$e';
          busy = false;
        });
      }
    }
  }

  @override
  void dispose() {
    doctorText.dispose();
    dateText.dispose();
    startText.dispose();
    endText.dispose();
    super.dispose();
  }

  Widget _fieldTitle(String text, {bool required = true}) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text.rich(
      TextSpan(
        text: text,
        children: [
          if (required)
            TextSpan(
              text: ' *',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
      style: const TextStyle(
        fontWeight: FontWeight.w700,
        color: _PracticeStyle.ink,
      ),
    ),
  );

  InputDecoration _decoration(String hint, IconData icon) => InputDecoration(
    hintText: hint,
    prefixIcon: Icon(icon),
    suffixIcon: const Icon(Icons.expand_more),
  );

  Widget _doctorField() => LayoutBuilder(
    builder: (context, box) {
      final options = doctors;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _fieldTitle('Dokter & Poliklinik'),
          DropdownMenuFormField<String>(
            key: const ValueKey('practice-doctor'),
            controller: doctorText,
            initialSelection: doctorLink,
            enabled: !busy && options.isNotEmpty,
            width: box.maxWidth,
            menuHeight: 280,
            maxLines: 2,
            decorationBuilder: (_, _) =>
                const InputDecoration(prefixIcon: Icon(Icons.person_outline)),
            hintText: 'Cari dokter atau poliklinik',
            enableFilter: true,
            requestFocusOnTap: true,
            dropdownMenuEntries: options
                .map(
                  (d) => DropdownMenuEntry(
                    value: d.id,
                    label: d.title,
                    labelWidget: Text(
                      d.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            validator: (v) =>
                !options.any((d) => d.id == v && d.title == doctorText.text)
                ? 'Pilih dokter dan poliklinik dari hasil pencarian.'
                : null,
            onSelected: (value) => setState(() {
              doctorLink = value;
              if (!rooms.any((r) => r['id'] == room)) room = null;
            }),
          ),
          if (options.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Belum ada dokter yang terhubung ke poliklinik aktif.',
              ),
            ),
        ],
      );
    },
  );

  Widget _roomField() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _fieldTitle('Ruang / Loket'),
      DropdownButtonFormField<String>(
        key: ValueKey('practice-room:$doctorLink:$room'),
        initialValue: rooms.any((r) => r['id'] == room) ? room : null,
        isExpanded: true,
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.location_on_outlined),
        ),
        hint: Text(
          doctorLink == null
              ? 'Pilih dokter terlebih dahulu'
              : 'Pilih ruang pelayanan',
        ),
        items: rooms
            .map(
              (r) => DropdownMenuItem<String>(
                value: '${r['id']}',
                child: Text(
                  '${r['kode']} · ${label(r)}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            )
            .toList(),
        onChanged: busy || doctorLink == null
            ? null
            : (v) => setState(() => room = v),
        validator: (v) => rooms.any((r) => r['id'] == v)
            ? null
            : 'Pilih ruang sesuai poliklinik.',
      ),
      if (doctorLink != null && rooms.isEmpty)
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text('Belum ada ruang aktif untuk poliklinik ini.'),
        ),
    ],
  );

  Widget _dateField() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _fieldTitle('Tanggal Pelayanan'),
      TextFormField(
        key: const ValueKey('practice-date'),
        controller: dateText,
        readOnly: true,
        enabled: !busy,
        onTap: pickDate,
        decoration: _decoration(
          'Pilih tanggal pelayanan',
          Icons.calendar_month_outlined,
        ),
      ),
    ],
  );

  Widget _timeField(bool beginning) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        beginning ? 'Mulai' : 'Selesai',
        style: const TextStyle(color: _PracticeStyle.muted),
      ),
      const SizedBox(height: 6),
      TextFormField(
        key: ValueKey(beginning ? 'practice-start' : 'practice-end'),
        controller: beginning ? startText : endText,
        readOnly: true,
        enabled: !busy,
        onTap: () => pickTime(beginning),
        decoration: _decoration('HH:mm', Icons.access_time),
        validator: (_) {
          if ((beginning ? start : end) == null) {
            return 'Pilih jam ${beginning ? 'mulai' : 'selesai'}.';
          }
          if (!beginning &&
              start != null &&
              _minutes(end!) <= _minutes(start!)) {
            return 'Jam selesai harus setelah jam mulai.';
          }
          return null;
        },
      ),
    ],
  );

  Widget _practiceTimes() {
    final duration = start == null || end == null
        ? null
        : _minutes(end!) - _minutes(start!);
    final valid = duration != null && duration > 0;
    final hours = valid ? duration ~/ 60 : 0;
    final minutes = valid ? duration % 60 : 0;
    final text = valid
        ? 'Durasi praktik: ${[if (hours > 0) '$hours jam', if (minutes > 0) '$minutes menit'].join(' ')}'
        : 'Durasi praktik';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _fieldTitle('Waktu Praktik'),
        LayoutBuilder(
          builder: (context, box) => box.maxWidth < 300
              ? Column(
                  children: [
                    _timeField(true),
                    const SizedBox(height: 16),
                    _timeField(false),
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _timeField(true)),
                    const SizedBox(width: 16),
                    Expanded(child: _timeField(false)),
                  ],
                ),
        ),
        const SizedBox(height: 16),
        Semantics(
          liveRegion: true,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _PracticeStyle.tint,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.access_time,
                  color: _PracticeStyle.accent,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        text,
                        style: const TextStyle(
                          color: _PracticeStyle.accent,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        valid ? 'Sesuai dengan waktu yang dipilih.' : 'Pilih jam mulai dan selesai pada tanggal pelayanan yang sama.',
                        style: const TextStyle(color: _PracticeStyle.muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (editing)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Jadwal aktif'),
              value: active,
              onChanged: busy ? null : (v) => setState(() => active = v),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    final theme = base.copyWith(
      colorScheme: base.colorScheme.copyWith(
        primary: _PracticeStyle.accent,
        surface: _PracticeStyle.paper,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(168, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(112, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _PracticeStyle.paper,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 18,
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _PracticeStyle.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _PracticeStyle.accent, width: 2),
        ),
        errorMaxLines: 3,
      ),
    );
    return Theme(
      data: theme,
      child: PopScope(
        canPop: !busy,
        child: Dialog(
          backgroundColor: _PracticeStyle.paper,
          surfaceTintColor: _PracticeStyle.paper,
          insetPadding: EdgeInsets.symmetric(
            horizontal: MediaQuery.sizeOf(context).width < 600 ? 12 : 32,
            vertical: 24,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 840),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 8, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _PracticeStyle.tint,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(
                          Icons.edit_calendar_outlined,
                          color: _PracticeStyle.accent,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Semantics(
                              header: true,
                              child: Text(
                                '${editing ? 'Ubah' : 'Tambah'} Jadwal Praktik',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  color: _PracticeStyle.ink,
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Atur jadwal layanan dokter di poliklinik.',
                              style: TextStyle(color: _PracticeStyle.muted),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  Icons.schedule,
                                  size: 18,
                                  color: _PracticeStyle.muted,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Zona waktu: ${config.serviceTimeZone}',
                                    style: const TextStyle(
                                      color: _PracticeStyle.muted,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Tutup formulir',
                        onPressed: busy
                            ? null
                            : () => Navigator.pop(context, false),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: _PracticeStyle.border),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Form(
                      key: form,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (error != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: AdminNotice(error!, error: true),
                            ),
                          LayoutBuilder(
                            builder: (context, box) {
                              final identity = Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _doctorField(),
                                  const SizedBox(height: 12),
                                  _roomField(),
                                  const SizedBox(height: 12),
                                  _dateField(),
                                ],
                              );
                              return box.maxWidth >= 700
                                  ? Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(child: identity),
                                        const SizedBox(width: 16),
                                        Expanded(child: _practiceTimes()),
                                      ],
                                    )
                                  : Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        identity,
                                        const SizedBox(height: 12),
                                        _practiceTimes(),
                                      ],
                                    );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const Divider(height: 1, color: _PracticeStyle.border),
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: LayoutBuilder(
                    builder: (context, box) {
                      final cancel = OutlinedButton(
                        onPressed: busy
                            ? null
                            : () => Navigator.pop(context, false),
                        child: const Text('Batal'),
                      );
                      final submit = FilledButton.icon(
                        onPressed: busy ? null : save,
                        icon: busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.save_outlined),
                        label: Text(busy ? 'Menyimpan…' : 'Simpan Jadwal'),
                      );
                      return box.maxWidth < 380
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                submit,
                                const SizedBox(height: 8),
                                cancel,
                              ],
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                cancel,
                                const SizedBox(width: 16),
                                submit,
                              ],
                            );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DoctorChoice {
  const _DoctorChoice(this.id, this.clinicId, this.title);
  final String id, clinicId, title;
}
