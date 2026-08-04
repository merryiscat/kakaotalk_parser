# -*- coding: utf-8 -*-
"""
티스토리 발행 로컬 테스트 스크립트

서버 배포 전에 tistory_service.publish_post()를 로컬에서 직접 실행해
제목·본문·태그가 실제로 들어가는지 확인합니다.
(실제 블로그에 짧은 테스트 글이 공개 발행되므로, 확인 후 삭제하세요)

사용법:
  cd tokbiseo-server
  uv run python scripts/test_publish_local.py
"""
import asyncio
import io
import os
import sys
from pathlib import Path

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")

_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(_ROOT))

# .env를 직접 파싱해 환경변수로 주입 (셸 인코딩을 타지 않음)
for line in (_ROOT / ".env").read_text(encoding="utf-8").splitlines():
    line = line.strip()
    if line and not line.startswith("#") and "=" in line:
        k, v = line.split("=", 1)
        os.environ.setdefault(k, v.strip())

from app.services.tistory_service import publish_post  # noqa: E402

TEST_MARKDOWN = """## 발행 테스트

이 글은 톡비서 발행 파이프라인 테스트용입니다. 확인 후 삭제해 주세요.

- 본문 주입 확인
- **굵은 글씨** 확인

> 인용문 확인
"""


async def main():
    result = await publish_post(
        title="톡비서 발행 테스트 (삭제 예정)",
        markdown=TEST_MARKDOWN,
        tags=["테스트"],
    )
    print("결과:", result)


asyncio.run(main())
