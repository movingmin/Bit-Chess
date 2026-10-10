"""Bit-Chess 효과음 생성기. 나무 말을 판에 놓는 '똑' 소리를 직접 합성한다(외부 음원 없음).

실행: python scripts/gen_sounds.py  ->  android/app/src/main/res/raw/*.wav
소리를 바꾸려면 아래 숫자(주파수·감쇠)를 조정하고 다시 실행한다.
"""

import wave
from pathlib import Path

import numpy as np

SR = 44100
OUT = Path(__file__).resolve().parent.parent / "android/app/src/main/res/raw"
rng = np.random.default_rng(7)  # 매번 같은 결과


def t(sec):
    return np.arange(int(SR * sec)) / SR


def knock(pitch=1.0, sec=0.18, bright=1.0):
    """나무 '똑': 짧은 노이즈 타격 + 빨리 사라지는 공명 몇 개."""
    x = t(sec)
    body = sum(
        a * np.sin(2 * np.pi * f * pitch * x) * np.exp(-x * d)
        for f, a, d in [(420, 1.0, 38), (1180, 0.55, 60), (2350, 0.3 * bright, 90)]
    )
    click = rng.standard_normal(x.size) * np.exp(-x * 900) * 0.6 * bright
    return body + click


def chime(freqs, sec=0.6):
    x = t(sec)
    return sum(np.sin(2 * np.pi * f * x) * np.exp(-x * 7) * (0.6 ** i) for i, f in enumerate(freqs))


def seq(*parts):
    """(소리, 시작초) 목록을 섞는다."""
    end = max(int(s * SR) + p.size for p, s in parts)
    y = np.zeros(end)
    for p, s in parts:
        i = int(s * SR)
        y[i : i + p.size] += p
    return y


def save(name, y):
    y = y / np.max(np.abs(y)) * 0.9
    fade = min(400, y.size)
    y[-fade:] *= np.linspace(1, 0, fade)
    OUT.mkdir(parents=True, exist_ok=True)
    with wave.open(str(OUT / f"{name}.wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((y * 32767).astype("<i2").tobytes())


save("move", knock())
save("capture", seq((knock(1.15, bright=1.6), 0), (knock(0.85, 0.2), 0.045)))  # 두 번 겹친 '딱'
save("check", seq((knock(), 0), (chime([1320, 2640], 0.35) * 0.5, 0.03)))
save("end", seq((chime([523, 1046]), 0), (chime([784, 1568]), 0.16)))

if __name__ == "__main__":
    print("written:", sorted(p.name for p in OUT.glob("*.wav")))
