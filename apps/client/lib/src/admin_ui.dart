import 'package:flutter/material.dart';

import 'config.dart';
import 'mobile_ui.dart';

// Hallmark · ADMIN workbench · QueueB tokens · P5 H5 E4 S5 R5 V4.
abstract final class AdminStyle {
  static const canvas = Color(0xfff2f9fc);
  static const sky = Color(0xffe0f2ff);
  static const blue = Color(0xff087bd4);
  static const rule = Color(0xffe2edf3);
  static const shadow = Color(0x080c637d);
  static BoxDecoration get panel => BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(22),
    border: Border.all(color: rule),
    boxShadow: const [
      BoxShadow(color: shadow, blurRadius: 22, offset: Offset(0, 6)),
    ],
  );
  static ThemeData get theme => QueueBStyle.theme.copyWith(
    scaffoldBackgroundColor: canvas,
    cardTheme: const CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.symmetric(vertical: 6),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: QueueBStyle.navy,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    dataTableTheme: const DataTableThemeData(
      headingRowColor: WidgetStatePropertyAll(QueueBStyle.background),
      headingTextStyle: TextStyle(
        fontWeight: FontWeight.w700,
        color: QueueBStyle.navy,
        fontSize: 12,
      ),
      dataTextStyle: TextStyle(color: QueueBStyle.navy, fontSize: 13),
      horizontalMargin: 16,
      columnSpacing: 24,
      dividerThickness: .5,
    ),
    inputDecorationTheme: QueueBStyle.theme.inputDecorationTheme.copyWith(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    ),
  );
}

/// Session identity only; the existing profile and logout actions remain in app.dart.
class AdminIdentity extends StatelessWidget {
  const AdminIdentity({super.key, required this.name});
  final String name;
  @override
  Widget build(BuildContext context) {
    final displayName = name.trim().isEmpty ? 'Administrator' : name.trim();
    final initials = displayName
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .take(2)
        .map((s) => String.fromCharCode(s.runes.first).toUpperCase())
        .join();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            backgroundColor: AdminStyle.sky,
            foregroundColor: QueueBStyle.darkTeal,
            child: Text(
              initials,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 220,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: QueueBStyle.navy,
                    fontSize: 14,
                  ),
                ),
                const Text(
                  'Administrator',
                  style: TextStyle(color: QueueBStyle.muted, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AdminColumn {
  const AdminColumn(
    this.title,
    this.value, {
    this.cell,
    this.numeric = false,
    this.icon,
  });
  final String title;
  final Object? Function(Json) value;
  final Widget Function(Json)? cell;
  final bool numeric;
  final IconData? icon;
}

/// Client pagination for existing REST arrays. Only one page creates row widgets.
class AdminTable extends StatefulWidget {
  const AdminTable({
    super.key,
    required this.rows,
    required this.columns,
    this.title,
    this.pageSize = 10,
    this.compact = false,
    this.decorated = true,
  });
  final List<Json> rows;
  final List<AdminColumn> columns;
  final String? title;
  final int pageSize;
  final bool compact, decorated;
  @override
  State<AdminTable> createState() => _AdminTableState();
}

class _AdminTableState extends State<AdminTable> {
  late final _AdminTableSource source;
  int sort = 0, size = 10;
  bool ascending = true;
  int firstRow = 0, epoch = 0;
  @override
  void initState() {
    super.initState();
    size = widget.pageSize;
    source = _AdminTableSource(this);
    reorder();
  }

  @override
  void didUpdateWidget(covariant AdminTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (firstRow > 0 && firstRow >= widget.rows.length) {
      firstRow = 0;
      epoch++;
    }
    reorder();
  }

  void reorder() {
    final column = widget.columns[sort.clamp(0, widget.columns.length - 1)];
    source.rows = [...widget.rows]
      ..sort((a, b) {
        final av = column.value(a), bv = column.value(b);
        final result = av is num && bv is num
            ? av.compareTo(bv)
            : '$av'.toLowerCase().compareTo('$bv'.toLowerCase());
        final stable = result == 0
            ? '${a['id']}'.compareTo('${b['id']}')
            : result;
        return ascending ? stable : -stable;
      });
    source.refresh();
  }

  @override
  void dispose() {
    source.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => Container(
      decoration: !widget.decorated
          ? null
          : BoxDecoration(
              color: Colors.white,
              border: Border.all(color: QueueBStyle.border),
              borderRadius: BorderRadius.circular(16),
            ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: (widget.columns.length * 160.0)
              .clamp(box.maxWidth, double.infinity)
              .toDouble(),
          child: PaginatedDataTable(
            key: ValueKey(epoch),
            onPageChanged: (value) => firstRow = value,
            header: widget.title == null
                ? null
                : Text(
                    widget.title!,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
            showCheckboxColumn: false,
            showEmptyRows: false,
            dataRowMinHeight: widget.compact ? 52 : 58,
            dataRowMaxHeight: widget.compact ? 60 : 112,
            headingRowHeight: widget.compact ? 52 : 56,
            rowsPerPage: widget.rows.length.clamp(1, size),
            availableRowsPerPage: [
              if (widget.rows.length < 10) widget.rows.length.clamp(1, 10),
              10,
              20,
              50,
            ],
            onRowsPerPageChanged: (value) => setState(() => size = value ?? 10),
            sortColumnIndex: sort,
            sortAscending: ascending,
            columns: [
              for (var i = 0; i < widget.columns.length; i++)
                DataColumn(
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.columns[i].icon != null) ...[
                        Icon(
                          widget.columns[i].icon,
                          size: 18,
                          color: QueueBStyle.muted,
                        ),
                        const SizedBox(width: 8),
                      ],
                      Text(widget.columns[i].title),
                    ],
                  ),
                  numeric: widget.columns[i].numeric,
                  onSort: widget.columns[i].title == 'Aksi'
                      ? null
                      : (index, order) => setState(() {
                          sort = index;
                          ascending = order;
                          reorder();
                        }),
                ),
            ],
            source: source,
          ),
        ),
      ),
    ),
  );
}

class _AdminTableSource extends DataTableSource {
  _AdminTableSource(this.owner);
  final _AdminTableState owner;
  List<Json> rows = [];
  int? hoveredRow;
  void hover(int? index) {
    if (hoveredRow == index) return;
    hoveredRow = index;
    notifyListeners();
  }

  void refresh() => notifyListeners();
  @override
  DataRow? getRow(int index) {
    if (index >= rows.length) return null;
    final row = rows[index];
    return DataRow.byIndex(
      index: index,
      color: owner.widget.compact && hoveredRow == index
          ? const WidgetStatePropertyAll(QueueBStyle.mint)
          : null,
      cells: [
        for (final col in owner.widget.columns)
          DataCell(
            MouseRegion(
              onEnter: owner.widget.compact ? (_) => hover(index) : null,
              onExit: owner.widget.compact ? (_) => hover(null) : null,
              child:
                  col.cell?.call(row) ??
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 220),
                    child: Tooltip(
                      message: '${col.value(row) ?? '—'}',
                      child: Text(
                        '${col.value(row) ?? '—'}',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
            ),
          ),
      ],
    );
  }

  @override
  int get rowCount => rows.length;
  @override
  bool get isRowCountApproximate => false;
  @override
  int get selectedRowCount => 0;
}

class AdminSearchChoice extends StatefulWidget {
  const AdminSearchChoice({
    super.key,
    required this.label,
    required this.choices,
    required this.value,
    required this.onChanged,
    this.required = true,
  });
  final String label;
  final List<(String, String)> choices;
  final String? value;
  final ValueChanged<String?>? onChanged;
  final bool required;
  @override
  State<AdminSearchChoice> createState() => _AdminSearchChoiceState();
}

class _AdminSearchChoiceState extends State<AdminSearchChoice> {
  final text = TextEditingController();
  String? selected;
  @override
  void initState() {
    super.initState();
    reset();
  }

  void reset() {
    selected = widget.value;
    text.text =
        widget.choices.where((c) => c.$1 == selected).firstOrNull?.$2 ?? '';
  }

  @override
  void didUpdateWidget(covariant AdminSearchChoice oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) reset();
  }

  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DropdownMenuFormField<String>(
    key: ValueKey(widget.value),
    controller: text,
    initialSelection: selected,
    expandedInsets: EdgeInsets.zero,
    menuHeight: 280,
    enabled: widget.onChanged != null,
    enableFilter: true,
    enableSearch: true,
    requestFocusOnTap: true,
    label: Text(widget.label),
    dropdownMenuEntries: [
      for (final c in widget.choices)
        DropdownMenuEntry(value: c.$1, label: c.$2),
    ],
    onSelected: (value) {
      selected = value;
      widget.onChanged?.call(value);
    },
    validator: (_) =>
        (widget.required || selected != null || text.text.isNotEmpty) &&
            !widget.choices.any((c) => c.$1 == selected && c.$2 == text.text)
        ? 'Pilih ${widget.label.toLowerCase()} dari daftar.'
        : null,
  );
}
