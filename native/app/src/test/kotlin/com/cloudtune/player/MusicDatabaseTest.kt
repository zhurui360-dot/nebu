package com.cloudtune.player

import androidx.test.core.app.ApplicationProvider
import com.cloudtune.player.data.db.MusicDatabase
import com.cloudtune.player.data.model.Track
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/** 数据层测试：曲库入库、去重、搜索、专辑/歌手聚合。用 Robolectric 的真 SQLite。 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class MusicDatabaseTest {

    private lateinit var db: MusicDatabase

    @Before
    fun setUp() {
        db = MusicDatabase(ApplicationProvider.getApplicationContext())
        db.deleteAll()
    }

    private fun track(id: String, title: String, artist: String, album: String, size: Long = 100L) = Track(
        id = id, title = title, artist = artist, albumId = "al_$album", albumName = album,
        durationMs = 180_000, url = "/music/$id.mp3", source = "local", sizeBytes = size,
    )

    @Test
    fun `入库后能查到并按标题排序`() {
        db.upsertAll(listOf(
            track("1", "Zebra", "歌手A", "专辑一"),
            track("2", "Apple", "歌手B", "专辑二"),
        ))
        val all = db.allTracks()
        assertEquals(2, all.size)
        assertEquals("Apple", all[0].title) // COLLATE NOCASE 排序
        assertEquals(2L, db.count())
    }

    @Test
    fun `同 id 重复入库会覆盖不产生重复行`() {
        val t = track("1", "原标题", "歌手A", "专辑一")
        db.upsertAll(listOf(t))
        db.upsertAll(listOf(t.copy(title = "新标题")))
        val all = db.allTracks()
        assertEquals(1, all.size)
        assertEquals("新标题", all[0].title)
    }

    @Test
    fun `增量路径映射正确`() {
        db.upsertAll(listOf(track("1", "歌", "歌手", "专辑", size = 12345L)))
        val paths = db.existingPaths()
        assertEquals(1, paths.size)
        assertEquals(12345L, paths["/music/1.mp3"])
    }

    @Test
    fun `搜索命中歌名歌手专辑`() {
        db.upsertAll(listOf(
            track("1", "晴天", "周杰伦", "叶惠美"),
            track("2", "稻香", "周杰伦", "魔杰座"),
            track("3", "Imagine", "John", "Imagine"),
        ))
        assertEquals(2, db.search("周杰伦").size)
        assertEquals(1, db.search("叶惠美").size)
        assertEquals(1, db.search("imag").size) // 大小写不敏感
        assertTrue(db.search("不存在").isEmpty())
    }

    @Test
    fun `专辑与歌手聚合去重`() {
        db.upsertAll(listOf(
            track("1", "歌1", "周杰伦", "叶惠美"),
            track("2", "歌2", "周杰伦", "叶惠美"),
            track("3", "歌3", "林俊杰", "第二天堂"),
        ))
        assertEquals(2, db.distinctAlbums().size)
        assertEquals(2, db.distinctArtists().size)
        val album = db.distinctAlbums().first { it.name == "叶惠美" }
        assertEquals(2, album.count)
    }

    @Test
    fun `按来源删除不影响其他来源`() {
        db.upsertAll(listOf(
            track("1", "本地", "A", "X").copy(source = "local"),
            track("2", "网盘", "B", "Y").copy(source = "webdav"),
        ))
        db.deleteBySource("webdav")
        val all = db.allTracks()
        assertEquals(1, all.size)
        assertEquals("本地", all[0].title)
    }
}
