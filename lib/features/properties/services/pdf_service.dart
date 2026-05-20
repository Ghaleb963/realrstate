import 'dart:isolate';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:image/image.dart' as img;
import '../models/property_model.dart';
import '../../../core/constants/app_constants.dart';
import '../../settings/providers/settings_provider.dart';

class PdfService {
  static Future<List<pw.Font>>? _fontCache;

  static Future<List<pw.Font>> _loadFonts() async {
    if (_fontCache != null) return _fontCache!;

    _fontCache = () async {
      try {
        final fontData =
            await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
        final fontBoldData =
            await rootBundle.load('assets/fonts/Cairo-Bold.ttf');
        return [pw.Font.ttf(fontData), pw.Font.ttf(fontBoldData)];
      } catch (_) {
        final regular = await PdfGoogleFonts.notoSansArabicRegular();
        final bold = await PdfGoogleFonts.notoSansArabicBold();
        return [regular, bold];
      }
    }();

    return _fontCache!;
  }

  static Future<Uint8List> generatePropertyPdf({
    required PropertyModel property,
    required SettingsState settings,
  }) async {
    final fonts = await _loadFonts();
    final arabicFont = fonts[0];
    final arabicBoldFont = fonts[1];

    final isOffer = property.entryType == EntryType.offer;
    final pdf = pw.Document();

    final imageWidgets = <pw.Widget>[];
    if (isOffer && property.images.isNotEmpty) {
      final processedImages = await _processImages(property.images);

      for (final processed in processedImages) {
        if (processed == null) continue;
        imageWidgets.add(
          pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 20),
            child: pw.Center(
              child: pw.Image(
                pw.MemoryImage(processed),
                fit: pw.BoxFit.contain,
                width: 450,
              ),
            ),
          ),
        );
      }
    }

    final entryPdfColor = isOffer ? PdfColors.green900 : PdfColors.orange900;
    final dividerColor = isOffer ? PdfColors.green : PdfColors.orange;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        theme: pw.ThemeData.withFont(base: arabicFont, bold: arabicBoldFont),
        build: (pw.Context context) {
          return [
            pw.Directionality(
              textDirection: pw.TextDirection.rtl,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        isOffer ? 'تقرير العقار الاحترافي' : 'تقرير طلب عقار',
                        style: pw.TextStyle(
                            font: arabicBoldFont,
                            fontSize: 22,
                            color: entryPdfColor),
                      ),
                      pw.Text(
                        'تاريخ التصدير: ${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}',
                        style: const pw.TextStyle(
                            fontSize: 10, color: PdfColors.grey700),
                      ),
                    ],
                  ),
                  pw.Divider(color: dividerColor, thickness: 2),
                  pw.SizedBox(height: 10),
                  if (settings.officeName.isNotEmpty) ...[
                    pw.Container(
                      padding: const pw.EdgeInsets.all(10),
                      decoration: pw.BoxDecoration(
                        color: PdfColors.grey100,
                        border: pw.Border(
                          right: pw.BorderSide(color: dividerColor, width: 4),
                        ),
                      ),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(settings.officeName,
                              style: pw.TextStyle(
                                  font: arabicBoldFont, fontSize: 16)),
                          if (settings.officePhone.isNotEmpty)
                            pw.Text('هاتف: ${settings.officePhone}',
                                style: const pw.TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                    pw.SizedBox(height: 20),
                  ],
                  pw.Text(
                    isOffer ? 'تفاصيل ومواصفات العقار' : 'تفاصيل طلب الزبون',
                    style: pw.TextStyle(font: arabicBoldFont, fontSize: 18),
                  ),
                  pw.SizedBox(height: 10),
                  _buildPdfRow('نوع السجل', property.entryType.label),
                  _buildPdfRow('نوع العقار', property.propertyType),
                  _buildPdfRow(
                      isOffer ? 'نوع الإعلان' : 'نوع المطلوب', property.adType),
                  _buildPdfRow('المحافظة', property.province),
                  if (property.region.isNotEmpty)
                    _buildPdfRow('المنطقة', property.region),
                  if (property.area > 0)
                    _buildPdfRow('المساحة', '${property.area} م²'),
                  if (property.rooms > 0)
                    _buildPdfRow('عدد الغرف', '${property.rooms}'),
                  if (property.price > 0)
                    _buildPdfRow(isOffer ? 'السعر' : 'الميزانية',
                        '${property.price} ${property.currency}'),
                  if (isOffer) ...[
                    if (property.finishingLevel.isNotEmpty)
                      _buildPdfRow('الإكساء', property.finishingLevel),
                    if (property.floor.isNotEmpty)
                      _buildPdfRow('الطابق', property.floor),
                    if (property.facade.isNotEmpty)
                      _buildPdfRow('الواجهة', property.facade),
                    if (property.ownershipType.isNotEmpty)
                      _buildPdfRow('الملكية', property.ownershipType),
                    _buildPdfRow('الحالة', property.status),
                  ],
                  if (property.notes.isNotEmpty) ...[
                    pw.SizedBox(height: 15),
                    pw.Text('ملاحظات:',
                        style:
                            pw.TextStyle(font: arabicBoldFont, fontSize: 14)),
                    pw.Text(property.notes,
                        style: const pw.TextStyle(fontSize: 12)),
                  ],
                  if (imageWidgets.isNotEmpty) ...[
                    pw.NewPage(),
                    pw.Text('صور العقار',
                        style:
                            pw.TextStyle(font: arabicBoldFont, fontSize: 18)),
                    pw.SizedBox(height: 15),
                    ...imageWidgets,
                  ],
                ],
              ),
            ),
          ];
        },
      ),
    );

    return pdf.save();
  }

  static Future<List<Uint8List?>> _processImages(List<String> paths) async {
    return await Isolate.run(() => _processImagesSync(paths));
  }

  static List<Uint8List?> _processImagesSync(List<String> paths) {
    final results = <Uint8List?>[];
    for (final path in paths) {
      try {
        final bytes = File(path).readAsBytesSync();
        final image = img.decodeImage(bytes);
        if (image == null) {
          results.add(null);
          continue;
        }
        final resized =
            image.width > 800 ? img.copyResize(image, width: 800) : image;
        results.add(Uint8List.fromList(img.encodeJpg(resized, quality: 65)));
      } catch (_) {
        results.add(null);
      }
    }
    return results;
  }

  static pw.Widget _buildPdfRow(String title, String value) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 5),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: PdfColors.grey200, width: 0.5),
        ),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(title,
              style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold, color: PdfColors.grey700)),
          pw.Text(value, style: const pw.TextStyle(color: PdfColors.black)),
        ],
      ),
    );
  }
}
