package com.cloudtune.player.playback

import android.content.Context
import android.util.Base64
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DefaultHttpDataSource
import com.cloudtune.player.data.webdav.WebDavAccountStore

/**
 * 带 Basic 认证的 DataSource：本地文件走默认，WebDAV 直链加 Authorization 头。
 *
 * 本地音乐是 content:// / file://，不走 HTTP，所以给所有 http(s) 请求带上
 * WebDAV 认证头互不影响。每次 createDataSource 都重新读账号，改密码后立即生效。
 */
class AuthDataSourceFactory(context: Context) : DataSource.Factory {
    private val accountStore = WebDavAccountStore(context)
    private val httpFactory = DefaultHttpDataSource.Factory()
        .setConnectTimeoutMs(20_000)
        .setReadTimeoutMs(30_000)
        .setAllowCrossProtocolRedirects(true)

    private fun basicAuth(account: WebDavAccountStore.Account): String {
        val token = "${account.username}:${account.password}".toByteArray(Charsets.UTF_8)
        return "Basic " + Base64.encodeToString(token, Base64.NO_WRAP)
    }

    override fun createDataSource(): DataSource {
        val props = accountStore.load()?.let { mapOf("Authorization" to basicAuth(it)) }
            ?: emptyMap()
        return httpFactory.setDefaultRequestProperties(props).createDataSource()
    }
}
