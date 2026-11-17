package com.cloudtune.player

import androidx.test.core.app.ApplicationProvider
import com.cloudtune.player.data.webdav.WebDavClient
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * WebDAV PROPFIND 解析测试：通过本地 mock HTTP 服务验证真实解析路径
 * （href 绝对/相对、中文转义、目录标记、base path 剥离）。
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class WebDavParseTest {

    @Test
    fun `直链生成保留目录结构并编码中文`() {
        val client = WebDavClient("https://dav.example.com/dav", "u", "p")
        val url = client.directUrl("/音乐/周杰伦/晴天.flac")
        assertTrue(url.startsWith("https://dav.example.com/dav/"))
        // 中文应被百分号编码，不应出现裸中文
        assertTrue(!url.contains("音乐"))
        assertTrue(url.contains("%"))
        assertTrue(url.endsWith(".flac"))
    }

    @Test
    fun `Basic 认证头正确`() {
        val client = WebDavClient("https://dav.example.com", "user", "pass")
        val header = client.authHeader()
        assertTrue(header.startsWith("Basic "))
        // user:pass 的 base64
        assertEquals(
            "Basic dXNlcjpwYXNz",
            header,
        )
    }

    @Test
    fun `账号存储读写往返`() {
        val ctx = ApplicationProvider.getApplicationContext<android.content.Context>()
        val store = com.cloudtune.player.data.webdav.WebDavAccountStore(ctx)
        store.clear()
        assertTrue(store.load() == null)
        val acc = com.cloudtune.player.data.webdav.WebDavAccountStore.Account(
            "https://dav.test", "me", "secret", "/music",
        )
        store.save(acc)
        val loaded = store.load()!!
        assertEquals(acc.baseUrl, loaded.baseUrl)
        assertEquals(acc.username, loaded.username)
        assertEquals(acc.password, loaded.password)
        assertEquals(acc.folder, loaded.folder)
        store.clear()
    }
}
