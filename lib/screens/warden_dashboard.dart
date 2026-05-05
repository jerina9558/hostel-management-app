// warden_dashboard.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'profile_page.dart';
import 'mess_menu.dart';
import 'gatepass_page.dart';
import 'complaint_page.dart';
import 'post_event_page.dart';
import 'post_announcement_page.dart';
import 'settings_page.dart';
import '../screens/login_page.dart';
import 'package:firebase_auth/firebase_auth.dart';

// ─────────────────────────────────────────────────────────────────────────────
// COLOUR HELPER  (mirrors _AC from admin_dashboard.dart)
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
}

// ============================================================================
// WARDEN DASHBOARD
// ============================================================================

class WardenDashboard extends StatefulWidget {
  const WardenDashboard({super.key});

  @override
  State<WardenDashboard> createState() => _WardenDashboardState();
}

class _WardenDashboardState extends State<WardenDashboard> {
  String userName = "";
  int _pendingGatePasses = 0;
  int _pendingComplaints = 0;

  @override
  void initState() {
    super.initState();
    _loadName();
    _listenGatePassCount();
    _listenComplaintCount();
  }

  Future<void> _loadName() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        SharedPreferences prefs = await SharedPreferences.getInstance();
        String name = prefs.getString('${user.uid}_userName') ?? '';
        if (name.isEmpty) {
          final doc = await FirebaseFirestore.instance
              .collection('users').doc(user.uid).get();
          if (doc.exists) {
            name = doc.data()?['name'] ?? '';
            await prefs.setString('${user.uid}_userName', name);
          }
        }
        if (mounted) setState(() => userName = name);
      }
    } catch (e) {
      debugPrint('Error loading name: $e');
    }
  }

  void _listenGatePassCount() {
    FirebaseFirestore.instance
        .collection('gatePasses')
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .listen((snap) {
      if (mounted) setState(() => _pendingGatePasses = snap.docs.length);
    }, onError: (e) => debugPrint('GatePass count error: $e'));
  }

  void _listenComplaintCount() {
    FirebaseFirestore.instance
        .collection('complaints')
        .where('status', isEqualTo: 'Pending')
        .snapshots()
        .listen((snap) {
      if (mounted) setState(() => _pendingComplaints = snap.docs.length);
    }, onError: (e) => debugPrint('Complaint count error: $e'));
  }

  Future<void> _logout() async {
    try {
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(context,
          MaterialPageRoute(builder: (_) => const LoginPage()), (route) => false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Logout failed: $e'), backgroundColor: Colors.red));
    }
  }

  // ── STEP 1 & 2: Notification bottom sheet ──────────────────────────────────
  void _showWardenNotificationsSheet(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final c = _AC.of(context);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Container(
        height: MediaQuery.of(context).size.height * 0.75,
        decoration: BoxDecoration(
          color: c.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(children: [
          // Handle bar
          Center(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
              width: 36, height: 4,
              decoration: BoxDecoration(
                  color: c.divider, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          // Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: c.appBar,
            child: const Text('Notifications',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w700)),
          ),
          // List
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('notifications')
                  .doc(uid)
                  .collection('items')
                  .orderBy('time', descending: true)
                  .limit(30)
                  .snapshots(),
              builder: (context, snapshot) {
                // Mark all as seen when sheet opens
                if (snapshot.hasData) {
                  final unseen = snapshot.data!.docs
                      .where((d) => (d.data() as Map)['seen'] == false);
                  if (unseen.isNotEmpty) {
                    final batch = FirebaseFirestore.instance.batch();
                    for (final doc in unseen) {
                      batch.update(doc.reference, {'seen': true});
                    }
                    batch.commit();
                  }
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(
                      child: CircularProgressIndicator(color: c.blue));
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.notifications_none_outlined,
                          size: 48, color: c.blueBorder),
                      const SizedBox(height: 12),
                      Text('No notifications yet',
                          style: TextStyle(color: c.textGrey, fontSize: 15)),
                    ]),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  itemCount: snapshot.data!.docs.length,
                  separatorBuilder: (_, __) =>
                      Divider(height: 1, color: c.divider),
                  itemBuilder: (_, i) {
                    final data = snapshot.data!.docs[i].data()
                    as Map<String, dynamic>;
                    final title = (data['title'] ?? 'Notification').toString();
                    final body = (data['body'] ?? '').toString();
                    final time = data['time'] is Timestamp
                        ? (data['time'] as Timestamp).toDate()
                        : DateTime.now();
                    final seen = data['seen'] == true;
                    final type = (data['type'] ?? '').toString();

                    // Icon and color based on type
                    IconData icon = Icons.notifications_rounded;
                    Color color = c.blue;
                    if (type == 'gate_pass_request') {
                      icon = Icons.exit_to_app_rounded;
                      color = c.success;
                    } else if (type == 'student_returned') {
                      icon = Icons.home_rounded;
                      color = c.success;
                    } else if (type == 'complaint_raised') {
                      icon = Icons.build_rounded;
                      color = c.danger;
                    } else if (type == 'new_permission') {
                      icon = Icons.assignment_rounded;
                      color = c.warn;
                    }

                    return Container(
                      color: seen
                          ? Colors.transparent
                          : c.blue.withOpacity(0.05),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 38, height: 38,
                                decoration: BoxDecoration(
                                    color: color.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                        color: color.withOpacity(0.3))),
                                child: Icon(icon, color: color, size: 18),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                    children: [
                                      Row(children: [
                                        Expanded(
                                          child: Text(title,
                                              style: TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: seen
                                                      ? FontWeight.w600
                                                      : FontWeight.w800,
                                                  color: c.ink)),
                                        ),
                                        if (!seen)
                                          Container(
                                            width: 8, height: 8,
                                            decoration: BoxDecoration(
                                                color: c.blue,
                                                shape: BoxShape.circle),
                                          ),
                                      ]),
                                      if (body.isNotEmpty) ...[
                                        const SizedBox(height: 3),
                                        Text(body,
                                            style: TextStyle(
                                                fontSize: 13,
                                                color: c.textGrey)),
                                      ],
                                      const SizedBox(height: 4),
                                      Text(
                                        '${time.day}/${time.month}/${time.year}  ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                                        style: TextStyle(
                                            fontSize: 11, color: c.textGrey),
                                      ),
                                    ]),
                              ),
                            ]),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ]),
      ),
    );
  }

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
        title: const Text('Warden Dashboard',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        actions: [
          // ── STEP 3: Live unseen-count badge via StreamBuilder ──────────────
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('notifications')
                .doc(FirebaseAuth.instance.currentUser?.uid ?? '')
                .collection('items')
                .where('seen', isEqualTo: false)
                .snapshots(),
            builder: (context, snapshot) {
              final unseenCount = snapshot.data?.docs.length ?? 0;
              return Stack(
                children: [
                  IconButton(
                    icon: const Icon(Icons.notifications_none_rounded,
                        color: Colors.white),
                    onPressed: () => _showWardenNotificationsSheet(context),
                  ),
                  if (unseenCount > 0)
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Container(
                        width: 17,
                        height: 17,
                        decoration: const BoxDecoration(
                          color: Color(0xFFDC2626),
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          unseenCount > 99 ? '99+' : '$unseenCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.person, color: Colors.white),
            onPressed: () async {
              await Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const ProfilePage(initialRole: 'warden')));
              _loadName();
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white),
            tooltip: 'Settings',
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => SettingsPage(onLogout: _logout, role: UserRole.warden))),
          ),
        ],
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Welcome, $userName 👋',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: c.ink)),
          const SizedBox(height: 4),
          Text(todayDate, style: TextStyle(fontSize: 16, color: c.blue)),
          const SizedBox(height: 20),

          _buildOverviewCards(context, c),
          const SizedBox(height: 20),

          Text('Quick Actions',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: c.ink)),
          const SizedBox(height: 12),

          Row(children: [
            Expanded(child: _buildFeatureCard(context, c,
                icon: Icons.campaign, iconColor: c.warn,
                title: 'Post Announcement', subtitle: 'Notify all students',
                page: const WardenAnnouncementsPage())),
            const SizedBox(width: 12),
            Expanded(child: _buildFeatureCard(context, c,
                icon: Icons.event, iconColor: const Color(0xFF7C3AED),
                title: 'Post Event', subtitle: 'Add hostel events',
                page: const PostEventPage())),
          ]),
          const SizedBox(height: 12),

          Row(children: [
            Expanded(child: _buildFeatureCard(context, c,
                icon: Icons.assignment, iconColor: const Color(0xFF0D9488),
                title: 'Student Permissions', subtitle: 'View all requests',
                page: const ViewPermissionsPage())),
            const SizedBox(width: 12),
            Expanded(child: _buildFeatureCard(context, c,
                icon: Icons.menu_book, iconColor: c.blue,
                title: 'Mess Menu', subtitle: 'Update food menu',
                page: const MessMenuWardenPage())),
          ]),
          const SizedBox(height: 12),

          Row(children: [
            Expanded(child: _buildFeatureCard(context, c,
                icon: Icons.exit_to_app, iconColor: c.success,
                title: 'Approve Gate Pass', subtitle: 'View gate pass',
                page: WardenGatePassPage())),
            const SizedBox(width: 12),
            Expanded(child: _buildFeatureCard(context, c,
                icon: Icons.build, iconColor: c.danger,
                title: 'Complaints', subtitle: 'View & update',
                page: const ComplaintPage())),
          ]),
        ]),
      ),
    );
  }

  Widget _buildOverviewCards(BuildContext context, _AC c) {
    return Row(children: [
      _overviewCard(c,
          title: 'Gate Pass',
          value: '$_pendingGatePasses Pending',
          icon: Icons.exit_to_app,
          color: c.success),
      const SizedBox(width: 12),
      _overviewCard(c,
          title: 'Complaints',
          value: '$_pendingComplaints Pending',
          icon: Icons.build,
          color: c.danger),
    ]);
  }

  Widget _overviewCard(_AC c, {
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: c.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
          boxShadow: [BoxShadow(
              color: Colors.black.withOpacity(c.dark ? 0.2 : 0.05),
              blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Column(children: [
          Icon(icon, color: color, size: 30),
          const SizedBox(height: 8),
          Text(value,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
          Text(title, style: TextStyle(fontSize: 12, color: c.textGrey)),
        ]),
      ),
    );
  }

  Widget _buildFeatureCard(BuildContext context, _AC c, {
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required Widget page,
  }) {
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => page)),
      child: Container(
        height: 160,
        decoration: BoxDecoration(
          color: c.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: iconColor.withOpacity(0.3), width: 1.5),
          boxShadow: [BoxShadow(
              color: iconColor.withOpacity(c.dark ? 0.12 : 0.10),
              blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 60, height: 60,
            decoration: BoxDecoration(
                color: iconColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(16)),
            child: Icon(icon, size: 32, color: iconColor),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(title,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: c.ink),
                textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(subtitle,
                style: TextStyle(fontSize: 11, color: c.textGrey),
                textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
        ]),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
//  VIEW PERMISSIONS PAGE
// ════════════════════════════════════════════════════════════════════

class ViewPermissionsPage extends StatefulWidget {
  const ViewPermissionsPage({super.key});

  @override
  State<ViewPermissionsPage> createState() => _ViewPermissionsPageState();
}

class _ViewPermissionsPageState extends State<ViewPermissionsPage> {
  String selectedFilter = 'All';
  List<Map<String, dynamic>> _allRequests = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _listenToRequests();
  }

  void _listenToRequests() {
    FirebaseFirestore.instance
        .collection('permission_requests')
        .snapshots()
        .listen((snapshot) async {
      final List<Map<String, dynamic>> requests = [];
      for (final doc in snapshot.docs) {
        final data = Map<String, dynamic>.from(doc.data());
        data['_docId'] = doc.id;
        final userId = data['userId'] as String? ?? '';
        if (userId.isNotEmpty) {
          try {
            final userDoc = await FirebaseFirestore.instance
                .collection('users').doc(userId).get();
            if (userDoc.exists) {
              final profile = userDoc.data()!;
              data['studentName'] = profile['name'] ?? data['studentName'] ?? '—';
              data['rollNumber']  = profile['regNo'] ?? profile['rollNo'] ?? data['rollNumber'] ?? '—';
              data['room']        = profile['roomNo'] ?? profile['room'] ?? data['room'] ?? '—';
            }
          } catch (_) {}
        }
        requests.add(data);
      }
      requests.sort((a, b) {
        final aDate = (a['requestDate'] as Timestamp).toDate();
        final bDate = (b['requestDate'] as Timestamp).toDate();
        return bDate.compareTo(aDate);
      });
      if (mounted) setState(() { _allRequests = requests; _isLoading = false; });
    }, onError: (e) {
      debugPrint('Warden listener error: $e');
      if (mounted) setState(() => _isLoading = false);
    });
  }

  Future<void> _callNumber(String number) async {
    final uri = Uri(scheme: 'tel', path: number);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    final c = _AC.of(context);
    final filteredRequests = selectedFilter == 'All'
        ? _allRequests
        : _allRequests.where((r) => r['status'] == selectedFilter.toLowerCase()).toList();
    final pendingCount  = _allRequests.where((r) => r['status'] == 'pending').length;
    final approvedCount = _allRequests.where((r) => r['status'] == 'approved').length;
    final rejectedCount = _allRequests.where((r) => r['status'] == 'rejected').length;

    return Scaffold(
      backgroundColor: c.scaffold,
      appBar: AppBar(
        backgroundColor: c.appBar,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Student Permissions',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: c.blue))
          : Column(children: [
        // Header banner
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          color: c.blueDark,
          child: Column(children: [
            const Text('Permission Requests Overview',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(child: _buildStatCard('Total',    _allRequests.length)),
              const SizedBox(width: 8),
              Expanded(child: _buildStatCard('Pending',  pendingCount)),
              const SizedBox(width: 8),
              Expanded(child: _buildStatCard('Approved', approvedCount)),
              const SizedBox(width: 8),
              Expanded(child: _buildStatCard('Rejected', rejectedCount)),
            ]),
          ]),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              _buildFilterChip(context, c, 'All',      _allRequests.length),
              const SizedBox(width: 8),
              _buildFilterChip(context, c, 'Pending',  pendingCount),
              const SizedBox(width: 8),
              _buildFilterChip(context, c, 'Approved', approvedCount),
              const SizedBox(width: 8),
              _buildFilterChip(context, c, 'Rejected', rejectedCount),
            ]),
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: filteredRequests.isEmpty
              ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.assignment_outlined, size: 80, color: c.blueBorder),
            const SizedBox(height: 16),
            Text('No ${selectedFilter.toLowerCase()} requests',
                style: TextStyle(fontSize: 16, color: c.textGrey)),
            const SizedBox(height: 8),
            Text('Requests appear here after tutor approves or rejects them',
                style: TextStyle(fontSize: 13, color: c.textGrey),
                textAlign: TextAlign.center),
          ]))
              : ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: filteredRequests.length,
            itemBuilder: (context, index) =>
                _buildRequestCard(context, c, filteredRequests[index]),
          ),
        ),
      ]),
    );
  }

  Widget _buildStatCard(String label, int count) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.2)),
      ),
      child: Column(children: [
        Text('$count',
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
        const SizedBox(height: 4),
        Text(label,
            style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w500)),
      ]),
    );
  }

  Widget _buildFilterChip(BuildContext context, _AC c, String label, int count) {
    final isSelected = selectedFilter == label;
    return InkWell(
      onTap: () => setState(() => selectedFilter = label),
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? c.blue : c.blueBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? c.blue : c.blueBorder, width: 1.5),
        ),
        child: Text('$label ($count)',
            style: TextStyle(
                fontSize: 13,
                color: isSelected ? Colors.white : c.textGrey,
                fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _buildRequestCard(BuildContext context, _AC c, Map<String, dynamic> data) {
    final status = data['status'] as String? ?? 'unknown';
    Color statusColor;
    IconData statusIcon;
    String statusText;
    switch (status) {
      case 'pending':
        statusColor = c.warn; statusIcon = Icons.pending; statusText = 'PENDING'; break;
      case 'approved':
        statusColor = c.success; statusIcon = Icons.check_circle; statusText = 'APPROVED BY TUTOR'; break;
      case 'rejected':
        statusColor = c.danger; statusIcon = Icons.cancel; statusText = 'REJECTED BY TUTOR'; break;
      default:
        statusColor = c.textGrey; statusIcon = Icons.help; statusText = status.toUpperCase();
    }

    String formatTs(dynamic ts) {
      if (ts == null) return '—';
      return DateFormat('dd MMM yyyy').format((ts as Timestamp).toDate());
    }

    String formatTsWithTime(dynamic ts, String time) {
      if (ts == null) return '—';
      final date = DateFormat('dd MMM yyyy').format((ts as Timestamp).toDate());
      return '$date at $time';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: c.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: statusColor.withOpacity(0.35), width: 1.5),
        boxShadow: [BoxShadow(
            color: Colors.black.withOpacity(c.dark ? 0.2 : 0.06),
            blurRadius: 16, offset: const Offset(0, 4))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Permission Request',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.blue)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: statusColor)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(statusIcon, size: 14, color: statusColor),
                const SizedBox(width: 6),
                Text(statusText,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: statusColor)),
              ]),
            ),
          ]),
          const SizedBox(height: 16),
          Row(children: [
            Container(
              width: 50, height: 50,
              decoration: BoxDecoration(
                  color: c.blueBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: c.blueBorder)),
              child: Icon(Icons.person, color: c.blue, size: 28),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(data['studentName'] ?? '—',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.ink)),
              const SizedBox(height: 2),
              Text('Roll No: ${data['rollNumber'] ?? '—'}',
                  style: TextStyle(fontSize: 13, color: c.textGrey)),
              Text('Room: ${data['room'] ?? '—'}',
                  style: TextStyle(fontSize: 13, color: c.textGrey)),
            ])),
          ]),
          const SizedBox(height: 20),
          _buildInfoField(c, icon: Icons.description_outlined,
              label: 'Reason for Leave', value: data['reason'] ?? '—'),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: _buildDateTimeCard(c,
                icon: Icons.flight_takeoff, label: 'Out Date',
                dateStr: formatTsWithTime(data['outDate'], data['outTime'] ?? ''))),
            const SizedBox(width: 12),
            Expanded(child: _buildDateTimeCard(c,
                icon: Icons.flight_land, label: 'Return Date',
                dateStr: formatTsWithTime(data['returnDate'], data['returnTime'] ?? ''))),
          ]),
          const SizedBox(height: 16),
          _buildInfoField(c, icon: Icons.location_on_outlined,
              label: 'Destination', value: data['destination'] ?? '—'),
          const SizedBox(height: 16),
          _buildInfoField(c, icon: Icons.phone_outlined,
              label: 'Student Contact', value: data['contact'] ?? '—'),
          const SizedBox(height: 16),
          _buildTappablePhoneField(context, c,
              icon: Icons.phone_android_outlined,
              label: 'Parent/Guardian Contact',
              value: data['parentContact'] ?? '—'),
          const SizedBox(height: 16),
          Divider(color: c.divider, height: 1),
          const SizedBox(height: 12),
          Row(children: [
            Icon(Icons.access_time, size: 14, color: c.blue.withOpacity(0.6)),
            const SizedBox(width: 6),
            Text('Requested on ${formatTs(data['requestDate'])}',
                style: TextStyle(fontSize: 12, color: c.textGrey, fontWeight: FontWeight.w500)),
          ]),
        ]),
      ),
    );
  }

  Widget _buildInfoField(_AC c, {
    required IconData icon, required String label, required String value,
  }) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(icon, size: 16, color: c.blue),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(fontSize: 12, color: c.textGrey, fontWeight: FontWeight.w500)),
      ]),
      const SizedBox(height: 6),
      Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.ink)),
    ]);
  }

  Widget _buildTappablePhoneField(BuildContext context, _AC c, {
    required IconData icon, required String label, required String value,
  }) {
    final bool isDialable = value != '—' && value.trim().isNotEmpty;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(icon, size: 16, color: c.blue),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(fontSize: 12, color: c.textGrey, fontWeight: FontWeight.w500)),
      ]),
      const SizedBox(height: 6),
      GestureDetector(
        onTap: isDialable ? () => _callNumber(value.trim()) : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isDialable ? c.blueBg : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: isDialable ? Border.all(color: c.blueBorder) : null,
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (isDialable)
              Container(
                width: 34, height: 34,
                decoration: BoxDecoration(color: c.success, borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.call, color: Colors.white, size: 18),
              ),
            if (isDialable) const SizedBox(width: 10),
            Flexible(child: Text(value,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isDialable ? c.success : c.ink,
                    decoration: isDialable ? TextDecoration.underline : TextDecoration.none,
                    decorationColor: c.success))),
            if (isDialable) ...[
              const SizedBox(width: 8),
              Text('Tap to call',
                  style: TextStyle(fontSize: 11, color: c.success, fontStyle: FontStyle.italic)),
            ],
          ]),
        ),
      ),
    ]);
  }

  Widget _buildDateTimeCard(_AC c, {
    required IconData icon, required String label, required String dateStr,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: c.blueBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.blueBorder)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 14, color: c.blue),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 11, color: c.blue, fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 8),
        Text(dateStr, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.ink)),
      ]),
    );
  }
}