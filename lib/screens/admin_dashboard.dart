// ════════════════════════════════════════════════════════════════════════════
// admin_dashboard.dart  — mess-menu blue palette
// ════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'student_dashboard.dart';
import 'warden_dashboard.dart';
import 'tutor_dashboard.dart';
import '../screens/login_page.dart';
import '../screens/settings_page.dart';

// ─────────────────────────────────────────────────────────────────────────────
// COLOUR HELPER
// ─────────────────────────────────────────────────────────────────────────────

class _AC {
  final bool dark;
  const _AC(this.dark);
  factory _AC.of(BuildContext ctx) =>
      _AC(Theme.of(ctx).brightness == Brightness.dark);

  Color get blue        => const Color(0xFF1C5FC5);
  Color get blueDark    => dark ? const Color(0xFF0E1A30) : const Color(0xFF1248A8);
  Color get blueBg      => dark ? const Color(0xFF111C30) : const Color(0xFFF0F5FF);
  Color get blueBorder  => dark ? const Color(0xFF1E3060) : const Color(0xFFD0DFF8);
  Color get appBar      => dark ? const Color(0xFF0A0D18) : const Color(0xFF1248A8);
  Color get white       => dark ? const Color(0xFF1A1D2B) : Colors.white;
  Color get scaffold    => dark ? const Color(0xFF12141F) : Colors.white;
  Color get ink         => dark ? const Color(0xFFE4E8F5) : const Color(0xFF1A1F36);
  Color get textGrey    => dark ? const Color(0xFF7A85A0) : const Color(0xFF6B7280);
  Color get divider     => dark ? const Color(0xFF222638) : const Color(0xFFE8EDF5);
  Color get success     => const Color(0xFF059669);
  Color get danger      => const Color(0xFFDC2626);
  Color get warn        => const Color(0xFFD97706);
  Color get surface     => dark ? const Color(0xFF1A1D2B) : const Color(0xFFF8FAFF);

  ColorScheme toColorScheme(BuildContext ctx) => Theme.of(ctx).colorScheme;
}

// ─────────────────────────────────────────────────────────────────────────────
// SHARED PDF HELPERS
// ─────────────────────────────────────────────────────────────────────────────

String _fmtTs(dynamic ts) {
  if (ts == null) return '—';
  if (ts is Timestamp) return DateFormat('dd MMM yyyy, hh:mm a').format(ts.toDate());
  return ts.toString();
}

pw.Widget _pdfHeader(String title, String subtitle) {
  return pw.Container(
    padding: const pw.EdgeInsets.all(14),
    decoration: pw.BoxDecoration(
      color: const PdfColor(0.07, 0.28, 0.77),
      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
    ),
    child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Text(title,
          style: pw.TextStyle(
              fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
      pw.SizedBox(height: 4),
      pw.Text(subtitle,
          style: pw.TextStyle(fontSize: 10, color: PdfColors.white)),
    ]),
  );
}

pw.Widget _pdfSummaryCards(List<Map<String, dynamic>> cards) {
  return pw.Row(
    children: cards.asMap().entries.map((e) {
      final card = e.value;
      return pw.Expanded(
        child: pw.Container(
          margin: pw.EdgeInsets.only(left: e.key == 0 ? 0 : 6),
          padding: const pw.EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: pw.BoxDecoration(
            color: PdfColors.white,
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
            border: pw.Border.all(color: PdfColors.grey300),
          ),
          child: pw.Column(children: [
            pw.Text(card['value'],
                style: pw.TextStyle(
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                    color: card['color'] as PdfColor)),
            pw.SizedBox(height: 4),
            pw.Text(card['label'],
                style: pw.TextStyle(fontSize: 8.5, color: PdfColors.grey600),
                textAlign: pw.TextAlign.center),
          ]),
        ),
      );
    }).toList(),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// ADMIN DASHBOARD
// ══════════════════════════════════════════════════════════════════════════════

class AdminDashboard extends StatelessWidget {
  const AdminDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    final c = _AC.of(context);
    final String todayDate = DateFormat('EEEE, d MMM yyyy').format(DateTime.now());

    return Scaffold(
      backgroundColor: c.scaffold,
      appBar: AppBar(
        backgroundColor: c.appBar,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pushReplacement(
              context, MaterialPageRoute(builder: (_) => const LoginPage())),
        ),
        title: const Text('Admin Dashboard',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white),
            tooltip: 'Settings',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SettingsPage(
                  role: UserRole.admin,
                  onLogout: () async {
                    Navigator.pushAndRemoveUntil(
                        context,
                        MaterialPageRoute(builder: (_) => const LoginPage()),
                            (r) => false);
                  },
                ),
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Welcome, Admin',
              style: TextStyle(
                  fontSize: 22, fontWeight: FontWeight.bold, color: c.ink)),
          const SizedBox(height: 4),
          Text(todayDate,
              style: TextStyle(fontSize: 16, color: c.blue)),
          const SizedBox(height: 20),
          _buildStatisticsSection(context, c),
          const SizedBox(height: 20),
          Text('Dashboard Access',
              style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.bold, color: c.ink)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
                child: _buildFeatureCard(context, c,
                    icon: Icons.person,
                    iconColor: c.blue,
                    title: 'Student Dashboard',
                    subtitle: 'View student interface',
                    page: const StudentDashboard())),
            const SizedBox(width: 12),
            Expanded(
                child: _buildFeatureCard(context, c,
                    icon: Icons.school,
                    iconColor: c.success,
                    title: 'Tutor Dashboard',
                    subtitle: 'Manage permission requests',
                    page: const TutorDashboard())),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
                child: _buildFeatureCard(context, c,
                    icon: Icons.admin_panel_settings,
                    iconColor: const Color(0xFF7C3AED),
                    title: 'Warden Dashboard',
                    subtitle: 'Hostel administration',
                    page: const WardenDashboard())),
            const SizedBox(width: 12),
            const Expanded(child: SizedBox()),
          ]),
          const SizedBox(height: 20),
          Text('Admin Features',
              style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.bold, color: c.ink)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
                child: _buildFeatureCard(context, c,
                    icon: Icons.people,
                    iconColor: c.blue,
                    title: 'User Management',
                    subtitle: 'Manage students, tutors & wardens',
                    page: const UserManagementPage())),
            const SizedBox(width: 12),
            Expanded(
                child: _buildFeatureCard(context, c,
                    icon: Icons.analytics,
                    iconColor: c.warn,
                    title: 'Reports & Analytics',
                    subtitle: 'View system reports',
                    page: const ReportsPage())),
          ]),
        ]),
      ),
    );
  }

  Widget _buildStatisticsSection(BuildContext context, _AC c) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Hostel Overview',
          style: TextStyle(
              fontSize: 20, fontWeight: FontWeight.bold, color: c.ink)),
      const SizedBox(height: 12),
      GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.5,
        children: [
          _buildStatCard(context, c, 'Total Students', '245', Icons.people, c.blue),
          _buildStatCard(context, c, 'Total Rooms', '120', Icons.meeting_room, c.success),
          _buildStatCard(context, c, 'Pending Requests', '12', Icons.pending_actions, c.warn),
          _buildStatCard(context, c, 'Active Complaints', '5', Icons.report_problem, c.danger),
        ],
      ),
    ]);
  }

  Widget _buildStatCard(BuildContext context, _AC c, String title,
      String count, IconData icon, Color color) {
    return Container(
      decoration: BoxDecoration(
        color: c.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.blueBorder),
        boxShadow: [BoxShadow(
            color: Colors.black.withOpacity(c.dark ? 0.3 : 0.06),
            blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 32, color: color),
          const SizedBox(height: 6),
          Text(count,
              style: TextStyle(
                  fontSize: 22, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 4),
          Text(title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 12,
                  color: c.textGrey,
                  fontWeight: FontWeight.w500)),
        ]),
      ),
    );
  }

  Widget _buildFeatureCard(BuildContext context, _AC c,
      {required IconData icon,
        required Color iconColor,
        required String title,
        required String subtitle,
        required Widget page}) {
    return GestureDetector(
      onTap: () =>
          Navigator.push(context, MaterialPageRoute(builder: (_) => page)),
      child: Container(
        height: 160,
        decoration: BoxDecoration(
          color: c.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: iconColor.withOpacity(0.3), width: 1.5),
          boxShadow: [BoxShadow(
              color: iconColor.withOpacity(0.10),
              blurRadius: 10,
              offset: const Offset(0, 4))],
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
              width: 60, height: 60,
              decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16)),
              child: Icon(icon, size: 32, color: iconColor)),
          const SizedBox(height: 12),
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(title,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: c.ink),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis)),
          const SizedBox(height: 4),
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(subtitle,
                  style: TextStyle(fontSize: 11, color: c.textGrey),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis)),
        ]),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// REPORTS PAGE
// ══════════════════════════════════════════════════════════════════════════════

class ReportsPage extends StatelessWidget {
  const ReportsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final c = _AC.of(context);
    return Scaffold(
      backgroundColor: c.scaffold,
      appBar: AppBar(
        backgroundColor: c.appBar,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Reports & Analytics',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          Text('Available Reports',
              style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.bold, color: c.ink)),
          const SizedBox(height: 12),
          _buildReportCard(context, c, 'Weekly Complaints Report',
              'Student complaints & progress for this week',
              Icons.assignment_turned_in, const Color(0xFFEA580C),
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const WeeklyComplaintsReportPage()))),
          _buildReportCard(context, c, 'Weekly Permission Requests',
              'All student permission requests for the last 7 days with tutor approval status',
              Icons.assignment_turned_in, const Color(0xFF4F46E5),
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const WeeklyPermissionRequestsReportPage()))),
          _buildReportCard(context, c, 'Gate Pass Report',
              'Students who went out in the last 7 days with full details',
              Icons.exit_to_app, const Color(0xFF0D9488),
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const WeeklyGatePassReportPage()))),
          _buildReportCard(context, c, 'Mess Feedback',
              'Food quality and satisfaction ratings for the last 7 days',
              Icons.restaurant, const Color(0xFF7C3AED),
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const MessFeedbackReportPage()))),
        ],
      ),
    );
  }

  Widget _buildReportCard(BuildContext context, _AC c, String title,
      String subtitle, IconData icon, Color color, {VoidCallback? onTap}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: c.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.blueBorder),
        boxShadow: [BoxShadow(
            color: Colors.black.withOpacity(c.dark ? 0.25 : 0.05),
            blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: ListTile(
        onTap: onTap,
        leading: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: color, size: 28)),
        title: Text(title,
            style: TextStyle(fontWeight: FontWeight.bold, color: c.ink)),
        subtitle: Text(subtitle,
            style: TextStyle(color: c.textGrey)),
        trailing: Icon(Icons.chevron_right, color: c.textGrey),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// MESS FEEDBACK REPORT PAGE
// ══════════════════════════════════════════════════════════════════════════════

class MessFeedbackReportPage extends StatefulWidget {
  const MessFeedbackReportPage({super.key});
  @override
  State<MessFeedbackReportPage> createState() => _MessFeedbackReportPageState();
}

class _MessFeedbackReportPageState extends State<MessFeedbackReportPage> {
  bool _isLoading = true;
  bool _isGenerating = false;
  List<Map<String, dynamic>> _feedbacks = [];

  String _filterMeal = 'All';
  String _filterRating = 'All';

  static const _meals = ['All', 'Morning', 'Afternoon', 'Night'];
  static const _ratingLabels = ['All', '1', '2', '3', '4', '5'];

  @override
  void initState() {
    super.initState();
    _fetchFeedbacks();
  }

  Future<void> _fetchFeedbacks() async {
    setState(() => _isLoading = true);
    try {
      final weekAgo = DateTime.now().subtract(const Duration(days: 7));
      final weekAgoTs = Timestamp.fromDate(weekAgo);
      final snapshot = await FirebaseFirestore.instance
          .collection('mess_feedbacks')
          .where('submittedAt', isGreaterThanOrEqualTo: weekAgoTs)
          .orderBy('submittedAt', descending: true)
          .get();
      final loaded = snapshot.docs.map((doc) {
        final d = Map<String, dynamic>.from(doc.data());
        d['_docId'] = doc.id;
        return d;
      }).toList();
      if (mounted) setState(() => _feedbacks = loaded);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Error loading feedback: $e'),
            backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<Map<String, dynamic>> get _filtered {
    return _feedbacks.where((f) {
      final meal = (f['meal'] ?? '').toString();
      final rating = _parseRating(f['rating']);
      if (_filterMeal != 'All' && meal != _filterMeal) return false;
      if (_filterRating != 'All' && rating != _filterRatingInt) return false;
      return true;
    }).toList();
  }

  int get _filterRatingInt {
    final idx = _ratingLabels.indexOf(_filterRating);
    return idx > 0 ? idx : 0;
  }

  int _parseRating(dynamic v) => int.tryParse((v ?? 0).toString()) ?? 0;

  double get _avgRating {
    if (_filtered.isEmpty) return 0;
    final sum = _filtered.fold<int>(0, (s, f) => s + _parseRating(f['rating']));
    return sum / _filtered.length;
  }

  Map<int, int> get _ratingDist {
    final dist = {1: 0, 2: 0, 3: 0, 4: 0, 5: 0};
    for (final f in _filtered) {
      final r = _parseRating(f['rating']).clamp(1, 5);
      dist[r] = (dist[r] ?? 0) + 1;
    }
    return dist;
  }

  Map<String, double> get _mealAvgRating {
    final Map<String, List<int>> byMeal = {};
    for (final f in _feedbacks) {
      final meal = (f['meal'] ?? 'Unknown').toString();
      byMeal.putIfAbsent(meal, () => []).add(_parseRating(f['rating']));
    }
    return {
      for (final e in byMeal.entries)
        e.key: e.value.isEmpty
            ? 0
            : e.value.reduce((a, b) => a + b) / e.value.length
    };
  }

  Color _ratingColor(int r) {
    if (r >= 4) return const Color(0xFF059669);
    if (r == 3) return const Color(0xFFD97706);
    return const Color(0xFFDC2626);
  }

  String _ratingLabel(int r) {
    switch (r) {
      case 5: return 'Excellent';
      case 4: return 'Great';
      case 3: return 'Good';
      case 2: return 'Fair';
      case 1: return 'Poor';
      default: return '—';
    }
  }

  String _mealEmoji(String meal) {
    switch (meal) {
      case 'Morning': return '☀️';
      case 'Afternoon': return '🌤';
      case 'Night': return '🌙';
      default: return '🍽';
    }
  }

  String _formatTs(dynamic ts) {
    if (ts == null) return '—';
    if (ts is Timestamp)
      return DateFormat('dd MMM yyyy, hh:mm a').format(ts.toDate());
    return ts.toString();
  }

  Future<void> _generatePdf() async {
    setState(() => _isGenerating = true);
    try {
      final pdf = pw.Document();
      final now = DateTime.now();
      final dateRange =
          '${DateFormat('dd MMM yyyy').format(now.subtract(const Duration(days: 7)))} – ${DateFormat('dd MMM yyyy').format(now)}';
      pdf.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (ctx) => [
          _pdfHeader('Mess Feedback Report', dateRange),
          pw.SizedBox(height: 16),
          _pdfSummaryCards([
            {'label': 'Total', 'value': '${_feedbacks.length}', 'color': PdfColors.blue700},
            {
              'label': 'Average Rating',
              'value': _avgRating.toStringAsFixed(1),
              'color': _avgRating >= 4
                  ? PdfColors.green700
                  : _avgRating >= 3
                  ? PdfColors.orange700
                  : PdfColors.red700
            },
            {
              'label': '5 Stars',
              'value': '${_feedbacks.where((f) => _parseRating(f['rating']) == 5).length}',
              'color': PdfColors.green700
            },
            {
              'label': '1 Star',
              'value': '${_feedbacks.where((f) => _parseRating(f['rating']) == 1).length}',
              'color': PdfColors.red700
            },
          ]),
          pw.SizedBox(height: 20),
          _pdfFeedbackTable(),
        ],
      ));
      await Printing.layoutPdf(
        onLayout: (fmt) async => pdf.save(),
        name: 'Mess_Feedback_Report_${DateFormat('dd-MM-yyyy').format(now)}.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Failed to generate PDF: $e'),
            backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  pw.Widget _pdfFeedbackTable() {
    final headers = ['#', 'Student', 'Roll', 'Room', 'Meal', 'Rating', 'Comment', 'Submitted'];
    final colWidths = [18.0, 75.0, 55.0, 32.0, 48.0, 35.0, 165.0, 90.0];

    pw.Widget hc(String t) => pw.Container(
        padding: const pw.EdgeInsets.symmetric(vertical: 7, horizontal: 5),
        color: const PdfColor(0.07, 0.37, 0.77),
        child: pw.Text(t,
            style: pw.TextStyle(
                fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white)));

    pw.Widget dc(String text, {PdfColor? textColor}) => pw.Container(
        padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 5),
        child: pw.Text(text,
            style: pw.TextStyle(
                fontSize: 8,
                color: textColor ?? PdfColors.black,
                fontWeight: textColor != null ? pw.FontWeight.bold : pw.FontWeight.normal)));

    PdfColor starColor(int r) {
      if (r >= 4) return PdfColors.green700;
      if (r == 3) return PdfColors.orange700;
      return PdfColors.red700;
    }

    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Text('Feedback Details',
          style: pw.TextStyle(
              fontSize: 13, fontWeight: pw.FontWeight.bold, color: const PdfColor(0.07, 0.37, 0.77))),
      pw.SizedBox(height: 10),
      if (_feedbacks.isEmpty)
        pw.Text('No feedback submitted in the last 7 days.',
            style: pw.TextStyle(color: PdfColors.grey600, fontSize: 10))
      else
        pw.Table(
          columnWidths: {
            for (int i = 0; i < colWidths.length; i++)
              i: pw.FixedColumnWidth(colWidths[i])
          },
          border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
          children: [
            pw.TableRow(children: headers.map(hc).toList()),
            ..._feedbacks.asMap().entries.map((entry) {
              final idx = entry.key;
              final f = entry.value;
              final rating = _parseRating(f['rating']);
              final comment = (f['comment'] ?? f['feedback'] ?? '—').toString();
              final shortComment =
              comment.length > 55 ? '${comment.substring(0, 55)}...' : comment;
              return pw.TableRow(
                decoration: pw.BoxDecoration(
                    color: idx % 2 == 0 ? PdfColors.grey50 : PdfColors.white),
                children: [
                  dc('${idx + 1}'),
                  dc((f['name'] ?? f['studentName'] ?? '—').toString()),
                  dc((f['rollNo'] ?? f['regNo'] ?? '—').toString()),
                  dc((f['roomNo'] ?? '—').toString()),
                  dc((f['meal'] ?? '—').toString()),
                  dc('$rating', textColor: starColor(rating)),
                  dc(shortComment),
                  dc(_formatTs(f['submittedAt'] ?? f['at'])),
                ],
              );
            }),
          ],
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final c = _AC.of(context);
    final filtered = _filtered;
    final avg = _avgRating;
    final dist = _ratingDist;
    final mealAvgs = _mealAvgRating;
    final dateRangeStr =
        '${DateFormat('dd MMM').format(DateTime.now().subtract(const Duration(days: 7)))} - ${DateFormat('dd MMM yyyy').format(DateTime.now())}';

    return Scaffold(
      backgroundColor: c.scaffold,
      appBar: AppBar(
        backgroundColor: c.appBar,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Mess Feedback Report',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white),
              tooltip: 'Refresh',
              onPressed: _fetchFeedbacks),
          IconButton(
            tooltip: 'Download PDF',
            icon: _isGenerating
                ? const SizedBox(
                width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.picture_as_pdf, color: Colors.white),
            onPressed: _isGenerating ? null : _generatePdf,
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: c.blue))
          : Column(children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          color: c.blueDark,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Mess Feedback Overview',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(dateRangeStr,
                style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 13)),
          ]),
        ),
        Expanded(
          child: _feedbacks.isEmpty
              ? _buildEmptyState(c)
              : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: c.blueBg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: c.blueBorder),
                  ),
                  child: Row(children: [
                    Icon(Icons.cloud_done_rounded, size: 15, color: c.blue),
                    const SizedBox(width: 8),
                    Text(
                        'Live data from Firestore  ·  ${_feedbacks.length} record${_feedbacks.length == 1 ? '' : 's'} loaded',
                        style: TextStyle(fontSize: 12, color: c.blue, fontWeight: FontWeight.w600)),
                  ]),
                ),
                Row(children: [
                  _summaryChip(c, 'Total', _feedbacks.length, c.blue),
                  const SizedBox(width: 8),
                  _summaryChip(c, 'Avg',
                      double.parse(avg.toStringAsFixed(1)).toString(),
                      avg >= 4 ? c.success : avg >= 3 ? c.warn : c.danger,
                      suffix: '★'),
                  const SizedBox(width: 8),
                  _summaryChip(c, '5 Stars',
                      _feedbacks.where((f) => _parseRating(f['rating']) == 5).length,
                      c.success),
                  const SizedBox(width: 8),
                  _summaryChip(c, '1 Star',
                      _feedbacks.where((f) => _parseRating(f['rating']) == 1).length,
                      c.danger),
                ]),
                const SizedBox(height: 16),
                Row(children: ['Morning', 'Afternoon', 'Night'].map((meal) {
                  final a = mealAvgs[meal] ?? 0;
                  final emoji = _mealEmoji(meal);
                  final color = a >= 4 ? c.success : a >= 3 ? c.warn : c.danger;
                  return Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(right: meal != 'Night' ? 8 : 0),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                          decoration: BoxDecoration(
                            color: c.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: c.blueBorder),
                          ),
                          child: Column(children: [
                            Text(emoji, style: const TextStyle(fontSize: 18)),
                            const SizedBox(height: 4),
                            Text(a.toStringAsFixed(1),
                                style: TextStyle(
                                    fontSize: 20, fontWeight: FontWeight.w900, color: color)),
                            Text('/ 5.0',
                                style: TextStyle(fontSize: 10, color: c.textGrey)),
                            const SizedBox(height: 2),
                            Text(meal,
                                style: TextStyle(
                                    fontSize: 11, fontWeight: FontWeight.w600, color: color)),
                          ]),
                        ),
                      ));
                }).toList()),
                const SizedBox(height: 16),
                _buildRatingDistCard(dist, _feedbacks.length, c),
                const SizedBox(height: 16),
                _buildFilterRow(c),
                const SizedBox(height: 12),
                if (filtered.isEmpty)
                  Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 30),
                        child: Text('No feedbacks match your filters.',
                            style: TextStyle(color: c.textGrey, fontSize: 14)),
                      ))
                else
                  ...filtered.map((f) {
                    final rating = _parseRating(f['rating']);
                    return _buildFeedbackCard(f, rating, _ratingColor(rating), c);
                  }),
              ]),
        ),
      ]),
    );
  }

  Widget _buildEmptyState(_AC c) {
    return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.sentiment_satisfied_alt, size: 72, color: c.blueBorder),
          const SizedBox(height: 16),
          Text('No mess feedback this week!',
              style: TextStyle(fontSize: 16, color: c.textGrey)),
        ]));
  }

  Widget _summaryChip(_AC c, String label, dynamic count, Color color,
      {String suffix = ''}) {
    return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Column(children: [
            Text('$count$suffix',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
            Text(label,
                style: TextStyle(fontSize: 10, color: color.withOpacity(0.9)),
                textAlign: TextAlign.center),
          ]),
        ));
  }

  Widget _buildRatingDistCard(Map<int, int> dist, int total, _AC c) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: c.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.blueBorder),
          boxShadow: [BoxShadow(
              color: Colors.black.withOpacity(c.dark ? 0.25 : 0.05),
              blurRadius: 8, offset: const Offset(0, 2))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Rating Distribution',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.ink)),
        const SizedBox(height: 12),
        ...List.generate(5, (i) {
          final star = 5 - i;
          final count = dist[star] ?? 0;
          final pct = total == 0 ? 0.0 : count / total;
          final color = star >= 4 ? c.success : star == 3 ? c.warn : c.danger;
          return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                SizedBox(
                    width: 28,
                    child: Text('$star★',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700, color: color))),
                const SizedBox(width: 8),
                Expanded(
                    child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                            value: pct,
                            minHeight: 10,
                            backgroundColor: c.blueBg,
                            valueColor: AlwaysStoppedAnimation<Color>(color)))),
                const SizedBox(width: 10),
                SizedBox(
                    width: 40,
                    child: Text('$count',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600, color: c.textGrey),
                        textAlign: TextAlign.right)),
                SizedBox(
                    width: 36,
                    child: Text(' ${(pct * 100).toStringAsFixed(0)}%',
                        style: TextStyle(fontSize: 11, color: c.textGrey))),
              ]));
        }),
      ]),
    );
  }

  Widget _buildFilterRow(_AC c) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Filter Feedback',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.textGrey)),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: _dropdownFilter(c,
            label: 'Meal', value: _filterMeal, items: _meals,
            onChanged: (v) => setState(() => _filterMeal = v!))),
        const SizedBox(width: 10),
        Expanded(child: _dropdownFilter(c,
            label: 'Rating', value: _filterRating, items: _ratingLabels,
            onChanged: (v) => setState(() => _filterRating = v!))),
      ]),
    ]);
  }

  Widget _dropdownFilter(_AC c,
      {required String label, required String value,
        required List<String> items, required void Function(String?) onChanged}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
          border: Border.all(color: c.blueBorder),
          borderRadius: BorderRadius.circular(8),
          color: c.blueBg),
      child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: value, isExpanded: true, hint: Text(label),
            dropdownColor: c.white,
            style: TextStyle(fontSize: 13, color: c.ink),
            items: items
                .map((item) => DropdownMenuItem(value: item, child: Text(item)))
                .toList(),
            onChanged: onChanged,
          )),
    );
  }

  Widget _buildFeedbackCard(Map<String, dynamic> f, int rating, Color color, _AC c) {
    final meal = (f['meal'] ?? '—').toString();
    final day = (f['day'] ?? '—').toString();
    final name = (f['name'] ?? f['studentName'] ?? '—').toString();
    final rollNo = (f['rollNo'] ?? f['regNo'] ?? '—').toString();
    final roomNo = (f['roomNo'] ?? '—').toString();
    final dept = (f['dept'] ?? '—').toString();
    final comment = (f['comment'] ?? f['feedback'] ?? '—').toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
          color: c.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.35), width: 1.5),
          boxShadow: [BoxShadow(
              color: Colors.black.withOpacity(c.dark ? 0.2 : 0.04),
              blurRadius: 8, offset: const Offset(0, 2))]),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                  color: c.blueBg, borderRadius: BorderRadius.circular(20)),
              alignment: Alignment.center,
              child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: TextStyle(color: c.blue, fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            const SizedBox(width: 10),
            Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name,
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700, color: c.ink)),
                  Text('Roll: $rollNo  •  Room: $roomNo  •  $dept',
                      style: TextStyle(fontSize: 11, color: c.textGrey)),
                ])),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: color.withOpacity(0.5))),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.star_rounded, size: 14, color: color),
                const SizedBox(width: 3),
                Text('$rating  ${_ratingLabel(rating)}',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
              ]),
            ),
          ]),
          const SizedBox(height: 10),
          Divider(height: 1, color: c.divider),
          const SizedBox(height: 10),
          Row(children: [
            _infoChip(c, Icons.calendar_today_outlined, day, c.blue),
            const SizedBox(width: 8),
            _infoChip(c, Icons.restaurant_menu_outlined, '${_mealEmoji(meal)} $meal', c.warn),
          ]),
          const SizedBox(height: 10),
          Row(children: List.generate(5, (i) => Icon(
            i < rating ? Icons.star_rounded : Icons.star_outline_rounded,
            color: i < rating ? const Color(0xFFF59E0B) : c.blueBorder,
            size: 18,
          ))),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: c.blueBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: c.blueBorder)),
            child: Text(comment,
                style: TextStyle(fontSize: 13, height: 1.5, color: c.ink)),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Icon(Icons.access_time, size: 12, color: c.textGrey),
            const SizedBox(width: 4),
            Text(_formatTs(f['submittedAt'] ?? f['at']),
                style: TextStyle(fontSize: 11, color: c.textGrey)),
          ]),
        ]),
      ),
    );
  }

  Widget _infoChip(_AC c, IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withOpacity(0.25))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 5),
        Text(label,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// USER MANAGEMENT PAGE
// ══════════════════════════════════════════════════════════════════════════════

class UserManagementPage extends StatefulWidget {
  const UserManagementPage({super.key});
  @override
  State<UserManagementPage> createState() => _UserManagementPageState();
}

class _UserManagementPageState extends State<UserManagementPage> {
  String _selectedRole = 'All';
  final List<String> _roles = ['All', 'Students', 'Tutors', 'Wardens'];
  bool _isLoading = true;
  List<Map<String, dynamic>> _allUsers = [];

  static const Map<String, List<String>> _roleKeys = {
    'Students': ['student', 'Student'],
    'Tutors': ['tutor', 'Tutor'],
    'Wardens': ['warden', 'Warden'],
  };

  int _studentCount = 0, _tutorCount = 0, _wardenCount = 0;

  @override
  void initState() {
    super.initState();
    _fetchUsers();
  }

  Future<void> _fetchUsers() async {
    setState(() => _isLoading = true);
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users').orderBy('name').get();
      final loaded = snapshot.docs.map((doc) {
        final d = Map<String, dynamic>.from(doc.data());
        d['_uid'] = doc.id;
        return d;
      }).toList();
      int students = 0, tutors = 0, wardens = 0;
      for (final u in loaded) {
        final role = (u['role'] ?? '').toString().toLowerCase();
        if (role == 'student') students++;
        else if (role == 'tutor') tutors++;
        else if (role == 'warden') wardens++;
      }
      if (mounted) {
        setState(() {
          _allUsers = loaded;
          _studentCount = students;
          _tutorCount = tutors;
          _wardenCount = wardens;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<Map<String, dynamic>> get _filteredUsers {
    if (_selectedRole == 'All') return _allUsers;
    final keys = _roleKeys[_selectedRole] ?? [];
    return _allUsers.where((u) {
      final role = (u['role'] ?? '').toString();
      return keys.any((k) => k.toLowerCase() == role.toLowerCase());
    }).toList();
  }

  Color _roleColor(String role) {
    switch (role.toLowerCase()) {
      case 'student': return const Color(0xFF1C5FC5);
      case 'tutor': return const Color(0xFF059669);
      case 'warden': return const Color(0xFF7C3AED);
      default: return const Color(0xFF6B7280);
    }
  }

  IconData _roleIcon(String role) {
    switch (role.toLowerCase()) {
      case 'student': return Icons.person;
      case 'tutor': return Icons.school;
      case 'warden': return Icons.admin_panel_settings;
      default: return Icons.person_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _AC.of(context);
    final filtered = _filteredUsers;

    return Scaffold(
      backgroundColor: c.scaffold,
      appBar: AppBar(
        backgroundColor: c.appBar,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('User Management',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white),
              tooltip: 'Refresh',
              onPressed: _fetchUsers),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: c.blue))
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          color: c.blueBg,
          child: Row(children: [
            _countCard(c, 'Students', _studentCount, c.blue, Icons.person),
            const SizedBox(width: 10),
            _countCard(c, 'Tutors', _tutorCount, c.success, Icons.school),
            const SizedBox(width: 10),
            _countCard(c, 'Wardens', _wardenCount, const Color(0xFF7C3AED), Icons.admin_panel_settings),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
                children: _roles.map((role) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedRole = role),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                          color: _selectedRole == role ? c.blue : c.blueBg,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: _selectedRole == role ? c.blue : c.blueBorder,
                              width: 1.5)),
                      child: Text(role,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: _selectedRole == role
                                  ? Colors.white
                                  : c.textGrey)),
                    ),
                  ),
                )).toList()),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
              '${filtered.length} user${filtered.length == 1 ? '' : 's'} found',
              style: TextStyle(
                  fontSize: 13, color: c.textGrey, fontWeight: FontWeight.w500)),
        ),
        Expanded(
            child: filtered.isEmpty
                ? Center(
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.people_outline, size: 64, color: c.blueBorder),
                  const SizedBox(height: 12),
                  Text('No users found',
                      style: TextStyle(fontSize: 15, color: c.textGrey)),
                ]))
                : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              itemCount: filtered.length,
              itemBuilder: (context, index) {
                final u = filtered[index];
                final role = (u['role'] ?? '').toString();
                final color = _roleColor(role);
                final name = (u['name'] ?? u['fullName'] ?? 'Unknown').toString();
                final id = (u['regNo'] ?? u['rollNo'] ?? u['_uid'] ?? '').toString();
                final email = (u['email'] ?? '—').toString();
                final room = (u['roomNo'] ?? '—').toString();
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: c.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: color.withOpacity(0.25)),
                    boxShadow: [BoxShadow(
                        color: Colors.black.withOpacity(c.dark ? 0.2 : 0.04),
                        blurRadius: 4, offset: const Offset(0, 1))],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Row(children: [
                      Container(
                        width: 44, height: 44,
                        decoration: BoxDecoration(
                            color: color.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(10)),
                        alignment: Alignment.center,
                        child: Icon(_roleIcon(role), color: color, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(name,
                                style: TextStyle(
                                    fontWeight: FontWeight.w700, fontSize: 14, color: c.ink)),
                            Text(email,
                                style: TextStyle(fontSize: 12, color: c.textGrey)),
                            if (id.isNotEmpty)
                              Text('ID: $id',
                                  style: TextStyle(fontSize: 11, color: c.textGrey)),
                            if (room != '—')
                              Text('Room: $room',
                                  style: TextStyle(fontSize: 11, color: c.textGrey)),
                          ])),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                            color: color.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: color.withOpacity(0.4))),
                        child: Text(
                          role.isEmpty ? 'Unknown' : role[0].toUpperCase() + role.substring(1),
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
                        ),
                      ),
                    ]),
                  ),
                );
              },
            )),
      ]),
    );
  }

  Widget _countCard(_AC c, String label, int count, Color color, IconData icon) {
    return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
              color: c.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withOpacity(0.25))),
          child: Row(children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 8),
            Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('$count',
                      style: TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold, color: color)),
                  Text(label,
                      style: TextStyle(fontSize: 11, color: color.withOpacity(0.8))),
                ])),
          ]),
        ));
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// SHARED HELPERS
// ══════════════════════════════════════════════════════════════════════════════

Widget _buildSummaryRow(_AC c, List<_ChipData> chips) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    color: c.blueBg,
    child: Row(
        children: chips
            .expand((chip) => [
          Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                    color: chip.color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: chip.color.withOpacity(0.3))),
                child: Column(children: [
                  Text('${chip.count}',
                      style: TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold, color: chip.color)),
                  Text(chip.label,
                      style: TextStyle(fontSize: 10, color: chip.color.withOpacity(0.9)),
                      textAlign: TextAlign.center),
                ]),
              )),
          if (chip != chips.last) const SizedBox(width: 8),
        ])
            .toList()),
  );
}

class _ChipData {
  final String label;
  final int count;
  final Color color;
  const _ChipData(this.label, this.count, this.color);
}

Widget _infoRow(_AC c, IconData icon, String label, String value) {
  return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Icon(icon, size: 15, color: c.blue),
    const SizedBox(width: 6),
    Expanded(
        child: RichText(
            text: TextSpan(children: [
              TextSpan(
                  text: '$label: ',
                  style: TextStyle(
                      fontSize: 12, color: c.textGrey,
                      fontWeight: FontWeight.w500, fontFamily: 'Roboto')),
              TextSpan(
                  text: value,
                  style: TextStyle(
                      fontSize: 12, color: c.ink,
                      fontWeight: FontWeight.w600, fontFamily: 'Roboto')),
            ]))),
  ]);
}

// ══════════════════════════════════════════════════════════════════════════════
// WEEKLY COMPLAINTS REPORT
// ══════════════════════════════════════════════════════════════════════════════

class WeeklyComplaintsReportPage extends StatefulWidget {
  const WeeklyComplaintsReportPage({super.key});
  @override
  State<WeeklyComplaintsReportPage> createState() =>
      _WeeklyComplaintsReportPageState();
}

class _WeeklyComplaintsReportPageState extends State<WeeklyComplaintsReportPage> {
  bool _isLoading = true;
  bool _isGenerating = false;
  List<Map<String, dynamic>> _complaints = [];

  @override
  void initState() {
    super.initState();
    _fetchWeeklyComplaints();
  }

  String? _firstNonEmpty(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final val = map[key]?.toString().trim() ?? '';
      if (val.isNotEmpty) return val;
    }
    return null;
  }

  Future<void> _fetchWeeklyComplaints() async {
    setState(() => _isLoading = true);
    try {
      final weekAgoTs = Timestamp.fromDate(DateTime.now().subtract(const Duration(days: 7)));
      final snapshot = await FirebaseFirestore.instance
          .collection('complaints')
          .where('createdAt', isGreaterThanOrEqualTo: weekAgoTs)
          .orderBy('createdAt', descending: true)
          .get();
      final List<Map<String, dynamic>> loaded = [];
      for (final doc in snapshot.docs) {
        final data = Map<String, dynamic>.from(doc.data());
        data['_docId'] = doc.id;
        data['roomNo'] = (data['roomNumber'] ?? '—').toString();
        final userId = (data['studentUid'] ?? '').toString().trim();
        if (userId.isNotEmpty) {
          try {
            final userDoc = await FirebaseFirestore.instance
                .collection('users').doc(userId).get();
            if (userDoc.exists) {
              final p = userDoc.data()!;
              data['studentName'] = _firstNonEmpty(p, ['name', 'fullName', 'displayName']) ?? '—';
              data['regNo'] = _firstNonEmpty(p, ['regNo', 'rollNo', 'registrationNo']) ?? '—';
            } else {
              data['studentName'] = '—';
              data['regNo'] = '—';
            }
          } catch (_) {
            data['studentName'] = '—';
            data['regNo'] = '—';
          }
        } else {
          data['studentName'] = '—';
          data['regNo'] = '—';
        }
        loaded.add(data);
      }
      if (mounted) setState(() => _complaints = loaded);
    } catch (e) { debugPrint('Error: $e'); }
    finally { if (mounted) setState(() => _isLoading = false); }
  }

  Color _statusColor(String s) {
    switch (s.toLowerCase()) {
      case 'resolved': case 'completed': return const Color(0xFF059669);
      case 'in progress': case 'inprogress': return const Color(0xFFD97706);
      default: return const Color(0xFFDC2626);
    }
  }

  String _formatTs(dynamic ts) => _fmtTs(ts);

  int get _totalCount => _complaints.length;
  int get _pendingCount => _complaints.where((c) => (c['status'] ?? '').toString().toLowerCase() == 'pending').length;
  int get _inProgressCount => _complaints.where((c) { final s = (c['status'] ?? '').toString().toLowerCase(); return s == 'in progress' || s == 'inprogress'; }).length;
  int get _resolvedCount => _complaints.where((c) { final s = (c['status'] ?? '').toString().toLowerCase(); return s == 'resolved' || s == 'completed'; }).length;

  Future<void> _generatePdf() async {
    setState(() => _isGenerating = true);
    try {
      final pdf = pw.Document();
      final now = DateTime.now();
      final dateRange =
          '${DateFormat('dd MMM yyyy').format(now.subtract(const Duration(days: 7)))} – ${DateFormat('dd MMM yyyy').format(now)}';

      pdf.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (ctx) => [
          _pdfHeader('Weekly Complaints Report', dateRange),
          pw.SizedBox(height: 16),
          _pdfSummaryCards([
            {'label': 'Total', 'value': '$_totalCount', 'color': PdfColors.grey700},
            {'label': 'Pending', 'value': '$_pendingCount', 'color': PdfColors.red700},
            {'label': 'In Progress', 'value': '$_inProgressCount', 'color': PdfColors.orange700},
            {'label': 'Resolved', 'value': '$_resolvedCount', 'color': PdfColors.green700},
          ]),
          pw.SizedBox(height: 20),
          _pdfComplaintsTable(),
        ],
      ));

      await Printing.layoutPdf(
        onLayout: (fmt) async => pdf.save(),
        name: 'Weekly_Complaints_Report_${DateFormat('dd-MM-yyyy').format(now)}.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Failed to generate PDF: $e'),
            backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  pw.Widget _pdfComplaintsTable() {
    final headers = ['#', 'Student', 'Reg No', 'Room', 'Category', 'Description', 'Status', 'Raised On'];
    final colWidths = [18.0, 80.0, 55.0, 30.0, 55.0, 150.0, 55.0, 85.0];

    pw.Widget hc(String t) => pw.Container(
        padding: const pw.EdgeInsets.symmetric(vertical: 7, horizontal: 5),
        color: const PdfColor(0.91, 0.36, 0.0),
        child: pw.Text(t,
            style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white)));

    pw.Widget dc(String text, {PdfColor? textColor}) => pw.Container(
        padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 5),
        child: pw.Text(text,
            style: pw.TextStyle(
                fontSize: 8,
                color: textColor ?? PdfColors.black,
                fontWeight: textColor != null ? pw.FontWeight.bold : pw.FontWeight.normal)));

    PdfColor statusPdfColor(String s) {
      switch (s.toLowerCase()) {
        case 'resolved': case 'completed': return PdfColors.green700;
        case 'in progress': case 'inprogress': return PdfColors.orange700;
        default: return PdfColors.red700;
      }
    }

    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Text('Complaint Details',
          style: pw.TextStyle(
              fontSize: 13,
              fontWeight: pw.FontWeight.bold,
              color: const PdfColor(0.91, 0.36, 0.0))),
      pw.SizedBox(height: 10),
      if (_complaints.isEmpty)
        pw.Text('No complaints this week.',
            style: pw.TextStyle(color: PdfColors.grey600, fontSize: 10))
      else
        pw.Table(
          columnWidths: {
            for (int i = 0; i < colWidths.length; i++)
              i: pw.FixedColumnWidth(colWidths[i])
          },
          border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
          children: [
            pw.TableRow(children: headers.map(hc).toList()),
            ..._complaints.asMap().entries.map((entry) {
              final idx = entry.key;
              final comp = entry.value;
              final status = (comp['status'] ?? 'Pending').toString();
              final desc = (comp['description'] ?? comp['message'] ?? '—').toString();
              final shortDesc = desc.length > 45 ? '${desc.substring(0, 45)}...' : desc;
              return pw.TableRow(
                decoration: pw.BoxDecoration(
                    color: idx % 2 == 0 ? PdfColors.grey50 : PdfColors.white),
                children: [
                  dc('${idx + 1}'),
                  dc((comp['studentName'] ?? '—').toString()),
                  dc((comp['regNo'] ?? '—').toString()),
                  dc((comp['roomNo'] ?? '—').toString()),
                  dc((comp['category'] ?? comp['type'] ?? '—').toString()),
                  dc(shortDesc),
                  dc(status, textColor: statusPdfColor(status)),
                  dc(_formatTs(comp['createdAt'])),
                ],
              );
            }),
          ],
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final c = _AC.of(context);
    return Scaffold(
      backgroundColor: c.scaffold,
      appBar: AppBar(
        backgroundColor: c.appBar, foregroundColor: Colors.white, elevation: 0,
        title: const Text('Weekly Complaints Report',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh, color: Colors.white),
              onPressed: _fetchWeeklyComplaints),
          IconButton(
            tooltip: 'Download PDF',
            icon: _isGenerating
                ? const SizedBox(
                width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.picture_as_pdf, color: Colors.white),
            onPressed: _isGenerating ? null : _generatePdf,
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: c.blue))
          : Column(children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          color: c.blueDark,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Weekly Complaint Overview',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
                '${DateFormat('dd MMM yyyy').format(DateTime.now().subtract(const Duration(days: 7)))} - ${DateFormat('dd MMM yyyy').format(DateTime.now())}',
                style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 13)),
          ]),
        ),
        _buildSummaryRow(c, [
          _ChipData('Total', _totalCount, const Color(0xFF6B7280)),
          _ChipData('Pending', _pendingCount, const Color(0xFFDC2626)),
          _ChipData('In Progress', _inProgressCount, const Color(0xFFD97706)),
          _ChipData('Resolved', _resolvedCount, const Color(0xFF059669)),
        ]),
        Expanded(
            child: _complaints.isEmpty
                ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.sentiment_satisfied_alt, size: 70, color: c.blueBorder),
              const SizedBox(height: 16),
              Text('No complaints this week!', style: TextStyle(fontSize: 16, color: c.textGrey)),
            ]))
                : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _complaints.length,
              itemBuilder: (context, index) {
                final comp = _complaints[index];
                final status = (comp['status'] ?? 'Pending').toString();
                final color = _statusColor(status);
                return Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                      color: c.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: color.withOpacity(0.35), width: 1.5),
                      boxShadow: [BoxShadow(
                          color: Colors.black.withOpacity(c.dark ? 0.2 : 0.04),
                          blurRadius: 8, offset: const Offset(0, 2))]),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        Expanded(child: Row(children: [
                          Container(
                            width: 36, height: 36,
                            decoration: BoxDecoration(color: c.blueBg, borderRadius: BorderRadius.circular(18)),
                            alignment: Alignment.center,
                            child: Text(
                                (comp['studentName'] ?? '?').toString().isNotEmpty
                                    ? (comp['studentName'] ?? '?').toString().substring(0, 1).toUpperCase()
                                    : '?',
                                style: TextStyle(color: c.blue, fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(width: 10),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(comp['studentName'] ?? '—',
                                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: c.ink)),
                            Text('Room: ${comp['roomNo'] ?? '—'}  •  Reg: ${comp['regNo'] ?? '—'}',
                                style: TextStyle(fontSize: 11, color: c.textGrey)),
                          ])),
                        ])),
                        Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                                color: color.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: color)),
                            child: Text(status.toUpperCase(),
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color))),
                      ]),
                      const SizedBox(height: 12),
                      Divider(height: 1, color: c.divider),
                      const SizedBox(height: 12),
                      if (comp['category'] != null || comp['type'] != null)
                        _infoRow(c, Icons.category_outlined, 'Category',
                            (comp['category'] ?? comp['type']).toString()),
                      const SizedBox(height: 8),
                      _infoRow(c, Icons.description_outlined, 'Description',
                          (comp['description'] ?? comp['message'] ?? '—').toString()),
                      const SizedBox(height: 8),
                      _infoRow(c, Icons.access_time, 'Raised On', _formatTs(comp['createdAt'])),
                    ]),
                  ),
                );
              },
            )),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// WEEKLY PERMISSION REQUESTS REPORT
// ══════════════════════════════════════════════════════════════════════════════

class WeeklyPermissionRequestsReportPage extends StatefulWidget {
  const WeeklyPermissionRequestsReportPage({super.key});
  @override
  State<WeeklyPermissionRequestsReportPage> createState() =>
      _WeeklyPermissionRequestsReportPageState();
}

class _WeeklyPermissionRequestsReportPageState
    extends State<WeeklyPermissionRequestsReportPage> {
  bool _isLoading = true;
  bool _isGenerating = false;
  List<Map<String, dynamic>> _requests = [];

  @override
  void initState() {
    super.initState();
    _fetchWeeklyRequests();
  }

  Future<void> _fetchWeeklyRequests() async {
    setState(() => _isLoading = true);
    try {
      final weekAgoTs =
      Timestamp.fromDate(DateTime.now().subtract(const Duration(days: 7)));

      final snapshot = await FirebaseFirestore.instance
          .collection('permissions')
          .where('submittedAt', isGreaterThanOrEqualTo: weekAgoTs)
          .orderBy('submittedAt', descending: true)
          .get();

      final List<Map<String, dynamic>> loaded = [];

      for (final doc in snapshot.docs) {
        final data = Map<String, dynamic>.from(doc.data());
        data['_docId'] = doc.id;

        final String uid =
        (data['studentUid'] ?? data['uid'] ?? '').toString().trim();
        final String existingName =
        (data['studentName'] ?? '').toString().trim();
        final String existingReg =
        (data['regNo'] ?? data['rollNumber'] ?? '').toString().trim();

        if ((existingName.isEmpty || existingReg.isEmpty) && uid.isNotEmpty) {
          try {
            final userDoc = await FirebaseFirestore.instance
                .collection('users')
                .doc(uid)
                .get();
            if (userDoc.exists) {
              final p = userDoc.data()!;
              if (existingName.isEmpty) {
                data['studentName'] =
                    (p['name'] ?? p['fullName'] ?? p['displayName'] ?? '—')
                        .toString();
              }
              if (existingReg.isEmpty) {
                data['regNo'] =
                    (p['regNo'] ?? p['rollNo'] ?? p['registrationNo'] ?? '—')
                        .toString();
              }
              if ((data['room'] ?? data['roomNo'] ?? '').toString().isEmpty) {
                data['room'] = (p['roomNo'] ?? p['room'] ?? '—').toString();
              }
            }
          } catch (_) {}
        }

        if ((data['regNo'] ?? '').toString().isEmpty) {
          data['regNo'] =
              (data['rollNumber'] ?? data['rollNo'] ?? '—').toString();
        }
        if ((data['room'] ?? '').toString().isEmpty) {
          data['room'] = (data['roomNo'] ?? '—').toString();
        }

        loaded.add(data);
      }

      if (mounted) setState(() => _requests = loaded);
    } catch (e) {
      debugPrint('Permission fetch error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _formatTs(dynamic ts) => _fmtTs(ts);

  Color _statusColor(String s) {
    switch (s.toLowerCase()) {
      case 'approved': return const Color(0xFF059669);
      case 'rejected': return const Color(0xFFDC2626);
      default:         return const Color(0xFFD97706);
    }
  }

  IconData _statusIcon(String s) {
    switch (s.toLowerCase()) {
      case 'approved': return Icons.check_circle;
      case 'rejected': return Icons.cancel;
      default:         return Icons.pending;
    }
  }

  int get _totalCount    => _requests.length;
  int get _pendingCount  => _requests
      .where((r) => (r['status'] ?? '').toString().toLowerCase() == 'pending')
      .length;
  int get _approvedCount => _requests
      .where((r) => (r['status'] ?? '').toString().toLowerCase() == 'approved')
      .length;
  int get _rejectedCount => _requests
      .where((r) => (r['status'] ?? '').toString().toLowerCase() == 'rejected')
      .length;

  Future<void> _generatePdf() async {
    setState(() => _isGenerating = true);
    try {
      final pdf = pw.Document();
      final now = DateTime.now();
      final dateRange =
          '${DateFormat('dd MMM yyyy').format(now.subtract(const Duration(days: 7)))} – ${DateFormat('dd MMM yyyy').format(now)}';

      pdf.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (ctx) => [
          _pdfHeader('Weekly Permission Requests Report', dateRange),
          pw.SizedBox(height: 16),
          _pdfSummaryCards([
            {'label': 'Total',    'value': '$_totalCount',    'color': PdfColors.grey700},
            {'label': 'Pending',  'value': '$_pendingCount',  'color': PdfColors.orange700},
            {'label': 'Approved', 'value': '$_approvedCount', 'color': PdfColors.green700},
            {'label': 'Rejected', 'value': '$_rejectedCount', 'color': PdfColors.red700},
          ]),
          pw.SizedBox(height: 20),
          _pdfPermissionsTable(),
        ],
      ));

      await Printing.layoutPdf(
        onLayout: (fmt) async => pdf.save(),
        name: 'Weekly_Permission_Requests_${DateFormat('dd-MM-yyyy').format(now)}.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Failed to generate PDF: $e'),
            backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  // ── PDF table — Room column REMOVED ─────────────────────────────────────
  pw.Widget _pdfPermissionsTable() {
    // Columns: #, Student, Reg No, Reason, Destination,
    //          Out Date, Out Time, In Date, In Time, Status, Submitted
    final headers = [
      '#', 'Student', 'Reg No',
      'Reason', 'Destination',
      'Out Date', 'Out Time', 'In Date', 'In Time',
      'Status', 'Submitted',
    ];
    final colWidths = [
      14.0, 62.0, 44.0,
      72.0, 72.0,
      40.0, 34.0, 40.0, 34.0,
      40.0, 70.0,
    ];

    pw.Widget hc(String t) => pw.Container(
        padding: const pw.EdgeInsets.symmetric(vertical: 7, horizontal: 4),
        color: const PdfColor(0.31, 0.27, 0.90),
        child: pw.Text(t,
            style: pw.TextStyle(
                fontSize: 7,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white)));

    pw.Widget dc(String text, {PdfColor? textColor}) => pw.Container(
        padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 4),
        child: pw.Text(text,
            style: pw.TextStyle(
                fontSize: 7,
                color: textColor ?? PdfColors.black,
                fontWeight: textColor != null
                    ? pw.FontWeight.bold
                    : pw.FontWeight.normal)));

    PdfColor statusPdfColor(String s) {
      switch (s.toLowerCase()) {
        case 'approved': return PdfColors.green700;
        case 'rejected': return PdfColors.red700;
        default:         return PdfColors.orange700;
      }
    }

    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Text('Permission Request Details',
          style: pw.TextStyle(
              fontSize: 13,
              fontWeight: pw.FontWeight.bold,
              color: const PdfColor(0.31, 0.27, 0.90))),
      pw.SizedBox(height: 10),
      if (_requests.isEmpty)
        pw.Text('No permission requests this week.',
            style: pw.TextStyle(color: PdfColors.grey600, fontSize: 10))
      else
        pw.Table(
          columnWidths: {
            for (int i = 0; i < colWidths.length; i++)
              i: pw.FixedColumnWidth(colWidths[i])
          },
          border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
          children: [
            pw.TableRow(children: headers.map(hc).toList()),
            ..._requests.asMap().entries.map((entry) {
              final idx    = entry.key;
              final r      = entry.value;
              final status = (r['status'] ?? 'pending').toString();

              final reason = (r['reason'] ?? '—').toString();
              final shortReason =
              reason.length > 28 ? '${reason.substring(0, 28)}...' : reason;

              final dest =
              (r['destination'] ?? r['destinationAddress'] ?? '—').toString();
              final shortDest =
              dest.length > 28 ? '${dest.substring(0, 28)}...' : dest;

              final outDate = (r['outDate'] ?? '—').toString();
              final outTime = (r['outTime'] ?? '—').toString();
              final inDate  = (r['inDate']  ?? '—').toString();
              final inTime  = (r['inTime']  ?? '—').toString();

              return pw.TableRow(
                decoration: pw.BoxDecoration(
                    color: idx % 2 == 0 ? PdfColors.grey50 : PdfColors.white),
                children: [
                  dc('${idx + 1}'),
                  dc((r['studentName'] ?? '—').toString()),
                  dc((r['regNo'] ?? '—').toString()),
                  // Room column removed
                  dc(shortReason),
                  dc(shortDest),
                  dc(outDate),
                  dc(outTime),
                  dc(inDate),
                  dc(inTime),
                  dc(status, textColor: statusPdfColor(status)),
                  dc(_formatTs(r['submittedAt'] ?? r['requestDate'])),
                ],
              );
            }),
          ],
        ),
    ]);
  }

  // ── UI ───────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final c = _AC.of(context);
    return Scaffold(
      backgroundColor: c.scaffold,
      appBar: AppBar(
        backgroundColor: c.appBar,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Weekly Permission Requests',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white),
              onPressed: _fetchWeeklyRequests),
          IconButton(
            tooltip: 'Download PDF',
            icon: _isGenerating
                ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.picture_as_pdf, color: Colors.white),
            onPressed: _isGenerating ? null : _generatePdf,
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: c.blue))
          : Column(children: [
        Container(
          width: double.infinity,
          padding:
          const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          color: c.blueDark,
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Permission Requests Overview',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(
                    '${DateFormat('dd MMM yyyy').format(DateTime.now().subtract(const Duration(days: 7)))} - ${DateFormat('dd MMM yyyy').format(DateTime.now())}',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.8),
                        fontSize: 13)),
              ]),
        ),
        _buildSummaryRow(c, [
          _ChipData('Total',    _totalCount,    const Color(0xFF6B7280)),
          _ChipData('Pending',  _pendingCount,  const Color(0xFFD97706)),
          _ChipData('Approved', _approvedCount, const Color(0xFF059669)),
          _ChipData('Rejected', _rejectedCount, const Color(0xFFDC2626)),
        ]),
        Expanded(
          child: _requests.isEmpty
              ? Center(
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.assignment_outlined,
                        size: 70, color: c.blueBorder),
                    const SizedBox(height: 16),
                    Text('No permission requests this week!',
                        style: TextStyle(
                            fontSize: 16, color: c.textGrey)),
                  ]))
              : ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _requests.length,
            itemBuilder: (context, index) {
              final r      = _requests[index];
              final status = (r['status'] ?? 'pending').toString();
              final color  = _statusColor(status);

              final outDate = (r['outDate'] ?? '—').toString();
              final outTime = (r['outTime'] ?? '—').toString();
              final inDate  = (r['inDate']  ?? '—').toString();
              final inTime  = (r['inTime']  ?? '—').toString();
              final dest    = (r['destination'] ??
                  r['destinationAddress'] ??
                  '—')
                  .toString();

              return Container(
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                    color: c.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: color.withOpacity(0.4), width: 1.5),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black
                              .withOpacity(c.dark ? 0.2 : 0.04),
                          blurRadius: 8,
                          offset: const Offset(0, 2))
                    ]),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                            mainAxisAlignment:
                            MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Row(children: [
                                  Container(
                                    width: 44, height: 44,
                                    decoration: BoxDecoration(
                                        color: c.blueBg,
                                        borderRadius:
                                        BorderRadius.circular(
                                            22)),
                                    alignment: Alignment.center,
                                    child: Text(
                                        (r['studentName'] ?? 'S')
                                            .toString()
                                            .isNotEmpty
                                            ? (r['studentName'] ??
                                            'S')
                                            .toString()
                                            .substring(0, 1)
                                            .toUpperCase()
                                            : 'S',
                                        style: TextStyle(
                                            color: c.blue,
                                            fontWeight:
                                            FontWeight.bold,
                                            fontSize: 17)),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                        crossAxisAlignment:
                                        CrossAxisAlignment
                                            .start,
                                        children: [
                                          Text(
                                              (r['studentName'] ??
                                                  '—')
                                                  .toString(),
                                              style: TextStyle(
                                                  fontWeight:
                                                  FontWeight
                                                      .w700,
                                                  fontSize: 15,
                                                  color: c.ink)),
                                          Text(
                                              'Reg: ${r['regNo'] ?? '—'}  •  Room: ${r['room'] ?? r['roomNo'] ?? '—'}',
                                              style: TextStyle(
                                                  fontSize: 11,
                                                  color:
                                                  c.textGrey)),
                                        ]),
                                  ),
                                ]),
                              ),
                              Container(
                                  padding:
                                  const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6),
                                  decoration: BoxDecoration(
                                      color:
                                      color.withOpacity(0.12),
                                      borderRadius:
                                      BorderRadius.circular(20),
                                      border: Border.all(
                                          color: color)),
                                  child: Row(
                                      mainAxisSize:
                                      MainAxisSize.min,
                                      children: [
                                        Icon(_statusIcon(status),
                                            size: 14, color: color),
                                        const SizedBox(width: 4),
                                        Text(
                                            status.toUpperCase(),
                                            style: TextStyle(
                                                fontSize: 11,
                                                fontWeight:
                                                FontWeight.bold,
                                                color: color)),
                                      ])),
                            ]),

                        const SizedBox(height: 14),
                        Divider(height: 1, color: c.divider),
                        const SizedBox(height: 14),

                        _infoRow(c, Icons.edit_note, 'Reason',
                            (r['reason'] ?? '—').toString()),
                        const SizedBox(height: 8),
                        _infoRow(c, Icons.location_on,
                            'Destination', dest),
                        const SizedBox(height: 8),

                        Row(children: [
                          Expanded(
                            child: _infoRow(
                              c,
                              Icons.login_rounded,
                              'Out',
                              outDate != '—'
                                  ? '$outDate  $outTime'
                                  : '—',
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _infoRow(
                              c,
                              Icons.logout_rounded,
                              'Return',
                              inDate != '—'
                                  ? '$inDate  $inTime'
                                  : '—',
                            ),
                          ),
                        ]),

                        const SizedBox(height: 8),
                        _infoRow(
                            c,
                            Icons.access_time,
                            'Submitted',
                            _formatTs(r['submittedAt'] ??
                                r['requestDate'])),

                        if ((r['staffNote'] ?? '')
                            .toString()
                            .trim()
                            .isNotEmpty) ...[
                          const SizedBox(height: 8),
                          _infoRow(
                              c,
                              Icons.note_outlined,
                              'Tutor Note',
                              r['staffNote'].toString()),
                        ],
                      ]),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// WEEKLY GATE PASS REPORT
// ══════════════════════════════════════════════════════════════════════════════

class WeeklyGatePassReportPage extends StatefulWidget {
  const WeeklyGatePassReportPage({super.key});
  @override
  State<WeeklyGatePassReportPage> createState() => _WeeklyGatePassReportPageState();
}

class _WeeklyGatePassReportPageState extends State<WeeklyGatePassReportPage> {
  bool _isLoading = true;
  bool _isGenerating = false;
  List<Map<String, dynamic>> _passes = [];

  @override
  void initState() {
    super.initState();
    _fetchWeeklyPasses();
  }

  String? _firstNonEmpty(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final val = map[key]?.toString().trim() ?? '';
      if (val.isNotEmpty) return val;
    }
    return null;
  }

  Future<void> _fetchWeeklyPasses() async {
    setState(() => _isLoading = true);
    try {
      final weekAgoTs = Timestamp.fromDate(DateTime.now().subtract(const Duration(days: 7)));
      final snapshot = await FirebaseFirestore.instance
          .collection('gatePasses')
          .where('submittedAt', isGreaterThanOrEqualTo: weekAgoTs)
          .orderBy('submittedAt', descending: true)
          .get();
      if (mounted) {
        final List<Map<String, dynamic>> loaded = [];
        for (final doc in snapshot.docs) {
          final data = Map<String, dynamic>.from(doc.data());
          data['_docId'] = doc.id;
          final uid = (data['studentUid'] ?? '').toString().trim();
          if (uid.isNotEmpty) {
            try {
              final uDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
              if (uDoc.exists) {
                data['department'] =
                    _firstNonEmpty(uDoc.data()!, ['department', 'dept', 'branch']) ??
                        (data['department'] ?? '—').toString();
              }
            } catch (_) {
              data['department'] = (data['department'] ?? '—').toString();
            }
          }
          loaded.add(data);
        }
        setState(() => _passes = loaded);
      }
    } catch (e) { debugPrint('Error: $e'); }
    finally { if (mounted) setState(() => _isLoading = false); }
  }

  String _formatTs(dynamic ts) => _fmtTs(ts);

  Color _statusColor(String s) {
    switch (s.toLowerCase()) {
      case 'approved': return const Color(0xFF1C5FC5);
      case 'returned': return const Color(0xFF059669);
      case 'rejected': return const Color(0xFFDC2626);
      default: return const Color(0xFFD97706);
    }
  }

  IconData _statusIcon(String s) {
    switch (s.toLowerCase()) {
      case 'approved': return Icons.check_circle;
      case 'returned': return Icons.home;
      case 'rejected': return Icons.cancel;
      default: return Icons.pending;
    }
  }

  int get _totalCount    => _passes.length;
  int get _pendingCount  => _passes.where((p) => (p['status'] ?? '').toString().toLowerCase() == 'pending').length;
  int get _approvedCount => _passes.where((p) => (p['status'] ?? '').toString().toLowerCase() == 'approved').length;
  int get _returnedCount => _passes.where((p) => (p['status'] ?? '').toString().toLowerCase() == 'returned').length;
  int get _notBackCount  => _passes.where((p) =>
  (p['status'] ?? '').toString().toLowerCase() == 'approved' &&
      p['studentReturnDone'] != true).length;

  Future<void> _generatePdf() async {
    setState(() => _isGenerating = true);
    try {
      final pdf = pw.Document();
      final now = DateTime.now();
      final dateRange =
          '${DateFormat('dd MMM yyyy').format(now.subtract(const Duration(days: 7)))} – ${DateFormat('dd MMM yyyy').format(now)}';

      pdf.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (ctx) => [
          _pdfHeader('Weekly Gate Pass Report', dateRange),
          pw.SizedBox(height: 16),
          _pdfSummaryCards([
            {'label': 'Total',    'value': '$_totalCount',    'color': PdfColors.grey700},
            {'label': 'Pending',  'value': '$_pendingCount',  'color': PdfColors.orange700},
            {'label': 'Approved', 'value': '$_approvedCount', 'color': PdfColors.blue700},
            {'label': 'Returned', 'value': '$_returnedCount', 'color': PdfColors.green700},
            {'label': 'Not Back', 'value': '$_notBackCount',  'color': PdfColors.red700},
          ]),
          pw.SizedBox(height: 20),
          _pdfGatePassTable(),
        ],
      ));

      await Printing.layoutPdf(
        onLayout: (fmt) async => pdf.save(),
        name: 'Weekly_Gate_Pass_Report_${DateFormat('dd-MM-yyyy').format(now)}.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Failed to generate PDF: $e'),
            backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  pw.Widget _pdfGatePassTable() {
    final headers = [
      '#', 'Student', 'Reg No', 'Room', 'Dept',
      'Destination', 'Reason', 'Status', 'Submitted',
    ];
    final colWidths = [
      15.0, 75.0, 52.0, 28.0, 50.0,
      100.0, 85.0, 45.0, 87.0,
    ];

    pw.Widget hc(String t) => pw.Container(
        padding: const pw.EdgeInsets.symmetric(vertical: 7, horizontal: 4),
        color: const PdfColor(0.05, 0.60, 0.53),
        child: pw.Text(t,
            style: pw.TextStyle(
                fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: PdfColors.white)));

    pw.Widget dc(String text, {PdfColor? textColor}) => pw.Container(
        padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 4),
        child: pw.Text(text,
            style: pw.TextStyle(
                fontSize: 7.5,
                color: textColor ?? PdfColors.black,
                fontWeight: textColor != null
                    ? pw.FontWeight.bold
                    : pw.FontWeight.normal)));

    PdfColor statusPdfColor(String s) {
      switch (s.toLowerCase()) {
        case 'approved': return PdfColors.blue700;
        case 'returned': return PdfColors.green700;
        case 'rejected': return PdfColors.red700;
        default:         return PdfColors.orange700;
      }
    }

    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Text('Gate Pass Details',
          style: pw.TextStyle(
              fontSize: 13,
              fontWeight: pw.FontWeight.bold,
              color: const PdfColor(0.05, 0.60, 0.53))),
      pw.SizedBox(height: 10),
      if (_passes.isEmpty)
        pw.Text('No gate passes this week.',
            style: pw.TextStyle(color: PdfColors.grey600, fontSize: 10))
      else
        pw.Table(
          columnWidths: {
            for (int i = 0; i < colWidths.length; i++)
              i: pw.FixedColumnWidth(colWidths[i])
          },
          border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
          children: [
            pw.TableRow(children: headers.map(hc).toList()),
            ..._passes.asMap().entries.map((entry) {
              final idx    = entry.key;
              final p      = entry.value;
              final status = (p['status'] ?? 'pending').toString();

              final dest = (p['destinationAddress'] ?? '—').toString();
              final shortDest =
              dest.length > 35 ? '${dest.substring(0, 35)}...' : dest;

              final reason = (p['reason'] ?? '—').toString();
              final shortReason =
              reason.length > 35 ? '${reason.substring(0, 35)}...' : reason;

              return pw.TableRow(
                decoration: pw.BoxDecoration(
                    color: idx % 2 == 0 ? PdfColors.grey50 : PdfColors.white),
                children: [
                  dc('${idx + 1}'),
                  dc((p['studentName'] ?? '—').toString()),
                  dc((p['regNo'] ?? '—').toString()),
                  dc((p['roomNo'] ?? '—').toString()),
                  dc((p['department'] ?? '—').toString()),
                  dc(shortDest),
                  dc(shortReason),
                  dc(status, textColor: statusPdfColor(status)),
                  dc(_formatTs(p['submittedAt'])),
                ],
              );
            }),
          ],
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final c = _AC.of(context);
    return Scaffold(
      backgroundColor: c.scaffold,
      appBar: AppBar(
        backgroundColor: c.appBar, foregroundColor: Colors.white, elevation: 0,
        title: const Text('Weekly Gate Pass Report',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh, color: Colors.white),
              onPressed: _fetchWeeklyPasses),
          IconButton(
            tooltip: 'Download PDF',
            icon: _isGenerating
                ? const SizedBox(
                width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.picture_as_pdf, color: Colors.white),
            onPressed: _isGenerating ? null : _generatePdf,
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: c.blue))
          : Column(children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          color: c.blueDark,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Gate Pass Overview',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
                '${DateFormat('dd MMM yyyy').format(DateTime.now().subtract(const Duration(days: 7)))} - ${DateFormat('dd MMM yyyy').format(DateTime.now())}',
                style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 13)),
          ]),
        ),
        _buildSummaryRow(c, [
          _ChipData('Total',    _totalCount,    const Color(0xFF6B7280)),
          _ChipData('Pending',  _pendingCount,  const Color(0xFFD97706)),
          _ChipData('Approved', _approvedCount, const Color(0xFF1C5FC5)),
          _ChipData('Returned', _returnedCount, const Color(0xFF059669)),
          _ChipData('Not Back', _notBackCount,  const Color(0xFFDC2626)),
        ]),
        Expanded(
            child: _passes.isEmpty
                ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.exit_to_app, size: 70, color: c.blueBorder),
              const SizedBox(height: 16),
              Text('No gate passes this week!', style: TextStyle(fontSize: 16, color: c.textGrey)),
            ]))
                : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _passes.length,
              itemBuilder: (context, index) {
                final p = _passes[index];
                final status = (p['status'] ?? 'pending').toString();
                final color = _statusColor(status);
                final returnDone = p['studentReturnDone'] == true;
                return Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                      color: c.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: color.withOpacity(0.35), width: 1.5),
                      boxShadow: [BoxShadow(
                          color: Colors.black.withOpacity(c.dark ? 0.2 : 0.04),
                          blurRadius: 8, offset: const Offset(0, 2))]),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        Expanded(child: Row(children: [
                          Container(
                            width: 40, height: 40,
                            decoration: BoxDecoration(color: c.blueBg, borderRadius: BorderRadius.circular(20)),
                            alignment: Alignment.center,
                            child: Text(
                                (p['studentName'] ?? 'S').toString().isNotEmpty
                                    ? (p['studentName'] ?? 'S').toString().substring(0, 1).toUpperCase()
                                    : 'S',
                                style: TextStyle(color: c.blue, fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(width: 10),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text((p['studentName'] ?? '—').toString(),
                                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: c.ink)),
                            Text('Reg: ${p['regNo'] ?? '—'}  •  Room: ${p['roomNo'] ?? '—'}  •  ${p['department'] ?? '—'}',
                                style: TextStyle(fontSize: 11, color: c.textGrey)),
                          ])),
                        ])),
                        Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                                color: color.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: color)),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(_statusIcon(status), size: 13, color: color),
                              const SizedBox(width: 4),
                              Text(status.toUpperCase(),
                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color)),
                            ])),
                      ]),
                      const SizedBox(height: 12),
                      Divider(height: 1, color: c.divider),
                      const SizedBox(height: 12),
                      _infoRow(c, Icons.location_on_outlined, 'Destination',
                          (p['destinationAddress'] ?? '—').toString()),
                      const SizedBox(height: 6),
                      _infoRow(c, Icons.edit_note, 'Reason', (p['reason'] ?? '—').toString()),
                      const SizedBox(height: 6),
                      _infoRow(c, Icons.access_time, 'Submitted', _formatTs(p['submittedAt'])),
                      if (returnDone) ...[
                        const SizedBox(height: 8),
                        Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                                color: const Color(0xFF059669).withOpacity(0.08),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFF059669).withOpacity(0.3))),
                            child: Row(children: [
                              const Icon(Icons.qr_code_scanner_rounded,
                                  size: 14, color: Color(0xFF059669)),
                              const SizedBox(width: 6),
                              Text(
                                  'Return verified via QR - ${p['inDate'] ?? ''} at ${p['inTime'] ?? ''}',
                                  style: const TextStyle(
                                      fontSize: 12, fontWeight: FontWeight.w600,
                                      color: Color(0xFF059669))),
                            ])),
                      ],
                    ]),
                  ),
                );
              },
            )),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// ROOM ALLOCATION PAGE
// ══════════════════════════════════════════════════════════════════════════════

class RoomAllocationPage extends StatelessWidget {
  const RoomAllocationPage({super.key});

  @override
  Widget build(BuildContext context) {
    final c = _AC.of(context);
    final rooms = [
      {'number': 'A-201', 'capacity': 2, 'occupied': 2, 'status': 'Full'},
      {'number': 'A-202', 'capacity': 2, 'occupied': 1, 'status': 'Available'},
      {'number': 'A-203', 'capacity': 2, 'occupied': 0, 'status': 'Empty'},
      {'number': 'B-101', 'capacity': 3, 'occupied': 3, 'status': 'Full'},
      {'number': 'B-102', 'capacity': 3, 'occupied': 2, 'status': 'Available'},
    ];
    return Scaffold(
      backgroundColor: c.scaffold,
      appBar: AppBar(
        backgroundColor: c.appBar, foregroundColor: Colors.white, elevation: 0,
        title: const Text('Room Allocation',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
      ),
      body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: _summaryCard(c, 'Total Rooms', '120', c.blue)),
              const SizedBox(width: 12),
              Expanded(child: _summaryCard(c, 'Occupied', '98', c.success)),
              const SizedBox(width: 12),
              Expanded(child: _summaryCard(c, 'Available', '22', c.warn)),
            ]),
            const SizedBox(height: 20),
            Text('Room Status',
                style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.bold, color: c.ink)),
            const SizedBox(height: 12),
            Expanded(
                child: ListView.builder(
                    itemCount: rooms.length,
                    itemBuilder: (context, index) {
                      final room = rooms[index];
                      final statusColor = room['status'] == 'Full'
                          ? c.danger
                          : room['status'] == 'Available'
                          ? c.success
                          : c.textGrey;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: c.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: c.blueBorder),
                          boxShadow: [BoxShadow(
                              color: Colors.black.withOpacity(c.dark ? 0.2 : 0.04),
                              blurRadius: 4, offset: const Offset(0, 1))],
                        ),
                        child: ListTile(
                          leading: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                  color: statusColor.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8)),
                              child: Icon(Icons.meeting_room, color: statusColor)),
                          title: Text('Room ${room['number']}',
                              style: TextStyle(fontWeight: FontWeight.bold, color: c.ink)),
                          subtitle: Text('${room['occupied']}/${room['capacity']} occupied',
                              style: TextStyle(color: c.textGrey)),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                                color: statusColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: statusColor.withOpacity(0.4))),
                            child: Text(room['status'] as String,
                                style: TextStyle(color: statusColor, fontSize: 12, fontWeight: FontWeight.w600)),
                          ),
                        ),
                      );
                    })),
          ])),
    );
  }

  Widget _summaryCard(_AC c, String title, String count, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3)),
        boxShadow: [BoxShadow(
            color: Colors.black.withOpacity(c.dark ? 0.2 : 0.05),
            blurRadius: 4, offset: const Offset(0, 1))],
      ),
      child: Column(children: [
        Text(count,
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
        Text(title,
            style: TextStyle(fontSize: 12, color: c.textGrey)),
      ]),
    );
  }
}