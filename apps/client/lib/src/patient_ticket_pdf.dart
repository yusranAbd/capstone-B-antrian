import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// Data cetak yang aman: tanpa ID teknis dan token QR check-in sementara.
class PatientTicketPdfData {
  const PatientTicketPdfData({
    required this.queueNumber,
    required this.serviceName,
    required this.status,
    required this.serviceDate,
    required this.patientName,
    this.consultationTime,
    this.doctorName,
    this.roomName,
    this.reservationType,
    this.reservationCode,
  });

  final String queueNumber;
  final String serviceName;
  final String status;
  final String serviceDate;
  final String patientName;
  final String? consultationTime;
  final String? doctorName;
  final String? roomName;
  final String? reservationType;
  // Kode tiket acak yang sudah ada di DB, bukan token QR check-in SQ1.
  final String? reservationCode;

  String? get receiptQrPayload {
    final code = reservationCode?.trim() ?? '';
    if (status.toUpperCase() != 'DIPESAN' ||
        !RegExp(r'^TK[A-F0-9]{24}$').hasMatch(code)) {
      return null;
    }
    return 'QBR1.$code';
  }

  String get filename {
    String safe(String value) {
      final cleaned = value.trim().replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      return cleaned.isEmpty ? 'tiket' : cleaned;
    }

    return 'QueueB_Nota_Reservasi_${safe(queueNumber)}_${safe(serviceDate)}.pdf';
  }
}

/// Kertas nota termal 80 mm, bukan A4/A5.
/// Bukti ini tidak mengandung token check-in yang akan kedaluwarsa.
class PatientTicketPdf {
  const PatientTicketPdf._();

  static const double paperWidthMm = 80;

  static PdfPageFormat receiptFormat(PatientTicketPdfData ticket) {
    final optional = [
      ticket.consultationTime,
      ticket.doctorName,
      ticket.roomName,
      ticket.reservationType,
    ].where((value) => value != null && value.trim().isNotEmpty).length;
    // Tinggi mengikuti jumlah informasi, dengan cadangan untuk teks panjang.
    final longFields = [
      ticket.serviceName,
      ticket.serviceDate,
      ticket.patientName,
      ticket.doctorName ?? '',
      ticket.roomName ?? '',
    ].where((value) => value.length > 29).length;
    // QR reservasi membutuhkan sekitar 50 mm ruang vertikal tambahan.
    final heightMm = 103.0 + (optional * 9.0) + (longFields * 6.0) +
        (ticket.receiptQrPayload == null ? 0.0 : 52.0);
    return PdfPageFormat(
      paperWidthMm * PdfPageFormat.mm,
      heightMm * PdfPageFormat.mm,
    );
  }

  static Future<Uint8List> build(
    PatientTicketPdfData ticket, {
    PdfPageFormat? pageFormat,
  }) async {
    final pdf = pw.Document(
      title: 'Nota Bukti Reservasi QueueB Hospital',
      author: 'QueueB Hospital',
      subject: 'Bukti reservasi. Tidak berlaku untuk QR check-in.',
    );
    const ink = PdfColor.fromInt(0xff1c2541);
    const muted = PdfColor.fromInt(0xff606b80);
    const divider = PdfColor.fromInt(0xffb4bdc9);
    final format = pageFormat ?? receiptFormat(ticket);

    pw.Widget fact(String label, String value) => pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 6),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(label.toUpperCase(),
              style: const pw.TextStyle(fontSize: 7, color: muted)),
          pw.SizedBox(height: 2),
          pw.Text(value,
              style: pw.TextStyle(
                fontSize: 9,
                color: ink,
                fontWeight: pw.FontWeight.bold,
              )),
        ],
      ),
    );

    final details = <(String, String)>[
      ('Tanggal pelayanan', ticket.serviceDate),
      if (ticket.consultationTime case final value? when value.trim().isNotEmpty)
        ('Jam konsultasi', value),
      if (ticket.doctorName case final value? when value.trim().isNotEmpty)
        ('Dokter', value),
      if (ticket.roomName case final value? when value.trim().isNotEmpty)
        ('Ruang / Loket', value),
      if (ticket.patientName.trim().isNotEmpty) ('Pasien', ticket.patientName),
      if (ticket.reservationType case final value? when value.trim().isNotEmpty)
        ('Jenis reservasi', value),
    ];

    pdf.addPage(
      pw.Page(
        pageFormat: format,
        margin: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Text('QueueB Hospital',
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                    fontSize: 13, color: ink, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 3),
            pw.Text('BUKTI RESERVASI',
                textAlign: pw.TextAlign.center,
                style: const pw.TextStyle(fontSize: 8, color: muted)),
            pw.SizedBox(height: 8),
            pw.Divider(color: divider, thickness: .7),
            pw.SizedBox(height: 5),
            pw.Text(ticket.queueNumber,
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                    fontSize: 24, color: ink, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 2),
            pw.Text(ticket.serviceName,
                textAlign: pw.TextAlign.center,
                style: const pw.TextStyle(fontSize: 9, color: muted)),
            pw.SizedBox(height: 4),
            pw.Text('STATUS: ${ticket.status.toUpperCase()}',
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                    fontSize: 9, color: ink, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 7),
            pw.Divider(color: divider, thickness: .7),
            pw.SizedBox(height: 7),
            for (final detail in details) fact(detail.$1, detail.$2),
            pw.SizedBox(height: 2),
            pw.Divider(color: divider, thickness: .7),
            pw.SizedBox(height: 6),
            if (ticket.receiptQrPayload case final payload?) ...[
              pw.Center(
                child: pw.BarcodeWidget(
                  barcode: pw.Barcode.qrCode(),
                  data: payload,
                  width: 126,
                  height: 126,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text('QR BUKTI RESERVASI',
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(fontSize: 8, color: ink, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 3),
              pw.Text('Bukan QR check-in. Petugas memverifikasi bukti; '
                  'check-in tetap mengikuti prosedur pada hari pelayanan.',
                  textAlign: pw.TextAlign.center,
                  style: const pw.TextStyle(fontSize: 7.5, color: muted)),
            ] else ...[
              pw.Text('QR BUKTI RESERVASI TIDAK TERSEDIA',
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(fontSize: 8, color: ink, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 4),
              pw.Text('Tunjukkan nomor antrean kepada petugas. '
                  'QR check-in aktif diterbitkan sesuai aturan pelayanan.',
                  textAlign: pw.TextAlign.center,
                  style: const pw.TextStyle(fontSize: 7.5, color: muted)),
            ],
            pw.SizedBox(height: 7),
            pw.Text('Terima kasih',
                textAlign: pw.TextAlign.center,
                style: const pw.TextStyle(fontSize: 8, color: muted)),
          ],
        ),
      ),
    );
    return pdf.save();
  }

  static Future<bool> save(PatientTicketPdfData ticket) async =>
      Printing.sharePdf(bytes: await build(ticket), filename: ticket.filename);

  static Future<bool> print(PatientTicketPdfData ticket) => Printing.layoutPdf(
    name: ticket.filename,
    format: receiptFormat(ticket),
    dynamicLayout: false,
    onLayout: (_) => build(ticket),
  );
}
