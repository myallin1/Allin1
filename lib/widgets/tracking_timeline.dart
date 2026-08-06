// ================================================================
// tracking_timeline.dart — Shared horizontal status pipeline used
// inside DeliveryChallanCard (and reusable anywhere else a compact
// progress strip is needed). Reuses the SAME canonical status enum
// (kServiceRequestStatuses / kServiceRequestAdvanceOrder) and label
// helpers (serviceRequestLabelsFor / serviceRequestStatusIndex) from
// service_request_service.dart and service_request_labels.dart — does
// NOT invent a second status pipeline or duplicate English strings.
// ================================================================
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/theme_context_extensions.dart';
import '../utils/service_request_labels.dart';

class TrackingTimeline extends StatelessWidget {
  const TrackingTimeline({
    super.key,
    required this.currentStatus,
    required this.requestType,
  });

  final String currentStatus;
  final String requestType;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final labels = serviceRequestLabelsFor(requestType);
    final currentIndex = serviceRequestStatusIndex(currentStatus);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 54,
          child: Row(
            children: List.generate(labels.length, (i) {
              final isCompleted = i < currentIndex;
              final isCurrent = i == currentIndex;
              final isLast = i == labels.length - 1;
              final dotColor = (isCompleted || isCurrent) ? colors.accent : colors.border;

              return Expanded(
                child: Row(
                  children: [
                    Container(
                      width: isCurrent ? 16 : 12,
                      height: isCurrent ? 16 : 12,
                      decoration: BoxDecoration(
                        color: dotColor,
                        shape: BoxShape.circle,
                        boxShadow: isCurrent
                            ? [
                                BoxShadow(
                                  color: colors.accent.withValues(alpha: 0.4),
                                  blurRadius: 8,
                                  spreadRadius: 1,
                                ),
                              ]
                            : null,
                      ),
                      child: isCompleted
                          ? const Icon(Icons.check_rounded, color: Colors.white, size: 9)
                          : null,
                    ),
                    if (!isLast)
                      Expanded(
                        child: Container(
                          height: 2,
                          color: isCompleted ? colors.accent : colors.border,
                        ),
                      ),
                  ],
                ),
              );
            }),
          ),
        ),
        Row(
          children: List.generate(labels.length, (i) {
            final isCurrent = i == currentIndex;
            final isCompleted = i < currentIndex;
            return Expanded(
              child: Text(
                labels[i],
                textAlign: i == 0
                    ? TextAlign.left
                    : (i == labels.length - 1 ? TextAlign.right : TextAlign.center),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.outfit(
                  fontSize: 9.5,
                  fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w600,
                  color: isCurrent || isCompleted ? colors.text : colors.mutedText,
                ),
              ),
            );
          }),
        ),
      ],
    );
  }
}
