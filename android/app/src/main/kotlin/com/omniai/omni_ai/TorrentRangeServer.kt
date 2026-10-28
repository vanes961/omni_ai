package com.omniai.omni_ai

import org.libtorrent4j.TorrentHandle
import org.libtorrent4j.TorrentInfo
import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.BufferedReader
import java.io.File
import java.io.InputStreamReader
import java.io.RandomAccessFile
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.net.SocketTimeoutException
import java.net.URLDecoder
import java.nio.charset.StandardCharsets
import java.util.UUID
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Private loopback HTTP endpoint for one selected torrent file.
 *
 * It never serves bytes until libtorrent reports the covering pieces complete,
 * avoiding playback of preallocated/sparse-file zeros.
 */
internal class TorrentRangeServer(
    private val handle: TorrentHandle,
    private val info: TorrentInfo,
    private val fileIndex: Int,
    private val saveDirectory: File,
) : AutoCloseable {
    private val stopped = AtomicBoolean(false)
    private val clients: ExecutorService = Executors.newCachedThreadPool()
    private val token = UUID.randomUUID().toString().replace("-", "")
    private val fileStorage = info.files()
    private val fileSize = fileStorage.fileSize(fileIndex)
    private val pieceLength = info.pieceLength()
    private val fileOffset = fileStorage.fileOffset(fileIndex)
    private val file = File(fileStorage.filePath(fileIndex, saveDirectory.absolutePath)).canonicalFile
    private val root = saveDirectory.canonicalFile
    private val server = ServerSocket(0, 16, InetAddress.getByName("127.0.0.1"))
    private val acceptThread = Thread({ acceptLoop() }, "omni-torrent-http").apply {
        isDaemon = true
        start()
    }

    init {
        require(fileIndex in 0 until info.numFiles()) { "Invalid torrent file index." }
        require(file.path.startsWith(root.path + File.separator)) {
            "Torrent file path escaped private storage."
        }
        require(pieceLength > 0 && fileSize >= 0L) { "Invalid torrent file metadata." }
    }

    val url: String
        get() = "http://127.0.0.1:${server.localPort}/$token"

    override fun close() {
        if (!stopped.compareAndSet(false, true)) return
        try {
            server.close()
        } catch (_: Throwable) {
        }
        clients.shutdownNow()
    }

    private fun acceptLoop() {
        while (!stopped.get()) {
            try {
                val socket = server.accept()
                socket.soTimeout = 10_000
                clients.execute { handleClient(socket) }
            } catch (_: SocketTimeoutException) {
                // Retry until explicitly stopped.
            } catch (_: Throwable) {
                if (!stopped.get()) continue
            }
        }
    }

    private fun handleClient(socket: Socket) {
        socket.use { client ->
            try {
                val input = BufferedInputStream(client.getInputStream())
                val reader = BufferedReader(InputStreamReader(input, StandardCharsets.US_ASCII))
                val requestLine = reader.readLine() ?: return
                val parts = requestLine.split(" ")
                if (parts.size < 2 || (parts[0] != "GET" && parts[0] != "HEAD")) {
                    writeError(client, 405, "Method Not Allowed")
                    return
                }
                val path = parts[1].substringBefore('?')
                if (path != "/$token") {
                    writeError(client, 404, "Not Found")
                    return
                }
                var rangeHeader: String? = null
                while (true) {
                    val line = reader.readLine() ?: break
                    if (line.isEmpty()) break
                    if (line.startsWith("Range:", ignoreCase = true)) {
                        rangeHeader = line.substringAfter(':').trim()
                    }
                }
                if (!file.isFile || !file.canRead()) {
                    writeError(client, 503, "Torrent file is not available yet")
                    return
                }
                val range = parseRange(rangeHeader, fileSize)
                if (range == null && rangeHeader != null) {
                    writeError(client, 416, "Range Not Satisfiable", "Content-Range: bytes */$fileSize\r\n")
                    return
                }
                val start = range?.first ?: 0L
                val end = range?.last ?: (fileSize - 1L)
                if (fileSize == 0L) {
                    val output = BufferedOutputStream(client.getOutputStream())
                    output.write("HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".toByteArray(StandardCharsets.US_ASCII))
                    output.flush()
                    return
                }
                val firstPiece = ((fileOffset + start) / pieceLength).toInt()
                val lastPiece = ((fileOffset + end) / pieceLength).toInt()
                handle.setSequentialRange(firstPiece, lastPiece)
                val ready = waitForPieces(firstPiece, lastPiece, 45_000L)
                if (!ready) {
                    writeError(client, 503, "Requested torrent pieces are not ready")
                    return
                }

                val output = BufferedOutputStream(client.getOutputStream())
                val status = if (range != null) "206 Partial Content" else "200 OK"
                output.write("HTTP/1.1 $status\r\n".toByteArray(StandardCharsets.US_ASCII))
                output.write("Content-Type: ${contentType(file.name)}\r\n".toByteArray(StandardCharsets.US_ASCII))
                output.write("Accept-Ranges: bytes\r\n".toByteArray(StandardCharsets.US_ASCII))
                output.write("Content-Length: ${if (fileSize == 0L) 0L else end - start + 1L}\r\n".toByteArray(StandardCharsets.US_ASCII))
                if (range != null) {
                    output.write("Content-Range: bytes $start-$end/$fileSize\r\n".toByteArray(StandardCharsets.US_ASCII))
                }
                output.write("Connection: close\r\n\r\n".toByteArray(StandardCharsets.US_ASCII))
                output.flush()
                if (parts[0] == "HEAD" || fileSize == 0L) return

                RandomAccessFile(file, "r").use { random ->
                    random.seek(start)
                    var position = start
                    val buffer = ByteArray(64 * 1024)
                    while (!stopped.get() && position <= end) {
                        val chunkEnd = minOf(end, position + buffer.size - 1L)
                        val chunkFirstPiece = ((fileOffset + position) / pieceLength).toInt()
                        val chunkLastPiece = ((fileOffset + chunkEnd) / pieceLength).toInt()
                        handle.setSequentialRange(chunkFirstPiece, chunkLastPiece)
                        if (!waitForPieces(chunkFirstPiece, chunkLastPiece, 45_000L)) return
                        val wanted = minOf(buffer.size.toLong(), end - position + 1L).toInt()
                        random.seek(position)
                        val count = random.read(buffer, 0, wanted)
                        if (count <= 0) return
                        output.write(buffer, 0, count)
                        output.flush()
                        position += count
                    }
                }
            } catch (_: Throwable) {
                // Client disconnects during seeking/playback are expected.
            }
        }
    }

    private fun waitForPieces(first: Int, last: Int, timeoutMs: Long): Boolean {
        val deadline = System.currentTimeMillis() + timeoutMs
        while (!stopped.get() && System.currentTimeMillis() < deadline) {
            if (!handle.isValid()) return false
            var allReady = true
            for (piece in first..last) {
                if (!handle.havePiece(piece)) {
                    allReady = false
                    break
                }
            }
            if (allReady) return true
            try {
                Thread.sleep(150)
            } catch (_: InterruptedException) {
                Thread.currentThread().interrupt()
                return false
            }
        }
        return false
    }

    private fun parseRange(value: String?, size: Long): ByteRange? {
        if (value == null) return null
        if (!value.startsWith("bytes=") || value.contains(',')) return null
        val parts = value.removePrefix("bytes=").split('-', limit = 2)
        if (parts.size != 2 || size <= 0L) return null
        return try {
            val start: Long
            val end: Long
            if (parts[0].isBlank()) {
                val suffixLength = parts[1].toLong()
                if (suffixLength <= 0L) return null
                start = maxOf(0L, size - suffixLength)
                end = size - 1L
            } else {
                start = parts[0].toLong()
                end = if (parts[1].isBlank()) size - 1L else parts[1].toLong()
            }
            if (start < 0L || start >= size || end < start) null
            else ByteRange(start, minOf(end, size - 1L))
        } catch (_: NumberFormatException) {
            null
        }
    }

    private fun writeError(socket: Socket, status: Int, message: String, extraHeaders: String = "") {
        try {
            val body = message.toByteArray(StandardCharsets.UTF_8)
            val output = BufferedOutputStream(socket.getOutputStream())
            output.write("HTTP/1.1 $status $message\r\n".toByteArray(StandardCharsets.US_ASCII))
            output.write("Content-Type: text/plain; charset=utf-8\r\n".toByteArray(StandardCharsets.US_ASCII))
            output.write("Content-Length: ${body.size}\r\n".toByteArray(StandardCharsets.US_ASCII))
            output.write(extraHeaders.toByteArray(StandardCharsets.US_ASCII))
            output.write("Connection: close\r\n\r\n".toByteArray(StandardCharsets.US_ASCII))
            output.write(body)
            output.flush()
        } catch (_: Throwable) {
        }
    }

    private fun contentType(name: String): String = when (name.substringAfterLast('.', "").lowercase()) {
        "mp4", "m4v" -> "video/mp4"
        "mkv" -> "video/x-matroska"
        "webm" -> "video/webm"
        "avi" -> "video/x-msvideo"
        "mov" -> "video/quicktime"
        "ts" -> "video/mp2t"
        "mpg", "mpeg" -> "video/mpeg"
        else -> "application/octet-stream"
    }

    private data class ByteRange(val first: Long, val last: Long)
}
