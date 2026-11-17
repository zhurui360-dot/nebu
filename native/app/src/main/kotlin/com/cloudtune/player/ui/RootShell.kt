package com.cloudtune.player.ui

import android.Manifest
import android.os.Build
import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.fadeIn
import androidx.compose.animation.slideInVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Home
import androidx.compose.material.icons.rounded.LibraryMusic
import androidx.compose.material.icons.rounded.Person
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.cloudtune.player.data.update.UpdateService
import com.cloudtune.player.ui.glass.FrostedGlass
import com.cloudtune.player.ui.home.HomeScreen
import com.cloudtune.player.ui.library.LibraryScreen
import com.cloudtune.player.ui.me.MeScreen
import com.cloudtune.player.ui.player.MiniPlayer
import com.cloudtune.player.ui.player.PlayerScreen
import com.cloudtune.player.ui.search.SearchScreen
import com.cloudtune.player.ui.sources.SourcesScreen
import com.cloudtune.player.ui.theme.NebuBackground
import com.cloudtune.player.ui.theme.Pad
import com.cloudtune.player.ui.theme.T
import com.cloudtune.player.ui.theme.Text1
import com.cloudtune.player.ui.update.UpdateSheet
import com.cloudtune.player.ui.update.UpdateViewModel

private enum class Tab(val label: String, val icon: ImageVector) {
    Home("主页", Icons.Rounded.Home),
    Library("曲库", Icons.Rounded.LibraryMusic),
    Search("搜索", Icons.Rounded.Search),
    Me("我的", Icons.Rounded.Person),
}

@Composable
fun RootShell(appVm: AppViewModel = viewModel(), updateVm: UpdateViewModel = viewModel()) {
    var index by rememberSaveable { mutableIntStateOf(0) }
    var showSources by remember { mutableStateOf(false) }
    var showWebDav by remember { mutableStateOf(false) }

    val updateState by updateVm.state.collectAsStateWithLifecycle()
    val playerExpanded by appVm.playerExpanded.collectAsStateWithLifecycle()
    val current by appVm.player.currentTrack.collectAsStateWithLifecycle()
    val context = LocalContext.current

    // 存储权限：拿到后自动扫描一次；通知权限（Android 13+）：媒体通知需要
    val audioPermission = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
        Manifest.permission.READ_MEDIA_AUDIO
    } else {
        Manifest.permission.READ_EXTERNAL_STORAGE
    }
    val permLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { granted -> if (granted) appVm.scanLocal() }
    val notifPermission = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
        Manifest.permission.POST_NOTIFICATIONS
    } else null
    val notifLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { /* 拒绝也不阻塞：只是锁屏/通知栏看不到媒体通知 */ }

    // 播放出错时给用户明确提示（之前"点了没反应"就是这个原因）
    val playerError by appVm.player.error.collectAsStateWithLifecycle()
    LaunchedEffect(playerError) {
        playerError?.let {
            Toast.makeText(context, it, Toast.LENGTH_LONG).show()
            appVm.player.clearError()
        }
    }

    LaunchedEffect(Unit) {
        permLauncher.launch(audioPermission)
        notifPermission?.let { notifLauncher.launch(it) }
        updateVm.checkSilently()
    }

    Box(Modifier.fillMaxSize()) {
        NebuBackground()

        // 主内容区
        Box(Modifier.fillMaxSize()) {
            when (Tab.entries[index]) {
                Tab.Home -> HomeScreen(
                    vm = appVm,
                    onGoSearch = { index = 2 },
                    onGoTab = { index = it },
                )
                Tab.Library -> LibraryScreen(appVm)
                Tab.Search -> SearchScreen(appVm)
                Tab.Me -> MeScreen(
                    vm = appVm,
                    updatePhase = updateState.phase,
                    onCheckUpdate = updateVm::checkManually,
                    onSources = { showSources = true },
                )
            }
        }

        // 迷你播放条（有歌在播 且 播放页未展开时显示）
        AnimatedVisibility(
            visible = current != null && !playerExpanded,
            enter = slideInVertically(initialOffsetY = { it }) + fadeIn(),
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .padding(bottom = 84.dp),
        ) {
            MiniPlayer(appVm.player, onExpand = appVm::expandPlayer)
        }

        BottomDock(
            selected = index,
            onSelect = { index = it },
            modifier = Modifier.align(Alignment.BottomCenter),
        )

        // 全屏播放页
        AnimatedVisibility(
            visible = playerExpanded,
            enter = slideInVertically(initialOffsetY = { it / 2 }) + fadeIn(),
        ) {
            Box(
                Modifier
                    .fillMaxSize()
                    .background(com.cloudtune.player.ui.theme.BgBottom),
            ) {
                PlayerScreen(appVm.player, onClose = appVm::collapsePlayer)
            }
        }

        // 来源页
        if (showSources) {
            Box(Modifier.fillMaxSize().background(com.cloudtune.player.ui.theme.BgBottom)) {
                SourcesScreen(
                    vm = appVm,
                    onBack = { showSources = false },
                    onWebDav = { showWebDav = true },
                )
            }
        }

        // WebDAV 配置页
        if (showWebDav) {
            Box(Modifier.fillMaxSize().background(com.cloudtune.player.ui.theme.BgBottom)) {
                com.cloudtune.player.ui.sources.WebDavConfigScreen(
                    vm = appVm,
                    onBack = { showWebDav = false },
                )
            }
        }

        UpdateSheet(
            state = updateState,
            onDownload = updateVm::download,
            onInstall = {
                updateVm.install {
                    UpdateService.openInstallPermissionSettings(context)
                }
            },
            onDismiss = updateVm::dismiss,
        )
    }
}

/**
 * 底部玻璃胶囊导航。选中态是会滑动的胶囊（设计稿 04 的做法）。
 */
@Composable
private fun BottomDock(
    selected: Int,
    onSelect: (Int) -> Unit,
    modifier: Modifier = Modifier,
) {
    val items = Tab.entries

    Box(
        modifier
            .fillMaxWidth()
            .navigationBarsPadding()
            .padding(horizontal = Pad.page)
            .padding(bottom = 10.dp),
    ) {
        FrostedGlass(
            modifier = Modifier.fillMaxWidth().height(62.dp),
            radius = 31.dp,
            elevation = 18.dp,
        ) {
            BoxWithConstraints(Modifier.fillMaxSize().padding(4.dp)) {
                val itemW = (maxWidth - 8.dp) / items.size
                val targetX by animateDpAsState(
                    targetValue = itemW * selected,
                    animationSpec = spring(dampingRatio = 0.78f, stiffness = 480f),
                    label = "dock-pill",
                )
                Box(
                    Modifier
                        .offset(x = targetX + 4.dp)
                        .width(itemW)
                        .fillMaxHeight()
                        .clip(RoundedCornerShape(27.dp))
                        .background(Color.White.copy(alpha = 0.16f))
                        .border(1.dp, Color.White.copy(alpha = 0.22f), RoundedCornerShape(27.dp)),
                )
                Row(Modifier.fillMaxSize(), horizontalArrangement = Arrangement.SpaceEvenly) {
                    items.forEachIndexed { i, tab ->
                        DockItem(tab, i == selected, Modifier.width(itemW)) { onSelect(i) }
                    }
                }
            }
        }
    }
}

@Composable
private fun DockItem(
    tab: Tab,
    selected: Boolean,
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
) {
    val interaction = remember { MutableInteractionSource() }
    Column(
        modifier = modifier
            .fillMaxHeight()
            .clip(RoundedCornerShape(27.dp))
            .clickable(interactionSource = interaction, indication = null, onClick = onClick),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Icon(
            tab.icon,
            contentDescription = tab.label,
            tint = if (selected) Text1 else Text1.copy(alpha = 0.5f),
            modifier = Modifier.size(20.dp),
        )
        Spacer(Modifier.height(3.dp))
        Text(tab.label, style = T.label, color = if (selected) Text1 else Text1.copy(alpha = 0.5f))
    }
}
