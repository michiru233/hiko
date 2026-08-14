package top.voicehub.hiko

import java.io.ByteArrayInputStream
import java.nio.charset.Charset
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class Id3v2ParserTest {
    @Test
    fun parsesUtf8V24Frames() {
        val tag = tag(4, listOf(frame(4, "TIT2", text(3, "放課後の耳かき", Charsets.UTF_8)), frame(4, "TRCK", text(3, "03/12", Charsets.UTF_8))))
        val metadata = Id3v2Parser.parse(ByteArrayInputStream(tag))!!
        assertEquals("放課後の耳かき", metadata.title)
        assertEquals(3, metadata.trackNumber)
    }

    @Test
    fun parsesUtf16V23Frame() {
        val tag = tag(3, listOf(frame(3, "TALB", text(1, "雨夜耳語", Charset.forName("UTF-16")))))
        assertEquals("雨夜耳語", Id3v2Parser.parse(ByteArrayInputStream(tag))!!.album)
    }

    @Test
    fun repairsLegacyChineseJapaneseAndEucJpBytes() {
        val cases = listOf(
            "雨夜耳语" to Charset.forName("GB18030"),
            "放課後の耳かき" to Charset.forName("windows-31j"),
            "ぐらまらす工房" to Charset.forName("EUC-JP")
        )
        for ((expected, charset) in cases) {
            val tag = tag(3, listOf(frame(3, "TIT2", byteArrayOf(0) + expected.toByteArray(charset))))
            assertEquals("failed charset ${charset.name()}", expected, Id3v2Parser.parse(ByteArrayInputStream(tag))?.title)
        }
    }

    @Test
    fun preservesValidLatin1() {
        val tag = tag(3, listOf(frame(3, "TPE1", text(0, "Café Noir", Charsets.ISO_8859_1))))
        assertEquals("Café Noir", Id3v2Parser.parse(ByteArrayInputStream(tag))!!.artist)
    }

    @Test
    fun rejectsTruncatedAndOversizedTags() {
        assertNull(Id3v2Parser.parse(ByteArrayInputStream("ID3".toByteArray())))
        val header = byteArrayOf(73, 68, 51, 3, 0, 0, 0x02, 0, 0, 0)
        assertNull(Id3v2Parser.parse(ByteArrayInputStream(header)))
    }

    @Test
    fun keepsAmbiguousPureHanForSystemFallback() {
        val bytes = byteArrayOf(0, 0x93.toByte(), 0xfa.toByte(), 0x96.toByte(), 0x7b)
        val tag = tag(3, listOf(frame(3, "TIT2", bytes)))
        assertNull(Id3v2Parser.parse(ByteArrayInputStream(tag)))
    }

    @Test
    fun rejectsHangulAsUnsupportedLegacyMetadata() {
        assertTrue(Id3v2Parser.isUsableText("정상적으로 선언된 UTF-8"))
        val cp949 = "잘못된 제목".toByteArray(Charset.forName("CP949"))
        val tag = tag(3, listOf(frame(3, "TIT2", byteArrayOf(0) + cp949)))
        assertTrue(Id3v2Parser.parse(ByteArrayInputStream(tag)) == null || Id3v2Parser.parse(ByteArrayInputStream(tag))!!.title != "잘못된 제목")
    }

    @Test
    fun identifiesIrrecoverableQuestionAndReplacementText() {
        assertFalse(Id3v2Parser.isUsableText("Track1 ??????"))
        assertFalse(Id3v2Parser.isUsableText("曲名�"))
        assertTrue(Id3v2Parser.isUsableText("What?"))
        assertTrue(Id3v2Parser.isUsableText("正常なタイトル"))
    }

    private fun text(encoding: Int, value: String, charset: Charset): ByteArray =
        byteArrayOf(encoding.toByte()) + value.toByteArray(charset)

    private fun tag(version: Int, frames: List<ByteArray>): ByteArray {
        val body = frames.fold(ByteArray(0)) { result, frame -> result + frame }
        return "ID3".toByteArray() + byteArrayOf(version.toByte(), 0, 0) + syncSafe(body.size) + body
    }

    private fun frame(version: Int, id: String, body: ByteArray): ByteArray {
        val size = if (version == 4) syncSafe(body.size) else byteArrayOf(0, 0, 0, body.size.toByte())
        return id.toByteArray() + size + byteArrayOf(0, 0) + body
    }

    private fun syncSafe(value: Int): ByteArray = byteArrayOf(
        ((value shr 21) and 0x7f).toByte(),
        ((value shr 14) and 0x7f).toByte(),
        ((value shr 7) and 0x7f).toByte(),
        (value and 0x7f).toByte()
    )
}
