package top.voicehub.hiko

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.nio.charset.Charset
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ImportScannerTest {

    @Test
    fun parsesTagOverLegacy4MbLimit() {
        // 1.54 回归：真实 DLsite 音频内嵌 2240px PNG 使 ID3 标签达 4.4MB，
        // 旧 MAX_TAG_SIZE=4MB 直接整标签拒解析 → 退到 MMR 兜底乱码。
        // 合成 4.4MB 标签（UTF-16 文本帧 + 大 APIC 占位）必须完整解析。
        val big = ImportScannerTestIds3v2.buildOversizeTag(overshootBytes = 300 * 1024)
        val meta = Id3v2Parser.parse(big.inputStream())
        assertNotNull(meta)
        assertEquals("雨夜耳語", meta!!.title)
        assertEquals("音波彼女", meta.artist)
        assertEquals("はちみつ社", meta.albumArtist)
        assertEquals(3, meta.trackNumber)
        // 默认不提取封面（并行解析零拷贝）
        assertNull("默认不提取封面（并行解析零拷贝）", meta.picture)
    }

    @Test
    fun extractsPictureFromApicWhenRequested() {
        // 1.54.1 回归：MMR.embeddedPicture 对 4.4MB 大标签返回 null（RJ01650240 实锤），
        // 封面必须走自研 APIC 解析（与桌面同源）；覆盖 enc=0 单字节 desc 与 UTF-16 双字节 desc。
        val png = byteArrayOf(0x89.toByte(), 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3)

        val latin = ImportScannerTestIds3v2.buildTagWithApic(png, utf16Desc = false)
        val m1 = Id3v2Parser.parse(latin.inputStream(), extractPicture = true)
        assertNotNull(m1)
        assertEquals("雨夜耳語", m1!!.title)
        assertTrue(m1.picture!!.contentEquals(png))

        val utf16 = ImportScannerTestIds3v2.buildTagWithApic(png, utf16Desc = true)
        val m2 = Id3v2Parser.parse(utf16.inputStream(), extractPicture = true)
        assertNotNull(m2)
        assertTrue(m2!!.picture!!.contentEquals(png))
    }

    @Test
    fun rejectsAbsurdTagSize() {
        // 声明 >16MB 的畸形标签仍拒解析（内存天花板）
        val header = byteArrayOf(
            0x49, 0x44, 0x33, 0x03, 0x00, 0x00,
            // syncsafe 20MB: 0,0x60,0,0
            0x00, 0x60, 0x00, 0x00,
        )
        assertNull(Id3v2Parser.parse(header.inputStream()))
    }

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
        // 1.43 对齐桌面：artist 取第一轨 TPE1（声优），不再是 TPE2（社团）
        assertEquals("艺人A", d.artist)
        assertEquals(true, d.titleFromTags)
    }

    @Test
    fun albumMetaArtistFallsBackToAnyTrackTag() {
        // 第一轨无任何艺术家标签 → 取任何轨的第一个有效 TPE1/TPE2
        val f1 = ImportScanner.FileMeta("content://x/01.mp3", "01.mp3", "content://x", "RJ111111_作品甲",
            "第1首", null, "作品甲", null, 1, 100.0, null)
        val f2 = ImportScanner.FileMeta("content://x/02.mp3", "02.mp3", "content://x", "RJ111111_作品甲",
            "第2首", "艺人B", "作品甲", "社团乙", 2, 100.0, null)
        val d = ImportScanner.decideAlbumMeta(listOf(f1, f2), isTagGroup = true)
        assertEquals("艺人B", d.artist)
        assertEquals("社团乙", d.albumArtist)
    }

    @Test
    fun albumMetaArtistTrailingSpaceTrimmed() {
        // 尾随空格的艺术家标签必须规范化，否则「同名艺术家」排序时被拆开
        val f = ImportScanner.FileMeta("content://x/01.mp3", "01.mp3", "content://x", "RJ111111_作品甲",
            "第1首", "艺人A ", "作品甲", "社团甲 ", 1, 100.0, null)
        val d = ImportScanner.decideAlbumMeta(listOf(f), isTagGroup = true)
        assertEquals("艺人A", d.artist)
        assertEquals("社团甲", d.albumArtist)
    }

    @Test
    fun albumMetaTitleMultilineSanitized() {
        // DLsite 的 TALB 标签常写入带换行的冗长文本 → 取首个非空行
        val f = ImportScanner.FileMeta("content://x/01.mp3", "01.mp3", "content://x", "RJ111111_作品甲",
            "第1首", "艺人A", "作品甲\n作品甲（2）\n", "社团甲", 1, 100.0, null)
        val d = ImportScanner.decideAlbumMeta(listOf(f), isTagGroup = true)
        assertEquals("作品甲", d.title)
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

/** 合成 ID3v2.3 字节流的测试夹具 */
private object ImportScannerTestIds3v2 {
    /** 生成 v2.3 标签：TIT2 + APIC（png 字节；desc 按 utf16Desc 选单/双字节 null 结尾） */
    fun buildTagWithApic(png: ByteArray, utf16Desc: Boolean): ByteArray {
        val frames = ByteArrayOutputStream()
        fun frame(id: String, body: ByteArray) {
            frames.write(id.toByteArray(Charsets.ISO_8859_1))
            val size = body.size
            frames.write(byteArrayOf(
                (size ushr 24).toByte(), (size ushr 16).toByte(),
                (size ushr 8).toByte(), size.toByte(),
            ))
            frames.write(byteArrayOf(0, 0))
            frames.write(body)
        }
        val titleRaw = "雨夜耳語".toByteArray(Charsets.UTF_16LE)
        val title = byteArrayOf(1, 0xFF.toByte(), 0xFE.toByte()) + titleRaw
        frame("TIT2", title)
        val apic = ByteArrayOutputStream()
        // enc 决定 desc 编码:utf16Desc=true → enc=1(UTF-16,desc 以双字节 \0 结尾)
        apic.write(if (utf16Desc) 1 else 0)
        apic.write("image/png".toByteArray(Charsets.ISO_8859_1))
        apic.write(0)
        apic.write(3) // picture type: front cover
        if (utf16Desc) {
            apic.write(byteArrayOf(0, 0)) // 空 desc 的 UTF-16 双字节 null
        } else {
            apic.write(0) // 空 desc 单字节 null
        }
        apic.write(png)
        frame("APIC", apic.toByteArray())

        val payload = frames.toByteArray()
        val out = ByteArrayOutputStream()
        out.write(byteArrayOf(0x49, 0x44, 0x33, 0x03, 0x00, 0x00))
        val size = payload.size
        out.write(byteArrayOf(
            ((size ushr 21) and 0x7f).toByte(),
            ((size ushr 14) and 0x7f).toByte(),
            ((size ushr 7) and 0x7f).toByte(),
            (size and 0x7f).toByte(),
        ))
        out.write(payload)
        return out.toByteArray()
    }

    /** 生成总大小 >4MB 的标签：TIT2/TPE1/TPE2/TRCK + 占位 APIC（垃圾字节撑体积） */
    fun buildOversizeTag(overshootBytes: Int): ByteArray {        val frames = ByteArrayOutputStream()

        fun frame(id: String, body: ByteArray) {
            frames.write(id.toByteArray(Charsets.ISO_8859_1))
            val size = body.size
            frames.write(byteArrayOf(
                (size ushr 24).toByte(), (size ushr 16).toByte(),
                (size ushr 8).toByte(), size.toByte(),
            ))
            frames.write(byteArrayOf(0, 0)) // flags
            frames.write(body)
        }

        fun utf16(text: String): ByteArray {
            val raw = text.toByteArray(Charsets.UTF_16LE)
            val out = ByteArray(raw.size + 3)
            out[0] = 1 // encoding UTF-16 w/ BOM
            out[1] = 0xFF.toByte(); out[2] = 0xFE.toByte()
            raw.copyInto(out, 3)
            return out
        }

        frame("TIT2", utf16("雨夜耳語"))
        frame("TPE1", utf16("音波彼女"))
        frame("TPE2", utf16("はちみつ社"))
        frame("TRCK", byteArrayOf(0) + "3".toByteArray(Charsets.ISO_8859_1))
        // APIC：encoding 0 + mime "image/png" + type + desc + 大块垃圾字节
        val filler = ByteArray(4 * 1024 * 1024 + overshootBytes) { (it % 251).toByte() }
        val apic = ByteArray(11) { 0 } // enc + "image/png\0"
        apic[10] = 3 // picture type
        frame("APIC", apic + filler)

        val payload = frames.toByteArray()
        val out = ByteArrayOutputStream()
        out.write(byteArrayOf(0x49, 0x44, 0x33, 0x03, 0x00, 0x00))
        // syncsafe int
        val size = payload.size
        out.write(byteArrayOf(
            ((size ushr 21) and 0x7f).toByte(),
            ((size ushr 14) and 0x7f).toByte(),
            ((size ushr 7) and 0x7f).toByte(),
            (size and 0x7f).toByte(),
        ))
        out.write(payload)
        return out.toByteArray()
    }
}
