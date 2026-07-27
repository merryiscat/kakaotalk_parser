# ============================================================
# 톡비서 멀티에이전트 서버 — Docker 이미지 빌드
#
# 멀티스테이지 빌드:
#   1단계(builder): uv로 의존성 설치
#   2단계(runtime): 실행에 필요한 것만 복사하여 이미지 경량화
# ============================================================

# ── 1단계: 의존성 설치 (builder) ──
FROM python:3.13-slim AS builder

# uv 설치 (pip 대신 사용하는 빠른 Python 패키지 관리자)
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

WORKDIR /build

# 가상환경을 최종 경로(/app/.venv)에 직접 생성
# → runtime으로 복사해도 스크립트 내부 경로가 깨지지 않음
ENV UV_PROJECT_ENVIRONMENT=/app/.venv

# 의존성 파일만 먼저 복사 (Docker 캐시 활용 — 코드 변경 시 재설치 방지)
COPY pyproject.toml uv.lock ./

# 의존성 설치
RUN uv sync --frozen --no-dev --no-install-project

# 소스 코드 복사
COPY . .

# 프로젝트 자체를 설치 (app 패키지 인식용)
RUN uv sync --frozen --no-dev


# ── 2단계: 실행 환경 (runtime) ──
FROM python:3.13-slim AS runtime

# 한국 시간대 설정
ENV TZ=Asia/Seoul
RUN ln -sf /usr/share/zoneinfo/Asia/Seoul /etc/localtime

# 보안: root가 아닌 일반 사용자로 실행
RUN groupadd --gid 1000 tokbiseo && \
    useradd --uid 1000 --gid tokbiseo --create-home tokbiseo

WORKDIR /app

# 로그 디렉토리 생성 (볼륨 마운트 시 권한 보장)
RUN mkdir -p /app/logs && chown tokbiseo:tokbiseo /app/logs

# builder에서 가상환경과 소스 코드만 복사 (빌드 도구는 제외)
# 가상환경이 이미 /app/.venv 경로로 만들어져 있으므로 그대로 복사
COPY --from=builder /app/.venv /app/.venv
COPY --from=builder /build/app ./app

# 가상환경의 Python을 기본으로 사용
ENV PATH="/app/.venv/bin:$PATH"

# Docker에서는 환경변수를 docker-compose.yml의 env_file로 주입
# Python 출력 버퍼링 끄기 (로그가 즉시 출력되도록)
ENV PYTHONUNBUFFERED=1

# 포트 노출 (톡비서 서버 기본 포트)
EXPOSE 3936

# 일반 사용자로 전환
USER tokbiseo

# 서버 실행
# --host 0.0.0.0 : 컨테이너 외부에서 접근 가능
# --port 3936    : 톡비서 서버 포트
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "3936"]
