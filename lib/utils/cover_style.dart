/// 没有封面图时的兜底渐变配色。
///
/// 按专辑 id 稳定哈希，保证同一张专辑每次都用同一个颜色（不随机闪烁）。
/// 返回 1..6，对应 AlbumCover 里的 6 套渐变。
int coverStyleOf(String albumId) => (albumId.hashCode.abs() % 6) + 1;
