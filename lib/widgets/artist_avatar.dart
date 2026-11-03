import 'dart:io';

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/artist_image.dart';
import '../theme/app_theme.dart';
import 'common.dart';

/// 歌手头像：先本地缓存 → 联网取专辑封面当头像 → 都失败时用首字母渐变兜底。
/// 头像用圆形，与列表里的 44px 行高匹配。
class ArtistAvatar extends StatefulWidget {
  const ArtistAvatar({super.key, required this.name, this.size = 44});
  final String name;
  final double size;

  @override
  State<ArtistAvatar> createState() => _ArtistAvatarState();
}

class _ArtistAvatarState extends State<ArtistAvatar> {
  String? _path;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ArtistAvatar old) {
    super.didUpdateWidget(old);
    if (old.name != widget.name) {
      _path = null;
      _done = false;
      _load();
    }
  }

  Future<void> _load() async {
    final p = await ArtistImage.lookup(widget.name);
    if (!mounted) return;
    setState(() {
      _path = p;
      _done = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final path = _path;
    // 不再每次 build 都 existsSync()：lookup 返回的路径已经落过盘，
    // 万一文件被清掉，下面 Image.file 的 errorBuilder 会退回首字母，
    // 界面表现一样，但省掉了每个头像一次同步磁盘 IO。
    final hasFile = path != null;

    return SizedBox(
      width: size,
      height: size,
      child: ClipOval(
        child: hasFile
            ? Image.file(
                File(path),
                width: size,
                height: size,
                fit: BoxFit.cover,
                // 头像加载失败时退回首字母
                errorBuilder: (_, __, ___) => _Fallback(name: widget.name, size: size),
              )
            : _done
                ? _Fallback(name: widget.name, size: size)
                : _Fallback(name: widget.name, size: size, loading: true),
      ),
    );
  }
}

class _Fallback extends StatelessWidget {
  const _Fallback({required this.name, required this.size, this.loading = false});
  final String name;
  final double size;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    // 用名字哈希取一组稳定的渐变色，避免每个头像都一个样
    final style = (name.hashCode & 0x7fffffff) % _grads.length;
    final t = name.trim();
    final initial = t.isEmpty ? '?' : t.substring(0, 1).toUpperCase();

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _grads[style],
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: TextStyle(
          fontSize: size * .40,
          fontWeight: FontWeight.w700,
          color: Colors.white.op(loading ? .55 : .95),
        ),
      ),
    );
  }

  static const _grads = <List<Color>>[
    [Color(0xFF5B8BFF), Color(0xFF8FB4FF)],
    [Color(0xFF7C5CFF), Color(0xFF33D6FF)],
    [Color(0xFF2E8FA3), Color(0xFF6FD3E8)],
    [Color(0xFFB65C2E), Color(0xFFF3C07B)],
    [Color(0xFF1F9E8A), Color(0xFF8CE0C0)],
    [Color(0xFFC2418A), Color(0xFFFFB84D)],
  ];
}

/// 歌单封面：抽屉式四宫格，装歌单里最近的 4 首歌的封面。
/// 不足 4 首时有几首填几格，空格用暗色板块补齐，整体仍是一个方形。
class CoverCollage extends StatelessWidget {
  const CoverCollage({
    super.key,
    required this.tracks,
    this.size = 44,
    this.radius = 12,
  });

  /// 传入歌单里的歌曲（顺序即"最近"顺序），内部只取前 4 首
  final List<Track> tracks;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final four = tracks.take(4).toList();

    // 空歌单：给一块淡色占位，别让列表里出现一个纯黑洞
    if (four.isEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [p.brand.op(.24), p.brand2.op(.16)],
            ),
          ),
          child: Icon(Icons.queue_music_rounded,
              size: size * .42, color: p.t2.op(.85)),
        ),
      );
    }

    // 只有一首：直接铺满，视觉更干净
    if (four.length == 1) {
      return CoverArt(
        albumId: four.first.albumId,
        size: size,
        radius: radius,
        coverPath: four.first.coverPath,
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  Expanded(child: _cell(context, four, 0)),
                  _gap(),
                  Expanded(child: _cell(context, four, 1)),
                ],
              ),
            ),
            _gap(horizontal: true),
            Expanded(
              child: Row(
                children: [
                  Expanded(child: _cell(context, four, 2)),
                  _gap(),
                  Expanded(child: _cell(context, four, 3)),
                ],
              ),
            ),
          ],
        ),
      ),
    ).withBg(p.elev);
  }

  Widget _cell(BuildContext context, List<Track> four, int i) {
    if (i >= four.length) {
      // 空位：一块很暗的底，让拼图仍成立，不出现白洞
      return ColoredBox(color: P.of(context).line2);
    }
    final t = four[i];
    return CoverArt(
      albumId: t.albumId,
      size: size / 2,
      radius: 0,
      coverPath: t.coverPath,
    );
  }

  // 四宫格之间的细分隔线：固定 1.5px，两个方向都用它
  Widget _gap({bool horizontal = false}) => const SizedBox(width: 1.5, height: 1.5);
}

extension _Bg on Widget {
  Widget withBg(Color c) => ColoredBox(color: c, child: this);
}
