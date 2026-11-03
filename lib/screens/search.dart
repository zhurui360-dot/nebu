import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../l10n/strings.dart';
import '../state/app_state.dart';
import '../state/player_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/sheets.dart';
import 'category.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  String _type = 'all';
  String _query = '';

  /// 类型筛选（标签随界面语言变化）
  static List<List<String>> _types(L l) => [
        ['all', l.all],
        ['song', l.t('search.songs')],
        ['album', l.t('lib.albums')],
        ['artist', l.t('lib.artists')],
        ['pl', l.t('home.playlists')],
      ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final l = L.of(context);
    final types = _types(l);
    final app = context.watch<AppState>();
    final player = context.watch<PlayerState>();
    final q = _query.trim().toLowerCase();

    final hits = app.tracks.where((t) {
      if (q.isEmpty) return false;
      return t.title.toLowerCase().contains(q) ||
          t.artist.toLowerCase().contains(q) ||
          app.albumOf(t.albumId).name.toLowerCase().contains(q);
    }).toList();

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
            // 搜索框也走玻璃，和全站材质统一
            child: Glass(
              radius: 14,
              blur: Blur.thin,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: SizedBox(
                height: 44,
                child: Row(
                children: [
                  Icon(Icons.search_rounded, size: 18, color: p.t3),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      onChanged: (v) => setState(() => _query = v),
                      onSubmitted: (v) => context.read<AppState>().addSearchTerm(v),
                      textInputAction: TextInputAction.search,
                      style: TextStyle(fontSize: 14.5, color: p.t1),
                      decoration: InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        hintText: l.t('search.hint'),
                        hintStyle: TextStyle(fontSize: 14.5, color: p.t3),
                      ),
                    ),
                  ),
                  if (_query.isNotEmpty)
                    GestureDetector(
                      onTap: () {
                        _controller.clear();
                        setState(() => _query = '');
                      },
                      child: Icon(Icons.close_rounded, size: 16, color: p.t3),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 类型筛选：只搜音乐库，不按网盘筛
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: types.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final on = _type == types[i][0];
                return GestureDetector(
                  onTap: () => setState(() => _type = types[i][0]),
                  child: Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: on ? p.t1 : Colors.transparent,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: on ? p.t1 : p.line),
                    ),
                    child: Text(
                      types[i][1],
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: on ? p.bg : p.t2,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),

          Expanded(
            child: _query.isEmpty
                ? _history(context, app, player)
                : _results(context, app, player, hits),
          ),
        ],
      ),
    );
  }

  Widget _history(BuildContext context, AppState app, PlayerState player) {
    final p = P.of(context);
    final l = L.of(context);
    final bottomPad = player.showMiniPlayer ? 176.0 : 110.0;
    final hist = app.searchHistory;
    final recent = app.recentTracks.take(3).toList();

    return ListView(
      padding: EdgeInsets.only(bottom: bottomPad),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
          child: Row(
            children: [
              Text(l.t('search.recent'),
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.1,
                      color: p.t3)),
              const Spacer(),
              if (hist.isNotEmpty)
                GestureDetector(
                  onTap: () => app.clearSearchHistory(),
                  child: Text(l.t('search.clear'),
                      style: TextStyle(fontSize: 12.5, color: p.t2)),
                ),
            ],
          ),
        ),
        if (hist.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Text(l.t('search.noHistory'),
                style: TextStyle(fontSize: 12.5, color: p.t3)),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                for (final h in hist)
                  GestureDetector(
                    onTap: () {
                      _controller.text = h;
                      setState(() {
                        _query = h;
                        _type = 'all';
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: p.surface,
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(color: p.line),
                      ),
                      child: Text(h, style: TextStyle(fontSize: 12.5, color: p.t2)),
                    ),
                  ),
              ],
            ),
          ),

        // 只有真的有播放记录时才显示，不再放写死的示例
        if (recent.isNotEmpty) ...[
          const SizedBox(height: 22),
          SectionHead(l.t('home.recent')),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              children: [
                for (final t in recent)
                  TrackTile(
                    track: t,
                    subtitle: '${t.artist} · ${app.albumOf(t.albumId).name}',
                    playing: player.currentId == t.id,
                    trailing: player.currentId == t.id ? const Equalizer() : null,
                                        onLongPress: () => showTrackActionsSheet(context, track: t),
onTap: () => player.playFromList(t.id, queue: app.recent),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _results(BuildContext context, AppState app, PlayerState player, List<Track> hits) {
    final p = P.of(context);
    final l = L.of(context);
    final bottomPad = player.showMiniPlayer ? 176.0 : 110.0;

    if (_type == 'album') {
      final albums = app.albumList
          .where((a) => a.name.contains(_query) || a.artist.contains(_query))
          .toList();
      return ListView(
        padding: EdgeInsets.only(bottom: bottomPad),
        children: [
          SectionHead(l.albums(albums.length)),
          for (final a in albums)
            InkWell(
              onTap: () => pushCategory(context, CategoryKind.albums),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
                child: Row(
                  children: [
                    CoverArt(albumId: a.id),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(a.name,
                              style: TextStyle(
                                  fontSize: 14.5, fontWeight: FontWeight.w600, color: p.t1)),
                          const SizedBox(height: 3),
                          Text('${a.artist} · ${a.year}',
                              style: TextStyle(fontSize: 12, color: p.t3)),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, size: 16, color: p.t3),
                  ],
                ),
              ),
            ),
        ],
      );
    }

    if (_type == 'artist') {
      final q = _query.trim().toLowerCase();
      final byArtist = <String, List<Track>>{};
      for (final t in app.tracks) {
        byArtist.putIfAbsent(t.artist, () => []).add(t);
      }
      final all = byArtist.entries.toList()
        ..sort((a, b) => b.value.length.compareTo(a.value.length));
      final named =
          all.where((e) => e.key.toLowerCase().contains(q)).toList();
      final entries = named.isNotEmpty
          ? named
          : all
              .where((e) => e.value.any((t) => t.title.toLowerCase().contains(q)))
              .toList();

      return ListView(
        padding: EdgeInsets.only(bottom: bottomPad),
        children: [
          SectionHead(l.artists(entries.length)),
          if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Text(l.t('search.empty'),
                  style: TextStyle(fontSize: 12, color: p.t3)),
            )
          else
            for (final e in entries)
              InkWell(
                onTap: () => pushCategory(context, CategoryKind.all),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient:
                              LinearGradient(colors: [Color(0xFF5B8BFF), Color(0xFF8FB4FF)]),
                        ),
                        child: const Icon(Icons.person_rounded, color: Colors.white, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(e.key,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 14.5, fontWeight: FontWeight.w600, color: p.t1)),
                            const SizedBox(height: 3),
                            Text(
                              '${l.songs(e.value.length)} · ${l.albums(e.value.map((t) => t.albumId).toSet().length)}',
                              style: TextStyle(fontSize: 12, color: p.t3),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded, size: 16, color: p.t3),
                    ],
                  ),
                ),
              ),
        ],
      );
    }

    if (_type == 'pl') {
      // 智能歌单：内容全部来自真实曲库统计
      final q = _query.trim().toLowerCase();
      final items = <(String, String, String?, CategoryKind)>[
        (l.t('lib.allSongs'), l.songs(app.tracks.length),
            app.tracks.isEmpty ? null : app.tracks.first.albumId, CategoryKind.all),
        (l.t('lib.favorites'), l.songs(app.favoritesTracks.length),
            app.favoritesTracks.isEmpty ? null : app.favoritesTracks.first.albumId,
            CategoryKind.favorites),
        (l.t('home.recent'), l.songs(app.recentTracks.length),
            app.recentTracks.isEmpty ? null : app.recentTracks.first.albumId,
            CategoryKind.recent),
        (l.t('search.cached'), l.songs(app.cachedTracks.length),
            app.cachedTracks.isEmpty ? null : app.cachedTracks.first.albumId,
            CategoryKind.downloads),
      ].where((e) => q.isEmpty || e.$1.toLowerCase().contains(q)).toList();

      return ListView(
        padding: EdgeInsets.only(bottom: bottomPad),
        children: [
          SectionHead(l.playlists(items.length)),
          for (final pl in items)
            InkWell(
              onTap: () => pushCategory(context, pl.$4),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
                child: Row(
                  children: [
                    CoverArt(albumId: pl.$3 ?? ''),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(pl.$1,
                              style: TextStyle(
                                  fontSize: 14.5, fontWeight: FontWeight.w600, color: p.t1)),
                          const SizedBox(height: 3),
                          Text(pl.$2,
                              style: TextStyle(fontSize: 12, color: p.t3)),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, size: 16, color: p.t3),
                  ],
                ),
              ),
            ),
        ],
      );
    }

    if (hits.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('没找到「$_query」', style: TextStyle(fontSize: 13, color: p.t3)),
            const SizedBox(height: 6),
            Text(l.t('search.empty'),
                style: TextStyle(fontSize: 12.5, color: p.t3)),
          ],
        ),
      );
    }

    return ListView(
      padding: EdgeInsets.only(bottom: bottomPad),
      children: [
        SectionHead(l.t('search.hits', {'n': '${hits.length}'}),
            action: l.t('search.byRelevance')),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(
            children: [
              for (final t in hits)
                TrackTile(
                  track: t,
                  subtitle: '${t.artist} · ${app.albumOf(t.albumId).name} · ${t.format.label}',
                  playing: player.currentId == t.id,
                  trailing: player.currentId == t.id ? const Equalizer() : null,
                                    onLongPress: () => showTrackActionsSheet(context, track: t),
onTap: () {
                    context.read<AppState>().addSearchTerm(_query);
                    player.playFromList(t.id, queue: hits.map((e) => e.id).toList());
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }
}
