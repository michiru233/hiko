package top.voicehub.hiko

import java.io.InputStream
import java.nio.ByteBuffer
import java.nio.charset.CharacterCodingException
import java.nio.charset.Charset
import java.nio.charset.CodingErrorAction

/** Small, bounded ID3v2 reader used before MediaMetadataRetriever loses malformed legacy bytes. */
object Id3v2Parser {
    private const val HEADER_SIZE = 10
    private const val MAX_TAG_SIZE = 4 * 1024 * 1024

    data class Metadata(
        val title: String? = null,
        val artist: String? = null,
        val album: String? = null,
        val albumArtist: String? = null,
        val trackNumber: Int? = null
    ) {
        fun isEmpty(): Boolean =
            title == null && artist == null && album == null && albumArtist == null && trackNumber == null
    }

    fun parse(input: InputStream): Metadata? {
        val header = ByteArray(HEADER_SIZE)
        if (!input.readFully(header) || !header.copyOfRange(0, 3).contentEquals("ID3".toByteArray())) return null
        val major = header[3].toInt() and 0xff
        if (major !in 2..4) return null
        val size = syncSafeInt(header, 6) ?: return null
        if (size <= 0 || size > MAX_TAG_SIZE) return null
        val payload = ByteArray(size)
        if (!input.readFully(payload)) return null
        return parsePayload(major, header[5].toInt() and 0xff, payload)
    }

    private fun parsePayload(major: Int, tagFlags: Int, source: ByteArray): Metadata? {
        val tagUnsynchronised = tagFlags and 0x80 != 0
        var offset = extendedHeaderSize(major, tagFlags, source) ?: return null
        var result = Metadata()

        while (offset < source.size) {
            val headerSize = if (major == 2) 6 else 10
            if (offset + headerSize > source.size || source[offset] == 0.toByte()) break
            val idLength = if (major == 2) 3 else 4
            val id = source.copyOfRange(offset, offset + idLength).toString(Charsets.ISO_8859_1)
            if (!id.all { it in 'A'..'Z' || it in '0'..'9' }) break
            val frameSize = when (major) {
                2 -> unsignedInt(source, offset + 3, 3)
                4 -> syncSafeInt(source, offset + 4)
                else -> unsignedInt(source, offset + 4, 4)
            } ?: break
            if (frameSize <= 0 || frameSize > source.size - offset - headerSize) break

            val frameFlags = if (major == 2) 0 else unsignedInt(source, offset + 8, 2) ?: 0
            var body = source.copyOfRange(offset + headerSize, offset + headerSize + frameSize)
            val frameUnsynchronised = major == 4 && frameFlags and 0x0002 != 0
            if (tagUnsynchronised || frameUnsynchronised) body = removeUnsynchronisation(body)

            val value = decodeTextFrame(body)
            result = when (id) {
                "TT2", "TIT2" -> result.copy(title = result.title ?: value)
                "TP1", "TPE1" -> result.copy(artist = result.artist ?: value)
                "TAL", "TALB" -> result.copy(album = result.album ?: value)
                "TP2", "TPE2" -> result.copy(albumArtist = result.albumArtist ?: value)
                "TRK", "TRCK" -> result.copy(trackNumber = result.trackNumber ?: parseTrackNumber(value))
                else -> result
            }
            offset += headerSize + frameSize
        }
        return result.takeUnless { it.isEmpty() }
    }

    private fun extendedHeaderSize(major: Int, flags: Int, data: ByteArray): Int? {
        if (flags and 0x40 == 0) return 0
        if (major == 2 || data.size < 4) return null
        val declared = if (major == 4) syncSafeInt(data, 0) else unsignedInt(data, 0, 4)
        declared ?: return null
        val total = if (major == 3) declared + 4 else declared
        return total.takeIf { it in 4..data.size }
    }

    private fun decodeTextFrame(body: ByteArray): String? {
        if (body.size < 2) return null
        val encoding = body[0].toInt() and 0xff
        val bytes = trimTerminator(body.copyOfRange(1, body.size), encoding)
        if (bytes.isEmpty()) return null
        val decoded = when (encoding) {
            0 -> decodeLegacy(bytes)
            1 -> decodeStrict(bytes, Charset.forName("UTF-16"))
            2 -> decodeStrict(bytes, Charset.forName("UTF-16BE"))
            3 -> decodeStrict(bytes, Charsets.UTF_8)
            else -> null
        }
        return decoded?.trim()?.takeIf { it.isNotEmpty() && isUsableText(it) }
    }

    private data class LegacyCandidate(
        val charset: Charset,
        val value: String,
        val score: Int,
    )

    private fun decodeLegacy(bytes: ByteArray): String? {
        val candidates = listOf("ISO-8859-1", "GB18030", "windows-31j", "EUC-JP")
            .mapNotNull { name -> legacyCandidate(bytes, Charset.forName(name)) }
            .distinctBy { it.value }
            .sortedByDescending { it.score }
        val best = candidates.firstOrNull() ?: return null
        val runnerUp = candidates.getOrNull(1)
        return best.value.takeIf { runnerUp == null || best.score - runnerUp.score >= 2 || best.charset.name() == "GB18030" }
    }

    private fun legacyCandidate(bytes: ByteArray, charset: Charset): LegacyCandidate? {
        val value = decodeStrict(bytes, charset)?.trim()?.takeIf { it.isNotEmpty() } ?: return null
        if (!isUsableText(value) || value.any { it.code in 0xac00..0xd7af }) return null
        if (!value.toByteArray(charset).contentEquals(bytes)) return null
        val kana = value.count { it.code in 0x3040..0x30ff }
        val han = value.count { it.code in 0x4e00..0x9fff }
        val accentedLatin = value.count { it.code in 0x00a0..0x024f }
        val expansionPenalty = (value.length - bytes.size / 2).coerceAtLeast(0) * 2
        val charsetEvidence = when (charset.name()) {
            "ISO-8859-1" -> if (accentedLatin > 0 && kana == 0 && han == 0) 6 else 0
            "windows-31j" -> if (kana > 0) 10 else if (han > 0) 3 else 0
            "EUC-JP" -> if (kana > 0) 30 else if (han > 0) 2 else 0
            "GB18030" -> if (han > 0 && kana == 0) 2 else 0
            else -> 0
        }
        return LegacyCandidate(charset, value, textScore(value) - expansionPenalty + charsetEvidence)
    }

    private fun decodeStrict(bytes: ByteArray, charset: Charset): String? = try {
        charset.newDecoder()
            .onMalformedInput(CodingErrorAction.REPORT)
            .onUnmappableCharacter(CodingErrorAction.REPORT)
            .decode(ByteBuffer.wrap(bytes))
            .toString()
    } catch (_: CharacterCodingException) {
        null
    }

    private fun textScore(value: String): Int = value.sumOf { ch ->
        when (ch.code) {
            0xfffd -> -100
            in 0x00..0x08, in 0x0e..0x1f, in 0x7f..0x9f -> -20
            in 0x3040..0x30ff -> 8
            in 0xff61..0xff9f -> -2
            in 0x4e00..0x9fff -> 5
            in 0x3000..0x303f -> 3
            else -> if (ch.isLetterOrDigit() || ch.isWhitespace() || ch.isDefined()) 1 else 0
        }
    }

    fun isUsableText(value: String?): Boolean {
        if (value.isNullOrBlank()) return false
        if ('\ufffd' in value || value.any { it.code in 0x00..0x08 || it.code in 0x0e..0x1f || it.code in 0x7f..0x9f }) return false
        val questionCount = value.count { it == '?' || it == '？' }
        if (questionCount >= 2 && (questionCount * 3 >= value.length || "??" in value || "？？" in value)) return false
        return true
    }

    private fun parseTrackNumber(value: String?): Int? =
        value?.substringBefore('/')?.trim()?.toIntOrNull()?.takeIf { it > 0 }

    private fun trimTerminator(bytes: ByteArray, encoding: Int): ByteArray {
        var end = bytes.size
        if (encoding == 1 || encoding == 2) {
            while (end >= 2 && bytes[end - 1] == 0.toByte() && bytes[end - 2] == 0.toByte()) end -= 2
        } else {
            while (end > 0 && bytes[end - 1] == 0.toByte()) end--
        }
        return bytes.copyOf(end)
    }

    private fun removeUnsynchronisation(bytes: ByteArray): ByteArray {
        val out = ArrayList<Byte>(bytes.size)
        var index = 0
        while (index < bytes.size) {
            out.add(bytes[index])
            if (bytes[index] == 0xff.toByte() && index + 1 < bytes.size && bytes[index + 1] == 0.toByte()) index++
            index++
        }
        return out.toByteArray()
    }

    private fun syncSafeInt(bytes: ByteArray, offset: Int): Int? {
        if (offset + 4 > bytes.size) return null
        var value = 0
        repeat(4) { index ->
            val byte = bytes[offset + index].toInt() and 0xff
            if (byte and 0x80 != 0) return null
            value = (value shl 7) or byte
        }
        return value
    }

    private fun unsignedInt(bytes: ByteArray, offset: Int, length: Int): Int? {
        if (offset + length > bytes.size) return null
        var value = 0L
        repeat(length) { index -> value = (value shl 8) or (bytes[offset + index].toLong() and 0xff) }
        return value.takeIf { it <= Int.MAX_VALUE }?.toInt()
    }

    private fun InputStream.readFully(target: ByteArray): Boolean {
        var offset = 0
        while (offset < target.size) {
            val count = read(target, offset, target.size - offset)
            if (count < 0) return false
            offset += count
        }
        return true
    }
}
