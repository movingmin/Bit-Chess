# Bit-Chess

인터넷·와이파이 없이 **블루투스(BLE)만으로** 옆자리 두 Android 폰이 1:1로 두는 체스 앱입니다.
비행기 모드에서 블루투스만 켠 상태에서 쓰는 것을 목표로 합니다. 서버·계정·광고·분석 SDK가 없습니다.

> 개발 중입니다. 단계별 진행 상황은 [docs/PROGRESS.md](docs/PROGRESS.md), 사양은 [docs/SPEC.md](docs/SPEC.md)에 있습니다.

## 개발 환경

- Flutter stable, Android SDK (Android 전용. iOS는 설계만 열어 둠)
- Windows 11 + PowerShell 기준
- BLE는 에뮬레이터에서 시험할 수 없어 실기기 Android 2대로 시험합니다.

```powershell
flutter pub get
flutter run -d <기기ID>     # 기기ID: flutter devices
flutter analyze
flutter test
```

## 비밀 유출 방지 (pre-commit 훅)

커밋할 때마다 [gitleaks](https://github.com/gitleaks/gitleaks)가 staged 변경을 검사합니다. clone 후 한 번 실행하세요.

```powershell
winget install --id Gitleaks.Gitleaks
git config core.hooksPath scripts/hooks
```

훅 스크립트는 `scripts/hooks/pre-commit`에 있습니다. CI(GitHub Actions)에서도 analyze, test, gitleaks(전체 히스토리)를 돌립니다.

## 보안

취약점 제보와 저장소 보안 설정은 [SECURITY.md](SECURITY.md)를 보세요.

## 라이선스

[GPL-3.0](LICENSE). 나중에 Stockfish(GPLv3)를 넣을 수 있도록 GPL-3.0을 씁니다.
