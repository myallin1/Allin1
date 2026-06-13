import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/task_model.dart';

class TaskProvider extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  List<TaskModel> _tasks = [];
  bool _isLoading = false;
  String? _error;
  String _selectedCategory = 'all';

  // Getters
  List<TaskModel> get tasks => _tasks;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String get selectedCategory => _selectedCategory;

  // Filtered tasks based on selected category
  List<TaskModel> get filteredTasks {
    if (_selectedCategory == 'all') {
      return _tasks;
    }
    return _tasks.where((task) {
      if (_selectedCategory == 'quick') {
        return task.category == 'quick' || task.category == 'survey';
      }
      if (_selectedCategory == 'food') {
        return task.category == 'food_delivery';
      }
      if (_selectedCategory == 'finance') {
        return task.category == 'finance' || task.category == 'finance_premium';
      }
      if (_selectedCategory == 'flash') {
        return task.category == 'flash';
      }
      return task.category == _selectedCategory;
    }).toList();
  }

  // Fetch active tasks from Firestore (Phase 3 Integration)
  Future<void> fetchActiveTasks() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final snapshot = await _firestore
          .collection('affiliate_tasks')
          .where('isActive', isEqualTo: true)
          .get();

      _tasks = snapshot.docs
          .map((doc) => TaskModel.fromFirestore(doc.data(), doc.id))
          .toList();

      // Sort: Flash and high rewards first
      _tasks.sort((a, b) {
        if (a.category == 'flash' && b.category != 'flash') {
          return -1;
        }
        if (a.category != 'flash' && b.category == 'flash') {
          return 1;
        }
        return b.rewardCoins.compareTo(a.rewardCoins);
      });
    } catch (e) {
      _error = e.toString();
      debugPrint('Error fetching tasks: $_error');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Set category filter
  void setCategory(String category) {
    _selectedCategory = category;
    notifyListeners();
  }

  // Refresh tasks
  Future<void> refresh() async {
    await fetchActiveTasks();
  }

  // Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }

  // Backwards compatibility for early stage calls
  void loadDummyData() {
    fetchActiveTasks();
  }

  void startTask(String taskId) {
    debugPrint('Task starting through TaskProvider: $taskId');
  }
}
