// tutor_dashboard.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'profile_page.dart';
import 'settings_page.dart';
import '../screens/login_page.dart';

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
// TUTOR DASHBOARD
// ============================================================================

class TutorDashboard extends StatefulWidget {
  const TutorDashboard({super.key});

  @override
  State<TutorDashboard> createState() => _TutorDashboardState();
}

class _TutorDashboardState extends State<TutorDashboard> {
  String userName = '';
  int _pendingCount = 0;
  int _approvedCount = 0;
  int _rejectedCount = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadName();
    _listenToRequestCounts();
  }

  Future<void> _loadName() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final prefs = await SharedPreferences.getInstance();
        String name = prefs.getString('${user.uid}_userName') ?? '';
        if (name.isEmpty) {
          final doc = await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get();
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

  void _listenToRequestCounts() {
    FirebaseFirestore.instance
        .collection('permissions')
        .snapshots()
        .listen((snapshot) {
      int pending = 0, approved = 0, rejected = 0;
      for (final doc in snapshot.docs) {
        final status = (doc.data()['status'] ?? '').toString();
        if (status == 'pending') pending++;
        else if (status == 'approved') approved++;
        else if (status == 'rejected') rejected++;
      }
      if (mounted) {
        setState(() {
          _pendingCount = pending;
          _approvedCount = approved;
          _rejectedCount = rejected;
          _isLoading = false;
        });
      }
    }, onError: (e) {
      debugPrint('Error: $e');
      if (mounted) setState(() => _isLoading = false);
    });
  }

  Future<void> _logout() async {
    try {
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
            (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Logout failed: $e'), backgroundColor: Colors.red),
      );
    }
  }
  void _showNotificationsSheet(BuildContext context) {
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
          Center(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
              width: 36, height: 4,
              decoration: BoxDecoration(
                  color: c.divider, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: c.appBar,
            child: const Text('Notifications',
                style: TextStyle(
                    color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
          ),
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
                  return Center(child: CircularProgressIndicator(color: c.blue));
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
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  itemCount: snapshot.data!.docs.length,
                  separatorBuilder: (_, __) => Divider(height: 1, color: c.divider),
                  itemBuilder: (_, i) {
                    final data = snapshot.data!.docs[i].data() as Map<String, dynamic>;
                    final title = (data['title'] ?? 'Notification').toString();
                    final body  = (data['body'] ?? '').toString();
                    final time  = data['time'] is Timestamp
                        ? (data['time'] as Timestamp).toDate()
                        : DateTime.now();
                    final seen  = data['seen'] == true;
                    final type  = (data['type'] ?? '').toString();

                    IconData icon = Icons.notifications_rounded;
                    Color color   = c.blue;
                    if (type == 'new_permission_request') {
                      icon  = Icons.assignment_rounded;
                      color = c.warn;
                    } else if (type == 'permission_approved') {
                      icon  = Icons.check_circle_rounded;
                      color = c.success;
                    } else if (type == 'permission_rejected') {
                      icon  = Icons.cancel_rounded;
                      color = c.danger;
                    }

                    return Container(
                      color: seen ? Colors.transparent : c.blue.withOpacity(0.05),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Container(
                            width: 38, height: 38,
                            decoration: BoxDecoration(
                                color: color.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: color.withOpacity(0.3))),
                            child: Icon(icon, color: color, size: 18),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                Expanded(
                                  child: Text(title,
                                      style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: seen ? FontWeight.w600 : FontWeight.w800,
                                          color: c.ink)),
                                ),
                                if (!seen)
                                  Container(
                                    width: 8, height: 8,
                                    decoration: BoxDecoration(
                                        color: c.blue, shape: BoxShape.circle),
                                  ),
                              ]),
                              if (body.isNotEmpty) ...[
                                const SizedBox(height: 3),
                                Text(body, style: TextStyle(fontSize: 13, color: c.textGrey)),
                              ],
                              const SizedBox(height: 4),
                              Text(
                                '${time.day}/${time.month}/${time.year}  ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                                style: TextStyle(fontSize: 11, color: c.textGrey),
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
  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning';
    if (hour < 17) return 'Good Afternoon';
    return 'Good Evening';
  }

  @override
  Widget build(BuildContext context) {
    final c = _AC.of(context);
    final today = DateFormat('EEEE, d MMM yyyy').format(DateTime.now());
    final total = _pendingCount + _approvedCount + _rejectedCount;

    return Scaffold(
      backgroundColor: c.scaffold,
      appBar: AppBar(
        backgroundColor: c.appBar,
        foregroundColor: Colors.white,
        title: const Text('Tutor Dashboard',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        actions: [
          // ── Notification Bell ──────────────────────────────────
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
                    icon: const Icon(Icons.notifications_none_rounded, color: Colors.white),
                    onPressed: () => _showNotificationsSheet(context),
                  ),
                  if (unseenCount > 0)
                    Positioned(
                      right: 8, top: 8,
                      child: Container(
                        width: 17, height: 17,
                        decoration: const BoxDecoration(
                            color: Color(0xFFDC2626), shape: BoxShape.circle),
                        alignment: Alignment.center,
                        child: Text(
                          unseenCount > 99 ? '99+' : '$unseenCount',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          // ──────────────────────────────────────────────────────
          IconButton(
            icon: const Icon(Icons.person, color: Colors.white),
            onPressed: () async {
              await Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const ProfilePage(initialRole: 'tutor')));
              _loadName();
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white),
            tooltip: 'Settings',
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => SettingsPage(onLogout: _logout, role: UserRole.tutor))),
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: c.blue))
          : SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(children: [

          // ── Hero header ───────────────────────────────────────────
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: c.blueDark,
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(32),
                bottomRight: Radius.circular(32),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 32),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${_greeting()},',
                  style: TextStyle(fontSize: 15, color: Colors.white.withOpacity(0.8))),
              const SizedBox(height: 2),
              Text(userName.isNotEmpty ? userName : 'Tutor',
                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 4),
              Text(today,
                  style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.7))),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withOpacity(0.25)),
                ),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.assignment, color: Colors.white, size: 26),
                  ),
                  const SizedBox(width: 14),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Total Permission Requests',
                        style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
                    Text('$total requests',
                        style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                  ]),
                  const Spacer(),
                  Icon(Icons.trending_up, color: Colors.white.withOpacity(0.7), size: 28),
                ]),
              ),
            ]),
          ),

          const SizedBox(height: 24),

          // ── Stats row ─────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              _statCard(c, 'Pending', _pendingCount, c.warn, Icons.pending_actions),
              const SizedBox(width: 12),
              _statCard(c, 'Approved', _approvedCount, c.success, Icons.check_circle_outline),
              const SizedBox(width: 12),
              _statCard(c, 'Rejected', _rejectedCount, c.danger, Icons.cancel_outlined),
            ]),
          ),

          const SizedBox(height: 28),

          // ── Quick Actions ──────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Quick Actions',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: c.ink)),
              const SizedBox(height: 14),
              _actionCard(
                context, c,
                icon: Icons.assignment_turned_in,
                title: 'Permission Requests',
                subtitle: _pendingCount > 0
                    ? '$_pendingCount pending request${_pendingCount > 1 ? 's' : ''} need your attention'
                    : 'All requests are up to date',
                badge: _pendingCount > 0 ? '$_pendingCount' : null,
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const TutorPermissionRequestsPage())),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: _smallActionCard(context, c,
                      icon: Icons.bar_chart,
                      iconColor: c.blue,
                      title: 'This Week',
                      subtitle: 'View weekly summary',
                      onTap: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const TutorWeeklySummaryPage()))),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _smallActionCard(context, c,
                      icon: Icons.history,
                      iconColor: const Color(0xFF7C3AED),
                      title: 'History',
                      subtitle: 'All past requests',
                      onTap: () => Navigator.push(context,
                          MaterialPageRoute(
                              builder: (_) => const TutorPermissionRequestsPage(initialFilter: 'all')))),
                ),
              ]),
            ]),
          ),

          const SizedBox(height: 28),

          // ── Recent Activity ───────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('Recent Activity',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: c.ink)),
                TextButton(
                  onPressed: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const TutorPermissionRequestsPage())),
                  child: Text('See All', style: TextStyle(color: c.blue)),
                ),
              ]),
              const SizedBox(height: 10),
              _RecentActivityList(),
            ]),
          ),

          const SizedBox(height: 30),
        ]),
      ),
    );
  }

  Widget _statCard(_AC c, String label, int count, Color color, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color: c.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.3)),
          boxShadow: [BoxShadow(
              color: Colors.black.withOpacity(c.dark ? 0.2 : 0.05),
              blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Column(children: [
          Icon(icon, color: color, size: 26),
          const SizedBox(height: 8),
          Text('$count',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(fontSize: 11, color: color.withOpacity(0.8)),
              textAlign: TextAlign.center),
        ]),
      ),
    );
  }

  Widget _actionCard(BuildContext context, _AC c, {
    required IconData icon,
    required String title,
    required String subtitle,
    String? badge,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: c.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: c.blueBorder),
          boxShadow: [BoxShadow(
              color: Colors.black.withOpacity(c.dark ? 0.2 : 0.07),
              blurRadius: 14, offset: const Offset(0, 4))],
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: c.blue, borderRadius: BorderRadius.circular(14)),
            child: Icon(icon, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: c.ink)),
              const SizedBox(height: 3),
              Text(subtitle,
                  style: TextStyle(fontSize: 12, color: c.textGrey)),
            ]),
          ),
          if (badge != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                  color: c.warn, borderRadius: BorderRadius.circular(20)),
              child: Text(badge,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
            )
          else
            Icon(Icons.arrow_forward_ios, size: 16, color: c.textGrey),
        ]),
      ),
    );
  }

  Widget _smallActionCard(BuildContext context, _AC c, {
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: c.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.blueBorder),
          boxShadow: [BoxShadow(
              color: Colors.black.withOpacity(c.dark ? 0.2 : 0.06),
              blurRadius: 10, offset: const Offset(0, 3))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: iconColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(height: 10),
          Text(title,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: c.ink)),
          const SizedBox(height: 2),
          Text(subtitle, style: TextStyle(fontSize: 11, color: c.textGrey)),
        ]),
      ),
    );
  }
}

// ── Recent activity list ─────────────────────────────────────────────────────
class _RecentActivityList extends StatelessWidget {
  const _RecentActivityList();

  @override
  Widget build(BuildContext context) {
    final c = _AC.of(context);

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('permissions')
          .orderBy('submittedAt', descending: true)
          .limit(5)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: Padding(
              padding: const EdgeInsets.all(20),
              child: CircularProgressIndicator(color: c.blue)));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
                color: c.white, borderRadius: BorderRadius.circular(16)),
            child: Center(child: Text('No recent activity',
                style: TextStyle(color: c.textGrey))),
          );
        }
        return Column(
          children: snapshot.data!.docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final name = (data['studentName'] ?? '—').toString();
            final status = (data['status'] ?? 'pending').toString();
            final ts = data['submittedAt'] as Timestamp?;
            final date = ts != null
                ? DateFormat('dd MMM, hh:mm a').format(ts.toDate()) : '—';

            Color statusColor;
            IconData statusIcon;
            switch (status) {
              case 'approved': statusColor = c.success; statusIcon = Icons.check_circle; break;
              case 'rejected': statusColor = c.danger;  statusIcon = Icons.cancel; break;
              default:         statusColor = c.warn;    statusIcon = Icons.pending;
            }

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: c.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: c.blueBorder),
                boxShadow: [BoxShadow(
                    color: Colors.black.withOpacity(c.dark ? 0.15 : 0.04),
                    blurRadius: 8, offset: const Offset(0, 2))],
              ),
              child: Row(children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: c.blueBg,
                  child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: TextStyle(color: c.blue, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(name,
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: c.ink)),
                    Text(date, style: TextStyle(fontSize: 11, color: c.textGrey)),
                  ]),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: statusColor.withOpacity(0.4))),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(statusIcon, size: 12, color: statusColor),
                    const SizedBox(width: 4),
                    Text(status.toUpperCase(),
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: statusColor)),
                  ]),
                ),
              ]),
            );
          }).toList(),
        );
      },
    );
  }
}

// ============================================================================
// TUTOR PERMISSION REQUESTS PAGE
// ============================================================================

class TutorPermissionRequestsPage extends StatefulWidget {
  final String initialFilter;
  const TutorPermissionRequestsPage({super.key, this.initialFilter = 'pending'});

  @override
  State<TutorPermissionRequestsPage> createState() =>
      _TutorPermissionRequestsPageState();
}

class _TutorPermissionRequestsPageState
    extends State<TutorPermissionRequestsPage>
    with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> _allRequests = [];
  bool _isLoading = true;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _listenToRequests();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _listenToRequests() {
    FirebaseFirestore.instance.collection('permissions').snapshots().listen(
            (snapshot) async {
          final List<Map<String, dynamic>> requests = [];
          for (final doc in snapshot.docs) {
            final data = Map<String, dynamic>.from(doc.data());
            data['_docId'] = doc.id;
            final name = data['studentName']?.toString() ?? '';
            final reg  = data['regNo']?.toString() ?? '';
            if (name.isEmpty || reg.isEmpty) {
              final uid = data['studentUid'] as String?;
              if (uid != null) {
                try {
                  final userDoc = await FirebaseFirestore.instance
                      .collection('users').doc(uid).get();
                  if (userDoc.exists) {
                    if (name.isEmpty) data['studentName'] = userDoc.data()?['name'] ?? '—';
                    if (reg.isEmpty)  data['regNo']       = userDoc.data()?['regNo'] ?? '—';
                  }
                } catch (_) {}
              }
            }
            requests.add(data);
          }
          requests.sort((a, b) {
            final aTs = a['submittedAt'], bTs = b['submittedAt'];
            if (aTs == null && bTs == null) return 0;
            if (aTs == null) return 1;
            if (bTs == null) return -1;
            return (bTs as Timestamp).compareTo(aTs as Timestamp);
          });
          if (mounted) setState(() { _allRequests = requests; _isLoading = false; });
        }, onError: (e) {
      debugPrint('Error: $e');
      if (mounted) setState(() => _isLoading = false);
    });
  }

  Future<void> _approveRequest(String docId, String studentName) async {
    try {
      await FirebaseFirestore.instance.collection('permissions').doc(docId).update({
        'status': 'approved', 'notified': true,
        'staffNote': '', 'decidedAt': FieldValue.serverTimestamp(),
      });

      final permDoc = await FirebaseFirestore.instance
          .collection('permissions').doc(docId).get();
      final studentUid = permDoc.data()?['studentUid'] as String? ?? '';
      final permId     = permDoc.data()?['permId'] as String? ?? docId;

      String? fcmToken = permDoc.data()?['fcmToken'] as String?;
      if ((fcmToken ?? '').isEmpty && studentUid.isNotEmpty) {
        final userDoc = await FirebaseFirestore.instance
            .collection('users').doc(studentUid).get();
        fcmToken = userDoc.data()?['fcmToken'] as String?;
      }

      if (studentUid.isNotEmpty) {
        // In-app bell notification
        await FirebaseFirestore.instance
            .collection('notifications')
            .doc(studentUid)
            .collection('items')
            .add({
          'title': 'Permission Approved ✅',
          'body':  'Your permission request ($permId) has been approved. Have a safe trip!',
          'type':  'permission_approved',
          'time':  FieldValue.serverTimestamp(),
          'seen':  false,
        });

        // FCM push trigger for Cloud Function
        await FirebaseFirestore.instance.collection('notifications').add({
          'toUid':    studentUid,
          'toToken':  fcmToken ?? '',
          'title':    'Permission Approved ✅',
          'body':     'Your permission request ($permId) has been approved. Have a safe trip!',
          'type':     'permission_approved',
          'permId':   permId,
          'createdAt': FieldValue.serverTimestamp(),
          'sent':     false,
        });
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Request from $studentName approved ✅'),
          backgroundColor: const Color(0xFF059669)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: const Color(0xFFDC2626)));
    }
  }

  Future<void> _rejectRequest(String docId, String studentName) async {
    String rejectionNote = '';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final noteCtrl = TextEditingController();
        return AlertDialog(
          title: const Text('Reject Request'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Are you sure you want to reject this permission request?'),
            const SizedBox(height: 12),
            TextField(
              controller: noteCtrl,
              decoration: const InputDecoration(
                hintText: 'Reason for rejection (optional)',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              onChanged: (v) => rejectionNote = v,
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: TextButton.styleFrom(foregroundColor: const Color(0xFFDC2626)),
                child: const Text('Reject')),
          ],
        );
      },
    );
    if (confirm != true) return;
    try {
      await FirebaseFirestore.instance.collection('permissions').doc(docId).update({
        'status': 'rejected', 'notified': true,
        'staffNote': rejectionNote.trim(), 'decidedAt': FieldValue.serverTimestamp(),
      });

      final permDoc = await FirebaseFirestore.instance
          .collection('permissions').doc(docId).get();
      final studentUid = permDoc.data()?['studentUid'] as String? ?? '';
      final permId     = permDoc.data()?['permId'] as String? ?? docId;

      String? fcmToken = permDoc.data()?['fcmToken'] as String?;
      if ((fcmToken ?? '').isEmpty && studentUid.isNotEmpty) {
        final userDoc = await FirebaseFirestore.instance
            .collection('users').doc(studentUid).get();
        fcmToken = userDoc.data()?['fcmToken'] as String?;
      }

      final body = rejectionNote.trim().isNotEmpty
          ? 'Your permission request ($permId) was rejected. Reason: ${rejectionNote.trim()}'
          : 'Your permission request ($permId) was rejected.';

      if (studentUid.isNotEmpty) {
        // In-app bell notification
        await FirebaseFirestore.instance
            .collection('notifications')
            .doc(studentUid)
            .collection('items')
            .add({
          'title': 'Permission Rejected ❌',
          'body':  body,
          'type':  'permission_rejected',
          'time':  FieldValue.serverTimestamp(),
          'seen':  false,
        });

        // FCM push trigger for Cloud Function
        await FirebaseFirestore.instance.collection('notifications').add({
          'toUid':    studentUid,
          'toToken':  fcmToken ?? '',
          'title':    'Permission Rejected ❌',
          'body':     body,
          'type':     'permission_rejected',
          'permId':   permId,
          'createdAt': FieldValue.serverTimestamp(),
          'sent':     false,
        });
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Request from $studentName rejected'),
          backgroundColor: const Color(0xFFDC2626)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: const Color(0xFFDC2626)));
    }
  }


  @override
  Widget build(BuildContext context) {
    final c = _AC.of(context);
    final pendingList  = _allRequests.where((r) => r['status'] == 'pending').toList();
    final approvedList = _allRequests.where((r) => r['status'] == 'approved').toList();
    final rejectedList = _allRequests.where((r) => r['status'] == 'rejected').toList();

    return Scaffold(
      backgroundColor: c.scaffold,
      appBar: AppBar(
        backgroundColor: c.appBar,
        foregroundColor: Colors.white,
        title: const Text('Permission Requests',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: [
            Tab(text: 'Pending (${pendingList.length})'),
            Tab(text: 'Approved (${approvedList.length})'),
            Tab(text: 'Rejected (${rejectedList.length})'),
          ],
        ),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: c.blue))
          : TabBarView(
        controller: _tabController,
        children: [
          _buildList(pendingList),
          _buildList(approvedList),
          _buildList(rejectedList),
        ],
      ),
    );
  }

  Widget _buildList(List<Map<String, dynamic>> list) {
    final c = _AC.of(context);
    if (list.isEmpty) {
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.inbox_outlined, size: 64, color: c.blueBorder),
        const SizedBox(height: 12),
        Text('No requests here', style: TextStyle(fontSize: 16, color: c.textGrey)),
      ]));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      physics: const BouncingScrollPhysics(),
      itemCount: list.length,
      itemBuilder: (context, index) => _buildRequestCard(list[index]),
    );
  }

  Widget _buildRequestCard(Map<String, dynamic> data) {
    final c = _AC.of(context);
    final docId         = data['_docId'] as String;
    final studentName   = (data['studentName'] ?? '—').toString();
    final regNo         = (data['regNo'] ?? '—').toString();
    final reason        = (data['reason'] ?? '—').toString();
    final outDate       = (data['outDate'] ?? '—').toString();
    final outTime       = (data['outTime'] ?? '—').toString();
    final inDate        = (data['inDate'] ?? '—').toString();
    final inTime        = (data['inTime'] ?? '—').toString();
    final destination   = (data['destinationAddress'] ?? '—').toString();
    final contactNumber = (data['contactNumber'] ?? '—').toString();
    final parentPhone   = (data['parentPhone'] ?? '—').toString();
    final parentName    = (data['parentName'] ?? '').toString();
    final staffNote     = (data['staffNote'] ?? '').toString();
    final ts = data['submittedAt'] as Timestamp?;
    final submittedStr = ts != null
        ? DateFormat('dd MMM yyyy, hh:mm a').format(ts.toDate()) : '—';

    Color statusColor;
    IconData statusIcon;
    switch (data['status']) {
      case 'approved': statusColor = c.success; statusIcon = Icons.check_circle; break;
      case 'rejected': statusColor = c.danger;  statusIcon = Icons.cancel; break;
      default:         statusColor = c.warn;     statusIcon = Icons.pending;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: c.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: statusColor.withOpacity(0.35), width: 1.5),
        boxShadow: [BoxShadow(
            color: Colors.black.withOpacity(c.dark ? 0.2 : 0.05),
            blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Row(children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: c.blueBg,
                child: Text(
                    studentName.isNotEmpty ? studentName[0].toUpperCase() : '?',
                    style: TextStyle(color: c.blue, fontWeight: FontWeight.bold, fontSize: 16)),
              ),
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(studentName,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: c.ink)),
                Text('Reg No: $regNo', style: TextStyle(fontSize: 12, color: c.textGrey)),
              ]),
            ]),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: statusColor)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(statusIcon, size: 14, color: statusColor),
                const SizedBox(width: 4),
                Text(data['status'].toString().toUpperCase(),
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: statusColor)),
              ]),
            ),
          ]),

          const SizedBox(height: 14),
          Divider(height: 1, color: c.divider),
          const SizedBox(height: 14),

          _infoRow(c, Icons.edit_note, 'Reason', reason),
          const SizedBox(height: 8),
          _infoRow(c, Icons.calendar_today, 'Out', '$outDate  $outTime'),
          const SizedBox(height: 8),
          _infoRow(c, Icons.event_available, 'Return', '$inDate  $inTime'),
          const SizedBox(height: 8),
          _infoRow(c, Icons.location_on, 'Destination', destination),
          const SizedBox(height: 8),
          _infoRow(c, Icons.phone_iphone, 'Student Contact', contactNumber),
          const SizedBox(height: 8),
          _callableRow(context: context, c: c,
              icon: Icons.phone, label: 'Parent Contact',
              phone: parentPhone, subLabel: parentName.isNotEmpty ? parentName : null),
          const SizedBox(height: 8),
          _infoRow(c, Icons.access_time, 'Submitted', submittedStr),

          if (staffNote.isNotEmpty) ...[
            const SizedBox(height: 8),
            _infoRow(c, Icons.note_outlined, 'Staff Note', staffNote),
          ],

          if (data['status'] == 'pending') ...[
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _approveRequest(docId, studentName),
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('Approve'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF059669),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _rejectRequest(docId, studentName),
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text('Reject'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFDC2626),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                ),
              ),
            ]),
          ],
        ]),
      ),
    );
  }

  Widget _infoRow(_AC c, IconData icon, String label, String value) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 16, color: c.blue),
      const SizedBox(width: 8),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 11, color: c.textGrey)),
        Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: c.ink)),
      ])),
    ]);
  }

  Widget _callableRow({
    required BuildContext context,
    required _AC c,
    required IconData icon,
    required String label,
    required String phone,
    String? subLabel,
  }) {
    final bool hasPhone = phone.isNotEmpty && phone != '—';
    return GestureDetector(
      onTap: hasPhone ? () async {
        final uri = Uri.parse('tel:$phone');
        if (await canLaunchUrl(uri)) await launchUrl(uri);
        else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Could not launch dialler')));
        }
      } : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: hasPhone ? c.blueBg : c.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: hasPhone ? c.blueBorder : c.divider),
        ),
        child: Row(children: [
          Icon(icon, size: 18, color: hasPhone ? c.blue : c.textGrey),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(subLabel != null ? '$label  ·  $subLabel' : label,
                style: TextStyle(fontSize: 11, color: hasPhone ? c.blue : c.textGrey)),
            Text(phone,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
                    color: hasPhone ? c.blue : c.textGrey)),
          ])),
          if (hasPhone)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: c.blue, borderRadius: BorderRadius.circular(8)),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.call_rounded, size: 14, color: Colors.white),
                SizedBox(width: 4),
                Text('Call', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
              ]),
            ),
        ]),
      ),
    );
  }
}

// ============================================================================
// TUTOR WEEKLY SUMMARY PAGE
// ============================================================================

class TutorWeeklySummaryPage extends StatefulWidget {
  const TutorWeeklySummaryPage({super.key});

  @override
  State<TutorWeeklySummaryPage> createState() => _TutorWeeklySummaryPageState();
}

class _TutorWeeklySummaryPageState extends State<TutorWeeklySummaryPage> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _weekRequests = [];

  @override
  void initState() {
    super.initState();
    _fetchWeek();
  }

  Future<void> _fetchWeek() async {
    setState(() => _isLoading = true);
    try {
      final weekAgo = DateTime.now().subtract(const Duration(days: 7));
      final snapshot = await FirebaseFirestore.instance
          .collection('permissions')
          .where('submittedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(weekAgo))
          .orderBy('submittedAt', descending: true)
          .get();
      if (mounted) {
        setState(() {
          _weekRequests = snapshot.docs.map((doc) {
            final data = Map<String, dynamic>.from(doc.data());
            data['_docId'] = doc.id;
            return data;
          }).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _AC.of(context);
    final pending  = _weekRequests.where((r) => r['status'] == 'pending').length;
    final approved = _weekRequests.where((r) => r['status'] == 'approved').length;
    final rejected = _weekRequests.where((r) => r['status'] == 'rejected').length;

    return Scaffold(
      backgroundColor: c.scaffold,
      appBar: AppBar(
        backgroundColor: c.appBar,
        foregroundColor: Colors.white,
        title: const Text("This Week's Summary",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh, color: Colors.white), onPressed: _fetchWeek),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: c.blue))
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: c.blueDark, borderRadius: BorderRadius.circular(14)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Weekly Overview',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(
                  '${DateFormat('dd MMM yyyy').format(DateTime.now().subtract(const Duration(days: 7)))} – ${DateFormat('dd MMM yyyy').format(DateTime.now())}',
                  style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 13)),
            ]),
          ),

          const SizedBox(height: 20),

          Row(children: [
            _weekStatCard(c, 'Total',    _weekRequests.length, c.blue,    Icons.assignment),
            const SizedBox(width: 10),
            _weekStatCard(c, 'Pending',  pending,              c.warn,    Icons.pending_actions),
            const SizedBox(width: 10),
            _weekStatCard(c, 'Approved', approved,             c.success, Icons.check_circle),
            const SizedBox(width: 10),
            _weekStatCard(c, 'Rejected', rejected,             c.danger,  Icons.cancel),
          ]),

          const SizedBox(height: 24),

          Text('Requests This Week',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: c.ink)),
          const SizedBox(height: 12),

          if (_weekRequests.isEmpty)
            Center(child: Column(children: [
              const SizedBox(height: 30),
              Icon(Icons.sentiment_satisfied_alt, size: 64, color: c.blueBorder),
              const SizedBox(height: 12),
              Text('No requests this week!', style: TextStyle(fontSize: 15, color: c.textGrey)),
            ]))
          else
            ..._weekRequests.map((r) => _weekRequestTile(c, r)),
        ]),
      ),
    );
  }

  Widget _weekStatCard(_AC c, String label, int count, Color color, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: c.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.25)),
          boxShadow: [BoxShadow(
              color: Colors.black.withOpacity(c.dark ? 0.15 : 0.04),
              blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: Column(children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 6),
          Text('$count', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
          Text(label,
              style: TextStyle(fontSize: 10, color: c.textGrey),
              textAlign: TextAlign.center),
        ]),
      ),
    );
  }

  Widget _weekRequestTile(_AC c, Map<String, dynamic> r) {
    final status = (r['status'] ?? 'pending').toString();
    Color statusColor;
    switch (status) {
      case 'approved': statusColor = c.success; break;
      case 'rejected': statusColor = c.danger; break;
      default:         statusColor = c.warn;
    }
    final name = (r['studentName'] ?? '—').toString();
    final ts   = r['submittedAt'] as Timestamp?;
    final date = ts != null ? DateFormat('dd MMM, hh:mm a').format(ts.toDate()) : '—';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: statusColor.withOpacity(0.3)),
        boxShadow: [BoxShadow(
            color: Colors.black.withOpacity(c.dark ? 0.15 : 0.04),
            blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Row(children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: c.blueBg,
          child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: TextStyle(color: c.blue, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: c.ink)),
          Text('${r['reason'] ?? '—'} • $date',
              style: TextStyle(fontSize: 11, color: c.textGrey),
              maxLines: 1, overflow: TextOverflow.ellipsis),
        ])),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
              color: statusColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: statusColor.withOpacity(0.4))),
          child: Text(status.toUpperCase(),
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: statusColor)),
        ),
      ]),
    );
  }
}