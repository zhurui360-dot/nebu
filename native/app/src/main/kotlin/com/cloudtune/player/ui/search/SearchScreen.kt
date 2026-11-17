package com.cloudtune.player.ui.search

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.cloudtune.player.ui.AppViewModel
import com.cloudtune.player.ui.components.SongRow
import com.cloudtune.player.ui.theme.Brand
import com.cloudtune.player.ui.theme.Pad
import com.cloudtune.player.ui.theme.R
import com.cloudtune.player.ui.theme.T
import com.cloudtune.player.ui.theme.Text1
import com.cloudtune.player.ui.theme.Text2
import com.cloudtune.player.ui.theme.Text3

/** 搜索：输入即时过滤曲库（歌名/歌手/专辑）。 */
@Composable
fun SearchScreen(vm: AppViewModel) {
    var query by remember { mutableStateOf("") }
    val tracks by vm.tracks.collectAsState()
    val currentId by vm.player.currentTrack.collectAsState()

    val results = remember(query, tracks) {
        if (query.isBlank()) emptyList() else vm.search(query)
    }

    Column(Modifier.fillMaxSize()) {
        Text(
            "搜索",
            style = T.h1,
            color = Text1,
            modifier = Modifier.padding(start = Pad.pageWide, top = 22.dp, bottom = 6.dp),
        )
        OutlinedTextField(
            value = query,
            onValueChange = { query = it },
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = Pad.page, vertical = 8.dp),
            placeholder = { Text("搜索歌曲、歌手、专辑", color = Text3) },
            singleLine = true,
            shape = androidx.compose.foundation.shape.RoundedCornerShape(R.md),
            colors = OutlinedTextFieldDefaults.colors(
                focusedTextColor = Text1,
                unfocusedTextColor = Text1,
                focusedBorderColor = Brand,
                unfocusedBorderColor = Color.White.copy(alpha = 0.15f),
                cursorColor = Brand,
            ),
        )

        LazyColumn(
            Modifier.fillMaxSize(),
            contentPadding = PaddingValues(bottom = 180.dp),
        ) {
            if (query.isBlank()) {
                item {
                    Spacer(Modifier.height(60.dp))
                    Text(
                        "输入关键词开始搜索",
                        style = T.sub,
                        color = Text3,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
            } else if (results.isEmpty()) {
                item {
                    Spacer(Modifier.height(60.dp))
                    Text(
                        "没有找到「$query」",
                        style = T.sub,
                        color = Text3,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
            } else {
                item {
                    Text(
                        "${results.size} 个结果",
                        style = T.caption,
                        color = Text3,
                        modifier = Modifier.padding(horizontal = Pad.page, vertical = 6.dp),
                    )
                }
                items(results, key = { it.id }) { t ->
                    SongRow(
                        track = t,
                        playing = t.id == currentId?.id,
                        onClick = { vm.playTrack(t, results) },
                    )
                }
            }
        }
    }
}
