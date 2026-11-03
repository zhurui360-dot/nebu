import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../services/local_scanner.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

/// 本地音乐目录选择器：从存储根目录一层层点进去，选中一个目录返回它的路径。
///
/// 和网盘目录一样：选中即「添加目录」，之后可以在「音乐来源」里再次扫描，
/// 只会把新加进来的歌补进曲库，已有的不会重复。
class LocalFolderPicker extends StatefulWidget {
  const LocalFolderPicker({super.key});

  @override
  State<LocalFolderPicker> createState() => _LocalFolderPickerState();
}

class _LocalFolderPickerState extends State<LocalFolderPicker> {
  List<String> _roots = const [];
  String? _current;
  List<String> _subs = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    final roots = await LocalScanner().storageRoots();
    if (!mounted) return;
    setState(() {
      _roots = roots;
      _loading = false;
      // 只有一个根目录就直接进去，少点一次
      if (roots.length == 1) _current = null;
    });
    if (roots.length == 1) await _enter(roots.first);
  }

  Future<void> _enter(String path) async {
    setState(() {
      _current = path;
      _loading = true;
      _subs = const [];
    });
    final subs = await LocalScanner.listDirs(path);
    if (!mounted) return;
    setState(() {
      _subs = subs;
      _loading = false;
    });
  }

  void _up() {
    final cur = _current;
    if (cur == null) return;
    final parent = p.dirname(cur);
    final atRoot = _roots.contains(cur) || parent == cur;
    if (atRoot) {
      setState(() {
        _current = null;
        _subs = const [];
      });
      return;
    }
    _enter(parent);
  }

  @override
  Widget build(BuildContext context) {
    final p0 = P.of(context);
    final cur = _current;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            SizedBox(
              height: 52,
              child: Row(
                children: [
                  const SizedBox(width: 6),
                  RoundIcon(
                    Icons.chevron_left_rounded,
                    size: 40,
                    onTap: () {
                      if (cur == null) {
                        Navigator.maybePop(context);
                      } else {
                        _up();
                      }
                    },
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        '选择音乐目录',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: p0.t1),
                      ),
                    ),
                  ),
                  const SizedBox(width: 46),
                ],
              ),
            ),
            Expanded(child: _body(p0, cur)),
          ],
        ),
      ),
    );
  }

  Widget _body(P p0, String? cur) {
    if (cur == null) {
      if (_roots.isEmpty) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Text(
              '没找到可读的存储目录。\n请先在系统设置里允许本应用读取存储/音频。',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, height: 1.7, color: p0.t3),
            ),
          ),
        );
      }
      return ListView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
            child: Text('选一个存储位置',
                style: TextStyle(fontSize: 12.5, color: p0.t3)),
          ),
          for (final r in _roots)
            _dirRow(p0, r, () => _enter(r), root: true),
        ],
      );
    }

    return Column(
      children: [
        // 当前路径 + 扫描按钮
        Container(
          margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          padding: const EdgeInsets.fromLTRB(13, 11, 13, 12),
          decoration: BoxDecoration(
            color: p0.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: p0.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('当前目录', style: TextStyle(fontSize: 11.5, color: p0.t3)),
              const SizedBox(height: 3),
              Text(cur,
                  maxLines: 2,
                  style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      fontWeight: FontWeight.w600,
                      color: p0.t1)),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 42,
                child: FilledButton.icon(
                  onPressed: () => Navigator.pop(context, cur),
                  icon: const Icon(Icons.playlist_add_check_rounded, size: 18),
                  label: const Text('扫描这个目录',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700)),
                  style: FilledButton.styleFrom(
                    backgroundColor: p0.brandSolid,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_loading)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: p0.brand),
            ),
          ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
            children: [
              if (!_loading && _subs.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 14, 8, 0),
                  child: Text('这个目录下面没有子目录了，可以直接扫描它',
                      style: TextStyle(fontSize: 12.5, color: p0.t3)),
                ),
              for (final d in _subs)
                _dirRow(p0, d, () => _enter(d)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _dirRow(P p0, String path, VoidCallback onTap,
      {bool root = false}) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
        child: Row(
          children: [
            Icon(
              root ? Icons.sd_storage_rounded : Icons.folder_rounded,
              size: 20,
              color: p0.brand,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                p.basename(path).isEmpty ? path : p.basename(path),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: p0.t1),
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 16, color: p0.t3),
          ],
        ),
      ),
    );
  }
}
