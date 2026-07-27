"""
Notion 서비스 — OAuth 토큰 교환 + 데이터베이스에 리포트 페이지 생성

1. OAuth 콜백으로 access token 발급 → .env에 자동 저장
2. 파이프라인 완료 후 리포트를 Notion 데이터베이스에 자동 저장

.env 필요 항목:
- NOTION_CLIENT_ID, NOTION_CLIENT_SECRET: OAuth 앱 정보
- NOTION_ACCESS_TOKEN: 발급된 토큰 (콜백으로 자동 저장)
- NOTION_DATABASE_ID: 저장 대상 데이터베이스
"""

import os
import re
import logging
import base64
from pathlib import Path
import httpx

logger = logging.getLogger("톡비서.notion")

NOTION_VERSION = "2022-06-28"
NOTION_API_BASE = "https://api.notion.com/v1"

# .env 파일 경로
_env_path = Path(__file__).resolve().parent.parent.parent / ".env"


async def exchange_code_for_token(code: str) -> dict:
    """
    OAuth authorization code를 access token으로 교환하고 .env에 저장.

    Returns:
        {"access_token": "ntn_...", ...} 또는 {"error": "에러 메시지"}
    """
    client_id = os.getenv("NOTION_CLIENT_ID", "")
    client_secret = os.getenv("NOTION_CLIENT_SECRET", "")
    redirect_uri = os.getenv(
        "NOTION_REDIRECT_URI",
        "http://localhost:3936/auth/notion/callback",
    )

    if not client_id or not client_secret:
        return {"error": "NOTION_CLIENT_ID/NOTION_CLIENT_SECRET가 .env에 설정되지 않았습니다."}

    credentials = base64.b64encode(
        f"{client_id}:{client_secret}".encode()
    ).decode()

    async with httpx.AsyncClient() as client:
        try:
            resp = await client.post(
                f"{NOTION_API_BASE}/oauth/token",
                headers={
                    "Authorization": f"Basic {credentials}",
                    "Content-Type": "application/json",
                    "Notion-Version": NOTION_VERSION,
                },
                json={
                    "grant_type": "authorization_code",
                    "code": code,
                    "redirect_uri": redirect_uri,
                },
                timeout=15,
            )
            if resp.status_code == 200:
                data = resp.json()
                access_token = data.get("access_token", "")

                # .env에 토큰 저장 + 환경변수에도 반영
                if access_token:
                    _save_to_env("NOTION_ACCESS_TOKEN", access_token)
                    os.environ["NOTION_ACCESS_TOKEN"] = access_token
                    logger.info("Notion access token 발급 및 .env 저장 완료")

                return data
            else:
                detail = resp.json().get("error_description", resp.text)
                return {"error": f"토큰 교환 실패: {detail}"}
        except Exception as e:
            return {"error": f"토큰 교환 중 오류: {e}"}


def _save_to_env(key: str, value: str):
    """
    .env 파일에 key=value를 추가하거나 업데이트.
    파일이 없으면 생성합니다.
    """
    lines = []
    found = False

    if _env_path.exists():
        lines = _env_path.read_text(encoding="utf-8").splitlines()
        for i, line in enumerate(lines):
            if line.startswith(f"{key}=") or line.startswith(f"# {key}="):
                lines[i] = f"{key}={value}"
                found = True
                break

    if not found:
        lines.append(f"{key}={value}")

    _env_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


async def save_report_to_notion(
    access_token: str,
    database_id: str,
    title: str,
    report_markdown: str,
) -> dict:
    """
    Notion 데이터베이스에 리포트 페이지를 생성합니다.

    Args:
        access_token: Notion OAuth access token
        database_id: 저장할 데이터베이스 ID
        title: 페이지 제목 (예: "방이름 — 2026-03-10")
        report_markdown: 최종 마크다운 리포트

    Returns:
        {"url": "https://notion.so/..."} 또는
        {"error": "에러 메시지"}
    """
    blocks = _markdown_to_notion_blocks(report_markdown)

    # Notion API 제한: 한 번에 최대 100개 블록
    if len(blocks) > 100:
        blocks = blocks[:100]

    payload = {
        "parent": {"database_id": database_id},
        "properties": {
            "title": {
                "title": [{"text": {"content": title}}],
            },
        },
        "children": blocks,
    }

    headers = {
        "Authorization": f"Bearer {access_token}",
        "Content-Type": "application/json",
        "Notion-Version": NOTION_VERSION,
    }

    async with httpx.AsyncClient() as client:
        try:
            resp = await client.post(
                f"{NOTION_API_BASE}/pages",
                headers=headers,
                json=payload,
                timeout=30,
            )
            if resp.status_code == 200:
                url = resp.json().get("url", "")
                logger.info(f"Notion 페이지 생성 완료: {url}")
                return {"url": url}
            else:
                detail = resp.json().get("message", resp.text)
                logger.error(f"Notion 페이지 생성 실패: {detail}")
                return {"error": f"Notion API 오류: {detail}"}
        except Exception as e:
            logger.error(f"Notion 저장 중 오류: {e}")
            return {"error": f"Notion 저장 중 오류: {e}"}


def _markdown_to_notion_blocks(markdown: str) -> list[dict]:
    """마크다운을 Notion 블록 리스트로 변환."""
    blocks = []
    lines = markdown.split("\n")
    i = 0

    while i < len(lines):
        line = lines[i]
        stripped = line.strip()

        # 빈 줄 스킵
        if not stripped:
            i += 1
            continue

        # ## 헤딩 2
        if stripped.startswith("## "):
            blocks.append(_heading2(stripped[3:].strip()))
            i += 1
            continue

        # ### 헤딩 3
        if stripped.startswith("### "):
            blocks.append(_heading3(stripped[4:].strip()))
            i += 1
            continue

        # > 인용문
        if stripped.startswith("> "):
            blocks.append(_quote(stripped[2:].strip()))
            i += 1
            continue

        # - 또는 * 리스트
        if stripped.startswith("- ") or stripped.startswith("* "):
            blocks.append(_bulleted_list_item(stripped[2:]))
            i += 1
            continue

        # 번호 리스트
        num_match = re.match(r"^\d+\.\s+(.+)$", stripped)
        if num_match:
            blocks.append(_numbered_list_item(num_match.group(1)))
            i += 1
            continue

        # 일반 텍스트 — 연속된 줄을 하나의 paragraph로 합치기
        para_lines = [stripped]
        i += 1
        while i < len(lines):
            next_line = lines[i].strip()
            if (
                not next_line
                or next_line.startswith("## ")
                or next_line.startswith("### ")
                or next_line.startswith("> ")
                or next_line.startswith("- ")
                or next_line.startswith("* ")
                or re.match(r"^\d+\.\s+", next_line)
            ):
                break
            para_lines.append(next_line)
            i += 1

        blocks.append(_paragraph(" ".join(para_lines)))

    return blocks


def _parse_rich_text(text: str) -> list[dict]:
    """**bold** 와 [text](url) 패턴을 Notion rich_text로 변환."""
    rich_texts = []
    pattern = re.compile(r"\*\*(.+?)\*\*|\[([^\]]+)\]\(([^)]+)\)")
    last_end = 0

    for match in pattern.finditer(text):
        # 매치 앞 일반 텍스트
        if match.start() > last_end:
            plain = text[last_end : match.start()]
            if plain:
                rich_texts.append({"type": "text", "text": {"content": plain}})

        if match.group(1):
            # **bold**
            rich_texts.append({
                "type": "text",
                "text": {"content": match.group(1)},
                "annotations": {"bold": True},
            })
        elif match.group(2) and match.group(3):
            # [text](url)
            rich_texts.append({
                "type": "text",
                "text": {
                    "content": match.group(2),
                    "link": {"url": match.group(3)},
                },
            })

        last_end = match.end()

    # 나머지
    if last_end < len(text):
        remaining = text[last_end:]
        if remaining:
            rich_texts.append({"type": "text", "text": {"content": remaining}})

    if not rich_texts:
        rich_texts.append({"type": "text", "text": {"content": text}})

    return rich_texts


# ── Notion 블록 빌더 ──

def _heading2(text: str) -> dict:
    return {
        "object": "block",
        "type": "heading_2",
        "heading_2": {"rich_text": [{"type": "text", "text": {"content": text}}]},
    }


def _heading3(text: str) -> dict:
    return {
        "object": "block",
        "type": "heading_3",
        "heading_3": {"rich_text": [{"type": "text", "text": {"content": text}}]},
    }


def _paragraph(text: str) -> dict:
    return {
        "object": "block",
        "type": "paragraph",
        "paragraph": {"rich_text": _parse_rich_text(text)},
    }


def _bulleted_list_item(text: str) -> dict:
    return {
        "object": "block",
        "type": "bulleted_list_item",
        "bulleted_list_item": {"rich_text": _parse_rich_text(text)},
    }


def _numbered_list_item(text: str) -> dict:
    return {
        "object": "block",
        "type": "numbered_list_item",
        "numbered_list_item": {"rich_text": _parse_rich_text(text)},
    }


def _quote(text: str) -> dict:
    return {
        "object": "block",
        "type": "quote",
        "quote": {"rich_text": _parse_rich_text(text)},
    }
