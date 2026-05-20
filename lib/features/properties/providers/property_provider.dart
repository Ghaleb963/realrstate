import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/property_model.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/constants/app_constants.dart';
import '../services/matching_service.dart';

class PropertyNotifier extends StateNotifier<List<PropertyModel>> {
  final Ref ref;
  PropertyNotifier(this.ref) : super([]) {
    loadProperties();
  }

  Future<void> loadProperties() async {
    try {
      final properties = await DatabaseHelper.instance.getAllProperties();
      state = properties;
    } catch (e) {
      state = [];
    }
  }

  Future<bool> addProperty(PropertyModel property) async {
    final newId = await DatabaseHelper.instance.insertProperty(property);
    final inserted = property.copyWith(id: newId);
    state = [inserted, ...state];
    return true;
  }

  Future<void> deleteProperty(int id) async {
    await DatabaseHelper.instance.deleteProperty(id);
    state = state.where((p) => p.id != id).toList();
  }

  Future<void> updateProperty(PropertyModel property) async {
    await DatabaseHelper.instance.updateProperty(property);
    state = state.map((p) => p.id == property.id ? property : p).toList();
  }

  Future<void> updatePropertyStatus(int id, String newStatus) async {
    final index = state.indexWhere((p) => p.id == id);
    if (index == -1) return;

    final updated = state[index].copyWith(status: newStatus);
    await DatabaseHelper.instance.updateProperty(updated);
    state = state.map((p) => p.id == id ? updated : p).toList();
  }

  List<MatchResult>? findMatchesFor(PropertyModel property) {
    final matches = MatchingService.findMatches(property, state);
    return matches.isEmpty ? null : matches;
  }
}

final propertyProvider =
    StateNotifierProvider<PropertyNotifier, List<PropertyModel>>((ref) {
  return PropertyNotifier(ref);
});

final filteredPropertiesProvider = Provider<List<PropertyModel>>((ref) {
  final allProperties = ref.watch(propertyProvider);
  final filter = ref.watch(propertyFilterProvider);

  if (filter.isEmpty) return allProperties;

  return allProperties.where((p) {
    final matchesEntryType = filter.selectedEntryType == null ||
        p.entryType == filter.selectedEntryType;

    final matchesQuery = filter.query.isEmpty ||
        p.region.toLowerCase().contains(filter.query.toLowerCase()) ||
        p.propertyType.toLowerCase().contains(filter.query.toLowerCase()) ||
        p.province.toLowerCase().contains(filter.query.toLowerCase()) ||
        p.addressDetails.toLowerCase().contains(filter.query.toLowerCase()) ||
        p.ownerName.toLowerCase().contains(filter.query.toLowerCase()) ||
        p.officeName.toLowerCase().contains(filter.query.toLowerCase());

    final matchesMinPrice =
        filter.minPrice == null || p.price >= filter.minPrice!;
    final matchesMaxPrice =
        filter.maxPrice == null || p.price <= filter.maxPrice!;
    final matchesType =
        filter.selectedType == null || p.propertyType == filter.selectedType;
    final matchesOwner = filter.selectedOwnerStatus == null ||
        p.ownerStatus == filter.selectedOwnerStatus;
    final matchesProvince = filter.selectedProvince == null ||
        p.province == filter.selectedProvince;
    final matchesAdType =
        filter.selectedAdType == null || p.adType == filter.selectedAdType;
    final matchesStatus =
        filter.selectedStatus == null || p.status == filter.selectedStatus;
    final matchesFinishing = filter.selectedFinishing == null ||
        p.finishingLevel == filter.selectedFinishing;
    final matchesFacade =
        filter.selectedFacade == null || p.facade == filter.selectedFacade;
    final matchesDeedType = filter.selectedDeedType == null ||
        p.deedType == filter.selectedDeedType;
    final matchesMinRooms =
        filter.minRooms == null || p.rooms >= filter.minRooms!;
    final matchesMaxRooms =
        filter.maxRooms == null || p.rooms <= filter.maxRooms!;
    final matchesMinArea = filter.minArea == null || p.area >= filter.minArea!;
    final matchesMaxArea = filter.maxArea == null || p.area <= filter.maxArea!;
    final matchesFloor = filter.selectedFloor == null ||
        filter.selectedFloor!.isEmpty ||
        p.floor.toLowerCase().contains(filter.selectedFloor!.toLowerCase());
    final matchesHasGarden =
        filter.hasGarden == null || p.hasGarden == filter.hasGarden;
    final matchesIsDuplex =
        filter.isDuplex == null || p.isDuplex == filter.isDuplex;
    final matchesCurrency = filter.selectedCurrency == null ||
        p.currency == filter.selectedCurrency;
    final matchesOwnership = filter.selectedOwnership == null ||
        p.ownershipType == filter.selectedOwnership;

    return matchesEntryType &&
        matchesQuery &&
        matchesMinPrice &&
        matchesMaxPrice &&
        matchesType &&
        matchesOwner &&
        matchesProvince &&
        matchesAdType &&
        matchesStatus &&
        matchesFinishing &&
        matchesFacade &&
        matchesDeedType &&
        matchesMinRooms &&
        matchesMaxRooms &&
        matchesMinArea &&
        matchesMaxArea &&
        matchesFloor &&
        matchesHasGarden &&
        matchesIsDuplex &&
        matchesCurrency &&
        matchesOwnership;
  }).toList();
});

class PropertyFilter {
  final EntryType? selectedEntryType;
  final String query;
  final double? minPrice;
  final double? maxPrice;
  final String? selectedType;
  final String? selectedOwnerStatus;
  final String? selectedProvince;
  final String? selectedAdType;
  final String? selectedStatus;
  final String? selectedFinishing;
  final String? selectedFacade;
  final String? selectedDeedType;
  final int? minRooms;
  final int? maxRooms;
  final double? minArea;
  final double? maxArea;
  final String? selectedFloor;
  final bool? hasGarden;
  final bool? isDuplex;
  final String? selectedCurrency;
  final String? selectedOwnership;

  const PropertyFilter({
    this.selectedEntryType,
    this.query = '',
    this.minPrice,
    this.maxPrice,
    this.selectedType,
    this.selectedOwnerStatus,
    this.selectedProvince,
    this.selectedAdType,
    this.selectedStatus,
    this.selectedFinishing,
    this.selectedFacade,
    this.selectedDeedType,
    this.minRooms,
    this.maxRooms,
    this.minArea,
    this.maxArea,
    this.selectedFloor,
    this.hasGarden,
    this.isDuplex,
    this.selectedCurrency,
    this.selectedOwnership,
  });

  bool get isEmpty =>
      selectedEntryType == null &&
      query.isEmpty &&
      minPrice == null &&
      maxPrice == null &&
      selectedType == null &&
      selectedOwnerStatus == null &&
      selectedProvince == null &&
      selectedAdType == null &&
      selectedStatus == null &&
      selectedFinishing == null &&
      selectedFacade == null &&
      selectedDeedType == null &&
      minRooms == null &&
      maxRooms == null &&
      minArea == null &&
      maxArea == null &&
      selectedFloor == null &&
      hasGarden == null &&
      isDuplex == null &&
      selectedCurrency == null &&
      selectedOwnership == null;

  PropertyFilter copyWith({
    EntryType? Function()? selectedEntryType,
    String? query,
    double? Function()? minPrice,
    double? Function()? maxPrice,
    String? Function()? selectedType,
    String? Function()? selectedOwnerStatus,
    String? Function()? selectedProvince,
    String? Function()? selectedAdType,
    String? Function()? selectedStatus,
    String? Function()? selectedFinishing,
    String? Function()? selectedFacade,
    String? Function()? selectedDeedType,
    int? Function()? minRooms,
    int? Function()? maxRooms,
    double? Function()? minArea,
    double? Function()? maxArea,
    String? Function()? selectedFloor,
    bool? Function()? hasGarden,
    bool? Function()? isDuplex,
    String? Function()? selectedCurrency,
    String? Function()? selectedOwnership,
  }) {
    return PropertyFilter(
      selectedEntryType: selectedEntryType != null
          ? selectedEntryType()
          : this.selectedEntryType,
      query: query ?? this.query,
      minPrice: minPrice != null ? minPrice() : this.minPrice,
      maxPrice: maxPrice != null ? maxPrice() : this.maxPrice,
      selectedType: selectedType != null ? selectedType() : this.selectedType,
      selectedOwnerStatus: selectedOwnerStatus != null
          ? selectedOwnerStatus()
          : this.selectedOwnerStatus,
      selectedProvince:
          selectedProvince != null ? selectedProvince() : this.selectedProvince,
      selectedAdType:
          selectedAdType != null ? selectedAdType() : this.selectedAdType,
      selectedStatus:
          selectedStatus != null ? selectedStatus() : this.selectedStatus,
      selectedFinishing: selectedFinishing != null
          ? selectedFinishing()
          : this.selectedFinishing,
      selectedFacade:
          selectedFacade != null ? selectedFacade() : this.selectedFacade,
      selectedDeedType:
          selectedDeedType != null ? selectedDeedType() : this.selectedDeedType,
      minRooms: minRooms != null ? minRooms() : this.minRooms,
      maxRooms: maxRooms != null ? maxRooms() : this.maxRooms,
      minArea: minArea != null ? minArea() : this.minArea,
      maxArea: maxArea != null ? maxArea() : this.maxArea,
      selectedFloor:
          selectedFloor != null ? selectedFloor() : this.selectedFloor,
      hasGarden: hasGarden != null ? hasGarden() : this.hasGarden,
      isDuplex: isDuplex != null ? isDuplex() : this.isDuplex,
      selectedCurrency:
          selectedCurrency != null ? selectedCurrency() : this.selectedCurrency,
      selectedOwnership: selectedOwnership != null
          ? selectedOwnership()
          : this.selectedOwnership,
    );
  }
}

final propertyFilterProvider =
    StateProvider<PropertyFilter>((ref) => const PropertyFilter());

// ════════════════════════════════════════════════════════
// allMatchesProvider — Provider تفاعلي لجميع التوافقات
//
// يراقب propertyProvider ويُعيد حساب التوافقات تلقائياً
// في كل مرة تتغير قائمة العقارات (إضافة/تعديل/حذف).
// ════════════════════════════════════════════════════════
final allMatchesProvider = Provider<List<MatchResult>>((ref) {
  final allProperties = ref.watch(propertyProvider);
  return MatchingService.findAllMatches(allProperties);
});

class PropertyStats {
  final int total;
  final int offers;
  final int requirements;
  final int available;
  final int sold;

  const PropertyStats({
    required this.total,
    required this.offers,
    required this.requirements,
    required this.available,
    required this.sold,
  });
}

final propertyStatsProvider = Provider<PropertyStats>((ref) {
  final all = ref.watch(propertyProvider);
  return PropertyStats(
    total: all.length,
    offers: all.where((p) => p.entryType == EntryType.offer).length,
    requirements: all.where((p) => p.entryType == EntryType.requirement).length,
    available: all.where((p) => p.status == 'متاح').length,
    sold: all.where((p) => p.status == 'مباع').length,
  );
});
