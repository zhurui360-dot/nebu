import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../screens/player.dart' show showPlayer;
import '../state/app_state.dart';
import '../state/player_state.dart';
import '../theme/app_theme.dart';
import 'common.dart';

/// 列表页（全部歌曲等）底部的悬浮播放控件。
///
/// 推到二级页面后没有导航栏那条迷你条，所以正在放歌时在列表底部浮一片玻璃：
/// 封面 + 歌名 + 当前这句歌词 + 上一首/播放/下一首，点文字区进播放页。
/// 宽度只占屏幕 3/4，居中浮着，不压满整行。
class FloatingPlayerBar extends StatelessWidget {
  const FloatingPlayerBar({super.key});

  /// 屏宽占比
  static const _widthFactor = .75;

  /// 第二行：有歌词就显示当前这句，没有就退回歌手
  String _secondLine(PlayerState player, Track track) {
    if (player.lyrics.isNotEmpty) {
      final i = player.lyricIndex.clamp(0, player.lyrics.length - 1).toInt();
      final line = player.lyrics[i].text.trim();
      if (line.isNotEmpty) return line;
    }
    return track.artist;
  }

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final player = context.watch<PlayerState>();
    final app = context.watch<AppState>();

    if (player.currentId.isEmpty) return const SizedBox.shrink();
    final track = player.current;
    if (track.id.isEmpty) return const SizedBox.shrink();

    final cover = track.coverPath ?? app.coverOfAlbum(track.albumId);
    final second = _secondLine(player, track);
    final showingLyric = player.lyrics.isNotEmpty && second != track.artist;

    return Padding(
      // 底部留一指的空白，浮在列表内容之上
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 16),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * _widthFactor,
          ),
          child: Glass(
            radius: R.lg,
            blur: Blur.regular,
            fill: p.dockFill,
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    // 封面 + 文字：点这里进播放页
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => showPlayer(context),
                        child: Row(
                          children: [
                            CoverArt(
                              albumId: track.albumId,
                              coverPath: cover,
                              size: 42,
                              radius: 11,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(track.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: p.t1)),
                                  const SizedBox(height: 1),
                                  SizedBox(
                                    height: 16,
                                    // 歌词逐行变化：竖向小幅滑动切换
                                    child: AnimatedSwitcher(
                                      duration:
                                          const Duration(milliseconds: 220),
                                      switchInCurve: Curves.easeOutCubic,
                                      transitionBuilder: (child, anim) =>
                                          FadeTransition(
                                        opacity: anim,
                                        child: SlideTransition(
                                          position: Tween(
                                            begin: const Offset(0, .55),
                                            end: Offset.zero,
                                          ).animate(anim),
                                          child: child,
                                        ),
                                      ),
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: Text(
                                          second,
                                          key: ValueKey<String>(second),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color:
                                                showingLyric ? p.t1 : p.t3,
                                            fontWeight: showingLyric
                                                ? FontWeight.w500
                                                : FontWeight.w400,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    // 按键按拇指尺寸给足：上一首/下一首 42，播放 56
                    RoundIcon(Icons.skip_previous_rounded,
                        size: 42, color: p.t2, onTap: player.prev),
                    RoundIcon(
                      player.playing
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      size: 56,
                      color: p.t1,
                      onTap: player.toggle,
                    ),
                    RoundIcon(Icons.skip_next_rounded,
                        size: 42, color: p.t2, onTap: player.next),
                  ],
                ),
                // 细进度线：只在播放时跟着动，独立订阅，不牵动整块控件
                const SizedBox(height: 5),
                ValueListenableBuilder<Duration>(
                  valueListenable: player.pos,
                  builder: (context, position, _) {
                    final total = player.duration.inMilliseconds;
                    final v = total <= 0
                        ? 0.0
                        : (position.inMilliseconds / total).clamp(0.0, 1.0);
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: v,
                        minHeight: 2.5,
                        backgroundColor: p.line2,
                        valueColor: AlwaysStoppedAnimation(p.brand),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


/// 把列表和悬浮播放条叠在一起：
/// 条子浮在内容之上（不占布局高度，周围的空白是透明的、点得到下面的列表），
/// 手指一滑就淡出躲开，停手 0.3 秒再浮回来。
class FloatingPlayerOverlay extends StatefulWidget {
  const FloatingPlayerOverlay({
    super.key,
    required this.child,
    this.enabled = true,
  });

  final Widget child;

  /// 多选等场景下临时关掉
  final bool enabled;

  @override
  State<FloatingPlayerOverlay> createState() => _FloatingPlayerOverlayState();
}

class _FloatingPlayerOverlayState extends State<FloatingPlayerOverlay> {
  bool _visible = true;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _hide() {
    if (!_visible) return;
    setState(() => _visible = false);
  }

  void _show() {
    if (!mounted || _visible) return;
    setState(() => _visible = true);
  }

  /// 滚动期间隐藏；滚动结束（或手指停下）再显示
  bool _onScroll(ScrollNotification n) {
    if (n is ScrollStartNotification ||
        n is ScrollUpdateNotification ||
        n is OverscrollNotification ||
        n is UserScrollNotification) {
      _hide();
      _timer?.cancel();
      // 惯性滑动时 ScrollUpdate 会持续来，最后一次之后的 400ms 才算「停手」
      _timer = Timer(const Duration(milliseconds: 420), _show);
    } else if (n is ScrollEndNotification) {
      _timer?.cancel();
      _timer = Timer(const Duration(milliseconds: 220), _show);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerState>();
    final show = widget.enabled && player.currentId.isNotEmpty;

    return Stack(
      children: [
        Positioned.fill(
          child: NotificationListener<ScrollNotification>(
            onNotification: _onScroll,
            child: widget.child,
          ),
        ),
        if (show)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: IgnorePointer(
              ignoring: !_visible,
              child: AnimatedSlide(
                offset: Offset(0, _visible ? 0 : .45),
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                child: AnimatedOpacity(
                  opacity: _visible ? 1 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: const FloatingPlayerBar(),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
