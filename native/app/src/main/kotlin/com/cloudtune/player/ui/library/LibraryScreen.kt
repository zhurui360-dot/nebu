package com.cloudtune.player.ui.library

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import com.cloudtune.player.data.db.MusicDatabase
import com.cloudtune.player.data.model.Track
import com.cloudtune.player.ui.AppViewModel
import com.cloudtune.player.ui.components.CoverArt
import com.cloudtune.player.ui.components.SongRow
import com.cloudtune.player.ui.glass.Glass
import com.cloudtune.player.ui.theme.Brand
import com.cloudtune.player.ui.theme.Pad
import com.cloudtune.player.ui.theme.R
import com.cloudtune.player.ui.theme.T
import com.cloudtune.player.ui.theme.Text1
import com.cloudtune.player.ui.theme.Text2
import com.cloudtune.player.ui.theme.Text3

/** 曲库：歌曲 / 专辑 / 歌手 三个 tab，全部接真实数据。 */
@Composable
fun LibraryScreen(vm: AppViewModel) {
    var selectedTab by remember { mutableIntStateOf(0) }

    val albumFilter by vm.albumFilter.collectAsState()
    val artistFilter by vm.artistFilter.collectAsState()

    when {
        albumFilter != null -> AlbumDetail(vm, albumFilter!!, onBack = vm::closeAlbum)
        artistFilter != null -> ArtistDetail(vm, artistFilter!!, onBack = vm::closeArtist)
        else -> {
            Column(Modifier.fillMaxSize().statusBarsPadding()) {
                Text(
                    "曲库",
                    style = T.h1,
                    color = Text1,
                    modifier = Modifier.padding(start = Pad.pageWide, top = 14.dp, bottom = 8.dp),
                )
                TabBar(selected = selectedTab, onSelect = { selectedTab = it })
                when (selectedTab) {
                    0 -> SongsTab(vm)
                    1 -> AlbumsTab(vm)
                    2 -> ArtistsTab(vm)
                }
            }
        }
    }
}

@Composable
private fun TabBar(selected: Int, onSelect: (Int) -> Unit) {
    val tabs = listOf("歌曲", "专辑", "歌手")
    Row(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = Pad.page, vertical = 10.dp),
    ) {
        tabs.forEachIndexed { i, name ->
            val on = i == selected
            Box(
                Modifier
                    .clip(RoundedCornerShape(20.dp))
                    .background(if (on) Brand.copy(alpha = 0.22f) else androidx.compose.ui.graphics.Color.Transparent)
                    .clickable { onSelect(i) }
                    .padding(horizontal = 18.dp, vertical = 8.dp),
            ) {
                Text(name, style = T.sub, color = if (on) Brand else Text2, fontWeight = if (on) FontWeight.Bold else FontWeight.Normal)
            }
            Spacer(Modifier.width(8.dp))
        }
    }
}

@Composable
private fun SongsTab(vm: AppViewModel) {
    val tracks by vm.tracks.collectAsState()
    val currentId by vm.player.currentTrack.collectAsState()
    LazyColumn(
        Modifier.fillMaxSize(),
        contentPadding = PaddingValues(bottom = 180.dp),
    ) {
        item {
            Text(
                "${tracks.size} 首歌曲",
                style = T.caption,
                color = Text3,
                modifier = Modifier.padding(horizontal = Pad.page, vertical = 6.dp),
            )
        }
        items(tracks, key = { it.id }) { t ->
            SongRow(
                track = t,
                playing = t.id == currentId?.id,
                onClick = { vm.playTrack(t, tracks) },
            )
        }
        if (tracks.isEmpty()) item { EmptyHint(vm) }
    }
}

@Composable
private fun AlbumsTab(vm: AppViewModel) {
    val albums by vm.albums.collectAsState()
    LazyVerticalGrid(
        columns = GridCells.Fixed(2),
        Modifier.fillMaxSize(),
        contentPadding = PaddingValues(start = Pad.page, end = Pad.page, bottom = 180.dp),
        horizontalArrangement = Arrangement.spacedBy(14.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        items(albums, key = { it.id }) { a ->
            Column(Modifier.clickable { vm.openAlbum(a.id) }) {
                if (a.coverUri != null) {
                    AsyncImage(
                        model = a.coverUri,
                        contentDescription = a.name,
                        contentScale = ContentScale.Crop,
                        modifier = Modifier
                            .fillMaxWidth()
                            .aspectRatio(1f)
                            .clip(RoundedCornerShape(R.lg)),
                    )
                } else {
                    CoverArt(albumId = a.id, size = 160.dp, radius = R.lg)
                }
                Spacer(Modifier.height(8.dp))
                Text(a.name, style = T.sub, color = Text1, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text("${a.artist} · ${a.count}首", style = T.caption, color = Text2, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
    }
}

@Composable
private fun ArtistsTab(vm: AppViewModel) {
    val artists by vm.artists.collectAsState()
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 180.dp)) {
        items(artists, key = { it.name }) { a ->
            Row(
                Modifier
                    .fillMaxWidth()
                    .clickable { vm.openArtist(a.name) }
                    .padding(horizontal = Pad.page, vertical = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Box(
                    Modifier
                        .size(48.dp)
                        .clip(RoundedCornerShape(24.dp))
                        .background(Brand.copy(alpha = 0.25f)),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(a.name.take(1), style = T.h2, color = Brand)
                }
                Spacer(Modifier.width(12.dp))
                Column {
                    Text(a.name, style = T.rowTitle, color = Text1)
                    Text("${a.count} 首", style = T.caption, color = Text3)
                }
            }
        }
    }
}

@Composable
private fun AlbumDetail(vm: AppViewModel, albumId: String, onBack: () -> Unit) {
    val tracks by vm.tracks.collectAsState()
    val list = tracks.filter { it.albumId == albumId }
    val name = list.firstOrNull()?.albumName ?: "专辑"
    val artist = list.firstOrNull()?.artist ?: ""
    Column(Modifier.fillMaxSize()) {
        Row(
            Modifier.fillMaxWidth().padding(horizontal = Pad.page, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(Icons.AutoMirrored.Rounded.ArrowBack, contentDescription = "返回", tint = Text1,
                modifier = Modifier.size(24.dp).clickable(onClick = onBack))
            Spacer(Modifier.width(14.dp))
            Column {
                Text(name, style = T.h2, color = Text1, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text("$artist · ${list.size}首", style = T.caption, color = Text2)
            }
        }
        LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 180.dp)) {
            items(list, key = { it.id }) { t ->
                SongRow(track = t, playing = false, onClick = { vm.playTrack(t, list) })
            }
        }
    }
}

@Composable
private fun ArtistDetail(vm: AppViewModel, artist: String, onBack: () -> Unit) {
    val tracks by vm.tracks.collectAsState()
    val list = tracks.filter { it.artist == artist }
    Column(Modifier.fillMaxSize()) {
        Row(
            Modifier.fillMaxWidth().padding(horizontal = Pad.page, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(Icons.AutoMirrored.Rounded.ArrowBack, contentDescription = "返回", tint = Text1,
                modifier = Modifier.size(24.dp).clickable(onClick = onBack))
            Spacer(Modifier.width(14.dp))
            Column {
                Text(artist, style = T.h2, color = Text1)
                Text("${list.size} 首", style = T.caption, color = Text2)
            }
        }
        LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 180.dp)) {
            items(list, key = { it.id }) { t ->
                SongRow(track = t, playing = false, onClick = { vm.playTrack(t, list) })
            }
        }
    }
}

@Composable
private fun EmptyHint(vm: AppViewModel) {
    Column(
        Modifier.fillMaxWidth().padding(40.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text("曲库还是空的", style = T.h2, color = Text2)
        Spacer(Modifier.height(8.dp))
        Text("在「我的」页扫描本地音乐，或添加音乐来源", style = T.sub, color = Text3, textAlign = TextAlign.Center)
        Spacer(Modifier.height(20.dp))
        Text("立即扫描", style = T.sub, color = Brand, modifier = Modifier.clickable { vm.scanLocal() })
    }
}
