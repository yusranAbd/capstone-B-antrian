import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'config.dart';
import 'mobile_ui.dart';

bool validCheckInQr(String value) =>
    RegExp(r'^SQ1\.[A-Za-z0-9_-]{43}$').hasMatch(value);

class StaffScanResult extends StatelessWidget {
  const StaffScanResult({super.key, required this.result});
  final Json result;
  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('staff-qr-result'),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: QueueBStyle.mint,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.check_circle, color: QueueBStyle.success),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${result['nomorAntrean']} · ${result['status']}',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: QueueBStyle.darkTeal,
                ),
              ),
              if (result['namaPasien'] != null) Text('${result['namaPasien']}'),
              if (result['namaPoliklinik'] != null)
                Text(
                  '${result['namaPoliklinik']}',
                  style: const TextStyle(fontSize: 12),
                ),
              Text(
                result['sudahTerdaftar'] == true
                    ? 'Sudah terdaftar dalam antrean.'
                    : 'Check-in berhasil. Pasien masuk antrean.',
                style: const TextStyle(fontSize: 12, color: QueueBStyle.muted),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// Camera stays ready for a different patient. Same QR is suppressed until an
/// explicit retry; no raw payload is persisted, logged, or rendered in results.
class StaffQrScanner extends StatefulWidget {
  const StaffQrScanner({super.key, required this.onScan, this.previewBuilder});
  final Future<Json> Function(String) onScan;
  final Widget Function(ValueChanged<String>)? previewBuilder;
  @override
  State<StaffQrScanner> createState() => _StaffQrScannerState();
}

class _StaffQrScannerState extends State<StaffQrScanner>
    with WidgetsBindingObserver {
  final controller = MobileScannerController(formats: [BarcodeFormat.qrCode]);
  bool processing = false;
  String? lastPayload, error;
  Json? result;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (widget.previewBuilder != null ||
        !controller.value.hasCameraPermission) {
      return;
    }
    unawaited(cameraLifecycle(state));
  }

  Future<void> cameraLifecycle(AppLifecycleState state) async {
    try {
      if (state == AppLifecycleState.resumed) {
        await controller.start();
      } else {
        await controller.stop();
      }
    } catch (_) {
      if (mounted && state == AppLifecycleState.resumed) {
        setState(
          () => error = 'Kamera belum dapat dibuka kembali. Tutup lalu gunakan Input Manual.',
        );
      }
    }
  }

  Future<void> detected(String raw) async {
    if (!mounted || processing || raw == lastPayload || !validCheckInQr(raw)) {
      return;
    }
    setState(() {
      processing = true;
      lastPayload = raw;
      result = null;
      error = null;
    });
    try {
      final value = await widget.onScan(raw);
      if (mounted) {
        setState(() => result = value);
        // Audio is optional and must never hold the scanner's request lock.
        unawaited(
          SystemSound.play(SystemSoundType.click).catchError((Object _) {}),
        );
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => processing = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !processing,
    child: AlertDialog(
      title: const Text('QR Check-in Otomatis'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 230,
                child:
                    widget.previewBuilder?.call(detected) ??
                    MobileScanner(
                      controller: controller,
                      onDetect: (capture) {
                        for (final barcode in capture.barcodes) {
                          final raw = barcode.rawValue;
                          if (raw != null && validCheckInQr(raw)) {
                            detected(raw);
                            break;
                          }
                        }
                      },
                      errorBuilder: (_, _) => const Center(
                        child: Text(
                          'Kamera tidak tersedia atau izin ditolak. Tutup kamera lalu gunakan Input Manual.',
                        ),
                      ),
                    ),
              ),
              const SizedBox(height: 12),
              if (processing) const LinearProgressIndicator(),
              if (result != null) StaffScanResult(result: result!),
              if (error != null)
                Text(error!, style: const TextStyle(color: QueueBStyle.danger)),
              const SizedBox(height: 8),
              const Text(
                'Arahkan ke QR pasien berikutnya. QR yang sama tidak dikirim berulang.',
                style: TextStyle(fontSize: 12, color: QueueBStyle.muted),
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (error != null)
          TextButton(
            onPressed: processing
                ? null
                : () => setState(() {
                    lastPayload = null;
                    error = null;
                  }),
            child: const Text('Coba pindai lagi'),
          ),
        TextButton(
          onPressed: processing ? null : () => Navigator.pop(context),
          child: const Text('Tutup'),
        ),
      ],
    ),
  );
}
