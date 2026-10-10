# 진행 상황

| 단계 | 내용 | 상태 |
|---|---|---|
| 0 | 저장소·보안 기반 | 통과 |
| 1 | 체스 핵심 (Pass & Play·기보) | 통과 |
| 2 | BLE 기술 검증 (관문) | 진행 중 (폰 2대 검증 대기) |
| 3 | 닉네임·방 만들기/찾기·대기실 | 대기 |
| 4 | 암호화·확인 코드·랜덤 색 | 대기 |
| 5 | BLE 대국·시계·기권/무승부/재대국 | 대기 |
| 6 | 채팅 | 대기 |
| 7 | 연결 유지·재연결·복구 | 대기 |
| 8 | 릴리스 빌드·보안 점검 | 대기 |
| 9 | (선택) 엔진 분석 (9a 분석 보드 → 9b 엔진 → 9c 복기) | 대기 |

## 기록

아래에 덧붙이기만 합니다. 기존 항목은 고치지 않습니다.

### 2026-10-09 21:34 — 0단계: 저장소·보안 기반

- 한 일: 빈 저장소 확인(로컬·원격 커밋 0), `flutter create`(Android 전용, `io.github.movingmin.bit_chess`), `.gitignore` 보강, SPEC/PROGRESS/README/SECURITY, GPL-3.0 LICENSE, gitleaks pre-commit 훅(`scripts/hooks`), GitHub Actions CI(analyze·test·gitleaks, `contents: read`, 액션 SHA 고정).
- 매니페스트: main에 INTERNET 없음. debug/profile에만 있음(Flutter 기본).
- 새 패키지: 없음(Flutter 기본 템플릿 의존성만).
- 미확인: CI 초록색(push 전이라 실행 안 됨), GitHub 웹 보안 설정, 훅 차단 시험(사용자 시험 대기).

### 2026-10-09 21:53 — 0단계: 검증 결과 보완

- 훅 차단: 에이전트가 가짜 GitHub PAT로 커밋을 시도해 막히는 것을 확인했다(`github-pat` 규칙). 시험 파일은 커밋하지 않고 지웠다. 사용자 재시험 대기.
- 폰: 디버그 APK 빌드·설치 성공, Flutter 엔진 시작 로그 확인. 화면 표시는 미확인(사용자 검증).
- `flutter analyze`: No issues found. `flutter test`: All tests passed(1개).
- `secret-check.ps1`: 금지 파일 0, gitleaks staged·전체 히스토리 0, 커밋 이메일 noreply, 개인 경로 없음, main INTERNET 없음.
- 보완 커밋: CI Flutter 3.47.7 고정, `.gitignore`에 `Screenshot_*`와 `!test/**/*.pgn` 추가.
- 환경: 첫 빌드 때 Gradle이 Android SDK Build-Tools 36.0.0을 자동 설치했다.
- 미확인: CI 초록색(push 전), GitHub 웹 보안 설정.

### 2026-10-09 21:59 — 0단계: 통과

- 사용자 검증: 통과 — 폰 카운터 앱 동작 확인(사용자). 금지 파일 0, gitleaks 0, main INTERNET 없음, 훅이 가짜 토큰 차단(에이전트 실행).
- GitHub 보안 설정(gh API): Secret scanning·Push protection·Dependabot alerts·security updates·Private vulnerability reporting 켬. main ruleset: 삭제 금지·force push 금지.
- CI: 첫 push 후 `check` 통과(1m42s).
- 남은 것: 필수 상태 검사(required check)는 main 직접 push를 막으므로 걸지 않았다. PR 흐름으로 바꿀 때 추가.

### 2026-10-09 22:28 - 1단계: 체스 핵심 (Pass & Play·기보)

- 한 일: 규칙 dartchess, 보드 chessground(둘 다 lichess, GPL-3.0). 홈(혼자 두기·지난 대국·설정, BLE·분석 보드 자리), 대국 화면(시계 무제한/3/5/10/15+10, 뒤집기, 기권, 합의 무승부), 결과 8종, PGN 자동 저장(중단 포함), 다시보기, 공유 시트 내보내기, 강제 종료 복구.
- 단위 테스트 8개: 메이트·스테일메이트·3회 반복·기물 부족·핀·특수 수 PGN·시계·저장/복구. analyze 깨끗.
- 폰: 디버그 APK 설치·실행 확인(앱 맨 앞 화면). 화면 동작은 미확인(사용자 검증).
- 결정: 상태 관리는 Riverpod 대신 Flutter 기본(StatefulWidget). 화면 하나에 상태가 모여 있어 충분하다. BLE 상태가 여러 화면에 걸치면 그때 다시 본다.
- 한계: 효과음은 시스템 클릭음 하나(이동·잡기·체크·종료 구분 없음). 진동은 잡기·체크·종료에 강하게. 50수·3회 반복은 자동 무승부(Chess.com 방식).
- 첫 빌드 때 Gradle이 Android SDK Platform 35를 자동 설치했다.

### 2026-10-09 23:06 - 1단계: 사용자 검증 통과

- 사용자 검증: 바보의 메이트·앙파상·캐슬링·프로모션·스테일메이트·핀·강제 중지 복구·기보(다시보기·내보내기) 통과(사용자 확인).
- 사용자 요청 반영: 버튼을 보드 바로 아래로(SafeArea, 갤럭시 내비게이션 바 가림 해결), 세로 모드 고정, 잡은 기물·점수 차 표시, 효과음·진동.
- 효과음·진동: 시스템 터치음/터치 진동이 꺼진 폰에서 Flutter 기본 피드백이 안 나 네이티브(SoundPool·Vibrator, 진동 용도 USAGE_MEDIA)로 바꿨다. 효과음은 scripts/gen_sounds.py로 직접 합성(Chess.com 음원은 독점, lichess 기본 음원은 non-free). VIBRATE 권한 추가.
- 자동: analyze 문제 없음, test 10개 통과, gitleaks 0건.

### 2026-10-09 23:58 - 2단계: 개발(폰 1대 + 노트북)

- 한 일: ADR-001(central·peripheral 모두 Kotlin 직접 구현), Transport 인터페이스·Android 구현, 쪼개기·합치기(단위 테스트 5개), 권한 흐름(Android 12+/11 이하, 두 번 거부 시 설정 화면), 블루투스 꺼짐 안내, 디버그 BLE 화면(디버그 빌드 전용).
- 노트북 게스트(scripts/ble_laptop_guest.py, bleak) 시험 — 폰은 호스트: 연결 성공, MTU 517, 노트북→폰 ping 5/5(29~180 ms)·2KB 해시 일치, 폰→노트북 ping 3/3·2KB 3회 수신, 끊긴 뒤 다시 광고·재연결 확인. 권한 거부 → 안내 → 설정에서 허용 후 안내 사라짐(사용자 확인).
- 미확인(폰 2대 필요): 폰 게스트(스캔·연결), 비행기 모드 연결 5/5, 재연결 5/5. 통과 판정은 그때 한다. 3단계는 시작하지 않는다.
- 그 밖: 앱 아이콘(적응형+레거시, 사용자가 직접 만든 이미지).

### 2026-10-10 12:31 - 사양 변경: 방 광고 데이터

- 결정(사용자 승인): 스캔 응답을 서비스 데이터 → 제조사 데이터로 바꿔 방 이름을 9바이트 → 22바이트(한글 7자)로 늘린다. 시간 프리셋 1바이트 추가(255 = 사용자 지정, 세부 값은 ROOM_INFO).
- 목록에서 호스트 닉네임은 뺀다(입장 뒤 HELLO로 받음). 기본 방 이름이 넘치면 닉네임을 잘라 "…의 방".
- 버린 안: 영어만 허용(9자로 여전히 짧음), 방마다 연결해 이름 읽기(연결 1개 규칙과 충돌, 느림).
- 확인 필요: 회사 번호(시험용 0xFFFF)를 배포 앱에 써도 되는지, 두 폰의 BLE 5 확장 광고 지원 여부.
- 반영: SPEC 25·26·45행, ADR-001 35행. 코드는 3단계에서 바꾼다(2단계 미통과).
