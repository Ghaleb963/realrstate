import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/utils/encryption_helper.dart';
import '../repositories/device_repository_impl.dart';

class SettingsState {
  final bool isActivated;
  final String deviceId;
  final String userCode;
  final String officeName;
  final String officePhone;
  final String facebookLink;
  final String instagramLink;
  final bool isLoading;

  const SettingsState({
    required this.isActivated,
    required this.deviceId,
    required this.userCode,
    this.officeName = '',
    this.officePhone = '',
    this.facebookLink = '',
    this.instagramLink = '',
    this.isLoading = true,
  });

  SettingsState copyWith({
    bool? isActivated,
    String? deviceId,
    String? userCode,
    String? officeName,
    String? officePhone,
    String? facebookLink,
    String? instagramLink,
    bool? isLoading,
  }) {
    return SettingsState(
      isActivated: isActivated ?? this.isActivated,
      deviceId: deviceId ?? this.deviceId,
      userCode: userCode ?? this.userCode,
      officeName: officeName ?? this.officeName,
      officePhone: officePhone ?? this.officePhone,
      facebookLink: facebookLink ?? this.facebookLink,
      instagramLink: instagramLink ?? this.instagramLink,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class SettingsNotifier extends StateNotifier<SettingsState> {
  final _deviceRepo = DeviceRepositoryImpl();

  // [إصلاح #3] تم تخزين instance الـ SharedPreferences في متغير خاص
  // بدلاً من استدعاء SharedPreferences.getInstance() في كل دالة.
  // الـ getInstance() هي عملية async تُنشئ أو تجلب singleton داخلياً،
  // لكن استدعاؤها مراراً يُضيف overhead غير ضروري ويُصعّب قراءة الكود.
  // التخزين المؤقت يضمن جلب الـ instance مرة واحدة فقط طوال دورة حياة
  // الـ Notifier، وهو نمط أكثر اتساقاً مع مبدأ Dependency Injection.
  SharedPreferences? _prefs;

  SettingsNotifier()
      : super(const SettingsState(
            isActivated: true, deviceId: '', userCode: '')) {
    _loadSettings();
  }

  /// جلب أو إنشاء instance واحدة من SharedPreferences (Lazy Singleton)
  Future<SharedPreferences> _getPrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await _getPrefs();

      String? dynamicId = await _deviceRepo.getDeviceId();
      dynamicId ??= await _deviceRepo.rotateDeviceId();

      final userCode = EncryptionHelper.encryptDeviceIdForUser(dynamicId);

      state = state.copyWith(
        isActivated: true,
        deviceId: dynamicId,
        userCode: userCode,
        officeName: prefs.getString('officeName') ?? '',
        officePhone: prefs.getString('officePhone') ?? '',
        facebookLink: prefs.getString('facebookLink') ?? '',
        instagramLink: prefs.getString('instagramLink') ?? '',
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false);
    }
  }

  Future<bool> activate(String inputCode) async {
    final prefs = await _getPrefs();
    await prefs.setBool('isActivated', true);
    state = state.copyWith(isActivated: true);
    return true;
  }

  /// تسجيل الخروج وتدوير المعرف الديناميكي
  Future<void> logout() async {
    try {
      final prefs = await _getPrefs();
      await prefs.setBool('isActivated', true);

      final newId = await _deviceRepo.rotateDeviceId();
      final newUserCode = EncryptionHelper.encryptDeviceIdForUser(newId);

      state = state.copyWith(
        isActivated: true,
        deviceId: newId,
        userCode: newUserCode,
      );
    } catch (e) {
      rethrow;
    }
  }

  Future<void> updateOfficeData({
    required String name,
    required String phone,
    required String fb,
    required String insta,
  }) async {
    final prefs = await _getPrefs();
    await prefs.setString('officeName', name);
    await prefs.setString('officePhone', phone);
    await prefs.setString('facebookLink', fb);
    await prefs.setString('instagramLink', insta);

    state = state.copyWith(
      officeName: name,
      officePhone: phone,
      facebookLink: fb,
      instagramLink: insta,
    );
  }
}

final settingsProvider =
    StateNotifierProvider<SettingsNotifier, SettingsState>((ref) {
  return SettingsNotifier();
});
