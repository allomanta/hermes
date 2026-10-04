package chat.pantheon.hermes

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.util.UUID
import java.util.concurrent.Executors

/** Keep each share and its Direct Share target together until Dart presents it. */
object IncomingShares {
    private const val CHANNEL = "im.hermes.hermes/incoming_shares"
    private val pending = linkedMapOf<String, Map<String, Any?>?>()
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var channel: MethodChannel? = null
    private var engine: FlutterEngine? = null

    fun register(flutterEngine: FlutterEngine) {
        if (engine === flutterEngine) return
        channel?.setMethodCallHandler(null)
        engine = flutterEngine
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getPendingShares" -> result.success(pending.values.filterNotNull())
                "completeShare" -> {
                    val id = call.arguments as? String
                    if (id != null) pending.remove(id)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    fun receive(context: Context, intent: Intent) {
        val copy = Intent(intent)
        val appContext = context.applicationContext
        val id = UUID.randomUUID().toString()
        pending[id] = null
        worker.execute {
            val share = try {
                @Suppress("DEPRECATION")
                val uris = when (copy.action) {
                    Intent.ACTION_SEND_MULTIPLE -> copy.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)?.toList()
                    else -> copy.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)?.let { listOf(it) }
                } ?: (0 until (copy.clipData?.itemCount ?: 0))
                    .mapNotNull { copy.clipData?.getItemAt(it)?.uri }
                val files = if (uris.isNotEmpty()) {
                    uris.mapIndexed { index, uri ->
                        val resolver = appContext.contentResolver
                        val mime = resolver.getType(uri) ?: copy.type
                        val name = try {
                            resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
                                if (it.moveToFirst()) it.getString(0) else null
                            }
                        } catch (_: Exception) { null }
                        val directory = File(appContext.cacheDir, "incoming-shares/$id/$index")
                        if (!directory.mkdirs() && !directory.isDirectory) throw IOException("Cannot cache shared file")
                        val fileName = File(name ?: uri.lastPathSegment ?: "shared_file").name
                            .takeIf { it.isNotBlank() && it != "." && it != ".." } ?: "shared_file"
                        val file = File(directory, fileName)
                        val input = resolver.openInputStream(uri) ?: throw IOException("Cannot read shared file")
                        input.use { source -> file.outputStream().use { source.copyTo(it) } }
                        mapOf(
                            "path" to file.path,
                            "mimeType" to mime,
                            "type" to when {
                                mime?.startsWith("image/") == true -> "image"
                                mime?.startsWith("video/") == true -> "video"
                                else -> "file"
                            }
                        )
                    }
                } else {
                    val text = copy.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()
                        ?: copy.clipData?.getItemAt(0)?.text?.toString()
                        ?: throw IOException("Share contains no content")
                    listOf(mapOf("path" to text, "type" to "text", "mimeType" to copy.type))
                }
                mapOf("id" to id, "shortcutId" to copy.getStringExtra(Intent.EXTRA_SHORTCUT_ID), "files" to files)
            } catch (error: Exception) {
                Log.w("HermesShare", "Unable to read shared content", error)
                mapOf("id" to id, "files" to emptyList<Any>(), "error" to "read_failed")
            }
            main.post {
                pending[id] = share
                channel?.invokeMethod("sharesChanged", null)
            }
        }
    }
}
