package com.omniai.omni_ai

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest

class MainActivity : FlutterActivity() {
    private val modelChannel = "omni_ai/bundled_model"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, modelChannel)
            .setMethodCallHandler { call, result ->
                if (call.method != "copyBundledModel") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }

                val assetPath = call.argument<String>("assetPath")
                val destinationPath = call.argument<String>("destinationPath")
                val expectedBytes = call.argument<Number>("expectedBytes")?.toLong()
                val expectedSha256 = call.argument<String>("expectedSha256")
                if (
                    assetPath.isNullOrBlank() ||
                    destinationPath.isNullOrBlank() ||
                    expectedBytes == null ||
                    expectedSha256.isNullOrBlank()
                ) {
                    result.error("INVALID_ARGUMENT", "Missing bundled model metadata.", null)
                    return@setMethodCallHandler
                }

                try {
                    val destination = File(destinationPath).canonicalFile
                    val appFiles = filesDir.canonicalFile
                    if (!destination.path.startsWith(appFiles.path + File.separator)) {
                        result.error("INVALID_PATH", "Model destination is outside app storage.", null)
                        return@setMethodCallHandler
                    }

                    destination.parentFile?.mkdirs()
                    val temporary = File(destination.path + ".part")
                    if (temporary.exists()) temporary.delete()
                    val digest = MessageDigest.getInstance("SHA-256")
                    var copied = 0L
                    try {
                        assets.open(assetPath).use { input ->
                            temporary.outputStream().buffered().use { output ->
                                val buffer = ByteArray(1024 * 1024)
                                while (true) {
                                    val count = input.read(buffer)
                                    if (count < 0) break
                                    output.write(buffer, 0, count)
                                    digest.update(buffer, 0, count)
                                    copied += count
                                }
                                output.flush()
                            }
                        }
                        val actualHash = digest.digest().joinToString("") { "%02x".format(it) }
                        if (copied < expectedBytes * 0.95 || actualHash != expectedSha256) {
                            throw IllegalStateException(
                                "Bundled model validation failed (bytes=$copied, sha256=$actualHash)."
                            )
                        }
                        if (destination.exists() && !destination.delete()) {
                            throw IllegalStateException("Unable to replace previous model file.")
                        }
                        if (!temporary.renameTo(destination)) {
                            throw IllegalStateException("Unable to finalize bundled model file.")
                        }
                        result.success(destination.absolutePath)
                    } catch (error: Throwable) {
                        if (temporary.exists()) temporary.delete()
                        throw error
                    }
                } catch (error: Throwable) {
                    result.error("BUNDLED_MODEL_INSTALL_FAILED", error.message, null)
                }
            }
    }
}
