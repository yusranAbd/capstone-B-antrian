import 'package:flutter/material.dart';

import 'config.dart';
import 'mobile_ui.dart';
import 'api.dart';

// Hallmark · scoped profile components · QueueB tokens · P5 H5 E4 S5 R5 V4.
String? doctorPhotoUrl(AppConfig config, Object? reference) {
  if (reference is! String ||
      !RegExp(
        r'^/media/dokter/[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.webp$',
      ).hasMatch(reference)) {
    return null;
  }
  return '${config.apiBase}$reference';
}

class ProfessionalDoctorAvatar extends StatelessWidget {
  const ProfessionalDoctorAvatar({
    super.key,
    required this.config,
    required this.photo,
    this.radius = 28,
  });
  final AppConfig config;
  final Object? photo;
  final double radius;
  @override
  Widget build(BuildContext context) {
    final url = doctorPhotoUrl(config, photo);
    Widget fallback() => ColoredBox(
      color: QueueBStyle.mint,
      child: Center(
        child: Icon(
          Icons.person_outline_rounded,
          size: radius,
          color: QueueBStyle.darkTeal,
        ),
      ),
    );
    return Semantics(
      label: 'Foto profil profesional dokter',
      image: true,
      child: ClipOval(
        child: SizedBox.square(
          dimension: radius * 2,
          child: url == null
              ? fallback()
              : Image.network(
                  url,
                  fit: BoxFit.cover,
                  excludeFromSemantics: true,
                  loadingBuilder: (context, child, loading) =>
                      loading == null ? child : fallback(),
                  errorBuilder: (context, error, stack) => fallback(),
                ),
        ),
      ),
    );
  }
}

class DoctorBiography extends StatefulWidget {
  const DoctorBiography({super.key, required this.text});
  final Object? text;
  @override
  State<DoctorBiography> createState() => _DoctorBiographyState();
}

class _DoctorBiographyState extends State<DoctorBiography> {
  bool expanded = false;
  @override
  void didUpdateWidget(DoctorBiography oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) expanded = false;
  }

  @override
  Widget build(BuildContext context) {
    final bio = widget.text is String ? (widget.text as String).trim() : '';
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Tentang Dokter',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: QueueBStyle.navy,
            ),
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final text = bio.isEmpty
                  ? 'Informasi tentang dokter belum dicantumkan.'
                  : bio;
              const style = TextStyle(color: QueueBStyle.muted, height: 1.5);
              final painter = TextPainter(
                text: TextSpan(text: text, style: style),
                maxLines: 4,
                textDirection: Directionality.of(context),
                textScaler: MediaQuery.textScalerOf(context),
              )..layout(maxWidth: constraints.maxWidth);
              final truncated = painter.didExceedMaxLines;
              painter.dispose();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    text,
                    style: style,
                    maxLines: expanded ? null : 4,
                    overflow: expanded
                        ? TextOverflow.visible
                        : TextOverflow.ellipsis,
                  ),
                  if (truncated || expanded)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () => setState(() => expanded = !expanded),
                        child: Text(
                          expanded
                              ? 'Tampilkan lebih sedikit'
                              : 'Baca Selengkapnya',
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Professional identity is read-only for DOKTER and distinct from account data.
class DoctorProfessionalDialog extends StatefulWidget {
  const DoctorProfessionalDialog({super.key, required this.api});
  final QueueApi api;
  @override
  State<DoctorProfessionalDialog> createState() =>
      _DoctorProfessionalDialogState();
}

class _DoctorProfessionalDialogState extends State<DoctorProfessionalDialog> {
  late Future<dynamic> profile = widget.api.request(
    'GET',
    '/portal-dokter/profil',
  );
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Profil profesional dokter'),
    content: SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: FutureBuilder<dynamic>(
          future: profile,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${snapshot.error}'),
                  TextButton(
                    onPressed: () => setState(
                      () => profile = widget.api.request(
                        'GET',
                        '/portal-dokter/profil',
                      ),
                    ),
                    child: const Text('Coba lagi'),
                  ),
                ],
              );
            }
            final data = object(snapshot.data);
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    ProfessionalDoctorAvatar(
                      config: widget.api.config,
                      photo: data['fotoProfil'],
                      radius: 36,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label(data),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            '${data['spesialisasi'] ?? 'Spesialisasi belum dicantumkan'}',
                          ),
                          Text(rows(data['poliklinik']).map(label).join(', ')),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DoctorBiography(text: data['tentangDokter']),
                const Text(
                  'Foto dan informasi profesional dikelola oleh ADMIN.',
                  style: TextStyle(color: QueueBStyle.muted, fontSize: 12),
                ),
              ],
            );
          },
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Tutup'),
      ),
    ],
  );
}
