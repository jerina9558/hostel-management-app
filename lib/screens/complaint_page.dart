import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class _C {
  final bool dark;
  const _C(this.dark);
  factory _C.of(BuildContext ctx) =>
      _C(Theme.of(ctx).brightness == Brightness.dark);

  Color get blue        => const Color(0xFF1C5FC5);
  Color get blueDark    => dark ? const Color(0xFF0E1A30) : const Color(0xFF1248A8);
  Color get blueBg      => dark ? const Color(0xFF111C30) : const Color(0xFFF0F5FF);
  Color get blueBorder  => dark ? const Color(0xFF1E3060) : const Color(0xFFD0DFF8);
  Color get white       => dark ? const Color(0xFF1A1D2B) : Colors.white;
  Color get scaffold    => dark ? const Color(0xFF12141F) : Colors.white;
  Color get ink         => dark ? const Color(0xFFE4E8F5) : const Color(0xFF1A1F36);
  Color get textGrey    => dark ? const Color(0xFF7A85A0) : const Color(0xFF6B7280);
  Color get divider     => dark ? const Color(0xFF222638) : const Color(0xFFE8EDF5);
  Color get surface     => dark ? const Color(0xFF1A1D2B) : Colors.white;
  Color get danger      => const Color(0xFFDC2626);
  Color get dangerLight => dark ? const Color(0xFF2A1010) : const Color(0xFFFEE2E2);
  Color get success     => const Color(0xFF059669);
  Color get warn        => const Color(0xFFD97706);
}

Color _statusColor(String s) {
  switch (s) {
    case 'Completed':   return const Color(0xFF059669);
    case 'In Progress': return const Color(0xFFD97706);
    default:            return const Color(0xFFDC2626);
  }
}

IconData _statusIcon(String s) {
  switch (s) {
    case 'Completed':   return Icons.check_circle;
    case 'In Progress': return Icons.pending;
    default:            return Icons.access_time;
  }
}

class ComplaintPage extends StatefulWidget {
  const ComplaintPage({super.key});
  @override
  State<ComplaintPage> createState() => _ComplaintPageState();
}

class _ComplaintPageState extends State<ComplaintPage>
    with SingleTickerProviderStateMixin {
  final _auth = FirebaseAuth.instance;
  final _db   = FirebaseFirestore.instance;

  String _role        = '';
  bool _loadingRole   = true;
  String get _uid     => _auth.currentUser?.uid ?? '';

  late TabController _tabController;
  final _roomCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String? _selectedCategory;
  bool _submitting    = false;
  String _filterStatus = 'All';
  final List<String> _statusFilters = [
    'All', 'Pending', 'In Progress', 'Completed'
  ];

  final List<Map<String, dynamic>> _categories = [
    {'name': 'Electrical', 'icon': Icons.lightbulb_outline},
    {'name': 'Plumbing',   'icon': Icons.water_drop_outlined},
    {'name': 'Furniture',  'icon': Icons.chair_outlined},
    {'name': 'Cleaning',   'icon': Icons.cleaning_services_outlined},
    {'name': 'Fan',        'icon': Icons.ac_unit_outlined},
    {'name': 'Other',      'icon': Icons.more_horiz},
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchRole();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _roomCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchRole() async {
    try {
      final snap = await _db.collection('users').doc(_uid).get();
      if (mounted) {
        setState(() {
          _role        = snap.data()?['role'] as String? ?? 'student';
          _loadingRole = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() { _role = 'student'; _loadingRole = false; });
    }
  }

  String _fmtDate(Timestamp? ts) {
    if (ts == null) return 'Just now';
    final d = ts.toDate();
    const mo = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${d.day} ${mo[d.month - 1]} ${d.year}';
  }

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w700)),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
    ));
  }

  // ── Mark all notifications as seen ─────────────────────────────
  Future<void> _markAllNotificationsSeen() async {
    try {
      final snap = await _db
          .collection('notifications')
          .doc(_uid)
          .collection('items')
          .where('seen', isEqualTo: false)
          .get();
      final batch = _db.batch();
      for (final doc in snap.docs) {
        batch.update(doc.reference, {'seen': true});
      }
      await batch.commit();
    } catch (e) {
      debugPrint('Error marking notifications seen: $e');
    }
  }

  // ── Notifications bottom sheet ──────────────────────────────────
  void _showNotificationsSheet(BuildContext context) {
    final c = _C.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(children: [
          Center(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
              width: 36, height: 4,
              decoration: BoxDecoration(color: c.divider, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: c.blue,
            child: const Text('Notifications',
                style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _db
                  .collection('notifications')
                  .doc(_uid)
                  .collection('items')
                  .orderBy('time', descending: true)
                  .limit(30)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator(color: c.blue));
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.notifications_none_outlined, size: 48, color: c.blueBorder),
                      const SizedBox(height: 12),
                      Text('No notifications yet', style: TextStyle(color: c.textGrey, fontSize: 15)),
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
                    final body = (data['body'] ?? '').toString();
                    final time = data['time'] is Timestamp
                        ? (data['time'] as Timestamp).toDate()
                        : DateTime.now();
                    final seen = data['seen'] == true;
                    final notifType = (data['type'] ?? '').toString();

                    IconData notifIcon = Icons.notifications_rounded;
                    Color notifColor = c.blue;
                    if (notifType == 'gate_pass_approved') { notifIcon = Icons.check_circle_rounded; notifColor = c.success; }
                    else if (notifType == 'gate_pass_rejected') { notifIcon = Icons.cancel_rounded; notifColor = c.danger; }
                    else if (notifType == 'permission_approved') { notifIcon = Icons.assignment_turned_in_rounded; notifColor = c.success; }
                    else if (notifType == 'permission_rejected') { notifIcon = Icons.assignment_late_rounded; notifColor = c.danger; }
                    else if (notifType == 'complaint_status') { notifIcon = Icons.build_circle_rounded; notifColor = c.warn; }
                    else if (notifType == 'new_announcement') { notifIcon = Icons.campaign_rounded; notifColor = c.blue; }
                    else if (notifType == 'new_event') { notifIcon = Icons.event_rounded; notifColor = const Color(0xFF7C3AED); }

                    return Container(
                      color: seen ? Colors.transparent : c.blue.withOpacity(0.05),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Container(
                            width: 36, height: 36,
                            decoration: BoxDecoration(
                                color: notifColor.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: notifColor.withOpacity(0.3))),
                            child: Icon(notifIcon, color: notifColor, size: 18),
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
                                    decoration: BoxDecoration(color: c.blue, shape: BoxShape.circle),
                                  ),
                              ]),
                              if (body.isNotEmpty) ...[
                                const SizedBox(height: 3),
                                Text(body, style: TextStyle(fontSize: 13, color: c.textGrey)),
                              ],
                              const SizedBox(height: 4),
                              Text(DateFormat('dd MMM, hh:mm a').format(time),
                                  style: TextStyle(fontSize: 11, color: c.textGrey)),
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

  Future<void> _submitComplaint() async {
    if (_selectedCategory == null ||
        _roomCtrl.text.trim().isEmpty ||
        _descCtrl.text.trim().isEmpty) {
      _snack('Please fill all fields', const Color(0xFFDC2626));
      return;
    }
    setState(() => _submitting = true);
    try {
      final ref     = _db.collection('complaints').doc();
      final shortId = 'C${ref.id.substring(0, 5).toUpperCase()}';
      await ref.set({
        'shortId':     shortId,
        'studentUid':  _uid,
        'category':    _selectedCategory,
        'roomNumber':  _roomCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
        'status':      'Pending',
        'createdAt':   FieldValue.serverTimestamp(),
        'updatedAt':   FieldValue.serverTimestamp(),
      });

      await _notifyWardens(shortId); // ← only new line added here

      if (!mounted) return;
      _snack('Complaint submitted successfully!', const Color(0xFF059669));
      setState(() => _selectedCategory = null);
      _roomCtrl.clear();
      _descCtrl.clear();
      _tabController.animateTo(1);
    } catch (e) {
      if (mounted) _snack('Error: $e', const Color(0xFFDC2626));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
  Future<void> _notifyWardens(String shortId) async {
    try {
      final wardensSnap = await _db
          .collection('users')
          .where('role', isEqualTo: 'warden')
          .get();

      final batch = _db.batch();

      for (final wardenDoc in wardensSnap.docs) {
        final wardenUid = wardenDoc.id;
        final fcmToken  = wardenDoc.data()['fcmToken'] as String?;

        final title = 'New Complaint Raised 🔧';
        final body  = 'Room ${_roomCtrl.text.trim()} – '
            '$_selectedCategory complaint ($shortId) needs attention.';

        // In-app bell notification
        final notifRef = _db
            .collection('notifications')
            .doc(wardenUid)
            .collection('items')
            .doc();
        batch.set(notifRef, {
          'title': title,
          'body':  body,
          'type':  'complaint_raised',
          'time':  FieldValue.serverTimestamp(),
          'seen':  false,
        });

        // FCM push trigger for Cloud Function
        final pushRef = _db.collection('notifications').doc();
        batch.set(pushRef, {
          'toUid':     wardenUid,
          'toToken':   fcmToken ?? '',
          'title':     title,
          'body':      body,
          'type':      'complaint_raised',
          'createdAt': FieldValue.serverTimestamp(),
          'sent':      false,
        });
      }

      await batch.commit();
    } catch (e) {
      debugPrint('Error notifying wardens: $e');
    }
  }

  Future<void> _showUpdateDialog(String docId, Map<String, dynamic> data) async {
    String currentStatus = data['status'] as String? ?? 'Pending';
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          final dc = _C.of(ctx);
          return AlertDialog(
            backgroundColor: dc.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            title: Row(children: [
              Icon(Icons.edit_rounded, color: dc.blue, size: 20),
              const SizedBox(width: 8),
              Text('Update Status',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: dc.ink)),
            ]),
            content: SingleChildScrollView(
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: dc.blueBg,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: dc.blueBorder),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        _dlgRow(dc, Icons.category_outlined, data['category'] ?? ''),
                        const SizedBox(height: 6),
                        _dlgRow(dc, Icons.door_front_door_outlined, 'Room ${data['roomNumber'] ?? ''}'),
                        const SizedBox(height: 6),
                        _dlgRow(dc, Icons.notes_rounded, data['description'] ?? '', wrap: true),
                      ]),
                    ),
                    const SizedBox(height: 18),
                    Text('Status',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: dc.textGrey)),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8, runSpacing: 8,
                      children: ['Pending', 'In Progress', 'Completed'].map((s) {
                        final sel   = currentStatus == s;
                        final color = _statusColor(s);
                        return GestureDetector(
                          onTap: () => setDlg(() => currentStatus = s),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: sel ? color : dc.blueBg,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: sel ? color : dc.blueBorder, width: sel ? 2 : 1),
                            ),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(_statusIcon(s), size: 13, color: sel ? Colors.white : color),
                              const SizedBox(width: 6),
                              Text(s,
                                  style: TextStyle(
                                      fontSize: 13, fontWeight: FontWeight.w600,
                                      color: sel ? Colors.white : color)),
                            ]),
                          ),
                        );
                      }).toList(),
                    ),
                  ]),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('Cancel', style: TextStyle(color: dc.textGrey))),
              GestureDetector(
                onTap: () async {
                  await _db.collection('complaints').doc(docId).update({
                    'status':    currentStatus,
                    'updatedAt': FieldValue.serverTimestamp(),
                  });

                  final studentUid = data['studentUid'] as String? ?? '';

                  String? fcmToken;
                  if (studentUid.isNotEmpty) {
                    try {
                      final userDoc = await _db.collection('users').doc(studentUid).get();
                      fcmToken = userDoc.data()?['fcmToken'] as String?;
                    } catch (_) {}
                  }

                  final title = currentStatus == 'Completed'
                      ? 'Complaint Resolved ✅'
                      : 'Complaint Updated';
                  final body = 'Your ${data['category']} complaint '
                      '(${data['shortId']}) status changed to "$currentStatus".';

                  if (studentUid.isNotEmpty) {
                    // In-app bell notification
                    await _db
                        .collection('notifications')
                        .doc(studentUid)
                        .collection('items')
                        .add({
                      'title': title,
                      'body':  body,
                      'type':  'complaint_status',
                      'time':  FieldValue.serverTimestamp(),
                      'seen':  false,
                    });

                    // FCM push trigger for Cloud Function
                    await _db.collection('notifications').add({
                      'toUid':     studentUid,
                      'toToken':   fcmToken ?? '',
                      'title':     title,
                      'body':      body,
                      'type':      'complaint_status',
                      'createdAt': FieldValue.serverTimestamp(),
                      'sent':      false,
                    });
                  }

                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) _snack('Status updated successfully', const Color(0xFF059669));
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                  decoration: BoxDecoration(color: dc.blue, borderRadius: BorderRadius.circular(8)),
                  child: const Text('Save',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = _C.of(context);
    if (_loadingRole) {
      return Scaffold(
        backgroundColor: c.scaffold,
        body: Center(child: CircularProgressIndicator(color: c.blue)),
      );
    }
    return _role == 'warden' ? _buildWardenView() : _buildStudentView();
  }

  // ── Student View ────────────────────────────────────────────────
  Widget _buildStudentView() {
    final c = _C.of(context);
    return Scaffold(
      backgroundColor: c.scaffold,
      appBar: AppBar(
        backgroundColor: c.blueDark,
        elevation: 0,
        title: const Text('Complaints',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        iconTheme: const IconThemeData(color: Colors.white),
        // ── NOTIFICATION BELL ─────────────────────────────────────
        actions: [
          StreamBuilder<QuerySnapshot>(
            stream: _db
                .collection('notifications')
                .doc(_uid)
                .collection('items')
                .where('seen', isEqualTo: false)
                .limit(99)
                .snapshots(),
            builder: (context, snapshot) {
              final unseenCount = snapshot.data?.docs.length ?? 0;
              return Stack(
                alignment: Alignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.notifications_outlined, color: Colors.white),
                    tooltip: 'Notifications',
                    onPressed: () async {
                      await _markAllNotificationsSeen();
                      if (mounted) _showNotificationsSheet(context);
                    },
                  ),
                  if (unseenCount > 0)
                    Positioned(
                      top: 8, right: 8,
                      child: Container(
                        width: 18, height: 18,
                        decoration: const BoxDecoration(
                            color: Color(0xFFE53935), shape: BoxShape.circle),
                        alignment: Alignment.center,
                        child: Text(
                          unseenCount > 99 ? '99+' : '$unseenCount',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
        // ─────────────────────────────────────────────────────────
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          indicatorSize: TabBarIndicatorSize.tab,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white54,
          labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
          tabs: const [
            Tab(text: 'New Complaint'),
            Tab(text: 'Track Complaints'),
          ],
        ),
      ),
      body: TabBarView(
          controller: _tabController,
          children: [_buildNewComplaintTab(), _buildTrackTab()]),
    );
  }

  Widget _buildNewComplaintTab() {
    final c = _C.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 40),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
          decoration: BoxDecoration(
              color: c.blueBg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: c.blueBorder)),
          child: Row(children: [
            Icon(Icons.info_outline_rounded, color: c.blue, size: 16),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                  'Your complaint will be assigned to maintenance staff and resolved as soon as possible.',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: c.blue)),
            ),
          ]),
        ),
        const SizedBox(height: 18),
        _sectionLabel(c, 'Room Number'),
        const SizedBox(height: 10),
        TextField(
          controller: _roomCtrl,
          style: TextStyle(color: c.ink, fontWeight: FontWeight.w500),
          decoration: _deco(c, 'Enter your room number (e.g., 204)',
              prefixIcon: Icon(Icons.door_front_door, color: c.textGrey, size: 18)),
        ),
        const SizedBox(height: 20),
        _sectionLabel(c, 'Select Category'),
        const SizedBox(height: 10),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3, crossAxisSpacing: 10,
              mainAxisSpacing: 10, childAspectRatio: 1.05),
          itemCount: _categories.length,
          itemBuilder: (_, i) {
            final cat = _categories[i];
            final sel = _selectedCategory == cat['name'];
            return GestureDetector(
              onTap: () => setState(() => _selectedCategory = cat['name']),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                decoration: BoxDecoration(
                  color: sel ? c.blueBg : c.surface,
                  border: Border.all(color: sel ? c.blue : c.divider, width: sel ? 1.5 : 1),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [BoxShadow(
                      color: Colors.black.withOpacity(c.dark ? 0.2 : 0.04),
                      blurRadius: 4, offset: const Offset(0, 2))],
                ),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(cat['icon'] as IconData, size: 28, color: sel ? c.blue : c.textGrey),
                  const SizedBox(height: 7),
                  Text(cat['name'] as String,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                          color: sel ? c.blue : c.textGrey)),
                ]),
              ),
            );
          },
        ),
        const SizedBox(height: 20),
        _sectionLabel(c, 'Description'),
        const SizedBox(height: 10),
        TextField(
          controller: _descCtrl,
          maxLines: 5,
          style: TextStyle(color: c.ink, fontWeight: FontWeight.w500),
          decoration: _deco(c, 'Describe the issue in detail...'),
        ),
        const SizedBox(height: 22),
        SizedBox(
          width: double.infinity, height: 50,
          child: GestureDetector(
            onTap: _submitting ? null : _submitComplaint,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: BoxDecoration(
                color: _submitting ? c.blue.withOpacity(0.6) : c.blue,
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: _submitting
                  ? const SizedBox(width: 22, height: 22,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                  : const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.send_rounded, color: Colors.white, size: 17),
                SizedBox(width: 8),
                Text('Submit Complaint',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
              ]),
            ),
          ),
        ),
        const SizedBox(height: 16),
      ]),
    );
  }

  Widget _buildTrackTab() {
    final c = _C.of(context);
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _db.collection('complaints').where('studentUid', isEqualTo: _uid).snapshots(),
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator(color: c.blue));
        }
        if (snap.hasError) {
          return Center(child: Text('Error: ${snap.error}',
              style: const TextStyle(color: Color(0xFFDC2626))));
        }
        final docs = (snap.data?.docs ?? [])..sort((a, b) {
          final aTs = a.data()['createdAt'] as Timestamp?;
          final bTs = b.data()['createdAt'] as Timestamp?;
          if (aTs == null && bTs == null) return 0;
          if (aTs == null) return 1;
          if (bTs == null) return -1;
          return bTs.compareTo(aTs);
        });
        if (docs.isEmpty) {
          return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.inbox_outlined, size: 64, color: c.blueBorder),
            const SizedBox(height: 14),
            Text('No Complaints Yet',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.ink)),
            const SizedBox(height: 6),
            Text('Your complaint history will appear here',
                style: TextStyle(fontSize: 13, color: c.textGrey)),
          ]));
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 32),
          itemCount: docs.length,
          itemBuilder: (_, i) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _buildComplaintCard(docs[i].id, docs[i].data(), isWarden: false),
          ),
        );
      },
    );
  }

  // ── Warden View ─────────────────────────────────────────────────
  Widget _buildWardenView() {
    final c = _C.of(context);
    return Scaffold(
      backgroundColor: c.scaffold,
      appBar: AppBar(
        backgroundColor: c.blueDark,
        elevation: 0,
        title: const Text('Manage Complaints',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [c.blue, c.blueDark],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Column(children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18), shape: BoxShape.circle),
              child: const Icon(Icons.report_problem_rounded, size: 36, color: Colors.white),
            ),
            const SizedBox(height: 10),
            const Text('Student Complaints',
                style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('Review and update complaint statuses',
                style: TextStyle(color: Colors.white.withOpacity(0.88), fontSize: 13)),
          ]),
        ),
        Container(
          color: c.surface,
          padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 14),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
                children: _statusFilters.map((s) {
                  final sel   = _filterStatus == s;
                  final color = s == 'All' ? c.blue : _statusColor(s);
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () => setState(() => _filterStatus = s),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: sel ? color : c.blueBg,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: sel ? color : c.blueBorder),
                        ),
                        child: Text(s,
                            style: TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600,
                                color: sel ? Colors.white : c.textGrey)),
                      ),
                    ),
                  );
                }).toList()),
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _db.collection('complaints').snapshots(),
            builder: (ctx, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return Center(child: CircularProgressIndicator(color: c.blue));
              }
              if (snap.hasError) {
                return Center(child: Text('Error: ${snap.error}',
                    style: const TextStyle(color: Color(0xFFDC2626))));
              }
              final docs = (snap.data?.docs ?? []).where((d) {
                if (_filterStatus == 'All') return true;
                return d.data()['status'] == _filterStatus;
              }).toList()
                ..sort((a, b) {
                  final aTs = a.data()['createdAt'] as Timestamp?;
                  final bTs = b.data()['createdAt'] as Timestamp?;
                  if (aTs == null && bTs == null) return 0;
                  if (aTs == null) return 1;
                  if (bTs == null) return -1;
                  return bTs.compareTo(aTs);
                });
              if (docs.isEmpty) {
                return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.inbox_outlined, size: 64, color: c.blueBorder),
                  const SizedBox(height: 14),
                  Text('No complaints found',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.textGrey)),
                ]));
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 32),
                itemCount: docs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) =>
                    _buildComplaintCard(docs[i].id, docs[i].data(), isWarden: true),
              );
            },
          ),
        ),
      ]),
    );
  }

  // ── Shared Card ─────────────────────────────────────────────────
  Widget _buildComplaintCard(String docId, Map<String, dynamic> d, {required bool isWarden}) {
    final c      = _C.of(context);
    final status = d['status'] as String? ?? 'Pending';
    final sColor = _statusColor(status);
    final sIcon  = _statusIcon(status);

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border(left: BorderSide(color: sColor, width: 4)),
        boxShadow: [BoxShadow(
            color: Colors.black.withOpacity(c.dark ? 0.2 : 0.04),
            blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Row(children: [
              _badge(c, d['shortId'] as String? ?? ''),
              const SizedBox(width: 8),
              _roomBadge(c, d['roomNumber'] as String? ?? ''),
            ]),
            _statusPill(status, sColor, sIcon),
          ]),
          const SizedBox(height: 11),
          Row(children: [
            Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(color: c.blueBg, borderRadius: BorderRadius.circular(6)),
              child: Icon(Icons.category_outlined, size: 14, color: c.textGrey),
            ),
            const SizedBox(width: 8),
            Text(d['category'] as String? ?? '',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.ink)),
          ]),
          const SizedBox(height: 7),
          Text(d['description'] as String? ?? '',
              style: TextStyle(fontSize: 13, color: c.textGrey, height: 1.4)),
          const SizedBox(height: 10),
          Divider(height: 1, color: c.divider),
          const SizedBox(height: 9),
          Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(children: [
                  Icon(Icons.calendar_today, size: 12, color: c.textGrey),
                  const SizedBox(width: 4),
                  Text(_fmtDate(d['createdAt'] as Timestamp?),
                      style: TextStyle(fontSize: 12, color: c.textGrey)),
                ]),
                if (isWarden)
                  GestureDetector(
                    onTap: () => _showUpdateDialog(docId, d),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(color: c.blue, borderRadius: BorderRadius.circular(8)),
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.edit_rounded, size: 13, color: Colors.white),
                        SizedBox(width: 5),
                        Text('Update',
                            style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
                      ]),
                    ),
                  ),
              ]),
        ]),
      ),
    );
  }

  // ── Small widgets ───────────────────────────────────────────────
  Widget _sectionLabel(_C c, String text) => Text(text,
      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.blue));

  InputDecoration _deco(_C c, String hint, {Widget? prefixIcon}) =>
      InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: c.textGrey, fontWeight: FontWeight.w400, fontSize: 13),
        prefixIcon: prefixIcon,
        filled: true,
        fillColor: c.blueBg,
        contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.blueBorder)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.blue, width: 1.5)),
      );

  Widget _badge(_C c, String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
        color: c.blueBg, borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.blueBorder)),
    child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.blue)),
  );

  Widget _roomBadge(_C c, String room) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED), borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFFED7AA))),
    child: Row(children: [
      const Icon(Icons.door_front_door, size: 11, color: Color(0xFFD97706)),
      const SizedBox(width: 4),
      Text('Room $room',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFD97706))),
    ]),
  );

  Widget _statusPill(String status, Color color, IconData icon) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
    child: Row(children: [
      Icon(icon, size: 12, color: color),
      const SizedBox(width: 4),
      Text(status, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
    ]),
  );

  Widget _dlgRow(_C c, IconData icon, String text, {bool wrap = false}) =>
      Row(
          crossAxisAlignment: wrap ? CrossAxisAlignment.start : CrossAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: c.textGrey),
            const SizedBox(width: 8),
            wrap
                ? Expanded(child: Text(text, style: TextStyle(fontSize: 13, color: c.ink)))
                : Text(text, style: TextStyle(fontSize: 13, color: c.ink)),
          ]);
}