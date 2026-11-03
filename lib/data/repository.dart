import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 轻量偏好存储。曲库 / 收藏 / 最近播放都已经进 sqflite（见 data/db/app_database.dart），
/// 这里只留「不属于曲库」的两项：主题与版本号。
class LibraryRepository {
  static const _kTheme = 'ct_theme';
  static const _kVersion = 'ct_version';
  static const _kUpdateUrl = 'ct_update_url';
  static const _kSearchHistory = 'ct_search_history';
  static const _kMetaSources = 'ct_meta_sources';
  static const _kAlbumFavorites = 'ct_album_favorites';
  static const _kLastUpdateCheck = 'ct_last_update_check';
  static const _kCacheLimitMb = 'ct_cache_limit_mb';
  static const _kOnlineMeta = 'ct_online_meta';
  static const _kPlaylists = 'ct_playlists';
  static const _kMyRows = 'ct_my_rows_hidden';
  static const _kFilenamePattern = 'ct_filename_pattern';
  static const _kFilenameSep = 'ct_filename_sep';
  static const _kDurationBackfill = 'ct_duration_backfill';
  static const _kLang = 'ct_lang';
  static const _kDownloadDir = 'ct_download_dir';

  SharedPreferences? _sp;

  Future<void> init() async {
    _sp = await SharedPreferences.getInstance();
  }

  ThemeMode loadTheme() {
    final v = _sp?.getString(_kTheme);
    return switch (v) {
      'dark' => ThemeMode.dark,
      'light' => ThemeMode.light,
      // 老版本没存过 system，这里兼容读取；
      // 未设置时仍按设计稿默认浅色
      'system' => ThemeMode.system,
      _ => ThemeMode.light,
    };
  }

  Future<void> saveTheme(ThemeMode m) async {
    await _sp?.setString(
      _kTheme,
      switch (m) {
        ThemeMode.dark => 'dark',
        ThemeMode.light => 'light',
        ThemeMode.system => 'system',
      },
    );
  }

  /// 界面语言（空字符串 = 跟随系统）
  String loadLang() => _sp?.getString(_kLang) ?? '';

  Future<void> saveLang(String code) async {
    await _sp?.setString(_kLang, code);
  }

  /// 音乐保存目录（DownloadDir.index）
  int loadDownloadDir() => _sp?.getInt(_kDownloadDir) ?? 0;

  Future<void> saveDownloadDir(int index) async {
    await _sp?.setInt(_kDownloadDir, index);
  }

  String loadVersion() => _sp?.getString(_kVersion) ?? '1.0.0';

  Future<void> saveVersion(String v) async {
    await _sp?.setString(_kVersion, v);
  }

  String loadUpdateUrl() => _sp?.getString(_kUpdateUrl) ?? '';

  Future<void> saveUpdateUrl(String url) async {
    await _sp?.setString(_kUpdateUrl, url);
  }

  /// 上次成功检查更新的时间（epoch 毫秒，0 = 从未检查过）。
  /// 启动静默检查用它节流：不足间隔就不打服务器。
  int loadLastUpdateCheck() => _sp?.getInt(_kLastUpdateCheck) ?? 0;

  Future<void> saveLastUpdateCheck(int epochMs) async {
    await _sp?.setInt(_kLastUpdateCheck, epochMs);
  }

  /// 老曲库缺时长（旧解析器不读 MP3 音频帧）的一次性补读标记
  bool loadDurationBackfilled() => _sp?.getBool(_kDurationBackfill) ?? false;

  Future<void> saveDurationBackfilled() async {
    await _sp?.setBool(_kDurationBackfill, true);
  }

  List<String> loadSearchHistory() =>
      _sp?.getStringList(_kSearchHistory) ?? const [];

  Future<void> saveSearchHistory(List<String> items) async {
    await _sp?.setStringList(_kSearchHistory, items);
  }

  String loadMetaSources() => _sp?.getString(_kMetaSources) ?? '';

  Future<void> saveMetaSources(String json) async {
    await _sp?.setString(_kMetaSources, json);
  }

  /// 收藏的专辑 id（「收藏」页用的就是它）
  List<String> loadAlbumFavorites() =>
      _sp?.getStringList(_kAlbumFavorites) ?? const [];

  Future<void> saveAlbumFavorites(List<String> ids) async {
    await _sp?.setStringList(_kAlbumFavorites, ids);
  }

  /// 离线缓存大小上限（MB，0 = 不限制）
  int loadCacheLimitMb() => _sp?.getInt(_kCacheLimitMb) ?? 5120;

  Future<void> saveCacheLimitMb(int mb) async {
    await _sp?.setInt(_kCacheLimitMb, mb);
  }

  /// 是否允许联网补全歌词与封面
  bool loadOnlineMeta() => _sp?.getBool(_kOnlineMeta) ?? true;

  Future<void> saveOnlineMeta(bool on) async {
    await _sp?.setBool(_kOnlineMeta, on);
  }

  /// 自建歌单（JSON 数组字符串）
  String loadPlaylists() => _sp?.getString(_kPlaylists) ?? '';

  Future<void> savePlaylists(String json) async {
    await _sp?.setString(_kPlaylists, json);
  }

  /// 「音乐库 → 我的」里被用户隐藏的条目（favorites / bookmarks / recent / downloads）
  List<String> loadHiddenMyRows() =>
      _sp?.getStringList(_kMyRows) ?? const [];

  Future<void> saveHiddenMyRows(List<String> keys) async {
    await _sp?.setStringList(_kMyRows, keys);
  }

  /// 文件名识别模板（空 = 智能识别）
  String loadFilenamePattern() => _sp?.getString(_kFilenamePattern) ?? '';

  Future<void> saveFilenamePattern(String v) async {
    await _sp?.setString(_kFilenamePattern, v);
  }

  /// 文件名识别用的「间隔符号」集合
  String loadFilenameSep() => _sp?.getString(_kFilenameSep) ?? '-–—_·';

  Future<void> saveFilenameSep(String v) async {
    await _sp?.setString(_kFilenameSep, v);
  }
}
