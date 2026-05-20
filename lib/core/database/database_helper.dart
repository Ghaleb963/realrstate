import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../../features/properties/models/property_model.dart';

class DatabaseHelper {
  // ═══════════════════════════════════════════════════════════
  //  Constants
  // ═══════════════════════════════════════════════════════════
  static const String _dbFilename = 'real_estate.db';
  static const String tableProperties = 'properties';
  static const int _dbVersion = 3;

  /// الأعمدة المتوقعة — مرجع واحد يُستخدم للتحقق من صحة الـ Backup
  /// ويجب تحديثه يدوياً عند إضافة أي عمود جديد.
  static const Set<String> expectedColumns = {
    'id',
    'entry_type',
    'adType',
    'deedType',
    'propertyType',
    'province',
    'region',
    'addressDetails',
    'floor',
    'rooms',
    'area',
    'hasGarden',
    'isDuplex',
    'facade',
    'directions',
    'finishingLevel',
    'features',
    'ownershipType',
    'ownershipDetails',
    'sharesCount',
    'price',
    'currency',
    'status',
    'ownerName',
    'ownerWhatsapp',
    'officeName',
    'contactPhone',
    'facebookLink',
    'notes',
    'images',
    'videos',
    'ownerStatus',
    'created_at',
    'updated_at',
  };

  // ═══════════════════════════════════════════════════════════
  //  Singleton
  // ═══════════════════════════════════════════════════════════
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB();
    return _database!;
  }

  // ═══════════════════════════════════════════════════════════
  //  Initialization
  // ═══════════════════════════════════════════════════════════

  Future<Database> _initDB() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _dbFilename);

    return await openDatabase(
      path,
      version: _dbVersion,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
      onConfigure: _configureDB,
    );
  }

  /// ضبط إعدادات SQLite عند فتح الاتصال
  Future<void> _configureDB(Database db) async {
    // On Android (sqflite) PRAGMA statements must be executed via query/rawQuery.
    // Using execute(...) for PRAGMA can cause the SQLite error observed on device.
    try {
      await db.rawQuery('PRAGMA journal_mode=WAL');
    } catch (_) {
      // fallback: ignore if platform does not support or already set
    }

    try {
      await db.rawQuery('PRAGMA foreign_keys=ON');
    } catch (_) {
      // ignore failures here as some environments may not allow changing pragmas
    }
  }

  /// يُستدعى مرة واحدة فقط عند إنشاء DB لأول مرة
  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableProperties (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        entry_type      TEXT NOT NULL DEFAULT 'offer',
        adType          TEXT NOT NULL DEFAULT '',
        deedType        TEXT NOT NULL DEFAULT '',
        propertyType    TEXT NOT NULL DEFAULT '',
        province        TEXT NOT NULL DEFAULT '',
        region          TEXT NOT NULL DEFAULT '',
        addressDetails  TEXT NOT NULL DEFAULT '',
        floor           TEXT NOT NULL DEFAULT '',
        rooms           INTEGER NOT NULL DEFAULT 0,
        area            REAL NOT NULL DEFAULT 0,
        hasGarden       INTEGER NOT NULL DEFAULT 0,
        isDuplex        INTEGER NOT NULL DEFAULT 0,
        facade          TEXT NOT NULL DEFAULT '',
        directions      TEXT NOT NULL DEFAULT '[]',
        finishingLevel  TEXT NOT NULL DEFAULT '',
        features        TEXT NOT NULL DEFAULT '[]',
        ownershipType   TEXT NOT NULL DEFAULT '',
        ownershipDetails TEXT NOT NULL DEFAULT '',
        sharesCount     INTEGER,
        price           REAL NOT NULL DEFAULT 0,
        currency        TEXT NOT NULL DEFAULT '',
        status          TEXT NOT NULL DEFAULT '',
        ownerName       TEXT NOT NULL DEFAULT '',
        ownerWhatsapp   TEXT NOT NULL DEFAULT '',
        officeName      TEXT NOT NULL DEFAULT '',
        contactPhone    TEXT NOT NULL DEFAULT '',
        facebookLink    TEXT NOT NULL DEFAULT '',
        notes           TEXT NOT NULL DEFAULT '',
        images          TEXT NOT NULL DEFAULT '[]',
        videos          TEXT NOT NULL DEFAULT '[]',
        ownerStatus     TEXT NOT NULL DEFAULT '',
        created_at      TEXT,
        updated_at      TEXT
      )
    ''');
  }

  // ═══════════════════════════════════════════════════════════
  //  Migrations  (كل ترقية في دالة منفصلة = تركيبي + آمن)
  // ═══════════════════════════════════════════════════════════

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    // تُطبق الترقيات بالترتيب الرقمي — حتى لو قفز المستخدم
    // من v1 إلى v3 مباشرةً، ستنفذ كل الترقيات الوسيطة بالترتيب
    if (oldVersion < 2) await _migrateV1toV2(db);
    if (oldVersion < 3) await _migrateV2toV3(db);
    // مستقبلاً: if (oldVersion < 4) await _migrateV3toV4(db);
  }

  /// v1 → v2 : إضافة حقل entry_type (للمشروع القديم قبل الـ Type Classification)
  Future<void> _migrateV1toV2(Database db) async {
    await db.transaction((txn) async {
      // DEFAULT 'offer' يضمن أن السجلات القديمة تُصنَّف كعروض تلقائياً
      await txn.execute(
        "ALTER TABLE $tableProperties ADD COLUMN entry_type TEXT NOT NULL DEFAULT 'offer'",
      );
    });
  }

  /// v2 → v3 : إضافة أختام زمنية لتتبع وقت الإنشاء والتعديل
  Future<void> _migrateV2toV3(Database db) async {
    await db.transaction((txn) async {
      await txn.execute(
        'ALTER TABLE $tableProperties ADD COLUMN created_at TEXT',
      );
      await txn.execute(
        'ALTER TABLE $tableProperties ADD COLUMN updated_at TEXT',
      );
      // تعيين created_at = updated_at للسجلات الموجودة
      // (بقيمة وقت الترقية — أفضل من null)
      final now = DateTime.now().toIso8601String();
      await txn.update(
        tableProperties,
        {'created_at': now, 'updated_at': now},
      );
    });
  }

  // ═══════════════════════════════════════════════════════════
  //  CRUD — عمليات آمنة بـ Transaction + Error Handling
  // ═══════════════════════════════════════════════════════════

  Future<int> insertProperty(PropertyModel property) async {
    final db = await instance.database;
    final map = property.toMap();
    final now = DateTime.now().toIso8601String();
    map['created_at'] = now;
    map['updated_at'] = now;
    try {
      return await db.transaction((txn) => txn.insert(tableProperties, map));
    } catch (e) {
      throw Exception('فشل إضافة العقار: $e');
    }
  }

  Future<int> updateProperty(PropertyModel property) async {
    final db = await instance.database;
    final map = property.toMap();
    map['updated_at'] = DateTime.now().toIso8601String();
    map.remove('created_at');
    try {
      return await db.transaction((txn) => txn.update(
            tableProperties,
            map,
            where: 'id = ?',
            whereArgs: [property.id],
          ));
    } catch (e) {
      throw Exception('فشل تحديث العقار: $e');
    }
  }

  Future<int> deleteProperty(int id) async {
    final db = await instance.database;
    try {
      return await db.transaction((txn) => txn.delete(
            tableProperties,
            where: 'id = ?',
            whereArgs: [id],
          ));
    } catch (e) {
      throw Exception('فشل حذف العقار: $e');
    }
  }

  Future<List<PropertyModel>> getAllProperties() async {
    final db = await instance.database;
    try {
      final result = await db.query(tableProperties, orderBy: 'id DESC');
      return result.map((json) => PropertyModel.fromMap(json)).toList();
    } catch (e) {
      throw Exception('فشل تحميل العقارات: $e');
    }
  }

  Future<int> getPropertiesCount() async {
    final db = await instance.database;
    try {
      final count = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM $tableProperties'),
      );
      return count ?? 0;
    } catch (e) {
      throw Exception('فشل حساب عدد العقارات: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  //  Utilities
  // ═══════════════════════════════════════════════════════════

  Future<String> getDatabasePath() async {
    final dbPath = await getDatabasesPath();
    return join(dbPath, _dbFilename);
  }

  Future<void> closeDatabase() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }

  /// التحقق من صحة ملف قاعدة البيانات المختار للاستعادة.
  /// يضمن أن الملف يحتوي على table properties بجميع الأعمدة المتوقعة.
  Future<bool> isValidDatabase(String path) async {
    Database? tempDb;
    try {
      tempDb = await openReadOnlyDatabase(path);

      final tables = await tempDb.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='$tableProperties'",
      );
      if (tables.isEmpty) return false;

      final columns =
          await tempDb.rawQuery('PRAGMA table_info($tableProperties)');
      final columnNames = columns.map((c) => c['name'] as String).toSet();

      for (final col in expectedColumns) {
        if (!columnNames.contains(col)) return false;
      }

      return true;
    } catch (_) {
      return false;
    } finally {
      await tempDb?.close();
    }
  }
}
