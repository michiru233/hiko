package top.voicehub.kikoeru

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/**
 * 音声库持久化：library.json（schema 与 desktop 端一致：{"albums": [...]}）。
 * 存放在应用私有 filesDir，避免任何存储权限。
 */
class LibraryStore(context: Context) {

    private val file = File(context.filesDir, "library.json")

    fun load(): JSONArray {
        if (!file.exists()) return JSONArray()
        val text = file.readText()
        return JSONObject(text).optJSONArray("albums") ?: JSONArray()
    }

    fun save(albums: JSONArray) {
        file.writeText(JSONObject().put("albums", albums).toString(2))
    }
}
