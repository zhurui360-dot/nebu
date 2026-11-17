package com.cloudtune.player

import android.app.Application
import com.cloudtune.player.data.MusicRepository

class NebuApp : Application() {
    override fun onCreate() {
        super.onCreate()
        // 启动时就开始读库，进首页不用等
        MusicRepository.get(this)
    }
}
