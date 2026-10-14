import { ModeReservasi } from '../generated/prisma/client';
import { pilihBerikutnyaHospital, urutkanKandidatHospital, type KandidatHospital } from './hospital-queue-selector';

const kini = new Date('2026-10-14T03:30:00Z');
const loketA = 'loket-a';
const loketB = 'loket-b';
const waktu = (jam: string) => new Date(`2026-10-14T${jam}:00Z`);

function walkIn(id: string, checkIn = '03:00', urutan = 1): KandidatHospital {
  return { id, urutanMasukAntrean: urutan, checkInPada: waktu(checkIn),
    tanggalAntrean: waktu('00:00'), layananId: 'poli-a', janjiTemu: null };
}
function janji(
  id: string,
  awal = '03:00',
  akhir = '04:00',
  checkIn = '03:10',
  loketId = loketA,
  aktif = true,
): KandidatHospital {
  return {
    id,
    urutanMasukAntrean: 2,
    checkInPada: waktu(checkIn),
    tanggalAntrean: waktu('00:00'),
    layananId: 'poli-a',
    janjiTemu: {
      slotPraktik: {
        aktif,
        mulaiPada: waktu(awal),
        selesaiPada: waktu(akhir),
        jadwalPraktik: { aktif: true, loketId, tanggal: waktu('00:00'),
          mulaiPada: waktu('01:00'), selesaiPada: waktu('06:00'),
          loket: { aktif: true, layananId: 'poli-a' },
          dokterLayanan: { aktif: true, layananId: 'poli-a', layanan: { aktif: true }, dokter: { aktif: true } } },
      },
    },
  };
}

describe('Hospital Queue Selector H3.3', () => {
  it('mendahulukan janji yang sedang dalam slot, bukan walk-in lebih dulu check-in', () => {
    const data = [walkIn('walk', '02:00'), janji('janji')];
    expect(pilihBerikutnyaHospital(data, ModeReservasi.HIBRIDA, loketA, kini, true)?.id).toBe('janji');
  });
  it('dua slot aktif: awal slot lebih dini lebih prioritas', () => {
    const data = [janji('akhir', '03:15', '04:00', '02:59'), janji('awal', '03:00', '03:45', '03:20')];
    expect(pilihBerikutnyaHospital(data, ModeReservasi.HIBRIDA, loketA, kini, true)?.id).toBe('awal');
  });
  it('slot sama: FIFO waktu check-in, bukan urutan masuk', () => {
    const cepat = janji('cepat', '03:00', '04:00', '03:05');
    cepat.urutanMasukAntrean = 9;
    const lambat = janji('lambat', '03:00', '04:00', '03:10');
    lambat.urutanMasukAntrean = 1;
    expect(pilihBerikutnyaHospital([lambat, cepat], ModeReservasi.HIBRIDA, loketA, kini, true)?.id).toBe('cepat');
  });
  it('REQUEUE pada slot yang sama memakai waktu antre ulang, bukan check-in lama', () => {
    const ulang = janji('ulang', '03:00', '04:00', '02:00');
    ulang.urutanMasukAntrean = 9;
    ulang.peristiwaAntrean = [{ terjadiPada: waktu('03:25') }];
    const menunggu = janji('menunggu', '03:00', '04:00', '03:10');
    expect(urutkanKandidatHospital([ulang, menunggu], ModeReservasi.HIBRIDA, loketA, kini, true)
      .map((item) => item.tiket.id)).toEqual(['menunggu', 'ulang']);
    expect(pilihBerikutnyaHospital([ulang, menunggu], ModeReservasi.HIBRIDA, loketA, kini, true)?.id).toBe('menunggu');
    expect(ulang.checkInPada).toEqual(waktu('02:00'));
  });
  it('REQUEUE tetap mempertahankan prioritas slot lebih awal', () => {
    const ulang = janji('ulang', '02:00', '03:00', '02:00');
    ulang.peristiwaAntrean = [{ terjadiPada: waktu('03:25') }];
    const berikut = janji('berikut', '03:00', '04:00', '03:00');
    expect(pilihBerikutnyaHospital([berikut, ulang], ModeReservasi.HIBRIDA, loketA, kini, true)?.id).toBe('ulang');
  });
  it('walk-in yang REQUEUE tidak mendahului pasien dengan waktu check-in lebih baru', () => {
    const ulang = walkIn('ulang', '02:00', 9);
    ulang.peristiwaAntrean = [{ terjadiPada: waktu('03:25') }];
    const menunggu = walkIn('menunggu', '03:10', 2);
    expect(pilihBerikutnyaHospital([ulang, menunggu], ModeReservasi.HIBRIDA, loketA, kini, true)?.id).toBe('menunggu');
  });
  it('tanpa audit REQUEUE, FIFO check-in tetap berlaku meskipun ENQUEUE lebih akhir', () => {
    const cepat = walkIn('cepat', '03:00', 9);
    cepat.peristiwaAntrean = [];
    expect(pilihBerikutnyaHospital([walkIn('lambat', '03:10', 1), cepat], ModeReservasi.HIBRIDA, loketA, kini, true)?.id).toBe('cepat');
  });
  it('slot belum tiba tidak menutup kesempatan walk-in', () => {
    expect(pilihBerikutnyaHospital([janji('nanti', '04:00', '05:00'), walkIn('walk')], ModeReservasi.HIBRIDA, loketA, kini, true)?.id).toBe('walk');
  });
  it('janji untuk ruang B tidak dapat dipanggil dari ruang A', () => {
    expect(pilihBerikutnyaHospital([janji('ruang-b', '03:00', '04:00', '03:00', loketB), walkIn('walk')], ModeReservasi.HIBRIDA, loketA, kini, true)?.id).toBe('walk');
  });
  it.each([ModeReservasi.HIBRIDA, ModeReservasi.JANJI_TEMU_DOKTER])(
    'pasien MENUNGGU tetap dapat dipanggil setelah slot berakhir pada mode %s',
    (mode) => {
      expect(pilihBerikutnyaHospital([janji('lama', '02:00', '03:00'), walkIn('walk')], mode, loketA, kini, true)?.id).toBe('lama');
    },
  );
  it('slot lebih awal yang sudah berakhir tetap mendahului slot berikutnya', () => {
    const lama = janji('lama', '02:00', '03:00', '03:20');
    const berikut = janji('berikut', '03:00', '04:00', '02:50');
    expect(pilihBerikutnyaHospital([berikut, lama], ModeReservasi.HIBRIDA, loketA, kini, true)?.id).toBe('lama');
  });
  it('tepat pada akhir slot, tiket tetap layak di daftar dan CALL', () => {
    const data = [janji('batas', '03:00', '03:30')];
    expect(urutkanKandidatHospital(data, ModeReservasi.HIBRIDA, loketA, kini, true)[0]?.layakDipanggil).toBe(true);
    expect(pilihBerikutnyaHospital(data, ModeReservasi.HIBRIDA, loketA, kini, true)?.id).toBe('batas');
  });
  it.each(['belum-mulai', 'berakhir', 'tanggal-lain', 'nonaktif'] as const)(
    'appointment dengan slot berakhir tetap ditolak jika sesi %s', (kasus) => {
      const tiket = janji('lama', '02:00', '03:00');
      const sesi = tiket.janjiTemu!.slotPraktik.jadwalPraktik;
      if (kasus === 'belum-mulai') sesi.mulaiPada = waktu('04:00');
      if (kasus === 'berakhir') sesi.selesaiPada = kini;
      if (kasus === 'tanggal-lain') sesi.tanggal = new Date('2026-10-15T00:00:00Z');
      if (kasus === 'nonaktif') sesi.aktif = false;
      expect(urutkanKandidatHospital([tiket], ModeReservasi.JANJI_TEMU_DOKTER, loketA, kini, true)[0]?.layakDipanggil).toBe(false);
      expect(pilihBerikutnyaHospital([tiket], ModeReservasi.JANJI_TEMU_DOKTER, loketA, kini, true)).toBeNull();
    },
  );
  it('tepat pada awal sesi, slot yang sudah dimulai layak dipanggil', () => {
    const tiket = janji('awal', '03:30', '04:00');
    tiket.janjiTemu!.slotPraktik.jadwalPraktik.mulaiPada = kini;
    expect(pilihBerikutnyaHospital([tiket], ModeReservasi.JANJI_TEMU_DOKTER, loketA, kini, true)?.id).toBe('awal');
  });
  it('slot nonaktif tidak dapat dipanggil', () => {
    expect(pilihBerikutnyaHospital([janji('mati', '03:00', '04:00', '03:00', loketA, false)], ModeReservasi.HIBRIDA, loketA, kini, true)).toBeNull();
  });
  it('janji tanpa check-in tidak dapat dipanggil', () => {
    const data = janji('belum'); data.checkInPada = null;
    expect(pilihBerikutnyaHospital([data], ModeReservasi.HIBRIDA, loketA, kini, true)).toBeNull();
  });
  it('mode hanya-appointment tidak mengizinkan walk-in', () => {
    expect(pilihBerikutnyaHospital([walkIn('walk')], ModeReservasi.JANJI_TEMU_DOKTER, loketA, kini, true)).toBeNull();
  });
  it('walk-in pada mode HIBRIDA FIFO check-in, urutan masuk sebagai tie-break', () => {
    const data = [walkIn('lambat', '03:10', 1), walkIn('cepat', '03:00', 9)];
    expect(urutkanKandidatHospital(data, ModeReservasi.HIBRIDA, loketA, kini, true).map((x) => x.tiket.id)).toEqual(['cepat', 'lambat']);
  });
  it('prioritas deterministik pada check-in sama: urutan kemudian id', () => {
    const a = walkIn('a', '03:00', 2);
    const b = walkIn('b', '03:00', 2);
    const c = walkIn('c', '03:00', 1);
    expect(urutkanKandidatHospital([b, a, c], ModeReservasi.HIBRIDA, loketA, kini, true).map((x) => x.tiket.id)).toEqual(['c', 'a', 'b']);
  });
  it('GET dapat memuat tiket ineligible tetapi menandainya', () => {
    const urut = urutkanKandidatHospital([janji('nanti', '04:00', '05:00'), walkIn('walk')], ModeReservasi.HIBRIDA, loketA, kini, true);
    expect(urut.map((item) => [item.tiket.id, item.layakDipanggil])).toEqual([['walk', true], ['nanti', false]]);
  });
  it('tidak memutasi array dari ORM', () => {
    const data = Object.freeze([walkIn('walk'), janji('janji')]);
    expect(() => urutkanKandidatHospital(data, ModeReservasi.HIBRIDA, loketA, kini, true)).not.toThrow();
    expect(data[0]?.id).toBe('walk');
  });
});
