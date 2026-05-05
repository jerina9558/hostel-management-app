import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// ─────────────────────────────────────────────────────────────────────────────
// COLOUR HELPER
// ─────────────────────────────────────────────────────────────────────────────

class _C {
  final bool dark;
  const _C(this.dark);
  factory _C.of(BuildContext ctx) =>
      _C(Theme.of(ctx).brightness == Brightness.dark);

  Color get blue       => const Color(0xFF1C5FC5);
  Color get blueDark   => dark ? const Color(0xFF0E1A30) : const Color(0xFF1248A8);
  Color get blueBg     => dark ? const Color(0xFF111C30) : const Color(0xFFF0F5FF);
  Color get blueBorder => dark ? const Color(0xFF1E3060) : const Color(0xFFD0DFF8);
  Color get white      => dark ? const Color(0xFF1A1D2B) : Colors.white;
  Color get scaffold   => dark ? const Color(0xFF12141F) : Colors.white;
  Color get ink        => dark ? const Color(0xFFE4E8F5) : const Color(0xFF1A1F36);
  Color get textGrey   => dark ? const Color(0xFF7A85A0) : const Color(0xFF6B7280);
  Color get divider    => dark ? const Color(0xFF222638) : const Color(0xFFE8EDF5);
  Color get surface    => dark ? const Color(0xFF1A1D2B) : Colors.white;
}

Color _priorityColor(String priority) {
  switch (priority) {
    case 'high':   return const Color(0xFFDC2626);
    case 'low':    return const Color(0xFF059669);
    default:       return const Color(0xFFD97706);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// NOTIFICATION DISPATCH HELPER
//
// Queries every user whose role == 'student' and whose
// 'announcement_notifications' AND 'push_notifications' prefs are both true
// (stored in Firestore under users/{uid}/settings), then writes a notification
// document into notifications/{uid}/items.
// ─────────────────────────────────────────────────────────────────────────────

Future<void> _dispatchAnnouncementNotification({
  required String title,
  required String message,
  required String priority,
}) async {
  final db = FirebaseFirestore.instance;

  // 1. Fetch all students
  final usersSnap = await db
      .collection('users')
      .where('role', isEqualTo: 'student')
      .get();

  if (usersSnap.docs.isEmpty) return;

  // 2. For each student, check their notification preferences
  final batch = db.batch();
  int writeCount = 0;

  for (final userDoc in usersSnap.docs) {
    final uid = userDoc.id;

    // Read per-user settings stored in Firestore
    // (SettingsPage persists to SharedPreferences locally, but for
    //  cross-device dispatch we store a mirror in users/{uid}/settings)
    final settingsSnap = await db
        .collection('users')
        .doc(uid)
        .collection('settings')
        .doc('notifications')
        .get();

    final settings = settingsSnap.data() ?? {};

    final pushEnabled         = settings['push_notifications']         ?? true;
    final announcementsEnabled = settings['announcement_notifications'] ?? true;

    // Skip students who have either master or sub-toggle disabled
    if (!pushEnabled || !announcementsEnabled) continue;

    // 3. Write notification document
    final notifRef = db
        .collection('notifications')
        .doc(uid)
        .collection('items')
        .doc(); // auto-ID

    batch.set(notifRef, {
      'type'     : 'announcement',
      'title'    : title,
      'body'     : message,
      'priority' : priority,
      'time'     : FieldValue.serverTimestamp(),
      'read'     : false,
    });

    // ── FCM push trigger — root collection → Cloud Function fires ──
    await db.collection('notifications').add({
      'toUid'    : uid,
      'toToken'  : userDoc.data()['fcmToken'] as String? ?? '',
      'title'    : title,
      'body'     : message,
      'type'     : 'new_announcement',
      'createdAt': FieldValue.serverTimestamp(),
      'sent'     : false,
    });

    writeCount++;
    // Firestore batch limit is 500 — flush and start a new batch if needed
    if (writeCount % 499 == 0) {
      await batch.commit();
    }
  }

  if (writeCount % 499 != 0) {
    await batch.commit();
  }
}

// ═══════════════════════════════════════════════════════════════════
//  PAGE 1 – WardenAnnouncementsPage
// ═══════════════════════════════════════════════════════════════════
class WardenAnnouncementsPage extends StatefulWidget {
  const WardenAnnouncementsPage({super.key});

  @override
  State<WardenAnnouncementsPage> createState() =>
      _WardenAnnouncementsPageState();
}

class _WardenAnnouncementsPageState extends State<WardenAnnouncementsPage> {
  final _formKey     = GlobalKey<FormState>();
  final _titleCtrl   = TextEditingController();
  final _messageCtrl = TextEditingController();
  String _priority   = 'medium';
  bool   _saving     = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  void _clearForm() {
    _titleCtrl.clear();
    _messageCtrl.clear();
    setState(() => _priority = 'medium');
  }

  Future<void> _post() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final title    = _titleCtrl.text.trim();
    final message  = _messageCtrl.text.trim();
    final priority = _priority;

    try {
      // 1. Save announcement to the main collection (shown on all dashboards)
      await FirebaseFirestore.instance.collection('announcements').add({
        'title'    : title,
        'message'  : message,
        'priority' : priority,
        'location' : 'Hostel',
        'time'     : 'All Day',
        'date'     : Timestamp.fromDate(DateTime.now()),
        'createdAt': FieldValue.serverTimestamp(),
      });

      // 2. Dispatch notification only to students who opted in
      await _dispatchAnnouncementNotification(
        title:    title,
        message:  message,
        priority: priority,
      );

      _clearForm();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Announcement posted successfully',
            style: TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: const Color(0xFF059669),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error: $e',
            style: const TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: const Color(0xFFDC2626),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      ));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _C.of(context);

    return Scaffold(
      backgroundColor: c.scaffold,
      appBar: AppBar(
        backgroundColor: c.blueDark,
        elevation: 0,
        title: const Text('Post Announcement',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(
                    builder: (_) => const ViewAnnouncementsPage())),
            icon: const Icon(Icons.list_alt_rounded,
                color: Colors.white, size: 20),
            label: const Text('View',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
        child: Column(children: [
          // ── Hero banner ──────────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [c.blue, c.blueDark],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: const BorderRadius.only(
                bottomLeft:  Radius.circular(24),
                bottomRight: Radius.circular(24),
              ),
              boxShadow: [
                BoxShadow(
                    color: c.blue.withOpacity(0.35),
                    blurRadius: 20,
                    offset: const Offset(0, 10))
              ],
            ),
            child: Column(children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.18),
                    shape: BoxShape.circle),
                child: const Icon(Icons.campaign,
                    size: 44, color: Colors.white),
              ),
              const SizedBox(height: 14),
              const Text('Create Announcement',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text('Notify all students instantly',
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.88), fontSize: 13)),
            ]),
          ),
          const SizedBox(height: 22),

          Form(
            key: _formKey,
            child: Column(children: [
              // Title
              _card(c, child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _lbl(c, Icons.title, 'Title'),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _titleCtrl,
                      style: TextStyle(
                          color: c.ink, fontWeight: FontWeight.w500),
                      decoration: _deco(c,
                          'e.g., Hostel Mess Timings Updated'),
                      validator: (v) =>
                      (v == null || v.isEmpty) ? 'Please enter a title' : null,
                    ),
                  ])),
              const SizedBox(height: 12),

              // Message
              _card(c, child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _lbl(c, Icons.message, 'Message'),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _messageCtrl,
                      maxLines: 4,
                      style: TextStyle(
                          color: c.ink, fontWeight: FontWeight.w500),
                      decoration:
                      _deco(c, 'Enter announcement details...'),
                      validator: (v) =>
                      (v == null || v.isEmpty) ? 'Please enter a message' : null,
                    ),
                  ])),
              const SizedBox(height: 12),

              // Priority
              _card(c, child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _lbl(c, Icons.priority_high, 'Priority Level'),
                    const SizedBox(height: 14),
                    Row(children: [
                      _chip(c, 'high',   const Color(0xFFDC2626), 'High'),
                      const SizedBox(width: 10),
                      _chip(c, 'medium', const Color(0xFFD97706), 'Medium'),
                      const SizedBox(width: 10),
                      _chip(c, 'low',    const Color(0xFF059669), 'Low'),
                    ]),
                  ])),
              const SizedBox(height: 22),

              // Post button
              SizedBox(
                width: double.infinity, height: 50,
                child: GestureDetector(
                  onTap: _saving ? null : _post,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    decoration: BoxDecoration(
                      color: _saving ? c.blue.withOpacity(0.6) : c.blue,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: _saving
                        ? const SizedBox(
                        width: 22, height: 22,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2.5))
                        : const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.send, color: Colors.white, size: 18),
                          SizedBox(width: 8),
                          Text('Post Announcement',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white)),
                        ]),
                  ),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  Widget _card(_C c, {required Widget child}) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: c.surface,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: c.divider),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(c.dark ? 0.25 : 0.05),
          blurRadius: 8,
          offset: const Offset(0, 2),
        )
      ],
    ),
    child: child,
  );

  Widget _lbl(_C c, IconData icon, String text) => Row(children: [
    Icon(icon, color: c.blue, size: 18),
    const SizedBox(width: 8),
    Text(text,
        style: TextStyle(
            fontSize: 14, fontWeight: FontWeight.w700, color: c.blue)),
  ]);

  InputDecoration _deco(_C c, String hint) => InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(
        color: c.textGrey, fontWeight: FontWeight.w400, fontSize: 13),
    filled: true,
    fillColor: c.blueBg,
    contentPadding:
    const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
    border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide.none),
    enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: c.blueBorder)),
    focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: c.blue, width: 1.5)),
    errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFDC2626))),
    focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide:
        const BorderSide(color: Color(0xFFDC2626), width: 1.5)),
  );

  Widget _chip(_C c, String value, Color color, String label) {
    final sel = _priority == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _priority = value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: sel ? color : c.blueBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: sel ? color : c.blueBorder,
              width: sel ? 2 : 1,
            ),
          ),
          child: Center(
            child: Text(label,
                style: TextStyle(
                    color: sel ? Colors.white : c.textGrey,
                    fontWeight:
                    sel ? FontWeight.w700 : FontWeight.w500,
                    fontSize: 13)),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  PAGE 2 – ViewAnnouncementsPage
// ═══════════════════════════════════════════════════════════════════
class ViewAnnouncementsPage extends StatelessWidget {
  const ViewAnnouncementsPage({super.key});

  String _fmtDate(DateTime d) {
    const mo = [
      'Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec'
    ];
    return '${d.day} ${mo[d.month - 1]} ${d.year}';
  }

  Future<void> _confirmDelete(BuildContext context, String docId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final c = _C.of(ctx);
        return AlertDialog(
          backgroundColor: c.surface,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
          title: Text('Delete announcement?',
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: c.ink)),
          content: Text(
              'This will permanently remove the announcement from all student dashboards.',
              style: TextStyle(color: c.textGrey, fontSize: 13)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('Cancel',
                    style: TextStyle(color: c.textGrey))),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFDC2626),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8))),
              child: const Text('Delete',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        );
      },
    );
    if (ok == true) {
      await FirebaseFirestore.instance
          .collection('announcements')
          .doc(docId)
          .delete();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Announcement deleted'),
          backgroundColor: Color(0xFFDC2626),
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _C.of(context);

    return Scaffold(
      backgroundColor: c.scaffold,
      appBar: AppBar(
        backgroundColor: c.blueDark,
        elevation: 0,
        title: const Text('Posted Announcements',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('announcements')
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (ctx, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return Center(
                child: CircularProgressIndicator(color: c.blue));
          }
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}',
                style: const TextStyle(color: Color(0xFFDC2626))));
          }
          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) {
            return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.campaign_outlined,
                    size: 60, color: c.blueBorder),
                const SizedBox(height: 12),
                Text('No announcements posted yet',
                    style: TextStyle(fontSize: 15, color: c.textGrey)),
              ]),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 32),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (ctx, i) {
              final doc      = docs[i];
              final d        = doc.data();
              final priority = d['priority'] as String? ?? 'medium';
              final pColor   = _priorityColor(priority);

              return Container(
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: c.divider),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black
                          .withOpacity(c.dark ? 0.25 : 0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    )
                  ],
                ),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      Container(
                        padding:
                        const EdgeInsets.fromLTRB(14, 13, 14, 11),
                        decoration: BoxDecoration(
                          color: pColor
                              .withOpacity(c.dark ? 0.14 : 0.07),
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(9)),
                        ),
                        child: Row(children: [
                          Container(
                              width: 9, height: 9,
                              decoration: BoxDecoration(
                                  color: pColor,
                                  shape: BoxShape.circle)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(d['title'] ?? '',
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: c.ink)),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 9, vertical: 3),
                            decoration: BoxDecoration(
                              color: pColor.withOpacity(0.13),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              priority[0].toUpperCase() +
                                  priority.substring(1),
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: pColor),
                            ),
                          ),
                        ]),
                      ),

                      // Message
                      Padding(
                        padding:
                        const EdgeInsets.fromLTRB(14, 11, 14, 0),
                        child: Text(d['message'] ?? '',
                            style: TextStyle(
                                fontSize: 13,
                                color: c.textGrey,
                                height: 1.5)),
                      ),

                      // Footer
                      Padding(
                        padding:
                        const EdgeInsets.fromLTRB(10, 8, 10, 10),
                        child: Row(children: [
                          Expanded(
                            child: Text(
                              d['createdAt'] != null
                                  ? 'Posted ${_fmtDate((d['createdAt'] as Timestamp).toDate())}'
                                  : '',
                              style: TextStyle(
                                  fontSize: 11, color: c.textGrey),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () => Navigator.push(context,
                                MaterialPageRoute(
                                    builder: (_) =>
                                        EditAnnouncementPage(doc: doc))),
                            icon: Icon(Icons.edit_rounded,
                                size: 15, color: c.blue),
                            label: Text('Edit',
                                style: TextStyle(
                                    fontSize: 13,
                                    color: c.blue,
                                    fontWeight: FontWeight.w700)),
                            style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                minimumSize: Size.zero,
                                tapTargetSize:
                                MaterialTapTargetSize.shrinkWrap),
                          ),
                          const SizedBox(width: 2),
                          TextButton.icon(
                            onPressed: () =>
                                _confirmDelete(context, doc.id),
                            icon: const Icon(Icons.delete_rounded,
                                size: 15, color: Color(0xFFDC2626)),
                            label: const Text('Delete',
                                style: TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFFDC2626),
                                    fontWeight: FontWeight.w700)),
                            style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                minimumSize: Size.zero,
                                tapTargetSize:
                                MaterialTapTargetSize.shrinkWrap),
                          ),
                        ]),
                      ),
                    ]),
              );
            },
          );
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  PAGE 3 – EditAnnouncementPage
// ═══════════════════════════════════════════════════════════════════
class EditAnnouncementPage extends StatefulWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  const EditAnnouncementPage({super.key, required this.doc});

  @override
  State<EditAnnouncementPage> createState() =>
      _EditAnnouncementPageState();
}

class _EditAnnouncementPageState extends State<EditAnnouncementPage> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _messageCtrl;
  late String _priority;
  bool _saving   = false;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    final d      = widget.doc.data();
    _titleCtrl   = TextEditingController(text: d['title']   ?? '');
    _messageCtrl = TextEditingController(text: d['message'] ?? '');
    _priority    = d['priority'] ?? 'medium';
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance
          .collection('announcements')
          .doc(widget.doc.id)
          .update({
        'title'    : _titleCtrl.text.trim(),
        'message'  : _messageCtrl.text.trim(),
        'priority' : _priority,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Announcement updated successfully',
            style: TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: const Color(0xFF059669),
        behavior: SnackBarBehavior.floating,
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      ));
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error: $e',
            style: const TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: const Color(0xFFDC2626),
        behavior: SnackBarBehavior.floating,
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      ));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _C.of(context);

    return Scaffold(
      backgroundColor: c.scaffold,
      appBar: AppBar(
        backgroundColor: c.blueDark,
        elevation: 0,
        title: const Text('Edit Announcement',
            style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.w700)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
        child: Column(children: [
          // Hero
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [c.blue, c.blueDark],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: const BorderRadius.only(
                bottomLeft:  Radius.circular(24),
                bottomRight: Radius.circular(24),
              ),
              boxShadow: [
                BoxShadow(
                    color: c.blue.withOpacity(0.35),
                    blurRadius: 20,
                    offset: const Offset(0, 10))
              ],
            ),
            child: Column(children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.18),
                    shape: BoxShape.circle),
                child: const Icon(Icons.edit_rounded,
                    size: 44, color: Colors.white),
              ),
              const SizedBox(height: 14),
              const Text('Edit Announcement',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text('Update and save your changes',
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.88),
                      fontSize: 13)),
            ]),
          ),
          const SizedBox(height: 22),

          Form(
            key: _formKey,
            child: Column(children: [
              _card(c, child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _lbl(c, Icons.title, 'Title'),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _titleCtrl,
                      style: TextStyle(
                          color: c.ink, fontWeight: FontWeight.w500),
                      decoration: _deco(c,
                          'e.g., Hostel Mess Timings Updated'),
                      validator: (v) => (v == null || v.isEmpty)
                          ? 'Please enter a title'
                          : null,
                    ),
                  ])),
              const SizedBox(height: 12),

              _card(c, child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _lbl(c, Icons.message, 'Message'),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _messageCtrl,
                      maxLines: 4,
                      style: TextStyle(
                          color: c.ink, fontWeight: FontWeight.w500),
                      decoration:
                      _deco(c, 'Enter announcement details...'),
                      validator: (v) => (v == null || v.isEmpty)
                          ? 'Please enter a message'
                          : null,
                    ),
                  ])),
              const SizedBox(height: 12),

              _card(c, child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _lbl(c, Icons.priority_high, 'Priority Level'),
                    const SizedBox(height: 14),
                    Row(children: [
                      _chip(c, 'high',   const Color(0xFFDC2626), 'High'),
                      const SizedBox(width: 10),
                      _chip(c, 'medium', const Color(0xFFD97706), 'Medium'),
                      const SizedBox(width: 10),
                      _chip(c, 'low',    const Color(0xFF059669), 'Low'),
                    ]),
                  ])),
              const SizedBox(height: 22),

              SizedBox(
                width: double.infinity, height: 50,
                child: GestureDetector(
                  onTap: _saving ? null : _save,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    decoration: BoxDecoration(
                      color: _saving ? c.blue.withOpacity(0.6) : c.blue,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: _saving
                        ? const SizedBox(
                        width: 22, height: 22,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2.5))
                        : const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.save_rounded,
                              color: Colors.white, size: 18),
                          SizedBox(width: 8),
                          Text('Save Changes',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white)),
                        ]),
                  ),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _card(_C c, {required Widget child}) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: c.surface,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: c.divider),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(c.dark ? 0.25 : 0.05),
          blurRadius: 8,
          offset: const Offset(0, 2),
        )
      ],
    ),
    child: child,
  );

  Widget _lbl(_C c, IconData icon, String text) => Row(children: [
    Icon(icon, color: c.blue, size: 18),
    const SizedBox(width: 8),
    Text(text,
        style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: c.blue)),
  ]);

  InputDecoration _deco(_C c, String hint) => InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(
        color: c.textGrey, fontWeight: FontWeight.w400, fontSize: 13),
    filled: true,
    fillColor: c.blueBg,
    contentPadding:
    const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
    border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide.none),
    enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: c.blueBorder)),
    focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: c.blue, width: 1.5)),
    errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFDC2626))),
    focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide:
        const BorderSide(color: Color(0xFFDC2626), width: 1.5)),
  );

  Widget _chip(_C c, String value, Color color, String label) {
    final sel = _priority == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _priority = value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: sel ? color : c.blueBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: sel ? color : c.blueBorder,
              width: sel ? 2 : 1,
            ),
          ),
          child: Center(
            child: Text(label,
                style: TextStyle(
                    color: sel ? Colors.white : c.textGrey,
                    fontWeight:
                    sel ? FontWeight.w700 : FontWeight.w500,
                    fontSize: 13)),
          ),
        ),
      ),
    );
  }
}