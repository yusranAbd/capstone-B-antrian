import 'package:flutter/material.dart';

import 'admin_schema.dart';
import 'mobile_ui.dart';

const adminCategories = <(String, List<int>)>[
  ('Master data', [0, 1, 2]),
  ('Manajemen jadwal', [3, 4, 5]),
  ('Operasional', [6, 7]),
];
IconData adminIcon(int index) => switch (index) {
  1 => Icons.medical_services_outlined,
  2 => Icons.meeting_room_outlined,
  3 => Icons.access_time,
  4 => Icons.calendar_month_outlined,
  5 => Icons.event_available,
  6 => Icons.badge_outlined,
  7 => Icons.tv_outlined,
  _ => Icons.local_hospital_outlined,
};

class AdminNavigation extends StatelessWidget {
  const AdminNavigation({
    super.key,
    required this.selected,
    required this.onSelect,
    this.collapsed = false,
    this.onToggle,
  });
  final int selected;
  final ValueChanged<int>? onSelect;
  final bool collapsed;
  final VoidCallback? onToggle;
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
    children: [
      Row(
        children: [
          if (!collapsed)
            const Expanded(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Administrasi',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: QueueBStyle.navy,
                  ),
                ),
              ),
            ),
          if (onToggle != null)
            IconButton(
              tooltip: collapsed ? 'Perluas sidebar' : 'Ciutkan sidebar',
              onPressed: onToggle,
              icon: Icon(collapsed ? Icons.menu : Icons.menu_open),
            ),
        ],
      ),
      if (collapsed)
        IconButton(
          tooltip: 'Dashboard',
          isSelected: selected == -1,
          onPressed: onSelect == null ? null : () => onSelect!(-1),
          icon: const Icon(Icons.dashboard_outlined),
        )
      else
        ListTile(
          selected: selected == -1,
          selectedTileColor: QueueBStyle.mint,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          leading: const Icon(Icons.dashboard_outlined),
          title: collapsed ? null : const Text('Dashboard'),
          onTap: onSelect == null ? null : () => onSelect!(-1),
        ),
      if (collapsed) ...[
        for (var i = 0; i < 8; i++)
          IconButton(
            tooltip: i == 7 ? 'Manajemen Display' : resources[i].title,
            isSelected: selected == i,
            icon: Icon(adminIcon(i)),
            onPressed: onSelect == null ? null : () => onSelect!(i),
          ),
      ] else
        for (final (category, indices) in adminCategories) ...[
          const Divider(color: QueueBStyle.border, height: 24),
          ExpansionTile(
            key: PageStorageKey('admin-category-$category'),
            initiallyExpanded: selected == -1 || indices.contains(selected),
            shape: const Border(),
            collapsedShape: const Border(),
            iconColor: QueueBStyle.darkTeal,
            collapsedIconColor: QueueBStyle.darkTeal,
            childrenPadding: const EdgeInsets.only(bottom: 12),
            title: Text(
              category,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: QueueBStyle.muted,
              ),
            ),
            children: [
              for (final i in indices)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: ListTile(
                    dense: false,
                    visualDensity: VisualDensity.compact,
                    selectedColor: QueueBStyle.darkTeal,
                    selected: i == selected,
                    selectedTileColor: QueueBStyle.mint,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    leading: Icon(adminIcon(i), size: 22),
                    title: Text(
                      i == 7 ? 'Manajemen Display' : resources[i].title,
                      style: const TextStyle(fontSize: 14),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: onSelect == null ? null : () => onSelect!(i),
                  ),
                ),
            ],
          ),
        ],
    ],
  );
}
