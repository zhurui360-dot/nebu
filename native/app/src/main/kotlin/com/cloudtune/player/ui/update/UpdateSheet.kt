package com.cloudtune.player.ui.update

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.Download
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.cloudtune.player.ui.glass.FrostedGlass
import com.cloudtune.player.ui.glass.Glass
import com.cloudtune.player.ui.theme.Brand
import com.cloudtune.player.ui.theme.Pad
import com.cloudtune.player.ui.theme.PlayBtnBg
import com.cloudtune.player.ui.theme.PlayBtnFg
import com.cloudtune.player.ui.theme.R
import com.cloudtune.player.ui.theme.T
import com.cloudtune.player.ui.theme.Text1
import com.cloudtune.player.ui.theme.Text2
import com.cloudtune.player.ui.theme.Text3

/**
 * 升级弹层。
 *
 * 用底部卡片而不是居中对话框：手机上弹出层从下方升起，手指本来就落在下半屏，
 * 「下载」按钮在拇指区，比居中对话框少一次手指移动。
 */
@Composable
fun UpdateSheet(
    state: UpdateUiState,
    onDownload: () -> Unit,
    onInstall: () -> Unit,
    onDismiss: () -> Unit,
) {
    if (!state.visible) return

    Box(
        Modifier
            .fillMaxSize()
            .background(Color.Black.copy(alpha = 0.55f))
            .clickable(
                // 下载中不给关：避免用户误以为取消后就不下载了
                enabled = state.phase != UpdatePhase.Downloading,
                indication = null,
                interactionSource = null,
            ) { onDismiss() },
        contentAlignment = Alignment.BottomCenter,
    ) {
        FrostedGlass(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 12.dp)
                .navigationBarsPadding()
                .padding(bottom = 12.dp),
            radius = R.xxl,
            elevation = 24.dp,
        ) {
            Column(Modifier.padding(22.dp)) {
                SheetHeader(state, onDismiss)
                Spacer(Modifier.height(16.dp))
                SheetBody(state)
                Spacer(Modifier.height(20.dp))
                SheetActions(state, onDownload, onInstall, onDismiss)
            }
        }
    }
}

@Composable
private fun SheetHeader(state: UpdateUiState, onDismiss: () -> Unit) {
    Row(verticalAlignment = Alignment.Top) {
        Column(Modifier.weight(1f)) {
            Text(
                text = when (state.phase) {
                    UpdatePhase.Latest -> "已是最新版本"
                    UpdatePhase.Checking -> "正在检查更新"
                    UpdatePhase.Error -> "检查失败"
                    else -> "发现新版本"
                },
                style = T.h1.copy(fontSize = T.h2.fontSize),
                color = Text1,
            )
            val info = state.info
            if (info != null) {
                Spacer(Modifier.height(4.dp))
                Text(
                    text = "v${info.version}" + if (info.sizeText.isNotEmpty()) " · ${info.sizeText}" else "",
                    style = T.caption,
                    color = Brand,
                )
            }
        }
        // 下载中隐藏关闭按钮，明确告诉用户"现在不能取消"
        if (state.phase != UpdatePhase.Downloading) {
            Box(
                Modifier
                    .size(30.dp)
                    .clip(CircleShape)
                    .background(Color.White.copy(alpha = 0.10f))
                    .clickable(onClick = onDismiss),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    Icons.Rounded.Close,
                    contentDescription = "关闭",
                    tint = Text2,
                    modifier = Modifier.size(17.dp),
                )
            }
        }
    }
}

@Composable
private fun SheetBody(state: UpdateUiState) {
    when (state.phase) {
        UpdatePhase.Downloading -> {
            DownloadProgress(state.progress)
        }

        UpdatePhase.Ready -> {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    Icons.Rounded.CheckCircle,
                    contentDescription = null,
                    tint = Brand,
                    modifier = Modifier.size(20.dp),
                )
                Spacer(Modifier.width(8.dp))
                Text("下载完成，点下方按钮安装", style = T.sub, color = Text2)
            }
        }

        UpdatePhase.Error -> {
            Text(
                text = state.error ?: "出了点问题，稍后再试",
                style = T.sub,
                color = Color(0xFFFF8A9B),
            )
        }

        UpdatePhase.Latest -> {
            Text("当前已是最新版本，无需更新。", style = T.sub, color = Text2)
        }

        UpdatePhase.Checking -> {
            Text("正在获取版本信息…", style = T.sub, color = Text2)
        }

        else -> {
            val notes = state.info?.notes ?: emptyList()
            if (notes.isEmpty()) {
                Text("优化了若干细节。", style = T.sub, color = Text2)
            } else {
                Column(
                    Modifier
                        .height(200.dp)
                        .verticalScroll(rememberScrollState()),
                    verticalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    notes.forEach { n ->
                        Row {
                            Text("·", style = T.sub, color = Brand)
                            Spacer(Modifier.width(8.dp))
                            Text(n, style = T.sub, color = Text2, modifier = Modifier.weight(1f))
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun DownloadProgress(progress: Float) {
    Column {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("正在下载", style = T.sub, color = Text1)
            Spacer(Modifier.weight(1f))
            // 进度数字用整数百分比就够了，小数点后一位会一直在跳，反而看不清
            Text("${(progress * 100).toInt()}%", style = T.caption, color = Brand)
        }
        Spacer(Modifier.height(10.dp))
        Box(
            Modifier
                .fillMaxWidth()
                .height(4.dp)
                .clip(CircleShape)
                .background(Color.White.copy(alpha = 0.16f)),
        ) {
            Box(
                Modifier
                    .fillMaxWidth(progress.coerceIn(0f, 1f))
                    .height(4.dp)
                    .clip(CircleShape)
                    .background(Brand),
            )
        }
    }
}

@Composable
private fun SheetActions(
    state: UpdateUiState,
    onDownload: () -> Unit,
    onInstall: () -> Unit,
    onDismiss: () -> Unit,
) {
    when (state.phase) {
        UpdatePhase.Found -> {
            ActionButton(text = "下载更新", onClick = onDownload)
            Spacer(Modifier.height(8.dp))
            TextButton(text = "以后再说", onClick = onDismiss)
        }

        UpdatePhase.Ready -> {
            ActionButton(text = "立即安装", onClick = onInstall, icon = true)
            Spacer(Modifier.height(8.dp))
            TextButton(text = "稍后", onClick = onDismiss)
        }

        UpdatePhase.Error -> {
            ActionButton(text = "重试", onClick = onDownload)
        }

        UpdatePhase.Latest -> {
            ActionButton(text = "知道了", onClick = onDismiss)
        }

        UpdatePhase.Checking, UpdatePhase.Downloading -> {
            // 进行中不放按钮，避免重复点击
        }

        else -> Unit
    }
}

@Composable
private fun ActionButton(text: String, onClick: () -> Unit, icon: Boolean = false) {
    Box(
        Modifier
            .fillMaxWidth()
            .height(50.dp)
            .clip(RoundedCornerShape(R.md))
            .background(PlayBtnBg)
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            if (icon) {
                Icon(
                    Icons.Rounded.Download,
                    contentDescription = null,
                    tint = PlayBtnFg,
                    modifier = Modifier.size(18.dp),
                )
                Spacer(Modifier.width(7.dp))
            }
            Text(
                text = text,
                style = T.rowTitle.copy(fontWeight = FontWeight.Bold),
                color = PlayBtnFg,
                textAlign = TextAlign.Center,
            )
        }
    }
}

@Composable
private fun TextButton(text: String, onClick: () -> Unit) {
    Box(
        Modifier
            .fillMaxWidth()
            .height(44.dp)
            .clip(RoundedCornerShape(R.md))
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Text(text = text, style = T.sub, color = Text3)
    }
}
