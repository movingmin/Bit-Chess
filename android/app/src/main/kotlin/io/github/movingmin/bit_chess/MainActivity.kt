package io.github.movingmin.bit_chess

import android.content.Context
import android.media.AudioManager
import android.media.ToneGenerator
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// 효과음은 기기 내장 톤(음원 파일·라이선스 없음), 진동은 Vibrator 직접 호출.
// 시스템 "터치음/터치 진동" 설정이 꺼져 있어도 동작한다. 소리 크기는 미디어 볼륨.
class MainActivity : FlutterActivity() {
    private val tones by lazy { ToneGenerator(AudioManager.STREAM_MUSIC, 80) }

    private val vibrator: Vibrator by lazy {
        if (Build.VERSION.SDK_INT >= 31) {
            (getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager).defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "bitchess/feedback").setMethodCallHandler { call, result ->
            when (call.method) {
                "tone" -> {
                    val (tone, ms) = when (call.arguments as String) {
                        "capture" -> ToneGenerator.TONE_PROP_ACK to 120
                        "check" -> ToneGenerator.TONE_PROP_BEEP2 to 200
                        "end" -> ToneGenerator.TONE_CDMA_ALERT_CALL_GUARD to 400
                        else -> ToneGenerator.TONE_PROP_BEEP to 60 // move
                    }
                    tones.startTone(tone, ms)
                    result.success(null)
                }
                "vibrate" -> {
                    val ms = (call.arguments as Int).toLong()
                    if (Build.VERSION.SDK_INT >= 26) {
                        vibrator.vibrate(VibrationEffect.createOneShot(ms, VibrationEffect.DEFAULT_AMPLITUDE))
                    } else {
                        @Suppress("DEPRECATION")
                        vibrator.vibrate(ms)
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        tones.release()
        super.onDestroy()
    }
}
