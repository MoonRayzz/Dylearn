// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../config/guru_theme.dart';
import '../../../core/utils/responsive_helper.dart';

class RadarChartDataModel {
  final double accuracy;
  final double fluency;
  final double precision;
  final double focus;
  final double spelling;

  const RadarChartDataModel({
    required this.accuracy,
    required this.fluency,
    required this.precision,
    required this.focus,
    required this.spelling,
  });
}

class StudentRadarChart extends StatelessWidget {
  final RadarChartDataModel data;
  final ResponsiveHelper r;

  const StudentRadarChart({
    super.key,
    required this.data,
    required this.r,
  });

  @override
  Widget build(BuildContext context) {
    if (data.accuracy == 0 && data.fluency == 0 && data.precision == 0) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.radar_rounded,
                size: r.size(40), color: GuruTheme.outlineVariant),
            SizedBox(height: r.spacing(8)),
            Text(
              'Belum ada data latihan yang cukup.',
              style: GuruTheme.bodyMedium(),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final double chartSize = constraints.maxWidth;

        return SizedBox(
          width: chartSize,
          height: chartSize * 1.05,
          child: Padding(
            padding: EdgeInsets.only(
              top: r.spacing(28),
              bottom: r.spacing(16),
              left: r.spacing(8),
              right: r.spacing(8),
            ),
            child: RadarChart(
              RadarChartData(
                radarShape: RadarShape.polygon,
                dataSets: [
                  RadarDataSet(
                    fillColor: GuruTheme.accentOrange.withOpacity(0.2),
                    borderColor: GuruTheme.accentOrange,
                    entryRadius: 4,
                    borderWidth: 2.5,
                    dataEntries: [
                      RadarEntry(value: data.accuracy),
                      RadarEntry(value: data.precision),
                      RadarEntry(value: data.fluency),
                      RadarEntry(value: data.focus),
                      RadarEntry(value: data.spelling),
                    ],
                  ),
                ],
                radarBackgroundColor: Colors.transparent,
                borderData: FlBorderData(show: false),
                radarBorderData:
                    const BorderSide(color: Colors.transparent),
                titlePositionPercentageOffset: 0.15,
                titleTextStyle: GoogleFonts.plusJakartaSans(
                  fontSize: r.font(10),
                  fontWeight: FontWeight.w700,
                  color: GuruTheme.primary,
                ),
                getTitle: (index, angle) {
                  switch (index) {
                    case 0:
                      return RadarChartTitle(
                          text: 'Akurasi\n(${data.accuracy.round()}%)',
                          angle: 0);
                    case 1:
                      return RadarChartTitle(
                          text: 'Ketepatan\n(${data.precision.round()}%)',
                          angle: 0);
                    case 2:
                      return RadarChartTitle(
                          text: 'Kelancaran\n(${data.fluency.round()}%)',
                          angle: 0);
                    case 3:
                      return RadarChartTitle(
                          text: 'Fokus\n(${data.focus.round()}%)',
                          angle: 0);
                    case 4:
                      return RadarChartTitle(
                          text: 'Pengejaan\n(${data.spelling.round()}%)',
                          angle: 0);
                    default:
                      return const RadarChartTitle(text: '');
                  }
                },
                tickCount: 5,
                ticksTextStyle: const TextStyle(
                    color: Colors.transparent, fontSize: 0),
                tickBorderData: BorderSide(
                    color: GuruTheme.outlineVariant, width: 1),
                gridBorderData: BorderSide(
                    color: GuruTheme.outlineVariant, width: 1.5),
              ),
              swapAnimationDuration: const Duration(milliseconds: 600),
              swapAnimationCurve: Curves.easeOutCubic,
            ),
          ),
        );
      },
    );
  }
}