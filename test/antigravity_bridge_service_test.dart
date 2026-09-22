import 'package:flutter_test/flutter_test.dart';
import 'package:erode_superapp/services/antigravity_bridge_service.dart';

void main() {
  group('AntigravityBridgeTask Serialization & Logic Tests', () {
    test('Correctly serializes and deserializes task from Map', () {
      final now = DateTime.now();
      final map = {
        'prompt': 'Fix checkout payment button on mobile',
        'imageUrl': 'https://res.cloudinary.com/test/image/upload/screenshot.jpg',
        'priority': 'high',
        'status': 'in_progress',
        'agentResponse': 'Analyzed widget tree, fixed padding overflow.',
        'logs': ['Task received', 'Analyzing layout', 'Fixed overflow'],
        'clientContext': {'platform': 'Web PWA', 'screen': 'checkout'},
        'createdAt': now.toIso8601String(),
        'updatedAt': now.toIso8601String(),
      };

      final task = AntigravityBridgeTask.fromMap('task_123', map);

      expect(task.id, 'task_123');
      expect(task.prompt, 'Fix checkout payment button on mobile');
      expect(task.imageUrl, 'https://res.cloudinary.com/test/image/upload/screenshot.jpg');
      expect(task.priority, 'high');
      expect(task.status, AntigravityTaskStatus.inProgress);
      expect(task.agentResponse, 'Analyzed widget tree, fixed padding overflow.');
      expect(task.logs.length, 3);
      expect(task.clientContext['platform'], 'Web PWA');
    });

    test('Handles fallback defaults for missing fields', () {
      final task = AntigravityBridgeTask.fromMap('empty_doc', {});

      expect(task.id, 'empty_doc');
      expect(task.prompt, '');
      expect(task.imageUrl, isNull);
      expect(task.priority, 'normal');
      expect(task.status, AntigravityTaskStatus.pending);
      expect(task.agentResponse, isNull);
      expect(task.logs, isEmpty);
      expect(task.clientContext, isEmpty);
    });

    test('toMap converts enum status properly', () {
      final task = AntigravityBridgeTask(
        id: 't1',
        prompt: 'Test prompt',
        priority: 'urgent',
        status: AntigravityTaskStatus.completed,
        createdAt: DateTime(2026, 9, 20),
        updatedAt: DateTime(2026, 9, 20),
      );

      final map = task.toMap();
      expect(map['status'], 'completed');
      expect(map['priority'], 'urgent');
      expect(map['prompt'], 'Test prompt');
    });

    test('copyWith properly preserves unedited fields', () {
      final task = AntigravityBridgeTask(
        id: 't2',
        prompt: 'Original prompt',
        status: AntigravityTaskStatus.pending,
        createdAt: DateTime(2026, 9, 20),
        updatedAt: DateTime(2026, 9, 20),
      );

      final updated = task.copyWith(
        status: AntigravityTaskStatus.completed,
        agentResponse: 'Finished work',
      );

      expect(updated.id, 't2');
      expect(updated.prompt, 'Original prompt');
      expect(updated.status, AntigravityTaskStatus.completed);
      expect(updated.agentResponse, 'Finished work');
    });
  });
}
