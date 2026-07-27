"""
LangGraph 워크플로우 — 멀티에이전트 파이프라인 조립

전체 흐름 (7노드):
  Filter → Analyst → Supervisor → [Web Searcher, YouTube Searcher] (병렬)
  → Validator → Writer
"""

from langgraph.graph import StateGraph, END

from .state import AgentState
from .filter import filter_node
from .analyst import analyst_node
from .supervisor import supervisor_node
from .web_searcher import web_searcher_node
from .yt_searcher import yt_searcher_node
from .validator import validator_node
from .writer import writer_node


def build_graph() -> StateGraph:
    """
    멀티에이전트 워크플로우 그래프를 구성하고 컴파일합니다.

    Returns:
        컴파일된 LangGraph StateGraph (invoke/ainvoke로 실행 가능)
    """
    graph = StateGraph(AgentState)

    # ── 노드 등록 ──
    graph.add_node("filter", filter_node)
    graph.add_node("analyst", analyst_node)
    graph.add_node("supervisor", supervisor_node)
    graph.add_node("web_searcher", web_searcher_node)
    graph.add_node("yt_searcher", yt_searcher_node)
    graph.add_node("validator", validator_node)
    graph.add_node("writer", writer_node)

    # ── 엣지 (흐름) 설정 ──

    # 시작점: Filter (잡담 필터링, gpt-4.1-mini)
    graph.set_entry_point("filter")

    # Filter → Analyst
    graph.add_edge("filter", "analyst")

    # Analyst → Supervisor
    graph.add_edge("analyst", "supervisor")

    # Supervisor → 웹 검색 + 유튜브 검색 (병렬)
    graph.add_edge("supervisor", "web_searcher")
    graph.add_edge("supervisor", "yt_searcher")

    # 두 Searcher 완료 → Validator (통합 검증)
    graph.add_edge("web_searcher", "validator")
    graph.add_edge("yt_searcher", "validator")

    # Validator → Writer → 종료
    graph.add_edge("validator", "writer")
    graph.add_edge("writer", END)

    return graph.compile()
