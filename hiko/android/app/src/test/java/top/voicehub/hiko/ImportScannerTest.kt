package top.voicehub.hiko

import java.io.ByteArrayInputStream
import java.nio.charset.Charset
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ImportScannerTest {

    @Test
    fun readsLyricTextWithinLimit() {
        val lrc = "[00:01.00]ささやき\n[00:05.50]おやすみ\n"
        val text = ImportScanner.readLyricText(
            ByteArrayInputStream(lrc.toByteArray(Charsets.UTF_8)),
            lrc.toByteArray(Charsets.UTF_8).size.toLong(),
        )
        assertEquals(lrc, text)
    }

    @Test
    fun skipsLyricTextOver64KbLimit() {
        val big = ByteArray((ImportScanner.LYRIC_MAX_BYTES + 1).toInt()) { 'a'.code.toByte() }
        // length 超限:直接跳过
        assertNull(ImportScanner.readLyricText(ByteArrayInputStream(big), big.size.toLong()))
        // length 不可信时按实际字节数兜底
        assertNull(ImportScanner.readLyricText(ByteArrayInputStream(big), 0L))
    }

    @Test
    fun decodesShiftJisAndUtf8BomLyrics() {
        // Shift-JIS 歌词(非法 UTF-8 字节)→ 按 CJK 评分还原
        val sjisBytes = "[00:01.00]放課後の耳かき".toByteArray(Charset.forName("Shift_JIS"))
        assertEquals(
            "[00:01.00]放課後の耳かき",
            ImportScanner.decodeLyricText(sjisBytes),
        )
        // UTF-8 BOM 头剥离
        val bom = byteArrayOf(0xEF.toByte(), 0xBB.toByte(), 0xBF.toByte()) +
            "[00:01.00]test".toByteArray(Charsets.UTF_8)
        assertEquals("[00:01.00]test", ImportScanner.decodeLyricText(bom))
    }

    @Test
    fun repairsShiftJisKatakanaMojibake() {
        // Shift-JIS 片假名（首字节 0x83）被按 ISO-8859-1 解码 → C1 控制字符乱码。
        // 旧触发范围 0xA0..0xFF 漏掉 0x81-0x9F 首字节，对齐 Dart 版 0x80..0xFF 后才能还原。
        val original = "ササヤキボイス"
        val mojibake = String(original.toByteArray(Charset.forName("Shift_JIS")), Charsets.ISO_8859_1)
        assertEquals(original, ImportScanner.repairText(mojibake))
    }

    @Test
    fun repairsShiftJisKanjiKanaMojibake() {
        // 汉字+假名混合（首字节 0x82/0x88 区间）同样要能还原
        val original = "囁き耳かき"
        val mojibake = String(original.toByteArray(Charset.forName("Shift_JIS")), Charsets.ISO_8859_1)
        assertEquals(original, ImportScanner.repairText(mojibake))
    }

    @Test
    fun keepsNormalLatinTextUnchanged() {
        // 合法重音 Latin 文本（无 CJK 证据）不得被改写
        assertEquals("Café Crème", ImportScanner.repairText("Café Crème"))
    }

    @Test
    fun albumMetaFromFirstTaggedTrack() {
        // 乱序传入（track 2 在前），排序后第 1 首（TRCK=1）的标签决定专辑元数据
        val f1 = ImportScanner.FileMeta("content://x/01.mp3", "01.mp3", "content://x", "RJ111111_作品甲",
            "第1首", "艺人A", "作品甲", "社团甲", 1, 100.0, null)
        val f2 = ImportScanner.FileMeta("content://x/02.mp3", "02.mp3", "content://x", "RJ111111_作品甲",
            "第2首", "艺人B", "作品甲", "社团乙", 2, 100.0, null)
        // decideAlbumMeta 约定输入已按 TRCK 排序（buildAlbumFromFiles 排序后调用）
        val d = ImportScanner.decideAlbumMeta(listOf(f1, f2), isTagGroup = true)
        assertEquals("作品甲", d.title)
        assertEquals("社团甲", d.albumArtist)
        assertEquals("社团甲", d.artist)
        assertEquals(true, d.titleFromTags)
    }

    @Test
    fun albumMetaFallsBackToFolderTitleWithFlag() {
        // 全轨无 ALBUM 标签 → 标题回退文件夹名（剥 RJ 前缀失败保留原名），titleFromTags=false
        val f = ImportScanner.FileMeta("content://x/01.mp3", "01.mp3", "content://x", "RJ222222",
            null, null, null, null, null, 100.0, null)
        val d = ImportScanner.decideAlbumMeta(listOf(f), isTagGroup = false)
        assertEquals("RJ222222", d.title)
        assertEquals("本地导入", d.artist)
        assertEquals("", d.albumArtist)
        assertEquals(false, d.titleFromTags)
    }

    @Test
    fun albumMetaRjPrefixFolderNameCleaned() {
        // 文件夹名带 RJ 前缀作品名 → 回退标题剥离前缀
        val f = ImportScanner.FileMeta("content://x/01.mp3", "01.mp3", "content://x", "RJ333333_雨夜耳语",
            null, null, null, null, null, 100.0, null)
        val d = ImportScanner.decideAlbumMeta(listOf(f), isTagGroup = false)
        assertEquals("雨夜耳语", d.title)
    }

    @Test
    fun sampleSizeForDownsampling() {
        // 超大图降采样：长边压到 ≤maxDim×2 的最小 2 的幂
        assertEquals(1, ImportScanner.sampleSizeFor(4000, 3000, 2048))
        assertEquals(2, ImportScanner.sampleSizeFor(8000, 6000, 2048))
        assertEquals(4, ImportScanner.sampleSizeFor(16000, 12000, 2048))
        assertEquals(1, ImportScanner.sampleSizeFor(600, 600, 2048))
    }

    @Test
    fun lyricExtensionDetection() {
        assertEquals(true, ImportScanner.isLyric("01.lrc"))
        assertEquals(true, ImportScanner.isLyric("02.VTT"))
        assertEquals(true, ImportScanner.isLyric("03.srt"))
        assertEquals(false, ImportScanner.isLyric("04.mp3"))
        assertEquals(false, ImportScanner.isLyric(null))
    }
}
