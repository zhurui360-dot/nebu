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
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.cloudtune.player.data.webdav.WebDavAccountStore
import com.cloudtune.player.data.webdav.WebDavClient
import com.cloudtune.player.ui.AppViewModel
import com.cloudtune.player.ui.theme.Brand
import com.cloudtune.player.ui.theme.Pad
import com.cloudtune.player.ui.theme.R
import com.cloudtune.player.ui.theme.T
import com.cloudtune.player.ui.theme.Text1
import com.cloudtune.player.ui.theme.Text2
import com.cloudtune.player.ui.theme.Text3
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** WebDAV 配置页：填地址/账号，测试连接，保存并扫描。 */
@Composable
fun WebDavConfigScreen(
    vm: AppViewModel,
    onBack: () -> Unit,
) {
    val context = LocalContext.current
    val store = remember { WebDavAccountStore(context) }
    val saved = remember { store.load() }

    var url by remember { mutableStateOf(saved?.baseUrl ?: "") }
    var user by remember { mutableStateOf(saved?.username ?: "") }
    var pass by remember { mutableStateOf(saved?.password ?: "") }
    var folder by remember { mutableStateOf(saved?.folder ?: "/") }
    var status by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }

    val fieldColors = OutlinedTextFieldDefaults.colors(
        focusedTextColor = Text1, unfocusedTextColor = Text1,
        focusedBorderColor = Brand, unfocusedBorderColor = Color.White.copy(alpha = 0.15f),
        cursorColor = Brand, focusedLabelColor = Brand, unfocusedLabelColor = Text3,
    )

    Column(
        Modifier.fillMaxSize().statusBarsPadding().padding(horizontal = Pad.page),
    ) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text("WebDAV 网盘", style = T.h2, color = Text1, modifier = Modifier.weight(1f))
            Text("返回", style = T.sub, color = Brand, modifier = Modifier.clickable(onClick = onBack))
        }
        Spacer(Modifier.height(8.dp))
        Text(
            "支持群晖 / 坚果云 / NextCloud / Alist 等标准 WebDAV",
            style = T.caption, color = Text3,
        )
        Spacer(Modifier.height(20.dp))

        OutlinedTextField(
            value = url, onValueChange = { url = it }, singleLine = true,
            label = { Text("服务器地址") }, placeholder = { Text("https://dav.example.com") },
            modifier = Modifier.fillMaxWidth(), shape = RoundedCornerShape(R.md), colors = fieldColors,
        )
        Spacer(Modifier.height(12.dp))
        OutlinedTextField(
            value = user, onValueChange = { user = it }, singleLine = true,
            label = { Text("用户名") }, modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(R.md), colors = fieldColors,
        )
        Spacer(Modifier.height(12.dp))
        OutlinedTextField(
            value = pass, onValueChange = { pass = it }, singleLine = true,
            label = { Text("密码") }, modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(R.md), colors = fieldColors,
        )
        Spacer(Modifier.height(12.dp))
        OutlinedTextField(
            value = folder, onValueChange = { folder = it }, singleLine = true,
            label = { Text("音乐目录（可选）") }, placeholder = { Text("/") },
            modifier = Modifier.fillMaxWidth(), shape = RoundedCornerShape(R.md), colors = fieldColors,
        )

        Spacer(Modifier.height(20.dp))
        if (status.isNotBlank()) {
            Text(status, style = T.caption, color = if (status.contains("失败") || status.contains("不正确")) Color(0xFFFF8A8A) else Brand)
            Spacer(Modifier.height(12.dp))
        }

        val scope = rememberCoroutineScopeCompat()
        Button(
            onClick = {
                if (url.isBlank() || user.isBlank()) {
                    status = "请填写服务器地址和用户名"
                    return@Button
                }
                busy = true
                status = "正在连接…"
                scope.launch {
                    val account = WebDavAccountStore.Account(
                        url.trim(), user, pass, folder.ifBlank { "/" },
                    )
                    val msg = withContext(Dispatchers.IO) {
                        try {
                            WebDavClient(account.baseUrl, account.username, account.password).testConnection()
                            store.save(account)
                            "连接成功"
                        } catch (e: WebDavClient.WebDavException) {
                            "连接失败：${e.message}"
                        } catch (e: Exception) {
                            "连接失败：${e.message ?: "未知错误"}"
                        }
                    }
                    status = msg
                    busy = false
                    if (msg == "连接成功") {
                        // 连接成功后立即扫描入库
                        status = "正在扫描音乐…"
                        vm.scanWebDav { result -> status = result }
                    }
                }
            },
            enabled = !busy,
            modifier = Modifier.fillMaxWidth().height(48.dp),
            shape = RoundedCornerShape(24.dp),
            colors = ButtonDefaults.buttonColors(containerColor = Brand),
        ) {
            Text(if (busy) "请稍候…" else "连接并扫描", color = Color.White)
        }

        Spacer(Modifier.height(16.dp))
        if (saved != null) {
            Text(
                "已保存账号：${saved.username}@${saved.baseUrl}",
                style = T.caption, color = Text3, textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth(),
            )
        }
    }
}

@Composable
private fun rememberCoroutineScopeCompat(): CoroutineScope =
    androidx.compose.runtime.remember { CoroutineScope(Dispatchers.Main + kotlinx.coroutines.SupervisorJob()) }
