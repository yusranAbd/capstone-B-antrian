import 'config.dart';

enum FieldKind { text, integer, date, instant, clock, choice, flag }

class AdminField {
  const AdminField(
    this.key,
    this.title, {
    this.kind = FieldKind.text,
    this.required = true,
    this.nullable = false,
    this.createOnly = false,
    this.editOnly = false,
    this.maxLength,
    this.min = 1,
    this.max,
    this.pattern,
    this.initial = '',
    this.options = const [],
  });
  final String key, title, initial;
  final FieldKind kind;
  final bool required, nullable, createOnly, editOnly;
  final int? maxLength, max;
  final int min;
  final String? pattern;
  final List<String> options;
}

class AdminResource {
  const AdminResource(this.path, this.title, this.fields);
  final String path, title;
  final List<AdminField> fields;
}

const _active = AdminField(
  'aktif',
  'Aktif',
  kind: FieldKind.flag,
  editOnly: true,
);
const _service = AdminField('layananId', 'Poliklinik', kind: FieldKind.choice);
const _room = AdminField('loketId', 'Ruang / loket', kind: FieldKind.choice);
const _name = AdminField('nama', 'Nama', maxLength: 150, min: 3);
const _start = AdminField(
  'mulaiPada',
  'Mulai (YYYY-MM-DDTHH:mm)',
  kind: FieldKind.instant,
);
const _end = AdminField(
  'selesaiPada',
  'Selesai (YYYY-MM-DDTHH:mm)',
  kind: FieldKind.instant,
);
const resources = [
  AdminResource('/layanan', 'Poliklinik', [
    AdminField('kode', 'Kode', pattern: r'[A-Z0-9]{2,20}', maxLength: 20),
    _name,
    AdminField(
      'deskripsi',
      'Deskripsi',
      required: false,
      nullable: true,
      maxLength: 1000,
    ),
    AdminField(
      'prefixAntrean',
      'Prefix antrean',
      pattern: r'[A-Z]{1,5}',
      maxLength: 5,
    ),
    AdminField(
      'durasiDasarMenit',
      'Durasi dasar (menit)',
      kind: FieldKind.integer,
      max: 240,
      initial: '15',
    ),
    AdminField(
      'modeReservasi',
      'Mode pendaftaran',
      kind: FieldKind.choice,
      createOnly: true,
      initial: 'HIBRIDA',
      options: ['ANTREAN_HARIAN', 'JANJI_TEMU_DOKTER', 'HIBRIDA'],
    ),
    _active,
  ]),
  AdminResource('/dokter', 'Dokter', [
    AdminField('kode', 'Kode', pattern: r'[A-Z0-9-]{2,30}', maxLength: 30),
    _name,
    AdminField(
      'spesialisasi',
      'Spesialisasi',
      required: false,
      nullable: true,
      maxLength: 150,
    ),
    _active,
  ]),
  AdminResource('/loket', 'Ruang & loket', [
    _service,
    AdminField(
      'kode',
      'Kode',
      pattern: r'[A-Z0-9]+(?:-[A-Z0-9]+)*',
      min: 2,
      maxLength: 20,
    ),
    AdminField('nama', 'Nama', min: 3, maxLength: 100),
    AdminField(
      'lokasi',
      'Lokasi',
      required: false,
      nullable: true,
      maxLength: 150,
    ),
    _active,
  ]),
  AdminResource('/jadwal-layanan', 'Jam & kapasitas poli', [
    _service,
    AdminField(
      'hari',
      'Hari',
      kind: FieldKind.choice,
      options: ['SENIN', 'SELASA', 'RABU', 'KAMIS', 'JUMAT', 'SABTU', 'MINGGU'],
    ),
    AdminField('jamBuka', 'Jam buka (HH:mm)', kind: FieldKind.clock),
    AdminField('jamTutup', 'Jam tutup (HH:mm)', kind: FieldKind.clock),
    AdminField(
      'kapasitasHarian',
      'Kapasitas harian',
      kind: FieldKind.integer,
      initial: '10',
    ),
    _active,
  ]),
  AdminResource('/jadwal-praktik', 'Jadwal praktik', [
    AdminField(
      'dokterLayananId',
      'Dokter & poliklinik',
      kind: FieldKind.choice,
    ),
    _room,
    AdminField(
      'tanggal',
      'Tanggal pelayanan (YYYY-MM-DD)',
      kind: FieldKind.date,
    ),
    _start,
    _end,
    _active,
  ]),
  AdminResource('/slot-praktik', 'Slot konsultasi', [
    AdminField(
      'jadwalPraktikId',
      'Sesi praktik',
      kind: FieldKind.choice,
      createOnly: true,
    ),
    _start,
    _end,
    AdminField(
      'kapasitas',
      'Kapasitas slot',
      kind: FieldKind.integer,
      initial: '1',
    ),
    _active,
  ]),
  AdminResource('/penugasan-petugas', 'Penugasan petugas', [
    AdminField(
      'petugasId',
      'ID akun PETUGAS',
      pattern: r'[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}',
    ),
    _room,
    AdminField(
      'tanggalMulai',
      'Tanggal mulai (YYYY-MM-DD)',
      kind: FieldKind.date,
    ),
    AdminField(
      'tanggalSelesai',
      'Tanggal selesai (opsional)',
      kind: FieldKind.date,
      required: false,
      nullable: true,
    ),
    _active,
  ]),
];
String? validateAdminField(AdminField field, String input, AppConfig config) {
  if (input.isEmpty) {
    return field.required ? '${field.title} wajib diisi.' : null;
  }
  if (field.maxLength != null && input.length > field.maxLength!) {
    return 'Maksimal ${field.maxLength} karakter.';
  }
  if (field.pattern != null &&
      !RegExp('^(?:${field.pattern})\$').hasMatch(input)) {
    return 'Format ${field.title} tidak sesuai.';
  }
  if (field.kind == FieldKind.integer) {
    final n = int.tryParse(input);
    if (n == null || n < field.min || (field.max != null && n > field.max!)) {
      return 'Bilangan bulat ${field.min}${field.max == null ? ' atau lebih' : '–${field.max}'}.';
    }
  }
  if (field.kind == FieldKind.text && input.length < field.min) {
    return 'Minimal ${field.min} karakter.';
  }
  if (field.kind == FieldKind.clock &&
      !RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$').hasMatch(input)) {
    return 'Gunakan HH:mm.';
  }
  if (field.kind == FieldKind.date) {
    final parsed = DateTime.tryParse(input);
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(input) ||
        parsed == null ||
        calendarDate(parsed) != input) {
      return 'Tanggal tidak valid. Gunakan YYYY-MM-DD.';
    }
  }
  if (field.kind == FieldKind.instant) {
    try {
      config.toInstant(input);
    } catch (_) {
      return 'Waktu tidak valid. Gunakan YYYY-MM-DDTHH:mm.';
    }
  }
  return null;
}

Json adminPayload(
  AdminResource resource,
  Map<String, String> inputs,
  bool editing,
  AppConfig config,
) => {
  for (final f in resource.fields.where(
    (f) => !(editing && f.createOnly) && !(!editing && f.editOnly),
  ))
    if (inputs[f.key]?.isNotEmpty == true || f.nullable)
      f.key: (inputs[f.key] ?? '').isEmpty
          ? null
          : switch (f.kind) {
              FieldKind.integer => int.parse(inputs[f.key]!),
              FieldKind.flag => inputs[f.key] == 'true',
              FieldKind.instant => config.toInstant(inputs[f.key]!),
              _ => inputs[f.key]!.trim(),
            },
};
