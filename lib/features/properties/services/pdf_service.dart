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
    _fontCache ??= () async {
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

    return await _fontCache!;
  }

  static Future<Uint8List> generatePropertyPdf({
    required PropertyModel property,
    required SettingsState settings,
  }) async {
    // Try to load raw font bytes — if available we offload full PDF build to an isolate
    try {
      final fontBd = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
      final fontBoldBd = await rootBundle.load('assets/fonts/Cairo-Bold.ttf');
      final fontBytes = fontBd.buffer.asUint8List();
      final fontBoldBytes = fontBoldBd.buffer.asUint8List();

      final args = {
        'property': property.toMap(),
        'images': property.images,
        'settings': {
          'officeName': settings.officeName,
          'officePhone': settings.officePhone,
        },
        'font': fontBytes,
        'fontBold': fontBoldBytes,
      };

      final result =
          await Isolate.run<Uint8List>(() => _generatePdfAsync(args));
      return result;
    } catch (_) {
      // If loading font bytes failed, fall back to in-isolate-light approach
    }

    // Fallback: build PDF in current isolate using cached pw.Fonts (slower but safer)
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

  // Full PDF generation entry point for running inside an isolate.
  // Expects a Map with keys: 'property' (Map), 'images' (List<String>),
  // 'settings' (Map), 'font' (Uint8List), 'fontBold' (Uint8List)
  static Future<Uint8List> _generatePdfAsync(Map args) async {
    final prop = Map<String, dynamic>.from(args['property'] as Map);
    final images = List<String>.from(args['images'] as List);
    final settings = Map<String, dynamic>.from(args['settings'] as Map);

    final fontBytes = args['font'] as Uint8List;
    final fontBoldBytes = args['fontBold'] as Uint8List;

    final arabicFont = pw.Font.ttf(ByteData.view(fontBytes.buffer));
    final arabicBoldFont = pw.Font.ttf(ByteData.view(fontBoldBytes.buffer));

    final isOffer =
        (prop['entry_type'] as String?)?.toEntryType() == EntryType.offer;

    final pdf = pw.Document();

    // build image widgets after processing inside this isolate
    final imageWidgets = <pw.Widget>[];
    if (isOffer && images.isNotEmpty) {
      for (final path in images) {
        try {
          final bytes = File(path).readAsBytesSync();
          final image = img.decodeImage(bytes);
          if (image == null) continue;
          final resized =
              image.width > 800 ? img.copyResize(image, width: 800) : image;
          final jpeg = Uint8List.fromList(img.encodeJpg(resized, quality: 65));
          imageWidgets.add(
            pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 20),
              child: pw.Center(
                child: pw.Image(pw.MemoryImage(jpeg),
                    fit: pw.BoxFit.contain, width: 450),
              ),
            ),
          );
        } catch (_) {
          // ignore individual image failures
        }
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
                  if ((settings['officeName'] as String).isNotEmpty) ...[
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
                          pw.Text(settings['officeName'] as String,
                              style: pw.TextStyle(
                                  font: arabicBoldFont, fontSize: 16)),
                          if ((settings['officePhone'] as String).isNotEmpty)
                            pw.Text(
                                'هاتف: ${settings['officePhone'] as String}',
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
                  _buildPdfRow('نوع السجل',
                      (prop['entry_type'] as String).toEntryType().label),
                  _buildPdfRow(
                      'نوع العقار', (prop['propertyType'] as String?) ?? ''),
                  _buildPdfRow(isOffer ? 'نوع الإعلان' : 'نوع المطلوب',
                      (prop['adType'] as String?) ?? ''),
                  _buildPdfRow('المحافظة', (prop['province'] as String?) ?? ''),
                  if ((prop['region'] as String?)?.isNotEmpty ?? false)
                    _buildPdfRow('المنطقة', (prop['region'] as String?) ?? ''),
                  if ((prop['area'] as num?) != null &&
                      (prop['area'] as num) > 0)
                    _buildPdfRow('المساحة', '${prop['area']} م²'),
                  if ((prop['rooms'] as int?) != null &&
                      (prop['rooms'] as int) > 0)
                    _buildPdfRow('عدد الغرف', '${prop['rooms']}'),
                  if ((prop['price'] as num?) != null &&
                      (prop['price'] as num) > 0)
                    _buildPdfRow(isOffer ? 'السعر' : 'الميزانية',
                        '${prop['price']} ${prop['currency'] ?? ''}'),
                  if (isOffer) ...[
                    if ((prop['finishingLevel'] as String?)?.isNotEmpty ??
                        false)
                      _buildPdfRow(
                          'الإكساء', (prop['finishingLevel'] as String?) ?? ''),
                    if ((prop['floor'] as String?)?.isNotEmpty ?? false)
                      _buildPdfRow('الطابق', (prop['floor'] as String?) ?? ''),
                    if ((prop['facade'] as String?)?.isNotEmpty ?? false)
                      _buildPdfRow(
                          'الواجهة', (prop['facade'] as String?) ?? ''),
                    if ((prop['ownershipType'] as String?)?.isNotEmpty ?? false)
                      _buildPdfRow(
                          'الملكية', (prop['ownershipType'] as String?) ?? ''),
                    _buildPdfRow('الحالة', (prop['status'] as String?) ?? ''),
                  ],
                  if ((prop['notes'] as String?)?.isNotEmpty ?? false) ...[
                    pw.SizedBox(height: 15),
                    pw.Text('ملاحظات:',
                        style:
                            pw.TextStyle(font: arabicBoldFont, fontSize: 14)),
                    pw.Text((prop['notes'] as String?) ?? '',
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

    return await pdf.save();
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
