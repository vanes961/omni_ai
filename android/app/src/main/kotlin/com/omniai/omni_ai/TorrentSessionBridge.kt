package com.omniai.omni_ai

import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.libtorrent4j.AlertListener
import org.libtorrent4j.Priority
import org.libtorrent4j.SessionManager
import org.libtorrent4j.TorrentHandle
import org.libtorrent4j.alerts.AddTorrentAlert
import org.libtorrent4j.alerts.Alert
import org.libtorrent4j.alerts.MetadataReceivedAlert
import org.libtorrent4j.swig.torrent_flags_t
import java.io.File
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Native session boundary for OMNI's standalone torrent engine.
 *
 * Owns the standalone libtorrent session, validates magnet URIs, exposes
 * metadata/file selection and transfer status, and hosts the selected file via
 * a loopback HTTP byte-range server. End-to-end playback still needs device validation.
 */
internal class TorrentSessionBridge(context: Context) {
    private val appContext = context.applicationContext
    private val mainHandler = Handler(Looper.getMainLooper())
    private val worker: ExecutorService = Executors.newSingleThreadExecutor()
    private val sessionManagerDelegate = lazy(LazyThreadSafetyMode.SYNCHRONIZED) { SessionManager() }
    private val sessionManager by sessionManagerDelegate
    private val saveDirectory = File(appContext.filesDir, "omni_torrent_engine")
    @Volatile private var currentHandle: TorrentHandle? = null
    @Volatile private var sessionStarted = false
    @Volatile private var listenerRegistered = false
    @Volatile private var closed = false
    @Volatile private var rangeServer: TorrentRangeServer? = null

    private val alertListener = object : AlertListener {
        override fun types(): IntArray? = null

        override fun alert(alert: Alert<*>) {
            when (alert) {
                is AddTorrentAlert -> currentHandle = alert.handle()
                is MetadataReceivedAlert -> currentHandle = alert.handle()
            }
        }
    }

    fun handle(call: MethodCall, result: MethodChannel.Result): Boolean {
        when (call.method) {
            "startMagnet" -> {
                val magnet = call.argument<String>("magnetUri")
                if (!isValidMagnet(magnet)) {
                    result.error(
                        "INVALID_MAGNET",
                        "A valid magnet URI with a BitTorrent info hash is required.",
                        null
                    )
                    return true
                }
                runWorker(result) {
                    ensureSessionStarted()
                    sessionManager.download(magnet!!.trim(), saveDirectory, torrent_flags_t())
                    mapOf("accepted" to true, "state" to "resolving_metadata")
                }
            }
            "getTorrentStatus" -> runWorker(result) { statusSnapshot() }
            "listTorrentFiles" -> runWorker(result) { listFilesSnapshot() }
            "selectTorrentFile" -> {
                val index = call.argument<Number>("index")?.toInt()
                if (index == null || index < 0) {
                    result.error("INVALID_FILE_INDEX", "A non-negative file index is required.", null)
                    return true
                }
                runWorker(result) { selectFile(index) }
            }
            "startTorrentPlayback" -> {
                val index = call.argument<Number>("index")?.toInt()
                if (index == null || index < 0) {
                    result.error("INVALID_FILE_INDEX", "A non-negative file index is required.", null)
                    return true
                }
                runWorker(result) {
                    val handle = currentHandle
                    check(handle != null && handle.isValid()) { "No active torrent is available." }
                    val info = handle.torrentFile()
                        ?: throw IllegalStateException("Torrent metadata has not arrived yet.")
                    require(index in 0 until info.numFiles()) { "File index is outside the torrent file list." }
                    rangeServer?.close()
                    selectFile(index)
                    val server = TorrentRangeServer(handle, info, index, saveDirectory)
                    rangeServer = server
                    mapOf("url" to server.url, "selectedIndex" to index)
                }
            }
            "stopTorrent" -> runWorker(result) {
                rangeServer?.close()
                rangeServer = null
                val handle = currentHandle
                if (handle != null && handle.isValid()) sessionManager.remove(handle)
                currentHandle = null
                mapOf("stopped" to true)
            }
            else -> return false
        }
        return true
    }

    fun close() {
        if (closed) return
        closed = true
        worker.execute {
            try {
                rangeServer?.close()
                rangeServer = null
                // Do not initialize libtorrent during Activity teardown if the
                // user never opened the torrent player.
                if (sessionManagerDelegate.isInitialized()) {
                    val manager = sessionManagerDelegate.value
                    if (listenerRegistered) {
                        manager.removeListener(alertListener)
                        listenerRegistered = false
                    }
                    manager.stop()
                    sessionStarted = false
                }
            } catch (_: Throwable) {
                // Activity teardown must not crash if the native session failed.
            } finally {
                currentHandle = null
                worker.shutdown()
            }
        }
    }

    private fun ensureSessionStarted() {
        check(!closed) { "Torrent engine has been closed." }
        if (!saveDirectory.exists() && !saveDirectory.mkdirs()) {
            throw IllegalStateException("Unable to create private torrent storage.")
        }
        val canonicalSave = saveDirectory.canonicalFile
        val canonicalRoot = appContext.filesDir.canonicalFile
        require(canonicalSave.path.startsWith(canonicalRoot.path + File.separator)) {
            "Torrent storage must remain inside app-private storage."
        }
        if (!listenerRegistered) {
            sessionManager.addListener(alertListener)
            listenerRegistered = true
        }
        if (!sessionStarted) {
            sessionManager.start()
            sessionManager.startDht()
            sessionStarted = true
        }
    }

    private fun statusSnapshot(): Map<String, Any?> {
        val handle = currentHandle
        if (handle == null || !handle.isValid()) {
            return mapOf(
                "metadataReady" to false,
                "progress" to 0.0,
                "downloadRateBytesPerSecond" to 0,
                "downloadedBytes" to 0L,
                "finished" to false
            )
        }
        val status = handle.status()
        val info = handle.torrentFile()
        return mapOf(
            "metadataReady" to (info != null),
            "name" to (info?.name() ?: status.name()),
            "progress" to status.progress().toDouble(),
            "downloadRateBytesPerSecond" to status.downloadRate(),
            "downloadedBytes" to status.totalDone(),
            "finished" to status.isFinished(),
            "fileCount" to (info?.numFiles() ?: 0)
        )
    }

    private fun listFilesSnapshot(): Map<String, Any?> {
        val handle = currentHandle
        val info = if (handle != null && handle.isValid()) handle.torrentFile() else null
        if (info == null) return mapOf("metadataReady" to false, "files" to emptyList<Map<String, Any>>())
        val storage = info.files()
        val files = (0 until info.numFiles()).map { index ->
            mapOf(
                "index" to index,
                "path" to storage.filePath(index),
                "name" to storage.fileName(index),
                "sizeBytes" to storage.fileSize(index)
            )
        }
        return mapOf("metadataReady" to true, "files" to files)
    }

    private fun selectFile(index: Int): Map<String, Any?> {
        val handle = currentHandle
        check(handle != null && handle.isValid()) { "No active torrent is available." }
        val info = handle.torrentFile()
            ?: throw IllegalStateException("Torrent metadata has not arrived yet.")
        require(index in 0 until info.numFiles()) { "File index is outside the torrent file list." }

        val priorities = Priority.array(Priority.IGNORE, info.numFiles())
        priorities[index] = Priority.DEFAULT
        handle.prioritizeFiles(priorities)
        return mapOf("selectedIndex" to index, "path" to info.files().filePath(index))
    }

    private fun isValidMagnet(value: String?): Boolean {
        if (value.isNullOrBlank() || value.length > 4096) return false
        val uri = try {
            Uri.parse(value.trim())
        } catch (_: Throwable) {
            return false
        }
        if (!uri.scheme.equals("magnet", ignoreCase = true)) return false
        return uri.getQueryParameters("xt").any { topic ->
            val prefix = "urn:btih:"
            if (!topic.startsWith(prefix, ignoreCase = true)) {
                false
            } else {
                val hash = topic.substring(prefix.length)
                hash.matches(Regex("(?i)[0-9a-f]{40}")) ||
                    hash.matches(Regex("(?i)[a-z2-7]{32}"))
            }
        }
    }

    private fun runWorker(result: MethodChannel.Result, operation: () -> Any?) {
        worker.execute {
            try {
                val value = operation()
                mainHandler.post { result.success(value) }
            } catch (error: Throwable) {
                val code = when (error) {
                    is IllegalArgumentException -> "INVALID_ARGUMENT"
                    else -> "TORRENT_ENGINE_ERROR"
                }
                mainHandler.post {
                    result.error(code, error.message ?: "Torrent engine operation failed.", null)
                }
            }
        }
    }
}
