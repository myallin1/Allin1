// ================================================================
// admin_app_error_log_screen.dart — Allin1 In-App Error Monitor
// ================================================================
// On-device error viewer. Displays daily logs stored in Hive box
// 'app_error_log', with stack traces, repeat counts, and one-tap
// "Fix with Chitti" developer automation.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/app_error_log_service.dart';
import '../../services/chitti/chitti_dev_task_service.dart';

const Color _bg = Color(0xFF0A0A1A);
const Color _card = Color(0xFF141420);
const Color _text = Color(0xFFEEEEF5);
const Color _muted = Color(0xFF7777A0);
const Color _border = Color(0x267B6FE0);
const Color _red = Color(0xFFE05555);
const Color _green = Color(0xFF4ADE80);
const Color _amber = Color(0xFFFFB020);
const Color _yellow = Color(0xFFFBBF24);
const Color _purple = Color(0xFFB21FFF);

class AdminAppErrorLogScreen extends StatefulWidget {
  const AdminAppErrorLogScreen({super.key});

  @override
  State<AdminAppErrorLogScreen> createState() => _AdminAppErrorLogScreenState();
}

class _AdminAppErrorLogScreenState extends State<AdminAppErrorLogScreen> {
  DateTime _selectedDate = DateTime.now();
  List<AppErrorLogEntry> _logs = [];
  bool _loading = true;
  String _selectedSeverityFilter = 'ALL';
  final Set<String> _expandedIds = {};

  String get _dateStr =>
      "${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}";

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    setState(() => _loading = true);
    final entries = await AppErrorLogService.getLogsForDate(_dateStr);
    if (!mounted) return;
    setState(() {
      _logs = entries;
      _loading = false;
    });
  }

  void _changeDate(int dayDelta) {
    setState(() {
      _selectedDate = _selectedDate.add(Duration(days: dayDelta));
    });
    _loadLogs();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2025),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: _purple,
            surface: _card,
            onSurface: _text,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() => _selectedDate = picked);
      _loadLogs();
    }
  }

  Future<void> _confirmClearAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _card,
        title: Text(
          'Clear all error logs?',
          style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w700),
        ),
        content: Text(
          'This removes all local error records from this device. Cannot be undone.',
          style: GoogleFonts.outfit(color: _muted, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancel', style: GoogleFonts.outfit(color: _muted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Clear all'),
          ),
        ],
      ),
    );
    if (ok ?? false) {
      await AppErrorLogService.clearAll();
      _loadLogs();
    }
  }

  Future<void> _fixWithChitti(AppErrorLogEntry entry) async {
    ChittiDevEngine chosenEngine = ChittiDevEngine.claude;

    final shouldProceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: _card,
          title: Text(
            'Propose Bug Fix on GitHub',
            style:
                GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w700),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Chitti will create a plan issue on GitHub with this error and stack trace. '
                'The AI engine will audit it and post a fix proposal before any code changes happen.',
                style: GoogleFonts.outfit(
                  color: _muted,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Select AI Engine:',
                style: GoogleFonts.outfit(
                  color: _text,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<ChittiDevEngine>(
                initialValue: chosenEngine,
                dropdownColor: _card,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: _bg,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: _border),
                  ),
                ),
                items: ChittiDevEngine.values
                    .map((e) => DropdownMenuItem(
                          value: e,
                          child: Text(
                            e.label,
                            style: GoogleFonts.outfit(color: _text),
                          ),
                        ),)
                    .toList(),
                onChanged: (v) {
                  if (v != null) {
                    setDialogState(() => chosenEngine = v);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('Cancel', style: GoogleFonts.outfit(color: _muted)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: _purple,
                foregroundColor: Colors.white,
              ),
              child: const Text('Create Plan Issue'),
            ),
          ],
        ),
      ),
    );

    if (shouldProceed != true || !mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: _card,
        content: Text(
          'Opening GitHub issue via ${chosenEngine.label}...',
          style: GoogleFonts.outfit(color: _text),
        ),
      ),
    );

    final title = 'Fix: ${entry.errorMessage} on ${entry.screen}';
    final authLines = [
      if (entry.authEmail != null) '- **Auth Email**: `${entry.authEmail}`',
      if (entry.authUid != null) '- **Auth UID**: `${entry.authUid}`',
      if (entry.hasAdminClaim != null)
        '- **Admin Claim**: `${(entry.hasAdminClaim ?? false) ? 'Yes' : 'No'}`',
    ].join('\n');

    final description =
        'Automated bug report from Allin1 In-App Error Monitor:\n\n'
        '- **Screen**: `${entry.screen}`\n'
        '- **Severity**: `${entry.severity}`\n'
        '- **App Version**: `${entry.appVersion}`\n'
        '- **Occurred at**: `${entry.timestamp}` (Repeated: ${entry.repeatCount}x)\n'
        '${authLines.isNotEmpty ? '$authLines\n' : ''}\n'
        '### Error Message\n```\n${entry.errorMessage}\n```\n\n'
        '### Stack Trace\n```\n${entry.stackTrace}\n```';

    final result = await ChittiDevTaskService.createPlanIssue(
      title: title,
      description: description,
      engine: chosenEngine,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: result.success ? _green : _red,
        content: Text(
          result.success
              ? 'Plan issue #${result.issueNumber} created! ${chosenEngine.label} will audit it.'
              : (result.error ?? 'Failed to create plan issue'),
          style: const TextStyle(color: Colors.black),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _selectedSeverityFilter == 'ALL'
        ? _logs
        : _logs
            .where((l) => l.severity == _selectedSeverityFilter)
            .toList();

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        iconTheme: const IconThemeData(color: _text),
        title: Text(
          'In-App Error Log & Diagnostics',
          style: GoogleFonts.outfit(
            color: _text,
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined, color: _red),
            tooltip: 'Clear all logs',
            onPressed: _logs.isEmpty ? null : _confirmClearAll,
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: _text),
            tooltip: 'Refresh',
            onPressed: _loading ? null : _loadLogs,
          ),
        ],
      ),
      body: Column(
        children: [
          _dateNavigator(),
          _summaryCard(),
          _filterChips(),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: _purple),
                  )
                : filtered.isEmpty
                    ? _emptyState()
                    : RefreshIndicator(
                        onRefresh: _loadLogs,
                        color: _purple,
                        backgroundColor: _card,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: filtered.length,
                          itemBuilder: (ctx, i) =>
                              _errorCard(filtered[i]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _dateNavigator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      color: _card,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded, color: _text),
            onPressed: () => _changeDate(-1),
            tooltip: 'Previous day',
          ),
          InkWell(
            onTap: _pickDate,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  const Icon(
                    Icons.calendar_today_rounded,
                    size: 15,
                    color: _purple,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _dateStr,
                    style: GoogleFonts.outfit(
                      color: _text,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right_rounded, color: _text),
            onPressed: _selectedDate.day == DateTime.now().day &&
                    _selectedDate.month == DateTime.now().month &&
                    _selectedDate.year == DateTime.now().year
                ? null
                : () => _changeDate(1),
            tooltip: 'Next day',
          ),
        ],
      ),
    );
  }

  Widget _summaryCard() {
    int critical = 0;
    int error = 0;
    int warning = 0;

    for (final l in _logs) {
      if (l.severity == 'CRITICAL') {
        critical += l.repeatCount;
      } else if (l.severity == 'WARNING') {
        warning += l.repeatCount;
      } else {
        error += l.repeatCount;
      }
    }

    final total = critical + error + warning;

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 10, 14, 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _statCol('TOTAL', total.toString(), _text),
          _statCol('CRITICAL', critical.toString(), _red),
          _statCol('ERROR', error.toString(), _amber),
          _statCol('WARNING', warning.toString(), _yellow),
        ],
      ),
    );
  }

  Widget _statCol(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: GoogleFonts.outfit(
            color: color,
            fontWeight: FontWeight.w800,
            fontSize: 16,
          ),
        ),
        Text(
          label,
          style: GoogleFonts.outfit(
            color: _muted,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _filterChips() {
    final filters = ['ALL', 'CRITICAL', 'ERROR', 'WARNING'];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Row(
        children: filters.map((f) {
          final isSelected = _selectedSeverityFilter == f;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(
                f,
                style: GoogleFonts.outfit(
                  fontSize: 11,
                  fontWeight:
                      isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? Colors.white : _muted,
                ),
              ),
              selected: isSelected,
              selectedColor: _purple,
              backgroundColor: _card,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(color: isSelected ? _purple : _border),
              ),
              onSelected: (_) => setState(() => _selectedSeverityFilter = f),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.check_circle_outline_rounded,
            color: _green,
            size: 48,
          ),
          const SizedBox(height: 12),
          Text(
            'Zero errors recorded for this date!',
            style:
                GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            'The app has been running cleanly on this device.',
            style: GoogleFonts.outfit(color: _muted, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _errorCard(AppErrorLogEntry entry) {
    final isExpanded = _expandedIds.contains(entry.id);
    final color = entry.severity == 'CRITICAL'
        ? _red
        : (entry.severity == 'WARNING' ? _yellow : _amber);

    final time = DateTime.tryParse(entry.timestamp);
    final timeStr = time != null
        ? "${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}"
        : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: color.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    entry.severity,
                    style: GoogleFonts.outfit(
                      color: color,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (entry.repeatCount > 1)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: _purple.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${entry.repeatCount}x',
                      style: GoogleFonts.outfit(
                        color: _purple,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                const Spacer(),
                Text(
                  timeStr,
                  style: GoogleFonts.outfit(color: _muted, fontSize: 11),
                ),
              ],
            ),
          ),
          // Screen badge & Version
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                const Icon(
                  Icons.phonelink_outlined,
                  size: 13,
                  color: _muted,
                ),
                const SizedBox(width: 5),
                Text(
                  entry.screen,
                  style: GoogleFonts.outfit(
                    color: _text,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'v${entry.appVersion}',
                  style: GoogleFonts.outfit(color: _muted, fontSize: 11),
                ),
              ],
            ),
          ),
          if (entry.authUid != null || entry.authEmail != null) ...[
            const SizedBox(height: 3),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  const Icon(
                    Icons.account_circle_outlined,
                    size: 13,
                    color: _muted,
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      'User: ${entry.authEmail ?? entry.authUid ?? 'Anonymous'}'
                      ' · Admin Claim: ${(entry.hasAdminClaim ?? false) ? 'Yes' : (entry.hasAdminClaim == null ? 'Unknown' : 'No')}'
                      '${entry.authEmail != null && entry.authUid != null ? ' · UID: ${entry.authUid}' : ''}',
                      style: GoogleFonts.outfit(
                        color: _muted,
                        fontSize: 10.5,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 6),
          // Error message
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              entry.errorMessage,
              style: GoogleFonts.outfit(
                color: _text,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
          ),
          // Actions row
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            child: Row(
              children: [
                ElevatedButton.icon(
                  onPressed: () => _fixWithChitti(entry),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _purple,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 0,
                  ),
                  icon: const Icon(Icons.auto_fix_high_rounded, size: 14),
                  label: Text(
                    'Fix with Chitti',
                    style: GoogleFonts.outfit(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Spacer(),
                if (entry.stackTrace.isNotEmpty)
                  TextButton.icon(
                    onPressed: () {
                      setState(() {
                        if (isExpanded) {
                          _expandedIds.remove(entry.id);
                        } else {
                          _expandedIds.add(entry.id);
                        }
                      });
                    },
                    icon: Icon(
                      isExpanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 16,
                      color: _muted,
                    ),
                    label: Text(
                      isExpanded ? 'Hide Trace' : 'View Trace',
                      style: GoogleFonts.outfit(
                        color: _muted,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Expandable Stack Trace
          if (isExpanded && entry.stackTrace.isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _bg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'STACK TRACE',
                        style: GoogleFonts.outfit(
                          color: _muted,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      InkWell(
                        onTap: () {
                          Clipboard.setData(
                            ClipboardData(text: entry.stackTrace),
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Stack trace copied to clipboard'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                        child: Row(
                          children: [
                            const Icon(
                              Icons.copy_rounded,
                              size: 12,
                              color: _purple,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Copy',
                              style: GoogleFonts.outfit(
                                color: _purple,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  SelectableText(
                    entry.stackTrace,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      color: _muted,
                      fontSize: 10,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
