package com.ifallmusic.app

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.min
import kotlin.math.sin

/**
 * IfallMusic real-time spatial (8D) audio processor — native DSP core.
 *
 * The processor converts an interleaved 16-bit stereo PCM stream into an 8D
 * signal with three stages, all running inside the audio callback (no
 * allocation, no locking):
 *
 *  1. **Low-frequency oscillator panning**
 *     `pan(t) = sin(2π · f · t)` with `f` between 0.03 Hz and 0.5 Hz.
 *     Equal-power gains follow: `left = cos(θ)`, `right = sin(θ)` where
 *     `θ = (pan + 1) · π/4`, so loudness stays constant while the image orbits.
 *     A 1-pole smoother on the gains removes zipper noise at block edges.
 *
 *  2. **Stereo width / depth**
 *     Mid/side matrix. `side` is scaled by `1 + width`, `mid` is pulled back by
 *     `depth · 0.15` — this is what makes the sound feel *around* the listener
 *     instead of in front of them.
 *
 *  3. **Early-reflection reverb**
 *     Three prime-numbered combs (2 113 / 2 713 / 3 371 samples ≈ 48 / 61 / 76 ms
 *     at 44.1 kHz) plus one 4 093-sample all-pass diffuser. A Hall-style
 *     feedback of 0.72 keeps the tail short enough for music (no smear).
 *
 * ### Where it is used
 * This class is the sample-accurate engine. It is fed by the platform player
 * through an `AudioProcessor` (AndroidX Media3 / ExoPlayer) or by Oboe/AAudio
 * when the app drives the output itself:
 *
 * ```kotlin
 * // Media3 / ExoPlayer (recommended, what just_audio uses under the hood)
 * val factory = SpatialAudioProcessorFactory(processor)
 * val exoPlayer = ExoPlayer.Builder(context)
 *     .setAudioSink(DefaultAudioSink.Builder().setAudioProcessors(arrayOf(factory)).build())
 *     .build()
 *
 * // Oboe / AAudio (lowest latency, own engine)
 * val stream = AudioStreamBuilder()
 *     .setDataCallback(SpatialOboeCallback(processor))
 *     .setFormat(AudioFormat.Float)
 *     .setChannelCount(2)
 *     .build()
 * ```
 *
 * `SaxifyBridge` additionally exposes the same three parameters to Android's
 * system effects ([android.media.audiofx.Virtualizer] +
 * [android.media.audiofx.EnvironmentalReverb]) so the effect is audible on the
 * stock player without touching its pipeline.
 *
 * ### Suggested libraries / plugins
 * | Need | Android / Flutter |
 * | --- | --- |
 * | Insert into the player pipeline | **AndroidX Media3 `AudioProcessor`** (ExoPlayer) |
 * | Lowest latency output | **Oboe** (C++) / **AAudio** (NDK) |
 * | Pro DSP + 3D panner | **Superpowered SDK**, **Sonic** (pitch/speed), **Rubber Band** |
 * | System-level spatial | `Virtualizer`, `EnvironmentalReverb`, `PresetReverb`, `DynamicsProcessing` |
 * | Flutter side | `just_audio` (`AudioPipeline`), `flutter_soloud` (true 3D/pan), `audio_service` |
 *
 * All of it is deterministic and testable: [render] never allocates.
 */
class SpatialAudioProcessor(sampleRate: Int = 44_100) {

    /** Orbit speed in Hz (0.03 … 0.5). */
    @Volatile
    var rotationHz: Double = 0.12
        set(value) {
            field = value.coerceIn(0.0, 0.6)
        }

    /** How far the image swings: 0 = centre, 1 = hard left/right. */
    @Volatile
    var depth: Double = 0.9
        set(value) {
            field = value.coerceIn(0.0, 1.0)
        }

    /** Wet/dry mix of the early-reflection tail. */
    @Volatile
    var reverbMix: Double = 0.30
        set(value) {
            field = value.coerceIn(0.0, 1.0)
        }

    /** Extra stereo widening. */
    @Volatile
    var width: Double = 0.35
        set(value) {
            field = value.coerceIn(0.0, 1.0)
        }

    private val rate: Double = sampleRate.toDouble()

    // ------------------------------------------------------------- comb delays
    private val combSizes = intArrayOf(2113, 2713, 3371)
    private val combs = Array(combSizes.size) { FloatArray(combSizes[it]) }
    private val combIndex = IntArray(combSizes.size)
    private val combFeedback = 0.72f

    private val allPassSize = 4093
    private val allPass = FloatArray(allPassSize)
    private var allPassIndex = 0
    private val allPassGain = 0.5f

    private var phase = 0.0
    private var smoothedLeft = 1f
    private var smoothedRight = 1f
    private val smoothing = 0.02f

    /** Current pan position, -1 (left) … +1 (right). Used by the UI meter. */
    fun currentPan(): Double = sin(phase) * depth

    /**
     * Processes one block of **interleaved 16-bit stereo PCM in place**.
     *
     * @param buffer the sample block written by the decoder.
     * @param frames number of stereo frames available in [buffer].
     */
    fun render(buffer: ShortArray, frames: Int) {
        if (frames <= 0) return
        val d = depth
        val mix = reverbMix
        val w = width
        val phaseStep = (2.0 * PI * rotationHz) / rate

        for (frame in 0 until frames) {
            val i = frame * 2
            if (i + 1 >= buffer.size) break

            // ---- 1. mid/side split -------------------------------------
            val l = buffer[i].toFloat() / 32768f
            val r = buffer[i + 1].toFloat() / 32768f
            val mid = (l + r) * 0.5f
            val side = (l - r) * (0.5f + w.toFloat())

            // ---- 2. orbit -------------------------------------------------
            phase += phaseStep
            if (phase > 2.0 * PI) phase -= 2.0 * PI
            val pan = sin(phase) * d
            val theta = (pan + 1.0) * (PI / 4.0)
            val targetLeft = cos(theta).toFloat()
            val targetRight = sin(theta).toFloat()
            smoothedLeft += (targetLeft - smoothedLeft) * smoothing
            smoothedRight += (targetRight - smoothedRight) * smoothing

            var outL = (mid * (1f - 0.15f * d.toFloat()) + side) * smoothedLeft
            var outR = (mid * (1f - 0.15f * d.toFloat()) - side) * smoothedRight

            // ---- 3. early reflections ------------------------------------
            if (mix > 0.001f) {
                val dry = 1f - mix.toFloat() * 0.45f
                var wet = 0f
                for (c in combs.indices) {
                    val idx = combIndex[c]
                    val delayed = combs[c][idx]
                    combs[c][idx] = (outL + outR) * 0.5f + delayed * combFeedback
                    combIndex[c] = if (idx + 1 >= combs[c].size) 0 else idx + 1
                    wet += delayed
                }
                wet /= combs.size
                // one all-pass diffuser for a smoother tail
                val apDelayed = allPass[allPassIndex]
                val apInput = wet + allPassGain * apDelayed
                allPass[allPassIndex] = apInput
                allPassIndex = if (allPassIndex + 1 >= allPassSize) 0 else allPassIndex + 1
                wet = apDelayed - allPassGain * apInput

                outL = outL * dry + wet * mix.toFloat()
                outR = outR * dry + wet * mix.toFloat()
            }

            buffer[i] = clampToPcm(outL)
            buffer[i + 1] = clampToPcm(outR)
        }
    }

    private fun clampToPcm(value: Float): Short {
        val scaled = value * 32767f
        if (scaled > 32767f) return Short.MAX_VALUE
        if (scaled < -32768f) return Short.MIN_VALUE
        return scaled.toInt().toShort()
    }

    /** Clears every delay line (call on pause / track change). */
    fun reset() {
        phase = 0.0
        smoothedLeft = 1f
        smoothedRight = 1f
        allPassIndex = 0
        allPass.fill(0f)
        for (c in combs.indices) {
            combs[c].fill(0f)
            combIndex[c] = 0
        }
    }

    /** 0 … 1 progress of one full orbit — handy for a visualisation. */
    fun orbitFraction(): Double {
        if (rotationHz <= 0.0) return 0.0
        val circle = 2.0 * PI
        return abs((phase % circle) / circle)
    }

    /** True when the parameters are effectively bypassed. */
    fun isBypassed(): Boolean = depth < 0.01 && reverbMix < 0.01 && width < 0.01

    /** Latency introduced by the comb filters, in seconds. */
    fun latencySeconds(): Double = min(combs[0].size, allPassSize) / rate
}
