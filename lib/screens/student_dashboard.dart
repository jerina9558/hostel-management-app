// student_dashboard.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'gatepass_page.dart';
import 'complaint_page.dart';
import 'profile_page.dart';
import 'mess_menu.dart';
import 'settings_page.dart';
import 'notification_service.dart';
import '../screens/permission_request_page.dart';
import '../screens/login_page.dart';

// ─────────────────────────────────────────────────────────────────────────────
// COLOUR HELPER
// ─────────────────────────────────────────────────────────────────────────────

class _AC {
  final bool dark;
  const _AC(this.dark);
  factory _AC.of(BuildContext ctx) =>
      _AC(Theme.of(ctx).brightness == Brightness.dark);

  Color get blue => const Color(0xFF1C5FC5);
  Color get blueDark =>
      dark ? const Color(0xFF0E1A30) : const Color(0xFF1248A8);
  Color get blueBg =>
      dark ? const Color(0xFF111C30) : const Color(0xFFF0F5FF);
  Color get blueBorder =>
      dark ? const Color(0xFF1E3060) : const Color(0xFFD0DFF8);
  Color get appBar =>
      dark ? const Color(0xFF0A0D18) : const Color(0xFF1248A8);
  Color get white => dark ? const Color(0xFF1A1D2B) : Colors.white;
  Color get scaffold => dark ? const Color(0xFF12141F) : Colors.white;
  Color get ink =>
      dark ? const Color(0xFFE4E8F5) : const Color(0xFF1A1F36);
  Color get textGrey =>
      dark ? const Color(0xFF7A85A0) : const Color(0xFF6B7280);
  Color get divider =>
      dark ? const Color(0xFF222638) : const Color(0xFFE8EDF5);
  Color get success => const Color(0xFF059669);
  Color get danger => const Color(0xFFDC2626);
  Color get warn => const Color(0xFFD97706);
  Color get surface =>
      dark ? const Color(0xFF1A1D2B) : const Color(0xFFF8FAFF);
}

// ─────────────────────────────────────────────────────────────────────────────

// Types excluded from in-app notification bell & sheet
const _kExcludedNotifTypes = ['new_announcement', 'new_event'];

// ─────────────────────────────────────────────────────────────────────────────

class Event {
  final String title;
  final DateTime date;
  final String time;
  final String location;

  Event({
    required this.title,
    required this.date,
    required this.time,
    required this.location,
  });
}

class StudentDashboard extends StatefulWidget {
  const StudentDashboard({super.key});

  @override
  State<StudentDashboard> createState() => _StudentDashboardState();
}

class _StudentDashboardState extends State<StudentDashboard> {
  late Future<List<Event>> _eventsFuture;
  String userName = "";

  @override
  void initState() {
    super.initState();
    _eventsFuture = fetchEvents();
    _loadName();
    // Save FCM token every time dashboard loads (handles token refresh)
    NotificationService.saveTokenToFirestore();
  }

  Future<void> _loadName() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        SharedPreferences prefs = await SharedPreferences.getInstance();
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
        setState(() => userName = name);
      }
    } catch (e) {
      debugPrint('Error loading name: $e');
    }
  }

  Future<List<Event>> fetchEvents() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('events')
        .orderBy('date')
        .get();
    return snapshot.docs.map((doc) {
      final data = doc.data();
      return Event(
        title: data['title'],
        date: (data['date'] as Timestamp).toDate(),
        time: data['time'],
        location: data['location'],
      );
    }).toList();
  }

  Future<void> _logout() async {
    try {
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const LoginPage()),
              (route) => false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Logout failed: $e'),
          backgroundColor: Colors.red));
    }
  }

  // ── Mark all notifications as seen (excludes announcement & event types) ──
  Future<void> _markAllNotificationsSeen() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('notifications')
          .doc(uid)
          .collection('items')
          .where('seen', isEqualTo: false)
          .where('type', whereNotIn: _kExcludedNotifTypes) // ← FIX 3
          .get();
      final batch = FirebaseFirestore.instance.batch();
      for (final doc in snap.docs) {
        batch.update(doc.reference, {'seen': true});
      }
      await batch.commit();
    } catch (e) {
      debugPrint('Error marking notifications seen: $e');
    }
  }

  // ── Notification Bell Widget ───────────────────────────────────────────────
  Widget _buildNotificationBell(_AC c) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot>(
      // FIX 1: exclude announcement & event types from badge count
      stream: FirebaseFirestore.instance
          .collection('notifications')
          .doc(uid)
          .collection('items')
          .where('seen', isEqualTo: false)
          .where('type', whereNotIn: _kExcludedNotifTypes)
          .limit(99)
          .snapshots(),
      builder: (context, snapshot) {
        final unseenCount = snapshot.data?.docs.length ?? 0;
        return GestureDetector(
          onTap: () async {
            await _markAllNotificationsSeen();
            if (mounted) _showNotificationsSheet(context, c);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: SizedBox(
              width: 44,
              height: 44,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  const Icon(
                    Icons.notifications_outlined,
                    color: Colors.white,
                    size: 26,
                  ),
                  if (unseenCount > 0)
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 1),
                        constraints: const BoxConstraints(
                          minWidth: 18,
                          minHeight: 18,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE53935),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: Colors.white,
                            width: 1.5,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          unseenCount > 99 ? '99+' : '$unseenCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            height: 1,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = _AC.of(context);
    final String todayDate =
    DateFormat('EEEE, d MMM yyyy').format(DateTime.now());

    return Scaffold(
      backgroundColor: c.scaffold,
      appBar: AppBar(
        backgroundColor: c.appBar,
        foregroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text(
          'Student Dashboard',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        actions: [
          // ── NOTIFICATION BELL WITH BADGE ──────────────────────────────────
          _buildNotificationBell(c),
          // ── PROFILE ───────────────────────────────────────────────────────
          IconButton(
            icon: const Icon(Icons.person, color: Colors.white),
            onPressed: () async {
              await Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) =>
                      const ProfilePage(initialRole: 'student')));
              _loadName();
            },
          ),
          // ── SETTINGS ──────────────────────────────────────────────────────
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white),
            tooltip: 'Settings',
            onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => SettingsPage(
                        onLogout: _logout, role: UserRole.student))),
          ),
        ],
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child:
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            'Welcome, $userName 👋',
            style: TextStyle(
                fontSize: 22, fontWeight: FontWeight.bold, color: c.ink),
          ),
          const SizedBox(height: 4),
          Text(todayDate, style: TextStyle(fontSize: 16, color: c.blue)),
          const SizedBox(height: 16),
          _buildAnnouncementsSection(context, c),
          const SizedBox(height: 16),
          _buildUpcomingEventsSection(context, c),
          const SizedBox(height: 16),
          Text(
            'Quick Actions',
            style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.bold, color: c.ink),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
                child: _buildFeatureCard(context, c,
                    icon: Icons.menu_book,
                    iconColor: c.success,
                    title: 'Mess Menu',
                    subtitle: "Today's Menu",
                    page: const MessMenuStudentPage())),
            const SizedBox(width: 12),
            Expanded(
                child: _buildFeatureCard(context, c,
                    icon: Icons.assignment,
                    iconColor: const Color(0xFFE91E63),
                    title: 'Permission',
                    subtitle: 'Leave Request',
                    page: StudentPermissionPage())),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
                child: _buildFeatureCard(context, c,
                    icon: Icons.exit_to_app,
                    iconColor: c.blue,
                    title: 'Gate Pass',
                    subtitle: 'View Status',
                    page: StudentGatePassPage())),
            const SizedBox(width: 12),
            Expanded(
                child: _buildFeatureCard(context, c,
                    icon: Icons.build,
                    iconColor: c.danger,
                    title: 'Complaint',
                    subtitle: 'Report Issues',
                    page: const ComplaintPage())),
          ]),
        ]),
      ),
    );
  }

  // ── Notifications bottom sheet ─────────────────────────────────────────────
  void _showNotificationsSheet(BuildContext context, _AC c) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: BoxDecoration(
          color: c.white,
          borderRadius:
          const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(children: [
          // Handle bar
          Center(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: c.divider,
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          // Header
          Container(
            width: double.infinity,
            padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: c.blue,
            child: const Text(
              'Notifications',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w700),
            ),
          ),
          // Notification list from Firestore
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              // FIX 2: no `seen` filter here (show all), no orderBy (sort in Dart)
              stream: FirebaseFirestore.instance
                  .collection('notifications')
                  .doc(uid)
                  .collection('items')
                  .where('type', whereNotIn: _kExcludedNotifTypes)
                  .limit(30)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(
                      child: CircularProgressIndicator(color: c.blue));
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.notifications_none_outlined,
                              size: 48, color: c.blueBorder),
                          const SizedBox(height: 12),
                          Text('No notifications yet',
                              style:
                              TextStyle(color: c.textGrey, fontSize: 15)),
                        ]),
                  );
                }

                // FIX 2: sort by time descending in Dart
                // (whereNotIn + orderBy on different field needs composite index)
                final docs = [...snapshot.data!.docs]..sort((a, b) {
                  final aTime = (a.data()
                  as Map<String, dynamic>)['time'] is Timestamp
                      ? ((a.data() as Map<String, dynamic>)['time']
                  as Timestamp)
                      .millisecondsSinceEpoch
                      : 0;
                  final bTime = (b.data()
                  as Map<String, dynamic>)['time'] is Timestamp
                      ? ((b.data() as Map<String, dynamic>)['time']
                  as Timestamp)
                      .millisecondsSinceEpoch
                      : 0;
                  return bTime.compareTo(aTime); // descending
                });

                return ListView.separated(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) =>
                      Divider(height: 1, color: c.divider),
                  itemBuilder: (_, i) {
                    final data =
                    docs[i].data() as Map<String, dynamic>;
                    final title =
                    (data['title'] ?? 'Notification').toString();
                    final body = (data['body'] ?? '').toString();
                    final time = data['time'] is Timestamp
                        ? (data['time'] as Timestamp).toDate()
                        : DateTime.now();
                    final seen = data['seen'] == true;
                    final notifType = (data['type'] ?? '').toString();

                    // Pick icon based on notification type
                    IconData notifIcon = Icons.notifications_rounded;
                    Color notifColor = c.blue;
                    if (notifType == 'gate_pass_approved') {
                      notifIcon = Icons.check_circle_rounded;
                      notifColor = c.success;
                    } else if (notifType == 'gate_pass_rejected') {
                      notifIcon = Icons.cancel_rounded;
                      notifColor = c.danger;
                    } else if (notifType == 'permission_approved') {
                      notifIcon = Icons.assignment_turned_in_rounded;
                      notifColor = c.success;
                    } else if (notifType == 'permission_rejected') {
                      notifIcon = Icons.assignment_late_rounded;
                      notifColor = c.danger;
                    } else if (notifType == 'complaint_status') {
                      notifIcon = Icons.build_circle_rounded;
                      notifColor = c.warn;
                    }

                    return Container(
                      color: seen
                          ? Colors.transparent
                          : c.blue.withOpacity(0.05),
                      child: Padding(
                        padding:
                        const EdgeInsets.symmetric(vertical: 10),
                        child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                    color: notifColor.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                        color:
                                        notifColor.withOpacity(0.3))),
                                child: Icon(notifIcon,
                                    color: notifColor, size: 18),
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
                                              width: 8,
                                              height: 8,
                                              decoration: BoxDecoration(
                                                color: c.blue,
                                                shape: BoxShape.circle,
                                              ),
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
                                            DateFormat('dd MMM, hh:mm a')
                                                .format(time),
                                            style: TextStyle(
                                                fontSize: 11,
                                                color: c.textGrey)),
                                      ])),
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

  Widget _buildAnnouncementsSection(BuildContext context, _AC c) {
    return Container(
      decoration: BoxDecoration(
        color: c.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.blueBorder),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(c.dark ? 0.2 : 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child:
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.campaign, color: c.blue),
            const SizedBox(width: 8),
            Text('Announcements',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: c.ink)),
          ]),
          const SizedBox(height: 12),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('announcements')
                .orderBy('date', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Center(
                    child: CircularProgressIndicator(color: c.blue));
              }
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return Text("No announcements yet",
                    style: TextStyle(color: c.textGrey));
              }
              return Column(
                children: snapshot.data!.docs.map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  Color priorityColor;
                  switch (data['priority']) {
                    case 'high':
                      priorityColor = c.danger;
                      break;
                    case 'medium':
                      priorityColor = c.warn;
                      break;
                    default:
                      priorityColor = c.success;
                  }
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(children: [
                      Container(
                        width: 4,
                        height: 44,
                        decoration: BoxDecoration(
                            color: priorityColor,
                            borderRadius: BorderRadius.circular(2)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(data['title'] ?? '',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: c.ink)),
                                Text(data['message'] ?? '',
                                    style: TextStyle(
                                        fontSize: 12, color: c.textGrey)),
                                Text(
                                  DateFormat('dd MMM yyyy').format(
                                      (data['date'] as Timestamp).toDate()),
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: c.textGrey.withOpacity(0.7)),
                                ),
                              ])),
                    ]),
                  );
                }).toList(),
              );
            },
          ),
        ]),
      ),
    );
  }

  Widget _buildUpcomingEventsSection(BuildContext context, _AC c) {
    return Container(
      decoration: BoxDecoration(
        color: c.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.blueBorder),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(c.dark ? 0.2 : 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child:
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.event, color: c.blue),
            const SizedBox(width: 8),
            Text('Upcoming Events',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: c.ink)),
          ]),
          const SizedBox(height: 12),
          FutureBuilder<List<Event>>(
            future: _eventsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Center(
                    child: CircularProgressIndicator(color: c.blue));
              }
              if (snapshot.hasError) {
                return Text("Failed to load events",
                    style: TextStyle(color: c.danger));
              }
              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return Text("No events posted yet",
                    style: TextStyle(color: c.textGrey));
              }
              return Column(
                children: snapshot.data!.map((e) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(children: [
                      Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          color: c.blueBg,
                          border: Border.all(color: c.blue, width: 2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(DateFormat('dd').format(e.date),
                                  style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: c.ink)),
                              Text(DateFormat('MMM').format(e.date),
                                  style: TextStyle(
                                      color: c.textGrey, fontSize: 12)),
                            ]),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(e.title,
                                    style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: c.ink)),
                                Text('${e.time} • ${e.location}',
                                    style: TextStyle(
                                        fontSize: 12, color: c.textGrey)),
                              ])),
                    ]),
                  );
                }).toList(),
              );
            },
          ),
        ]),
      ),
    );
  }

  Widget _buildFeatureCard(
      BuildContext context,
      _AC c, {
        required IconData icon,
        required Color iconColor,
        required String title,
        required String subtitle,
        required Widget page,
      }) {
    return GestureDetector(
      onTap: () =>
          Navigator.push(context, MaterialPageRoute(builder: (_) => page)),
      child: Container(
        height: 160,
        decoration: BoxDecoration(
          color: c.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: iconColor.withOpacity(0.3), width: 1.5),
          boxShadow: [
            BoxShadow(
                color: iconColor.withOpacity(c.dark ? 0.12 : 0.10),
                blurRadius: 10,
                offset: const Offset(0, 4))
          ],
        ),
        child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                    color: iconColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16)),
                child: Icon(icon, size: 32, color: iconColor),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(title,
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: c.ink),
                    textAlign: TextAlign.center),
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(subtitle,
                    style: TextStyle(fontSize: 12, color: c.textGrey),
                    textAlign: TextAlign.center),
              ),
            ]),
      ),
    );
  }
}