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

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
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
        imagePath TEXT NOT NULL
      )
    ''');
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
    return await db.delete(
      'potholes',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deletePotholes(List<int> ids) async {
    if (ids.isEmpty) return 0;
    final db = await instance.database;
    return await db.delete(
      'potholes',
      where: 'id IN (${List.filled(ids.length, '?').join(',')})',
      whereArgs: ids,
    );
  }

  Future<int> deleteAllPotholes() async {
    final db = await instance.database;
    return await db.delete('potholes');
  }
}
