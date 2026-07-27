"""
톡비서 서버 앱 패키지

FastAPI + LangGraph 기반 멀티에이전트 대화 분석 서버.
각 하위 모듈 역할:
- agents/: LangGraph 노드 (Filter, Analyst, Supervisor, Searcher, Validator, Writer)
- tools/: 외부 API 래퍼 (Tavily 웹 검색, YouTube 검색)
- services/: 비즈니스 로직 서비스 (Notion 저장)
"""
