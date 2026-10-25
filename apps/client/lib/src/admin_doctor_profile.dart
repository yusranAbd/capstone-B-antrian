import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import 'admin_schedules.dart';
import 'api.dart';
import 'config.dart';
import 'doctor_professional.dart';
import 'image_sizing.dart';

// Hallmark · compact editor · existing ADMIN tokens · P5 H5 E4 S5 R5 V4.
typedef DoctorPhotoPicker = Future<XFile?> Function();
Future<XFile?> pickDoctorPhoto() => openFile(
  acceptedTypeGroups: const [
    XTypeGroup(
      label: 'Foto dokter',
      extensions: ['jpg', 'jpeg', 'png', 'webp'],
      mimeTypes: ['image/jpeg', 'image/png', 'image/webp'],
      uniformTypeIdentifiers: [
        'public.jpeg',
        'public.png',
        'org.webmproject.webp',
      ],
    ),
  ],
);

class AdminDoctorEditor extends StatefulWidget {
  const AdminDoctorEditor({
    super.key,
    required this.api,
    this.row,
    this.pickPhoto = pickDoctorPhoto,
  });
  final QueueApi api;
  final Json? row;
  final DoctorPhotoPicker pickPhoto;
  @override
  State<AdminDoctorEditor> createState() => _AdminDoctorEditorState();
}

class _AdminDoctorEditorState extends State<AdminDoctorEditor> {
  final form = GlobalKey<FormState>();
  late final name = TextEditingController(
    text: widget.row?['nama'] as String? ?? '',
  );
  late final code = TextEditingController(
    text: widget.row?['kode'] as String? ?? '',
  );
  late final specialty = TextEditingController(
    text: widget.row?['spesialisasi'] as String? ?? '',
  );
  late final bio = TextEditingController(
    text: widget.row?['tentangDokter'] as String? ?? '',
  );
  late String? savedId = widget.row?['id'] as String?;
  late Object? photo = widget.row?['fotoProfil'];
  late bool active = widget.row?['aktif'] != false;
  bool busy = false, picking = false, removePhoto = false, saved = false;
  Uint8List? selected;
  String? error;

  Future<void> pick() async {
    setState(() {
      picking = true;
      error = null;
    });
    try {
      final file = await widget.pickPhoto();
      if (file == null) return;
      if (await file.length() > 2 * 1024 * 1024) {
        throw const ApiException(413, 'Ukuran foto maksimal 2 MB.');
      }
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        selected = bytes;
        removePhoto = false;
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Foto belum dapat dipilih. Gunakan JPEG, PNG atau WebP maksimal 2 MB.',
        );
      }
    } finally {
      if (mounted) setState(() => picking = false);
    }
  }

  Future<void> save() async {
    if (busy || picking || !form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = object(
        await widget.api.request(
          savedId == null ? 'POST' : 'PATCH',
          savedId == null ? '/dokter' : '/dokter/$savedId',
          body: {
            'nama': name.text.trim(),
            'kode': code.text.trim(),
            'spesialisasi': specialty.text.trim().isEmpty
                ? null
                : specialty.text.trim(),
            'tentangDokter': bio.text.trim().isEmpty ? null : bio.text.trim(),
            if (savedId != null) 'aktif': active,
          },
        ),
      );
      savedId ??= result['id'] as String;
      saved = true;
      if (selected != null) {
        final upload = object(
          await widget.api.request(
            'POST',
            '/dokter/$savedId/foto',
            photoBytes: selected,
          ),
        );
        photo = upload['fotoProfil'];
        selected = null;
      } else if (removePhoto) {
        await widget.api.request('DELETE', '/dokter/$savedId/foto');
        photo = null;
        removePhoto = false;
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          error =
              '${saved ? 'Profil sudah tersimpan. Foto belum tersimpan; coba lagi tanpa membuat profil baru.\n' : ''}$e';
          busy = false;
        });
      }
    }
  }

  @override
  void dispose() {
    name.dispose();
    code.dispose();
    specialty.dispose();
    bio.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy && !picking,
    child: AlertDialog(
      title: Text('${savedId == null ? 'Tambah' : 'Ubah'} Dokter'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Profil profesional dokter. Penautan poliklinik dan akun login tetap dikelola dari tabel.',
                  style: TextStyle(fontSize: 13),
                ),
                if (error != null) AdminNotice(error!, error: true),
                const SizedBox(height: 16),
                const Text(
                  'Profil Dokter',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    selected != null
                        ? ClipOval(
                            child: Image.memory(
                              selected!,
                              cacheWidth: imageDecodeWidth(
                                72,
                                MediaQuery.devicePixelRatioOf(context),
                              ),
                              width: 72,
                              height: 72,
                              fit: BoxFit.cover,
                              errorBuilder: (_, error, stack) =>
                                  const SizedBox.square(
                                    dimension: 72,
                                    child: Icon(Icons.person_outline, size: 36),
                                  ),
                            ),
                          )
                        : ProfessionalDoctorAvatar(
                            config: widget.api.config,
                            photo: removePhoto ? null : photo,
                            radius: 36,
                          ),
                    OutlinedButton.icon(
                      onPressed: busy || picking ? null : pick,
                      icon: const Icon(Icons.upload_outlined, size: 18),
                      label: Text(
                        picking
                            ? 'Membaca foto…'
                            : selected != null || photo != null && !removePhoto
                            ? 'Ganti Foto'
                            : 'Upload Foto',
                      ),
                    ),
                    if (selected != null || photo != null && !removePhoto)
                      TextButton.icon(
                        onPressed: busy || picking
                            ? null
                            : () => setState(() {
                                selected = null;
                                removePhoto = photo != null;
                              }),
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: const Text('Hapus Foto'),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'JPEG, PNG atau WebP · maksimal 2 MB. Perubahan foto diterapkan saat Simpan.',
                  style: TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: name,
                  enabled: !busy,
                  decoration: const InputDecoration(labelText: 'Nama dokter'),
                  maxLength: 150,
                  validator: (v) => (v?.trim().length ?? 0) < 3
                      ? 'Nama minimal 3 karakter.'
                      : null,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: code,
                  enabled: !busy,
                  decoration: const InputDecoration(labelText: 'Kode'),
                  maxLength: 30,
                  validator: (v) =>
                      !RegExp(r'^[A-Z0-9-]{2,30}$').hasMatch(v?.trim() ?? '')
                      ? 'Gunakan 2–30 huruf kapital, angka atau tanda hubung.'
                      : null,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: specialty,
                  enabled: !busy,
                  decoration: const InputDecoration(
                    labelText: 'Spesialisasi (opsional)',
                  ),
                  maxLength: 150,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: bio,
                  enabled: !busy,
                  minLines: 3,
                  maxLines: 5,
                  maxLength: 1500,
                  decoration: const InputDecoration(
                    labelText: 'Tentang Dokter (opsional)',
                    alignLabelWithHint: true,
                    hintText: 'Deskripsi singkat profil profesional dokter',
                  ),
                  validator: (v) => (v?.length ?? 0) > 1500
                      ? 'Maksimal 1.500 karakter.'
                      : null,
                ),
                if (savedId != null)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Profil dokter aktif'),
                    value: active,
                    onChanged: busy ? null : (v) => setState(() => active = v),
                  ),
                if (busy) const LinearProgressIndicator(),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy || picking
              ? null
              : () => Navigator.pop(context, saved),
          child: const Text('Kembali'),
        ),
        FilledButton(
          onPressed: busy || picking ? null : save,
          child: Text(busy ? 'Menyimpan…' : 'Simpan'),
        ),
      ],
    ),
  );
}
