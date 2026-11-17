package com.cloudtune.player.ui.sources

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowRight
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.Cloud
import androidx.compose.material.icons.rounded.Folder
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
import androidx.compose.ui.unit.dp
import com.cloudtune.player.ui.AppViewModel
import com.cloudtune.player.ui.glass.Glass
import com.cloudtune.player.ui.theme.Brand
import com.cloudtune.player.ui.theme.Pad
import com.cloudtune.player.ui.theme.R
import com.cloudtune.player.ui.theme.T
import com.cloudtune.player.ui.theme.Text1
import com.cloudtune.player.ui.theme.Text2
import com.cloudtune.player.ui.theme.Text3

/** 音乐来源：本地音乐（MediaStore 自动扫描）+ WebDAV。 */
@Composable
fun SourcesScreen(
    vm: AppViewModel,
    onBack: () -> Unit,
    onWebDav: () -> Unit,
) {
    val tracks by vm.tracks.collectAsState()
    val scanning by vm.scanning.collectAsState()

    Column(Modifier.fillMaxSize().statusBarsPadding()) {
        Row(
            Modifier.fillMaxWidth().padding(horizontal = Pad.page, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text("音乐来源", style = T.h2, color = Text1, modifier = Modifier.weight(1f))
            Text("完成", style = T.sub, color = Brand, modifier = Modifier.clickable(onClick = onBack))
        }

        Column(Modifier.padding(horizontal = Pad.page)) {
            SourceCard(
                icon = Icons.Rounded.Folder,
                title = "本地音乐",
                subtitle = "自动扫描手机里的音频 · 当前 ${tracks.size} 首",
                trailing = "已启用",
                accent = true,
                onClick = { vm.scanLocal() },
            )
            Spacer(Modifier.height(12.dp))
            SourceCard(
                icon = Icons.Rounded.Cloud,
                title = "WebDAV 网盘",
                subtitle = "连接远程网盘，直接播放云端音乐",
                trailing = "配置",
                onClick = onWebDav,
            )
            Spacer(Modifier.height(16.dp))
            Text(
                "本地音乐由系统媒体库自动索引，点「本地音乐」可随时重新扫描。",
                style = T.caption,
                color = Text3,
            )
        }
    }
}

@Composable
private fun SourceCard(
    icon: ImageVector,
    title: String,
    subtitle: String,
    trailing: String,
    accent: Boolean = false,
    onClick: () -> Unit,
) {
    Glass(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick),
        radius = R.lg,
        topLight = false,
        elevation = 8.dp,
    ) {
        Row(Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(
                Modifier.size(42.dp).clip(CircleShape).background(Brand.copy(alpha = 0.18f)),
                contentAlignment = Alignment.Center,
            ) {
                Icon(icon, contentDescription = null, tint = Brand, modifier = Modifier.size(20.dp))
            }
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Text(title, style = T.rowTitle, color = Text1)
                Spacer(Modifier.height(2.dp))
                Text(subtitle, style = T.caption, color = Text2)
            }
            if (accent) {
                Icon(Icons.Rounded.CheckCircle, contentDescription = null, tint = Brand, modifier = Modifier.size(18.dp))
            } else {
                Text(trailing, style = T.caption, color = Brand)
                Spacer(Modifier.width(2.dp))
                Icon(Icons.AutoMirrored.Rounded.KeyboardArrowRight, contentDescription = null, tint = Text3, modifier = Modifier.size(16.dp))
            }
        }
    }
}
