import 'package:flutter/material.dart';

/// 톡비서 디자인 시스템 (2026-08 리뉴얼)
///
/// 디자인 산출물(docs/design_renewal_prompt_v1.md 기반 Claude Design 시안)을
/// 코드로 옮긴 파일입니다. 색·글꼴·모양 규칙이 전부 여기에 모여 있어서,
/// 화면 파일들은 Theme.of(context)로 가져다 쓰기만 하면 됩니다.
///
/// ── 컬러 전략 ──
/// 시드 1개 + 오버라이드 3개만 사용합니다 (임의 색 나열 금지).
/// - 시드: 딥 잉크 그린 #14524A → Material 3가 전체 팔레트를 자동 생성
/// - 허니(tertiary) 계열만 수동 지정: 카카오 옐로우의 연상은 남기되
///   브랜드 모방은 피한 색. "강조 전용"으로 키워드 칩, 1순위 제안 마커,
///   진행 중 상태에만 씁니다 (화면 면적 5% 이하 유지).
///
/// ── 타이포 전략 ──
/// BMJUA(주아체)는 제목 전용, 본문은 Pretendard로 분리합니다.
/// 기존에는 긴 리포트 본문까지 전부 주아체라 가독성이 떨어졌습니다.
/// 규칙: BMJUA는 "2줄 이하의 짧은 제목"에만. 본문·라벨은 Pretendard.
///
/// ── 컨테이너 규칙 (Card 남용 방지) ──
/// 위에서 아래로 갈수록 강한 도구. 같은 종류 중첩 금지 (Card 안 Card 금지).
/// ① 여백만        — 기본값. 같은 섹션 안의 문단·불릿.
/// ② 배경색 구분   — surfaceContainer. 섹션 경계, 인용 블록. 테두리·그림자 없음.
/// ③ 1px 보더      — outlineVariant. "탭 가능한 것"의 표시. 접힘 카드, 설정 그룹.
/// ④ Card(elev 1)  — 예외 2곳뿐: 홈의 방 카드, 요약 상세의 제안 카드.

// ─────────────────────────────────────────────────────────────
// 색상 토큰
// ─────────────────────────────────────────────────────────────

/// 시드 컬러: 딥 잉크 그린
const Color kSeedColor = Color(0xFF14524A);

/// 허니 액센트 오버라이드 (라이트)
const Color _honeyLight = Color(0xFF7A5300); // tertiary
const Color _honeyContainerLight = Color(0xFFFFE08A); // tertiaryContainer
const Color _onHoneyContainerLight = Color(0xFF2A1C00);

/// 허니 액센트 오버라이드 (다크)
const Color _honeyDark = Color(0xFFF5C453); // tertiary
const Color _honeyContainerDark = Color(0xFF5A4300); // tertiaryContainer
const Color _onHoneyContainerDark = Color(0xFFFFE08A);

// ─────────────────────────────────────────────────────────────
// 모양(라운딩) 토큰 — radius: 칩 999 / 컨테이너 16 / 카드 20 / 시트 28
// ─────────────────────────────────────────────────────────────

/// 보더 컨테이너(규칙 ③)와 접힘 카드의 라운딩
const double kRadiusContainer = 16;

/// Card(규칙 ④)의 라운딩
const double kRadiusCard = 20;

/// 바텀 시트·다이얼로그의 라운딩
const double kRadiusSheet = 28;

/// 라이트 테마 생성
ThemeData buildLightTheme() => _buildTheme(Brightness.light);

/// 다크 테마 생성
ThemeData buildDarkTheme() => _buildTheme(Brightness.dark);

ThemeData _buildTheme(Brightness brightness) {
  final isLight = brightness == Brightness.light;

  // 시드 1개로 팔레트 자동 생성 + 허니 계열만 오버라이드
  final scheme = ColorScheme.fromSeed(
    seedColor: kSeedColor,
    brightness: brightness,
  ).copyWith(
    tertiary: isLight ? _honeyLight : _honeyDark,
    tertiaryContainer: isLight ? _honeyContainerLight : _honeyContainerDark,
    onTertiary: isLight ? Colors.white : const Color(0xFF3F2E00),
    onTertiaryContainer:
        isLight ? _onHoneyContainerLight : _onHoneyContainerDark,
  );

  // ── 타이포 스케일 ──
  // display/headline/titleLarge → BMJUA (짧은 제목 전용)
  // titleMedium 이하 제목 + body/label → Pretendard
  const display = 'BMJUA';
  const body = 'Pretendard';
  final textTheme = ThemeData(brightness: brightness).textTheme.copyWith(
        // 큰 제목 (주아체)
        displayLarge: const TextStyle(fontFamily: display, height: 1.2),
        displayMedium: const TextStyle(fontFamily: display, height: 1.2),
        displaySmall:
            const TextStyle(fontFamily: display, fontSize: 28, height: 1.3),
        headlineLarge: const TextStyle(fontFamily: display, height: 1.25),
        headlineMedium: const TextStyle(fontFamily: display, height: 1.25),
        headlineSmall:
            const TextStyle(fontFamily: display, fontSize: 24, height: 1.3),
        titleLarge:
            const TextStyle(fontFamily: display, fontSize: 22, height: 1.35),
        // 중간 제목부터는 Pretendard (가독성)
        titleMedium: const TextStyle(
            fontFamily: body,
            fontSize: 16,
            fontWeight: FontWeight.w700,
            height: 1.4),
        titleSmall: const TextStyle(
            fontFamily: body,
            fontSize: 14,
            fontWeight: FontWeight.w600,
            height: 1.4),
        // 본문 — 긴 리포트를 읽는 유일한 스타일. 행간을 넉넉하게.
        bodyLarge:
            const TextStyle(fontFamily: body, fontSize: 16, height: 1.75),
        bodyMedium:
            const TextStyle(fontFamily: body, fontSize: 14, height: 1.6),
        bodySmall:
            const TextStyle(fontFamily: body, fontSize: 12.5, height: 1.5),
        // 라벨 (버튼·배지·메타 정보)
        labelLarge: const TextStyle(
            fontFamily: body, fontSize: 14, fontWeight: FontWeight.w600),
        labelMedium: const TextStyle(
            fontFamily: body, fontSize: 12, fontWeight: FontWeight.w500),
        labelSmall: const TextStyle(
            fontFamily: body, fontSize: 11, fontWeight: FontWeight.w500),
      );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    // 기본 폰트를 Pretendard로 — BMJUA는 textTheme에서 지정한 곳만
    fontFamily: body,
    textTheme: textTheme,
    scaffoldBackgroundColor: scheme.surface,

    // ── 앱바: 배경색만 살짝 구분(규칙 ②), 그림자 없음. 제목은 주아체 ──
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      scrolledUnderElevation: 0,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: display,
        fontSize: 22,
        color: scheme.onSurface,
      ),
    ),

    // ── Card(규칙 ④): elevation 1 고정, radius 20 ──
    // 사용처는 "홈의 방 카드"와 "요약 상세의 제안 카드" 2곳뿐입니다.
    cardTheme: CardThemeData(
      elevation: 1,
      shadowColor: Colors.black.withValues(alpha: 0.3),
      color: isLight ? Colors.white : scheme.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kRadiusCard),
      ),
      margin: EdgeInsets.zero,
    ),

    // ── 키워드 칩: 허니 배경, 라운딩 999, 테두리 없음 ──
    chipTheme: ChipThemeData(
      backgroundColor: scheme.tertiaryContainer,
      side: BorderSide.none,
      shape: const StadiumBorder(),
      labelStyle: TextStyle(
        fontFamily: body,
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: scheme.onTertiaryContainer,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    ),

    // ── FAB: 허니 컨테이너 배경, radius 18, 라벨은 주아체 ──
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.tertiaryContainer,
      foregroundColor: scheme.onTertiaryContainer,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
      extendedTextStyle: const TextStyle(fontFamily: display, fontSize: 17),
    ),

    // ── 입력창: 보더 라운딩 12 ──
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    ),

    // ── 다이얼로그·바텀시트: radius 28, 제목은 주아체 ──
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kRadiusSheet),
      ),
      titleTextStyle: TextStyle(
        fontFamily: display,
        fontSize: 21,
        color: scheme.onSurface,
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(kRadiusSheet)),
      ),
    ),

    // ── 진행률 바: 4px 얇게 ──
    progressIndicatorTheme: ProgressIndicatorThemeData(
      linearMinHeight: 4,
      linearTrackColor: scheme.surfaceContainerHighest,
    ),

    // ── ExpansionTile: 펼침 시 구분선 색 제거 (보더 컨테이너 안에서 사용) ──
    expansionTileTheme: const ExpansionTileThemeData(
      shape: Border(),
      collapsedShape: Border(),
    ),
  );
}

/// 규칙 ③ "탭 가능한 것 = 1px 보더" 컨테이너의 공통 장식
///
/// 접힘형 주제 카드, 설정 그룹, 발행 대기 카드, 날짜별 요약 행에서 씁니다.
/// Card 위젯 대신 이 장식을 쓰면 중첩·그림자 남용을 막을 수 있습니다.
BoxDecoration outlinedBox(BuildContext context, {double? radius}) {
  final scheme = Theme.of(context).colorScheme;
  return BoxDecoration(
    border: Border.all(color: scheme.outlineVariant),
    borderRadius: BorderRadius.circular(radius ?? kRadiusContainer),
  );
}
