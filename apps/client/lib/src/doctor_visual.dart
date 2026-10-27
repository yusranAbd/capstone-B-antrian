import 'package:flutter/material.dart';

import 'mobile_ui.dart';

abstract final class DoctorStyle {
  static const canvas = Color(0xffeff9fd);
  static const paleBlue = Color(0xffedf7ff);
  static const deepNavy = Color(0xff07334b);
  static const deepTeal = Color(0xff084f5e);
  static const liveMuted = Color(0xffc3e1e9);
  static const liveNumber = Color(0xff8eefd5);
  static const rule = Color(0xffe3eff5);
  static const shadow = Color(0x0707334b);
  static BoxDecoration get panel => BoxDecoration(
    color: Colors.white,
    border: Border.all(color: rule),
    borderRadius: BorderRadius.circular(20),
    boxShadow: const [
      BoxShadow(color: shadow, blurRadius: 20, offset: Offset(0, 5)),
    ],
  );
  static ThemeData get theme => QueueBStyle.theme.copyWith(
    scaffoldBackgroundColor: canvas,
    textTheme: QueueBStyle.operationalTextTheme,
    appBarTheme: QueueBStyle.theme.appBarTheme.copyWith(
      backgroundColor: Colors.white,
      toolbarHeight: QueueBStyle.operationalToolbarHeight,
      scrolledUnderElevation: 0,
      shape: const Border(bottom: BorderSide(color: rule)),
    ),
    inputDecorationTheme: QueueBStyle.theme.inputDecorationTheme.copyWith(
      fillColor: QueueBStyle.background,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    ),
  );
}

/// Generic local illustration, never a photo of the signed-in person.
class DoctorAvatar extends StatelessWidget {
  const DoctorAvatar({
    super.key,
    this.size = 88,
    this.asset = 'assets/illustrations/doctor_avatar.png',
  });
  final double size;
  final String asset;
  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: 'Avatar dokter generik',
    image: true,
    child: Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: DoctorStyle.paleBlue,
        shape: BoxShape.circle,
      ),
      child: ClipOval(
        child: Image.asset(
          asset,
          fit: BoxFit.cover,
          excludeFromSemantics: true,
          errorBuilder: (_, _, _) => Icon(
            Icons.medical_services_outlined,
            size: size * .48,
            color: QueueBStyle.darkTeal,
          ),
        ),
      ),
    ),
  );
}

class DoctorHeaderIdentity extends StatelessWidget {
  const DoctorHeaderIdentity({super.key, required this.name});
  final String name;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const DoctorAvatar(size: 36),
        if (MediaQuery.sizeOf(context).width >= 600) ...[
          const SizedBox(width: 12),
          SizedBox(
            width: MediaQuery.sizeOf(context).width >= 1100 ? 220 : 150,
            child: Text(
              name.trim().isEmpty ? 'Dokter' : name.trim(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ],
    ),
  );
}

class DoctorSectionTitle extends StatelessWidget {
  const DoctorSectionTitle({
    super.key,
    required this.title,
    required this.icon,
    this.subtitle,
  });
  final String title;
  final IconData icon;
  final String? subtitle;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      DoctorIconTile(icon: icon),
      const SizedBox(width: 14),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(subtitle!, style: const TextStyle(color: QueueBStyle.muted)),
            ],
          ],
        ),
      ),
    ],
  );
}

class DoctorIconTile extends StatelessWidget {
  const DoctorIconTile({
    super.key,
    required this.icon,
    this.color = QueueBStyle.darkTeal,
    this.size = 48,
  });
  final IconData icon;
  final Color color;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: color.withValues(alpha: .07),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Icon(icon, color: color, size: size * .5),
  );
}

/// Decorative clipboard drawn with native widgets; no patient data.
class DoctorQueueEmpty extends StatelessWidget {
  const DoctorQueueEmpty({super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 22),
    child: Column(
      children: [
        ExcludeSemantics(
          child: SizedBox(
            width: 150,
            height: 100,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 145,
                  height: 66,
                  decoration: BoxDecoration(
                    color: DoctorStyle.paleBlue,
                    borderRadius: BorderRadius.circular(45),
                  ),
                ),
                const Icon(
                  Icons.assignment_outlined,
                  size: 82,
                  color: DoctorStyle.liveMuted,
                ),
                const Positioned(
                  right: 16,
                  bottom: 0,
                  child: Icon(
                    Icons.search_rounded,
                    size: 44,
                    color: QueueBStyle.darkTeal,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          'Belum ada antrean yang sesuai.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}

class DoctorInfoBlock extends StatelessWidget {
  const DoctorInfoBlock({super.key, required this.icon, required this.child});
  final IconData icon;
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: DoctorStyle.paleBlue,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      children: [
        Icon(icon, color: QueueBStyle.darkTeal, size: 30),
        const SizedBox(width: 16),
        Expanded(child: child),
      ],
    ),
  );
}
