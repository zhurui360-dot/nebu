import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';

import '../../models/models.dart';

/// 把播放状态"广播"给系统：通知栏、锁屏、耳机按键、蓝牙设备都能看到并控制。
///
/// 这里不做实际发声——真正的播放还是 PlayerState + AudioEngine，
/// 本类只负责：
///   1) 把当前曲目/进度/播放状态推给系统（publish）
///   2) 收到系统控件的指令后回调给 PlayerState（onPlay/onPause/...）
class CloudTuneHandler extends BaseAudioHandler with SeekHandler {
  VoidCallback? onPlay;
  VoidCallback? onPause;
  VoidCallback? onNext;
  VoidCallback? onPrev;
  void Function(Duration position)? onSeek;
  VoidCallback? onStop;

  void publish({
    required Track track,
    required bool playing,
    required Duration position,
    required Duration duration,
  }) {
    mediaItem.add(
      MediaItem(
        id: track.id,
        title: track.title,
        artist: track.artist,
        album: track.albumName.isEmpty ? null : track.albumName,
        duration: duration,
        artUri: (track.coverPath != null && track.coverPath!.isNotEmpty)
            ? Uri.file(track.coverPath!)
            : null,
        displayTitle: track.title,
        displaySubtitle: track.artist,
      ),
    );

    playbackState.add(
      PlaybackState(
        controls: [
          const MediaControl(
            label: '上一首',
            action: MediaAction.skipToPrevious,
            androidIcon: 'drawable://ic_skip_previous',
          ),
          if (playing)
            const MediaControl(
              label: '暂停',
              action: MediaAction.pause,
              androidIcon: 'drawable://ic_pause',
            )
          else
            const MediaControl(
              label: '播放',
              action: MediaAction.play,
              androidIcon: 'drawable://ic_play_arrow',
            ),
          const MediaControl(
            label: '下一首',
            action: MediaAction.skipToNext,
            androidIcon: 'drawable://ic_skip_next',
          ),
        ],
        // 通知栏紧凑视图里放这三个按钮
        androidCompactActionIndices: const [0, 1, 2],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        playing: playing,
        processingState: AudioProcessingState.ready,
        updatePosition: position,
        bufferedPosition: position,
        speed: 1.0,
      ),
    );
  }

  @override
  Future<void> play() async => onPlay?.call();

  @override
  Future<void> pause() async => onPause?.call();

  @override
  Future<void> skipToNext() async => onNext?.call();

  @override
  Future<void> skipToPrevious() async => onPrev?.call();

  @override
  Future<void> seek(Duration position) async => onSeek?.call(position);

  @override
  Future<void> stop() async => onStop?.call();
}
