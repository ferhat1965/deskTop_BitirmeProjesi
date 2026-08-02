import 'dart:io';

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import '../models/pothole_record.dart';

class DbService {
  static final DbService instance = DbService._init();
  static Database? _database;

  DbService._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('potholes.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getApplicationDocumentsDirectory();
    final path = join(dbPath.path, 'RoadGuard', filePath);
    await Directory(dirname(path)).create(recursive: true);

    return await openDatabase(
      path,
      version: 2,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE potholes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL,
        time TEXT NOT NULL,
        confidence REAL NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        imagePath TEXT NOT NULL,
        className TEXT NOT NULL DEFAULT 'minor_pothole'
      )
    ''');
  }

  Future _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      try {
        await db.execute("ALTER TABLE potholes ADD COLUMN className TEXT NOT NULL DEFAULT 'minor_pothole'");
      } catch (e) {
        stderr.writeln('Database upgrade error: $e');
      }
    }
  }

  Future<int> insertPothole(PotholeRecord record) async {
    final db = await instance.database;
    return await db.insert('potholes', record.toMap());
  }

  Future<List<PotholeRecord>> fetchAllPotholes() async {
    final db = await instance.database;
    final maps = await db.query('potholes', orderBy: 'id DESC');

    return maps.map((map) => PotholeRecord.fromMap(map)).toList();
  }

  Future<int> deletePothole(int id) async {
    final db = await instance.database;
    final rows = await db.query(
      'potholes',
      columns: ['imagePath'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    final deleted = await db.delete(
      'potholes',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (rows.isNotEmpty) {
      await _deleteImageIfUnused(db, rows.first['imagePath'] as String?);
    }
    return deleted;
  }

  Future<int> deletePotholes(List<int> ids) async {
    if (ids.isEmpty) return 0;
    final db = await instance.database;
    final placeholders = List.filled(ids.length, '?').join(',');
    final rows = await db.query(
      'potholes',
      columns: ['imagePath'],
      where: 'id IN ($placeholders)',
      whereArgs: ids,
    );
    final deleted = await db.delete(
      'potholes',
      where: 'id IN ($placeholders)',
      whereArgs: ids,
    );
    for (final imagePath in rows.map((row) => row['imagePath'] as String?).toSet()) {
      await _deleteImageIfUnused(db, imagePath);
    }
    return deleted;
  }

  Future<int> deleteAllPotholes() async {
    final db = await instance.database;
    final rows = await db.query('potholes', columns: ['imagePath']);
    final deleted = await db.delete('potholes');
    for (final imagePath in rows.map((row) => row['imagePath'] as String?).toSet()) {
      await _deleteImageIfUnused(db, imagePath);
    }
    return deleted;
  }

  Future<void> _deleteImageIfUnused(Database db, String? imagePath) async {
    if (imagePath == null || imagePath.isEmpty) return;
    final remaining = Sqflite.firstIntValue(
      await db.rawQuery(
        'SELECT COUNT(*) FROM potholes WHERE imagePath = ?',
        [imagePath],
      ),
    );
    if ((remaining ?? 0) == 0) {
      try {
        final file = File(imagePath);
        if (await file.exists()) {
          await file.delete();
        }
      } on FileSystemException catch (error) {
        stderr.writeln('Kayıt resmi silinemedi: $error');
      }
    }
  }
}
