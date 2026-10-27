import 'package:flutter/material.dart';

import 'admin_schema.dart';
import 'mobile_ui.dart';

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
    this.onProfile,
  });
  final int selected;
  final ValueChanged<int>? onSelect;
  final bool collapsed;
  final VoidCallback? onToggle, onProfile;
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
    children: [
      Row(
        children: [
          if (!collapsed)
            const Expanded(
              child: Padding(
                padding: EdgeInsets.only(left: 12),
                child: Text(
                  'Administrasi',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: QueueBStyle.muted,
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
      for (final i in [-1, 0, 1, 2, 3, 4, 5, 6, 7])
        if (collapsed)
          IconButton(
            tooltip: i == -1
                ? 'Dashboard'
                : i == 7
                ? 'Manajemen Display'
                : resources[i].title,
            isSelected: selected == i,
            onPressed: onSelect == null ? null : () => onSelect!(i),
            icon: Icon(
              i == -1 ? Icons.dashboard_outlined : adminIcon(i),
              size: 20,
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: ListTile(
              minTileHeight: 44,
              dense: true,
              minLeadingWidth: 20,
              horizontalTitleGap: 10,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              selected: selected == i,
              selectedColor: QueueBStyle.darkTeal,
              selectedTileColor: QueueBStyle.mint,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              leading: Icon(
                i == -1 ? Icons.dashboard_outlined : adminIcon(i),
                size: 20,
              ),
              title: Text(
                i == -1
                    ? 'Dashboard'
                    : i == 7
                    ? 'Manajemen Display'
                    : resources[i].title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected == i ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              onTap: onSelect == null ? null : () => onSelect!(i),
            ),
          ),
      if (onProfile != null) ...[
        const Divider(height: 24),
        Tooltip(
          message: 'Profil akun',
          child: collapsed
              ? IconButton(
                  onPressed: onProfile,
                  icon: const Icon(Icons.person_outline),
                  tooltip: 'Profil Saya',
                )
              : TextButton.icon(
                  onPressed: onProfile,
                  icon: const Icon(Icons.person_outline, size: 20),
                  label: const Text('Profil Saya'),
                ),
        ),
      ],
    ],
  );
}
