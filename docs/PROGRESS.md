# 진행 상황

| 단계 | 내용 | 상태 |
|---|---|---|
| 0 | 저장소·보안 기반 | 진행 중 (사용자 검증 대기) |
| 1 | 체스 핵심 (Pass & Play·기보) | 대기 |
| 2 | BLE 기술 검증 (관문) | 대기 |
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
