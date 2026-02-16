/// LLM이 생성한 일별 요약
class DailyDigest {
  final DateTime date;
  final String summary;
  final List<String> topics;

  const DailyDigest({
    required this.date,
    required this.summary,
    this.topics = const [],
  });
}
