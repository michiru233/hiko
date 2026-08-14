package top.voicehub.kikoeru

import java.net.HttpURLConnection
import java.net.InetSocketAddress
import java.net.Proxy
import java.net.URL

/**
 * DLsite 标签刮削：与 desktop main.js 的 parseDlsiteTags / parseDlsiteTitle / fetchWithProxy 对齐。
 * 用 HttpURLConnection 直连（原生网络栈，无 CORS 限制）；代理为可选配置。
 */
object DlsiteScraper {

    private val TAG_REGEX = Regex("""genre/\d+/from/work\.genre/ana_flg/all"[^>]*>([^<]+)</a>""", RegexOption.IGNORE_CASE)
    private val TITLE_REGEX = Regex("""id="work_name"[^>]*>([^<]+)<""")

    fun parseTags(html: String): List<String> {
        val tags = mutableListOf<String>()
        for (m in TAG_REGEX.findAll(html)) {
            val tag = m.groupValues[1].trim()
            if (tag.isNotEmpty() && tag !in tags) tags.add(tag)
        }
        return tags
    }

    fun parseTitle(html: String): String? = TITLE_REGEX.find(html)?.groupValues?.get(1)?.trim()

    /** 请求 DLsite 作品页；非 200 抛异常（404 = 不存在的作品号）；限速由调用方负责 */
    fun fetchWorkPage(rj: String, proxy: String?): String {
        val url = URL("https://www.dlsite.com/maniax/work/=/product_id/$rj.html")
        val parsedProxy = proxy?.takeIf { it.isNotBlank() }?.let { raw ->
            val clean = raw.removePrefix("http://").removePrefix("https://")
            val parts = clean.split(":")
            if (parts.size >= 2) {
                Proxy(Proxy.Type.HTTP, InetSocketAddress(parts[0], parts[1].toIntOrNull() ?: 80))
            } else null
        }
        val conn = (if (parsedProxy != null) url.openConnection(parsedProxy) else url.openConnection()) as HttpURLConnection
        conn.requestMethod = "GET"
        conn.connectTimeout = 15000
        conn.readTimeout = 15000
        conn.setRequestProperty(
            "User-Agent",
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36"
        )
        conn.setRequestProperty("Accept-Language", "ja,zh-CN;q=0.8")
        try {
            val code = conn.responseCode
            if (code != 200) throw IllegalStateException("DLsite 返回 $code")
            return conn.inputStream.bufferedReader().use { it.readText() }
        } finally {
            conn.disconnect()
        }
    }
}
