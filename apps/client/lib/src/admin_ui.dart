import 'package:flutter/material.dart';

import 'config.dart';
import 'mobile_ui.dart';

// Hallmark · ADMIN workbench · QueueB tokens · P5 H5 E4 S5 R5 V4.
abstract final class AdminStyle {
  static ThemeData get theme => QueueBStyle.theme.copyWith(
    scaffoldBackgroundColor: QueueBStyle.background,
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

class AdminColumn {
  const AdminColumn(this.title, this.value, {this.cell, this.numeric = false});
  final String title;
  final Object? Function(Json) value;
  final Widget Function(Json)? cell;
  final bool numeric;
}

/// Client pagination for existing REST arrays. Only one page creates row widgets.
class AdminTable extends StatefulWidget {
  const AdminTable({
    super.key,
    required this.rows,
    required this.columns,
    this.title,
    this.pageSize = 10,
  });
  final List<Json> rows;
  final List<AdminColumn> columns;
  final String? title;
  final int pageSize;
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
    builder: (context, box) => DecoratedBox(
      decoration: BoxDecoration(
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
            dataRowMinHeight: 58,
            dataRowMaxHeight: 112,
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
                  label: Text(widget.columns[i].title),
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
  void refresh() => notifyListeners();
  @override
  DataRow? getRow(int index) {
    if (index >= rows.length) return null;
    final row = rows[index];
    return DataRow.byIndex(
      index: index,
      cells: [
        for (final col in owner.widget.columns)
          DataCell(
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
