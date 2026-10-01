package top.voicehub.hiko

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/**
 * 文件级扫描缓存（1.99.11）：uri → (lastModified, size, 文字元数据)。
 *
 * 增量扫描时命中且未变的文件直接复用上次解析结果，不再走 MediaMetadataRetriever；
 * 同 URI 文件被替换（mtime/size 变化）也能检出——堵住「目录级 URI 跳过」的盲区。
 * 不缓存封面（拍板）：封面由同目录当次解析/提取的新/变文件提供，全量扫描可修复极端情况。
 * 缓存损坏按空缓存处理 = 退化为全量解析，绝不致命。
 */
class ScanCache(context: Context) {

    data class Entry(
        val lastModified: Long,
        val size: Long,
        val fileName: String,
        val dirUri: String,
        val dirName: String?,
        val title: String?,
        val artist: String?,
        val album: String?,
        val albumArtist: String?,
        val trackNumber: Int?,
        val duration: Double,
    ) {
        /** 缓存命中判定（纯函数，可单测）：任一侧 mtime 取不到(≤0)视为变化；mtime/size 全等才命中 */
        fun isFresh(lastModified: Long, size: Long): Boolean =
            lastModified > 0 && this.lastModified > 0 &&
                lastModified == this.lastModified && size == this.size
    }

    private val file = File(context.filesDir, "scan_cache.json")
    private val entries = LinkedHashMap<String, Entry>()

    init {
        load()
    }

    private fun load() {
        try {
            if (!file.exists()) return
            val arr = JSONArray(file.readText())
            for (i in 0 until arr.length()) {
                val o = arr.getJSONObject(i)
                val track = if (o.has("track") && o.getInt("track") >= 0) o.getInt("track") else null
                entries[o.getString("uri")] = Entry(
                    lastModified = o.getLong("mtime"),
                    size = o.getLong("size"),
                    fileName = o.getString("name"),
                    dirUri = o.getString("dir"),
                    dirName = o.optString("dirName").ifEmpty { null },
                    title = o.optString("title").ifEmpty { null },
                    artist = o.optString("artist").ifEmpty { null },
                    album = o.optString("album").ifEmpty { null },
                    albumArtist = o.optString("albumArtist").ifEmpty { null },
                    trackNumber = track,
                    duration = o.getDouble("duration"),
                )
            }
        } catch (_: Exception) {
            entries.clear()
        }
    }

    fun get(uri: String): Entry? = entries[uri]

    fun put(uri: String, lastModified: Long, size: Long, meta: ImportScanner.FileMeta) {
        entries[uri] = Entry(
            lastModified = lastModified,
            size = size,
            fileName = meta.fileName,
            dirUri = meta.dirUri,
            dirName = meta.dirName,
            title = meta.title,
            artist = meta.artist,
            album = meta.album,
            albumArtist = meta.albumArtist,
            trackNumber = meta.trackNumber,
            duration = meta.duration,
        )
    }

    /** 只保留仍在扫描树内的 uri，其余清掉防无限膨胀 */
    fun retainAll(keep: Set<String>) {
        entries.keys.retainAll(keep)
    }

    /** 原子写：临时文件 + rename，中途崩溃不产生半份缓存 */
    fun save() {
        try {
            val arr = JSONArray()
            for ((uri, e) in entries) {
                arr.put(
                    JSONObject()
                        .put("uri", uri)
                        .put("mtime", e.lastModified)
                        .put("size", e.size)
                        .put("name", e.fileName)
                        .put("dir", e.dirUri)
                        .put("dirName", e.dirName ?: "")
                        .put("title", e.title ?: "")
                        .put("artist", e.artist ?: "")
                        .put("album", e.album ?: "")
                        .put("albumArtist", e.albumArtist ?: "")
                        .put("track", e.trackNumber ?: -1)
                        .put("duration", e.duration)
                )
            }
            val tmp = File(file.parentFile, file.name + ".tmp")
            tmp.writeText(arr.toString())
            if (!tmp.renameTo(file)) {
                file.delete()
                tmp.renameTo(file)
            }
        } catch (_: Exception) {
        }
    }
}
