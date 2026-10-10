package io.github.movingmin.bit_chess

import android.content.Context
import android.media.AudioAttributes
import android.media.SoundPool
import android.os.Build
import android.os.VibrationAttributes
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// 효과음은 scripts/gen_sounds.py로 직접 합성한 res/raw/*.wav(외부 음원 없음), 진동은 Vibrator 직접 호출.
// 시스템 "터치음/터치 진동" 설정이 꺼져 있어도 동작한다. 소리 크기는 미디어 볼륨.
class MainActivity : FlutterActivity() {
    private val poolLazy = lazy {
        SoundPool.Builder()
            .setMaxStreams(3)
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_GAME)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build(),
            )
            .build()
    }
    private val sounds by lazy {
        val p = poolLazy.value
        mapOf(
            "move" to p.load(this, R.raw.move, 1),
            "capture" to p.load(this, R.raw.capture, 1),
            "check" to p.load(this, R.raw.check, 1),
            "end" to p.load(this, R.raw.end, 1),
        )
    }

    private val vibrator: Vibrator by lazy {
        if (Build.VERSION.SDK_INT >= 31) {
            (getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager).defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        }
    }

    private fun vibrate(ms: Long) {
        when {
            // 용도를 '미디어'로 지정: 삼성은 용도 없는 진동을 터치 진동 설정에 묶어 무시할 수 있다.
            Build.VERSION.SDK_INT >= 33 -> vibrator.vibrate(
                VibrationEffect.createOneShot(ms, VibrationEffect.DEFAULT_AMPLITUDE),
                VibrationAttributes.createForUsage(VibrationAttributes.USAGE_MEDIA),
            )
            Build.VERSION.SDK_INT >= 26 -> @Suppress("DEPRECATION") vibrator.vibrate(
                VibrationEffect.createOneShot(ms, VibrationEffect.DEFAULT_AMPLITUDE),
                AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA).build(),
            )
            else -> @Suppress("DEPRECATION") vibrator.vibrate(ms)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        sounds // 첫 수에서 소리가 빠지지 않게 미리 로드
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "bitchess/feedback").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "tone" -> {
                        sounds[call.arguments as String]?.let { poolLazy.value.play(it, 1f, 1f, 1, 0, 1f) }
                        result.success(null)
                    }
                    "vibrate" -> {
                        vibrate((call.arguments as Int).toLong())
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: RuntimeException) {
                // 오디오 장치 문제로 실패해도 대국은 계속한다.
                result.error("feedback", e.message, null)
            }
        }
        ble = BleTransport(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    private var ble: BleTransport? = null

    override fun onRequestPermissionsResult(code: Int, perms: Array<out String>, grants: IntArray) {
        super.onRequestPermissionsResult(code, perms, grants)
        ble?.onPermissionResult(code, grants)
    }

    override fun onDestroy() {
        ble?.dispose()
        if (poolLazy.isInitialized()) poolLazy.value.release()
        super.onDestroy()
    }
}
