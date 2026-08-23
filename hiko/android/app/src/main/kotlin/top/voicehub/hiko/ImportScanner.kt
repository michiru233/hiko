package top.voicehub.hiko

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.util.Base64
import androidx.documentfile.provider.DocumentFile
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.nio.charset.Charset
import java.security.MessageDigest
import java.util.concurrent.Executors

/**
 * 导入扫描：行为对齐 desktop main.js 的 findFiles / groupFilesByFolder / scanAlbum / scanFolder。
 * 差异：文件访问用 SAF（content:// + DocumentFile），元数据用 MediaMetadataRetriever。
 */
object ImportScanner {

    private val AUDIO_EXTS = setOf("mp3", "m4a", "wav", "flac", "ogg", "aac", "opus", "webm")
    private val IMAGE_EXTS = setOf("jpg", "jpeg", "png", "webp", "gif")
    private val LYRIC_EXTS = setOf("lrc", "vtt", "srt")
    private val RJ_REGEX = Regex("RJ\\d{5,}", RegexOption.IGNORE_CASE)
    // DLsite 下载目录命名约定：RJxxxxxx_作品名（RJ 前缀可能带 _ - 空格）
    private val RJ_TITLE_REGEX = Regex("""^RJ\d{5,}[_\- ]+(.+)$""", RegexOption.IGNORE_CASE)

    /** 单曲歌词文本上限:64KB,超限直接跳过(防巨型文件拖垮导入) */
    const val LYRIC_MAX_BYTES = 64L * 1024

    fun isAudio(name: String?): Boolean = name?.substringAfterLast('.', "")?.lowercase() in AUDIO_EXTS
    fun isImage(name: String?): Boolean = name?.substringAfterLast('.', "")?.lowercase() in IMAGE_EXTS
    fun isLyric(name: String?): Boolean = name?.substringAfterLast('.', "")?.lowercase() in LYRIC_EXTS

    /** 与桌面 stableId 同源：sha1(path) 前 16 位十六进制 */
    fun stableId(value: String): String {
        val md = MessageDigest.getInstance("SHA-1").digest(value.toByteArray())
        return md.joinToString("") { "%02x".format(it) }.substring(0, 16)
    }

    /** 从多个候选中提取第一个 RJ 号（对应桌面 extractRjCode，检查路径全层级） */
    fun extractRjCode(vararg values: String?): String? {
        for (v in values) {
            RJ_REGEX.find(v.orEmpty())?.let { return it.value.uppercase() }
        }
        return null
    }

    /** 与桌面 mostCommon 同语义：取出现最多的值，平局取最先出现者 */
    fun mostCommon(values: List<String?>): String? {
        val counts = LinkedHashMap<String, Int>()
        var best: String? = null
        var bestCount = 0
        for (v in values) {
            if (v.isNullOrBlank()) continue
            val c = (counts[v] ?: 0) + 1
            counts[v] = c
            if (c > bestCount) { best = v; bestCount = c }
        }
        return best
    }

    /** 自然排序（数字感知），对应桌面 localeCompare(..., {numeric:true}) */
    fun naturalCompare(a: String, b: String): Int {
        var i = 0
        var j = 0
        while (i < a.length && j < b.length) {
            val ca = a[i]
            val cb = b[j]
            if (ca.isDigit() && cb.isDigit()) {
                var ni = i
                while (ni < a.length && a[ni].isDigit()) ni++
                var nj = j
                while (nj < b.length && b[nj].isDigit()) nj++
                val na = a.substring(i, ni).trimStart('0').ifEmpty { "0" }.toLongOrNull() ?: 0
                val nb = b.substring(j, nj).trimStart('0').ifEmpty { "0" }.toLongOrNull() ?: 0
                if (na != nb) return na.compareTo(nb)
                i = ni
                j = nj
            } else {
                val cmp = ca.lowercaseChar().compareTo(cb.lowercaseChar())
                if (cmp != 0) return cmp
                i++
                j++
            }
        }
        return a.length - b.length
    }

    /** 根树下所有「直接包含文件」的目录 → 该目录的直接文件（跳过 . 开头） */
    fun groupByFolder(root: DocumentFile): Map<DocumentFile, List<DocumentFile>> {
        val groups = LinkedHashMap<DocumentFile, MutableList<DocumentFile>>()
        fun walk(dir: DocumentFile) {
            val files = mutableListOf<DocumentFile>()
            for (f in dir.listFiles()) {
                if (f.name?.startsWith(".") == true) continue
                if (f.isDirectory) walk(f)
                else if (f.isFile) files.add(f)
            }
            if (files.isNotEmpty()) groups[dir] = files
        }
        walk(root)
        return groups
    }

    /** Android 封面策略：缩放到 ≤600px 转 JPEG，上限 500KB。
     *  超限时逐级降质（82→70→60→50）再降尺寸（600→400→300）重试，避免封面丢失；
     *  整链 try-catch（含 OOM）——单张封面失败绝不影响专辑导入。 */
    fun coverDataUrl(bytes: ByteArray): String? {
        return try {
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
            if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null

            val qualities = intArrayOf(82, 70, 60, 50)
            val maxSizes = intArrayOf(600, 400, 300)
            for (max in maxSizes) {
                var sample = 1
                while (bounds.outWidth / sample > max * 2 || bounds.outHeight / sample > max * 2) {
                    sample *= 2
                }
                val decodeOpts = BitmapFactory.Options().apply { inSampleSize = sample }
                val bmp = BitmapFactory.decodeByteArray(bytes, 0, bytes.size, decodeOpts) ?: return null
                val w = bmp.width
                val h = bmp.height
                if (w == 0 || h == 0) return null

                val scale = if (maxOf(w, h) > max) max.toFloat() / maxOf(w, h) else 1f
                var out = bmp
                if (scale < 1f) {
                    out = Bitmap.createScaledBitmap(
                        bmp,
                        (w * scale).toInt().coerceAtLeast(1),
                        (h * scale).toInt().coerceAtLeast(1),
                        true
                    )
                    if (out !== bmp) bmp.recycle()
                }
                for (quality in qualities) {
                    val stream = ByteArrayOutputStream()
                    if (out.compress(Bitmap.CompressFormat.JPEG, quality, stream)) {
                        val data = stream.toByteArray()
                        if (data.isNotEmpty() && data.size <= 500 * 1024) {
                            out.recycle()
                            return "data:image/jpeg;base64," + Base64.encodeToString(data, Base64.NO_WRAP)
                        }
                    }
                }
                out.recycle()
            }
            null
        } catch (e: Throwable) {
            // 解码/压缩异常（含 OOM）直接放弃封面，不影响专辑导入
            null
        }
    }

    /** 文本是否含 CJK 汉字/日文假名（视为正常文本，非乱码） */
    private fun hasCjkOrKana(s: String): Boolean =
        s.any { it.code in 0x4E00..0x9FFF || it.code in 0x3040..0x30FF || it.code in 0xFF61..0xFF9F }

    /** 修复 MediaMetadataRetriever 对非 UTF-8 ID3 标签的乱码：
     *  中文标签字节常被按 ISO-8859-1 解码成拉丁字符（你好 → ÄãºÃ），日文（Shift-JIS）同理。
     *  用 GB18030 / Shift_JIS 逐一还原并打分（假名 +3、汉字 +2、日文标点 +1），
     *  取分最高的结果；仅当得分 >0 才采纳，避免误伤正常 Latin-1 文本（如 Cafe）。 */
    fun repairText(s: String?): String? {
        if (s.isNullOrBlank()) return s
        if (hasCjkOrKana(s)) return s   // 已是正常中文/日文，无需修复
        if (!s.any { it.code in 0xA0..0xFF }) return s  // 无 Latin-1 扩展字符，非乱码特征
        val bytes = s.toByteArray(Charsets.ISO_8859_1)
        var best: String? = null
        var bestScore = 0
        for (name in listOf("GB18030", "Shift_JIS", "windows-31j", "EUC-JP")) {
            try {
                val candidate = String(bytes, Charset.forName(name))
                val score = candidate.sumOf { ch ->
                    when (ch.code) {
                        in 0x3040..0x30FF, in 0xFF61..0xFF9F -> 3  // 假名
                        in 0x4E00..0x9FFF -> 2                     // 汉字
                        in 0x3000..0x303F -> 1                     // 日文标点
                        else -> 0
                    }
                }
                if (score > bestScore) {
                    best = candidate
                    bestScore = score
                }
            } catch (_: Exception) { }
        }
        return if (bestScore > 0 && best != null) best else s
    }

    /** 字符串是否仍像乱码；合法重音 Latin 文本不能仅因含高位字符被拒绝。 */
    fun looksGarbled(s: String?): Boolean {
        if (s.isNullOrBlank()) return false
        if (!Id3v2Parser.isUsableText(s)) return true
        val mojibakeMarkers = listOf("Ã", "Â", "ã€", "ãƒ", "ã‚", "æ—", "å¤", "ï¿½")
        return mojibakeMarkers.any { it in s }
    }


    /** 文件夹名回退时清理：剥离 DLsite 的 "RJxxxxxx_" 前缀，只留作品名。
     *  例：RJ123456_雨夜耳语 → 雨夜耳语；无前缀则原样返回。 */
    fun cleanFolderTitle(name: String?): String? {
        if (name.isNullOrBlank()) return name
        val trimmed = name.trim()
        val match = RJ_TITLE_REGEX.find(trimmed)
        val clean = match?.groupValues?.get(1)?.trim()
        return if (!clean.isNullOrEmpty()) clean else name
    }

    private fun readBytes(context: Context, uri: Uri): ByteArray? {
        return try {
            val fd = context.contentResolver.openAssetFileDescriptor(uri, "r") ?: return null
            fd.use {
                if (it.length > 15 * 1024 * 1024) return null // 超大连封面直接跳过，避免内存峰值
                it.createInputStream().use { s -> s.readBytes() }
            }
        } catch (e: Exception) {
            null
        }
    }

    /** 提取单曲元数据；标签损坏/解析失败返回 null（对应桌面 try/catch 容忍） */
    private data class TrackMeta(
        val title: String?,
        val artist: String?,
        val album: String?,
        val albumArtist: String?,
        val durationMs: Long,
        val cover: String?
    )

    private fun readTrackMeta(context: Context, uri: Uri): TrackMeta? {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(context, uri)
            val durationMs = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
            val picture = retriever.embeddedPicture
            val rawId3 = if (uri.toString().lowercase().endsWith(".mp3")) {
                context.contentResolver.openInputStream(uri)?.use { Id3v2Parser.parse(it) }
            } else null
            TrackMeta(
                title = chooseMetadata(rawId3?.title, retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_TITLE)),
                artist = chooseMetadata(rawId3?.artist, retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ARTIST)),
                album = chooseMetadata(rawId3?.album, retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ALBUM)),
                albumArtist = chooseMetadata(rawId3?.albumArtist, retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ALBUMARTIST)),
                durationMs = durationMs,
                cover = picture?.let { coverDataUrl(it) }
            )
        } catch (e: Exception) {
            null
        } finally {
            retriever.release()
        }
    }

    /** 元数据经过 repairText 后仍不可用时交给文件名/文件夹回退逻辑。 */
    private fun usableMetadata(value: String?): String? =
        value?.trim()?.takeIf { Id3v2Parser.isUsableText(it) && !looksGarbled(it) }

    private fun chooseMetadata(raw: String?, system: String?): String? {
        val fallback = usableMetadata(repairText(system))
        val candidate = usableMetadata(raw)
        return candidate ?: fallback
    }

    /** 文件夹封面：优先 (cover|front|folder|album|封面) 命名的图片，否则第一张图 */
    private fun folderCover(context: Context, files: List<DocumentFile>): String? {
        val images = files.filter { isImage(it.name) }
        val pick = images.firstOrNull { Regex("cover|front|folder|album|封面", RegexOption.IGNORE_CASE).containsMatchIn(it.name.orEmpty()) }
            ?: images.firstOrNull()
            ?: return null
        val bytes = readBytes(context, pick.uri) ?: return null
        return coverDataUrl(bytes)
    }

    /** 扫描一张专辑（目录 + 其直接文件），无音频返回 null */
    fun scanAlbum(context: Context, albumDir: DocumentFile, files: List<DocumentFile>): JSONObject? {
        val audio = files
            .filter { isAudio(it.name) }
            .sortedWith(Comparator { a, b -> naturalCompare(a.name.orEmpty(), b.name.orEmpty()) })
        if (audio.isEmpty()) return null

        val albumNames = mutableListOf<String?>()
        val artists = mutableListOf<String?>()
        val albumArtists = mutableListOf<String?>()
        val tracks = JSONArray()
        var totalDuration = 0.0
        var embeddedCover: String? = null

        audio.forEachIndexed { index, file ->
            val meta = readTrackMeta(context, file.uri)
            if (meta != null) {
                albumNames.add(meta.album)
                artists.add(meta.artist)
                albumArtists.add(meta.albumArtist)
            }
            if (meta?.cover != null && embeddedCover == null) embeddedCover = meta.cover
            // 标题优先元数据（已做乱码还原），仍像乱码则回退文件名（文件名恒为正确 Unicode）
            val name = meta?.title?.takeIf { !looksGarbled(it) && it.isNotBlank() }
                ?: file.name?.substringBeforeLast('.')
                ?: "Track ${index + 1}"
            tracks.put(
                JSONObject()
                    .put("index", index)
                    .put("name", name)
                    .put("url", file.uri.toString())
                    .put("duration", if (meta != null) meta.durationMs / 1000.0 else 0)
                    .put("cover", meta?.cover)
            )
            totalDuration += if (meta != null) meta.durationMs / 1000.0 else 0.0
        }

        val albumPath = albumDir.uri.toString()
        // 专辑名优先元数据 ALBUM（已做乱码还原）；无 ALBUM 标签（DLsite 下载常见）时
        // 回退文件夹名并剥离 "RJxxxxxx_" 前缀，避免直接显示原始目录名
        val title = mostCommon(albumNames)?.takeIf { !looksGarbled(it) }
            ?: cleanFolderTitle(albumDir.name)
            ?: "本地导入"
        val artist = mostCommon(artists)?.takeIf { !looksGarbled(it) }
            ?: mostCommon(albumArtists)?.takeIf { !looksGarbled(it) }
            ?: "本地导入"
        val rjCode = extractRjCode(albumPath, albumDir.name, audio.firstOrNull()?.name)
        val localCover = embeddedCover ?: folderCover(context, files)

        return JSONObject()
            .put("id", "local-${stableId(albumPath)}")
            .put("sourcePath", albumPath)
            .put("title", title)
            .put("artist", artist)
            .put("albumArtist", mostCommon(albumArtists)?.takeIf { !looksGarbled(it) } ?: "")
            .put("rjCode", rjCode)
            .put("group", "本地文件夹")
            .put("genre", "未分类")
            .put("duration", tracks.length())
            .put("totalDuration", totalDuration)
            .put("played", 0)
            .put("favorite", false)
            .put("date", System.currentTimeMillis())
            .put("tracks", tracks)
            .put("localCover", localCover)
            .put("color", JSONArray().put("#c4b8e8").put("#4b416c"))
            .put("shape", "radio")
    }

    // ============ 文件级扫描（v1.11：并行解析 + 标签/文件夹混合分组）============

    // ============ 歌词 sidecar 读取(v1.29:同名 .lrc/.vtt/.srt ≤64KB,随专辑事件回传)============

    /** 读取歌词流:超 64KB 跳过;多编码还原(UTF-8 → Shift_JIS/GB18030/EUC-JP 评分) */
    fun readLyricText(input: InputStream, length: Long): String? {
        if (length > LYRIC_MAX_BYTES) return null
        val bytes = try {
            input.readBytes()
        } catch (_: Exception) {
            return null
        }
        if (bytes.isEmpty() || bytes.size > LYRIC_MAX_BYTES) return null
        return decodeLyricText(bytes)
    }

    /** 歌词文本多编码解码:UTF-8 BOM → UTF-8(合法即用) → 候选字符集按 CJK 评分 */
    fun decodeLyricText(bytes: ByteArray): String? {
        if (bytes.size >= 3 &&
            bytes[0] == 0xEF.toByte() && bytes[1] == 0xBB.toByte() && bytes[2] == 0xBF.toByte()
        ) {
            return String(bytes, 3, bytes.size - 3, Charsets.UTF_8)
        }
        val utf8 = String(bytes, Charsets.UTF_8) // JVM 默认 REPLACE 容错
        if (!utf8.contains('�')) return utf8
        var best: String? = null
        var bestScore = 0
        for (name in listOf("Shift_JIS", "GB18030", "EUC-JP")) {
            val candidate = String(bytes, Charset.forName(name))
            var score = 0
            for (ch in candidate) {
                score += when (ch.code) {
                    in 0x3040..0x30FF, in 0xFF61..0xFF9F -> 3  // 假名
                    in 0x4E00..0x9FFF -> 2                     // 汉字
                    0xFFFD -> -5                               // 替换符 = 解码劣迹
                    else -> 0
                }
            }
            if (score > bestScore) {
                best = candidate
                bestScore = score
            }
        }
        return best ?: utf8
    }

    /** 目录内查找与音频同名的歌词文件(01.mp3 → 01.lrc/01.vtt/01.srt,大小写不敏感) */
    fun findLyricFor(files: List<DocumentFile>?, audioName: String): DocumentFile? {
        val stem = audioName.substringBeforeLast('.').lowercase()
        return files?.firstOrNull { doc ->
            doc.name?.substringBeforeLast('.')?.lowercase() == stem && isLyric(doc.name)
        }
    }

    /** 单文件解析结果 */
    class FileMeta(
        val uri: String,
        val fileName: String,
        val dirUri: String,
        val dirName: String?,
        val title: String?,
        val artist: String?,
        val album: String?,
        val albumArtist: String?,
        val trackNumber: Int?,
        val duration: Double,
        val cover: String?
    )

    /** 逐文件解析（与 readTrackMeta 相同结构；单文件失败返回 null） */
    fun parseFile(context: Context, file: DocumentFile, albumDir: DocumentFile): FileMeta? {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(context, file.uri)
            val durationMs = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
            val picture = retriever.embeddedPicture
            val rawId3 = if (file.name?.lowercase()?.endsWith(".mp3") == true) {
                context.contentResolver.openInputStream(file.uri)?.use { Id3v2Parser.parse(it) }
            } else null
            FileMeta(
                uri = file.uri.toString(),
                fileName = file.name.orEmpty(),
                dirUri = albumDir.uri.toString(),
                dirName = albumDir.name,
                title = chooseMetadata(rawId3?.title, retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_TITLE)),
                artist = chooseMetadata(rawId3?.artist, retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ARTIST)),
                album = chooseMetadata(rawId3?.album, retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ALBUM)),
                albumArtist = chooseMetadata(rawId3?.albumArtist, retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ALBUMARTIST)),
                trackNumber = rawId3?.trackNumber ?: retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_CD_TRACK_NUMBER)?.toIntOrNull(),
                duration = durationMs / 1000.0,
                cover = picture?.let { coverDataUrl(it) }
            )
        } catch (e: Exception) {
            null
        } finally {
            retriever.release()
        }
    }

    /**
     * 扫描根目录：收集全部音频 → 并行解析 → 混合分组 → 组装专辑。
     * 有 ALBUM 标签按「专辑艺术家|专辑名」聚合（跨文件夹）；无标签按文件夹。
     */
    fun scanAlbums(
        context: Context,
        root: DocumentFile,
        onProgress: (processed: Int, total: Int, phase: String, album: JSONObject?) -> Unit = { _, _, _, _ -> },
    ): List<JSONObject> {
        data class Entry(val file: DocumentFile, val dir: DocumentFile)
        val entries = mutableListOf<Entry>()
        val dirImages = HashMap<String, MutableList<DocumentFile>>()
        val dirLyrics = HashMap<String, MutableList<DocumentFile>>()
        fun walk(dir: DocumentFile) {
            for (f in dir.listFiles()) {
                if (f.name?.startsWith(".") == true) continue
                if (f.isDirectory) walk(f)
                else if (f.isFile && isAudio(f.name)) entries.add(Entry(f, dir))
                else if (f.isFile && isImage(f.name)) {
                    dirImages.getOrPut(dir.uri.toString()) { mutableListOf() }.add(f)
                } else if (f.isFile && isLyric(f.name)) {
                    dirLyrics.getOrPut(dir.uri.toString()) { mutableListOf() }.add(f)
                }
            }
        }
        walk(root)

        val executor = Executors.newFixedThreadPool(4)
        try {
            val futures = entries.map { e ->
                executor.submit<FileMeta?> { parseFile(context, e.file, e.dir) }
            }
            onProgress(0, entries.size, "files", null)
            val metas = mutableListOf<FileMeta>()
            futures.forEachIndexed { index, future ->
                try { future.get()?.let { metas.add(it) } } catch (_: Exception) { }
                onProgress(index + 1, entries.size, "files", null)
            }
            val groups = LinkedHashMap<String, MutableList<FileMeta>>()
            val directoryAlbums = metas.groupBy { it.dirUri }
                .mapValues { (_, values) -> mostCommon(values.map { it.album }) }
            for (m in metas) {
                val albumName = m.album ?: directoryAlbums[m.dirUri]
                val albumKey = albumName?.takeIf { !looksGarbled(it) && it.isNotBlank() }
                val normalizedAlbum = albumKey?.normalizeTag()
                val normalizedArtist = m.albumArtist?.normalizeTag().orEmpty()
                val key = if (normalizedAlbum != null) "tag:$normalizedArtist|$normalizedAlbum" else "dir:${m.dirUri}"
                groups.getOrPut(key) { mutableListOf() }.add(if (m.album == null && albumName != null) {
                    FileMeta(m.uri, m.fileName, m.dirUri, m.dirName, m.title, m.artist, albumName, m.albumArtist, m.trackNumber, m.duration, m.cover)
                } else m)
            }
            val built = mutableListOf<JSONObject>()
            val groupEntries = groups.entries.toList()
            groupEntries.forEachIndexed { index, (key, files) ->
                buildAlbumFromFiles(context, key, files, dirImages, dirLyrics)?.let {
                    built.add(it)
                    onProgress(index + 1, groupEntries.size, "albums", it)
                }
            }
            return built
        } finally {
            executor.shutdown()
        }
    }

    private fun buildAlbumFromFiles(
        context: Context,
        key: String,
        files: List<FileMeta>,
        dirImages: Map<String, MutableList<DocumentFile>>,
        dirLyrics: Map<String, MutableList<DocumentFile>> = emptyMap()
    ): JSONObject? {
        if (files.isEmpty()) return null
        val sorted = files.sortedWith { a, b ->
            val ta = a.trackNumber ?: Int.MAX_VALUE
            val tb = b.trackNumber ?: Int.MAX_VALUE
            if (ta != tb) ta.compareTo(tb) else naturalCompare(a.fileName, b.fileName)
        }
        val isTagGroup = key.startsWith("tag:")
        val albumName = sorted.firstNotNullOfOrNull { m -> m.album?.takeIf { !looksGarbled(it) && it.isNotBlank() } }
        val firstDirName = sorted.firstNotNullOfOrNull { it.dirName }
        val title = if (isTagGroup) {
            albumName ?: cleanFolderTitle(firstDirName) ?: "本地导入"
        } else {
            cleanFolderTitle(firstDirName) ?: "本地导入"
        }
        val artist = mostCommon(sorted.map { it.albumArtist })
            ?.takeIf { !looksGarbled(it) }
            ?: mostCommon(sorted.map { it.artist })?.takeIf { !looksGarbled(it) }
            ?: "本地导入"
        val albumArtist = mostCommon(sorted.map { it.albumArtist })?.takeIf { !looksGarbled(it) } ?: ""
        val rjCode = extractRjCode(sorted.first().uri, sorted.first().dirUri, title)

        var embeddedCover: String? = null
        val tracks = JSONArray()
        var totalDuration = 0.0
        sorted.forEachIndexed { index, m ->
            if (embeddedCover == null) embeddedCover = m.cover
            val name = m.title?.takeIf { !looksGarbled(it) && it.isNotBlank() }
                ?: m.fileName.substringBeforeLast('.')
                ?: "Track ${index + 1}"
            // 同名歌词 sidecar(≤64KB,超限/损坏跳过,绝不影响导入)
            val lyricText = try {
                findLyricFor(dirLyrics[m.dirUri], m.fileName)?.let { doc ->
                    context.contentResolver.openInputStream(doc.uri)?.use {
                        readLyricText(it, doc.length())
                    }
                }
            } catch (_: Exception) {
                null
            }
            tracks.put(
                JSONObject()
                    .put("index", index)
                    .put("name", name)
                    .put("url", m.uri)
                    .put("duration", m.duration)
                    .put("cover", m.cover)
                    .put("lyricsText", lyricText)
            )
            totalDuration += m.duration
        }
        var localCover = embeddedCover
        if (localCover == null) {
            val candidates = sorted.flatMap { dirImages[it.dirUri].orEmpty() }.distinctBy { it.uri }
            localCover = folderCoverFromImages(context, candidates)
        }
        val idValue = if (isTagGroup) "tag:$key" else sorted.first().dirUri
        return JSONObject()
            .put("id", "local-${stableId(idValue)}")
            .put("sourcePath", sorted.first().dirUri)
            .put("title", title)
            .put("artist", artist)
            .put("albumArtist", albumArtist)
            .put("rjCode", rjCode)
            .put("group", "本地文件夹")
            .put("genre", "未分类")
            .put("duration", tracks.length())
            .put("totalDuration", totalDuration)
            .put("played", 0)
            .put("favorite", false)
            .put("date", System.currentTimeMillis())
            .put("tracks", tracks)
            .put("localCover", localCover)
            .put("color", JSONArray().put("#c4b8e8").put("#4b416c"))
            .put("shape", "radio")
    }

    private fun String.normalizeTag(): String =
        java.text.Normalizer.normalize(trim().replace(Regex("\\u0000+$"), ""), java.text.Normalizer.Form.NFC)

    private fun folderCoverFromImages(context: Context, images: List<DocumentFile>): String? {
        if (images.isEmpty()) return null
        val pick = images.firstOrNull { Regex("cover|front|folder|album|封面", RegexOption.IGNORE_CASE).containsMatchIn(it.name.orEmpty()) }
            ?: images.first()
        val bytes = readBytes(context, pick.uri) ?: return null
        return coverDataUrl(bytes)
    }
}
