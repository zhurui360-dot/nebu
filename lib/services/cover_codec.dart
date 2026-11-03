import 'dart:typed_data';
import 'dart:ui' as ui;

/// 封面落盘前的整理。
///
/// 现实里内嵌封面能夸张到什么程度：有整张 15MB 的 PNG（4000×4000）。
/// 原样存下来，一张专辑十几首就是几百 MB，列表里解码也吃内存。
/// 这里统一缩到 1200px 以内再写文件，肉眼在手机上完全看不出差别。
class CoverCodec {
  /// 超过这个大小才处理（小图原样返回，省一次解码）
  static const _threshold = 400 * 1024;

  /// 长边上限
  static const _maxSide = 1200;

  /// 缩小 + 重编码为 PNG；任何异常都原样返回，绝不让导入失败。
  static Future<Uint8List> shrink(Uint8List bytes) async {
    if (bytes.length <= _threshold) return bytes;
    try {
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: _maxSide);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      codec.dispose();
      if (data == null) return bytes;
      final out = data.buffer.asUint8List();
      // 重编码偶尔会变大（原图是高质量 JPEG 时），那就保留原图
      return out.length < bytes.length ? out : bytes;
    } catch (_) {
      return bytes;
    }
  }
}
