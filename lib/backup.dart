import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:video_player/video_player.dart'; // Import for video player

import 'package:intl/intl.dart'; // For date formatting
import 'package:url_launcher/url_launcher.dart'; // For opening artifact links
import 'package:flutter/services.dart'; // For Clipboard

// --- Configuration ---
const String _apiBaseUrl = 'https://localhost:8443/api/v1'; // Example, adjust as needed

// --- Models ---

// Represents summary data for a job list
class TestJob {
  final String id;
  final String project;
  final String status;
  final Map<String, dynamic>? details; // Made nullable
  final DateTime? enqueuedAt; // Made nullable
  final DateTime? startedAt; // Made nullable
  final DateTime? finishedAt; // Made nullable
  final String? runnerId; // Made nullable
  final int? priority; // NEW: Job priority
  final String? progress; // e.g., "22/102"
  final String? passRateString; // e.g., "95%"

  TestJob({
    required this.id,
    required this.project,
    required this.status,
    this.details,
    this.enqueuedAt,
    this.startedAt,
    this.finishedAt,
    this.runnerId,
    this.priority,
    this.progress,
    this.passRateString,
  });

  // Factory constructor to create a TestJob from JSON
  factory TestJob.fromJson(Map<String, dynamic> json) {
    // Helper to safely parse dates
    DateTime? parseDate(String? dateStr) {
      if (dateStr == null || dateStr.isEmpty) return null;
      try {
        return DateTime.tryParse(dateStr);
      } catch (e) {
        print("Error parsing date '$dateStr': $e");
        return null;
      }
    }

    return TestJob(
      id: json['job_id'] ?? json['id'] ?? 'N/A', // Prioritize 'job_id', fallback to 'id'
      project: json['project'] ?? 'N/A',
      status: json['status'] ?? 'UNKNOWN',
      details: json['details'] as Map<String, dynamic>?,
      enqueuedAt: parseDate(json['enqueued_at']),
      startedAt: parseDate(json['started_at']),
      finishedAt: parseDate(json['ended_at']),
      runnerId: json['details']['runner_id'],
      priority: json['priority'] as int?,
      progress: json['progress'] as String?,
      passRateString: json['passrate'] as String?, // API field is 'passrate'
    );
  }

  // Helper to get a brief description from details
  String get briefDetails {
     if (details == null) return 'No details';
     return details?['name']?.toString() ??
            details?['suite']?.toString() ??
            details?['description']?.toString() ??
            details?.entries.firstOrNull?.value?.toString() ??
            'Details available';
  }

  // Getter for sorting progress
  double get progressSortValue {
    if (progress == null || !progress!.contains('/')) return -1.0;
    final parts = progress!.split('/');
    if (parts.length != 2) return -1.0;
    final completed = int.tryParse(parts[0]);
    final total = int.tryParse(parts[1]);
    if (completed == null || total == null || total == 0) return -1.0;
    return completed / total;
  }

  // Getter for sorting and coloring pass rate
  double? get passRateNumericValue {
    if (passRateString == null || !passRateString!.endsWith('%')) return null;
    final numericPart = passRateString!.substring(0, passRateString!.length - 1);
    return double.tryParse(numericPart);
  }

  String get displayProgress => progress ?? 'N/A';
  String get displayPassRate => passRateString ?? 'N/A';

}

  Color getJobPriorityColor(BuildContext context, int? priority) {
    if (priority == null) return Theme.of(context).colorScheme.onSurface; // Default color
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    // 0 is most intense (darker red), 10 is least intense (lighter red/orange or grey)
    if (priority <= 1) return isDark ? Colors.red.shade400 : Colors.red.shade700;
    if (priority <= 3) return isDark ? Colors.red.shade300 : Colors.red.shade600;
    if (priority <= 5) return isDark ? Colors.orange.shade400 : Colors.orange.shade700;
    if (priority <= 7) return isDark ? Colors.amber.shade400 : Colors.amber.shade600;
    // For 8-10, or if you want less visual noise for lower priorities:
    return isDark ? Colors.grey.shade400 : Colors.grey.shade600;
  }


// Represents the status overview for a single project queue
class QueueStatus {
  final String project;
  final int pendingJobs;
  final int activeRunners;
  final int runningSuites; // 
  final int? highestPriority; // NEW: Highest priority of a pending job

  final DateTime? lastActivity;

  QueueStatus({
    required this.project,
    required this.pendingJobs,
    this.activeRunners = 0,
    required this.runningSuites,
    this.lastActivity,
    this.highestPriority,

  });

  factory QueueStatus.fromJson(Map<String, dynamic> json) {
     DateTime? parseDate(String? dateStr) {
      if (dateStr == null || dateStr.isEmpty) return null;
      try {
        return DateTime.tryParse(dateStr);
      } catch (e) {
        print("Error parsing date '$dateStr': $e");
        return null;
      }
    }

    return QueueStatus(
      project: json['project'] ?? 'Unknown Project',
      pendingJobs: json['pending_jobs'] ?? 0,
      activeRunners: json['active_runners'] ?? 0,
      runningSuites: json['running_suites'] ?? 0, // Parse new field
      highestPriority: json['highest_priority'] as int?, // Parse new field
      lastActivity: parseDate(json['last_activity']),
    );
  }
}

// NEW: Represents detailed results for a single job run
class TestResult {
  final String jobId;
  final String project; // Added project based on DB schema
  final String status;
  final String? logs;
  final List<String> messages;
  final double durationSeconds;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final List<String> screenshots;
  final List<String> videos;
  final Map<String, dynamic>? metadata; // Contains test case details, etc.
  final Map<String, dynamic>? details;
  final DateTime? enqueuedAt;
  final int? priority;
  final String? progress;
  final String? passRateString;
  List<TestDisplayItem> hierarchicalTestDisplayItems; // Added for parsed hierarchical items

   TestResult({
    required this.jobId,
    required this.project,
    required this.status,
    this.logs,
    required this.messages,
    required this.durationSeconds,
    this.startedAt,
    this.endedAt,
    required this.screenshots,
    required this.videos,
    this.metadata,
    this.details, // Already added
    this.enqueuedAt, // Already added
    this.priority, // Already added
    this.progress,
    this.passRateString,
    this.hierarchicalTestDisplayItems = const [], // Initialize
  });

   factory TestResult.fromJson(Map<String, dynamic> json) {
     DateTime? parseDate(String? dateStr) {
      if (dateStr == null || dateStr.isEmpty) return null;
      try {
        return DateTime.tryParse(dateStr);
      } catch (e) {
        print("Error parsing date '$dateStr': $e");
        return null;
      }
    }

     // Helper to safely parse list of strings
     List<String> parseStringList(dynamic listData) {
        if (listData is List) {
            // Filter out nulls just in case, though Go shouldn't send them
            return listData.map((item) => item?.toString() ?? '').where((s) => s.isNotEmpty).toList();
        }
        return [];
     }


     return TestResult(
       jobId: json['job_id'] ?? 'N/A',
       project: json['project'] ?? 'Unknown Project', // Assuming Go API adds project
       status: json['status'] ?? 'UNKNOWN',
       logs: json['logs'],
       messages: parseStringList(json['messages']),
       durationSeconds: (json['duration_seconds'] as num?)?.toDouble() ?? 0.0,
       startedAt: parseDate(json['started_at']),
       endedAt: parseDate(json['ended_at']),
       screenshots: parseStringList(json['screenshots']),
       videos: parseStringList(json['videos']),
       metadata: json['metadata'] as Map<String, dynamic>?,
       details: json['details'] as Map<String, dynamic>?,
       enqueuedAt: parseDate(json['enqueued_at']),
       priority: json['priority'] as int?,
       progress: json['progress'] as String?,
       passRateString: json['passrate'] as String?, // API field is 'passrate'
     );
   }

  //copyWith method to update hierarchicalTestDisplayItems after parsing
  TestResult copyWithParsedHierarchicalItems(List<TestDisplayItem> Function(List<dynamic>) parser) {
    List<TestDisplayItem> parsedItems = [];
    if (metadata != null && metadata!['test_cases'] is List) {
      parsedItems = parser(metadata!['test_cases'] as List<dynamic>);
    }
    return TestResult(
      jobId: jobId,
      project: project,
      status: status,
      logs: logs,
      messages: messages,
      durationSeconds: durationSeconds,
      startedAt: startedAt,
      endedAt: endedAt,
      screenshots: screenshots,
      videos: videos,
      metadata: metadata,
      details: details,
      enqueuedAt: enqueuedAt,
      priority: priority,
      progress: progress,
      passRateString: passRateString,
      hierarchicalTestDisplayItems: parsedItems,
    );
  }

   // Helper to extract test cases if stored in metadata
   List<Map<String, dynamic>> get testCases {
      if (metadata == null || metadata!['test_cases'] == null || metadata!['test_cases'] is! List) {
         return [];
      }
     List<Map<String, dynamic>> allTestCases = [];
     _collectAllTestCases(metadata!['test_cases'] as List<dynamic>, allTestCases);
     return allTestCases;
   }

  // Helper to recursively collect all test case maps from a potentially nested structure
  void _collectAllTestCases(List<dynamic> items, List<Map<String, dynamic>> collected) {
    for (var item in items) {
      if (item is Map<String, dynamic>) {
        Map<String, dynamic> currentMap = item;
        Map<String, dynamic> testCaseDataCandidate = Map.from(currentMap);
        List<String> keysToRemove = [];

        // Recurse into any list-valued entries (categories)
        for (var entry in currentMap.entries) {
          if (entry.key != 'steps' && entry.value is List) { // Exclude 'steps' from being treated as a category
            _collectAllTestCases(entry.value as List<dynamic>, collected); // Recurse
            keysToRemove.add(entry.key);
          }
        }

        for(var key in keysToRemove) {
          testCaseDataCandidate.remove(key);
        }

        // If what remains is a test case, add it
        if (testCaseDataCandidate.containsKey('id') && testCaseDataCandidate.isNotEmpty) {
          collected.add(testCaseDataCandidate);
        }
      }
    }
  }

  // Getter for sorting and coloring pass rate
  double? get passRateNumericValue {
    if (passRateString == null || !passRateString!.endsWith('%')) return null;
    final numericPart = passRateString!.substring(0, passRateString!.length - 1);
    return double.tryParse(numericPart);
  }

  String get displayProgress => progress ?? 'N/A';
  String get displayPassRate => passRateString ?? 'N/A';

}


// --- API Service ---
// Handles communication with the Go server API
class ApiService {
  // Fetches a list of all jobs
  Future<List<TestJob>> fetchJobs() async {
    final url = Uri.parse('$_apiBaseUrl/jobs');
    print('Fetching jobs from: $url');
    try {
      final response = await http.get(url).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        if (response.body.isEmpty) return [];
        List<dynamic> data;
        try { data = jsonDecode(response.body); } catch (e) { throw Exception('Failed to decode jobs JSON: $e'); }
        List<TestJob> jobs = [];
        for (var jsonItem in data) {
            try { if (jsonItem is Map<String, dynamic>) { jobs.add(TestJob.fromJson(jsonItem)); } } catch (e) { print('Error parsing job item $jsonItem: $e'); }
        }
        return jobs;
      } else { throw Exception('Failed to load jobs (${response.statusCode})'); }
    } catch (e) { throw Exception('Error fetching jobs: $e'); }
  }

  // Fetches the status overview for all queues
  Future<List<QueueStatus>> fetchQueueStatuses() async {
    final url = Uri.parse('$_apiBaseUrl/queues/overview');
    print('Fetching queue statuses from: $url');
    try {
       final response = await http.get(url).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
         if (response.body.isEmpty) return [];
         List<dynamic> data;
         try { data = jsonDecode(response.body); } catch (e) { throw Exception('Failed to decode queue status JSON: $e'); }
         List<QueueStatus> statuses = [];
         for (var jsonItem in data) {
             try { if (jsonItem is Map<String, dynamic>) { statuses.add(QueueStatus.fromJson(jsonItem)); } } catch (e) { print('Error parsing queue status item $jsonItem: $e'); }
         }
         return statuses;
      } else { throw Exception('Failed to load queue statuses (${response.statusCode})'); }
    } catch (e) { throw Exception('Error fetching queue statuses: $e'); }
  }

    // NEW: Fetches results for a specific project
  Future<List<TestResult>> fetchProjectResults(String projectName) async {
    final encodedProjectName = Uri.encodeComponent(projectName); // Ensure project name is URL-safe
    final url = Uri.parse('$_apiBaseUrl/projects/$encodedProjectName/results');
    print('Fetching project results from: $url');
    try {
      final response = await http.get(url).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        if (response.body.isEmpty) return [];
        List<dynamic> data;
        try {
          data = jsonDecode(response.body);
        } catch (e) {
          throw Exception('Failed to decode project results JSON: $e');
        }
        List<TestResult> jobs = [];
        for (var jsonItem in data) {
          try {
            if (jsonItem is Map<String, dynamic>) {
              jobs.add(TestResult.fromJson(jsonItem));
            }
          } catch (e) {
            print('Error parsing project result item $jsonItem: $e');
          }
        }
        return jobs;
      } else {
        throw Exception('Failed to load project results for $projectName (${response.statusCode})');
      }
    } catch (e) {
      throw Exception('Error fetching project results for $projectName: $e');
    }
  }

  // NEW: Fetches detailed result for a specific job
   Future<TestResult> fetchJobResult(String jobId) async {
     final url = Uri.parse('$_apiBaseUrl/results/$jobId');
     print('Fetching job result from: $url');
     try {
       final response = await http.get(url).timeout(const Duration(seconds: 10));

       if (response.statusCode == 200) {
         if (response.body.isEmpty) {
             throw Exception('Empty response body for job result $jobId');
         }
         Map<String, dynamic> data;
         try {
            data = jsonDecode(response.body);
         } catch (e) {
            print('Error decoding job result JSON: ${response.body}');
            throw Exception('Failed to decode job result JSON: $e');
         }
         try {
            return TestResult.fromJson(data);
         } catch (e) {
             print('Error parsing job result item $data: $e');
             throw Exception('Error parsing job result data: $e');
         }
       } else {
         print('Failed to load job result $jobId: ${response.statusCode} ${response.reasonPhrase}');
         print('Response body: ${response.body}');
         throw Exception('Failed to load job result $jobId (${response.statusCode})');
       }
     } catch (e) {
       print('Error fetching job result $jobId: $e');
       throw Exception('Error fetching job result $jobId: $e');
     }
   }

  // --- Action Methods ---
  Future<bool> cancelJob(String jobId) async {
    final url = Uri.parse('$_apiBaseUrl/jobs/$jobId/cancel');
    print('Attempting to cancel job: $jobId at $url');
    try {
       final response = await http.post(url).timeout(const Duration(seconds: 5));
       return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) { print('Error cancelling job $jobId: $e'); return false; }
  }

    Future<bool> prioritizeJob(String jobId) async {
    final url = Uri.parse('$_apiBaseUrl/jobs/$jobId/prioritize');
    print('Attempting to prioritize job: $jobId at $url');
    try {
       final response = await http.post(url).timeout(const Duration(seconds: 5));
       return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) { print('Error prioritizing job $jobId: $e'); return false; }
  }

  Future<bool> rerunJob(String jobId) async {
    final url = Uri.parse('$_apiBaseUrl/jobs/$jobId/rerun');
    print('Attempting to re-run job: $jobId at $url');
     try {
       final response = await http.post(url).timeout(const Duration(seconds: 5));
       return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) { print('Error re-running job $jobId: $e'); return false; }
  }

    Future<bool> abortJob(String jobId) async {
    final url = Uri.parse('$_apiBaseUrl/jobs/$jobId/abort');
    print('Attempting to abort job: $jobId at $url');
     try {
       final response = await http.post(url).timeout(const Duration(seconds: 5));
       return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) { print('Error aborting job $jobId: $e'); return false; }
  }
}

// --- Main Application ---
void main() {
  runApp(const TestDashboardApp());
}

class TestDashboardApp extends StatelessWidget {
  const TestDashboardApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seedColor = Colors.deepPurple;
    final lightColorScheme = ColorScheme.fromSeed(seedColor: seedColor, brightness: Brightness.light);
    final darkColorScheme = ColorScheme.fromSeed(seedColor: seedColor, brightness: Brightness.dark);

    final cardTheme = CardTheme(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12), // Slightly larger radius
      ),
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    );

    final lightCardThemeWithBorder = cardTheme.copyWith(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: lightColorScheme.outlineVariant, width: 0.8),
      ),
    );
    final darkCardThemeWithBorder = cardTheme.copyWith(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: darkColorScheme.outlineVariant, width: 0.8),
      ),
    );

    final commonDataTableTheme = DataTableThemeData(
      columnSpacing: 24,
      headingRowHeight: 48,
      dataRowMinHeight: 52,
      dataRowMaxHeight: 60,
      dividerThickness: 1,
    );
    final lightTheme = ThemeData( colorScheme: lightColorScheme, useMaterial3: true, cardTheme: lightCardThemeWithBorder.data, appBarTheme: AppBarTheme(backgroundColor: lightColorScheme.surfaceContainerHighest, elevation: 0), dataTableTheme: commonDataTableTheme.copyWith( headingTextStyle: TextStyle(fontWeight: FontWeight.w600, color: lightColorScheme.onSurfaceVariant), decoration: BoxDecoration(border: Border(bottom: BorderSide(color: lightColorScheme.outlineVariant, width: 1))),));
    final darkTheme = ThemeData( colorScheme: darkColorScheme, useMaterial3: true, cardTheme: darkCardThemeWithBorder.data, appBarTheme: AppBarTheme(backgroundColor: darkColorScheme.surfaceContainerHighest, elevation: 0), dataTableTheme: commonDataTableTheme.copyWith( headingTextStyle: TextStyle(fontWeight: FontWeight.w600, color: darkColorScheme.onSurfaceVariant), decoration: BoxDecoration(border: Border(bottom: BorderSide(color: darkColorScheme.outlineVariant, width: 1))),));

    return MaterialApp(
      title: 'Test Automation Dashboard',
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: ThemeMode.system,
      debugShowCheckedModeBanner: false,
      // Define initial route or home
      home: const DashboardShell(),
      // Define routes for navigation (optional but good practice)
      routes: {
         ProjectResultsScreen.routeName: (context) => const ProjectResultsScreen(),
         JobResultScreen.routeName: (context) => const JobResultScreen(),
         JobListScreen.routeName: (context) {
            final projectFilter = ModalRoute.of(context)?.settings.arguments as String?;
            return JobListScreen(apiService: ApiService(), initialProjectFilter: projectFilter);
         },
      },
    );
  }
}

// --- Dashboard Shell (Layout with Navigation) ---
class DashboardShell extends StatefulWidget {
  const DashboardShell({super.key});

  @override
  State<DashboardShell> createState() => _DashboardShellState();
}

class _DashboardShellState extends State<DashboardShell> {
  int _selectedIndex = 0;
  final ApiService _apiService = ApiService();
  
  // GlobalKeys to access child screen states
  final GlobalKey<_QueuesOverviewScreenState> _queuesScreenKey = GlobalKey<_QueuesOverviewScreenState>();
  final GlobalKey<_JobListScreenState> _jobListScreenKey = GlobalKey<_JobListScreenState>();
  final GlobalKey<_ProjectResultsScreenState> _projectResultsScreenKey = GlobalKey<_ProjectResultsScreenState>();


  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
     _screens = [
      QueuesOverviewScreen(key: _queuesScreenKey, apiService: _apiService),
      JobListScreen(key: _jobListScreenKey, apiService: _apiService),
      ProjectResultsScreen(key: _projectResultsScreenKey, apiService: _apiService), // Pass ApiService
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar( title: const Text('Test Automation Dashboard'), ),
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (int index) { setState(() { _selectedIndex = index; }); 
             // Call refresh on the newly selected screen's state
              switch (index) {
                case 0:
                  _queuesScreenKey.currentState?.refreshData();
                  break;
                case 1:
                  _jobListScreenKey.currentState?.refreshData();
                  break;
                case 2:
                  _projectResultsScreenKey.currentState?.refreshData();
                  break;
              }
            
            },
            labelType: NavigationRailLabelType.all,
            leading: const Padding( padding: EdgeInsets.symmetric(vertical: 20.0), child: Icon(Icons.dashboard_customize, size: 30), ),
            destinations: const <NavigationRailDestination>[
              NavigationRailDestination( icon: Icon(Icons.view_list_outlined), selectedIcon: Icon(Icons.view_list), label: Text('Queues'), ),
              NavigationRailDestination( icon: Icon(Icons.work_history_outlined), selectedIcon: Icon(Icons.work_history), label: Text('Active/Pending'), ),
              NavigationRailDestination( icon: Icon(Icons.assessment_outlined), selectedIcon: Icon(Icons.assessment), label: Text('Results'), ),
            ],
          ),
          const VerticalDivider(thickness: 1, width: 1),
          Expanded( child: IndexedStack( index: _selectedIndex, children: _screens, ), ),
        ],
      ),
    );
  }
}


// --- Screens ---

// Screen to display the overview of project queues
class QueuesOverviewScreen extends StatefulWidget {
  final ApiService apiService;
  const QueuesOverviewScreen({super.key, required this.apiService}); // Use super.key
  @override
  State<QueuesOverviewScreen> createState() => _QueuesOverviewScreenState();
}

class _QueuesOverviewScreenState extends State<QueuesOverviewScreen> {
  late Future<List<QueueStatus>> _queueStatusesFuture;

  @override
  void initState() { super.initState(); _fetchData(); }

  void _fetchData() {
    _queueStatusesFuture = widget.apiService.fetchQueueStatuses();
    if (mounted) { setState(() {}); }
  }

  // Public method to allow parent to trigger a refresh
  void refreshData() {
    _fetchData();
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'N/A';
    final now = DateTime.now(); final difference = now.difference(date);
    if (difference.inMinutes < 60) return '${difference.inMinutes} mins ago';
    if (difference.inHours < 24) return '${difference.inHours} hours ago';
    return DateFormat.yMd().add_jm().format(date);
  }

  Color _getPriorityColor(BuildContext context, int? priority) {
    if (priority == null) return Theme.of(context).colorScheme.onSurface; // Default color
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    // 0 is most intense (darker red), 10 is least intense (lighter red/orange or grey)
    if (priority <= 1) return isDark ? Colors.red.shade400 : Colors.red.shade700;
    if (priority <= 3) return isDark ? Colors.red.shade300 : Colors.red.shade600;
    if (priority <= 5) return isDark ? Colors.orange.shade400 : Colors.orange.shade700;
    if (priority <= 7) return isDark ? Colors.amber.shade400 : Colors.amber.shade600;
    // For 8-10, or if you want less visual noise for lower priorities:
    return isDark ? Colors.grey.shade400 : Colors.grey.shade600;
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
       appBar: AppBar( title: const Text('Queues Overview'), actions: [ IconButton( icon: const Icon(Icons.refresh), onPressed: _fetchData, tooltip: 'Refresh Queues', ), ], ),
       body: SelectionArea(
         child: FutureBuilder<List<QueueStatus>>(
           future: _queueStatusesFuture,
           builder: (context, snapshot) {
             if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
             if (snapshot.hasError) return Center( child: Padding( padding: const EdgeInsets.all(16.0), child: Text('Error loading queues: ${snapshot.error}\n\nPlease ensure the server is running and the API URL ($_apiBaseUrl) is correct.', textAlign: TextAlign.center), ) );
             if (!snapshot.hasData || snapshot.data!.isEmpty) return const Center(child: Text('No queue data available.'));
             final statuses = snapshot.data!;
             return GridView.builder(
               padding: const EdgeInsets.all(20.0), // Increased padding
               gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent( maxCrossAxisExtent: 500.0, mainAxisSpacing: 16.0, crossAxisSpacing: 16.0, childAspectRatio: 1.8, ),
               itemCount: statuses.length,
               itemBuilder: (context, index) {
                 final status = statuses[index];
                 return Card(
                   elevation: 0,
                   shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant, width: 1)),
                   child: InkWell(
                   onTap: () async { // Make onTap async
                     await Navigator.pushNamed( // Await navigation
                         context, // Navigate to JobListScreen
                         JobListScreen.routeName, // Assuming JobListScreen has a routeName or navigate directly
                         arguments: status.project, // Pass project name as filter argument
                       );
                     _fetchData(); // Refresh data when returning
                     },
                     borderRadius: BorderRadius.circular(12), // Match card's border radius
                     child: Padding( padding: const EdgeInsets.all(16.0), child: Column( crossAxisAlignment: CrossAxisAlignment.start, children: [
                             Text( status.project, style: Theme.of(context).textTheme.headlineSmall, ),
                             const SizedBox(height: 12),
                             Row( mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [ Text('Pending Jobs:', style: Theme.of(context).textTheme.labelLarge), Text( status.pendingJobs.toString(), style: Theme.of(context).textTheme.titleMedium?.copyWith( fontWeight: FontWeight.bold, color: status.pendingJobs > 0 ? Theme.of(context).colorScheme.tertiaryContainer : Theme.of(context).colorScheme.primaryContainer, ) ), ], ),
                             const SizedBox(height: 8),
                              Row( mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [ Text('Suites Running:', style: Theme.of(context).textTheme.labelLarge), Text( status.runningSuites.toString(), style: Theme.of(context).textTheme.titleMedium?.copyWith( color: status.runningSuites > 0 ? Theme.of(context).colorScheme.secondary : null,) ), ], ),
                             const SizedBox(height: 8),
                             Row( mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [ Text('Active Runners:', style: Theme.of(context).textTheme.labelLarge), Text( status.activeRunners.toString(), style: Theme.of(context).textTheme.titleMedium ), ], ),
                             const SizedBox(height: 8),
                             if (status.highestPriority != null) // Conditionally display highest priority
                               Row( mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [ Text('Highest Priority in queue:', style: Theme.of(context).textTheme.labelLarge),Text(status.highestPriority?.toString() ?? 'N/A', style:  Theme.of(context).textTheme.titleMedium?.copyWith( color: getJobPriorityColor(context, status.highestPriority), fontWeight: FontWeight.bold)),  ], ),
                              const SizedBox(height: 12), 
                             Text( 'Last Activity: ${_formatDate(status.lastActivity)}', style: Theme.of(context).textTheme.bodySmall, ),
                     ], ), ),
                   ),
                 );               },
             );
           },
         ),
       ),
    );
  }
}


// Screen to display the list of test jobs
class JobListScreen extends StatefulWidget {
  static const routeName = '/job-list'; // Added route name
  final ApiService apiService;
  final String? initialProjectFilter; // To receive project filter from navigation

  const JobListScreen({
    super.key,
    required this.apiService,
    this.initialProjectFilter,
  });

  @override
  State<JobListScreen> createState() => _JobListScreenState();
}

class _JobListScreenState extends State<JobListScreen> {
  List<TestJob> _allJobs = [];
  List<TestJob> _displayedJobs = [];
  bool _isLoading = true;
  String? _error;

  // Sorting state
  int _sortColumnIndex = 7; // Default to 'Enqueued' (index 7 after adding Priority, Progress, Pass Rate)
  bool _sortAscending = false; // Default to descending for dates

  // Filtering state
  String? _currentProjectFilter;
  List<String> _projectDropdownItems = ['All Projects'];

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
     // Set _currentProjectFilter directly from initialProjectFilter if available.
    // _fetchData will later validate this against the fetched projects.
    _currentProjectFilter = widget.initialProjectFilter ?? 'All Projects';
    _fetchData();
  }
   // Public method to allow parent to trigger a refresh
  void refreshData() {
    _fetchData();
  }

 @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Handle arguments if JobListScreen is navigated to directly with arguments
   // This ensures that if the screen is re-pushed with new arguments, the filter updates.
    final newInitialFilter = ModalRoute.of(context)?.settings.arguments as String?;
   // If newInitialFilter is null, it means we might be navigating back or the arguments are not set for this route.
    // We only want to update if newInitialFilter is explicitly provided and different.
    if (newInitialFilter != null && _currentProjectFilter != newInitialFilter) {
      _currentProjectFilter = newInitialFilter;
      // If data is already loaded, apply the new filter. Otherwise, _fetchData will pick it up.
        if (_allJobs.isNotEmpty) {
          _applyFilterAndSort();
      }
    }
  }
  Future<void> _fetchData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final jobs = await widget.apiService.fetchJobs();
      if (!mounted) return;
      setState(() {
        _allJobs = jobs;
        // Populate project dropdown items
        final uniqueProjects = _allJobs.map((job) => job.project).toSet().toList();
        _projectDropdownItems = ['All Projects', ...uniqueProjects];

         // Ensure _currentProjectFilter is valid against the now-populated _projectDropdownItems.
        // If _currentProjectFilter (which might have been set by initState from widget.initialProjectFilter
        // or by didChangeDependencies from route arguments) is not in the list, default to 'All Projects'.
        if (!_projectDropdownItems.contains(_currentProjectFilter)) {
          _currentProjectFilter = 'All Projects';
        }
        // If widget.initialProjectFilter was provided via constructor and is valid,
        // it should have been set in initState and will be validated here.
        // If a new filter came via didChangeDependencies, it's also validated here.

        _applyFilterAndSort();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _applyFilterAndSort() {
    List<TestJob> filteredJobs;
    if (_currentProjectFilter == null || _currentProjectFilter == 'All Projects') {
      filteredJobs = List.from(_allJobs);
    } else {
      filteredJobs = _allJobs.where((job) => job.project == _currentProjectFilter).toList();
    }
    _displayedJobs = filteredJobs;
    _sortJobs(); // _sortJobs operates on _displayedJobs
    if(mounted) setState(() {});
  }

  void _onSort(int columnIndex, bool ascending) {
    setState(() {
      _sortColumnIndex = columnIndex;
      _sortAscending = ascending;
      _applyFilterAndSort(); // Re-apply filter then sort
    });
  }

  void _sortJobs() {
    // This method now sorts the _displayedJobs list directly
    // _applyFilterAndSort() is responsible for populating _displayedJobs first

    if (_displayedJobs.isEmpty) return;

    _displayedJobs.sort((TestJob a, TestJob b) {
      Comparable<dynamic> valA, valB;
      switch (_sortColumnIndex) {
        case 0: valA = a.status; valB = b.status; break;
        case 1: valA = a.id; valB = b.id; break;
        case 2: valA = a.project; valB = b.project; break;
        case 3: valA = a.briefDetails; valB = b.briefDetails; break;
        case 4: valA = a.priority ?? -1; valB = b.priority ?? -1; break; // Lower number = higher priority, sort -1 last
        case 5: // Progress
          valA = a.progressSortValue;
          valB = b.progressSortValue;
          break;
        case 6: // Pass Rate
          valA = a.passRateNumericValue ?? -1.0; // Sort N/A (represented by -1.0) consistently
          valB = b.passRateNumericValue ?? -1.0;
          break;
        case 7: valA = a.enqueuedAt ?? DateTime.fromMillisecondsSinceEpoch(0); valB = b.enqueuedAt ?? DateTime.fromMillisecondsSinceEpoch(0); break;
        case 8: valA = a.startedAt ?? DateTime.fromMillisecondsSinceEpoch(0); valB = b.startedAt ?? DateTime.fromMillisecondsSinceEpoch(0); break;
        // case 9: // Finished column removed
        case 9: valA = a.runnerId ?? ""; valB = b.runnerId ?? ""; break;
        default: return 0;
      }

      if ((_sortColumnIndex >= 7 && _sortColumnIndex <= 8)) { // Date columns: Enqueued, Started
        DateTime? dateA = (valA as DateTime) == DateTime.fromMillisecondsSinceEpoch(0) ? null : valA;
        DateTime? dateB = (valB as DateTime) == DateTime.fromMillisecondsSinceEpoch(0) ? null : valB;
 
        if (dateA == null && dateB == null) return 0;
        if (dateA == null) return 1; // Nulls are considered "greater" or last
        if (dateB == null) return -1; // Nulls are considered "greater" or last
        return _sortAscending ? dateA.compareTo(dateB) : dateB.compareTo(dateA);
      }

      return _sortAscending ? valA.compareTo(valB) : valB.compareTo(valA);
    });
   }

  Color _getPassRateColor(BuildContext context, String? rateString) {
    final numericRate = TestJob(id: '', project: '', status: '', passRateString: rateString).passRateNumericValue; // Temporary TestJob to use parser
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (numericRate != null) {
      if (numericRate > 90) return isDark ? Colors.green.shade400 : Colors.green.shade700;
      if (numericRate > 70) return isDark ? Colors.amber.shade400 : Colors.amber.shade700;
      return isDark ? Colors.red.shade400 : Colors.red.shade700;
    }
    
    // For N/A, 0%, or other cases, use the default text color from the theme.
    return Theme.of(context).textTheme.bodyLarge?.color ?? (Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black);
   }

  String _formatDate(DateTime? date) {
    // Check for null or the specific "zero" date from the API
    if (date == null ||
        (date.year == 1 && date.month == 1 && date.day == 1 &&
         date.hour == 0 && date.minute == 0 && date.second == 0)) {
      return '-----';
    }
    return DateFormat.yMd().add_jms().format(date);
  }

  Widget _buildStatusChip(BuildContext context, String status) {
  Color chipColor;
  Color labelColor = Colors.white;
  IconData? iconData;
  final bool isDark = Theme.of(context).brightness == Brightness.dark;

  switch (status.toUpperCase()) {
    case 'PENDING': chipColor = isDark ? Colors.orange.shade300 : Colors.orange.shade700; labelColor = isDark ? Colors.black : Colors.white; iconData = Icons.pending_outlined; break;
    case 'RUNNING': chipColor = isDark ? Colors.blue.shade300 : Colors.blue.shade700; labelColor = isDark ? Colors.black : Colors.white; iconData = Icons.directions_run; break;
    case 'PASSED': chipColor = isDark ? Colors.green.shade300 : Colors.green.shade700; labelColor = isDark ? Colors.black : Colors.white; iconData = Icons.check_circle_outline; break;
    case 'FAILED': chipColor = isDark ? Colors.red.shade300 : Colors.red.shade700; labelColor = isDark ? Colors.black : Colors.white; iconData = Icons.error_outline; break;
    case 'SKIPPED': chipColor = Colors.grey.shade500; labelColor = Colors.white; iconData = Icons.skip_next_outlined; break;
    case 'RETEST': chipColor = isDark ? Colors.amber.shade300 : Colors.amber.shade700; labelColor = isDark ? Colors.black : Colors.white; iconData = Icons.replay_outlined; break;
    case 'CRITICAL': chipColor = isDark ? Colors.red.shade700 : Colors.red.shade900; labelColor = isDark ? Colors.black : Colors.white; iconData = Icons.dangerous_outlined; break;
    case 'CANCELLED': chipColor = isDark ? Colors.grey.shade600 : Colors.black54; labelColor = Colors.white; iconData = Icons.cancel_outlined; break;
    case 'ERROR': chipColor = isDark ? Colors.purple.shade200 : Colors.purple.shade700; labelColor = isDark ? Colors.black : Colors.white; iconData = Icons.report_problem_outlined; break;
    default: chipColor = Colors.grey; labelColor = Colors.white; iconData = Icons.help_outline;
  }
  return SizedBox( // Constrain the width of the chip
    width: 250, // Adjust this width as needed
    child: Chip(
      avatar: iconData != null ? Icon(iconData, color: labelColor, size: 16) : null,
      label: Text(status, overflow: TextOverflow.ellipsis), // Handle potential overflow
      backgroundColor: chipColor,
      labelStyle: TextStyle(color: labelColor, fontWeight: FontWeight.bold),
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
      visualDensity: VisualDensity.compact,
    ),
  );
}

  // UPDATED: Builds action buttons with real API calls
  List<Widget> _buildActionButtons(TestJob job) {
    List<Widget> actions = [];
    final iconColor = Theme.of(context).colorScheme.onSurfaceVariant;

    // --- Helper for showing feedback ---
    void showFeedback(String message, {bool isError = false}) {
       if (!mounted) return; // Check if widget is still in the tree
       ScaffoldMessenger.of(context).showSnackBar(
         SnackBar(
           content: Text(message),
           backgroundColor: isError ? Theme.of(context).colorScheme.error : Colors.green,
         ),
       );
    }

    // --- Helper for executing actions ---
    Future<void> executeAction(Future<bool> Function() action, String successMsg, String errorMsg) async {
        bool success = await action();
        if (success) {
            showFeedback(successMsg);
            _fetchData(); // Refresh list on success
        } else {
            showFeedback(errorMsg, isError: true);
        }
    }

    // --- Navigation Action ---
     Future<void> navigateToResults() async { // Make async
        await Navigator.pushNamed( // Await navigation
            context,
            JobResultScreen.routeName,
            arguments: job.id, // Pass job ID as argument
        );
        _fetchData(); // Refresh data when returning
    }

    // --- Define Actions ---
    if (['PASSED', 'FAILED', 'SKIPPED', 'ERROR', 'CANCELLED'].contains(job.status.toUpperCase())) {
       actions.add( IconButton( icon: Icon(Icons.description_outlined, color: iconColor), tooltip: 'View Results', onPressed: navigateToResults, ), );
       // Only allow re-run if not already a high priority (e.g. priority 0) to avoid re-running something already at max priority
       if (job.priority == null || job.priority != 0) {
            actions.add( IconButton( icon: Icon(Icons.refresh, color: iconColor), tooltip: 'Re-run Job', onPressed: () => executeAction( () => widget.apiService.rerunJob(job.id), 'Job ${job.id} re-queued.', 'Failed to re-run job ${job.id}.' ), ), );
       }
    }
    if (job.status.toUpperCase() == 'PENDING') {
      actions.add( IconButton( icon: Icon(Icons.cancel_outlined, color: Theme.of(context).colorScheme.error), tooltip: 'Cancel Job', onPressed: () => executeAction( () => widget.apiService.cancelJob(job.id), 'Job ${job.id} cancelled.', 'Failed to cancel job ${job.id}.' ), ), );
      // Only show prioritize button if priority is not already 0
      if (job.priority == null || job.priority != 0) {
        actions.add( IconButton( icon: Icon(Icons.priority_high_rounded, color: iconColor), tooltip: 'Prioritize Job', onPressed: () => executeAction( () => widget.apiService.prioritizeJob(job.id), 'Job ${job.id} prioritized.', 'Failed to prioritize job ${job.id}.' ), ), );
      }
    }
    if (job.status.toUpperCase() == 'RUNNING') {
       actions.add( IconButton( icon: Icon(Icons.stop_circle_outlined, color: Theme.of(context).colorScheme.error), tooltip: 'Abort Job', onPressed: () => executeAction( () => widget.apiService.abortJob(job.id), 'Abort signal sent for job ${job.id}.', 'Failed to abort job ${job.id}.' ), ), );
    }

    return actions.map((w) => Padding(padding: const EdgeInsets.symmetric(horizontal: 2.0), child: w)).toList();
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold( // Use key for ScaffoldMessenger
       key: _scaffoldKey,
       appBar: AppBar(
         title: const Text('Active/Pending Jobs'),
         actions: [
           // Project Filter Dropdown
           if (_projectDropdownItems.length > 1) // Show dropdown only if there are projects
             Padding(
               padding: const EdgeInsets.symmetric(horizontal: 8.0),
               child: DropdownButtonHideUnderline(
                 child: DropdownButton<String>(
                   value: _currentProjectFilter ?? 'All Projects',
                   icon: const Icon(Icons.filter_list),
                   items: _projectDropdownItems.map<DropdownMenuItem<String>>((String value) {
                     return DropdownMenuItem<String>(
                       value: value,
                       child: Text(value, style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
                     );
                   }).toList(),
                   onChanged: (String? newValue) {
                     setState(() {
                       _currentProjectFilter = newValue;
                       _applyFilterAndSort();
                     });
                   },
                   dropdownColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                 ),
               ),
             ),
           IconButton(
             icon: const Icon(Icons.refresh),
             onPressed: _fetchData, tooltip: 'Refresh Jobs',
           ),
         ], ),
       body: SelectionArea(
         child: Builder( // Use Builder to get context for DataTableTheme
            builder: (context) {
              if (_isLoading) return const Center(child: CircularProgressIndicator());
              if (_error != null) return Center( child: Padding( padding: const EdgeInsets.all(16.0), child: Text('Error loading jobs: $_error\n\nPlease ensure the server is running and the API URL ($_apiBaseUrl) is correct.', textAlign: TextAlign.center), ) );
              if (_displayedJobs.isEmpty) return const Center(child: Text('No jobs found.'));

              final dataTableTheme = Theme.of(context).dataTableTheme;

              return SingleChildScrollView( scrollDirection: Axis.vertical, child: SingleChildScrollView( scrollDirection: Axis.horizontal, child: DataTable(
                   sortColumnIndex: _sortColumnIndex,
                   sortAscending: _sortAscending,
                   headingTextStyle: dataTableTheme.headingTextStyle,
                   columnSpacing: dataTableTheme.columnSpacing,
                   dataRowMinHeight: dataTableTheme.dataRowMinHeight,
                   dataRowMaxHeight: dataTableTheme.dataRowMaxHeight,
                   columns: [
                     DataColumn(label: const Text('Status'), onSort: _onSort),
                     DataColumn(label: const Text('Job ID'), onSort: _onSort),
                     DataColumn(label: const Text('Project'), onSort: _onSort),
                     DataColumn(label: const Text('Details'), onSort: _onSort),
                     DataColumn(label: const Text('Priority'), onSort: _onSort, numeric: true),
                     DataColumn(label: const Text('Progress'), onSort: _onSort, numeric: true),
                     DataColumn(label: const Text('Pass Rate'), onSort: _onSort, numeric: true),
                     DataColumn(label: const Text('Enqueued'), onSort: _onSort, numeric: true),
                     DataColumn(label: const Text('Started'), onSort: _onSort, numeric: true),
                     // DataColumn(label: const Text('Finished'), onSort: _onSort, numeric: true), // REMOVED
                     DataColumn(label: const Text('Runner'), onSort: _onSort),
                     const DataColumn(label: Text('Actions')), // Actions column index is now 10
                   ],
                   rows: _displayedJobs.map((job) => DataRow(
                     key: ValueKey(job.id), // For better row state management
                     cells: [
                       DataCell(_buildStatusChip(context, job.status)),
                       DataCell( Tooltip(message: job.id, child: Text(job.id.length > 12 ? '${job.id.substring(0, 12)}...' : job.id)),
                         onTap: () async { // Make onTap async
                           await Navigator.pushNamed(context, JobResultScreen.routeName, arguments: job.id); // Await navigation
                           _fetchData(); // Refresh data when returning
                         }
                        ),
                       DataCell(Text(job.project)),
                       DataCell(
                         Tooltip(message: job.details?.toString() ?? 'No Details', child: Text(job.briefDetails, overflow: TextOverflow.ellipsis)),
                         onTap: () {
                           final String copyText = job.details?.toString() ?? job.briefDetails;
                           Clipboard.setData(ClipboardData(text: copyText));
                           ScaffoldMessenger.of(context).showSnackBar(
                             SnackBar(content: Text('Details copied to clipboard: "${copyText.length > 50 ? '${copyText.substring(0, 50)}...' : copyText}"')),
                           );
                         },
                       ),
                       DataCell(Text(job.priority?.toString() ?? 'N/A', style: TextStyle(color: getJobPriorityColor(context, job.priority), fontWeight: job.priority != null ? FontWeight.bold : FontWeight.normal ))),
                       DataCell(Text(job.displayProgress)),
                       DataCell(Text(job.displayPassRate, style: TextStyle(color: _getPassRateColor(context, job.passRateString)))),
                       DataCell(Text(_formatDate(job.enqueuedAt))),
                       DataCell(Text(_formatDate(job.startedAt))),
                       DataCell(Text(job.runnerId ?? 'N/A')),
                       DataCell(
                         ConstrainedBox( // Ensure actions row doesn't cause overflow if too many
                           constraints: const BoxConstraints(maxWidth: 180), // Adjust as needed
                           child: Row(mainAxisSize: MainAxisSize.min, children: _buildActionButtons(job)),
                         )
                       ),
                     ]
                   )).toList(),
              ), ), );
           },
         ),
       ),
    );
  }
}

// --- Helper classes for hierarchical test case display ---
abstract class TestDisplayItem {}

class CategoryDisplayItem extends TestDisplayItem {
  final String name;
  final List<TestDisplayItem> children;
  bool isExpanded; // Added for collapsibility

  CategoryDisplayItem(this.name, this.children, {this.isExpanded = true});
}

class TestCaseDisplayItem extends TestDisplayItem {
  final Map<String, dynamic> testCaseData;
  TestCaseDisplayItem(this.testCaseData);
}
// --- NEW: Job Result Screen ---
class JobResultScreen extends StatefulWidget {
  // Define named route for navigation
  static const routeName = '/job-result';

  const JobResultScreen({super.key});

  @override
  State<JobResultScreen> createState() => _JobResultScreenState();
}

class _JobResultScreenState extends State<JobResultScreen> {
  late Future<TestResult> _resultFuture;
  final ApiService _apiService = ApiService(); // Get instance of ApiService
  String? _jobId; // To store the job ID passed via arguments

  List<TestDisplayItem> _parseHierarchicalItems(List<dynamic> rawItems) {
    List<TestDisplayItem> displayItems = [];
    for (var rawItem in rawItems) {
      if (rawItem is Map<String, dynamic>) {
        Map<String, dynamic> currentMap = rawItem;
        Map<String, dynamic> testCaseDataCandidate = Map.from(currentMap); // Start with a copy

        // Pass 1: Extract and process categories
        List<String> keysToRemoveFromTestCaseCandidate = [];
        for (var entry in currentMap.entries) {
          if (entry.key != 'steps' && entry.value is List) { // Exclude 'steps' from being treated as a category
            // This entry represents a category
            displayItems.add(CategoryDisplayItem(
              entry.key,
              _parseHierarchicalItems(entry.value as List<dynamic>), // Recursive call
              isExpanded: true,
            ));
            keysToRemoveFromTestCaseCandidate.add(entry.key);
          }
        }

        // Remove category keys from the test case candidate map
        for (var key in keysToRemoveFromTestCaseCandidate) {
          testCaseDataCandidate.remove(key);
        }

        // Pass 2: If the remaining map has an 'id' and is not empty, it's a test case
        if (testCaseDataCandidate.containsKey('id') && testCaseDataCandidate.isNotEmpty) {
          displayItems.add(TestCaseDisplayItem(testCaseDataCandidate));
        }
      }
    }
    return displayItems;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Fetch arguments only once
    if (_jobId == null) {
       final args = ModalRoute.of(context)?.settings.arguments;
       if (args is String) {
          _jobId = args;
          _fetchResult();
       } else {
           // Handle case where jobId is not passed correctly
           print("Error: Job ID not provided to JobResultScreen");
           // You might want to navigate back or show an error message
           _resultFuture = Future.error("Job ID not provided.");
       }
    }
  }

  void _fetchResult() {
    if (_jobId != null) {
       setState(() {
          _resultFuture = _apiService.fetchJobResult(_jobId!).then((testResult) {
            return testResult.copyWithParsedHierarchicalItems(_parseHierarchicalItems);
          });
       });
    }
  }

  // Helper to format dates nicely
  String _formatDate(DateTime? date, {bool includeTime = true}) {
    // Check for null or the specific "zero" date from the API
    if (date == null ||
        (date.year == 1 && date.month == 1 && date.day == 1 &&
         date.hour == 0 && date.minute == 0 && date.second == 0)) {
      return '-----';
    }
    if (includeTime) {
       return DateFormat.yMd().add_jms().format(date); // e.g., 4/2/2025, 10:55:30 PM
    } else {
       return DateFormat.yMd().format(date); // e.g., 4/2/2025
    }
  }

  Color _getPassRateColor(BuildContext context, String? rateString) {
    final numericRate = TestResult(jobId: '', project: '', status: '', messages: [], durationSeconds: 0, screenshots: [], videos: [], passRateString: rateString).passRateNumericValue; // Temp TestResult to use parser
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (numericRate != null) {
      if (numericRate > 90) return isDark ? Colors.green.shade400 : Colors.green.shade700;
      if (numericRate > 70) return isDark ? Colors.amber.shade400 : Colors.amber.shade700;
      return isDark ? Colors.red.shade400 : Colors.red.shade700;
    }

    return Theme.of(context).textTheme.bodyLarge?.color ?? (Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black);
  }

  Widget _buildStatusChip(BuildContext context, String status) {
    Color chipColor;
    Color labelColor = Colors.white;
    IconData? iconData;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

  switch (status.toUpperCase()) {
    case 'PENDING': chipColor = isDark ? Colors.orange.shade300 : Colors.orange.shade700; labelColor = isDark ? Colors.black : Colors.white; iconData = Icons.pending_outlined; break;
    case 'RUNNING': chipColor = isDark ? Colors.blue.shade300 : Colors.blue.shade700; labelColor = isDark ? Colors.black : Colors.white; iconData = Icons.directions_run; break;
    case 'PASSED': chipColor = isDark ? Colors.green.shade300 : Colors.green.shade700; labelColor = isDark ? Colors.black : Colors.white; iconData = Icons.check_circle_outline; break;
    case 'FAILED': chipColor = isDark ? Colors.red.shade300 : Colors.red.shade700; labelColor = isDark ? Colors.black : Colors.white; iconData = Icons.error_outline; break;
    case 'SKIPPED': chipColor = Colors.grey.shade500; labelColor = Colors.white; iconData = Icons.skip_next_outlined; break;
    case 'RETEST': chipColor = isDark ? Colors.amber.shade300 : Colors.amber.shade700; labelColor = isDark ? Colors.black : Colors.white; iconData = Icons.replay_outlined; break;
    case 'CRITICAL': chipColor = isDark ? Colors.red.shade700 : Colors.red.shade900; labelColor = isDark ? Colors.black : Colors.white; iconData = Icons.dangerous_outlined; break;
    case 'CANCELLED': chipColor = isDark ? Colors.grey.shade600 : Colors.black54; labelColor = Colors.white; iconData = Icons.cancel_outlined; break;
    case 'ERROR': chipColor = isDark ? Colors.purple.shade200 : Colors.purple.shade700; labelColor = isDark ? Colors.black : Colors.white; iconData = Icons.report_problem_outlined; break;
    default: chipColor = Colors.grey; labelColor = Colors.white; iconData = Icons.help_outline;
  }
  return SizedBox( // Constrain the width of the chip
    width: 250, // Adjust this width as needed
    child: Chip(
      avatar: iconData != null ? Icon(iconData, color: labelColor, size: 16) : null,
      label: Text(status, overflow: TextOverflow.ellipsis), // Handle potential overflow
      backgroundColor: chipColor,
      labelStyle: TextStyle(color: labelColor, fontWeight: FontWeight.bold),
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
      visualDensity: VisualDensity.compact,
    ),
    );
}



   // Helper to launch URLs for artifacts
   Future<void> _launchUrl(String urlString) async {
      final Uri url = Uri.parse(urlString);
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) { // Open in external browser
         print('Could not launch $urlString');
         if(mounted) {
             ScaffoldMessenger.of(context).showSnackBar(
               SnackBar(content: Text('Could not open link: $urlString')),
             );
         }
      }
   }

  // Helper to launch URLs for artifacts or display in-page
  Future<void> _handleArtifactClick(BuildContext context, String urlString) async {
    final Uri uri = Uri.parse(urlString);
    final String fileName = uri.pathSegments.last.toLowerCase();

    // Determine file type based on extension
    if (fileName.endsWith('.png') || fileName.endsWith('.jpg') || fileName.endsWith('.jpeg') || fileName.endsWith('.gif') || fileName.endsWith('.bmp') || fileName.endsWith('.webp')) {
      _showImageDialog(context, urlString);
    } else if (fileName.endsWith('.mp4') || fileName.endsWith('.webm') || fileName.endsWith('.mov') || fileName.endsWith('.avi')) {
      _showVideoDialog(context, urlString);
    } else if (fileName.endsWith('.txt') || fileName.endsWith('.log') || fileName.endsWith('.json') || fileName.endsWith('.xml') || fileName.endsWith('.yaml') || fileName.endsWith('.yml')) {
      _showLogFileDialog(context, urlString);
    } else {
      // Fallback to external launch for other types or unknown types
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not open link: $urlString')),
          );
        }
      }
    }
  }

  // Dialog for displaying images
  void _showImageDialog(BuildContext context, String imageUrl) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.8,
              maxHeight: MediaQuery.of(context).size.height * 0.8,
            ),
            child: Stack(
              children: [
                Center(
                  child: Image.network(
                    imageUrl,
                    fit: BoxFit.contain,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return Center(
                        child: CircularProgressIndicator(
                          value: loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!,
                        ),
                      );
                    },
                    errorBuilder: (context, error, stackTrace) {
                      return Center(child: Text('Failed to load image: $error'));
                    },
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Dialog for displaying videos
  void _showVideoDialog(BuildContext context, String videoUrl) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          child: _VideoPlayerWidget(videoUrl: videoUrl),
        );
      },
    );
  }

  // Dialog for displaying log files (fetching content)
  void _showLogFileDialog(BuildContext context, String logUrl) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          child: FutureBuilder<http.Response>(
            future: http.get(Uri.parse(logUrl)),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              } else if (snapshot.hasError) {
                return Center(child: Text('Failed to load log: ${snapshot.error}'));
              } else if (snapshot.hasData && snapshot.data!.statusCode == 200) {
                return ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.8,
                    maxHeight: MediaQuery.of(context).size.height * 0.8,
                  ),
                  child: Stack(
                    children: [
                      SingleChildScrollView(
                        padding: const EdgeInsets.all(16.0),
                        child: SelectableText(
                          snapshot.data!.body,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontFamily: 'monospace'),
                        ),
                      ),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ),
                    ],
                  ),
                );
              } else {
                return Center(child: Text('Failed to load log: HTTP ${snapshot.data?.statusCode}'));
              }
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Extract jobId from arguments if not already done (e.g., if screen rebuilt)
    // This ensures we use the correct jobId even if didChangeDependencies isn't called again.
    final String? currentJobId = _jobId ?? (ModalRoute.of(context)?.settings.arguments as String?);


    return Scaffold(
      appBar: AppBar(
        title: Text(currentJobId != null ? 'Job Result: ${currentJobId.length > 8 ? '${currentJobId.substring(0,8)}...' : currentJobId}' : 'Job Result'),
        actions: [
           if(currentJobId != null)
             IconButton(
               icon: const Icon(Icons.refresh),
               onPressed: _fetchResult, // Re-fetch data
               tooltip: 'Refresh Result',
             ),
        ],
      ),
      body: SelectionArea(
        child: FutureBuilder<TestResult>(
          future: _resultFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            } else if (snapshot.hasError) {
              return Center( child: Padding( padding: const EdgeInsets.all(16.0), child: Text('Error loading result for Job ID $currentJobId: ${snapshot.error}', textAlign: TextAlign.center), ) );
            } else if (!snapshot.hasData) {
              return Center(child: Text('No result data found for Job ID $currentJobId.'));
            }

            // Data loaded successfully
            final result = snapshot.data!;

            return SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // --- Summary Card ---
                  Card(
                    elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant, width: 1)),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                               Text('Job Summary', style: Theme.of(context).textTheme.titleLarge),
                               _buildStatusChip(context, result.status),
                            ],
                          ),
                          const Divider(height: 20), // Adjusted height
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // --- Left Column: Core Job Info & Timestamps ---
                              Expanded(
                                flex: 3, // Adjust flex factor as needed
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildSummaryRow('Job ID:', result.jobId, isCompact: true),
                                    _buildSummaryRow('Project:', result.project, isCompact: true),
                                    _buildSummaryRow('Priority:', result.priority?.toString() ?? 'N/A', isCompact: true),
                                    const SizedBox(height: 8),
                                    _buildSummaryRow('Enqueued:', _formatDate(result.enqueuedAt), isCompact: true),
                                    _buildSummaryRow('Started:', _formatDate(result.startedAt), isCompact: true),
                                    _buildSummaryRow('Finished:', _formatDate(result.endedAt), isCompact: true),
                                    _buildSummaryRow('Duration:', '${result.durationSeconds.toStringAsFixed(2)}s', isCompact: true),
                                    // --- Suite Execution Summary ---
                                    if (result.metadata?['suite_execution_summary'] is Map &&
                                        (result.metadata!['suite_execution_summary'] as Map).isNotEmpty) ...[
                                      const SizedBox(height: 12),
                                      Text("Suite Summary", style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                                      const Divider(height: 10, thickness: 0.3),
                                      _buildSuiteSummaryTable(context, result.metadata!['suite_execution_summary'] as Map<String, dynamic>),
                                      const SizedBox(height: 8),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(width: 16), // Spacer between columns
                              // --- Right Column: Execution Summary, Environment & Other Details ---
                              Expanded(
                                flex: 4, // Adjust flex factor
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildSummaryRow(
                                      "Progress:", result.displayProgress,
                                      valueStyle: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                                      isCompact: true
                                    ),
                                    _buildSummaryRow(
                                      "Pass Rate:", result.displayPassRate,
                                      valueStyle: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: _getPassRateColor(context, result.passRateString)),
                                      isCompact: true
                                    ),
                                    const SizedBox(height: 8), // Spacer
                                    // Environment Snapshot & Suite Execution Summary
                                    if (result.details?['suite_name'] != null || result.details?['suite'] != null)
                                      _buildSummaryRow('Suite:', result.details!['suite_name']?.toString() ?? result.details!['suite']?.toString() ?? 'N/A', isCompact: true),
                                    if (result.details?['build_version'] != null)
                                      _buildSummaryRow('Build:', result.details!['build_version'].toString(), isCompact: true),
                                    if (result.details?['platform'] != null)
                                      _buildSummaryRow('Platform:', result.details!['platform'].toString(), isCompact: true),
                                    if (result.details?['environment'] != null)
                                      _buildSummaryRow('Env:', result.details!['environment'].toString(), isCompact: true),
                                    
                                    // --- Environment Snapshot ---
                                    if (result.metadata?['environment_snapshot'] is Map &&
                                        (result.metadata!['environment_snapshot'] as Map).isNotEmpty) ...[
                                      const SizedBox(height: 8),
                                      Text("Device Snapshot", style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                                      const Divider(height: 10, thickness: 0.3),
                                      ...(result.metadata!['environment_snapshot'] as Map<String, dynamic>)
                                          .entries
                                          .map((entry) => _buildSummaryRow(
                                                '${_formatDetailKey(entry.key)}:',
                                                entry.value?.toString() ?? 'N/A',
                                                isCompact: true,
                                              ))
                                          .toList(),
                                    ],

                                    // Display other details not explicitly handled above
                                    // Check if there are any "other" details to display before adding a divider
                                    if (result.details != null && result.details!.entries.any((entry) => ![
                                        'suite_name', 'suite', 'build_version', 
                                        'platform', 'environment', 'runner_id' // runner_id is usually part of TestJob, not TestResult.details
                                       ].contains(entry.key) && (entry.value?.toString().isNotEmpty ?? false) && entry.value?.toString() != 'N/A' &&
                                      // Also ensure we are not re-listing keys from environment_snapshot if they happen to be in details too
                                      !(result.metadata?['environment_snapshot'] is Map && (result.metadata!['environment_snapshot'] as Map).containsKey(entry.key))
                                    )) ...[
                                      const Divider(height: 12, thickness: 0.5, indent: 0, endIndent: 20), // Indent divider slightly

                                      ...result.details!.entries
                                          .where((entry) => ![ // Filter out already displayed or internal keys
                                                'suite_name', 'suite', 'build_version', 
                                                'platform', 'environment', 'runner_id'
                                              ].contains(entry.key))
                                          .map((entry) {
                                                final value = entry.value?.toString() ?? 'N/A';
                                                // Only show if value is not empty or N/A, or if it's a more complex object (like a map/list)
                                                if (value.isNotEmpty && value != 'N/A' || entry.value is Map || entry.value is List) {
                                                   return _buildSummaryRow('${_formatDetailKey(entry.key)}:', value, isCompact: true, valueMaxLines: 1); // Ensure other details fit in 1 line
                                                }
                                                return const SizedBox.shrink(); // Don't show empty/NA simple details
                                          }),
                                    ]
                                  ],
                                ),
                              ),
                            ],
                          // _buildSummaryRow('Metadata:', result.metadata?.toString() ?? 'N/A'), // Removed from summary
                      )
                      ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // --- Test Cases (If any) ---
                  if (result.hierarchicalTestDisplayItems.isNotEmpty) ...[
                     Text('Test Cases', style: Theme.of(context).textTheme.titleLarge),
                     const SizedBox(height: 8),
                     Column(
                       crossAxisAlignment: CrossAxisAlignment.start,
                       children: _buildHierarchicalTestWidgets(context, result.hierarchicalTestDisplayItems, 0, result.screenshots, result.videos),),
                     const SizedBox(height: 20),
                  ],


                  // --- Artifacts ---
                  // Display only general artifacts not associated with specific test cases, if any.
                  // For now, we assume all artifacts might be associated, so this section might become less prominent
                  // or only show if there are artifacts that couldn't be matched to a test case.
                  if (result.screenshots.any((s) => !_isArtifactAssociatedWithAnyTestCase(s, result.testCases)) || result.videos.any((v) => !_isArtifactAssociatedWithAnyTestCase(v, result.testCases))) ...[
                     Text('General Artifacts', style: Theme.of(context).textTheme.titleLarge),
                     const SizedBox(height: 8),
                     Wrap( // Use Wrap for links
                       spacing: 8.0, // Horizontal space
                       runSpacing: 4.0, // Vertical space
                       children: [
                         ...result.screenshots.where((url) => !_isArtifactAssociatedWithAnyTestCase(url, result.testCases)).map((url) => ActionChip(
                              avatar: const Icon(Icons.image_outlined, size: 16),
                              label: Text(url.split('?').first.split('/').last), // Show sanitized filename
                              onPressed: () => _handleArtifactClick(context, url),)),
                          ...result.videos.where((url) => !_isArtifactAssociatedWithAnyTestCase(url, result.testCases)).map((url) => ActionChip(
                              avatar: const Icon(Icons.videocam_outlined, size: 16),
                              label: Text(url.split('?').first.split('/').last), // Show sanitized filename
                              onPressed: () => _handleArtifactClick(context, url),)),
                       ],
                     ),
                     const SizedBox(height: 20),
                  ],


                  // --- Messages ---
                  if (result.messages.isNotEmpty) ...[
                     ExpansionTile(
                       title: Text('Messages (${result.messages.length})', style: Theme.of(context).textTheme.titleLarge), // Use titleLarge and include count
                       childrenPadding: const EdgeInsets.all(8.0),
                       shape: Border(), // Remove default border
                       children: [
                         Container(
                           width: double.infinity,
                           decoration: BoxDecoration(
                             color: Theme.of(context).colorScheme.surfaceContainer,
                             borderRadius: BorderRadius.circular(8),
                           ),
                           padding: const EdgeInsets.all(12.0),
                           child: Column(
                             crossAxisAlignment: CrossAxisAlignment.start,
                             children: result.messages.map((message) => Padding(
                               padding: const EdgeInsets.symmetric(vertical: 2.0),
                               child: SelectableText(message, style: Theme.of(context).textTheme.bodyMedium),
                             )).toList(),
                           ),
                         ),
                       ],
                     ),
                     const SizedBox(height: 20),
                  ],

                  // --- Logs ---
                   if (result.logs != null && result.logs!.isNotEmpty) ...[
                     Text('Job Logs', style: Theme.of(context).textTheme.titleLarge),
                     const SizedBox(height: 8),
                     if (result.logs!.startsWith('http://') || result.logs!.startsWith('https://'))
                       Align(
                         alignment: Alignment.centerLeft,
                         child: ActionChip( // Changed label to sanitize filename
                           avatar: const Icon(Icons.link, size: 16), // No change here
                           label: Text(result.logs!.split('?').first.split('/').last.isNotEmpty ? result.logs!.split('?').first.split('/').last : "Open Log File"), // Sanitize filename
                           onPressed: () => _showLogFileDialog(context, result.logs!),
                         ),
                       )
                   else
                       ExpansionTile(
                         title: Text('View Job Logs', style: Theme.of(context).textTheme.bodyLarge),
                         childrenPadding: const EdgeInsets.all(8.0),
                         shape: Border(), // Remove default border
                         children: [
                           Container(
                              width: double.infinity,
                              decoration: BoxDecoration( color: Theme.of(context).colorScheme.surfaceContainer, borderRadius: BorderRadius.circular(8), ),
                              padding: const EdgeInsets.all(12.0),
                              child: SelectableText(
                                 result.logs!,
                                 style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontFamily: 'monospace'),
                              ),
                           ),
                         ],
                       ),
                     const SizedBox(height: 20),     
                   ],
                ],
              ),
            );
          },
        ),
      ),
    );
    }
  

  // Helper widget for summary rows
  Widget _buildSummaryRow(String label, String value, {TextStyle? valueStyle, bool isCompact = false, int? valueMaxLines, Widget? valueWidget}) {
    final textTheme = Theme.of(context).textTheme; // Ensure textTheme is defined
    final labelStyle = textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurfaceVariant);
    final effectiveValueStyle = valueStyle ?? (isCompact ? textTheme.bodyMedium : textTheme.bodyLarge);

    return Padding(
      padding: EdgeInsets.symmetric(vertical: isCompact ? 2.0 : 4.0), // Reduced vertical padding for compact
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: isCompact ? 120 : 200, // Shorter label width for compact mode
            child: Text(label, style: labelStyle, overflow: TextOverflow.ellipsis, maxLines: 1)),
          const SizedBox(width: 20), // Reduced spacing for compact mode
          Expanded(child: valueWidget ?? Text(value, style: effectiveValueStyle, overflow: TextOverflow.ellipsis, maxLines: valueMaxLines ?? (isCompact ? 1 : null))), // Default to 1 line in compact
        ],
      ),
    );
  }

    Widget _getSuiteSummaryColor(BuildContext context, String key, String valueStr) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color valueColor = Theme.of(context).textTheme.bodyMedium?.color ?? (isDark ? Colors.white70 : Colors.black87);
    FontWeight fontWeight = FontWeight.normal;

    int? value = int.tryParse(valueStr);
    if (value == null) return Text(valueStr, style: TextStyle(color: valueColor, fontWeight: fontWeight));

    switch (key.toLowerCase()) {
      case 'passed':
        valueColor = value > 0 ? (isDark ? Colors.green.shade300 : Colors.green.shade700) : valueColor;
        fontWeight = value > 0 ? FontWeight.bold : fontWeight;
        break;
      case 'failed':
        valueColor = value > 0 ? (isDark ? Colors.red.shade300 : Colors.red.shade700) : valueColor;
        fontWeight = value > 0 ? FontWeight.bold : fontWeight;
        break;
      case 'critical':
        valueColor = value > 0 ? (isDark ? Colors.red.shade700 : Colors.red.shade900) : valueColor;
        fontWeight = value > 0 ? FontWeight.bold : fontWeight;
        break;
      case 'skipped':
        valueColor = value > 0 ? (isDark ? Colors.grey.shade400 : Colors.grey.shade700) : valueColor;
        break;
      case 'retest':
        valueColor = value > 0 ? (isDark ? Colors.orange.shade300 : Colors.orange.shade700) : valueColor;
        break;
      case 'total_tests':
        fontWeight = FontWeight.bold;
        break;
    }
    return Text(valueStr, style: TextStyle(color: valueColor, fontWeight: fontWeight));
  }

  Widget _buildSuiteSummaryTable(BuildContext context, Map<String, dynamic> summary) {
    final List<String> order = ['total_tests', 'passed', 'failed', 'critical', 'retest', 'skipped'];
    List<MapEntry<String, dynamic>> sortedEntries = [];

    for (String key in order) {
      if (summary.containsKey(key)) {
        sortedEntries.add(MapEntry(key, summary[key]));
      }
    }
    // Add any other keys not in the predefined order
    summary.entries.where((entry) => !order.contains(entry.key)).forEach(sortedEntries.add);

    return Column(
      children: sortedEntries.map((entry) {
        return _buildSummaryRow(_formatDetailKey(entry.key) + ':', entry.value.toString(), isCompact: true, valueWidget: _getSuiteSummaryColor(context, entry.key, entry.value.toString()));
      }).toList(),
    );
  }

  // NEW: Recursive widget builder for hierarchical test items
  List<Widget> _buildHierarchicalTestWidgets(BuildContext context, List<TestDisplayItem> items, int depth, List<String> allScreenshots, List<String> allVideos) {
    List<Widget> widgets = [];
    final double indentSize = 20.0; // Indentation per depth level

    for (var item in items) {
      if (item is CategoryDisplayItem) {
        // Category Row with Toggle
        widgets.add(
          InkWell(
            onTap: () {
              setState(() {
                item.isExpanded = !item.isExpanded;
              });
            },
            child: Padding(
              padding: EdgeInsets.only(left: depth * indentSize, top: 12.0, bottom: 4.0, right: 8.0),
              child: Row(
                children: [
                  Icon(item.isExpanded ? Icons.expand_more : Icons.chevron_right, size: 20),
                  const SizedBox(width: 6),
                  Expanded(child: Text(item.name, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600))),
                ],
              ),
            ),
          ),
        );
        if (item.isExpanded) { // Conditionally add children
          widgets.addAll(_buildHierarchicalTestWidgets(context, item.children, depth + 1, allScreenshots, allVideos));
        }
      } else if (item is TestCaseDisplayItem) {
        widgets.add(
          Padding(
            padding: EdgeInsets.only(left: depth * indentSize),
            child: _buildTestCaseTile(context, item.testCaseData, allScreenshots, allVideos),
          )
        );
      }
    }
    return widgets;
  }

  // Helper to format detail keys (e.g., "build_version" to "Build Version")
  String _formatDetailKey(String key) {
    if (key.isEmpty) return '';
    return key.split('_').map((word) => word[0].toUpperCase() + word.substring(1)).join(' ');
  }

  // Helper to check if an artifact URL is associated with any test case
  bool _isArtifactAssociatedWithAnyTestCase(String artifactUrl, List<Map<String, dynamic>> testCases) {
    final String artifactFileName = artifactUrl.split('/').last.toLowerCase();
    for (var tc in testCases) {
      final String tcId = tc['id']?.toString().toLowerCase() ?? '';
      if (tcId.isNotEmpty && artifactFileName.contains(tcId)) {
        return true;
      }
    }
    return false;
  }

  Color _getStepStatusColor(BuildContext context, String status) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    switch (status.toUpperCase()) {
      case 'PASSED': return isDark ? Colors.green.shade300 : Colors.green.shade700;
      case 'FAILED': return isDark ? Colors.red.shade300 : Colors.red.shade700;
      // Add more cases if needed for other step statuses like SKIPPED, PENDING, etc.
      default: return Theme.of(context).colorScheme.onSurfaceVariant; // Default color
    }
  }


   // Helper widget to display a single test case (example)
   Widget _buildTestCaseTile(BuildContext context, Map<String, dynamic> testCase, List<String> allScreenshots, List<String> allVideos) {
     final String status = testCase['status']?.toString() ?? 'UNKNOWN';     
     final double durationInSeconds = ((testCase['duration_ms'] as num?)?.toDouble() ?? 0.0) / 1000.0;
     final String logs = testCase['logs']?.toString() ?? '';
     final String testCaseId = testCase['id']?.toString() ?? '';
     final List<dynamic> steps = testCase['steps'] is List ? testCase['steps'] as List<dynamic> : [];
     final String name = "${testCaseId.isNotEmpty ? '$testCaseId: ' : ''}${testCase['name']?.toString() ?? 'Unknown Test Case'}";

     // Filter artifacts for this specific test case
     final List<String> caseScreenshots = allScreenshots.where((url) {
       final String fileName = url.split('/').last;
       return testCaseId.isNotEmpty && fileName.contains(testCaseId);
     }).toList();
     final List<String> caseVideos = allVideos.where((url) {
       final String fileName = url.split('/').last;
       return testCaseId.isNotEmpty && fileName.contains(testCaseId);
     }).toList();

     final Widget titleRow = Row(
       children: [
         Expanded(child: Text(name, style: Theme.of(context).textTheme.titleSmall, overflow: TextOverflow.ellipsis)),
         const SizedBox(width: 12),
         Text('${durationInSeconds.toStringAsFixed(2)}s', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
         const SizedBox(width: 12),
         _buildStatusChip(context, status),
         Padding(
           padding: const EdgeInsets.only(left: 8.0),
           child: logs.isNotEmpty
               ? Icon(Icons.notes_rounded, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant)
               : const SizedBox(width: 16.0), 
         ),
         Padding(
           padding: const EdgeInsets.only(left: 6.0),
           child: steps.isNotEmpty
               ? Icon(Icons.list_alt_rounded, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant) // Icon for steps
               : const SizedBox(width: 16.0),
         ),
         Padding(
           padding: const EdgeInsets.only(left: 6.0),
           child: caseScreenshots.isNotEmpty
               ? Icon(Icons.image_outlined, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant)
               : const SizedBox(width: 16.0),
         ),
         Padding(
           padding: const EdgeInsets.only(left: 6.0),
           child: caseVideos.isNotEmpty
               ? Icon(Icons.videocam_outlined, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant)
               : const SizedBox(width: 16.0),
         ),
       ],
     );

     return Card(
       margin: const EdgeInsets.symmetric(vertical: 4.0),
       elevation: 0,
       shape: RoundedRectangleBorder(
         borderRadius: BorderRadius.circular(8),
         side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant, width: 0.8),
       ),
       child: ExpansionTile(
               shape: Border(), 
               title: titleRow,
               childrenPadding: const EdgeInsets.all(8.0),
               children: [
                 // Test Case Specific Artifacts
                 if (caseScreenshots.isNotEmpty || caseVideos.isNotEmpty) ...[
                   Padding(
                     padding: const EdgeInsets.only(bottom: 8.0),
                     child: Align(
                       alignment: Alignment.centerLeft,
                       child: Text("Artifacts:", style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600)),
                     ),
                   ),
                   Align(
                     alignment: Alignment.centerLeft,
                     child: Wrap(
                       alignment: WrapAlignment.start, 
                       spacing: 8.0, runSpacing: 4.0,
                       children: [
                         ...caseScreenshots.map((url) => ActionChip(
                               avatar: const Icon(Icons.image_outlined, size: 16),
                               label: Text(url.split('?').first.split('/').last, style: Theme.of(context).textTheme.bodySmall),
                               onPressed: () => _handleArtifactClick(context, url), visualDensity: VisualDensity.compact,)),
                         ...caseVideos.map((url) => ActionChip(
                               avatar: const Icon(Icons.videocam_outlined, size: 16),
                               label: Text(url.split('?').first.split('/').last, style: Theme.of(context).textTheme.bodySmall),
                               onPressed: () => _handleArtifactClick(context, url), visualDensity: VisualDensity.compact,)),
                       ],
                     ),
                   ),
                   const SizedBox(height: 10),
                 ],
                 if (logs.isNotEmpty) ...[
                   if (logs.startsWith('http://') || logs.startsWith('https://'))
                     Padding(
                       padding: const EdgeInsets.only(bottom: 8.0),
                       child: Align(
                         alignment: Alignment.centerLeft,
                         child: ActionChip(
                           avatar: const Icon(Icons.link, size: 16),
                           label: Text(logs.split('/').last.isNotEmpty ? logs.split('/').last : "Open Log File", style: Theme.of(context).textTheme.bodySmall),
                           tooltip: logs,
                           onPressed: () => _launchUrl(logs),
                           visualDensity: VisualDensity.compact,
                         ),
                       ),
                     )
                   else 
                     Align(
                       alignment: Alignment.centerLeft,
                       child: Container(
                           width: double.infinity,
                           decoration: BoxDecoration( color: Theme.of(context).colorScheme.surfaceContainer, borderRadius: BorderRadius.circular(4), ),
                           padding: const EdgeInsets.all(10.0),
                           child: SelectableText(
                            logs,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontFamily: 'monospace'),
                          ),
                        ),
                     ),
                 ] else ...[ 
                      Align(
                        alignment: Alignment.centerLeft,
                        child: const Padding( padding: EdgeInsets.all(8.0), child: Text("No logs available for this test case."), ),
                      ),
                 ],
                 // Test Case Steps
                 if (steps.isNotEmpty) ...[
                   Padding(
                     padding: const EdgeInsets.only(top:10.0, bottom: 8.0),
                     child: Align(
                       alignment: Alignment.centerLeft,
                       child: Text("Steps:", style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600)),
                     ),
                   ),
                   Container(
                     width: double.infinity,
                     decoration: BoxDecoration(
                       color: Theme.of(context).colorScheme.surfaceContainerLowest, // Use a slightly different background for steps
                       borderRadius: BorderRadius.circular(4),
                       border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.5))
                     ),
                     padding: const EdgeInsets.all(10.0),
                     child: Column(
                       crossAxisAlignment: CrossAxisAlignment.start,
                       children: steps.map((step) {
                         if (step is Map<String, dynamic>) {
                           final String action = step['action']?.toString() ?? 'No action description';
                           final String stepStatus = step['status']?.toString() ?? 'UNKNOWN';
                           return Padding(
                             padding: const EdgeInsets.symmetric(vertical: 4.0),
                             child: Row(
                               crossAxisAlignment: CrossAxisAlignment.start,
                               children: [
                                 Expanded(child: SelectableText("• $action", style: Theme.of(context).textTheme.bodySmall)),
                                 const SizedBox(width: 8),
                                 Text(stepStatus, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: _getStepStatusColor(context, stepStatus), fontWeight: FontWeight.w500)),
                               ],
                             ),
                           );
                         }
                         return const SizedBox.shrink();
                       }).toList(),
                     ),
                   ),
                   const SizedBox(height: 10),
                 ]
               ],
             ),
     );
   }
}

// Widget for video player (requires video_player package)
class _VideoPlayerWidget extends StatefulWidget {
  final String videoUrl;

  const _VideoPlayerWidget({required this.videoUrl});

  @override
  _VideoPlayerWidgetState createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<_VideoPlayerWidget> {
  late VideoPlayerController _controller;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl))
      ..initialize().then((_) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _controller.play();
          });
        }
      }).catchError((e) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _error = e.toString();
          });
        }
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      return Center(child: Text('Failed to load video: $_error'));
    } else {
      return AspectRatio(
        aspectRatio: _controller.value.aspectRatio,
        child: Stack(
          children: [
            VideoPlayer(_controller),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            VideoProgressIndicator(_controller, allowScrubbing: true),
            Center(
              child: IconButton(
                icon: Icon(
                  _controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
                  color: Colors.white,
                  size: 50,
                ),
                onPressed: () {
                  setState(() {
                    _controller.value.isPlaying ? _controller.pause() : _controller.play();
                  });
                },
              ),
            ),
          ],
        ),
      );
    }
  }
}

// --- NEW: Project Results Screen ---

class ProjectResultsScreen extends StatefulWidget {
  static const routeName = '/project-results';

  final ApiService? apiService; // Make ApiService nullable or required

  const ProjectResultsScreen({super.key, this.apiService}); // Use super.key

  @override
  State<ProjectResultsScreen> createState() => _ProjectResultsScreenState();
}

class _ProjectResultsScreenState extends State<ProjectResultsScreen> {
  late Future<List<TestResult>> _projectResultsFuture;
  String? _initialProjectFromArg; // Project name passed via route arguments
  String? _selectedProject; // Starts as null
late ApiService _apiService;


  List<String> _allProjectNamesForDropdown = [];
  bool _isLoadingProjectList = true; // For loading project list for dropdown

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // This logic runs when dependencies change, including when arguments are first available.
    _apiService = widget.apiService ?? ApiService(); 

    if (_initialProjectFromArg == null && _allProjectNamesForDropdown.isEmpty) { // Check if already processed
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is String) {
        _initialProjectFromArg = args;
        if (_selectedProject != _initialProjectFromArg) {
          _selectedProject = _initialProjectFromArg;
          _fetchResultsForSelectedProject();
        }
      } else {
        // No argument, means we are on the "Results" tab. Fetch projects for dropdown.
        _fetchProjectListForDropdown();
        _projectResultsFuture = Future.value([]); // Initial empty state
      }
    } else if (_initialProjectFromArg == null && _selectedProject == null && _allProjectNamesForDropdown.isNotEmpty) {
      // If in dropdown mode, no project selected yet, but projects are loaded, select first one.
      // _selectedProject = _allProjectNamesForDropdown.first;
      // _fetchResultsForSelectedProject();
      // Or, let user select explicitly. For now, initialize future to empty.
       _projectResultsFuture = Future.value([]);
    }
  }

   // Public method to allow parent to trigger a refresh
  void refreshData() {
    if (_selectedProject != null && !_selectedProject!.startsWith("Error:")) {
      _fetchResultsForSelectedProject();
    } else if (_initialProjectFromArg == null) { // If no specific project, refresh list for dropdown
      _fetchProjectListForDropdown();
    }
  }

  Future<void> _fetchProjectListForDropdown() async {
    setState(() { _isLoadingProjectList = true; });
    try {
      final statuses = await _apiService.fetchQueueStatuses(); // Or a dedicated endpoint for projects
      _allProjectNamesForDropdown = statuses.map((s) => s.project).toSet().toList();
      // if (_allProjectNamesForDropdown.isNotEmpty && _selectedProject == null) {
      //   _selectedProject = _allProjectNamesForDropdown.first;
      //   _fetchResultsForSelectedProject();
      // }
    } catch (e) {
      print("Error fetching project list: $e");
      if (mounted) setState(() => _projectResultsFuture = Future.error("Failed to load project list: $e"));
    } finally {
      if (mounted) setState(() { _isLoadingProjectList = false; });
    }
  }

  void _fetchResultsForSelectedProject() {
    if (_selectedProject != null && !_selectedProject!.startsWith("Error:")) {
      setState(() {
        _projectResultsFuture = _apiService.fetchProjectResults(_selectedProject!);
      });
    }
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'N/A';
    return DateFormat.yMd().add_jms().format(date);
  }

  Color _getPassRateColor(BuildContext context, String? rateString) {
    final numericRate = TestResult(jobId: '', project: '', status: '', messages: [], durationSeconds: 0, screenshots: [], videos: [], passRateString: rateString).passRateNumericValue; // Temp TestResult to use parser
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (numericRate != null) {
      if (numericRate > 90) return isDark ? Colors.green.shade400 : Colors.green.shade700;
      if (numericRate > 70) return isDark ? Colors.amber.shade400 : Colors.amber.shade700;
      return isDark ? Colors.red.shade400 : Colors.red.shade700;
    }
    return Theme.of(context).textTheme.bodyLarge?.color ?? (Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black);
  }


Widget _buildStatusChip(BuildContext context, String status) {
  Color chipColor;
  Color labelColor = Colors.white;
  IconData? iconData;
  final bool isDark = Theme.of(context).brightness == Brightness.dark;

  switch (status.toUpperCase()) {
    case 'PENDING': chipColor = isDark ? Colors.orange.shade300 : Colors.orange.shade700; labelColor = isDark ? Colors.black : Colors.white; iconData = Icons.pending_outlined; break;
    case 'RUNNING': chipColor = isDark ? Colors.blue.shade300 : Colors.blue.shade700; labelColor = isDark ? Colors.black : Colors.white; iconData = Icons.directions_run; break;
    case 'PASSED': chipColor = isDark ? Colors.green.shade300 : Colors.green.shade700; labelColor = isDark ? Colors.black : Colors.white; iconData = Icons.check_circle_outline; break;
    case 'FAILED': chipColor = isDark ? Colors.red.shade300 : Colors.red.shade700; labelColor = isDark ? Colors.black : Colors.white; iconData = Icons.error_outline; break;
    case 'SKIPPED': chipColor = Colors.grey.shade500; labelColor = Colors.white; iconData = Icons.skip_next_outlined; break;
    case 'RETEST': chipColor = isDark ? Colors.amber.shade300 : Colors.amber.shade700; labelColor = isDark ? Colors.black : Colors.white; iconData = Icons.replay_outlined; break;
    case 'CRITICAL': chipColor = isDark ? Colors.red.shade700 : Colors.red.shade900; labelColor = isDark ? Colors.black : Colors.white; iconData = Icons.dangerous_outlined; break;
    case 'CANCELLED': chipColor = isDark ? Colors.grey.shade600 : Colors.black54; labelColor = Colors.white; iconData = Icons.cancel_outlined; break;
    case 'ERROR': chipColor = isDark ? Colors.purple.shade200 : Colors.purple.shade700; labelColor = isDark ? Colors.black : Colors.white; iconData = Icons.report_problem_outlined; break;
    default: chipColor = Colors.grey; labelColor = Colors.white; iconData = Icons.help_outline;
  }
  return SizedBox( // Constrain the width of the chip
    width: 250, // 
    child: Chip(
      avatar: iconData != null ? Icon(iconData, color: labelColor, size: 16) : null,
      label: Text(status, overflow: TextOverflow.ellipsis), // Handle potential overflow
      backgroundColor: chipColor,
      labelStyle: TextStyle(color: labelColor, fontWeight: FontWeight.bold),
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
      visualDensity: VisualDensity.compact,
    ),
  );
}

  @override
  Widget build(BuildContext context) {
    String appBarTitle;
    if (_initialProjectFromArg != null) {
      appBarTitle = 'Results for $_initialProjectFromArg';
    } else if (_selectedProject != null) {
      appBarTitle = 'Results for $_selectedProject';
    } else {
      appBarTitle = 'Select Project Results';
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(appBarTitle),
        actions: [
          if (_selectedProject != null && !_selectedProject!.startsWith("Error:"))
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _fetchResultsForSelectedProject,
              tooltip: 'Refresh Results',
            ),
        ],
      ),
      body: SelectionArea(
        child: Column(
          children: [
            // Show Dropdown only if no initial project was passed via arguments
            if (_initialProjectFromArg == null)
              Padding(
               padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 8.0), // Adjusted padding for better spacing
                child: _isLoadingProjectList
                    ? const Center(child: CircularProgressIndicator())
                    : (_allProjectNamesForDropdown.isEmpty
                        ? const Center(child: Text("No projects found to select."))
                        : Align(
                          alignment: Alignment.centerLeft,
                          child:  SizedBox( // Constrain the width of the dropdown
                            width: 300, // Adjust this width as needed
                              child:  Align(
                              alignment: Alignment.centerLeft,
                              child:
                              DropdownButtonFormField<String>(
                                alignment: Alignment.centerLeft ,
                                decoration: InputDecoration(
                                  labelText: 'Project',
                                  hintText: 'Select a project', 
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8.0),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
                                ),
                               value: _selectedProject,
                                // isExpanded: false, 
                                icon: const Icon(Icons.arrow_drop_down_rounded),
                                
                                items: _allProjectNamesForDropdown.map<DropdownMenuItem<String>>((String value) {

                                  return DropdownMenuItem<String>(
                                    value: value,
                                    child: Text(value),
                                  );
                                }).toList(),
                                onChanged: (String? newValue) {
                                  setState(() {
                                    _selectedProject = newValue;
                                    _fetchResultsForSelectedProject();
                                  });
                                },
                                borderRadius: BorderRadius.circular(8.0),
                                dropdownColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                              
                              ),
                          )
                      )
                    )
                    )
              ),
            Expanded(  
                child :Align(
                          alignment: Alignment.topLeft,
                          child: FutureBuilder<List<TestResult>>(
                future: _projectResultsFuture,
                builder: (context, snapshot) {
                  
                  // Handle initial state before a project is selected (if in dropdown mode)
                  if (_initialProjectFromArg == null && _selectedProject == null && !_isLoadingProjectList) {
                    return const  Align(alignment:Alignment.topLeft, child: Text('Please select a project to view results.'));
                  }
                  if (_selectedProject != null && _selectedProject!.startsWith("Error:")) {
                    return Center( child: Padding( padding: const EdgeInsets.all(16.0), child: Text(_selectedProject!, textAlign: TextAlign.center), ) );
                  }
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center( child: Padding( padding: const EdgeInsets.all(16.0), child: Text('Error loading results for ${_selectedProject ?? _initialProjectFromArg ?? 'project'}: ${snapshot.error}', textAlign: TextAlign.center), ) );
                  }
                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    if (_selectedProject == null && _initialProjectFromArg == null) { // No project selected yet
                        return const Center(child: Text('Select a project to see results.'));
                    }
                    return Align(alignment:Alignment.topLeft, child: Text('No results found for project ${_selectedProject ?? _initialProjectFromArg}.'));
                  }

                  // Filter jobs by status
                  final allJobs = snapshot.data!;
                  final filteredJobs = allJobs.where((job) {
                    final status = job.status.toUpperCase();
                    return status == 'PASSED' || status == 'FAILED' || status == 'ERROR';
                  }).toList();

                  if (filteredJobs.isEmpty) {
                    return Align(alignment:Alignment.topLeft, child: Text('No PASSED, FAILED, or ERROR results found for project ${_selectedProject ?? _initialProjectFromArg}.'));
                  }
                  final dataTableTheme = Theme.of(context).dataTableTheme;

                  return SingleChildScrollView( scrollDirection: Axis.vertical, child: SingleChildScrollView( scrollDirection: Axis.horizontal, child: DataTable(
                        
                        headingTextStyle: dataTableTheme.headingTextStyle,
                        columnSpacing: dataTableTheme.columnSpacing,
                        dataRowMinHeight: dataTableTheme.dataRowMinHeight,
                        dataRowMaxHeight: dataTableTheme.dataRowMaxHeight,
                        columns: const [
                          DataColumn(label: Text('Status')),
                          DataColumn(label: Text('Job ID')),
                          DataColumn(label: Text('Build')), // Changed from Metadata
                          DataColumn(label: Text('Platform')),   // New Platform column
                          DataColumn(label: Text('Environment')),// New Environment column
                          DataColumn(label: Text('Suite')),      // New Suite column
                          DataColumn(label: Text('Progress')),
                          DataColumn(label: Text('Pass Rate')),
                          DataColumn(label: Text('Duration'), numeric: true),
                          DataColumn(label: Text('Finished')),
                        ],
                        rows: filteredJobs.map((job) => DataRow( key: ValueKey(job.jobId),
                         cells: [ DataCell(_buildStatusChip(context, job.status)),
                         DataCell( Tooltip(message: job.jobId, child: Text(job.jobId.length > 12 ? '${job.jobId.substring(0, 12)}...' : job.jobId)),
                            onTap: () async { // Make onTap async
                              await Navigator.pushNamed(context, JobResultScreen.routeName, arguments: job.jobId); // Await navigation
                              if (_selectedProject != null) { // Only refresh if a project is selected
                                _fetchResultsForSelectedProject(); // Refresh data when returning
                              }
                            }),
                            DataCell(Text(job.details?['build_version']?.toString() ?? 'N/A')), // Display build_version
                            DataCell(Text(job.details?['platform']?.toString() ?? 'N/A')),      // Display platform
                            DataCell(Text(job.details?['environment']?.toString() ?? 'N/A')), // Display environment
                            DataCell(Text(job.details?['suite_name']?.toString() ?? job.details?['suite']?.toString() ?? 'N/A')), // Display suite_name or suite
                            DataCell(Text(job.displayProgress)),
                            DataCell(Text(job.displayPassRate, style: TextStyle(color: _getPassRateColor(context, job.passRateString)))),
                            DataCell(Text(job.durationSeconds.toStringAsFixed(2), overflow: TextOverflow.ellipsis)),
                            DataCell(Text(_formatDate(job.endedAt)))
                         ],
                        )).toList(),
                  ), ), );
                },
              ),
            ),
            )
          ],
        ),
      ),
    );
  }
}