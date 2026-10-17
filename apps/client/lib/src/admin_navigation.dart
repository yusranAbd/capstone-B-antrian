import 'package:flutter/material.dart';

import 'admin_schema.dart';

const adminCategories = <(String, List<int>)>[
  ('Master data', [0, 1, 2]),
  ('Manajemen jadwal', [3, 4, 5]),
  ('Manajemen petugas', [6]),
];
IconData adminIcon(int index) => switch (index) {
  1 => Icons.medical_services_outlined,
  2 => Icons.meeting_room_outlined,
  3 => Icons.access_time,
  4 => Icons.calendar_month_outlined,
  5 => Icons.event_available,
  6 => Icons.badge_outlined,
  _ => Icons.local_hospital_outlined,
};

class AdminNavigation extends StatelessWidget {
  const AdminNavigation({
    super.key,
    required this.selected,
    required this.onSelect,
  });
  final int selected;
  final ValueChanged<int>? onSelect;
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
    children: [
      const Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'Administrasi',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      for (final (category, indices) in adminCategories)
        ExpansionTile(
          key: PageStorageKey('admin-category-$category'),
          initiallyExpanded: indices.contains(selected),
          title: Text(category, style: Theme.of(context).textTheme.titleSmall),
          children: [
            for (final i in indices)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: ListTile(
                  dense: true,
                  selected: i == selected,
                  selectedTileColor: Theme.of(context)
                      .colorScheme
                      .primaryContainer,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  leading: Icon(adminIcon(i), size: 22),
                  title: Text(
                    resources[i].title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: onSelect == null ? null : () => onSelect!(i),
                ),
              ),
          ],
        ),
    ],
  );
}
