import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

/// 播放内核。
///
/// V1 的策略：
///  - 有直链（url != null）→ 交给 just_audio 真实解码播放；
///  - 没有直链（网盘未接入 / 授权过期 / 解码失败）→ 走模拟进度，保证 UI 与交互完整。
///
/// 这样 Demo 阶段不出声也不会崩，接入网盘后只要把 url 填进 Track 即可出声。
class AudioEngine {
  AudioEngine() {
    _procSub = _player.processingStateStream.listen((s) {
      if (s == ProcessingState.completed) onComplete?.call();
    });
  }

  final AudioPlayer _player = AudioPlayer();
  final _simCtrl = StreamController<Duration>.broadcast();
  StreamSubscription<ProcessingState>? _procSub;
  Timer? _timer;

  bool simulated = true;
  Duration total = Duration.zero;
  Duration _pos = Duration.zero;

  /// 播放结束回调（用于自动下一首）
  VoidCallback? onComplete;

  /// 直链播放失败的原因（null 表示正常）
  String? lastError;

  /// 失败回调：界面据此提示用户，而不是默默静音
  void Function(String message)? onError;

  /// 上一次是不是因为直链播不了而退化的无声预览
  bool get degraded => simulated && lastError != null;

  Duration get position => simulated ? _pos : _player.position;

  /// 真实播放时用播放器的时长；模拟时用已知时长。
  /// 标签里读不到时长是常事（部分 MP3/FLAC），不能因此不给进度条。
  Duration get duration {
    if (!simulated) {
      final d = _player.duration;
      if (d != null && d > Duration.zero) return d;
    }
    return total;
  }

  Stream<Duration> get positions =>
      simulated ? _simCtrl.stream : _player.positionStream;

  Future<void> load({
    required String? url,
    required Duration duration,
    Map<String, String>? headers,
  }) async {
    _timer?.cancel();
    _pos = Duration.zero;
    total = duration;
    lastError = null;

    if (url == null) {
      simulated = true;
      // 时长读不到时给个兜底，否则进度条卡在 0 看起来像"不能播"
      if (total <= Duration.zero) total = const Duration(seconds: 240);
      return;
    }
    try {
      simulated = false;
      await _player.setUrl(url, headers: headers);
      total = _player.duration ?? duration;
    } catch (e) {
      // 直链失效 / 格式不支持 → 回落模拟，但要记下原因并通知界面
      simulated = true;
      lastError = _describe(e);
      if (total <= Duration.zero) total = const Duration(seconds: 240);
      onError?.call(lastError!);
    }
  }

  Future<void> play() async {
    if (simulated) {
      _startTick();
      return;
    }
    try {
      await _player.play();
    } catch (e) {
      lastError = _describe(e);
      simulated = true;
      if (total <= Duration.zero) total = const Duration(seconds: 240);
      _startTick();
      onError?.call(lastError!);
    }
  }

  /// 把底层异常翻译成人看得懂的原因
  static String _describe(Object e) {
    final raw = '$e';
    if (raw.contains('PlayerException')) {
      final code = RegExp(r'PlayerException\((\d+)').firstMatch(raw)?.group(1);
      final msg = RegExp(r'message://s*([^,}]+)').firstMatch(raw)?.group(1)?.trim() ?? '';
      switch (code) {
        case '401':
          return '服务器拒绝播放（401）：账号或应用密码不对，请到网盘源重新连接';
        case '403':
          return '服务器拒绝播放（403）：这个账号没有该文件的读取权限';
        case '404':
          return '文件不存在（404）：路径可能变过，重新导入一次这个目录';
        default:
          return '播放失败（code=$code）${msg.isEmpty ? '' : '：$msg'}';
      }
    }
    if (raw.contains('SSL') ||
        raw.contains('certificate') ||
        raw.contains('Handshake')) {
      return '证书不受信任：NAS 自签证书请换成受信任证书，或改用 http:// 地址';
    }
    if (raw.contains('SocketException') || raw.contains('TimeoutException')) {
      return '连不上服务器：检查网络，或这个地址在手机上访问不到';
    }
    if (raw.contains('Unable to instantiate') ||
        raw.contains('Unsupported') ||
        raw.contains('ExoPlaybackException')) {
      return '这个音频格式手机放不了，或直链不是标准音频流';
    }
    return raw.length > 120 ? '${raw.substring(0, 120)}…' : raw;
  }

  Future<void> pause() async {
    if (simulated) {
      _timer?.cancel();
    } else {
      await _player.pause();
    }
  }

  Future<void> seek(Duration d) async {
    if (simulated) {
      _pos = d;
      _simCtrl.add(d);
    } else {
      await _player.seek(d);
    }
  }

  void _startTick() {
    _timer?.cancel();
    const step = Duration(milliseconds: 500);
    _timer = Timer.periodic(step, (_) {
      _pos += step;
      if (_pos >= total) {
        _pos = total;
        _simCtrl.add(_pos);
        _timer?.cancel();
        onComplete?.call();
      } else {
        _simCtrl.add(_pos);
      }
    });
  }

  void dispose() {
    _timer?.cancel();
    _procSub?.cancel();
    _player.dispose();
    _simCtrl.close();
  }
}
