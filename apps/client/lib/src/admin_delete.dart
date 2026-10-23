import 'package:flutter/material.dart';

import 'api.dart';
import 'config.dart';
import 'widgets.dart';

enum AdminDeleteResult { deleted, deactivate }

Future<AdminDeleteResult?> showAdminDelete(
  BuildContext context,
  QueueApi api,
  String path,
  Json row, {
  String? name,
}) => showDialog<AdminDeleteResult>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _AdminDeleteDialog(
    api: api,
    path: path,
    row: row,
    name: name ?? label(row),
  ),
);

class AdminDeleteButton extends StatelessWidget {
  const AdminDeleteButton({super.key, required this.onPressed});
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Hapus',
    constraints: const BoxConstraints.tightFor(width: 44, height: 44),
    padding: EdgeInsets.zero,
    onPressed: onPressed,
    icon: const Icon(Icons.delete_outline, color: Color(0xffb3261e), size: 20),
  );
}

class _AdminDeleteDialog extends StatefulWidget {
  const _AdminDeleteDialog({
    required this.api,
    required this.path,
    required this.row,
    required this.name,
  });
  final QueueApi api;
  final String path, name;
  final Json row;
  @override
  State<_AdminDeleteDialog> createState() => _AdminDeleteDialogState();
}

class _AdminDeleteDialogState extends State<_AdminDeleteDialog> {
  final confirmation = TextEditingController();
  bool busy = false;
  String? error;
  bool conflict = false;
  bool get important => ['/layanan', '/dokter'].contains(widget.path);
  String get expected {
    final code = '${widget.row['kode'] ?? ''}'.trim();
    return code.isNotEmpty ? code : '${widget.row['nama'] ?? ''}'.trim();
  }

  @override
  void dispose() {
    confirmation.dispose();
    super.dispose();
  }

  Future<void> remove() async {
    if (busy || (important && confirmation.text.trim() != expected)) {
      return;
    }
    setState(() {
      busy = true;
      error = null;
      conflict = false;
    });
    try {
      await widget.api.request(
        'DELETE',
        '${widget.path}/${widget.row['id']}/permanen',
      );
      if (mounted) {
        Navigator.pop(context, AdminDeleteResult.deleted);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          error = '$e';
          conflict = e is ApiException && e.status == 409;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      title: const Text('Hapus Data?'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Apakah Anda yakin ingin menghapus ${widget.name}? Tindakan ini tidak dapat dibatalkan.',
              ),
              if (widget.path == '/perangkat-display')
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text(
                    'Akses, kode aktivasi, dan koneksi perangkat akan dicabut.',
                  ),
                ),
              if (important)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: TextField(
                    controller: confirmation,
                    enabled: !busy,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: 'Konfirmasi kode/nama',
                      helperText: 'Ketik persis: $expected',
                    ),
                  ),
                ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Notice(error!, error: true),
                ),
              if (busy)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: LinearProgressIndicator(),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        if (conflict && widget.row['aktif'] == true)
          TextButton(
            onPressed: () =>
                Navigator.pop(context, AdminDeleteResult.deactivate),
            child: const Text('Gunakan Nonaktifkan'),
          ),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xffb3261e),
            foregroundColor: Colors.white,
          ),
          onPressed: busy || (important && confirmation.text.trim() != expected)
              ? null
              : remove,
          icon: const Icon(Icons.delete_outline, size: 18),
          label: const Text('Hapus Permanen'),
        ),
      ],
    ),
  );
}
