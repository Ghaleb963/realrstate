import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/property_model.dart';
import '../providers/property_provider.dart';
import '../services/pdf_service.dart';
import 'add_property_view.dart';
import 'package:printing/printing.dart';
import '../../settings/providers/settings_provider.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/status_helpers.dart';
import '../../../core/widgets/app_loading_dialog.dart';
import '../widgets/property_detail_sections.dart';

class PropertyDetailView extends ConsumerStatefulWidget {
  final PropertyModel property;
  const PropertyDetailView({super.key, required this.property});

  @override
  ConsumerState<PropertyDetailView> createState() => _PropertyDetailViewState();
}

class _PropertyDetailViewState extends ConsumerState<PropertyDetailView> {
  late PropertyModel _property;
  bool get _isOffer => _property.entryType == EntryType.offer;

  @override
  void initState() {
    super.initState();
    _property = widget.property;
  }

  Future<void> _generateAndSharePdf() async {
    final settings = ref.read(settingsProvider);
    if (!mounted) return;
    showAppLoadingDialog(context, message: 'جاري إنشاء PDF...');

    try {
      final bytes = await PdfService.generatePropertyPdf(
        property: _property,
        settings: settings,
      );

      if (mounted) Navigator.pop(context);
      await Printing.sharePdf(
        bytes: bytes,
        filename: '${_isOffer ? "Property" : "Request"}_${_property.id}.pdf',
      );
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في إنشاء PDF: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text(_isOffer
            ? 'هل تريد حذف هذا العقار نهائياً؟'
            : 'هل تريد حذف هذا الطلب نهائياً؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.accentRed),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await ref.read(propertyProvider.notifier).deleteProperty(_property.id!);
      if (mounted) Navigator.pop(context);
    }
  }

  Future<void> _showStatusSheet() async {
    final newStatus = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppTheme.sp16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: AppTheme.sp16),
                  decoration: BoxDecoration(
                    color: AppTheme.borderMedium,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(bottom: AppTheme.sp12),
                child: Text(
                  'تغيير حالة العقار',
                  style: TextStyle(
                    fontSize: AppTheme.fontLg,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              ...AppConstants.statusList.map(
                (s) => ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.sp24,
                  ),
                  leading: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: StatusHelpers.color(s),
                      shape: BoxShape.circle,
                    ),
                  ),
                  title: Text(s),
                  trailing: _property.status == s
                      ? const Icon(
                          Icons.check_rounded,
                          color: AppTheme.accentGreen,
                          size: 20,
                        )
                      : null,
                  onTap: () => Navigator.pop(context, s),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (newStatus != null && newStatus != _property.status && mounted) {
      await ref
          .read(propertyProvider.notifier)
          .updatePropertyStatus(_property.id!, newStatus);
      setState(() => _property = _property.copyWith(status: newStatus));
    }
  }

  Future<void> _openEdit() async {
    final updated = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AddPropertyView(existingProperty: _property),
      ),
    );
    if (updated == true && mounted) {
      final fresh = ref
          .read(propertyProvider)
          .firstWhere((p) => p.id == _property.id, orElse: () => _property);
      setState(() => _property = fresh);
    }
  }

  @override
  Widget build(BuildContext context) {
    final entryColor = _isOffer ? AppTheme.accentGreen : AppTheme.accentAmber;

    return Scaffold(
      backgroundColor: AppTheme.bgPage,
      appBar: AppBar(
        backgroundColor: AppTheme.bgPage,
        title: Text(_isOffer ? 'تفاصيل العقار' : 'تفاصيل الطلب'),
        actions: [
          AppBarAction(
            icon: Icons.picture_as_pdf_rounded,
            tooltip: 'تصدير PDF',
            onTap: _generateAndSharePdf,
          ),
          AppBarAction(
            icon: Icons.edit_rounded,
            tooltip: 'تعديل',
            onTap: _openEdit,
          ),
          AppBarAction(
            icon: Icons.delete_rounded,
            tooltip: 'حذف',
            onTap: _confirmDelete,
            color: AppTheme.accentRed.withValues(alpha: 0.8),
          ),
          const SizedBox(width: AppTheme.sp8),
        ],
      ),
      floatingActionButton: _isOffer
          ? FloatingActionButton.extended(
              onPressed: _showStatusSheet,
              icon: const Icon(Icons.swap_horiz_rounded, size: 18),
              label: Text('الحالة: ${_property.status}'),
              backgroundColor: StatusHelpers.color(_property.status),
              elevation: 0,
            )
          : null,
      body: ListView(
        children: [
          if (_isOffer && _property.images.isNotEmpty)
            ImageGallery(images: _property.images),
          HeroHeader(property: _property, entryColor: entryColor),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTheme.sp16,
              AppTheme.sp8,
              AppTheme.sp16,
              100,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SpecsGrid(property: _property),
                const SizedBox(height: AppTheme.sp16),
                DetailSection(
                  title: 'الموقع',
                  icon: Icons.location_on_rounded,
                  color: entryColor,
                  children: [
                    InfoRow(
                      icon: Icons.map_rounded,
                      label: 'المحافظة',
                      value: _property.province,
                    ),
                    if (_property.region.isNotEmpty)
                      InfoRow(
                        icon: Icons.place_rounded,
                        label: 'المنطقة',
                        value: _property.region,
                      ),
                    if (_isOffer && _property.addressDetails.isNotEmpty)
                      InfoRow(
                        icon: Icons.home_rounded,
                        label: 'العنوان',
                        value: _property.addressDetails,
                      ),
                  ],
                ),
                if (_isOffer) ...[
                  DetailSection(
                    title: 'مواصفات العقار',
                    icon: Icons.apartment_rounded,
                    color: entryColor,
                    children: [
                      InfoRow(
                        icon: Icons.sell_rounded,
                        label: 'نوع الإعلان',
                        value: _property.adType,
                      ),
                      if (_property.deedType.isNotEmpty)
                        InfoRow(
                          icon: Icons.description_rounded,
                          label: 'نوع السند',
                          value: _property.deedType,
                        ),
                      if (_property.floor.isNotEmpty)
                        InfoRow(
                          icon: Icons.layers_rounded,
                          label: 'الطابق',
                          value: _property.floor,
                        ),
                      if (_property.facade.isNotEmpty)
                        InfoRow(
                          icon: Icons.crop_landscape_rounded,
                          label: 'الواجهة',
                          value: _property.facade,
                        ),
                      if (_property.finishingLevel.isNotEmpty)
                        InfoRow(
                          icon: Icons.auto_fix_high_rounded,
                          label: 'الإكساء',
                          value: _property.finishingLevel,
                        ),
                      if (_property.ownershipType.isNotEmpty)
                        InfoRow(
                          icon: Icons.gavel_rounded,
                          label: 'الملكية',
                          value: _property.ownershipType,
                        ),
                      InfoRow(
                        icon: StatusHelpers.icon(_property.status),
                        label: 'الحالة',
                        value: _property.status,
                        valueColor: StatusHelpers.color(_property.status),
                      ),
                      if (_property.hasGarden)
                        const InfoRow(
                          icon: Icons.park_rounded,
                          label: 'حديقة',
                          value: 'نعم',
                        ),
                      if (_property.isDuplex)
                        const InfoRow(
                          icon: Icons.stairs_rounded,
                          label: 'دوبلكس',
                          value: 'نعم',
                        ),
                      if (_property.directions.isNotEmpty)
                        InfoRow(
                          icon: Icons.explore_rounded,
                          label: 'الاتجاهات',
                          value: _property.directions.join(' · '),
                        ),
                    ],
                  ),
                  if (_property.features.isNotEmpty)
                    FeaturesSection(
                      features: _property.features,
                      color: entryColor,
                    ),
                ],
                ContactSection(
                  property: _property,
                  isOffer: _isOffer,
                  entryColor: entryColor,
                ),
                if (_property.notes.isNotEmpty)
                  NotesSection(
                    notes: _property.notes,
                    color: entryColor,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
