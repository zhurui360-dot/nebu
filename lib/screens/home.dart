import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/lang.dart';
import '../l10n/strings.dart';
import '../state/app_state.dart';
import '../state/player_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/sheets.dart';
import 'category.dart';
import 'player.dart';
import 'sources.dart';
import '../utils/transitions.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final app = context.watch<AppState>();
    final player = context.watch<PlayerState>();
    final bottomPad = player.showMiniPlayer ? 176.0 : 110.0;

    final l = L.of(context);

    // 正式版首次打开是空库：直接给一条去导入的路径
    if (app.tracks.isEmpty) {
      return _EmptyHome(today: _todayText(l));
    }

    final current = player.current;

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: EdgeInsets.only(top: 4, bottom: bottomPad),
        children: [
          PageHeader(
            title: l.t('home.myMusic'),
            eyebrow: _todayText(l),
            // 右上角只留搜索；原来那个渐变圆圈没有实际用途，已去掉
            actions: [
              RoundIcon(Icons.search_rounded, tooltip: l.tabSearch, onTap: () => app.setTab(2)),
              const SizedBox(width: 10),
            ],
          ),

          // 继续播放
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Glass(
              radius: R.xl,
              fill: p.brand.op(p.dark ? .06 : .05),
              padding: const EdgeInsets.all(14),
              child: InkWell(
                onTap: () => showPlayer(context),
                borderRadius: BorderRadius.circular(R.xl),
                child: Column(
                  children: [
                    Row(
                      children: [
                        CoverArt(albumId: current.albumId, size: 54, radius: 14, coverPath: current.coverPath),
                        const SizedBox(width: 13),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // 进度走独立通知通道：只有这一行会随播放刷新，
                              // 首页其余部分不跟着 5Hz 重建
                              ValueListenableBuilder<Duration>(
                                valueListenable: player.pos,
                                builder: (context, pos, _) => Text(
                                  player.playing
                                      ? l.t('home.nowPlaying')
                                      : '${l.t('home.resume')} · ${_fmt(pos)}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: p.brand,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                current.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: p.t1,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '${current.artist} · ${app.albumOf(current.albumId).name}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12.5, color: p.t2),
                              ),
                            ],
                          ),
                        ),
                        GestureDetector(
                          onTap: () async {
                            if (!player.playing) {
                              // 首页这颗按钮是「随手放着」：进来就随机播放
                              // （在队列里打散，避免总从那首的顺序往下走）
                              player.playMode = PlayMode.shuffle;
                              await player.play(
                                current.id,
                                queue: app.recent.isEmpty
                                    ? null
                                    : app.recent,
                              );
                            } else {
                              await player.toggle();
                            }
                          },
                          child: Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [Color(0xFF6A45E8), Color(0xFF8B5CFF)],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF6A45E8).op(.5),
                                  blurRadius: 20,
                                  offset: const Offset(0, 8),
                                  spreadRadius: -8,
                                ),
                              ],
                            ),
                            child: Icon(
                              player.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 22,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: player.progress,
                        minHeight: 2,
                        backgroundColor: p.line2,
                        valueColor: const AlwaysStoppedAnimation(Color(0xFF8B7BFF)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 快捷入口
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                _Quick(
                  icon: Icons.history_rounded,
                  label: l.t('home.recent'),
                  count: l.songs(app.recent.length),
                  colors: const [Color(0xFF6A45E8), Color(0xFF9B7BFF)],
                  onTap: () => pushCategory(context, CategoryKind.recent),
                ),
                _Quick(
                  icon: Icons.favorite_rounded,
                  label: l.t('home.favorites'),
                  count: l.songs(app.favorites.length),
                  colors: const [Color(0xFFE8557A), Color(0xFFFF9AAE)],
                  onTap: () => pushCategory(context, CategoryKind.favorites),
                ),
                _Quick(
                  icon: Icons.download_rounded,
                  label: l.t('home.cached'),
                  count: l.songs(app.cachedIds.length),
                  colors: const [Color(0xFF1F9E8A), Color(0xFF5FE3C0)],
                  onTap: () => pushCategory(context, CategoryKind.downloads),
                ),
                _Quick(
                  icon: Icons.queue_music_rounded,
                  label: l.t('home.playlists'),
                  count: l.playlists(app.playlistCount),
                  colors: const [Color(0xFF2F6BE0), Color(0xFF4FC3F7)],
                  onTap: () => pushCategory(context, CategoryKind.playlists),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),

          SectionHead(l.t('home.recent'),
              action: '${l.all} ${app.recent.length}',
              onTap: () => pushCategory(context, CategoryKind.recent)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              children: [
                for (final t in app.recentTracks.take(AppState.homePreviewCount))
                  TrackTile(
                    track: t,
                    subtitle: '${t.artist} · ${app.albumOf(t.albumId).name}',
                    playing: t.id == player.currentId,
                    trailing: t.id == player.currentId ? const Equalizer() : null,
                                        onLongPress: () => showTrackActionsSheet(context, track: t),
onTap: () => player.playFromList(t.id, queue: app.recent),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 顶部那行日期：按语言给不同写法（不引 intl，够用就行）
  static String _todayText(L l) {
    final now = DateTime.now();
    final i = now.weekday - 1;
    switch (l.lang) {
      case AppLang.zhHans:
      case AppLang.zhHant:
        const zh = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
        return '${now.month}月${now.day}日 · ${zh[i]}';
      case AppLang.ja:
        const ja = ['月', '火', '水', '木', '金', '土', '日'];
        return '${now.month}月${now.day}日 · ${ja[i]}曜';
      case AppLang.ko:
        const ko = ['월', '화', '수', '목', '금', '토', '일'];
        return '${now.month}월 ${now.day}일 · ${ko[i]}요일';
      default:
        const en = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
        return '${en[i]} · ${now.month}/${now.day}';
    }
  }

  static String _fmt(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
}

/// 曲库为空时的首页
class _EmptyHome extends StatelessWidget {
  const _EmptyHome({required this.today});
  final String today;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final l = L.of(context);
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.only(top: 4, bottom: 110),
        children: [
          PageHeader(title: l.t('home.myMusic'), eyebrow: today),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Glass(
              radius: R.xl,
              fill: p.brand.op(p.dark ? .06 : .05),
              padding: const EdgeInsets.fromLTRB(20, 26, 20, 24),
              child: Column(
                children: [
                  Container(
                    width: 62,
                    height: 62,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [p.brand, p.brand2],
                      ),
                    ),
                    child: const Icon(Icons.cloud_download_outlined, size: 28, color: Colors.white),
                  ),
                  const SizedBox(height: 16),
                  Text(l.t('home.empty'),
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: p.t1)),
                  const SizedBox(height: 8),
                  Text(
                    l.t('home.emptySub'),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13.5, height: 1.7, color: p.t2),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).push(
                        slidePageRoute(const SourcesScreen()),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: p.brandSolid,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text(l.t('home.connectCloud'),
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 22),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.t('home.howTo'),
                    style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.1, color: p.t3)),
                const SizedBox(height: 10),
                _Step(p: p, index: 1, text: l.t('home.step1')),
                _Step(p: p, index: 2, text: l.t('home.step2')),
                _Step(p: p, index: 3, text: l.t('home.step3')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.p, required this.index, required this.text});
  final P p;
  final int index;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: p.brand.op(.12), shape: BoxShape.circle),
            child: Text('$index',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: p.brand)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 13.5, height: 1.6, color: p.t2)),
          ),
        ],
      ),
    );
  }
}

class _Quick extends StatelessWidget {
  const _Quick({
    required this.icon,
    required this.label,
    required this.count,
    required this.colors,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String count;
  final List<Color> colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: colors,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 17, color: Colors.white),
              ),
              const SizedBox(height: 7),
              Text(label,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.t1)),
              const SizedBox(height: 2),
              Text(count, style: TextStyle(fontSize: 11, color: p.t3)),
            ],
          ),
        ),
      ),
    );
  }
}
