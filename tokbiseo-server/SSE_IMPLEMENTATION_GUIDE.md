# SSE 스트리밍 구현 가이드

## 배경
`POST /api/summarize` 파이프라인이 4~10분 소요되어 Flutter 앱에서 TimeoutException 발생.
SSE(Server-Sent Events)로 진행 상황을 실시간 스트리밍하여 연결 유지 + 진행률 표시.

---

## 1. 서버 설정

### 1-1. 의존성 추가

```bash
cd tokbiseo-server
uv add sse-starlette
```

### 1-2. SSE 엔드포인트

서버에 `POST /api/summarize-stream` 엔드포인트가 이미 구현되어 있습니다.
기존 `POST /api/summarize`도 그대로 유지됩니다 (하위 호환).

---

## 2. SSE 이벤트 형식

### 진행 이벤트 (노드 하나 완료될 때마다)
```
event: node_complete
data: {"node":"analyst","display_name":"대화 분석","step":1,"total_steps":8,...}
```

> `input_tokens`/`output_tokens`는 **파이프라인 전체 누적값**입니다.

### 최종 결과 (파이프라인 완료)
```
event: result
data: {"summary":"## 주제 키워드\n\n...","input_tokens":17300,"output_tokens":3800}
```

### 에러
```
event: error
data: {"detail":"파이프라인 실행 중 오류: ..."}
```

### Keep-alive (30초마다 자동, 앱에서 무시)
```
: ping
```

---

## 3. 노드 실행 순서

> web_searcher + yt_searcher, web_validator + yt_validator는 **병렬 실행**됩니다.
> step 번호는 완료 순서에 따라 달라질 수 있으며, 총 노드 수(8개)만 보장됩니다.

| Step | 노드 | 한글명 | 설명 | 비고 |
|------|-------|--------|------|------|
| 1 | analyst | 대화 분석 | 대화 내용 분석 | 순차 |
| 2 | supervisor | 조사 계획 | 검색 필요 여부 판단 | 순차 |
| 3~4 | web_searcher | 웹 검색 | 웹 자료 수집 | **병렬** |
| 3~4 | yt_searcher | 유튜브 검색 | 유튜브 자료 수집 | **병렬** |
| 5~6 | web_validator | 웹 검증 | 검색 결과 검증 | **병렬** |
| 5~6 | yt_validator | 유튜브 검증 | 검색 결과 검증 | **병렬** |
| 7 | writer | 리포트 작성 | 최종 리포트 생성 | 순차 |
| 8 | reviewer | 리포트 검토 | 품질 검토 (PASS/REVISE) | 순차 |
| 9* | writer | 리포트 재작성 | REVISE 시에만 | 순차 |
| 10* | reviewer | 리포트 재검토 | REVISE 시에만 | 순차 |

*Step 9~10은 reviewer가 REVISE 판정 시에만 실행됨

---

## 4. 서버 빌드 & 테스트

### 서버 실행하기

1. 터미널(명령 프롬프트)을 열고 서버 폴더로 이동합니다:
   ```bash
   cd tokbiseo-server
   ```

2. 서버를 실행합니다:
   ```bash
   uv run uvicorn app.main:app --reload --host 0.0.0.0 --port 3936
   ```

3. 서버가 정상 실행되면 `http://localhost:3936/health` 에 접속해서 `{"status":"ok"}`가 보이는지 확인합니다.

### SSE 엔드포인트 테스트 (선택사항)

curl로 SSE 스트리밍이 동작하는지 확인할 수 있습니다:
```bash
curl -N -X POST http://localhost:3936/api/summarize-stream \
  -H "Content-Type: application/json" \
  -d '{"messages":"[14:30] 테스터: 테스트 메시지","url_titles":{},"openai_api_key":"sk-..."}'
```

`event: node_complete` 이벤트가 하나씩 출력되면 정상입니다.

---

## 5. 앱 연동 (완료)

톡비서 앱은 v2.0.1부터 SSE 스트리밍을 지원합니다:
- `lib/services/agent_api_service.dart` — `summarizeStream()` 메서드
- `lib/providers/digest_provider.dart` — 노드별 진행률 상태 관리
- `lib/screens/home_screen.dart`, `room_detail_screen.dart` — 확정 프로그레스바 + 노드명 표시
- SSE 실패 시 기존 `POST /api/summarize`로 자동 폴백
