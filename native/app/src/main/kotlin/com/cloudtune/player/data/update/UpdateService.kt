package com.cloudtune.player.data.update

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

/** 一次更新检查的结果 */
data class UpdateInfo(
    val version: String,
    val versionCode: Int,
    val url: String,
    val sizeBytes: Long,
    val notes: List<String>,
    val force: Boolean,
) {
    val sizeText: String
        get() = if (sizeBytes <= 0) "" else "%.1f MB".format(sizeBytes / 1024.0 / 1024.0)
}

class UpdateException(message: String) : Exception(message)

/**
 * 在线升级。
 *
 * 清单格式与 Flutter 版完全一致，方便两版共用发布工具：
 * ```json
 * { "version": "0.0.005", "versionCode": 5, "url": "https://...apk",
 *   "size": 3456789, "force": false, "notes": ["..."] }
 * ```
 *
 * ⚠️ 原生版用**独立的清单文件**（version-native.json）：
 * 两版 applicationId 相同，若共用一份清单，Flutter 用户会被推去装原生版，
 * 而原生版还没接播放器 —— 等于把那批用户的功能直接砍掉。
 * 等原生版功能齐了再切回正式链路。
 */
object UpdateService {

    /** 正式渠道（Flutter 版在用，原生版暂不指这里） */
    const val ENDPOINT_RELEASE =
        "https://cdn.jsdelivr.net/gh/zhurui360-dot/nebu@main/version.json"

    /** 原生内测渠道 */
    const val ENDPOINT_NATIVE =
        "https://cdn.jsdelivr.net/gh/zhurui360-dot/nebu@main/version-native.json"

    /** 返回 null 表示已是最新 */
    suspend fun check(
        endpoint: String = ENDPOINT_NATIVE,
        currentVersionCode: Int,
        /** 本地版本号（如 "0.0.004"）：清单缺 versionCode 时用它逐段比 */
        currentVersion: String? = null,
    ): UpdateInfo? = withContext(Dispatchers.IO) {
        val body = try {
            httpGetText(endpoint)
        } catch (e: Exception) {
            throw UpdateException("连不上更新服务器，请检查网络")
        }

        val json = try {
            JSONObject(body)
        } catch (e: Exception) {
            throw UpdateException("更新信息格式不对（需要 JSON）")
        }

        val remoteCode = json.optInt("versionCode", 0)
        val version = json.optString("version").trim()
        if (version.isEmpty()) throw UpdateException("更新信息里缺少 version 字段")

        val newer = if (remoteCode > 0) {
            remoteCode > currentVersionCode
        } else {
            // 兜底：按 x.y.z 逐段比。必须拿本地版本号字符串来比，
            // 不能拿 versionCode 反推（0.0.010 vs [4,0,0] 会得出错误的结论）
            compareSemver(remote = version, local = currentVersion ?: "$currentVersionCode.0.0")
        }
        if (!newer) return@withContext null

        val notesArr = json.optJSONArray("notes")
        val notes = buildList {
            if (notesArr != null) {
                for (i in 0 until notesArr.length()) add(notesArr.optString(i))
            }
        }

        UpdateInfo(
            version = version,
            versionCode = remoteCode,
            url = json.optString("url").trim(),
            sizeBytes = json.optLong("size", 0L),
            notes = notes,
            force = json.optBoolean("force", false),
        )
    }

    private fun httpGetText(endpoint: String): String {
        val conn = (URL(endpoint).openConnection() as HttpURLConnection).apply {
            connectTimeout = 15_000
            readTimeout = 15_000
            requestMethod = "GET"
            // 清单必须拿到最新的一份，CDN 缓存会让人一直看到旧版本
            setRequestProperty("Cache-Control", "no-cache")
            instanceFollowRedirects = true
        }
        try {
            if (conn.responseCode != 200) {
                throw UpdateException("更新地址返回 ${conn.responseCode}")
            }
            return conn.inputStream.bufferedReader().use { it.readText() }
        } finally {
            conn.disconnect()
        }
    }

    /** 没有 versionCode 时的兜底：x.y.z 逐段比 */
    private fun compareSemver(remote: String, local: String): Boolean {
        val r = remote.split(".").map { it.toIntOrNull() ?: 0 }
        val l = local.split(".").map { it.toIntOrNull() ?: 0 }
        for (i in 0 until 3) {
            val a = r.getOrElse(i) { 0 }
            val b = l.getOrElse(i) { 0 }
            if (a != b) return a > b
        }
        return false
    }

    /* ---------------- 下载 ---------------- */

    /**
     * 下载 APK 到 cache 目录，回报 0..1 进度。
     *
     * 用 cache 而不是 files：安装完系统不一定会清，但 cache 在空间紧张时会被回收，
     * 不会永久占着几十 MB。
     */
    suspend fun download(
        context: Context,
        info: UpdateInfo,
        onProgress: (Float) -> Unit = {},
    ): File = withContext(Dispatchers.IO) {
        if (info.url.isEmpty()) throw UpdateException("更新信息里缺少下载地址")

        val dir = File(context.cacheDir, "updates").apply { mkdirs() }
        val target = File(dir, "nebu-${info.version}.apk")
        if (target.exists()) target.delete()

        val conn = (URL(info.url).openConnection() as HttpURLConnection).apply {
            connectTimeout = 20_000
            readTimeout = 30_000
            instanceFollowRedirects = true
        }
        try {
            if (conn.responseCode != 200) {
                throw UpdateException("下载失败（HTTP ${conn.responseCode}）")
            }
            val total = conn.contentLengthLong
            var received = 0L
            conn.inputStream.use { input ->
                target.outputStream().use { out ->
                    val buf = ByteArray(64 * 1024)
                    while (true) {
                        val n = input.read(buf)
                        if (n <= 0) break
                        out.write(buf, 0, n)
                        received += n
                        if (total > 0) {
                            onProgress((received.toFloat() / total).coerceIn(0f, 1f))
                        }
                    }
                }
            }
            if (received < 1024) throw UpdateException("下载到的文件不完整")
            target
        } finally {
            conn.disconnect()
        }
    }

    /* ---------------- 安装 ---------------- */

    /** 是否已获得「安装未知来源应用」权限 */
    fun canInstall(context: Context): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.packageManager.canRequestPackageInstalls()
        } else {
            true
        }

    /** 跳到系统设置，让用户给本应用开安装权限 */
    fun openInstallPermissionSettings(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        context.startActivity(
            Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                data = Uri.parse("package:${context.packageName}")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            },
        )
    }

    /**
     * 拉起系统安装界面。
     *
     * Android 7 起不允许用 file:// 直接传路径（FileUriExposedException），
     * 必须走 FileProvider 换成一个 content:// URI 并授予读权限。
     */
    fun install(context: Context, apk: File) {
        val uri = FileProvider.getUriForFile(
            context,
            "${context.packageName}.fileprovider",
            apk,
        )
        context.startActivity(
            Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            },
        )
    }

    /** 清掉下载过的包 */
    fun clean(context: Context) {
        File(context.cacheDir, "updates").deleteRecursively()
    }
}
