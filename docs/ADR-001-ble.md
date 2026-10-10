# ADR-001: BLE 구현 방식

- 날짜: 2026-10-09
- 상태: 채택(2단계 실기기 검증 전)

## 문제

호스트 폰은 GATT 서버를 열고 광고(peripheral)해야 하고, 게스트 폰은 스캔해서 연결(central)해야 한다. Flutter에는 두 역할을 다 지원하는 표준 플러그인이 없다.

## 후보 (pub.dev, 2026-10-09 확인)

| 후보 | 역할 | 라이선스 | 최근 배포 | 비고 |
|---|---|---|---|---|
| flutter_blue_plus 2.3.14 | central만 | pub.dev 표시 `unknown`(자체 라이선스) | 2026-10 | peripheral 불가, 라이선스 검토 필요 |
| bluetooth_low_energy 6.2.1 | 둘 다 | MIT | 2026-01 | 9개월 갱신 없음, 추상화가 커서 MTU·쓰기 큐 제어가 간접적 |
| flutter_ble_peripheral 3.1.0 | 광고 위주 | BSD-3 | 2026-09 | GATT 서버 기능은 확인 필요 |
| ble_peripheral 2.4.0 | peripheral | MIT | 2024-12 | 2년 가까이 갱신 없음 |
| **Kotlin 플랫폼 채널 직접 구현** | 둘 다 | 우리 코드(GPL-3.0) | - | Android 공식 API만 사용 |

## 결정

**Kotlin 플랫폼 채널로 central·peripheral을 모두 직접 구현한다** (`android/.../BleTransport.kt`). Dart 쪽은 `Transport` 인터페이스(`lib/ble/transport.dart`) 뒤에 둔다.

근거:
- 외부 의존성과 라이선스 위험이 없다. 공개 저장소·GPL 앱에 맞다.
- 이 앱에 필요한 건 서비스 1개, 캐릭터리스틱 2개, 연결 1개로 범위가 작다.
- MTU, 쓰기·알림 큐(한 번에 하나), 연결 1개 제한, 광고 중지를 직접 제어할 수 있다. 삼성 기기에서 문제가 나면 원인을 바로 볼 수 있다.
- 효과음·진동도 이미 같은 방식(MethodChannel)이다.

대가: iOS는 Swift로 따로 구현해야 한다(`Transport`가 그 자리). Android API 버전별 분기(12+ 권한, 13+ 새 write/notify API)를 직접 관리한다.

## 설계 요약

- 서비스 UUID `6b1f0001-6a52-4c8e-9a3e-2f2b3c4d5e60`, 게스트→호스트 `…0002`(write with response), 호스트→게스트 `…0003`(notify).
- 광고: 서비스 UUID. 스캔 응답: 제조사 데이터 = 회사 번호 2바이트 + 세션 랜덤 방 ID 4바이트 + 시간 프리셋 1바이트 + 방 이름(UTF-8 최대 22바이트). 기기 고유 ID는 넣지 않는다. (2026-10-10 변경, 3단계에서 구현. 2단계 코드는 아직 서비스 데이터 = 방 ID 4 + 방 이름 9바이트)
- 연결: 게스트가 MTU 517 요청 → 서비스 탐색 → notify 구독. 조각 크기 = min(MTU−3, 512).
- 메시지 쪼개기·합치기는 Dart(`lib/ble/framing.dart`)에서 한다. 조각 헤더 5바이트: 메시지 번호(1), 조각 번호(2), 조각 수(2).
- 호스트는 연결 1개만 받고 나머지는 즉시 끊는다. 연결되면 광고를 멈추고, 끊기면 다시 광고한다.

## 막히면

삼성 기기에서 광고·GATT 서버가 불안정하면 억지로 진행하지 않고 대안(Wi-Fi Direct, Nearby Connections 오프라인 모드 등)을 비교해 보고한다.
