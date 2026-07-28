"""
Notion 서비스 — OAuth 토큰 교환 + 데이터베이스에 리포트 페이지 생성

1. OAuth 콜백으로 access token 발급 → .env에 자동 저장
2. 파이프라인 완료 후 리포트를 Notion 데이터베이스에 자동 저장

.env 필요 항목:
- NOTION_CLIENT_ID, NOTION_CLIENT_SECRET: OAuth 앱 정보
- NOTION_ACCESS_TOKEN: 발급된 토큰 (콜백으로 자동 저장)
- NOTION_DATABASE_ID: 저장 대상 데이터베이스

Notion DB 속성(선택):
아래 이름으로 속성을 만들어 두면 자동으로 채워집니다. 만들지 않은 속성은
조용히 건너뛰므로, 필요한 것만 골라 추가하면 됩니다.
- 채팅방 (텍스트 또는 선택)
- 대화일자 (날짜) / 생성일 (날짜)
- 주제 키워드 (다중 선택)
- 메시지수, 입력토큰, 출력토큰 (숫자)
- 발행상태 (선택) — 티스토리 발행 큐로 사용, 기본값 "초안"
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


# ── 메타데이터 → Notion 속성 매핑 ──
#
# 사용자가 Notion 데이터베이스에 실제로 만들어 둔 속성만 채웁니다.
# 없는 속성을 payload에 넣으면 Notion이 400을 반환하고 저장 자체가 실패하므로,
# 페이지를 만들기 전에 DB 스키마를 조회해서 존재하는 속성만 전송합니다.
#
# 같은 의미의 속성을 사용자가 어떤 이름으로 만들었을지 모르기 때문에
# 후보 이름을 여러 개 두고, 그중 타입까지 맞는 속성을 찾아 씁니다.
#   {메타 필드: (후보 속성명, 허용 타입)}
_PROPERTY_CANDIDATES: dict[str, tuple[tuple[str, ...], tuple[str, ...]]] = {
    "room_name": (("채팅방", "방 이름", "방이름", "Room"), ("rich_text", "select")),
    "chat_date": (("대화일자", "대화 일자", "날짜", "Date"), ("date",)),
    "created_at": (("생성일", "생성 일시", "작성일", "Created"), ("date",)),
    "keywords": (("주제 키워드", "키워드", "태그", "Tags"), ("multi_select",)),
    "message_count": (("메시지수", "메시지 수", "Messages"), ("number",)),
    "input_tokens": (("입력토큰", "입력 토큰"), ("number",)),
    "output_tokens": (("출력토큰", "출력 토큰"), ("number",)),
    # 발행 워크플로우용 — 티스토리 발행 대기 큐로 사용
    # status 타입은 API로 새 옵션을 만들 수 없어 select만 허용
    "publish_status": (("발행상태", "발행 상태", "상태"), ("select",)),
}

# DB 스키마 캐시 {database_id: {속성명: 타입}}
# 리포트마다 스키마를 다시 조회하지 않도록 프로세스 수명 동안 재사용합니다.
_schema_cache: dict[str, dict[str, str]] = {}


async def _fetch_database_schema(
    client: httpx.AsyncClient,
    headers: dict,
    database_id: str,
) -> dict[str, str]:
    """
    Notion 데이터베이스의 {속성명: 타입} 맵을 조회합니다.

    조회에 실패하면 빈 dict를 반환합니다.
    이 경우 호출부는 제목만 저장하므로, 스키마를 못 읽어도 리포트는 유실되지 않습니다.
    """
    if database_id in _schema_cache:
        return _schema_cache[database_id]

    try:
        resp = await client.get(
            f"{NOTION_API_BASE}/databases/{database_id}",
            headers=headers,
            timeout=15,
        )
        if resp.status_code != 200:
            detail = resp.json().get("message", resp.text)
            logger.warning(f"Notion DB 스키마 조회 실패 (제목만 저장됩니다): {detail}")
            return {}

        properties = resp.json().get("properties", {})
        schema = {
            name: prop.get("type", "")
            for name, prop in properties.items()
        }
        _schema_cache[database_id] = schema
        logger.info(f"Notion DB 스키마 조회 완료: {len(schema)}개 속성")
        return schema
    except Exception as e:
        logger.warning(f"Notion DB 스키마 조회 중 오류 (제목만 저장됩니다): {e}")
        return {}


def _property_value(prop_type: str, value) -> dict | None:
    """
    속성 타입에 맞는 Notion 속성 값 객체를 만듭니다.

    지원하지 않는 타입이면 None을 반환해 해당 속성을 건너뜁니다.
    Notion의 길이 제한(텍스트 2000자, 옵션명 100자)에 맞춰 잘라냅니다.
    """
    if prop_type == "rich_text":
        return {"rich_text": [{"text": {"content": str(value)[:2000]}}]}
    if prop_type == "select":
        return {"select": {"name": str(value)[:100]}}
    if prop_type == "multi_select":
        # 쉼표는 Notion 옵션명에 쓸 수 없어 제거
        options = [
            {"name": str(v).replace(",", " ")[:100]}
            for v in value
            if str(v).strip()
        ]
        return {"multi_select": options[:10]} if options else None
    if prop_type == "date":
        return {"date": {"start": str(value)}}
    if prop_type == "number":
        return {"number": value}
    return None


def _build_properties(
    schema: dict[str, str],
    title: str,
    meta: dict,
) -> dict:
    """
    제목 + 메타데이터로 Notion 페이지 속성 dict를 구성합니다.

    제목 속성의 이름은 DB마다 다르므로(이름/Name/제목 등) 스키마에서
    type이 "title"인 속성을 찾아 씁니다. 스키마를 못 읽었을 때는
    모든 DB에서 통용되는 속성 ID "title"로 폴백합니다.
    """
    title_prop = next(
        (name for name, ptype in schema.items() if ptype == "title"),
        "title",
    )
    properties = {
        title_prop: {"title": [{"text": {"content": title[:2000]}}]},
    }

    skipped = []
    for field, (candidates, allowed_types) in _PROPERTY_CANDIDATES.items():
        value = meta.get(field)
        # 0과 빈 값은 보내지 않음 (0개 메시지, 빈 키워드 등은 무의미)
        if not value:
            continue

        # 후보 이름 중 타입까지 일치하는 속성 찾기
        matched = next(
            (
                name
                for name in candidates
                if schema.get(name) in allowed_types
            ),
            None,
        )
        if matched is None:
            skipped.append(field)
            continue

        built = _property_value(schema[matched], value)
        if built is not None:
            properties[matched] = built

    if skipped:
        logger.info(
            f"Notion DB에 해당 속성이 없어 건너뜀: {', '.join(skipped)}"
        )
    return properties


def extract_keywords(report_markdown: str) -> list[str]:
    """
    리포트의 `## 주제 키워드` 섹션에서 쉼표로 구분된 키워드를 추출합니다.

    Notion multi_select 속성에 태그로 넣기 위한 용도입니다.
    섹션이 없으면 빈 리스트를 반환합니다.
    """
    match = re.search(
        r"^##\s*주제 키워드\s*\n+(.+)$",
        report_markdown,
        re.MULTILINE,
    )
    if not match:
        return []
    return [
        kw.strip()
        for kw in match.group(1).split(",")
        if kw.strip()
    ][:10]


async def _append_blocks(
    client: httpx.AsyncClient,
    headers: dict,
    page_id: str,
    blocks: list[dict],
) -> None:
    """
    페이지 생성 후 남은 블록을 100개씩 이어서 추가합니다.

    Notion API는 한 요청에 최대 100개 블록만 허용합니다.
    이전에는 초과분을 그냥 버려서 긴 리포트의 뒷부분이 유실됐습니다.
    """
    for i in range(0, len(blocks), 100):
        chunk = blocks[i : i + 100]
        try:
            resp = await client.patch(
                f"{NOTION_API_BASE}/blocks/{page_id}/children",
                headers=headers,
                json={"children": chunk},
                timeout=30,
            )
            if resp.status_code != 200:
                detail = resp.json().get("message", resp.text)
                logger.warning(
                    f"Notion 블록 추가 실패 (이후 {len(blocks) - i}개 누락): {detail}"
                )
                return
        except Exception as e:
            logger.warning(f"Notion 블록 추가 중 오류 (이후 {len(blocks) - i}개 누락): {e}")
            return


async def save_report_to_notion(
    access_token: str,
    database_id: str,
    title: str,
    report_markdown: str,
    meta: dict | None = None,
) -> dict:
    """
    Notion 데이터베이스에 리포트 페이지를 생성합니다.

    Args:
        access_token: Notion OAuth access token
        database_id: 저장할 데이터베이스 ID
        title: 페이지 제목 (예: "방이름 — 2026-03-10")
        report_markdown: 최종 마크다운 리포트
        meta: 속성에 채울 메타데이터. 지원 키는 _PROPERTY_CANDIDATES 참조.
              DB에 없는 속성은 자동으로 건너뜁니다.

    Returns:
        {"url": "https://notion.so/...", "page_id": "..."} 또는
        {"error": "에러 메시지"}
    """
    blocks = _markdown_to_notion_blocks(report_markdown)

    headers = {
        "Authorization": f"Bearer {access_token}",
        "Content-Type": "application/json",
        "Notion-Version": NOTION_VERSION,
    }

    async with httpx.AsyncClient() as client:
        try:
            # DB에 실제로 존재하는 속성만 채우기 위해 스키마를 먼저 조회
            schema = await _fetch_database_schema(client, headers, database_id)
            properties = _build_properties(schema, title, meta or {})

            payload = {
                "parent": {"database_id": database_id},
                "properties": properties,
                # 첫 100개만 페이지 생성과 함께 전송, 나머지는 이어서 추가
                "children": blocks[:100],
            }

            resp = await client.post(
                f"{NOTION_API_BASE}/pages",
                headers=headers,
                json=payload,
                timeout=30,
            )
            if resp.status_code != 200:
                detail = resp.json().get("message", resp.text)
                logger.error(f"Notion 페이지 생성 실패: {detail}")
                return {"error": f"Notion API 오류: {detail}"}

            data = resp.json()
            url = data.get("url", "")
            page_id = data.get("id", "")

            # 100개 초과분 이어붙이기 (긴 리포트 유실 방지)
            if len(blocks) > 100:
                await _append_blocks(client, headers, page_id, blocks[100:])

            logger.info(f"Notion 페이지 생성 완료 ({len(blocks)}블록): {url}")
            return {"url": url, "page_id": page_id}
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
