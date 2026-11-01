import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:queueb_client/src/patient_ticket_pdf.dart';

void main() {
  const sample = PatientTicketPdfData(
    queueNumber: 'PD-001',
    serviceName: 'Poliklinik Penyakit Dalam',
    status: 'Dipesan',
    serviceDate: 'Selasa, 3 November 2026',
    patientName: 'Pasien Test',
    consultationTime: '11.40 - 12.00 Asia/Jakarta',
    doctorName: 'dr. Sekar Larasati',
    roomName: 'Ruang Penyakit Dalam 2',
    reservationType: 'Janji temu dokter',
  );

  test('Bukti reservasi menghasilkan file PDF nota 80 mm', () async {
    final format = PatientTicketPdf.receiptFormat(sample);
    expect(format.width / PdfPageFormat.mm, closeTo(80, .001));
    expect(format.height / PdfPageFormat.mm, lessThan(180));
    final bytes = await PatientTicketPdf.build(sample);
    expect(bytes.length, greaterThan(500));
    expect(ascii.decode(bytes.take(5).toList()), '%PDF-');
  });

  test('PDF dapat dihasilkan untuk kertas 58 mm bila diperlukan', () async {
    final bytes = await PatientTicketPdf.build(
      sample,
      pageFormat: PdfPageFormat(58 * PdfPageFormat.mm, 175 * PdfPageFormat.mm),
    );
    expect(ascii.decode(bytes.take(5).toList()), '%PDF-');
  });

  test('QR bukti reservasi terbit dari kode tiket acak yang valid', () async {
    const ticket = PatientTicketPdfData(
      queueNumber: 'PD-001',
      serviceName: 'Poliklinik',
      status: 'Dipesan',
      serviceDate: '3 November 2026',
      patientName: 'Pasien Uji',
      reservationCode: 'TK0123456789ABCDEF01234567',
    );
    expect(ticket.receiptQrPayload, 'QBR1.TK0123456789ABCDEF01234567');
    expect(PatientTicketPdf.receiptFormat(ticket).height,
        greaterThan(PatientTicketPdf.receiptFormat(sample).height - 10));
    final bytes = await PatientTicketPdf.build(ticket);
    expect(ascii.decode(bytes.take(5).toList()), '%PDF-');
  });

  test('QR reservasi tidak muncul untuk tiket selesai, kode palsu, atau kosong', () {
    const selesai = PatientTicketPdfData(
      queueNumber: 'PD-001', serviceName: 'Poliklinik', status: 'Selesai',
      serviceDate: '3 November 2026', patientName: 'Pasien',
      reservationCode: 'TK0123456789ABCDEF01234567',
    );
    const palsu = PatientTicketPdfData(
      queueNumber: 'PD-001', serviceName: 'Poliklinik', status: 'Dipesan',
      serviceDate: '3 November 2026', patientName: 'Pasien',
      reservationCode: 'bukan-token-valid',
    );
    expect(selesai.receiptQrPayload, isNull);
    expect(palsu.receiptQrPayload, isNull);
    expect(sample.receiptQrPayload, isNull);
  });

  test('Nama PDF tidak memuat path dan identitas pasien', () {
    const ticket = PatientTicketPdfData(
      queueNumber: 'PD/001:2',
      serviceName: 'Poliklinik',
      status: 'Dipesan',
      serviceDate: '2026-11-03',
      patientName: 'Nama Privat',
    );
    expect(ticket.filename, 'QueueB_Nota_Reservasi_PD_001_2_2026-11-03.pdf');
    expect(ticket.filename, isNot(contains('Nama Privat')));
  });
}

// QBR1 hanya bukti reservasi: tidak boleh dianggap token check-in SQ1.
// Kode persisten hanya dapat dicetak untuk tiket DIPESAN dengan format valid.
