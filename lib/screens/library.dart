import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/strings.dart';
import '../state/app_state.dart';
import '../state/player_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/sheets.dart';
import 'category.dart';
import 'sources.dart';
import '../utils/transitions.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final app = context.watch<AppState>();
    final player = context.watch<PlayerState>();
    final l = L.of(context);
    final bottomPad = player.showMiniPlayer ? 176.0 : 110.0;

    if (app.tracks.isEmpty) {
      return SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.only(top: 4, bottom: 110),
          children: [
            PageHeader(title: l.t('lib.title'), eyebrow: l.songs(0)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  const SizedBox(height: 40),
                  Icon(Icons.library_music_outlined, size: 40, color: p.t3),
                  const SizedBox(height: 14),
                  Text(l.t('lib.empty'), style: TextStyle(fontSize: 14, color: p.t2)),
                  const SizedBox(height: 6),
                  Text(l.t('lib.emptySub'),
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12.5, height: 1.6, color: p.t3)),
                  const SizedBox(height: 18),
                  SizedBox(
                    height: 44,
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).push(
                        slidePageRoute(const SourcesScreen()),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: p.brandSolid,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
                      ),
                      child: Text(l.t('lib.goImport'),
                          style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: EdgeInsets.only(top: 4, bottom: bottomPad),
        children: [
          PageHeader(
            title: l.t('lib.title'),
            eyebrow:
                '${l.t('lib.importedDirs', {'n': '${app.importedDirs}'})} · ${l.songs(app.tracks.length)}',
            actions: [
              RoundIcon(Icons.search_rounded, tooltip: l.tabSearch, onTap: () => app.setTab(2)),
              const SizedBox(width: 10),
            ],
          ),

          // 分类入口
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                _LibTile(
                  icon: Icons.music_note_rounded,
                  label: l.t('lib.allSongs'),
                  count: '${app.tracks.length}',
                  colors: const [Color(0xFF7C5CFF), Color(0xFFA78BFA)],
                  onTap: () => pushCategory(context, CategoryKind.all),
                ),
                _LibTile(
                  icon: Icons.person_rounded,
                  label: l.t('lib.artists'),
                  count: '${app.artistCount}',
                  colors: const [Color(0xFF5B8BFF), Color(0xFF8FB4FF)],
                  onTap: () => pushCategory(context, CategoryKind.artists),
                ),
                _LibTile(
                  icon: Icons.album_rounded,
                  label: l.t('lib.albums'),
                  count: '${app.albumList.length}',
                  colors: const [Color(0xFF1F9E8A), Color(0xFF5FD3BE)],
                  onTap: () => pushCategory(context, CategoryKind.albums),
                ),
                _LibTile(
                  icon: Icons.queue_music_rounded,
                  label: l.t('lib.myPlaylists'),
                  count: '${app.playlistCount}',
                  colors: const [Color(0xFFE8744F), Color(0xFFF5A78D)],
                  onTap: () => pushCategory(context, CategoryKind.playlists),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 「我的」这一块可以由用户自己编辑展示哪些行（本地持久化）
          SectionHead(l.t('lib.mine'),
              action: l.t('lib.edit'), onTap: () => showMyRowsSheet(context)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              children: [
                if (app.isMyRowVisible('favorites'))
                  _MyRow(
                    icon: Icons.favorite_rounded,
                    tint: const Color(0xFFE4566A),
                    title: l.t('lib.favorites'),
                    sub: l.t('lib.favSub',
                        {'n': '${app.favoritesTracks.length}'}),
                    count: '${app.favorites.length}',
                    onTap: () => pushCategory(context, CategoryKind.favorites),
                  ),
                if (app.isMyRowVisible('bookmarks'))
                  _MyRow(
                    icon: Icons.bookmark_rounded,
                    tint: const Color(0xFFC07600),
                    title: l.t('lib.collections'),
                    sub: l.t('lib.favAlbums'),
                    count: '${app.albumFavorites.length}',
                    onTap: () => pushCategory(context, CategoryKind.bookmarks),
                  ),
                if (app.isMyRowVisible('recent'))
                  _MyRow(
                    icon: Icons.history_rounded,
                    tint: const Color(0xFF7C5CFF),
                    title: l.t('home.recent'),
                    sub: l.t('lib.byTime'),
                    count: '${app.recent.length}',
                    onTap: () => pushCategory(context, CategoryKind.recent),
                  ),
                if (app.isMyRowVisible('downloads'))
                  _MyRow(
                    icon: Icons.download_rounded,
                    tint: const Color(0xFF12907A),
                    title: l.t('lib.downloads'),
                    sub: l.t('lib.downloadsSub'),
                    count: '${app.cachedIds.length}',
                    onTap: () => pushCategory(context, CategoryKind.downloads),
                  ),
                // 自建歌单也能放进「我的」（在编辑里开关）
                for (final pl in app.playlists)
                  if (app.isMyRowVisible('pl:${pl.id}'))
                    _MyRow(
                      icon: Icons.queue_music_rounded,
                      tint: const Color(0xFFE8744F),
                      title: pl.name,
                      sub: l.t('lib.myPlaylists'),
                      count: '${pl.trackIds.length}',
                      onTap: () => pushCategory(
                        context,
                        CategoryKind.playlists,
                        playlistId: pl.id,
                      ),
                    ),
                // 全部关掉时给一句提示，别让这一块莫名其妙是空的
                if (AppState.myRowKeys.every((k) => !app.isMyRowVisible(k)) &&
                    app.playlists
                        .every((pl) => !app.isMyRowVisible('pl:${pl.id}')))
                  InkWell(
                    onTap: () => showMyRowsSheet(context),
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 14),
                      child: Row(
                        children: [
                          Icon(Icons.visibility_off_rounded,
                              size: 18, color: p.t3),
                          const SizedBox(width: 10),
                          Text(l.t('lib.allHidden'),
                              style:
                                  TextStyle(fontSize: 12.5, color: p.t3)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          SectionHead(l.t('lib.recentAdded'), action: l.all,
              onTap: () => pushCategory(context, CategoryKind.all)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              children: [
                for (final t in app.latestTracks)
                  Builder(builder: (ctx) {
                    final id = t.id;
                    return TrackTile(
                      track: t,
                      subtitle: '${t.artist} · ${app.albumOf(t.albumId).name}',
                      playing: player.currentId == id,
                      trailing: player.currentId == id ? const Equalizer() : null,
                                            onLongPress: () => showTrackActionsSheet(context, track: t),
onTap: () => player.playFromList(id,
                          queue: app.tracks.map((e) => e.id).toList()),
                    );
                  }),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LibTile extends StatelessWidget {
  const _LibTile({
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
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: colors,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: colors.first.op(.45),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                      spreadRadius: -10,
                    ),
                  ],
                ),
                child: Icon(icon, size: 21, color: Colors.white),
              ),
              const SizedBox(height: 6),
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

class _MyRow extends StatelessWidget {
  const _MyRow({
    required this.icon,
    required this.tint,
    required this.title,
    required this.sub,
    required this.count,
    required this.onTap,
  });

  final IconData icon;
  final Color tint;
  final String title;
  final String sub;
  final String count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: tint.op(.13),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 20, color: tint),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: p.t1)),
                  const SizedBox(height: 3),
                  Text(sub, style: TextStyle(fontSize: 12, color: p.t3)),
                ],
              ),
            ),
            Text(count, style: TextStyle(fontSize: 12, color: p.t3)),
            Icon(Icons.chevron_right_rounded, size: 16, color: p.t3),
          ],
        ),
      ),
    );
  }
}
