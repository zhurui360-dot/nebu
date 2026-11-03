import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/models.dart';
import '../services/audio_engine.dart';
import '../services/audio_handler.dart';
import '../services/offline_cache.dart';
import '../services/tags/lrc_parser.dart';
import 'app_state.dart';

enum PlayerMode { lyric, cover }

/// 播放模式：顺序播放 / 单曲循环 / 列表循环 / 随机播放
enum PlayMode { sequence, repeatOne, repeatAll, shuffle }

/// 播放状态：当前曲目、队列、进度、歌词行、封面/歌词模式。
/// 只负责「播放」，收藏/最近播放等库数据在 AppState。
class PlayerState extends ChangeNotifier {
  PlayerState([this._handler]) {
    _engine.onComplete = () => next(auto: true);
    _engine.onError = (_) => notifyListeners();
    _bindHandler();
  }

  final AudioEngine _engine = AudioEngine();

  /// 系统播放控件（通知栏/锁屏/耳机）
  final CloudTuneHandler? _handler;

  void _bindHandler() {
    final h = _handler;
    if (h == null) return;
    h.onPlay = () {
      if (!playing) toggle();
    };
    h.onPause = () {
      if (playing) toggle();
    };
    h.onNext = () => next();
    h.onPrev = () => prev();
    h.onSeek = (p) => seekRatio(
          p.inMilliseconds / (duration.inMilliseconds == 0 ? 1 : duration.inMilliseconds),
        );
    h.onStop = () {
      if (playing) toggle();
    };
  }

  /// 把当前状态同步给系统控件
  void _publish() {
    _handler?.publish(
      track: current,
      playing: playing,
      position: position,
      duration: duration,
    );
  }
  AppState? _app;
  StreamSubscription<Duration>? _posSub;

  String currentId = '';
  List<String> queue = [];
  Duration position = Duration.zero;
  bool playing = false;

  /// 播放进度单独走一条通知通道。
  ///
  /// 进度每 200ms 变一次，如果混进 notifyListeners()，那么全 App 每一个
  /// `context.watch<PlayerState>()` 的页面都会跟着按 5Hz 重建：列表整屏重排、
  /// 导航条和迷你条里的 BackdropFilter 反复重新模糊。这就是「放着歌刷列表特别卡」
  /// 的直接原因。现在只有真正订阅了进度的那条进度条子树会刷新。
  final ValueNotifier<Duration> pos = ValueNotifier(Duration.zero);

  /// 进度变更后同步给界面（低频：切歌、拖动进度、暂停复位）
  void _syncPosition() {
    pos.value = position;
  }

  /// 播放模式：顺序 → 单曲循环 → 列表循环 → 随机
  PlayMode playMode = PlayMode.repeatOne;
  PlayerMode mode = PlayerMode.lyric;
  int lyricIndex = 0;

  bool get repeatOne => playMode == PlayMode.repeatOne;
  bool get shuffle => playMode == PlayMode.shuffle;

  /// 播放页循环键：四态轮播
  void cycleMode() {
    playMode = PlayMode
        .values[(playMode.index + 1) % PlayMode.values.length];
    notifyListeners();
  }

  String get playModeName => switch (playMode) {
        PlayMode.sequence => '顺序播放',
        PlayMode.repeatOne => '单曲循环',
        PlayMode.repeatAll => '列表循环',
        PlayMode.shuffle => '随机播放',
      };

  /// 引擎是否已经按当前曲目准备好（首帧不会因为 total=0 直接播完）
  bool _preloaded = false;

  /// 直链播放失败的原因；不为 null 时说明当前是「无声预览」
  String? get playError => _engine.lastError;

  bool get isPreview => _engine.degraded;

  /// 重新加载当前曲目（换地址/重连后用）
  Future<void> retry() async {
    lastError = null;
    await play(currentId);
  }

  /// 最近一次失败提示（界面显示用）
  String? lastError;

  List<LyricLine> _lyrics = const [];
  List<LyricLine> get lyrics => _lyrics;
  bool get hasLyrics => _lyrics.isNotEmpty;

  /// 预览/测试用：直接塞一份歌词（不走文件、不碰数据库）
  @visibleForTesting
  void debugSetLyrics(List<LyricLine> lines, {int active = 0}) {
    _lyrics = lines;
    lyricIndex = active;
    notifyListeners();
  }

  /// 双语歌词里是否有翻译行（决定「翻译开关」显不显示）
  bool get hasTrans => _lyrics.any((l) => (l.trans ?? '').isNotEmpty);

  /// 歌词页是否显示翻译行
  bool showTrans = true;

  void toggleTrans() {
    showTrans = !showTrans;
    notifyListeners();
  }

  /// 从本地 .lrc 读取歌词（导入时就从网盘同目录抓下来了）
  Future<void> _loadLyrics(Track t) async {
    _lyrics = const [];
    final path = t.lyricPath;
    if (path != null) {
      try {
        final f = File(path);
        if (await f.exists()) {
          final raw = await f.readAsString();
          if (LrcParser.looksLikeLrc(raw)) _lyrics = LrcParser.parse(raw);
        }
      } catch (_) {
        _lyrics = const [];
      }
    }
    lyricIndex = _indexFor(position);
  }

  void attach(AppState app) {
    if (_app == app) return;
    _app = app;

    // 曲库变化时，补齐当前曲目与队列
    if (app.tracks.isNotEmpty) {
      if (currentId.isEmpty) currentId = app.tracks.first.id;
      if (queue.isEmpty) queue = app.tracks.map((t) => t.id).toList();
    }

    // 首次进入时把进度对齐到歌词行（不改变播放状态）
    lyricIndex = _indexFor(position);

    // 预加载：把时长交给引擎，之后点播放不会再从头开始
    if (!_preloaded && app.tracks.isNotEmpty) {
      _preloaded = true;
      _engine.load(url: current.url, duration: current.duration, headers: null);
      _loadLyrics(current);
    }
  }

  /// 当前曲目。库里没有这首歌时返回空占位，不拿任何示例曲目顶替
  Track get current => _app?.trackOf(currentId) ?? Track.empty();

  /// 是否在首页/浏览/搜索显示迷你播放条：播放过（或正在播）才出现
  bool get showMiniPlayer =>
      currentId.isNotEmpty && (playing || position > Duration.zero);

  /// 时长优先用引擎读到的真实值（标签缺失时 just_audio 能给）
  Duration get duration {
    final d = _engine.duration;
    return d > Duration.zero ? d : current.duration;
  }

  double get progress {
    final total = duration.inMilliseconds;
    if (total <= 0) return 0;
    return (position.inMilliseconds / total).clamp(0.0, 1.0);
  }

  int _indexFor(Duration p) {
    var idx = 0;
    for (var i = 0; i < lyrics.length; i++) {
      if (p >= lyrics[i].time) idx = i;
    }
    return idx;
  }

  /// 把某一首从播放队列里摘掉（歌曲被删除时调用）。
  /// 删的是当前正在播的这首就顺延到下一首；队列空了就彻底停下。
  Future<void> removeFromQueue(String id) async {
    final wasCurrent = currentId == id;
    queue.remove(id);
    if (!wasCurrent) {
      notifyListeners();
      return;
    }
    if (queue.isEmpty) {
      currentId = '';
      playing = false;
      position = Duration.zero;
      _syncPosition();
      _lyrics = const [];
      lyricIndex = 0;
      notifyListeners();
      _publish();
      return;
    }
    // 顺延到原本的下一首（删掉之后它就顶上来了）
    await play(queue.first);
  }

  Future<void> play(String id, {List<String>? queue}) async {
    if (queue != null && queue.isNotEmpty) this.queue = List.of(queue);
    if (!this.queue.contains(id)) this.queue.insert(0, id);


    currentId = id;
    final track = current;

    // 已经缓存过的歌直接读本地，断网也能播
    String? playUrl = track.url;
    String? local;
    try {
      local = await OfflineCache.cachedPath(track.id);
    } catch (_) {}
    if (local != null) playUrl = Uri.file(local).toString();

    await _engine.load(
      url: playUrl,
      duration: track.duration,
      headers: track.url == null ? null : _app?.headersFor(track.sourceId),
    );

    // 边听边缓存：后台把这首歌下到本地（不阻塞播放）
    // 先登记正在播放的 id，缓存超限清理时不会把它删掉
    OfflineCache.playingTrackId = track.id;
    if (_app?.autoCache == true && local == null && track.url != null) {
      // ignore: unawaited_futures
      OfflineCache.ensure(track.id, track.url, _app?.headersFor(track.sourceId));
    }

    position = Duration.zero;
    _syncPosition();
    lyricIndex = 0;
    playing = true;
    await _loadLyrics(track);
    notifyListeners();
    _publish();

    _listen();
    await _engine.play();
    _app?.markPlayed(id);

    // 还缺封面或歌词 → 后台自动补一首（不打扰用户）
    _app?.ensureMetaFor(track);
  }

  /// 在列表里点歌 / 点「播放全部」。
  ///
  /// 用户点的是「一批歌里的某一首」，期待顺着这批往下放；而单曲循环
  /// 通常是上一次收听留下的状态，会让新点的一首无限重播。所以这里先切成
  /// 列表循环再播。随机播放是用户主动选的模式，不动它。
  Future<void> playFromList(String id, {required List<String> queue}) {
    if (playMode == PlayMode.repeatOne && queue.length > 1) {
      playMode = PlayMode.repeatAll;
    }
    return play(id, queue: queue);
  }

  Future<void> toggle() async {
    if (playing) {
      playing = false;
      notifyListeners();
      await _engine.pause();
    } else {
      playing = true;
      notifyListeners();
      _publish();
      if (position >= duration) {
        position = Duration.zero;
        _syncPosition();
      }
      // 把 UI 上的进度同步给引擎，否则会从 0 开始
      await _engine.seek(position);
      _listen();
      await _engine.play();
    }
  }

  Future<void> next({bool auto = false}) async {
    // 单曲循环：播完原地重播（手动点下一首不在此列）
    if (playMode == PlayMode.repeatOne && auto) {
      await seekRatio(0);
      await _engine.play();
      return;
    }
    if (queue.isEmpty) return;
    final i = queue.indexOf(currentId);
    // 随机：保证和当前不是同一首；其余模式都走列表顺序（到尾自动回头）
    final n = playMode == PlayMode.shuffle
        ? (() {
            if (queue.length <= 1) return 0;
            var r = i;
            while (r == i) {
              r = DateTime.now().microsecond % queue.length;
            }
            return r;
          })()
        : (i + 1) % queue.length;
    await play(queue[n]);
  }

  Future<void> prev() async {
    if (position > const Duration(seconds: 4)) {
      await seekRatio(0);
      return;
    }
    if (queue.isEmpty) return;
    final i = queue.indexOf(currentId);
    final n = (i - 1 + queue.length) % queue.length;
    await play(queue[n]);
  }

  Future<void> seekRatio(double ratio) async {
    final target = Duration(
      milliseconds: (duration.inMilliseconds * ratio.clamp(0.0, 1.0)).round(),
    );
    await seekTo(target);
  }

  /// 点歌词行跳播用
  Future<void> seekTo(Duration target) async {
    if (target < Duration.zero) target = Duration.zero;
    if (target > duration) target = duration;
    position = target;
    _syncPosition();
    lyricIndex = _indexFor(target);
    notifyListeners();
    await _engine.seek(target);
  }

  void toggleMode() {
    mode = mode == PlayerMode.lyric ? PlayerMode.cover : PlayerMode.lyric;
    notifyListeners();
  }

  void _listen() {
    _posSub?.cancel();
    _lastPublish = null;
    _posSub = _engine.positions.listen((p) {
      position = p;
      pos.value = p; // 只唤醒进度条

      // 歌词行变了才刷新整页（迷你条要换行、播放页要滚动歌词）
      final idx = _indexFor(p);
      if (idx != lyricIndex) {
        lyricIndex = idx;
        notifyListeners();
      }

      // 系统控件不需要每 500ms 更新，2 秒一次就够
      final now = DateTime.now().millisecondsSinceEpoch;
      if (_lastPublish == null || now - _lastPublish! > 2000) {
        _lastPublish = now;
        _publish();
      }
    });
  }

  int? _lastPublish;

  @override
  void dispose() {
    _handler?.onPlay = null;
    _handler?.onPause = null;
    _handler?.onNext = null;
    _handler?.onPrev = null;
    _handler?.onSeek = null;
    _handler?.onStop = null;
    _posSub?.cancel();
    pos.dispose();
    _engine.dispose();
    super.dispose();
  }
}
