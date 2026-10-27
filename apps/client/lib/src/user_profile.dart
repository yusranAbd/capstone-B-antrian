import 'dart:convert';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import 'api.dart';
import 'config.dart';
import 'doctor_professional.dart';
import 'image_sizing.dart';
import 'mobile_ui.dart';
import 'patient_design.dart';

String accountRole(Object? role) => switch (role) {
  'USER' => 'Pasien',
  'PETUGAS' => 'Petugas',
  'DOKTER' => 'Dokter',
  _ => 'Administrator',
};

class AccountAvatar extends StatelessWidget {
  const AccountAvatar({super.key, required this.api, this.radius = 20});
  final QueueApi api;
  final double radius;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: api,
    builder: (context, _) {
      final name = '${api.user?['nama'] ?? ''}'.trim();
      return Semantics(
        label: 'Avatar akun',
        image: true,
        child: FutureBuilder<Uint8List?>(
          key: ValueKey('${api.user?['id']}|${api.user?['avatarProfil']}'),
          future: api.ownAvatar(),
          builder: (context, snapshot) => CircleAvatar(
            radius: radius,
            backgroundColor: PatientDesign.active(context)
                ? PatientDesign.soft
                : QueueBStyle.mint,
            foregroundColor: PatientDesign.active(context)
                ? PatientDesign.primary
                : QueueBStyle.darkTeal,
            child: snapshot.data == null
                ? Text(
                    name.isEmpty ? 'Q' : name.characters.first.toUpperCase(),
                    style: TextStyle(
                      fontSize: radius * .8,
                      fontWeight: FontWeight.w700,
                    ),
                  )
                : ClipOval(
                    child: Image.memory(
                      snapshot.data!,
                      cacheWidth: imageDecodeWidth(
                        radius * 2,
                        MediaQuery.devicePixelRatioOf(context),
                      ),
                      width: radius * 2,
                      height: radius * 2,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          const Icon(Icons.person_outline),
                    ),
                  ),
          ),
        ),
      );
    },
  );
}

class ProfileHeaderIdentity extends StatelessWidget {
  const ProfileHeaderIdentity({super.key, required this.api});
  final QueueApi api;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AccountAvatar(api: api, radius: 19),
        const SizedBox(width: 10),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 205),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${api.user?['nama'] ?? ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                accountRole(api.user?['peran']),
                style: const TextStyle(fontSize: 11, color: QueueBStyle.muted),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

Future<XFile?> pickUserAvatar() => openFile(
  acceptedTypeGroups: const [
    XTypeGroup(
      label: 'Avatar akun',
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

class UserProfilePage extends StatefulWidget {
  const UserProfilePage({
    super.key,
    required this.api,
    this.pickPhoto = pickUserAvatar,
    this.onReturnToPatient,
  });
  final QueueApi api;
  final VoidCallback? onReturnToPatient;
  final Future<XFile?> Function() pickPhoto;
  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> {
  final nameForm = GlobalKey<FormState>(),
      passwordForm = GlobalKey<FormState>();
  late final name = TextEditingController(
    text: '${widget.api.user?['nama'] ?? ''}',
  );
  final oldPassword = TextEditingController(),
      newPassword = TextEditingController(),
      confirmPassword = TextEditingController();
  int selected = 0;
  bool busy = false, loading = true;
  String? error, message;
  Uint8List? preview;
  Future<dynamic>? roleData;
  late final Object? profileOwner;
  Object? roleDataRole;
  static const labels = [
    'Informasi Pribadi',
    'Ubah Foto Profil',
    'Keamanan Akun',
    'Informasi Role/Penugasan',
  ];
  static const icons = [
    Icons.person_outline,
    Icons.photo_camera_outlined,
    Icons.lock_outline,
    Icons.badge_outlined,
  ];
  QueueApi get api => widget.api;
  @override
  void initState() {
    super.initState();
    profileOwner = api.user?['id'];
    load();
  }

  Future<void> load() async {
    setState(() => loading = true);
    try {
      await api.reloadOwnProfile();
      if (!mounted) return;
      name.text = '${api.user?['nama'] ?? ''}';
      final role = api.user?['peran'];
      roleDataRole = role;
      roleData = role == 'PETUGAS'
          ? api.request('GET', '/penugasan-petugas')
          : role == 'DOKTER'
          ? Future.wait([
              api.request('GET', '/portal-dokter/profil'),
              api.request(
                'GET',
                '/portal-dokter/jadwal',
                query: {'tanggal': api.config.today},
              ),
            ])
          : null;
      // FutureBuilder attaches immediately on selection; capture errors until then.
      roleData?.then<void>((_) {}, onError: (Object _) {});
      error = null;
    } catch (e) {
      if (mounted) error = '$e';
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> run(Future<void> Function() action, String success) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
      message = null;
    });
    try {
      await action();
      if (mounted) setState(() => message = success);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    for (final c in [name, oldPassword, newPassword, confirmPassword]) {
      c.dispose();
    }
    super.dispose();
  }

  Widget note(String text, {bool danger = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Semantics(
      liveRegion: true,
      child: Text(
        text,
        style: TextStyle(
          color: danger ? QueueBStyle.danger : QueueBStyle.darkTeal,
        ),
      ),
    ),
  );
  Widget title(String text, String subtitle) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        text,
        style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 6),
      Text(
        subtitle,
        style: const TextStyle(color: QueueBStyle.muted, height: 1.4),
      ),
      const SizedBox(height: 20),
    ],
  );
  Widget info(String label, Object? value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: QueueBStyle.muted),
        ),
        const SizedBox(height: 4),
        SelectableText(value == null || '$value'.isEmpty ? '—' : '$value'),
      ],
    ),
  );

  Widget personal() => Form(
    key: nameForm,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        title(
          'Informasi Pribadi',
          'Perbarui nama yang digunakan pada akun dan header aplikasi.',
        ),
        TextFormField(
          controller: name,
          enabled: !busy,
          maxLength: 150,
          autofillHints: const [AutofillHints.name],
          decoration: const InputDecoration(
            labelText: 'Nama lengkap',
            prefixIcon: Icon(Icons.person_outline),
          ),
          validator: (v) =>
              v == null ||
                  v.trim().runes.length < 3 ||
                  v.trim().runes.length > 150
              ? 'Nama 3–150 karakter.'
              : null,
        ),
        info('Email akun', api.user?['email']),
        note(
          'Email merupakan identitas login. Perubahan email belum tersedia.',
        ),
        info('Role', accountRole(api.user?['peran'])),
        info('Status akun', api.user?['aktif'] == false ? 'Nonaktif' : 'Aktif'),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: busy
                ? null
                : () {
                    if (nameForm.currentState!.validate()) {
                      run(
                        () => api.updateOwnName(name.text),
                        'Nama berhasil diperbarui.',
                      );
                    }
                  },
            icon: const Icon(Icons.save_outlined),
            label: const Text('Simpan Perubahan'),
          ),
        ),
      ],
    ),
  );
  Widget photo() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      title(
        'Foto Profil Akun',
        'Avatar ini hanya digunakan untuk identitas akun. Foto profesional Dokter dikelola terpisah oleh ADMIN.',
      ),
      Center(
        child: preview == null
            ? AccountAvatar(api: api, radius: 58)
            : ClipOval(
                child: Image.memory(
                  preview!,
                  cacheWidth: 256,
                  cacheHeight: 256,
                  width: 116,
                  height: 116,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) =>
                      const Icon(Icons.broken_image_outlined, size: 64),
                ),
              ),
      ),
      const SizedBox(height: 20),
      const Text(
        'JPEG, PNG atau WebP · maksimal 2 MB',
        style: TextStyle(color: QueueBStyle.muted),
      ),
      const SizedBox(height: 14),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: busy
                ? null
                : () => run(() async {
                    final file = await widget.pickPhoto();
                    if (file == null) return;
                    if (await file.length() > 2 * 1024 * 1024) {
                      throw const ApiException(
                        400,
                        'Ukuran foto maksimal 2 MB',
                      );
                    }
                    final bytes = await file.readAsBytes();
                    if (mounted) setState(() => preview = bytes);
                  }, ''),
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: Text(
              api.user?['avatarProfil'] == null ? 'Pilih Foto' : 'Ganti Foto',
            ),
          ),
          if (preview != null)
            FilledButton.icon(
              onPressed: busy
                  ? null
                  : () => run(() async {
                      await api.uploadOwnAvatar(preview!);
                      if (mounted) setState(() => preview = null);
                    }, 'Foto profil berhasil diperbarui.'),
              icon: const Icon(Icons.cloud_upload_outlined),
              label: const Text('Simpan Foto'),
            ),
          if (preview != null)
            TextButton(
              onPressed: busy ? null : () => setState(() => preview = null),
              child: const Text('Batal'),
            ),
          if (api.user?['avatarProfil'] != null)
            TextButton.icon(
              onPressed: busy
                  ? null
                  : () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Hapus Foto Profil?'),
                          content: const Text(
                            'Avatar akan kembali menggunakan inisial nama Anda. Foto profesional dokter tetap tersimpan.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Batal'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('Hapus Foto'),
                            ),
                          ],
                        ),
                      );
                      if (confirmed == true) {
                        run(() async {
                          await api.removeOwnAvatar();
                          if (mounted) setState(() => preview = null);
                        }, 'Foto profil dihapus.');
                      }
                    },
              icon: const Icon(Icons.delete_outline),
              label: const Text('Hapus Foto'),
            ),
        ],
      ),
    ],
  );
  Widget security() => Form(
    key: passwordForm,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        title(
          'Keamanan Akun',
          'Gunakan kata sandi 8–72 karakter (maksimal 72 byte). Setelah diubah, seluruh sesi dicabut dan Anda perlu masuk kembali.',
        ),
        for (final item in [
          (oldPassword, 'Kata sandi lama'),
          (newPassword, 'Kata sandi baru'),
          (confirmPassword, 'Konfirmasi kata sandi baru'),
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: TextFormField(
              controller: item.$1,
              enabled: !busy,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              autofillHints: [
                item.$1 == oldPassword
                    ? AutofillHints.password
                    : AutofillHints.newPassword,
              ],
              decoration: InputDecoration(
                labelText: item.$2,
                prefixIcon: const Icon(Icons.lock_outline),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) return 'Wajib diisi.';
                if (item.$1 == newPassword &&
                    (value.runes.length < 8 ||
                        value.runes.length > 72 ||
                        utf8.encode(value).length > 72)) {
                  return 'Gunakan 8–72 karakter, maksimal 72 byte.';
                }
                if (item.$1 == confirmPassword && value != newPassword.text) {
                  return 'Konfirmasi kata sandi tidak sesuai.';
                }
                return null;
              },
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: busy
                ? null
                : () {
                    if (passwordForm.currentState!.validate()) {
                      run(
                        () => api.changeOwnPassword(
                          oldPassword.text,
                          newPassword.text,
                        ),
                        '',
                      );
                    }
                  },
            icon: const Icon(Icons.lock_reset),
            label: const Text('Ubah Kata Sandi'),
          ),
        ),
      ],
    ),
  );
  Widget roleInfo() {
    final role = api.user?['peran'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        title(
          'Informasi Role/Penugasan',
          'Informasi ini hanya dapat dibaca. Penugasan, poliklinik, dan hak akses dikelola oleh ADMIN.',
        ),
        info('Peran akun', accountRole(role)),
        if (role == 'ADMIN')
          const Text(
            'Administrator mengelola master data dan kesiapan layanan QueueB Hospital.',
          ),
        if (role == 'USER') ...[
          const Text(
            'Tiket Saya dan Riwayat Kunjungan tersedia melalui navigasi aplikasi pasien.',
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: widget.onReturnToPatient ?? () => Navigator.pop(context),
            icon: const Icon(Icons.confirmation_number_outlined),
            label: const Text('Kembali ke aplikasi pasien'),
          ),
        ],
        if (roleData != null &&
            roleDataRole == role &&
            ['PETUGAS', 'DOKTER'].contains(role))
          FutureBuilder<dynamic>(
            future: roleData,
            builder: (context, s) {
              if (s.connectionState != ConnectionState.done) {
                return const LinearProgressIndicator();
              }
              if (s.hasError) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    note('${s.error}', danger: true),
                    TextButton(
                      onPressed: load,
                      child: const Text('Muat ulang informasi role'),
                    ),
                  ],
                );
              }
              if (role == 'PETUGAS') {
                final assignments = rows(s.data);
                return assignments.isEmpty
                    ? const Text('Belum ada penugasan loket.')
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final a in assignments)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Divider(),
                                  info(
                                    'Ruang / Loket',
                                    '${object(a['loket'])['kode']} · ${object(a['loket'])['nama']}',
                                  ),
                                  info(
                                    'Poliklinik',
                                    object(
                                      object(a['loket'])['layanan'],
                                    )['nama'],
                                  ),
                                  info(
                                    'Periode',
                                    '${date(a['tanggalMulai'])} — ${a['tanggalSelesai'] == null ? 'Tanpa batas akhir' : date(a['tanggalSelesai'])}',
                                  ),
                                  info('Status penugasan', assignmentStatus(a)),
                                ],
                              ),
                            ),
                        ],
                      );
              }
              final data = s.data as List<dynamic>,
                  doctor = object(data[0]),
                  schedules = rows(data[1]);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      ProfessionalDoctorAvatar(
                        config: api.config,
                        photo: doctor['fotoProfil'],
                        radius: 32,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '${doctor['nama'] ?? ''}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  info('Spesialisasi', doctor['spesialisasi']),
                  info(
                    'Poliklinik',
                    rows(doctor['poliklinik']).map((x) => x['nama']).join(', '),
                  ),
                  DoctorBiography(text: doctor['tentangDokter']),
                  const SizedBox(height: 16),
                  const Text(
                    'Jadwal praktik hari ini',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  if (schedules.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'Tidak ada jadwal pada tanggal pelayanan hari ini.',
                      ),
                    ),
                  for (final schedule in schedules)
                    info(
                      '${object(schedule['ruang'])['kode']} · ${object(schedule['poliklinik'])['nama']}',
                      '${serviceClock(schedule['mulaiPada'])}–${serviceClock(schedule['selesaiPada'])}${schedule['aktif'] == false ? ' · Nonaktif' : ''}',
                    ),
                ],
              );
            },
          ),
      ],
    );
  }

  String serviceClock(Object? value) {
    if (value == null) return '—';
    try {
      return api.config.localInput('$value').substring(11, 16);
    } catch (_) {
      return '—';
    }
  }

  String date(Object? value) => value == null ? '—' : '$value'.split('T').first;
  String assignmentStatus(Json row) {
    if (row['aktif'] == false) return 'Nonaktif';
    final today = api.config.today;
    if (date(row['tanggalMulai']).compareTo(today) > 0) return 'Akan datang';
    if (row['tanggalSelesai'] != null &&
        date(row['tanggalSelesai']).compareTo(today) < 0) {
      return 'Berakhir';
    }
    return 'Aktif';
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: api.user?['peran'] == 'USER'
        ? PatientDesign.theme
        : QueueBStyle.theme,
    child: ListenableBuilder(
      listenable: api,
      builder: (context, _) =>
          api.user == null || api.user?['id'] != profileOwner
          ? const SizedBox.shrink()
          : Scaffold(
              appBar: widget.onReturnToPatient != null
                  ? null
                  : AppBar(
                      automaticallyImplyLeading:
                          widget.onReturnToPatient == null,
                      title: const Text('Profil Saya'),
                      actions: [
                        IconButton(
                          tooltip: 'Muat ulang profil',
                          onPressed: busy || loading ? null : load,
                          icon: const Icon(Icons.refresh),
                        ),
                      ],
                    ),
              body: SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1040),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final wide = constraints.maxWidth >= 800;
                          final navigation = Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (widget.onReturnToPatient != null)
                                Row(
                                  children: [
                                    const Expanded(
                                      child: Text(
                                        'Profil Saya',
                                        style: TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Muat ulang profil',
                                      onPressed: busy || loading ? null : load,
                                      icon: const Icon(Icons.refresh),
                                    ),
                                  ],
                                ),
                              Row(
                                children: [
                                  AccountAvatar(api: api, radius: 32),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${api.user?['nama'] ?? ''}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 18,
                                          ),
                                        ),
                                        Text(
                                          accountRole(api.user?['peran']),
                                          style: const TextStyle(
                                            color: QueueBStyle.muted,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              info(
                                'Status akun',
                                api.user?['aktif'] == false
                                    ? 'Nonaktif'
                                    : 'Aktif',
                              ),
                              const Divider(),
                              for (var i = 0; i < labels.length; i++)
                                ListTile(
                                  dense: true,
                                  selected: selected == i,
                                  selectedTileColor: QueueBStyle.mint,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  leading: Icon(icons[i]),
                                  title: Text(labels[i]),
                                  onTap: busy
                                      ? null
                                      : () => setState(() {
                                          selected = i;
                                          error = null;
                                          message = null;
                                        }),
                                ),
                              const Divider(),
                              ListTile(
                                dense: true,
                                textColor: QueueBStyle.danger,
                                iconColor: QueueBStyle.danger,
                                leading: const Icon(Icons.logout),
                                title: const Text('Keluar Akun'),
                                onTap: busy ? null : () => run(api.logout, ''),
                              ),
                            ],
                          );
                          final content = Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: api.user?['peran'] == 'USER'
                                  ? PatientDesign.paper
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(
                                QueueBStyle.radius,
                              ),
                              border: Border.all(color: QueueBStyle.border),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (loading || busy)
                                  const Padding(
                                    padding: EdgeInsets.only(bottom: 16),
                                    child: LinearProgressIndicator(),
                                  ),
                                if (error != null) note(error!, danger: true),
                                if (message != null && message!.isNotEmpty)
                                  note(message!),
                                if (!loading)
                                  switch (selected) {
                                    0 => personal(),
                                    1 => photo(),
                                    2 => security(),
                                    _ => roleInfo(),
                                  },
                                if (loading) const Text('Memuat profil…'),
                              ],
                            ),
                          );
                          if (api.user?['peran'] == 'USER') {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (widget.onReturnToPatient != null)
                                  PatientPageIntro(
                                    title: 'Profil Saya',
                                    caption: 'Ruang pribadi untuk akun Anda.',
                                    action: IconButton(
                                      tooltip: 'Muat ulang profil',
                                      onPressed: busy || loading ? null : load,
                                      icon: const Icon(Icons.refresh),
                                    ),
                                  ),
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: PatientDesign.soft,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Row(
                                    children: [
                                      AccountAvatar(api: api, radius: 28),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              '${api.user?['nama'] ?? ''}',
                                              style: const TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.w700,
                                                color: PatientDesign.ink,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              api.user?['aktif'] == true
                                                  ? 'Akun pasien aktif'
                                                  : api.user?['aktif'] == false
                                                  ? 'Akun nonaktif'
                                                  : 'Akun pasien',
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: PatientDesign.primary,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    for (var i = 0; i < labels.length; i++)
                                      SizedBox(
                                        width: (constraints.maxWidth - 8) / 2,
                                        child: OutlinedButton.icon(
                                          style: OutlinedButton.styleFrom(
                                            backgroundColor: selected == i
                                                ? PatientDesign.soft
                                                : PatientDesign.paper,
                                            foregroundColor: selected == i
                                                ? PatientDesign.primary
                                                : PatientDesign.muted,
                                            alignment: Alignment.centerLeft,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 10,
                                            ),
                                          ),
                                          onPressed: busy
                                              ? null
                                              : () => setState(() {
                                                  selected = i;
                                                  error = null;
                                                  message = null;
                                                }),
                                          icon: Icon(icons[i], size: 18),
                                          label: Text(
                                            labels[i],
                                            style: const TextStyle(
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                content,
                                const SizedBox(height: 12),
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: PatientDesign.danger,
                                  ),
                                  onPressed: busy
                                      ? null
                                      : () => run(api.logout, ''),
                                  icon: const Icon(Icons.logout, size: 18),
                                  label: const Text('Keluar Akun'),
                                ),
                              ],
                            );
                          }
                          return wide
                              ? Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SizedBox(width: 260, child: navigation),
                                    const SizedBox(width: 24),
                                    Expanded(child: content),
                                  ],
                                )
                              : Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    navigation,
                                    const SizedBox(height: 16),
                                    content,
                                  ],
                                );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
    ),
  );
}
