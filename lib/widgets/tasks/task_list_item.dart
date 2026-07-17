// ================================================================
// TaskListItem — Allin1 Super App
// Modular Widget: Individual Task Card with Scarcity Hooks
// ================================================================

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/task_model.dart';
import '../../services/task_service.dart';

class TaskListItem extends StatefulWidget {
  final TaskModel task;
  final VoidCallback? onTap; // Optional: can be used for secondary actions

  const TaskListItem({
    required this.task,
    super.key,
    this.onTap,
  });

  @override
  State<TaskListItem> createState() => _TaskListItemState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty<TaskModel>('task', task))
      ..add(ObjectFlagProperty<VoidCallback?>.has('onTap', onTap));
  }
}

class _TaskListItemState extends State<TaskListItem> {
  bool _isStarting = false;
  final TaskService _taskService = TaskService();

  Future<void> _handleStartTask(BuildContext context) async {
    setState(() => _isStarting = true);

    try {
      // In a real device, we would use device_info_plus
      const deviceId = 'device_placeholder_123';

      final response =
          await _taskService.startTask(widget.task.taskId, deviceId);

      if (!mounted) {
        return;
      }

      if (response.success && response.trackingUrl != null) {
        final uri = Uri.parse(response.trackingUrl!);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);

          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('🚀 Opening ${widget.task.partnerName}...'),
                backgroundColor: const Color(0xFF00C853),
              ),
            );
          }
        } else {
          throw Exception('Could not launch partner URL');
        }
      } else {
        if (!context.mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(response.message),
            backgroundColor: const Color(0xFFFF5252),
          ),
        );
      }
    } catch (e) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: const Color(0xFFFF5252),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isStarting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scarcityMessage = widget.task.getScarcityMessage();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: widget.task.category == 'flash'
              ? const Color(0xFFFF5252).withValues(alpha: 0.4)
              : const Color(0xFFFFBB00).withValues(alpha: 0.2),
          width: widget.task.category == 'flash' ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              // Partner Logo
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: const Color(0xFF12121E),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    widget.task.partnerLogo,
                    style: const TextStyle(fontSize: 28),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Task Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.task.title,
                      style: GoogleFonts.outfit(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFFEEEEF5),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.task.partnerName,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF7777A0),
                      ),
                    ),
                  ],
                ),
              ),
              // Reward Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFBB00).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    const Text(
                      '🪙',
                      style: TextStyle(fontSize: 12),
                    ),
                    Text(
                      '+${widget.task.rewardCoins}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFFFFBB00),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Description
          Text(
            widget.task.description,
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFF7777A0),
            ),
          ),
          const SizedBox(height: 10),
          // Scarcity & Timer
          if (scarcityMessage.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFFF5252).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                scarcityMessage,
                style: const TextStyle(
                  fontSize: 10,
                  color: Color(0xFFFF5252),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          const SizedBox(height: 10),
          // Action Button
          SizedBox(
            width: double.infinity,
            height: 40,
            child: ElevatedButton(
              onPressed: _isStarting ? null : () => _handleStartTask(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: widget.task.category == 'flash'
                    ? const Color(0xFFFF5252)
                    : const Color(0xFFFFBB00),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                disabledBackgroundColor: const Color(0xFF12121E),
              ),
              child: _isStarting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.play_arrow, size: 16),
                        const SizedBox(width: 4),
                        Text(
                          widget.task.category == 'flash'
                              ? 'Claim Flash Offer'
                              : 'Start Task',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
