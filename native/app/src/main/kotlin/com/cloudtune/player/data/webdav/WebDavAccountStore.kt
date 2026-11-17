package com.cloudtune.player.data.webdav

import android.content.Context
import android.content.SharedPreferences

/** WebDAV 账号配置存储（SharedPreferences，简单够用）。 */
class WebDavAccountStore(context: Context) {
    private val prefs: SharedPreferences =
        context.applicationContext.getSharedPreferences("webdav_account", Context.MODE_PRIVATE)

    data class Account(val baseUrl: String, val username: String, val password: String, val folder: String = "/")

    fun save(account: Account) {
        prefs.edit()
            .putString("baseUrl", account.baseUrl)
            .putString("username", account.username)
            .putString("password", account.password)
            .putString("folder", account.folder)
            .apply()
    }

    fun load(): Account? {
        val url = prefs.getString("baseUrl", null) ?: return null
        return Account(
            baseUrl = url,
            username = prefs.getString("username", "").orEmpty(),
            password = prefs.getString("password", "").orEmpty(),
            folder = prefs.getString("folder", "/") ?: "/",
        )
    }

    fun clear() = prefs.edit().clear().apply()
}
