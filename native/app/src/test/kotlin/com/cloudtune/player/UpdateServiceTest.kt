package com.cloudtune.player

import com.cloudtune.player.data.update.UpdateException
import com.cloudtune.player.data.update.UpdateService
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.ServerSocket
import kotlin.concurrent.thread

/**
 * 升级清单解析与比对。
 *
 * 用真的 ServerSocket 起一个极简 HTTP 服务，而不是 mock：
 * 这样 HttpURLConnection 的响应码、header、流读取这些真机路径都走一遍。
 * （不用 com.sun.net.httpserver —— Android 单元测试的 boot classpath 里没有它。）
 */
class UpdateServiceTest {

    private fun withServer(
        body: String,
        code: Int = 200,
        block: (String) -> Unit,
    ) {
        val server = ServerSocket(0, 1, java.net.InetAddress.getByName("127.0.0.1"))
        val t = thread(isDaemon = true) {
            try {
                server.accept().use { sock ->
                    val reader = BufferedReader(InputStreamReader(sock.getInputStream()))
                    // 消费请求头，读到空行为止；不读干净客户端会卡在写请求上
                    while (true) {
                        val line = reader.readLine() ?: break
                        if (line.isEmpty()) break
                    }
                    val payload = body.toByteArray()
                    val head = buildString {
                        append("HTTP/1.1 $code OK\r\n")
                        append("Content-Type: application/json\r\n")
                        append("Content-Length: ${payload.size}\r\n")
                        append("Connection: close\r\n\r\n")
                    }.toByteArray()
                    sock.getOutputStream().apply {
                        write(head)
                        write(payload)
                        flush()
                    }
                }
            } catch (_: Exception) {
            }
        }
        try {
            block("http://127.0.0.1:${server.localPort}/v.json")
        } finally {
            server.close()
            t.join(1000)
        }
    }

    @Test
    fun `远端版本更高时返回更新信息`() = withServer(
        """{"version":"0.0.009","versionCode":9,"url":"https://x/a.apk","size":1048576,
           "force":false,"notes":["修复 A","优化 B"]}""",
    ) { url ->
        val info = runBlocking { UpdateService.check(url, currentVersionCode = 4) }
        assertTrue(info != null)
        assertEquals("0.0.009", info!!.version)
        assertEquals(9, info.versionCode)
        assertEquals("https://x/a.apk", info.url)
        assertEquals(2, info.notes.size)
        assertEquals("1.0 MB", info.sizeText)
    }

    @Test
    fun `版本相同返回 null`() = withServer(
        """{"version":"0.0.004","versionCode":4,"url":"https://x/a.apk"}""",
    ) { url ->
        val info = runBlocking { UpdateService.check(url, currentVersionCode = 4) }
        assertTrue(info == null)
    }

    @Test
    fun `HTTP 非 200 抛异常`() = withServer("oops", code = 500) { url ->
        var thrown: Exception? = null
        try {
            runBlocking { UpdateService.check(url, currentVersionCode = 4) }
        } catch (e: Exception) {
            thrown = e
        }
        assertTrue(thrown is UpdateException)
    }

    @Test
    fun `非法 JSON 抛异常而不是崩溃`() = withServer("not json at all") { url ->
        var thrown: Exception? = null
        try {
            runBlocking { UpdateService.check(url, currentVersionCode = 4) }
        } catch (e: Exception) {
            thrown = e
        }
        assertTrue(thrown is UpdateException)
    }

    @Test
    fun `缺 version 字段抛异常`() = withServer(
        """{"versionCode":9,"url":"https://x/a.apk"}""",
    ) { url ->
        var thrown: Exception? = null
        try {
            runBlocking { UpdateService.check(url, currentVersionCode = 4) }
        } catch (e: Exception) {
            thrown = e
        }
        assertTrue(thrown is UpdateException)
    }

    @Test
    fun `没有 versionCode 时按语义化版本比对`() {
        // 远端 0.0.010 vs 本地 0.0.004：第三段 10 > 4，应有更新
        withServer("""{"version":"0.0.010","url":"https://x/a.apk"}""") { url ->
            val info = runBlocking {
                UpdateService.check(url, currentVersionCode = 4, currentVersion = "0.0.004")
            }
            assertTrue(info != null)
            assertEquals("0.0.010", info!!.version)
        }
        // 反过来：远端 0.0.002 < 本地 0.0.004，不该提示
        withServer("""{"version":"0.0.002","url":"https://x/a.apk"}""") { url ->
            val info = runBlocking {
                UpdateService.check(url, currentVersionCode = 4, currentVersion = "0.0.004")
            }
            assertTrue(info == null)
        }
    }
}
