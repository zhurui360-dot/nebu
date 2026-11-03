import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../state/player_state.dart';
import '../theme/app_theme.dart';
import '../widgets/artist_avatar.dart';
import '../widgets/common.dart';
import '../widgets/floating_player.dart';
import '../widgets/sheets.dart';
import 'player.dart';
import '../utils/transitions.dart';

enum CategoryKind { all, artists, albums, playlists, favorites, bookmarks, recent, downloads }

extension CategoryKindX on CategoryKind {
  String get title => switch (this) {
        CategoryKind.all => '全部歌曲',
        CategoryKind.artists => '歌手',
        CategoryKind.albums => '专辑',
        CategoryKind.playlists => '歌单',
        CategoryKind.favorites => '我喜欢',
        CategoryKind.bookmarks => '收藏',
        CategoryKind.recent => '最近播放',
        CategoryKind.downloads => '下载列表',
      };
}

Future<void> pushCategory(
  BuildContext context,
  CategoryKind kind, {
  String? playlistId,
  String? sourceFilter,
}) {
  return Navigator.of(context).push(
    slidePageRoute(CategoryScreen(
      kind: kind,
      playlistId: playlistId,
      sourceFilter: sourceFilter,
    )),
  );
}

/// 直接打开某张专辑（播放页点专辑名、点「查看专辑」都走这里）
Future<void> pushAlbum(BuildContext context, Album album) {
  return Navigator.of(context).push(slidePageRoute(_AlbumScreen(album: album)));
}

/// 直接打开某位歌手（只列他自己的歌）
Future<void> pushArtist(BuildContext context, String artist) {
  return Navigator.of(context).push(
    slidePageRoute(CategoryScreen(kind: CategoryKind.all, artistFilter: artist)),
  );
}

/// 歌曲排序方式（全部歌曲 / 收藏 / 最近播放 等列表通用）
/// 排序维度。每个维度只有一条，点它一次升序、再点一次降序。
enum SongSortKey {
  added('添加时间'),
  created('创建时间'),
  title('歌名'),
  artist('歌手'),
  album('专辑'),
  duration('时长');

  const SongSortKey(this.label);
  final String label;

  /// 默认方向：时间和时长都是「大在前」，文字是 A→Z
  bool get descByDefault =>
      this == SongSortKey.added ||
      this == SongSortKey.created ||
      this == SongSortKey.duration;
}

/// 排序状态：维度 + 方向
class SongSort {
  const SongSort(this.key, this.desc);
  final SongSortKey key;
  final bool desc;

  SongSort toggled() => SongSort(key, !desc);

  /// 顺带把方向写进文案，列表副标题能直接显示
  String get label {
    switch (key) {
      case SongSortKey.added:
      case SongSortKey.created:
        return '${key.label} · ${desc ? '新→旧' : '旧→新'}';
      case SongSortKey.duration:
        return '${key.label} · ${desc ? '长→短' : '短→长'}';
      case SongSortKey.title:
      case SongSortKey.artist:
      case SongSortKey.album:
        return '${key.label} · ${desc ? 'Z→A' : 'A→Z'}';
    }
  }

  /// 按当前维度与方向排序（不改原列表）
  List<Track> apply(List<Track> input) {
    final out = List<Track>.from(input);
    int byTitle(Track a, Track b) =>
        a.title.toLowerCase().compareTo(b.title.toLowerCase());

    int raw(Track a, Track b) {
      switch (key) {
        case SongSortKey.added:
          // 老数据 addedAt 一致时用创建时间兜底，顺序才稳定
          final c = a.addedAt.compareTo(b.addedAt);
          return c != 0 ? c : a.createdAt.compareTo(b.createdAt);
        case SongSortKey.created:
          // 没读到文件时间（老库）→ 退回添加时间
          final ca = a.createdAt == 0 ? a.addedAt : a.createdAt;
          final cb = b.createdAt == 0 ? b.addedAt : b.createdAt;
          final c = ca.compareTo(cb);
          return c != 0 ? c : byTitle(a, b);
        case SongSortKey.title:
          return byTitle(a, b);
        case SongSortKey.artist:
          final c = a.artist.toLowerCase().compareTo(b.artist.toLowerCase());
          return c != 0 ? c : byTitle(a, b);
        case SongSortKey.album:
          final c =
              a.albumName.toLowerCase().compareTo(b.albumName.toLowerCase());
          return c != 0 ? c : byTitle(a, b);
        case SongSortKey.duration:
          return a.duration.compareTo(b.duration);
      }
    }

    out.sort((a, b) => desc ? raw(b, a) : raw(a, b));
    return out;
  }
}

class CategoryScreen extends StatefulWidget {
  const CategoryScreen({
    super.key,
    required this.kind,
    this.artistFilter,
    this.playlistId,
    this.sourceFilter,
  });

  final CategoryKind kind;

  /// 非空时只显示该歌手的歌（从「歌手」列表点进来时使用）
  final String? artistFilter;

  /// 非空时显示该自建歌单的曲目（从「歌单」列表点进来时使用）
  final String? playlistId;

  /// 非空时只看这个来源（本地 / 某个网盘账号）的歌
  final String? sourceFilter;

  @override
  State<CategoryScreen> createState() => _CategoryScreenState();
}

class _CategoryScreenState extends State<CategoryScreen> {
  final ScrollController _scroll = ScrollController();
  // 默认「添加时间 · 新→旧」
  SongSort _sort = const SongSort(SongSortKey.added, true);

  // ---- 多选（批量加入歌单） ----
  bool _selecting = false;
  final Set<String> _picked = <String>{};

  /// 当前页面是不是「一排歌」的列表（专辑/歌手/歌单这种索引页不参与多选）
  bool get _songList =>
      widget.playlistId != null ||
      widget.kind == CategoryKind.all ||
      widget.kind == CategoryKind.favorites ||
      widget.kind == CategoryKind.recent ||
      widget.kind == CategoryKind.downloads;

  /// 屏幕上这批歌（全选用），由 _content 建列表时顺手记下来
  List<Track> _visible = const [];

  void _startSelect() => setState(() {
        _selecting = true;
        _picked.clear();
      });

  void _endSelect() => setState(() {
        _selecting = false;
        _picked.clear();
      });

  void _togglePick(String id) => setState(() {
        if (!_picked.remove(id)) _picked.add(id);
      });

  void _pickAll() => setState(() {
        if (_picked.length == _visible.length) {
          _picked.clear();
        } else {
          _picked.addAll(_visible.map((e) => e.id));
        }
      });

  Future<void> _addPicked() async {
    if (_picked.isEmpty) return;
    final ids = List<String>.of(_picked);
    _endSelect();
    await showAddToPlaylistSheet(context, trackIds: ids);
  }

  /// 每行的右侧：多选时是勾选圈，平时是「正在播放」的跳动条
  Widget? _rowTrailing(Track t, PlayerState player) {
    if (_selecting) {
      final on = _picked.contains(t.id);
      return Icon(
        on ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
        size: 22,
        color: on ? P.of(context).brand : P.of(context).t3,
      );
    }
    return player.currentId == t.id ? const Equalizer() : null;
  }

  VoidCallback _rowTap(Track t, List<Track> list, PlayerState player) {
    if (_selecting) return () => _togglePick(t.id);
    // 点歌只负责「放这首」，不弹播放页；要看大图走底部的悬浮控制条
    return () =>
        player.playFromList(t.id, queue: list.map((e) => e.id).toList());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// 排序只对「全部歌曲」开放；其余列表（收藏 / 最近播放 / 离线缓存 / 专辑 / 歌手 / 歌单）
  /// 有各自固定的语义顺序，不放排序入口。
  bool get _sortable => widget.kind == CategoryKind.all;

  String _titleOf(AppState app) {
    final src = widget.sourceFilter;
    if (src != null) return app.sourceNameOf(src);
    final a = widget.artistFilter;
    if (a != null && widget.kind == CategoryKind.all) return a;
    final pid = widget.playlistId;
    if (pid != null) return app.playlistOf(pid)?.name ?? '歌单';
    return widget.kind.title;
  }

  bool get _hasSortIcon => widget.kind == CategoryKind.all;

  double get _headerActionWidth {
    if (_selecting) return 84;
    if (_songList) return _hasSortIcon ? 84 : 42;
    if (widget.playlistId != null) return 46;
    return 46;
  }

  Widget? _headerAction(AppState app) {
    if (_selecting) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          RoundIcon(Icons.checklist_rounded, size: 40, onTap: _pickAll),
          const SizedBox(width: 2),
          RoundIcon(Icons.close_rounded, size: 40, onTap: _endSelect),
        ],
      );
    }
    if (_songList) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          RoundIcon(Icons.checklist_rounded, size: 40, onTap: _startSelect),
          if (_hasSortIcon)
            RoundIcon(
              Icons.sort_rounded,
              key: _sortBtnKey,
              size: 40,
              onTap: _pickSort,
            ),
        ],
      );
    }
    final pid = widget.playlistId;
    if (pid != null) {
      return RoundIcon(
        Icons.more_horiz_rounded,
        size: 40,
        onTap: () {
          final pl = app.playlistOf(pid);
          if (pl != null) _openPlaylistMenu(app, pl);
        },
      );
    }
    return null;
  }

  /// 排序菜单：从右上角排序按钮的位置弹出（不是底部弹层）
  final GlobalKey _sortBtnKey = GlobalKey();

  Future<void> _pickSort() async {
    final p = P.of(context);
    final box = _sortBtnKey.currentContext?.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;

    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
    final rect = RelativeRect.fromRect(
      topLeft & box.size, // Offset & Size → 按钮的全局矩形
      Offset.zero & overlay.size,
    );

    final picked = await showMenu<SongSortKey>(
      context: context,
      position: rect,
      color: p.elev,
      elevation: 14,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(R.lg),
        side: BorderSide(color: p.line2),
      ),
      items: [
        for (final k in SongSortKey.values)
          PopupMenuItem<SongSortKey>(
            value: k,
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  k.label,
                  style: TextStyle(
                    fontSize: 13.5,
                    color: k == _sort.key ? p.brand : p.t1,
                    fontWeight:
                        k == _sort.key ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
                if (k == _sort.key) ...[
                  const SizedBox(width: 6),
                  // 方向直接摆在旁边：再点这一项就是翻转
                  Icon(
                    _sort.desc
                        ? Icons.arrow_downward_rounded
                        : Icons.arrow_upward_rounded,
                    size: 14,
                    color: p.brand,
                  ),
                ],
              ],
            ),
          ),
      ],
    );
    if (picked == null || !mounted) return;
    setState(() {
      // 点同一个维度 = 翻转方向；换维度 = 用该维度的默认方向
      _sort = picked == _sort.key
          ? _sort.toggled()
          : SongSort(picked, picked.descByDefault);
    });
  }

  /// 按来源（本地 / 某个网盘账号）筛选的曲目
  Widget _sourceTracks(
    BuildContext context,
    AppState app,
    PlayerState player,
    String sourceId,
  ) {
    final p = P.of(context);
    final list = _sort.apply(
      app.tracks.where((t) => t.sourceId == sourceId).toList(),
    );
    _visible = list;

    if (list.isEmpty) {
      return Center(
        child: Text('这个来源下还没有歌',
            style: TextStyle(fontSize: 13, color: p.t3)),
      );
    }

    return Scrollbar(
      controller: _scroll,
      thumbVisibility: true,
      interactive: true,
      thickness: 5,
      radius: const Radius.circular(3),
      child: ListView.builder(
        controller: _scroll,
        padding: EdgeInsets.fromLTRB(
            12, 0, 20, player.currentId.isEmpty ? 24 : 104),
        itemCount: list.length + 1,
        itemBuilder: (context, i) {
          if (i == list.length) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(8, 18, 8, 0),
              child: Text('共 ${list.length} 首 · ${_sort.label}',
                  style: TextStyle(fontSize: 12.5, color: p.t3)),
            );
          }
          final t = list[i];
          return TrackTile(
            track: t,
            subtitle: '${t.artist} · ${app.albumOf(t.albumId).name}',
            playing: player.currentId == t.id,
            trailing: _rowTrailing(t, player),
            onLongPress: _selecting
                ? null
                : () => showTrackActionsSheet(context, track: t),
            onTap: _rowTap(t, list, player),
          );
        },
      ),
    );
  }

  /// 歌单页的「按来源」分组：只在有 2 个及以上来源时才展示
  List<({String id, String name, int count, List<Track> covers})>
      _sourceGroups(AppState app) {
    final bySource = <String, List<Track>>{};
    for (final t in app.tracks) {
      final id = t.sourceId ?? 'local';
      (bySource[id] ??= <Track>[]).add(t);
    }
    if (bySource.length < 2) return const [];

    final out = <({String id, String name, int count, List<Track> covers})>[];
    for (final e in bySource.entries) {
      final sorted = List<Track>.of(e.value)
        ..sort((a, b) => b.addedAt.compareTo(a.addedAt));
      out.add((
        id: e.key,
        name: app.sourceNameOf(e.key),
        count: e.value.length,
        covers: sorted.length > 4 ? sorted.take(4).toList() : sorted,
      ));
    }
    out.sort((a, b) => b.count.compareTo(a.count));
    return out;
  }

  /// 自建歌单的曲目列表
  Widget _playlistTracks(
    BuildContext context,
    AppState app,
    PlayerState player,
    String pid,
  ) {
    final p = P.of(context);
    final list = app.tracksOfPlaylist(pid);

    if (list.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(32, 0, 32, 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.queue_music_rounded, size: 40, color: p.t3),
              const SizedBox(height: 14),
              Text('这个歌单还是空的', style: TextStyle(fontSize: 14, color: p.t2)),
              const SizedBox(height: 6),
              Text('在任意歌曲上长按，选「添加到歌单」加进来',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.5, height: 1.6, color: p.t3)),
              const SizedBox(height: 18),
              SizedBox(
                height: 42,
                child: FilledButton(
                  onPressed: () => pushCategory(context, CategoryKind.all),
                  style: FilledButton.styleFrom(
                    backgroundColor: p.brandSolid,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13),
                    ),
                  ),
                  child: const Text('去全部歌曲挑几首',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    _visible = list;

    return ListView.builder(
      padding: EdgeInsets.fromLTRB(12, 0, 12,
          player.currentId.isEmpty ? 24 : 104),
      itemCount: list.length + 1,
      itemBuilder: (context, i) {
        if (i == list.length) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(8, 18, 8, 0),
            child: Text('共 ${list.length} 首 · 长按歌曲可移出歌单',
                style: TextStyle(fontSize: 12.5, color: p.t3)),
          );
        }
        final t = list[i];
        final playing = player.currentId == t.id;
        return TrackTile(
          track: t,
          subtitle: '${t.artist} · ${app.albumOf(t.albumId).name}',
          playing: playing,
          trailing: _rowTrailing(t, player),
          onLongPress: _selecting
              ? null
              : () => showTrackActionsSheet(context, track: t,
                  removeFromPlaylistId: pid),
          onTap: _rowTap(t, list, player),
        );
      },
    );
  }

  /// 新建歌单并直接进去（建完就想往里加歌，少点一步）
  Future<void> _createPlaylist() async {
    final app = context.read<AppState>();
    final name = await showPlaylistNameSheet(context, title: '新建歌单');
    if (name == null || !mounted) return;
    final pl = await app.createPlaylist(name);
    if (!mounted) return;
    await pushCategory(context, CategoryKind.playlists, playlistId: pl.id);
  }

  Future<void> _openPlaylistMenu(AppState app, Playlist pl) async {
    final action = await showPlaylistActionsSheet(
      context,
      name: pl.name,
      count: pl.trackIds.length,
    );
    if (action == null || !mounted) return;
    if (action == 'rename') {
      final name = await showPlaylistNameSheet(
        context,
        title: '重命名歌单',
        initial: pl.name,
        confirm: '保存',
      );
      if (name != null) await app.renamePlaylist(pl.id, name);
    } else if (action == 'delete') {
      await app.deletePlaylist(pl.id);
      // 在歌单详情里删掉自己 → 退出这一页；在列表里删 → 留在原地
      if (mounted && widget.playlistId == pl.id) Navigator.maybePop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final player = context.watch<PlayerState>();
    final artist = widget.artistFilter;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _Header(
              title: _selecting ? '已选 ${_picked.length}' : _titleOf(app),
              onBack: _selecting ? _endSelect : null,
              actionWidth: _headerActionWidth,
              action: _headerAction(app),
            ),
            if (artist != null && !_selecting)
              _ArtistHead(
                name: artist,
                tracks: app.tracks.where((t) => t.artist == artist).toList(),
                onPlayAll: () {
                  final list = _sort
                      .apply(app.tracks.where((t) => t.artist == artist).toList());
                  if (list.isEmpty) return;
                  player.playFromList(list.first.id,
                      queue: list.map((e) => e.id).toList());
                  showPlayer(context);
                },
              ),
            // 播放控件浮在列表之上（不占高度），滑动时自动躲起来
            Expanded(
              child: FloatingPlayerOverlay(
                enabled: !_selecting,
                child: _content(context, app, player),
              ),
            ),
            if (_selecting)
              _SelectionBar(
                total: _visible.length,
                picked: _picked.length,
                onPickAll: _pickAll,
                onAdd: _picked.isEmpty ? null : _addPicked,
              )
            // 多选时让位给操作条（播放控件在上面的浮层里，不占布局）
          ],
        ),
      ),
    );
  }

  Widget _content(BuildContext context, AppState app, PlayerState player) {
    final p = P.of(context);

    // 按来源看歌：单独一屏
    final src = widget.sourceFilter;
    if (src != null) return _sourceTracks(context, app, player, src);

    // 自建歌单的曲目：单独一屏，进来就能播、能移出
    final pid = widget.playlistId;
    if (pid != null) return _playlistTracks(context, app, player, pid);

    switch (widget.kind) {
      case CategoryKind.playlists:
        // 智能歌单（由曲库实时统计）+ 自建歌单。
        // 封面统一用「抽屉式四宫格」—— 歌单里最近 4 首的封面拼起来，随内容变化。
        List<Track> head4(List<Track> list) =>
            list.length > 4 ? list.take(4).toList() : list;

        final groups = _sourceGroups(app);

        return ListView(
          padding: EdgeInsets.fromLTRB(12, 0, 12,
          player.currentId.isEmpty ? 24 : 104),
          children: [
            // 新建歌单
            InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: _createPlaylist,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                child: Row(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        color: p.brand.op(.10),
                        border: Border.all(color: p.brand.op(.28)),
                      ),
                      child: Icon(Icons.add_rounded, size: 24, color: p.brand),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('新建歌单',
                              style: TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w600,
                                  color: p.t1)),
                          const SizedBox(height: 3),
                          Text('长按任意歌曲即可加进来',
                              style: TextStyle(fontSize: 12, color: p.t3)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _PlaylistRow(
              name: '全部歌曲',
              sub: '${app.tracks.length} 首 · ${_sort.label}',
              covers: head4(const SongSort(SongSortKey.added, true)
                  .apply(app.tracks)),
              onTap: () => pushCategory(context, CategoryKind.all),
            ),
            _PlaylistRow(
              name: '我喜欢',
              sub: '${app.favoritesTracks.length} 首 · 你点过红心的',
              covers: head4(app.favoritesTracks),
              onTap: () => pushCategory(context, CategoryKind.favorites),
            ),
            _PlaylistRow(
              name: '最近播放',
              sub: '${app.recentTracks.length} 首 · 按时间倒序',
              covers: head4(app.recentTracks),
              onTap: () => pushCategory(context, CategoryKind.recent),
            ),
            _PlaylistRow(
              name: '离线缓存',
              sub: '${app.cachedTracks.length} 首 · 断网也能播',
              covers: head4(app.cachedTracks),
              onTap: () => pushCategory(context, CategoryKind.downloads),
            ),
            // 按来源分类（本地 / 各个网盘账号）：只有一个来源时不显示
            if (groups.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 16, 8, 6),
                child: Text('按来源 · ${groups.length}',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.1,
                        color: p.t3)),
              ),
              for (final g in groups)
                _PlaylistRow(
                  name: g.name,
                  sub: '${g.count} 首 · 按文件夹来源',
                  covers: g.covers,
                  onTap: () => pushCategory(
                    context,
                    CategoryKind.all,
                    sourceFilter: g.id,
                  ),
                ),
            ],
            if (app.playlists.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 16, 8, 6),
                child: Text('我的歌单 · ${app.playlists.length}',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.1,
                        color: p.t3)),
              ),
              for (final pl in app.playlists)
                _PlaylistRow(
                  name: pl.name,
                  sub: '${pl.trackIds.length} 首 · 自建',
                  covers: head4(app.tracksOfPlaylist(pl.id)),
                  onTap: () => pushCategory(context, CategoryKind.playlists,
                      playlistId: pl.id),
                  onMore: () => _openPlaylistMenu(app, pl),
                ),
            ],
          ],
        );

      case CategoryKind.artists:
        final byArtist = <String, List<Track>>{};
        for (final t in app.tracks) {
          byArtist.putIfAbsent(t.artist, () => []).add(t);
        }
        final entries = byArtist.entries.toList()
          ..sort((a, b) => b.value.length.compareTo(a.value.length));

        return ListView.builder(
          controller: _scroll,
          padding: EdgeInsets.fromLTRB(12, 0, 12,
          player.currentId.isEmpty ? 24 : 104),
          itemCount: entries.isEmpty ? 1 : entries.length,
          itemBuilder: (context, i) {
            if (entries.isEmpty) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(8, 20, 8, 0),
                child: Text('还没有歌手信息，先去导入音乐',
                    style: TextStyle(fontSize: 13.5, color: p.t3)),
              );
            }
            final e = entries[i];
            return InkWell(
              borderRadius: BorderRadius.circular(14),
              // 之前这里错跳「全部歌曲」，现在只显示该歌手自己的歌
              onTap: () => pushArtist(context, e.key),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
                child: Row(
                  children: [
                    ArtistAvatar(name: e.key, size: 44),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(e.key,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w600,
                                  color: p.t1)),
                          const SizedBox(height: 3),
                          Text(
                            '${e.value.length} 首 · ${e.value.map((t) => t.albumId).toSet().length} 张专辑',
                            style: TextStyle(fontSize: 12, color: p.t3),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, size: 16, color: p.t3),
                  ],
                ),
              ),
            );
          },
        );

      case CategoryKind.albums:
        final albums = app.albumList;
        return _SongScrollView(
          controller: _scroll,
          child: ListView.builder(
            controller: _scroll,
            padding: EdgeInsets.fromLTRB(12, 0, 12,
          player.currentId.isEmpty ? 24 : 104),
            itemCount: albums.length,
            itemBuilder: (context, i) {
              final a = albums[i];
              return _AlbumRow(
                album: a,
                count: app.tracksOfAlbum(a.id).length,
                coverPath: app.coverOfAlbum(a.id),
              );
            },
          ),
        );

      /// 收藏 = 收藏的专辑（在专辑页点心形图标加进来）
      case CategoryKind.bookmarks:
        final albums = app.favoriteAlbums;
        if (albums.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('还没有收藏专辑\n打开专辑页，点右上角的心形图标即可收藏',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13.5, height: 1.7, color: p.t3)),
            ),
          );
        }
        return ListView.builder(
          controller: _scroll,
          padding: EdgeInsets.fromLTRB(12, 0, 12,
          player.currentId.isEmpty ? 24 : 104),
          itemCount: albums.length,
          itemBuilder: (context, i) {
            final a = albums[i];
            return _AlbumRow(
              album: a,
              count: app.tracksOfAlbum(a.id).length,
              coverPath: app.coverOfAlbum(a.id),
            );
          },
        );

      default:
        var list = switch (widget.kind) {
          CategoryKind.favorites => app.favoritesTracks,
          CategoryKind.recent => app.recentTracks,
          CategoryKind.downloads => app.cachedTracks,
          _ => app.tracks,
        };

        // 歌手筛选（从歌手列表进入时）
        final artist = widget.artistFilter;
        if (artist != null) {
          list = list.where((t) => t.artist == artist).toList();
        }

        list = _sort.apply(list);

        if (list.isEmpty) {
          return Center(
            child: Text('这里还空着',
                style: TextStyle(fontSize: 13, color: p.t3)),
          );
        }

        _visible = list;

        // 右侧快速滚动条：拖滑块可以快速掠过整张列表
        return Scrollbar(
          controller: _scroll,
          thumbVisibility: true,
          interactive: true,
          thickness: 5,
          radius: const Radius.circular(3),
          child: ListView.builder(
            controller: _scroll,
            padding: EdgeInsets.fromLTRB(12, 0, 20,
                player.currentId.isEmpty ? 24 : 104),
            itemCount: list.length + 1,
            itemBuilder: (context, i) {
              if (i == list.length) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(8, 18, 8, 0),
                  child: Text(
                    _sortable
                        ? '共 ${list.length} 首 · ${_sort.label}'
                        : '共 ${list.length} 首',
                    style: TextStyle(fontSize: 12.5, color: p.t3),
                  ),
                );
              }
              final t = list[i];
              return TrackTile(
                track: t,
                subtitle: '${t.artist} · ${app.albumOf(t.albumId).name}',
                showFormat: widget.kind == CategoryKind.all,
                playing: player.currentId == t.id,
                trailing: _rowTrailing(t, player),
                onLongPress: _selecting
                    ? null
                    : () => showTrackActionsSheet(context, track: t),
                onTap: _rowTap(t, list, player),
              );
            },
          ),
        );
    }
  }
}

/// 给「专辑」列表套一层滚动条（列表本身由调用方提供）
class _SongScrollView extends StatelessWidget {
  const _SongScrollView({required this.controller, required this.child});
  final ScrollController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      controller: controller,
      thumbVisibility: true,
      interactive: true,
      thickness: 5,
      radius: const Radius.circular(3),
      child: child,
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    this.action,
    this.onBack,
    this.actionWidth = 46,
  });
  final String title;
  final Widget? action;

  /// 自定义返回行为（多选时用来退出多选而不是返回上一页）
  final VoidCallback? onBack;
  final double actionWidth;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    return SizedBox(
      height: 52,
      child: Row(
        children: [
          const SizedBox(width: 6),
          RoundIcon(Icons.chevron_left_rounded,
              size: 40,
              onTap: onBack ?? () => Navigator.maybePop(context)),
          Expanded(
            child: Center(
              child: Text(title,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.t1)),
            ),
          ),
          SizedBox(width: actionWidth, child: action),
        ],
      ),
    );
  }
}

class _AlbumRow extends StatelessWidget {
  const _AlbumRow({
    required this.album,
    required this.count,
    this.coverPath,
  });
  final Album album;
  final int count;

  /// 该专辑任一歌曲的内嵌封面（有就显示真封面）
  final String? coverPath;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => pushAlbum(context, album),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
        child: Row(
          children: [
            CoverArt(albumId: album.id, coverPath: coverPath),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(album.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: p.t1)),
                  const SizedBox(height: 3),
                  Text('${album.artist} · ${album.year} · $count 首',
                      style: TextStyle(fontSize: 12, color: p.t3)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 16, color: p.t3),
          ],
        ),
      ),
    );
  }
}

class _AlbumScreen extends StatelessWidget {
  const _AlbumScreen({required this.album});
  final Album album;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final app = context.watch<AppState>();
    final player = context.watch<PlayerState>();
    final list = app.tracksOfAlbum(album.id);
    final cover = app.coverOfAlbum(album.id);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _Header(
              title: '专辑',
              action: IconButton(
                padding: EdgeInsets.zero,
                iconSize: 20,
                icon: Icon(
                  app.isAlbumFavorite(album.id)
                      ? Icons.bookmark_rounded
                      : Icons.bookmark_border_rounded,
                  color: app.isAlbumFavorite(album.id)
                      ? const Color(0xFFC07600)
                      : p.t3,
                ),
                onPressed: () => app.toggleAlbumFavorite(album.id),
              ),
            ),
            Expanded(
              // 用 builder 按需建行：整张专辑一次性把几十个封面全解码，
              // 正是点进专辑那一下卡顿的来源
              child: FloatingPlayerOverlay(
                child: ListView.builder(
                padding: EdgeInsets.fromLTRB(
                    12, 0, 12, player.currentId.isEmpty ? 24 : 104),
                itemCount: list.length + 1,
                itemBuilder: (context, i) {
                  if (i == 0) {
                    return _AlbumHead(
                      album: album,
                      coverPath: cover,
                      count: list.length,
                      onPlayAll: list.isEmpty
                          ? null
                          : () {
                              player.playFromList(list.first.id,
                                  queue: list.map((e) => e.id).toList());
                              showPlayer(context);
                            },
                    );
                  }
                  final t = list[i - 1];
                  final playing = player.currentId == t.id;
                  return TrackTile(
                    track: t,
                    subtitle: t.artist,
                    playing: playing,
                    trailing: playing ? const Equalizer() : null,
                    onLongPress: () =>
                        showTrackActionsSheet(context, track: t),
                    onTap: () => player.playFromList(t.id,
                        queue: list.map((e) => e.id).toList()),
                  );
                },
                ),
              ),
            ),
            // 点歌不再自动弹播放页；进播放页的入口是浮在列表上的那条
          ],
        ),
      ),
    );
  }
}

/// 专辑页头部：大封面 + 专辑信息 + 播放全部
class _AlbumHead extends StatelessWidget {
  const _AlbumHead({
    required this.album,
    required this.count,
    this.coverPath,
    this.onPlayAll,
  });

  final Album album;
  final int count;
  final String? coverPath;
  final VoidCallback? onPlayAll;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CoverArt(
                albumId: album.id,
                coverPath: coverPath,
                size: 92,
                radius: 16,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    Text(album.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 17,
                            height: 1.3,
                            fontWeight: FontWeight.w800,
                            color: p.t1)),
                    const SizedBox(height: 6),
                    // 歌手名可点：直接从专辑跳去看这位歌手
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: (album.artist.isEmpty ||
                              album.artist == '未知歌手')
                          ? null
                          : () => pushArtist(context, album.artist),
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(album.artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: p.brand)),
                          ),
                          const SizedBox(width: 3),
                          Icon(Icons.chevron_right_rounded,
                              size: 14, color: p.brand),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      // 年份缺失（0）时不显示，别出现「0 · 12 首」这种
                      [
                        if (album.year > 0) '${album.year}',
                        '$count 首',
                      ].join(' · '),
                      style: TextStyle(fontSize: 12, color: p.t3),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (onPlayAll != null) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 42,
              child: FilledButton.icon(
                onPressed: onPlayAll,
                icon: const Icon(Icons.play_arrow_rounded, size: 20),
                label: const Text('播放全部',
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                style: FilledButton.styleFrom(
                  backgroundColor: p.brandSolid,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 歌手页头部：头像 + 名字 + 数量 + 播放全部
class _ArtistHead extends StatelessWidget {
  const _ArtistHead({
    required this.name,
    required this.tracks,
    this.onPlayAll,
  });

  final String name;
  final List<Track> tracks;
  final VoidCallback? onPlayAll;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final albums = tracks.map((t) => t.albumId).toSet().length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ArtistAvatar(name: name, size: 64),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            color: p.t1)),
                    const SizedBox(height: 4),
                    Text('${tracks.length} 首 · $albums 张专辑',
                        style: TextStyle(fontSize: 12.5, color: p.t3)),
                  ],
                ),
              ),
            ],
          ),
          if (onPlayAll != null && tracks.isNotEmpty) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 42,
              child: FilledButton.icon(
                onPressed: onPlayAll,
                icon: const Icon(Icons.play_arrow_rounded, size: 20),
                label: const Text('播放全部',
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700)),
                style: FilledButton.styleFrom(
                  backgroundColor: p.brandSolid,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 多选模式的底部操作条
class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.total,
    required this.picked,
    this.onPickAll,
    this.onAdd,
  });

  final int total;
  final int picked;
  final VoidCallback? onPickAll;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final all = total > 0 && picked >= total;
    return Glass(
      radius: 0,
      blur: Blur.regular,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      child: Row(
        children: [
          TextButton(
            onPressed: onPickAll,
            child: Text(all ? '取消全选' : '全选',
                style: TextStyle(fontSize: 13.5, color: p.brand)),
          ),
          const Spacer(),
          SizedBox(
            height: 42,
            child: FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.playlist_add_rounded, size: 18),
              label: Text(picked > 0 ? '加入歌单 ($picked)' : '加入歌单',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700)),
              style: FilledButton.styleFrom(
                backgroundColor: p.brandSolid,
                disabledBackgroundColor: p.brand.op(.30),
                padding: const EdgeInsets.symmetric(horizontal: 18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlaylistRow extends StatelessWidget {
  const _PlaylistRow({
    required this.name,
    required this.sub,
    required this.covers,
    required this.onTap,
    this.onMore,
  });
  final String name;
  final String sub;

  /// 歌单里最近的（最多）4 首，用来拼四宫格封面
  final List<Track> covers;
  final VoidCallback onTap;

  /// 自建歌单才有：重命名 / 删除
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
      child: Row(
        children: [
          CoverCollage(tracks: covers),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: p.t1)),
                const SizedBox(height: 3),
                Text(sub, style: TextStyle(fontSize: 12, color: p.t3)),
              ],
            ),
          ),
          if (onMore != null)
            RoundIcon(Icons.more_horiz_rounded, size: 34, onTap: onMore)
          else
            Icon(Icons.chevron_right_rounded, size: 16, color: p.t3),
        ],
      ),
      ),
    );
  }
}
