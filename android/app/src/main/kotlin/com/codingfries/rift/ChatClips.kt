package com.codingfries.rift

import android.content.Context
import android.graphics.Bitmap
import android.media.MediaDataSource
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.annotation.OptIn
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.Tracks
import androidx.media3.common.VideoSize
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.BaseDataSource
import androidx.media3.datasource.DataSourceException
import androidx.media3.datasource.DataSpec
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.ProgressiveMediaSource
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.InterruptedIOException
import java.util.concurrent.CompletableFuture
import java.util.concurrent.ExecutionException
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * Chat videos on Android (`AndroidChatClip` in the app): ExoPlayer, with the
 * phone's own decoders, drawing into a Flutter texture.
 *
 * A chat video is decrypted message content and never goes to disk, so the
 * player reads it from the app, a block at a time, as it wants it: each
 * block is asked of Dart over this channel (`read`), which reads it from the
 * video's reader, fetching a big one as it plays. Nothing is held but the
 * last few blocks.
 *
 * It also makes the poster a video carries when it is sent from here: its
 * first picture, as a JPEG (`poster`).
 */
@OptIn(markerClass = [UnstableApi::class])
class ChatClips private constructor(
    private val context: Context,
    private val textures: TextureRegistry,
    private val channel: MethodChannel,
) : MethodChannel.MethodCallHandler {
    companion object {
        const val CHANNEL = "rift/chat_clip"

        /** What one read asks Dart for: the block the desktop player reads. */
        const val BLOCK = 512 * 1024

        /** The blocks each clip keeps, so a player reading back a little finds them. */
        const val KEPT = 8

        /** How long Dart may take over a block before the read fails. */
        const val PATIENCE_S = 30L

        /**
         * How far ahead the player fetches, at least and at most. ExoPlayer's
         * own 50 s fetched a 90 s, 41 MB video whole in its first 8 s
         * (Nov 12); the desktop players and the browser fetch far less.
         */
        const val AHEAD_MIN_MS = 15_000
        const val AHEAD_MAX_MS = 30_000

        fun register(context: Context, engine: FlutterEngine): ChatClips {
            val channel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            val clips = ChatClips(context, engine.renderer, channel)
            channel.setMethodCallHandler(clips)
            return clips
        }
    }

    private val main = Handler(Looper.getMainLooper())
    private val clips = HashMap<Long, Clip>()
    private val posters = Executors.newSingleThreadExecutor()

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "open") return open(call, result)
        if (call.method == "poster") return poster(call, result)
        val clip = call.argument<Number>("id")?.toLong()?.let { clips[it] }
        if (clip == null) {
            // Closed already: nothing to do.
            result.success(null)
            return
        }
        when (call.method) {
            "play" -> {
                if (clip.player.playbackState == Player.STATE_ENDED) clip.player.seekTo(0)
                clip.player.play()
                result.success(true)
            }
            "pause" -> {
                clip.player.pause()
                result.success(null)
            }
            "seek" -> {
                clip.player.seekTo(call.argument<Number>("ms")?.toLong() ?: 0L)
                result.success(null)
            }
            "volume" -> {
                clip.player.volume = (call.argument<Number>("volume")?.toFloat() ?: 1f)
                result.success(null)
            }
            "time" -> {
                val length = clip.player.duration
                result.success(
                    mapOf(
                        "position" to clip.player.currentPosition,
                        "length" to if (length == C.TIME_UNSET) null else length,
                        "playing" to clip.player.isPlaying,
                    ),
                )
            }
            "close" -> {
                clips.remove(clip.id)
                clip.close()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        clips.values.forEach { it.close() }
        clips.clear()
        posters.shutdown()
    }

    private fun open(call: MethodCall, result: MethodChannel.Result) {
        val length = call.argument<Number>("length")?.toLong()
        if (length == null || length <= 0) {
            result.error("bad-length", "No length", null)
            return
        }
        try {
            val clip = Clip(textures.createSurfaceProducer(), length)
            clips[clip.id] = clip
            result.success(clip.id)
        } catch (e: Exception) {
            result.error("open", e.javaClass.simpleName, null)
        }
    }

    private fun event(id: Long, kind: String, width: Int = 0, height: Int = 0, turn: Int = 0, reason: String = "") {
        channel.invokeMethod(
            "event",
            mapOf(
                "id" to id,
                "kind" to kind,
                "width" to width,
                "height" to height,
                "turn" to turn,
                "reason" to reason,
            ),
        )
    }

    // ── One video ─────────────────────────────────────────────────────────

    /**
     * A player and the texture it draws into. Made, used and closed on the
     * main thread, as ExoPlayer wants.
     */
    private inner class Clip(
        private val producer: TextureRegistry.SurfaceProducer,
        length: Long,
    ) : Player.Listener, TextureRegistry.SurfaceProducer.Callback {
        val id: Long = producer.id()
        private val file = ClipFile(id, length)
        val player: ExoPlayer
        private var needsSurface: Boolean
        private var sent = Triple(0, 0, 0)
        private var failed = false

        init {
            player = ExoPlayer.Builder(context)
                .setMediaSourceFactory(ProgressiveMediaSource.Factory { ClipDataSource(file) })
                .setLoadControl(
                    DefaultLoadControl.Builder()
                        .setBufferDurationsMs(
                            AHEAD_MIN_MS,
                            AHEAD_MAX_MS,
                            DefaultLoadControl.DEFAULT_BUFFER_FOR_PLAYBACK_MS,
                            DefaultLoadControl.DEFAULT_BUFFER_FOR_PLAYBACK_AFTER_REBUFFER_MS,
                        )
                        .build(),
                )
                .build()
            // Played beside whatever else is: a call, or music, keeps the
            // sound, as it does on the desktop.
            player.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(C.USAGE_MEDIA)
                    .setContentType(C.AUDIO_CONTENT_TYPE_MOVIE)
                    .build(),
                false,
            )
            producer.setCallback(this)
            val surface = producer.surface
            player.setVideoSurface(surface)
            needsSurface = surface == null
            player.addListener(this)
            player.setMediaItem(MediaItem.fromUri(Uri.parse("rift-clip://$id")))
            player.prepare()
        }

        fun close() {
            player.removeListener(this)
            player.release()
            file.close()
            producer.release()
        }

        // The surface goes while the app is in the background; the sound
        // plays on, and the picture comes back with it.
        override fun onSurfaceAvailable() {
            if (!needsSurface) return
            player.setVideoSurface(producer.surface)
            needsSurface = false
        }

        override fun onSurfaceCleanup() {
            player.setVideoSurface(null)
            needsSurface = true
        }

        override fun onVideoSizeChanged(videoSize: VideoSize) = sendSize()

        override fun onPlaybackStateChanged(playbackState: Int) {
            // Waiting for the file, the card shows it is loading: a seek past
            // what has been fetched otherwise looks like a frozen video.
            if (playbackState == Player.STATE_BUFFERING) event(id, "waiting")
            else event(id, "loaded")
            when (playbackState) {
                Player.STATE_READY -> sendSize()
                Player.STATE_ENDED -> event(id, "ended")
            }
        }

        /**
         * A file whose picture nothing here decodes plays its sound alone
         * rather than failing; the card says so instead.
         */
        override fun onTracksChanged(tracks: Tracks) {
            if (tracks.containsType(C.TRACK_TYPE_VIDEO) && !tracks.isTypeSupported(C.TRACK_TYPE_VIDEO)) {
                fail("cannotDecode", "No decoder for the picture")
            }
        }

        override fun onPlayerError(error: PlaybackException) {
            val cannot = when (error.errorCode) {
                PlaybackException.ERROR_CODE_DECODER_INIT_FAILED,
                PlaybackException.ERROR_CODE_DECODER_QUERY_FAILED,
                PlaybackException.ERROR_CODE_DECODING_FAILED,
                PlaybackException.ERROR_CODE_DECODING_FORMAT_UNSUPPORTED,
                PlaybackException.ERROR_CODE_DECODING_FORMAT_EXCEEDS_CAPABILITIES,
                PlaybackException.ERROR_CODE_PARSING_CONTAINER_UNSUPPORTED,
                -> true
                else -> false
            }
            fail(if (cannot) "cannotDecode" else "failed", error.errorCodeName)
        }

        private fun fail(kind: String, reason: String) {
            if (failed) return
            failed = true
            player.pause()
            event(id, kind, reason = reason)
        }

        /**
         * The picture's shape as shown. Where the texture does not turn the
         * picture itself (the newer Android texture), the card turns it by
         * [turn] degrees, as video_player does.
         */
        private fun sendSize() {
            val size = player.videoSize
            if (size.width == 0 || size.height == 0) return
            val turn = if (producer.handlesCropAndRotation()) 0 else (player.videoFormat?.rotationDegrees ?: 0)
            val shape = Triple(size.width, size.height, turn)
            if (shape == sent) return
            sent = shape
            event(id, "pictureSize", size.width, size.height, turn)
        }
    }

    // ── Reading the file from Dart ────────────────────────────────────────

    /**
     * One clip's file, read a block at a time from Dart and kept a few
     * blocks deep. Read on ExoPlayer's loading thread, which waits for the
     * answer; asked on the main thread, where the channel is.
     */
    private inner class ClipFile(private val id: Long, val length: Long) {
        private val blocks = object : LinkedHashMap<Long, ByteArray>(KEPT, 0.75f, true) {
            override fun removeEldestEntry(eldest: MutableMap.MutableEntry<Long, ByteArray>?) = size > KEPT
        }
        private val waiting = HashSet<CompletableFuture<ByteArray>>()

        @Volatile
        private var closed = false

        /** Up to [size] bytes from [at] into [into], at least one. */
        fun read(at: Long, into: ByteArray, offset: Int, size: Int): Int {
            val index = at / BLOCK
            val block = block(index)
            val from = (at - index * BLOCK).toInt()
            val n = min(size, block.size - from)
            if (n <= 0) throw IOException("Short block")
            System.arraycopy(block, from, into, offset, n)
            return n
        }

        private fun block(index: Long): ByteArray {
            synchronized(blocks) { blocks[index]?.let { return it } }
            val start = index * BLOCK
            val want = min(BLOCK.toLong(), length - start).toInt()
            val answer = CompletableFuture<ByteArray>()
            synchronized(waiting) {
                if (closed) throw IOException("Closed")
                waiting.add(answer)
            }
            main.post {
                channel.invokeMethod(
                    "read",
                    mapOf("id" to id, "offset" to start, "length" to want),
                    object : MethodChannel.Result {
                        override fun success(result: Any?) {
                            if (result is ByteArray) {
                                answer.complete(result)
                            } else {
                                answer.completeExceptionally(IOException("No bytes"))
                            }
                        }

                        override fun error(code: String, message: String?, details: Any?) {
                            answer.completeExceptionally(IOException(message ?: code))
                        }

                        override fun notImplemented() {
                            answer.completeExceptionally(IOException("Nobody reads"))
                        }
                    },
                )
            }
            val bytes = try {
                answer.get(PATIENCE_S, TimeUnit.SECONDS)
            } catch (e: InterruptedException) {
                Thread.currentThread().interrupt()
                throw InterruptedIOException()
            } catch (e: TimeoutException) {
                throw IOException("The app did not answer")
            } catch (e: ExecutionException) {
                throw (e.cause as? IOException) ?: IOException(e.cause)
            } finally {
                synchronized(waiting) { waiting.remove(answer) }
            }
            if (bytes.size != want) throw IOException("Read ${bytes.size} of $want")
            synchronized(blocks) { blocks[index] = bytes }
            return bytes
        }

        /** A read still waiting fails now rather than at its time-out. */
        fun close() {
            synchronized(waiting) {
                closed = true
                waiting.forEach { it.completeExceptionally(IOException("Closed")) }
                waiting.clear()
            }
            synchronized(blocks) { blocks.clear() }
        }
    }

    /** What ExoPlayer reads a clip through. */
    private class ClipDataSource(private val file: ClipFile) : BaseDataSource(false) {
        private var uri: Uri? = null
        private var at = 0L
        private var left = 0L
        private var opened = false

        override fun open(dataSpec: DataSpec): Long {
            uri = dataSpec.uri
            transferInitializing(dataSpec)
            if (dataSpec.position > file.length) {
                throw DataSourceException(PlaybackException.ERROR_CODE_IO_READ_POSITION_OUT_OF_RANGE)
            }
            at = dataSpec.position
            left = file.length - at
            if (dataSpec.length != C.LENGTH_UNSET.toLong()) left = min(left, dataSpec.length)
            opened = true
            transferStarted(dataSpec)
            return left
        }

        override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
            if (length == 0) return 0
            if (left == 0L) return C.RESULT_END_OF_INPUT
            val n = file.read(at, buffer, offset, min(length.toLong(), left).toInt())
            at += n
            left -= n
            bytesTransferred(n)
            return n
        }

        override fun getUri(): Uri? = uri

        override fun close() {
            uri = null
            if (!opened) return
            opened = false
            transferEnded()
        }
    }

    // ── Posters ───────────────────────────────────────────────────────────

    /**
     * The first picture of a video being sent, as a JPEG whose longer side
     * is at most `longest`: from the picked file where it lies (`path`), or
     * from `bytes`. Null where the phone cannot decode it.
     */
    private fun poster(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")
        val bytes = call.argument<ByteArray>("bytes")
        val longest = call.argument<Number>("longest")?.toInt() ?: 880
        posters.execute {
            val jpeg = try {
                firstPicture(path, bytes, longest)
            } catch (e: Exception) {
                null
            }
            main.post { result.success(jpeg) }
        }
    }

    private fun firstPicture(path: String?, bytes: ByteArray?, longest: Int): ByteArray? {
        val retriever = MediaMetadataRetriever()
        try {
            when {
                path != null -> retriever.setDataSource(path)
                bytes != null -> retriever.setDataSource(BytesSource(bytes))
                else -> return null
            }
            // Turned upright, as the video shows.
            val frame = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                retriever.getScaledFrameAtTime(
                    0,
                    MediaMetadataRetriever.OPTION_CLOSEST_SYNC,
                    longest,
                    longest,
                )
            } else {
                retriever.getFrameAtTime(0, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
            } ?: return null
            val scale = longest.toFloat() / max(frame.width, frame.height)
            val picture = if (scale < 1f) {
                Bitmap.createScaledBitmap(
                    frame,
                    max(1, (frame.width * scale).roundToInt()),
                    max(1, (frame.height * scale).roundToInt()),
                    true,
                ).also { frame.recycle() }
            } else {
                frame
            }
            val out = ByteArrayOutputStream()
            picture.compress(Bitmap.CompressFormat.JPEG, 80, out)
            picture.recycle()
            return out.toByteArray()
        } finally {
            retriever.release()
        }
    }

    private class BytesSource(private val bytes: ByteArray) : MediaDataSource() {
        override fun readAt(position: Long, buffer: ByteArray, offset: Int, size: Int): Int {
            if (position >= bytes.size) return -1
            val n = min(size.toLong(), bytes.size - position).toInt()
            System.arraycopy(bytes, position.toInt(), buffer, offset, n)
            return n
        }

        override fun getSize(): Long = bytes.size.toLong()

        override fun close() {}
    }
}
