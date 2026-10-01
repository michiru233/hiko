package top.voicehub.hiko

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** ScanCache.Entry.isFresh 契约（1.99.11）：命中/失效语义是增量扫描正确性的根。 */
class ScanCacheTest {

    private fun entry(mtime: Long = 1000L, size: Long = 42L) =
        ScanCache.Entry(
            lastModified = mtime, size = size, fileName = "01.mp3",
            dirUri = "content://dir", dirName = "RJ1", title = "t", artist = "a",
            album = null, albumArtist = null, trackNumber = 1, duration = 3.0,
        )

    @Test
    fun `mtime 与 size 全等则命中`() {
        assertTrue(entry().isFresh(1000L, 42L))
    }

    @Test
    fun `mtime 变化则失效`() {
        assertFalse(entry().isFresh(2000L, 42L))
    }

    @Test
    fun `size 变化则失效（同名文件被替换检出）`() {
        assertFalse(entry().isFresh(1000L, 43L))
    }

    @Test
    fun `当前文件 mtime 取不到则视为变化`() {
        assertFalse(entry().isFresh(0L, 42L))
    }

    @Test
    fun `缓存里 mtime 为 0 则永不命中`() {
        assertFalse(entry(mtime = 0L).isFresh(0L, 42L))
        assertFalse(entry(mtime = 0L).isFresh(1000L, 42L))
    }
}
