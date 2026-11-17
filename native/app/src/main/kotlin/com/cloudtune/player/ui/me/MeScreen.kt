package com.cloudtune.player.ui.me

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
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.layout.RowScope
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowRight
import androidx.compose.material.icons.rounded.Cloud
import androidx.compose.material.icons.rounded.DarkMode
import androidx.compose.material.icons.rounded.Language
import androidx.compose.material.icons.rounded.SystemUpdate
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import com.cloudtune.player.BuildConfig
import com.cloudtune.player.ui.AppViewModel
import com.cloudtune.player.ui.glass.Glass
import com.cloudtune.player.ui.theme.AppearanceMode
import com.cloudtune.player.ui.theme.Brand
import com.cloudtune.player.ui.theme.Pad
import com.cloudtune.player.ui.theme.R
import com.cloudtune.player.ui.theme.T
import com.cloudtune.player.ui.theme.Text1
import com.cloudtune.player.ui.theme.Text2
import com.cloudtune.player.ui.theme.Text3
import com.cloudtune.player.ui.theme.ThemeStore
import com.cloudtune.player.ui.theme.label
import com.cloudtune.player.ui.update.UpdatePhase

/**
 * 「我的」：目前只承载设置入口 + 版本信息。
 * 等数据层接通后再补统计卡（歌曲数/专辑数/目录数）。
 */
@Composable
fun MeScreen(
    vm: AppViewModel,
    updatePhase: UpdatePhase,
    onCheckUpdate: () -> Unit,
    onSources: () -> Unit = {},
) {
    val trackCount by vm.tracks.collectAsState()
    val albumCount by vm.albums.collectAsState()
    val artistCount by vm.artists.collectAsState()
    val scanning by vm.scanning.collectAsState()
    val progress by vm.scanProgress.collectAsState()

    // 外观设置弹窗
    var showAppearance by remember { mutableStateOf(false) }
    val appearanceMode by ThemeStore.mode.collectAsState()

    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .statusBarsPadding(),
        contentPadding = PaddingValues(start = Pad.pageWide, end = Pad.pageWide, bottom = 112.dp),
    ) {
        item {
            Spacer(Modifier.height(14.dp))
            Text("我的", style = T.h1, color = Text1)
            Spacer(Modifier.height(18.dp))
        }

        item {
            // 曲库统计卡 + 扫描入口
            Glass(
                modifier = Modifier.fillMaxWidth(),
                radius = R.lg,
                topLight = false,
                elevation = 8.dp,
            ) {
                Column(Modifier.padding(18.dp)) {
                    Row(Modifier.fillMaxWidth()) {
                        StatCell("${trackCount.size}", "歌曲")
                        StatCell("${albumCount.size}", "专辑")
                        StatCell("${artistCount.size}", "歌手")
                    }
                    Spacer(Modifier.height(16.dp))
                    Box(
                        Modifier
                            .fillMaxWidth()
                            .height(44.dp)
                            .clip(RoundedCornerShape(R.md))
                            .background(Brand)
                            .clickable(enabled = !scanning) { vm.scanLocal() },
                        contentAlignment = Alignment.Center,
                    ) {
                        Text(
                            if (scanning) "扫描中 ${(progress * 100).toInt()}%" else "扫描本地音乐",
                            style = T.sub.copy(fontWeight = FontWeight.Bold),
                            color = androidx.compose.ui.graphics.Color.White,
                        )
                    }
                }
            }
            Spacer(Modifier.height(16.dp))
        }

        item {
            SectionLabel("音乐")
            GroupCard {
                SettingRow(Icons.Rounded.Cloud, "音乐来源", "WebDAV / 本地目录", onClick = onSources)
                Divider()
                SettingRow(Icons.Rounded.Language, "语言", "简体中文")
                Divider()
                SettingRow(
                    Icons.Rounded.DarkMode,
                    "外观",
                    appearanceMode.label(),
                    onClick = { showAppearance = true },
                )
            }
            Spacer(Modifier.height(16.dp))
        }

        item {
            SectionLabel("关于")
            GroupCard {
                SettingRow(
                    icon = Icons.Rounded.SystemUpdate,
                    title = "检查更新",
                    subtitle = when (updatePhase) {
                        UpdatePhase.Checking -> "正在检查…"
                        else -> "当前版本 v${BuildConfig.VERSION_NAME}"
                    },
                    trailingAccent = updatePhase == UpdatePhase.Checking,
                    onClick = onCheckUpdate,
                )
            }
            Spacer(Modifier.height(20.dp))
            Text(
                text = "Nebu · 原生版",
                style = T.caption,
                color = Text3,
                modifier = Modifier.padding(start = 6.dp),
            )
        }
    }

    // 外观选择：改完立即生效并持久化，下次启动保持
    if (showAppearance) {
        val context = LocalContext.current
        AlertDialog(
            onDismissRequest = { showAppearance = false },
            title = { Text("外观", color = Text1) },
            text = {
                Column {
                    AppearanceMode.entries.forEach { m ->
                        Row(
                            Modifier
                                .fillMaxWidth()
                                .clickable { ThemeStore.set(context, m) },
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            RadioButton(
                                selected = appearanceMode == m,
                                onClick = { ThemeStore.set(context, m) },
                            )
                            Text(m.label(), style = T.rowTitle, color = Text1)
                        }
                    }
                }
            },
            confirmButton = {
                Text(
                    "完成",
                    style = T.sub.copy(fontWeight = FontWeight.Bold),
                    color = Brand,
                    modifier = Modifier.clickable { showAppearance = false },
                )
            },
        )
    }
}

@Composable
private fun RowScope.StatCell(value: String, label: String) {
    Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally) {
        Text(value, style = T.h1, color = Text1)
        Spacer(Modifier.height(2.dp))
        Text(label, style = T.caption, color = Text3)
    }
}

@Composable
private fun SectionLabel(text: String) {
    Text(
        text = text,
        style = T.label.copy(fontWeight = FontWeight.Bold),
        color = Text3,
        modifier = Modifier.padding(start = 6.dp, bottom = 8.dp),
    )
}

@Composable
private fun GroupCard(content: @Composable () -> Unit) {
    Glass(
        modifier = Modifier.fillMaxWidth(),
        radius = R.lg,
        topLight = false,
        elevation = 8.dp,
    ) {
        Column(Modifier.padding(vertical = 4.dp)) { content() }
    }
}

@Composable
private fun Divider() {
    Box(
        Modifier
            .fillMaxWidth()
            .padding(start = 52.dp, end = 14.dp)
            .height(1.dp)
            .background(Color.White.copy(alpha = 0.06f)),
    )
}

@Composable
private fun SettingRow(
    icon: ImageVector,
    title: String,
    subtitle: String,
    trailingAccent: Boolean = false,
    onClick: (() -> Unit)? = null,
) {
    Row(
        Modifier
            .fillMaxWidth()
            .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier)
            .padding(horizontal = 14.dp, vertical = 13.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            Modifier
                .size(26.dp)
                .clip(CircleShape)
                .background(Brand.copy(alpha = 0.16f)),
            contentAlignment = Alignment.Center,
        ) {
            Icon(icon, contentDescription = null, tint = Brand, modifier = Modifier.size(15.dp))
        }
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.Center) {
            Text(title, style = T.rowTitle, color = Text1)
            Spacer(Modifier.height(2.dp))
            Text(
                text = subtitle,
                style = T.caption,
                color = if (trailingAccent) Brand else Text2,
            )
        }
        Icon(
            Icons.AutoMirrored.Rounded.KeyboardArrowRight,
            contentDescription = null,
            tint = Text3,
            modifier = Modifier.size(17.dp),
        )
    }
}
