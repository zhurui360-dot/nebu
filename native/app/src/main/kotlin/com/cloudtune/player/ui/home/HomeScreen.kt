package com.cloudtune.player.ui.home

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.QueueMusic
import androidx.compose.material.icons.rounded.Favorite
import androidx.compose.material.icons.rounded.History
import androidx.compose.material.icons.rounded.Pause
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.cloudtune.player.ui.AppViewModel
import com.cloudtune.player.ui.components.SongCover
import com.cloudtune.player.ui.components.SongRow
import com.cloudtune.player.ui.glass.Glass
import com.cloudtune.player.ui.glass.GlassCard
import com.cloudtune.player.ui.theme.Brand
import com.cloudtune.player.ui.theme.Pad
import com.cloudtune.player.ui.theme.PlayBtnBg
import com.cloudtune.player.ui.theme.PlayBtnFg
import com.cloudtune.player.ui.theme.R
import com.cloudtune.player.ui.theme.T
import com.cloudtune.player.ui.theme.Text1
import com.cloudtune.player.ui.theme.Text2
import com.cloudtune.player.ui.theme.Text3
import java.util.Calendar

/** 首页：问候 → 继续播放 → 快捷入口 → 为你推荐 → 最近播放。全部接真实数据。 */
@Composable
fun HomeScreen(vm: AppViewModel, onGoSearch: () -> Unit = {}, onGoTab: (Int) -> Unit = {}) {
    val hour = Calendar.getInstance().get(Calendar.HOUR_OF_DAY)
    val tracks by vm.tracks.collectAsState()
    val albums by vm.albums.collectAsState()
    val current by vm.player.currentTrack.collectAsState()
    val playing by vm.player.playing.collectAsState()
    val position by vm.player.position.collectAsState()

    LazyColumn(
        modifier = Modifier.fillMaxSize().statusBarsPadding(),
        contentPadding = PaddingValues(bottom = 180.dp),
    ) {
        item { GreetingHeader(hour, onGoSearch) }

        if (current != null) {
            item {
                ContinueCard(
                    title = current!!.title,
                    artist = current!!.artist,
                    album = current!!.albumName,
                    track = current!!,
                    position = position,
                    duration = current!!.durationMs,
                    playing = playing,
                    onToggle = { vm.toggle() },
                    onOpen = { vm.expandPlayer() },
                )
            }
        }

        item { QuickTiles(onGoTab) }

        if (albums.isNotEmpty()) {
            item { SectionHead(title = "为你推荐", action = null) }
            item {
                LazyRow(
                    contentPadding = PaddingValues(horizontal = Pad.page),
                    horizontalArrangement = Arrangement.spacedBy(14.dp),
                ) {
                    items(albums.take(12), key = { it.id }) { a ->
                        Column(
                            Modifier
                                .width(105.dp)
                                .clickable { vm.openAlbum(a.id) },
                        ) {
                            AlbumCover(a.id, a.coverUri, 105.dp)
                            Spacer(Modifier.height(8.dp))
                            Text(a.name, style = T.sub.copy(fontWeight = FontWeight.SemiBold), color = Text1,
                                maxLines = 1, overflow = TextOverflow.Ellipsis)
                            Spacer(Modifier.height(2.dp))
                            Text(a.artist, style = T.label, color = Text2, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        }
                    }
                }
                Spacer(Modifier.height(Pad.section))
            }
        }

        if (tracks.isNotEmpty()) {
            item { SectionHead(title = "全部歌曲", action = "${tracks.size} 首") }
            items(tracks.take(8), key = { it.id }) { t ->
                SongRow(
                    track = t,
                    playing = t.id == current?.id,
                    onClick = { vm.playTrack(t, tracks) },
                )
            }
        } else {
            item { EmptyHome(vm) }
        }
    }
}

@Composable
private fun AlbumCover(albumId: String, uri: String?, size: androidx.compose.ui.unit.Dp) {
    if (uri != null) {
        coil.compose.AsyncImage(
            model = uri,
            contentDescription = null,
            modifier = Modifier.size(size).clip(androidx.compose.foundation.shape.RoundedCornerShape(R.cover)),
        )
    } else {
        com.cloudtune.player.ui.components.CoverArt(albumId = albumId, size = size, radius = R.cover)
    }
}

@Composable
private fun GreetingHeader(hour: Int, onSearch: () -> Unit) {
    Row(Modifier.padding(start = Pad.pageWide, end = Pad.page, top = 14.dp), verticalAlignment = Alignment.Top) {
        Column(Modifier.weight(1f)) {
            Text(text = greetText(hour), style = T.greeting, color = Text1)
            Spacer(Modifier.height(4.dp))
            Text(text = "从上次听到的地方继续", style = T.sub, color = Text2)
        }
        Icon(
            Icons.Rounded.Search,
            contentDescription = "搜索",
            tint = Text1,
            modifier = Modifier.size(24.dp).clickable(onClick = onSearch),
        )
    }
    Spacer(Modifier.height(20.dp))
}

@Composable
private fun ContinueCard(
    title: String, artist: String, album: String, track: com.cloudtune.player.data.model.Track,
    position: Long, duration: Long, playing: Boolean,
    onToggle: () -> Unit, onOpen: () -> Unit,
) {
    GlassCard(
        onClick = onOpen,
        modifier = Modifier.fillMaxWidth().padding(horizontal = Pad.page),
        radius = R.xl,
        tint = Brand.copy(alpha = 0.07f),
        topLight = false,
        elevation = 16.dp,
    ) {
        Row(Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
            SongCover(track, 108.dp, R.cover)
            Spacer(Modifier.width(14.dp))
            Column(Modifier.weight(1f)) {
                Text("继续播放", style = T.caption.copy(fontWeight = FontWeight.SemiBold), color = Brand)
                Spacer(Modifier.height(4.dp))
                Text(title, style = T.title, color = Text1, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Spacer(Modifier.height(3.dp))
                Text("$artist · $album", style = T.caption, color = Text2, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Spacer(Modifier.height(12.dp))
                val p = if (duration > 0) (position.toFloat() / duration).coerceIn(0f, 1f) else 0f
                Box(Modifier.fillMaxWidth().height(3.dp).clip(CircleShape).background(Color.White.copy(alpha = 0.18f))) {
                    Box(Modifier.fillMaxWidth(p).fillMaxHeight().background(Brand))
                }
            }
            Spacer(Modifier.width(10.dp))
            Box(
                Modifier.size(52.dp).clip(CircleShape).background(PlayBtnBg).clickable(onClick = onToggle),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    imageVector = if (playing) Icons.Rounded.Pause else Icons.Rounded.PlayArrow,
                    contentDescription = "播放", tint = PlayBtnFg, modifier = Modifier.size(26.dp),
                )
            }
        }
    }
    Spacer(Modifier.height(16.dp))
}

private data class QuickEntry(val icon: ImageVector, val label: String, val tab: Int)

@Composable
private fun QuickTiles(onGoTab: (Int) -> Unit) {
    // tab: 0 首页 1 曲库 2 搜索 3 我的
    val entries = listOf(
        QuickEntry(Icons.Rounded.History, "最近播放", 0),
        QuickEntry(Icons.Rounded.Favorite, "我的收藏", 1),
        QuickEntry(Icons.AutoMirrored.Rounded.QueueMusic, "歌单", 1),
        QuickEntry(Icons.Rounded.Search, "搜索", 2),
    )
    Row(
        Modifier.fillMaxWidth().padding(horizontal = Pad.page),
        horizontalArrangement = Arrangement.spacedBy(11.dp),
    ) {
        entries.forEach { e ->
            Glass(
                modifier = Modifier.weight(1f).height(78.dp).clickable { onGoTab(e.tab) },
                radius = R.tile,
                topLight = false,
                elevation = 8.dp,
            ) {
                Column(Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.Center) {
                    Icon(e.icon, contentDescription = e.label, tint = Text1.copy(alpha = 0.88f), modifier = Modifier.size(20.dp))
                    Spacer(Modifier.height(9.dp))
                    Text(e.label, style = T.label, color = Text1)
                }
            }
        }
    }
    Spacer(Modifier.height(Pad.section))
}

@Composable
private fun SectionHead(title: String, action: String?) {
    Row(
        Modifier.fillMaxWidth().padding(start = Pad.pageWide, end = Pad.page, bottom = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(text = title, style = T.h2, color = Text1)
        Spacer(Modifier.weight(1f))
        if (action != null) Text(text = action, style = T.caption, color = Text2)
    }
}

@Composable
private fun EmptyHome(vm: AppViewModel) {
    Column(
        Modifier.fillMaxWidth().padding(40.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Spacer(Modifier.height(30.dp))
        Text("曲库还是空的", style = T.h2, color = Text2)
        Spacer(Modifier.height(8.dp))
        Text("扫描一次本地音乐，就能开始听了", style = T.sub, color = Text3)
        Spacer(Modifier.height(20.dp))
        Text("扫描本地音乐", style = T.sub.copy(fontWeight = FontWeight.Bold), color = Brand,
            modifier = Modifier.clickable { vm.scanLocal() })
    }
}

private fun greetText(hour: Int): String = when (hour) {
    in 5..11 -> "早上好"
    in 12..17 -> "下午好"
    else -> "晚上好"
}
