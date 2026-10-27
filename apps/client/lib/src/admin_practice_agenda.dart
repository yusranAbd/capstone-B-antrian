import 'package:flutter/material.dart';

import 'config.dart';
import 'mobile_ui.dart';

/// Read-only presentation of the loaded schedule array; mutations stay with ADMIN.
class AdminPracticeAgenda extends StatefulWidget {
  const AdminPracticeAgenda({
    super.key,
    required this.rows,
    required this.config,
    required this.clinicName,
    required this.actions,
    required this.busy,
  });
  final List<Json> rows;
  final AppConfig config;
  final String Function(Json) clinicName;
  final Widget Function(Json) actions;
  final bool busy;
  @override
  State<AdminPracticeAgenda> createState() => _AdminPracticeAgendaState();
}

class _AdminPracticeAgendaState extends State<AdminPracticeAgenda> {
  String? selected;
  bool initialized = false, allDates = false;
  int page = 0;
  static const pageSize = 6;
  List<String> get dates =>
      widget.rows
          .map((r) => dateOnly(r['tanggal']))
          .where((d) => DateTime.tryParse(d) != null)
          .toSet()
          .toList()
        ..sort();
  @override
  void initState() {
    super.initState();
    chooseInitial();
  }

  @override
  void didUpdateWidget(covariant AdminPracticeAgenda oldWidget) {
    super.didUpdateWidget(oldWidget);
    chooseInitial();
    if (oldWidget.rows.length != widget.rows.length ||
        oldWidget.rows.map((r) => '${r['id']}').join() !=
            widget.rows.map((r) => '${r['id']}').join()) {
      page = 0;
    }
  }

  void chooseInitial() {
    if (initialized || dates.isEmpty) return;
    final days = dates, today = widget.config.today;
    selected = days.contains(today)
        ? today
        : days.where((d) => d.compareTo(today) > 0).firstOrNull ?? days.last;
    initialized = true;
  }

  void select(String day) => setState(() {
    selected = day;
    allDates = false;
    page = 0;
  });
  String dateLabel(BuildContext c, String value) {
    final parsed = DateTime.tryParse(value);
    return parsed == null
        ? value
        : MaterialLocalizations.of(c).formatFullDate(parsed);
  }

  Future<void> pickDate() async {
    final initial = DateTime.parse(selected ?? widget.config.today);
    final days = dates, today = DateTime.parse(widget.config.today);
    final first = days.isEmpty ? today : DateTime.parse(days.first);
    final last = days.isEmpty ? today : DateTime.parse(days.last);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: (first.isBefore(initial) ? first : initial).subtract(
        const Duration(days: 365),
      ),
      lastDate: (last.isAfter(initial) ? last : initial).add(
        const Duration(days: 365),
      ),
      helpText: 'Tanggal agenda praktik',
    );
    if (mounted && picked != null) select(calendarDate(picked));
  }

  @override
  Widget build(BuildContext context) {
    final days = dates, day = selected ?? widget.config.today;
    final previous = days.where((d) => d.compareTo(day) < 0).lastOrNull;
    final next = days.where((d) => d.compareTo(day) > 0).firstOrNull;
    final visible =
        widget.rows
            .where((r) => allDates || dateOnly(r['tanggal']) == day)
            .toList()
          ..sort((a, b) {
            final date = dateOnly(a['tanggal'])
                .compareTo(dateOnly(b['tanggal']));
            if (date != 0) return date;
            final time = '${a['mulaiPada']}'.compareTo('${b['mulaiPada']}');
            return time != 0 ? time : '${a['id']}'.compareTo('${b['id']}');
          });
    final maxPage = visible.isEmpty ? 0 : (visible.length - 1) ~/ pageSize;
    final current = page.clamp(0, maxPage), start = current * pageSize;
    final groups = <String, List<Json>>{};
    for (final row in visible.skip(start).take(pageSize)) {
      final key =
          '${dateOnly(row['tanggal'])}:${object(row['loket'])['id'] ?? row['loketId'] ?? object(row['loket'])['kode'] ?? object(row['loket'])['nama'] ?? row['id']}';
      groups.putIfAbsent(key, () => []).add(row);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: QueueBStyle.border),
            borderRadius: BorderRadius.circular(14),
          ),
          child: LayoutBuilder(
            builder: (context, box) => Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                IconButton(
                  tooltip: 'Tanggal sebelumnya',
                  onPressed: widget.busy || previous == null
                      ? null
                      : () => select(previous),
                  icon: const Icon(Icons.chevron_left),
                ),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: box.maxWidth < 450 ? box.maxWidth - 120 : 330,
                  ),
                  child: TextButton.icon(
                    onPressed: widget.busy ? null : pickDate,
                    icon: const Icon(Icons.calendar_month_outlined, size: 20),
                    label: Text(
                      allDates ? 'Semua tanggal' : dateLabel(context, day),
                      maxLines: 2,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Tanggal berikutnya',
                  onPressed: widget.busy || next == null
                      ? null
                      : () => select(next),
                  icon: const Icon(Icons.chevron_right),
                ),
                FilterChip(
                  label: const Text('Semua tanggal'),
                  selected: allDates,
                  onSelected: widget.busy
                      ? null
                      : (v) => setState(() {
                          allDates = v;
                          page = 0;
                        }),
                ),
                if (day != widget.config.today || allDates)
                  TextButton(
                    onPressed: widget.busy
                        ? null
                        : () => select(widget.config.today),
                    child: const Text('Hari ini'),
                  ),
                Text(
                  '${visible.length} sesi · ${widget.config.serviceTimeZone}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: QueueBStyle.muted,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        if (visible.isEmpty && !widget.busy)
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: QueueBStyle.border),
            ),
            child: const Text(
              'Tidak ada jadwal pada tanggal dan filter ini. Pilih tanggal lain atau Semua tanggal.',
              style: TextStyle(color: QueueBStyle.muted),
            ),
          ),
        for (final entry in groups.entries) ...[
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: QueueBStyle.border),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: const BoxDecoration(
                    color: QueueBStyle.mint,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(13),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.meeting_room_outlined,
                        size: 18,
                        color: QueueBStyle.darkTeal,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${object(entry.value.first['loket'])['kode'] ?? ''} · ${label(object(entry.value.first['loket']))}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (allDates)
                        Flexible(
                          child: Text(
                            dateLabel(
                              context,
                              dateOnly(entry.value.first['tanggal']),
                            ),
                            style: const TextStyle(
                              fontSize: 12,
                              color: QueueBStyle.muted,
                            ),
                            textAlign: TextAlign.end,
                          ),
                        ),
                    ],
                  ),
                ),
                LayoutBuilder(
                  builder: (context, box) {
                    final columns =
                        box.maxWidth >= 900 &&
                            MediaQuery.textScalerOf(context).scale(13) <= 20
                        ? 2
                        : 1;
                    return Wrap(
                      children: [
                        for (var i = 0; i < entry.value.length; i++)
                          SizedBox(
                            width: box.maxWidth / columns,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                border: Border(
                                  top: const BorderSide(
                                    color: QueueBStyle.border,
                                    width: .5,
                                  ),
                                  right: BorderSide(
                                    color: columns == 2 && i.isEven
                                        ? QueueBStyle.border
                                        : Colors.transparent,
                                    width: .5,
                                  ),
                                ),
                              ),
                              child: _row(entry.value[i]),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (visible.isNotEmpty)
          Wrap(
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              Text(
                '${start + 1}–${(start + pageSize).clamp(0, visible.length)} dari ${visible.length} sesi',
                style: const TextStyle(fontSize: 12, color: QueueBStyle.muted),
              ),
              IconButton(
                tooltip: 'Halaman sebelumnya',
                onPressed: widget.busy || current == 0
                    ? null
                    : () => setState(() => page = current - 1),
                icon: const Icon(Icons.chevron_left),
              ),
              IconButton(
                tooltip: 'Halaman berikutnya',
                onPressed: widget.busy || current == maxPage
                    ? null
                    : () => setState(() => page = current + 1),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
      ],
    );
  }

  Widget _row(Json row) {
    final doctor = object(object(row['dokterLayanan'])['dokter']);
    final start = clockOnly(widget.config.localInput(row['mulaiPada'])),
        end = clockOnly(widget.config.localInput(row['selesaiPada']));
    return Padding(
      key: ValueKey('practice-row:${row['id']}'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      child: LayoutBuilder(
        builder: (context, box) {
          final details = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label(doctor),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                widget.clinicName(row),
                style: const TextStyle(fontSize: 12, color: QueueBStyle.muted),
              ),
            ],
          );
          final time = Container(
            width: 72,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: QueueBStyle.background,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Column(
              children: [
                Text(
                  start,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: QueueBStyle.darkTeal,
                  ),
                ),
                Text(
                  end,
                  style: const TextStyle(
                    fontSize: 12,
                    color: QueueBStyle.muted,
                  ),
                ),
              ],
            ),
          );
          final state = Text(
            row['aktif'] == true ? 'Aktif' : 'Nonaktif',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: row['aktif'] == true
                  ? QueueBStyle.success
                  : QueueBStyle.muted,
            ),
          );
          return box.maxWidth >= 430 &&
                  MediaQuery.textScalerOf(context).scale(13) <= 20
              ? Row(
                  children: [
                    time,
                    const SizedBox(width: 12),
                    Expanded(child: details),
                    const SizedBox(width: 12),
                    state,
                    const SizedBox(width: 16),
                    widget.actions(row),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        time,
                        const SizedBox(width: 10),
                        Expanded(child: details),
                      ],
                    ),
                    Wrap(
                      alignment: WrapAlignment.end,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      children: [state, widget.actions(row)],
                    ),
                  ],
                );
        },
      ),
    );
  }
}
