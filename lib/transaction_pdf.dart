import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:public_file_saver/public_file_saver.dart';

import 'share_or_download_helper.dart';

String _pdfRp(num value) {
  final text = value.round().toString();
  return 'Rp ${text.replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')}';
}

String _pdfKg(num value) {
  final rounded = (value * 100).round() / 100;
  return '${rounded.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '')} kg';
}

String _pdfDate(dynamic raw) {
  if (raw == null) return '-';
  final date = DateTime.tryParse(raw.toString());
  if (date == null) return raw.toString();
  final local = date.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(local.day)}/${two(local.month)}/${local.year} ${two(local.hour)}:${two(local.minute)}';
}

List<Map<String, dynamic>> _pdfItems(dynamic raw) {
  if (raw is List) {
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }
  if (raw is Map) {
    return raw.entries
        .map((e) => Map<String, dynamic>.from(e.value as Map))
        .toList();
  }
  return [];
}

Future<void> downloadTransactionPdf({
  required BuildContext context,
  required Map<String, dynamic> tx,
  String? txId,
}) async {
  final isSetor = tx['tipe']?.toString() == 'Setor';
  final total = (tx['total_rp'] as num?)?.toDouble() ?? 0;
  final items = _pdfItems(tx['items']);

  final doc = pw.Document(
    title: 'Detail Transaksi Resik For School',
    author: 'Resik For School',
  );

  final green = PdfColor.fromInt(0xFF23524E);
  final lightGreen = PdfColor.fromInt(0xFFEAF5F2);

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(40),
      build: (context) => [
        pw.Container(
          padding: const pw.EdgeInsets.only(bottom: 16),
          decoration: pw.BoxDecoration(
            border: pw.Border(
              bottom: pw.BorderSide(color: green, width: 2),
            ),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'RESIK FOR SCHOOL',
                    style: pw.TextStyle(
                      fontSize: 22,
                      fontWeight: pw.FontWeight.bold,
                      color: green,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'Detail Transaksi',
                    style: const pw.TextStyle(fontSize: 11),
                  ),
                ],
              ),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: pw.BoxDecoration(
                  color: lightGreen,
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Text(
                  isSetor ? 'SETOR' : 'PENARIKAN',
                  style: pw.TextStyle(
                    color: green,
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 10,
                  ),
                ),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 24),
        pw.Text(
          'Informasi Transaksi',
          style: pw.TextStyle(
            fontSize: 14,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 10),
        pw.Table(
          columnWidths: const {
            0: pw.FixedColumnWidth(130),
            1: pw.FlexColumnWidth(),
          },
          children: [
            _pdfRow('Tanggal', _pdfDate(tx['tanggal'])),
            _pdfRow('Jenis Transaksi', isSetor ? 'Setor Sampah' : 'Penarikan Saldo'),
            _pdfRow('Admin Pencatat', tx['admin_pencatat']?.toString() ?? '-'),
            if (txId != null) _pdfRow('ID Transaksi', txId),
          ],
        ),
        pw.SizedBox(height: 22),
        if (isSetor) ...[
          pw.Text(
            'Rincian Sampah',
            style: pw.TextStyle(
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 10),
          if (items.isNotEmpty)
            pw.TableHelper.fromTextArray(
              headers: const ['Kategori', 'Berat'],
              data: items.map((item) {
                final berat = (item['berat_kg'] as num?)?.toDouble() ?? 0;
                return [
                  item['kategori']?.toString() ?? '-',
                  _pdfKg(berat),
                ];
              }).toList(),
              headerStyle: pw.TextStyle(
                color: PdfColors.white,
                fontWeight: pw.FontWeight.bold,
              ),
              headerDecoration: pw.BoxDecoration(color: green),
              cellStyle: const pw.TextStyle(fontSize: 10),
              cellPadding: const pw.EdgeInsets.all(8),
              border: pw.TableBorder.all(
                color: PdfColors.grey300,
                width: 0.5,
              ),
            )
          else
            pw.Text(
              '${tx['kategori'] ?? '-'} — ${_pdfKg((tx['berat_kg'] as num?)?.toDouble() ?? 0)}',
              style: const pw.TextStyle(fontSize: 11),
            ),
          pw.SizedBox(height: 24),
        ],
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(16),
          decoration: pw.BoxDecoration(
            color: lightGreen,
            borderRadius: pw.BorderRadius.circular(10),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                isSetor ? 'Nilai Setoran' : 'Nominal Penarikan',
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                _pdfRp(total),
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                  color: green,
                ),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 34),
        pw.Text(
          'Dokumen ini dibuat otomatis oleh Resik For School.',
          style: const pw.TextStyle(
            fontSize: 9,
            color: PdfColors.grey600,
          ),
        ),
      ],
    ),
  );

  final bytes = await doc.save();
  final safeId = (txId ?? DateTime.now().millisecondsSinceEpoch.toString())
      .replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');

  final fileName = 'transaksi-$safeId.pdf';

  // Di browser HP yang support Web Share API dengan file (Android
  // Chrome, iOS Safari), langsung buka share sheet asli (WA, Telegram,
  // dll) — nasabah/admin gak perlu bingung nyari PDF-nya di folder
  // Download. Kalau gak support (browser desktop, atau app native
  // Android/iOS), fallback ke jalur lama lewat public_file_saver.
  if (canShareFile(bytes, fileName, mimeType: 'application/pdf')) {
    final shared = await shareFile(
      bytes,
      fileName,
      mimeType: 'application/pdf',
      title: 'Detail Transaksi',
      text: 'Detail transaksi Resik For School',
    );
    if (shared) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PDF transaksi berhasil dibagikan.')),
        );
      }
      return;
    }
    // shared == false: user sengaja batal di share sheet — gak usah
    // fallback ke simpan file atau kasih pesan error, biar gak kesan
    // aneh (tiba-tiba ke-download padahal tadi udah dibatalin).
    return;
  }

  try {
    await PublicFileSaver().saveBytes(
      bytes: bytes,
      fileName: fileName,
      mimeType: 'application/pdf',
      subDir: 'Resik For School',
    );

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PDF transaksi berhasil disimpan.')),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal menyimpan PDF: $e')),
      );
    }
  }
}

pw.TableRow _pdfRow(String label, String value) {
  return pw.TableRow(
    children: [
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 6),
        child: pw.Text(
          label,
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
        ),
      ),
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 6),
        child: pw.Text(value, style: const pw.TextStyle(fontSize: 10)),
      ),
    ],
  );
}

class TransactionDetailPage extends StatelessWidget {
  final Map<String, dynamic> tx;
  final String? txId;

  const TransactionDetailPage({
    super.key,
    required this.tx,
    this.txId,
  });

  @override
  Widget build(BuildContext context) {
    final isSetor = tx['tipe']?.toString() == 'Setor';
    final total = (tx['total_rp'] as num?)?.toDouble() ?? 0;
    final items = _pdfItems(tx['items']);

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F6),
      appBar: AppBar(
        title: const Text('Detail Transaksi'),
        actions: [
          IconButton(
            tooltip: 'Bagikan PDF',
            icon: const Icon(Icons.picture_as_pdf_outlined),
            onPressed: () => downloadTransactionPdf(
              context: context,
              tx: tx,
              txId: txId,
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 30),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: isSetor
                      ? Colors.green.withOpacity(.1)
                      : Colors.red.withOpacity(.1),
                  child: Icon(
                    isSetor
                        ? Icons.arrow_downward_rounded
                        : Icons.arrow_upward_rounded,
                    color: isSetor ? Colors.green : Colors.red,
                    size: 30,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  isSetor ? 'Setor Sampah' : 'Penarikan Saldo',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _pdfDate(tx['tanggal']),
                  style: TextStyle(color: Colors.grey.shade600),
                ),
                const SizedBox(height: 14),
                Text(
                  '${isSetor ? '+' : '-'} ${_pdfRp(total)}',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: isSetor ? Colors.green.shade700 : Colors.red.shade700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _detailCard(
            title: 'Informasi',
            children: [
              _detailRow('Tanggal', _pdfDate(tx['tanggal'])),
              _detailRow(
                'Jenis',
                isSetor ? 'Setor Sampah' : 'Penarikan Saldo',
              ),
              _detailRow(
                'Admin',
                tx['admin_pencatat']?.toString() ?? '-',
              ),
              if (txId != null) _detailRow('ID Transaksi', txId!),
            ],
          ),
          if (isSetor) ...[
            const SizedBox(height: 14),
            _detailCard(
              title: 'Rincian Sampah',
              children: items.isNotEmpty
                  ? items.map((item) {
                      final berat =
                          (item['berat_kg'] as num?)?.toDouble() ?? 0;
                      return _detailRow(
                        item['kategori']?.toString() ?? '-',
                        _pdfKg(berat),
                      );
                    }).toList()
                  : [
                      _detailRow(
                        tx['kategori']?.toString() ?? '-',
                        _pdfKg(
                          (tx['berat_kg'] as num?)?.toDouble() ?? 0,
                        ),
                      ),
                    ],
            ),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () => downloadTransactionPdf(
              context: context,
              tx: tx,
              txId: txId,
            ),
            icon: const Icon(Icons.ios_share_rounded),
            label: const Text('Bagikan Detail sebagai PDF'),
          ),
        ],
      ),
    );
  }

  Widget _detailCard({
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Text(
              label,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
          ),
          Expanded(
            flex: 6,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
