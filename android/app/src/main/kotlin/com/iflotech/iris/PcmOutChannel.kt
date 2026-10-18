package com.iflotech.iris

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.LinkedBlockingQueue
import kotlin.math.max

/**
 * Plays a voice reply's streamed 16-bit mono PCM on the voice-communication
 * stream, so the speaker/earpiece switch applies and the echo canceller hears
 * it. `iris/pcm_out`: start {sampleRate}, feed {pcm}, end (answers once all of
 * it has been heard), stop (silence at once).
 */
class PcmOutChannel(messenger: BinaryMessenger) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, "iris/pcm_out")
    private val main = Handler(Looper.getMainLooper())
    private var player: Player? = null

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> {
                player?.stop()
                player = try {
                    Player(call.argument<Int>("sampleRate") ?: 24000)
                } catch (e: Exception) {
                    result.error("start", e.message, null)
                    return
                }
                result.success(null)
            }
            "feed" -> {
                call.argument<ByteArray>("pcm")?.let { player?.feed(it) }
                result.success(null)
            }
            "end" -> {
                val current = player
                if (current == null) result.success(null)
                else current.end { main.post { result.success(null) } }
            }
            "stop" -> {
                player?.stop()
                player = null
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    fun dispose() {
        player?.stop()
        player = null
        channel.setMethodCallHandler(null)
    }

    private sealed class Item {
        class Pcm(val bytes: ByteArray) : Item()
        class End(val done: () -> Unit) : Item()
        object Wake : Item()
    }

    /** One reply's track and the thread that writes to it. */
    private class Player(private val sampleRate: Int) {
        private val queue = LinkedBlockingQueue<Item>()
        private val lock = Object()
        @Volatile private var stopped = false
        private var released = false
        private val bufferBytes: Int
        private val track: AudioTrack

        init {
            val min = AudioTrack.getMinBufferSize(
                sampleRate, AudioFormat.CHANNEL_OUT_MONO, AudioFormat.ENCODING_PCM_16BIT,
            )
            // About 200 ms: enough to ride out network jitter, short enough
            // that a barge-in's flush is not noticeably late.
            bufferBytes = max(min, sampleRate / 5 * 2)
            track = AudioTrack.Builder()
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                        .build(),
                )
                .setAudioFormat(
                    AudioFormat.Builder()
                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                        .setSampleRate(sampleRate)
                        .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                        .build(),
                )
                .setTransferMode(AudioTrack.MODE_STREAM)
                .setBufferSizeInBytes(bufferBytes)
                .build()
            track.play()
            Thread(::loop, "iris-pcm-out").start()
        }

        fun feed(bytes: ByteArray) {
            if (!stopped) queue.put(Item.Pcm(bytes))
        }

        fun end(done: () -> Unit) {
            if (stopped) done() else queue.put(Item.End(done))
        }

        fun stop() {
            stopped = true
            synchronized(lock) {
                if (!released) {
                    // pause() also wakes a write() blocked on a full buffer.
                    track.pause()
                    track.flush()
                }
            }
            val left = ArrayList<Item>()
            queue.drainTo(left)
            left.forEach { if (it is Item.End) it.done() }
            queue.put(Item.Wake)
        }

        private fun loop() {
            var frames = 0L
            try {
                while (!stopped) {
                    when (val item = queue.take()) {
                        is Item.Pcm -> {
                            write(item.bytes)
                            frames += item.bytes.size / 2
                        }
                        is Item.End -> {
                            // A track does not start until its buffer has
                            // filled once; silence pushes a short reply out.
                            write(ByteArray(bufferBytes))
                            awaitPlayed(frames)
                            item.done()
                        }
                        Item.Wake -> {}
                    }
                }
            } finally {
                synchronized(lock) {
                    released = true
                    track.release()
                }
                val left = ArrayList<Item>()
                queue.drainTo(left)
                left.forEach { if (it is Item.End) it.done() }
            }
        }

        private fun write(bytes: ByteArray) {
            var offset = 0
            while (offset < bytes.size && !stopped) {
                val n = track.write(bytes, offset, bytes.size - offset)
                if (n <= 0) break
                offset += n
            }
        }

        private fun awaitPlayed(frames: Long) {
            // Generous: the audio's own length plus two seconds.
            val deadline = System.currentTimeMillis() + frames * 1000 / sampleRate + 2000
            while (!stopped && System.currentTimeMillis() < deadline) {
                val head = track.playbackHeadPosition.toLong() and 0xFFFFFFFFL
                if (head >= frames) return
                Thread.sleep(10)
            }
        }
    }
}
