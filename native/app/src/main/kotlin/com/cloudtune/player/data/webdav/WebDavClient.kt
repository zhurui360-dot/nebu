package com.cloudtune.player.data.webdav

import android.util.Xml
import okhttp3.Credentials
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.xmlpull.v1.XmlPullParser
import java.io.StringReader
import java.net.URLEncoder
import java.util.concurrent.TimeUnit

/**
 * WebDAV 客户端：群晖 / 坚果云 / Alist / NextCloud 通用。
 *
 * 只用到 PROPFIND（Depth:1 列目录）。Basic 认证。
 * XML 用 Android 内置的 XmlPullParser，不引第三方解析库。
 */
class WebDavClient(
    val baseUrl: String,
    val username: String,
    val password: String,
) {
    private val client = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(20, TimeUnit.SECONDS)
        .build()

    private val auth: String by lazy { Credentials.basic(username, password) }

    data class Entry(
        val path: String,
        val name: String,
        val isDir: Boolean,
        val size: Long,
    )

    class WebDavException(message: String, val status: Int = 0) : Exception(message)

    private fun uri(path: String): String {
        val base = if (baseUrl.endsWith("/")) baseUrl else "$baseUrl/"
        val rel = path.removePrefix("/")
        // 保留目录分隔符，逐段编码（支持中文文件名）
        val encoded = rel.split("/").joinToString("/") { URLEncoder.encode(it, "UTF-8") }
        return base + encoded
    }

    /** 测试连接：PROPFIND 根目录，成功即账号可用 */
    fun testConnection() {
        val res = propfindRaw("/")
        if (res.status !in 200..299) {
            throw WebDavException(
                if (res.status == 401) "账号或密码不正确" else "连接失败（${res.status}）",
                res.status,
            )
        }
    }

    /** 列目录（Depth:1） */
    fun list(path: String): List<Entry> {
        val res = propfindRaw(path)
        if (res.status == 401) throw WebDavException("账号或密码不正确", 401)
        if (res.status !in 200..299) throw WebDavException("列目录失败（${res.status}）", res.status)
        return parsePropfind(res.body, path)
    }

    private data class RawResult(val status: Int, val body: String)

    private fun propfindRaw(path: String): RawResult {
        val xml = """<?xml version="1.0" encoding="utf-8"?>
<d:propfind xmlns:d="DAV:">
  <d:prop>
    <d:displayname/>
    <d:getcontentlength/>
    <d:resourcetype/>
    <d:getlastmodified/>
  </d:prop>
</d:propfind>""".trimIndent()
        val req = Request.Builder()
            .url(uri(path))
            .method("PROPFIND", xml.toRequestBody("application/xml; charset=utf-8".toMediaType()))
            .header("Authorization", auth)
            .header("Depth", "1")
            .build()
        client.newCall(req).execute().use { resp ->
            return RawResult(resp.code, resp.body?.string().orEmpty())
        }
    }

    /** 播放直链（带认证头，交给 Media3 的自定义 DataSource） */
    fun directUrl(path: String): String = uri(path)

    fun authHeader(): String = auth

    /** 解析 PROPFIND 207 XML。处理 href 绝对/相对 URL、中文转义、base path 剥离 */
    private fun parsePropfind(xml: String, requestPath: String): List<Entry> {
        val entries = ArrayList<Entry>()
        val parser = Xml.newPullParser()
        parser.setFeature(XmlPullParser.FEATURE_PROCESS_NAMESPACES, false)
        parser.setInput(StringReader(xml))

        var inResponse = false
        var href: String? = null
        var isDir = false
        var size = 0L

        fun flush() {
            if (href == null) return
            val rel = toRelPath(href!!) ?: return
            if (normalize(rel) == normalize(requestPath)) return
            val segs = rel.split("/").filter { it.isNotEmpty() }
            if (segs.isEmpty()) return
            entries.add(Entry(rel, segs.last(), isDir, size))
            href = null; isDir = false; size = 0L
        }

        var event = parser.eventType
        while (event != XmlPullParser.END_DOCUMENT) {
            when (event) {
                XmlPullParser.START_TAG -> {
                    when (parser.name.substringAfter(':')) {
                        "response" -> inResponse = true
                        "href" -> if (inResponse) href = parser.nextText()
                        "collection" -> if (inResponse) isDir = true
                        "getcontentlength" -> if (inResponse) {
                            size = parser.nextText().trim().toLongOrNull() ?: 0L
                        }
                    }
                }
                XmlPullParser.END_TAG -> {
                    if (parser.name.substringAfter(':') == "response") {
                        flush(); inResponse = false
                    }
                }
            }
            event = parser.next()
        }

        return entries.sortedWith(
            compareByDescending<Entry> { it.isDir }.thenBy { it.name.lowercase() }
        )
    }

    private fun normalize(s: String): String {
        var t = s.trim()
        while (t.length > 1 && t.endsWith("/")) t = t.dropLast(1)
        return if (t.isEmpty()) "/" else t
    }

    private fun toRelPath(href: String): String? {
        var p = href.trim()
        if (p.isEmpty()) return null
        // 解码 %XX（失败就原样）
        p = try {
            java.net.URLDecoder.decode(p, "UTF-8")
        } catch (_: Exception) { p }
        // 绝对 URL 取 path
        if (p.contains("://")) {
            p = try { java.net.URI.create(p).path } catch (_: Exception) { return null }
        }
        if (!p.startsWith("/")) p = "/$p"
        // 剥 baseUrl 的 path 前缀
        val basePath = try { java.net.URI.create(baseUrl).path.orEmpty() } catch (_: Exception) { "" }
        val bp = basePath.trimEnd('/')
        if (bp.isNotEmpty() && bp != "/") {
            p = when {
                p == bp -> "/"
                p.startsWith("$bp/") -> p.substring(bp.length)
                else -> p
            }
        }
        return normalize(p)
    }
}
