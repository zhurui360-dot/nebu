package com.cloudtune.player

import com.cloudtune.player.ui.components.formatTime
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * 纯逻辑测试。UI 渲染依赖真实数据库/MediaStore/MediaSession，
 * 无设备 JVM 上无法等价验证，交给真机验收；这里守住能测的纯函数。
 */
class HomeScreenTest {

    @Test
    fun `时间格式化`() {
        assertEquals("0:00", formatTime(0))
        assertEquals("0:00", formatTime(-100))
        assertEquals("1:36", formatTime(96_000))
        assertEquals("3:48", formatTime(228_000))
        assertEquals("59:59", formatTime(3_599_000))
    }
}
