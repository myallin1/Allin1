// ================================================================
// antigravity_bridge_service.dart — Antigravity Mobile-to-IDE Live Bridge
// ================================================================
// Powers direct 2-way real-time communication between the Admin Mobile PWA
// and the Antigravity IDE coding engine.
//
// Allows Nizam/Admin to:
// 1. Submit voice/text coding requests, bug reports, and UX tasks from mobile.
// 2. Attach mobile screenshots & camera photos via Cloudinary.
// 3. Include device context (viewport, user-agent, route, timestamps).
// 4. Stream live execution status (Queued -> In Progress -> Tested -> Deployed).
// 5. Read back Antigravity IDE responses, changelogs, and walkthrough notes.
// ================================================================

import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'cloudinary_upload_service.dart';

enum AntigravityTaskStatus {
  pending,
  inProgress,
  completed,
  failed,
}

class AntigravityBridgeTask {
  final String id;
  final String prompt;
  final String? imageUrl;
  final String priority; // 'normal', 'high', 'urgent'
  final AntigravityTaskStatus status;
  final String? agentResponse;
  final List<String> logs;
  final Map<String, dynamic> clientContext;
  final DateTime createdAt;
  final DateTime updatedAt;

  const AntigravityBridgeTask({
    required this.id,
    required this.prompt,
    this.imageUrl,
    this.priority = 'normal',
    this.status = AntigravityTaskStatus.pending,
    this.agentResponse,
    this.logs = const [],
    this.clientContext = const {},
    required this.createdAt,
    required this.updatedAt,
  });

  factory AntigravityBridgeTask.fromFirestore(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>?) ?? {};
    return AntigravityBridgeTask.fromMap(doc.id, data);
  }

  factory AntigravityBridgeTask.fromMap(String id, Map<String, dynamic> data) {
    final statusStr = (data['status'] as String?) ?? 'pending';
    AntigravityTaskStatus status;
    switch (statusStr.toLowerCase()) {
      case 'in_progress':
      case 'inprogress':
        status = AntigravityTaskStatus.inProgress;
        break;
      case 'completed':
      case 'done':
        status = AntigravityTaskStatus.completed;
        break;
      case 'failed':
      case 'error':
        status = AntigravityTaskStatus.failed;
        break;
      case 'pending':
      default:
        status = AntigravityTaskStatus.pending;
        break;
    }

    final rawCreatedAt = data['createdAt'];
    DateTime createdAt = DateTime.now();
    if (rawCreatedAt is Timestamp) {
      createdAt = rawCreatedAt.toDate();
    } else if (rawCreatedAt is String) {
      createdAt = DateTime.tryParse(rawCreatedAt) ?? DateTime.now();
    }

    final rawUpdatedAt = data['updatedAt'];
    DateTime updatedAt = DateTime.now();
    if (rawUpdatedAt is Timestamp) {
      updatedAt = rawUpdatedAt.toDate();
    } else if (rawUpdatedAt is String) {
      updatedAt = DateTime.tryParse(rawUpdatedAt) ?? DateTime.now();
    }

    final rawLogs = data['logs'];
    List<String> logsList = [];
    if (rawLogs is List) {
      logsList = rawLogs.map((e) => e.toString()).toList();
    }

    return AntigravityBridgeTask(
      id: id,
      prompt: (data['prompt'] as String?) ?? '',
      imageUrl: data['imageUrl'] as String?,
      priority: (data['priority'] as String?) ?? 'normal',
      status: status,
      agentResponse: data['agentResponse'] as String?,
      logs: logsList,
      clientContext: (data['clientContext'] as Map<String, dynamic>?) ?? {},
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    String statusStr;
    switch (status) {
      case AntigravityTaskStatus.inProgress:
        statusStr = 'in_progress';
        break;
      case AntigravityTaskStatus.completed:
        statusStr = 'completed';
        break;
      case AntigravityTaskStatus.failed:
        statusStr = 'failed';
        break;
      case AntigravityTaskStatus.pending:
        statusStr = 'pending';
        break;
    }

    return {
      'prompt': prompt,
      if (imageUrl != null && imageUrl!.isNotEmpty) 'imageUrl': imageUrl,
      'priority': priority,
      'status': statusStr,
      if (agentResponse != null) 'agentResponse': agentResponse,
      'logs': logs,
      'clientContext': clientContext,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  AntigravityBridgeTask copyWith({
    String? prompt,
    String? imageUrl,
    String? priority,
    AntigravityTaskStatus? status,
    String? agentResponse,
    List<String>? logs,
    Map<String, dynamic>? clientContext,
    DateTime? updatedAt,
  }) {
    return AntigravityBridgeTask(
      id: id,
      prompt: prompt ?? this.prompt,
      imageUrl: imageUrl ?? this.imageUrl,
      priority: priority ?? this.priority,
      status: status ?? this.status,
      agentResponse: agentResponse ?? this.agentResponse,
      logs: logs ?? this.logs,
      clientContext: clientContext ?? this.clientContext,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class AntigravityBridgeService {
  AntigravityBridgeService._();
  static final AntigravityBridgeService instance = AntigravityBridgeService._();

  static const String collectionName = 'antigravity_bridge_tasks';

  CollectionReference<Map<String, dynamic>> get _collection =>
      FirebaseFirestore.instance.collection(collectionName);

  /// Submits a new prompt / task directly to the IDE queue
  Future<AntigravityBridgeTask> submitTask({
    required String prompt,
    String? imageUrl,
    String priority = 'normal',
    Map<String, dynamic>? clientContext,
  }) async {
    final now = DateTime.now();
    final data = {
      'prompt': prompt.trim(),
      if (imageUrl != null && imageUrl.isNotEmpty) 'imageUrl': imageUrl,
      'priority': priority,
      'status': 'pending',
      'agentResponse': null,
      'logs': ['Task received from Admin Mobile PWA at ${now.toIso8601String()}'],
      'clientContext': clientContext ?? {
        'platform': kIsWeb ? 'Web PWA' : 'Native',
        'submittedAt': now.toIso8601String(),
      },
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    final docRef = await _collection.add(data);
    return AntigravityBridgeTask(
      id: docRef.id,
      prompt: prompt.trim(),
      imageUrl: imageUrl,
      priority: priority,
      status: AntigravityTaskStatus.pending,
      logs: ['Task received from Admin Mobile PWA'],
      clientContext: clientContext ?? {},
      createdAt: now,
      updatedAt: now,
    );
  }

  /// Uploads screenshot/image bytes to Cloudinary under antigravity_bridge folder
  Future<String?> uploadScreenshot(Uint8List bytes, {String? filename}) async {
    try {
      final name = filename ?? 'bridge_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final result = await CloudinaryUploadService().uploadImageBytes(
        bytes,
        folder: 'antigravity_bridge',
        fileName: name,
      );
      return result;
    } catch (e) {
      debugPrint('[AntigravityBridge] uploadScreenshot error: $e');
      return null;
    }
  }

  /// Stream of all bridge tasks ordered by latest first
  Stream<List<AntigravityBridgeTask>> streamTasks({int limit = 30}) {
    return _collection
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => AntigravityBridgeTask.fromFirestore(doc))
            .toList());
  }

  /// Stream of a single task
  Stream<AntigravityBridgeTask?> streamTask(String taskId) {
    return _collection.doc(taskId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return AntigravityBridgeTask.fromFirestore(doc);
    });
  }

  /// Updates task status from IDE or admin
  Future<void> updateTaskStatus({
    required String taskId,
    required AntigravityTaskStatus status,
    String? agentResponse,
    String? appendLog,
  }) async {
    String statusStr;
    switch (status) {
      case AntigravityTaskStatus.inProgress:
        statusStr = 'in_progress';
        break;
      case AntigravityTaskStatus.completed:
        statusStr = 'completed';
        break;
      case AntigravityTaskStatus.failed:
        statusStr = 'failed';
        break;
      case AntigravityTaskStatus.pending:
        statusStr = 'pending';
        break;
    }

    final updates = <String, dynamic>{
      'status': statusStr,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (agentResponse != null) {
      updates['agentResponse'] = agentResponse;
    }

    if (appendLog != null && appendLog.isNotEmpty) {
      updates['logs'] = FieldValue.arrayUnion([appendLog]);
    }

    await _collection.doc(taskId).update(updates);
  }
}
