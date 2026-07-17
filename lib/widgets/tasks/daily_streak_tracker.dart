// ================================================================
// DailyStreakTracker — Allin1 Super App
// Modular Widget: 7-Day Streak Visual Tracker
// ================================================================

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class DailyStreakTracker extends StatelessWidget {
  final int currentStreak;
  final int longestStreak;

  const DailyStreakTracker({
    required this.currentStreak,
    required this.longestStreak,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFFFBB00).withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🔥', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              const Text(
                'Daily Streak',
                style: TextStyle(
                  fontSize: 14,
                  color: Color(0xFFEEEEF5),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                '$currentStreak Days',
                style: GoogleFonts.outfit(
                  fontSize: 16,
                  color: const Color(0xFFFFBB00),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(7, (index) {
              final day = index + 1;
              final isCompleted = day <= currentStreak % 7;
              final isToday = day == (currentStreak % 7) + 1;

              return Column(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: isCompleted
                          ? const Color(0xFFFFBB00)
                          : const Color(0xFF1A1A2A),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isCompleted
                            ? const Color(0xFFFFBB00)
                            : const Color(0xFF7777A0),
                        width: 2,
                      ),
                    ),
                    child: Center(
                      child: isCompleted
                          ? const Icon(
                              Icons.check,
                              size: 18,
                              color: Colors.black,
                            )
                          : Text(
                              '$day',
                              style: TextStyle(
                                fontSize: 12,
                                color: isToday
                                    ? const Color(0xFFFFBB00)
                                    : const Color(0xFF7777A0),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _getDayName(index),
                    style: TextStyle(
                      fontSize: 9,
                      color: isToday
                          ? const Color(0xFFFFBB00)
                          : const Color(0xFF7777A0),
                    ),
                  ),
                ],
              );
            }),
          ),
          const SizedBox(height: 12),
          if (currentStreak >= 7)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFFFBB00).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('🎉', style: TextStyle(fontSize: 12)),
                  SizedBox(width: 4),
                  Text(
                    '7-Day Streak Bonus: +10% NJ Coins!',
                    style: TextStyle(
                      fontSize: 10,
                      color: Color(0xFFFFBB00),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _getDayName(int index) {
    const days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return days[index];
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(IntProperty('currentStreak', currentStreak))
      ..add(IntProperty('longestStreak', longestStreak));
  }
}
