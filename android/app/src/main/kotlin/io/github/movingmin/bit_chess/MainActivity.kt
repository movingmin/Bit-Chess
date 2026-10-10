package io.github.movingmin.bit_chess

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.ToneGenerator
import android.os.Build
import android.os.VibrationAttributes
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// 효과음은 기기 내장 톤(음원 파일·라이선스 없음), 진동은 Vibrator 직접 호출.
// 시스템 "터치음/터치 진동" 설정이 꺼져 있어도 동작한다. 소리 크기는 미디어 볼륨.
class MainActivity : FlutterActivity() {
    private val tonesLazy = lazy { ToneGenerator(AudioManager.STREAM_MUSIC, 80) }

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
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "bitchess/feedback").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "tone" -> {
                        val (tone, ms) = when (call.arguments as String) {
                            "capture" -> ToneGenerator.TONE_PROP_ACK to 120
                            "check" -> ToneGenerator.TONE_PROP_BEEP2 to 200
                            "end" -> ToneGenerator.TONE_CDMA_ALERT_CALL_GUARD to 400
                            else -> ToneGenerator.TONE_PROP_BEEP to 60 // move
                        }
                        tonesLazy.value.startTone(tone, ms)
                        result.success(null)
                    }
                    "vibrate" -> {
                        vibrate((call.arguments as Int).toLong())
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: RuntimeException) {
                // 오디오 장치가 바쁘면 ToneGenerator 생성이 실패할 수 있다. 대국은 계속한다.
                result.error("feedback", e.message, null)
            }
        }
    }

    override fun onDestroy() {
        if (tonesLazy.isInitialized()) tonesLazy.value.release()
        super.onDestroy()
    }
}
