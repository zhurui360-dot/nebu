import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../models/models.dart';

/// 本地曲库：sqflite。
///
/// 表结构：
///  tracks    曲目（主键 id = 源 + 网盘路径 的哈希，重复导入不会重复）
///  favorites 我喜欢（track_id）
///  recent    最近播放（track_id + played_at）
///  sources   网盘源
///  folders   已导入目录（用于增量扫描）
class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();

  static const _dbName = 'cloudtune.db';
  static const _dbVersion = 4;

  Database? _db;

  Future<Database> get _database async {
    if (_db != null) return _db!;
    final dir = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dir, _dbName),
      version: _dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
    return _db!;
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE tracks(
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        artist TEXT,
        album TEXT,
        album_id TEXT,
        year INTEGER,
        duration_ms INTEGER NOT NULL DEFAULT 0,
        format TEXT NOT NULL,
        quality TEXT,
        hi_res INTEGER NOT NULL DEFAULT 0,
        has_tags INTEGER NOT NULL DEFAULT 0,
        url TEXT,
        source_id TEXT,
        path TEXT,
        cover_path TEXT,
        lyric_path TEXT,
        size_bytes INTEGER NOT NULL DEFAULT 0,
        added_at INTEGER NOT NULL,
        created_at INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('CREATE INDEX idx_tracks_album ON tracks(album_id)');
    await db.execute('CREATE INDEX idx_tracks_added ON tracks(added_at DESC)');
    await db.execute('CREATE INDEX idx_tracks_source ON tracks(source_id)');

    await db.execute('''
      CREATE TABLE favorites(
        track_id TEXT PRIMARY KEY,
        added_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE recent(
        track_id TEXT PRIMARY KEY,
        played_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE sources(
        id TEXT PRIMARY KEY,
        name TEXT,
        kind TEXT,
        base_url TEXT,
        username TEXT,
        connected INTEGER NOT NULL DEFAULT 0,
        imported_dirs INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE folders(
        id TEXT PRIMARY KEY,
        source_id TEXT NOT NULL,
        path TEXT NOT NULL,
        file_count INTEGER NOT NULL DEFAULT 0,
        include_sub INTEGER NOT NULL DEFAULT 0,
        last_scan INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  /// 以后加字段在这里写迁移，别改 _onCreate（老用户升不上来）
  Future<void> _onUpgrade(Database db, int from, int to) async {
    if (from < 2) {
      await db.execute('ALTER TABLE tracks ADD COLUMN cover_path TEXT');
      await db.execute('ALTER TABLE tracks ADD COLUMN lyric_path TEXT');
    }
    if (from < 3) {
      await db.execute('ALTER TABLE folders ADD COLUMN include_sub INTEGER NOT NULL DEFAULT 0');
    }
    if (from < 4) {
      // 文件创建时间：老库先填 0（按创建时间排序时回退到添加时间）
      await db.execute(
          'ALTER TABLE tracks ADD COLUMN created_at INTEGER NOT NULL DEFAULT 0');
    }
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  // ======================= 曲目 =======================

  Future<List<Track>> allTracks() async {
    final db = await _database;
    final rows = await db.query('tracks', orderBy: 'added_at DESC');
    return rows.map(Track.fromMap).toList();
  }

  Future<int> countTracks() async {
    final db = await _database;
    final r = await db.rawQuery('SELECT COUNT(*) AS c FROM tracks');
    return (r.first['c'] as int?) ?? 0;
  }

  /// 批量写入；同 id 覆盖（重复导入不会产生重复行）
  Future<int> upsertTracks(List<Track> tracks) async {
    if (tracks.isEmpty) return 0;
    final db = await _database;
    final batch = db.batch();
    for (final t in tracks) {
      batch.insert('tracks', t.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    }
    final res = await batch.commit(noResult: true);
    return res.length;
  }

  Future<void> updateHasTags(List<String> ids, {required bool value}) async {
    if (ids.isEmpty) return;
    final db = await _database;
    final marks = List.filled(ids.length, '?').join(',');
    await db.rawUpdate(
      'UPDATE tracks SET has_tags = ? WHERE id IN ($marks)',
      [value ? 1 : 0, ...ids],
    );
  }

  Future<void> updateMeta(String id, {String? coverPath, String? lyricPath}) async {
    final db = await _database;
    final map = <String, Object?>{};
    if (coverPath != null) map['cover_path'] = coverPath;
    if (lyricPath != null) map['lyric_path'] = lyricPath;
    if (map.isNotEmpty) {
      await db.update('tracks', map, where: 'id = ?', whereArgs: [id]);
    }
  }

  /// 重新读取标签后回写：标题/歌手/专辑/时长/规格/封面
  Future<void> updateTrackMeta(
    String id, {
    String? title,
    String? artist,
    String? album,
    String? albumId,
    int? durationMs,
    String? quality,
    String? coverPath,
  }) async {
    final db = await _database;
    final map = <String, Object?>{};
    if (title != null) map['title'] = title;
    if (artist != null) map['artist'] = artist;
    if (album != null) map['album'] = album;
    if (albumId != null) map['album_id'] = albumId;
    if (durationMs != null) map['duration_ms'] = durationMs;
    if (quality != null) map['quality'] = quality;
    if (coverPath != null) map['cover_path'] = coverPath;
    if (map.isNotEmpty) {
      await db.update('tracks', map, where: 'id = ?', whereArgs: [id]);
    }
  }

  Future<void> updateUrl(String id, String? url) async {
    final db = await _database;
    await db.update('tracks', {'url': url}, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteTracksBySource(String sourceId) async {
    final db = await _database;
    return db.delete('tracks', where: 'source_id = ?', whereArgs: [sourceId]);
  }

  /// 删除单曲：连收藏 / 最近播放的引用一起清掉，
  /// 否则「我喜欢」里会留下一条点不开的空记录
  Future<void> deleteTrack(String id) async {
    final db = await _database;
    await db.delete('tracks', where: 'id = ?', whereArgs: [id]);
    await db.delete('favorites', where: 'track_id = ?', whereArgs: [id]);
    await db.delete('recent', where: 'track_id = ?', whereArgs: [id]);
  }

  /// 清空曲库相关的所有表（保留 sources / folders —— 已添加的目录不受影响）
  Future<void> clearLibrary() async {
    final db = await _database;
    await db.delete('tracks');
    await db.delete('favorites');
    await db.delete('recent');
  }

  /// 按「同源 + 同大小 + 同标题」去重，返回已存在的 id 集合（导入时跳过）
  Future<Set<String>> existingKeys(String sourceId) async {
    final db = await _database;
    final rows = await db.query(
      'tracks',
      columns: ['id'],
      where: 'source_id = ?',
      whereArgs: [sourceId],
    );
    return rows.map((e) => e['id'] as String).toSet();
  }

  /// 本地已入库文件的指纹（路径 → 大小 + 修改时间）。
  /// 重扫时文件没变就不用再读标签，几千首的曲库能省掉绝大部分 I/O。
  Future<Map<String, ({int size, int mtime})>> localFileStats() async {
    final db = await _database;
    final rows = await db.query(
      'tracks',
      columns: ['path', 'size_bytes', 'created_at'],
      where: "source_id = 'local'",
    );
    final out = <String, ({int size, int mtime})>{};
    for (final r in rows) {
      final path = r['path'] as String?;
      if (path == null || path.isEmpty) continue;
      out[path] = (
        size: (r['size_bytes'] as int?) ?? 0,
        mtime: (r['created_at'] as int?) ?? 0,
      );
    }
    return out;
  }

  // ======================= 我喜欢 =======================

  Future<Set<String>> favorites() async {
    final db = await _database;
    final rows = await db.query('favorites', orderBy: 'added_at DESC');
    return rows.map((e) => e['track_id'] as String).toSet();
  }

  Future<void> setFavorite(String trackId, bool on) async {
    final db = await _database;
    if (on) {
      await db.insert(
        'favorites',
        {'track_id': trackId, 'added_at': DateTime.now().millisecondsSinceEpoch},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } else {
      await db.delete('favorites', where: 'track_id = ?', whereArgs: [trackId]);
    }
  }

  // ======================= 最近播放 =======================

  Future<List<String>> recent({int limit = 30}) async {
    final db = await _database;
    final rows = await db.query('recent', orderBy: 'played_at DESC', limit: limit);
    return rows.map((e) => e['track_id'] as String).toList();
  }

  Future<void> touchRecent(String trackId) async {
    final db = await _database;
    await db.insert(
      'recent',
      {'track_id': trackId, 'played_at': DateTime.now().millisecondsSinceEpoch},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    // 只保留最近 100 条
    await db.rawDelete(
      'DELETE FROM recent WHERE track_id NOT IN '
      '(SELECT track_id FROM recent ORDER BY played_at DESC LIMIT 100)',
    );
  }

  // ======================= 网盘源 =======================

  Future<List<Map<String, Object?>>> sourceRows() async {
    final db = await _database;
    return db.query('sources');
  }

  Future<void> upsertSources(List<CloudSource> sources) async {
    final db = await _database;
    final batch = db.batch();
    for (final s in sources) {
      batch.insert('sources', s.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<void> bumpImportedDirs(String sourceId, int delta) async {
    final db = await _database;
    await db.rawUpdate(
      'UPDATE sources SET imported_dirs = imported_dirs + ? WHERE id = ?',
      [delta, sourceId],
    );
  }

  // ======================= 已导入目录 =======================

  Future<void> upsertFolder({
    required String id,
    required String sourceId,
    required String path,
    required int fileCount,
    bool includeSub = false,
  }) async {
    final db = await _database;
    await db.insert(
      'folders',
      {
        'id': id,
        'source_id': sourceId,
        'path': path,
        'file_count': fileCount,
        'include_sub': includeSub ? 1 : 0,
        'last_scan': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 读回已保存的目录
  Future<List<Map<String, Object?>>> loadFolders(String sourceId) async {
    final db = await _database;
    return db.query(
      'folders',
      where: 'source_id = ?',
      whereArgs: [sourceId],
      orderBy: 'last_scan DESC',
    );
  }

  /// 所有来源的已保存目录（本地 / 网盘 / 以后新增的源都用同一张表）
  Future<List<Map<String, Object?>>> loadAllFolders() async {
    final db = await _database;
    return db.query('folders', orderBy: 'source_id ASC, last_scan DESC');
  }

  Future<void> deleteFolder(String id) async {
    final db = await _database;
    await db.delete('folders', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<String>> importedFolders(String sourceId) async {
    final db = await _database;
    final rows = await db.query('folders',
        columns: ['path'], where: 'source_id = ?', whereArgs: [sourceId]);
    return rows.map((e) => e['path'] as String).toList();
  }
}
