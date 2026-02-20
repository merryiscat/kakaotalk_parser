import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/daily_digest.dart';

/// ──────────────────────────────────────────────
/// StorageService — 요약 데이터를 JSON 파일로 영구 저장
/// ──────────────────────────────────────────────
/// 앱이 종료되어도 요약 결과가 사라지지 않도록
/// 핸드폰의 앱 전용 폴더에 JSON 파일로 저장/불러오기를 담당합니다.
class StorageService {
  /// 저장 파일 이름 (앱 문서 디렉토리 안에 생성)
  static const _fileName = 'tokbiseo_data.json';

  /// 저장 파일의 전체 경로를 반환
  /// 예: /data/data/com.example.app/app_flutter/tokbiseo_data.json
  static Future<File> _getFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  /// 모든 데이터를 JSON 파일로 저장
  /// [roomNames]: 채팅방 이름 목록
  /// [digests]: "방이름_날짜" → 요약 결과 맵
  /// [totalInputTokens]: 누적 입력 토큰 수
  /// [totalOutputTokens]: 누적 출력 토큰 수
  static Future<void> save({
    required List<String> roomNames,
    required Map<String, DailyDigest> digests,
    required int totalInputTokens,
    required int totalOutputTokens,
  }) async {
    // 각 요약을 JSON으로 변환
    final digestsJson = <String, dynamic>{};
    for (final entry in digests.entries) {
      digestsJson[entry.key] = entry.value.toJson();
    }

    // 전체 데이터를 하나의 JSON 객체로 묶기
    final data = {
      'roomNames': roomNames,
      'digests': digestsJson,
      'totalInputTokens': totalInputTokens,
      'totalOutputTokens': totalOutputTokens,
    };

    // 파일에 쓰기 (예쁘게 정렬해서 디버깅 편하게)
    final file = await _getFile();
    await file.writeAsString(jsonEncode(data));
  }

  /// JSON 파일에서 저장된 데이터를 불러오기
  /// 파일이 없거나 읽기 실패 시 null 반환 (첫 실행 등)
  static Future<StorageData?> load() async {
    try {
      final file = await _getFile();

      // 파일이 없으면 null (첫 실행)
      if (!await file.exists()) return null;

      final content = await file.readAsString();
      final data = jsonDecode(content) as Map<String, dynamic>;

      // 방 이름 목록 복원
      final roomNames = (data['roomNames'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [];

      // 요약 데이터 복원
      final digestsJson = data['digests'] as Map<String, dynamic>? ?? {};
      final digests = <String, DailyDigest>{};
      for (final entry in digestsJson.entries) {
        digests[entry.key] =
            DailyDigest.fromJson(entry.value as Map<String, dynamic>);
      }

      return StorageData(
        roomNames: roomNames,
        digests: digests,
        totalInputTokens: data['totalInputTokens'] as int? ?? 0,
        totalOutputTokens: data['totalOutputTokens'] as int? ?? 0,
      );
    } catch (e) {
      // 파일 손상 등 예외 시 null 반환 (데이터 없이 시작)
      return null;
    }
  }
}

/// 저장된 데이터를 담는 간단한 클래스
class StorageData {
  final List<String> roomNames;
  final Map<String, DailyDigest> digests;
  final int totalInputTokens;
  final int totalOutputTokens;

  const StorageData({
    required this.roomNames,
    required this.digests,
    required this.totalInputTokens,
    required this.totalOutputTokens,
  });
}
