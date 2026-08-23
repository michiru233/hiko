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
    fun lyricExtensionDetection() {
        assertEquals(true, ImportScanner.isLyric("01.lrc"))
        assertEquals(true, ImportScanner.isLyric("02.VTT"))
        assertEquals(true, ImportScanner.isLyric("03.srt"))
        assertEquals(false, ImportScanner.isLyric("04.mp3"))
        assertEquals(false, ImportScanner.isLyric(null))
    }
}
