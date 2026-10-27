import 'package:flutter/material.dart';

import 'config.dart';
import 'mobile_ui.dart';

class Notice extends StatelessWidget {
  const Notice(this.text, {super.key, this.error = false});
  final String text;
  final bool error;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.symmetric(vertical: 8),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: error
          ? Theme.of(context).colorScheme.errorContainer
          : const Color(0xffeaf0ff),
      borderRadius: BorderRadius.circular(12),
    ),
    child: SelectableText(
      text,
      style: TextStyle(
        color: error
            ? Theme.of(context).colorScheme.onErrorContainer
            : const Color(0xff20375c),
      ),
    ),
  );
}

class Section extends StatelessWidget {
  const Section({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.action,
  });
  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.symmetric(vertical: 8),
    child: Padding(
      padding: const EdgeInsets.all(QueueBStyle.space),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: QueueBStyle.mediumSpace,
            runSpacing: QueueBStyle.smallSpace,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              ?action,
            ],
          ),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(subtitle!),
            ),
          const SizedBox(height: QueueBStyle.mediumSpace),
          child,
        ],
      ),
    ),
  );
}

class ChoiceField extends StatelessWidget {
  const ChoiceField({
    super.key,
    required this.label,
    required this.choices,
    required this.value,
    required this.onChanged,
    this.required = false,
  });
  final String label;
  final List<(String, String)> choices;
  final String? value;
  final ValueChanged<String?>? onChanged;
  final bool required;
  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
    key: ValueKey('$label:$value:${choices.map((c) => c.$1).join(',')}'),
    initialValue: choices.any((c) => c.$1 == value) ? value : null,
    isExpanded: true,
    decoration: InputDecoration(labelText: label),
    items: choices
        .map(
          (c) => DropdownMenuItem(
            value: c.$1,
            child: Text(c.$2, overflow: TextOverflow.ellipsis),
          ),
        )
        .toList(),
    onChanged: onChanged,
    validator: required
        ? (v) => v == null || v.isEmpty ? '$label wajib dipilih.' : null
        : null,
  );
}

Widget stateChip(Object? status) => Chip(
  label: Text('$status'.replaceAll('_', ' ')),
  visualDensity: VisualDensity.compact,
);
Future<bool> confirm(BuildContext context, String message) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Konfirmasi tindakan'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Kembali'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Lanjutkan'),
          ),
        ],
      ),
    ) ??
    false;
List<(String, String)> choicesOf(List<Json> list) => list
    .map(
      (v) => (
        '${v['id']}',
        '${v['kode'] ?? ''} · ${label(v)}${v['aktif'] == false ? ' (nonaktif)' : ''}',
      ),
    )
    .toList();
