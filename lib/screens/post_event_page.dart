import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
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

// ─────────────────────────────────────────────────────────────────────────────
// NOTIFICATION DISPATCH HELPER
// ─────────────────────────────────────────────────────────────────────────────

Future<void> _dispatchEventNotification({
  required String title,
  required DateTime date,
  required String time,
  required String location,
}) async {
  final db = FirebaseFirestore.instance;

  // 1. Fetch all students
  final usersSnap = await db
      .collection('users')
      .where('role', isEqualTo: 'student')
      .get();

  if (usersSnap.docs.isEmpty) return;

  final formattedDate = DateFormat('d MMM yyyy').format(date);
  final body = '$formattedDate • $time • $location';

  final batch = db.batch();
  int writeCount = 0;

  for (final userDoc in usersSnap.docs) {
    final uid = userDoc.id;

    // Read per-user notification settings
    final settingsSnap = await db
        .collection('users')
        .doc(uid)
        .collection('settings')
        .doc('notifications')
        .get();

    final settings = settingsSnap.data() ?? {};

    final pushEnabled   = settings['push_notifications']  ?? true;
    final eventsEnabled = settings['event_notifications'] ?? true;

    if (!pushEnabled || !eventsEnabled) continue;

    // ✅ Read the student's FCM token from their user document.
    // The Cloud Function (sendItemNotification) also reads this directly,
    // but storing it here too gives a fallback and makes the notif doc
    // self-contained for debugging.
    final fcmToken = userDoc.data()?['fcmToken'] as String? ?? '';

    // Write notification document
    final notifRef = db
        .collection('notifications')
        .doc(uid)
        .collection('items')
        .doc(); // auto-ID

    batch.set(notifRef, {
      'type'     : 'event',
      'title'    : 'New Event: $title',
      'body'     : body,
      'time'     : FieldValue.serverTimestamp(),
      'read'     : false,
      'fcmToken' : fcmToken,
    });

    // ── FCM push trigger — root collection → Cloud Function fires ──
    await db.collection('notifications').add({
      'toUid'    : uid,
      'toToken'  : fcmToken,
      'title'    : 'New Event: $title',
      'body'     : body,
      'type'     : 'new_event',
      'createdAt': FieldValue.serverTimestamp(),
      'sent'     : false,
    });

    writeCount++;
    // Firestore batch limit is 500
    if (writeCount % 499 == 0) {
      await batch.commit();
    }
  }

  if (writeCount % 499 != 0) {
    await batch.commit();
  }
}

// ═══════════════════════════════════════════════════════════════════
//  PAGE 1 – PostEventPage
// ═══════════════════════════════════════════════════════════════════
class PostEventPage extends StatefulWidget {
  const PostEventPage({super.key});

  @override
  State<PostEventPage> createState() => _PostEventPageState();
}

class _PostEventPageState extends State<PostEventPage> {
  final _formKey      = GlobalKey<FormState>();
  final _titleCtrl    = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _timeCtrl     = TextEditingController();
  DateTime? _selectedDate;
  bool _saving = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _locationCtrl.dispose();
    _timeCtrl.dispose();
    super.dispose();
  }

  void _clearForm() {
    _titleCtrl.clear();
    _locationCtrl.clear();
    _timeCtrl.clear();
    setState(() => _selectedDate = null);
  }

  Future<void> _pickDate(BuildContext context) async {
    final c     = _C.of(context);
    final now   = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? today,
      firstDate:   today,
      lastDate:    DateTime(2100),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: Theme.of(ctx).colorScheme.copyWith(primary: c.blue),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _post() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Please select a date'),
        backgroundColor: Colors.orange,
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    setState(() => _saving = true);

    final title    = _titleCtrl.text.trim();
    final location = _locationCtrl.text.trim();
    final time     = _timeCtrl.text.trim();
    final date     = _selectedDate!;

    try {
      // 1. Save event to Firestore
      await FirebaseFirestore.instance.collection('events').add({
        'title'    : title,
        'date'     : Timestamp.fromDate(date),
        'time'     : time,
        'location' : location,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // 2. Dispatch notification to students who opted in
      await _dispatchEventNotification(
        title:    title,
        date:     date,
        time:     time,
        location: location,
      );

      _clearForm();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Event posted successfully'),
        backgroundColor: const Color(0xFF059669),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error: $e'),
        backgroundColor: const Color(0xFFDC2626),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
        title: const Text('Post Event',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const ViewEventsPage())),
            icon: const Icon(Icons.list_alt_rounded, color: Colors.white, size: 20),
            label: const Text('View',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
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
                  offset: const Offset(0, 10),
                )
              ],
            ),
            child: Column(children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.event, size: 44, color: Colors.white),
              ),
              const SizedBox(height: 14),
              const Text('Create Event',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text('Schedule hostel events for students',
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
                    _lbl(c, Icons.title, 'Event Title'),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _titleCtrl,
                      style: TextStyle(color: c.ink, fontWeight: FontWeight.w500),
                      decoration: _deco(c, 'e.g., Annual Sports Day'),
                      validator: (v) =>
                      (v == null || v.isEmpty) ? 'Please enter a title' : null,
                    ),
                  ])),
              const SizedBox(height: 12),

              // Date
              _card(c, child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _lbl(c, Icons.calendar_today_outlined, 'Event Date'),
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: () => _pickDate(context),
                      child: _pickerBox(
                        c: c,
                        icon: Icons.calendar_today_outlined,
                        value: _selectedDate != null
                            ? DateFormat('d MMM yyyy').format(_selectedDate!)
                            : 'Tap to choose',
                        filled: _selectedDate != null,
                      ),
                    ),
                  ])),
              const SizedBox(height: 12),

              // Time
              _card(c, child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _lbl(c, Icons.access_time_rounded, 'Time'),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _timeCtrl,
                      style: TextStyle(color: c.ink, fontWeight: FontWeight.w500),
                      decoration: _deco(c, 'e.g., 6:00 PM – 9:00 PM'),
                      validator: (v) =>
                      (v == null || v.isEmpty) ? 'Please enter time' : null,
                    ),
                  ])),
              const SizedBox(height: 12),

              // Location
              _card(c, child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _lbl(c, Icons.location_on_outlined, 'Location'),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _locationCtrl,
                      style: TextStyle(color: c.ink, fontWeight: FontWeight.w500),
                      decoration: _deco(c, 'e.g., Main Hall / Ground'),
                      validator: (v) =>
                      (v == null || v.isEmpty) ? 'Please enter location' : null,
                    ),
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
                          Text('Post Event',
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
    hintStyle: TextStyle(color: c.textGrey, fontWeight: FontWeight.w400, fontSize: 13),
    filled: true,
    fillColor: c.blueBg,
    contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
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
        borderSide: const BorderSide(color: Color(0xFFDC2626), width: 1.5)),
  );

  Widget _pickerBox({
    required _C c,
    required IconData icon,
    required String value,
    required bool filled,
  }) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 13),
        decoration: BoxDecoration(
          color: c.blueBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: filled ? c.blue.withOpacity(0.5) : c.blueBorder),
        ),
        child: Row(children: [
          Icon(icon, size: 16,
              color: filled ? c.blue : c.textGrey),
          const SizedBox(width: 10),
          Expanded(
            child: Text(value,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: filled ? FontWeight.w600 : FontWeight.w400,
                    color: filled ? c.blue : c.textGrey)),
          ),
          Icon(Icons.chevron_right_rounded, size: 18, color: c.textGrey),
        ]),
      );
}

// ═══════════════════════════════════════════════════════════════════
//  PAGE 2 – ViewEventsPage
// ═══════════════════════════════════════════════════════════════════
class ViewEventsPage extends StatelessWidget {
  const ViewEventsPage({super.key});

  String _fmtDate(DateTime d)    => DateFormat('d MMM yyyy').format(d);
  String _fmtCreated(DateTime d) => DateFormat('d MMM yyyy').format(d);

  Future<void> _confirmDelete(BuildContext context, String docId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final c = _C.of(ctx);
        return AlertDialog(
          backgroundColor: c.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: Text('Delete event?',
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: c.ink)),
          content: Text(
              'This will permanently remove the event from all student dashboards.',
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
          .collection('events')
          .doc(docId)
          .delete();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Event deleted'),
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
        title: const Text('Posted Events',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('events')
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (ctx, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator(color: c.blue));
          }
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}',
                style: const TextStyle(color: Color(0xFFDC2626))));
          }
          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) {
            return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.event_outlined, size: 60, color: c.blueBorder),
                const SizedBox(height: 12),
                Text('No events posted yet',
                    style: TextStyle(fontSize: 15, color: c.textGrey)),
              ]),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 32),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (ctx, i) {
              final doc     = docs[i];
              final d       = doc.data();
              final eventTs = d['date'] as Timestamp?;
              final isPast  = eventTs != null &&
                  DateTime.now().isAfter(eventTs.toDate());

              final accentColor = isPast ? c.textGrey : c.blue;

              return Opacity(
                opacity: isPast ? 0.65 : 1.0,
                child: Container(
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: c.divider),
                    boxShadow: isPast
                        ? []
                        : [
                      BoxShadow(
                        color: Colors.black.withOpacity(c.dark ? 0.25 : 0.05),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      )
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.fromLTRB(14, 13, 14, 11),
                        decoration: BoxDecoration(
                          color: isPast
                              ? c.divider.withOpacity(0.5)
                              : c.blueBg,
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(9)),
                        ),
                        child: Row(children: [
                          Container(
                              width: 9, height: 9,
                              decoration: BoxDecoration(
                                  color: accentColor,
                                  shape: BoxShape.circle)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(d['title'] ?? '',
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: isPast
                                        ? c.textGrey
                                        : c.ink)),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 9, vertical: 3),
                            decoration: BoxDecoration(
                              color: accentColor.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(isPast ? 'Past' : 'Upcoming',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: accentColor)),
                          ),
                        ]),
                      ),

                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (eventTs != null)
                              _detailRow(c,
                                  icon: Icons.calendar_today_outlined,
                                  text: _fmtDate(eventTs.toDate()),
                                  isPast: isPast),
                            if ((d['time'] as String?)?.isNotEmpty == true) ...[
                              const SizedBox(height: 6),
                              _detailRow(c,
                                  icon: Icons.access_time_rounded,
                                  text: d['time'],
                                  isPast: isPast),
                            ],
                            if ((d['location'] as String?)?.isNotEmpty == true) ...[
                              const SizedBox(height: 6),
                              _detailRow(c,
                                  icon: Icons.location_on_outlined,
                                  text: d['location'],
                                  isPast: isPast),
                            ],
                          ],
                        ),
                      ),

                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                        child: Row(children: [
                          Expanded(
                            child: Text(
                              d['createdAt'] != null
                                  ? 'Posted ${_fmtCreated((d['createdAt'] as Timestamp).toDate())}'
                                  : '',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: c.textGrey),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () => Navigator.push(context,
                                MaterialPageRoute(
                                    builder: (_) => EditEventPage(doc: doc))),
                            icon: Icon(Icons.edit_rounded, size: 15, color: c.blue),
                            label: Text('Edit',
                                style: TextStyle(
                                    fontSize: 13,
                                    color: c.blue,
                                    fontWeight: FontWeight.w700)),
                            style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                          ),
                          const SizedBox(width: 2),
                          TextButton.icon(
                            onPressed: () => _confirmDelete(context, doc.id),
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
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                          ),
                        ]),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _detailRow(_C c,
      {required IconData icon, required String text, required bool isPast}) =>
      Row(children: [
        Icon(icon, size: 13,
            color: isPast ? c.textGrey : c.blue),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text,
              style: TextStyle(
                  fontSize: 13,
                  color: isPast ? c.textGrey : c.ink,
                  fontWeight: FontWeight.w500)),
        ),
      ]);
}

// ═══════════════════════════════════════════════════════════════════
//  PAGE 3 – EditEventPage
// ═══════════════════════════════════════════════════════════════════
class EditEventPage extends StatefulWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  const EditEventPage({super.key, required this.doc});

  @override
  State<EditEventPage> createState() => _EditEventPageState();
}

class _EditEventPageState extends State<EditEventPage> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _locationCtrl;
  late final TextEditingController _timeCtrl;
  DateTime? _selectedDate;
  bool _saving   = false;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    final d       = widget.doc.data();
    _titleCtrl    = TextEditingController(text: d['title']    ?? '');
    _locationCtrl = TextEditingController(text: d['location'] ?? '');
    _timeCtrl     = TextEditingController(text: d['time']     ?? '');
    final ts      = d['date'] as Timestamp?;
    if (ts != null) _selectedDate = ts.toDate();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _locationCtrl.dispose();
    _timeCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate(BuildContext context) async {
    final c     = _C.of(context);
    final now   = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? today,
      firstDate:   today,
      lastDate:    DateTime(2100),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: Theme.of(ctx).colorScheme.copyWith(primary: c.blue),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Please select a date'),
        backgroundColor: Colors.orange,
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance
          .collection('events')
          .doc(widget.doc.id)
          .update({
        'title'    : _titleCtrl.text.trim(),
        'date'     : Timestamp.fromDate(_selectedDate!),
        'time'     : _timeCtrl.text.trim(),
        'location' : _locationCtrl.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Event updated successfully'),
        backgroundColor: const Color(0xFF059669),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error: $e'),
        backgroundColor: const Color(0xFFDC2626),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
        title: const Text('Edit Event',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
        child: Column(children: [
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
              const Text('Edit Event',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text('Update and save your changes',
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.88), fontSize: 13)),
            ]),
          ),
          const SizedBox(height: 22),

          Form(
            key: _formKey,
            child: Column(children: [
              _card(c, child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _lbl(c, Icons.title, 'Event Title'),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _titleCtrl,
                      style: TextStyle(color: c.ink, fontWeight: FontWeight.w500),
                      decoration: _deco(c, 'e.g., Annual Sports Day'),
                      validator: (v) =>
                      (v == null || v.isEmpty) ? 'Please enter a title' : null,
                    ),
                  ])),
              const SizedBox(height: 12),

              _card(c, child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _lbl(c, Icons.calendar_today_outlined, 'Event Date'),
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: () => _pickDate(context),
                      child: _pickerBox(
                        c: c,
                        icon: Icons.calendar_today_outlined,
                        value: _selectedDate != null
                            ? DateFormat('d MMM yyyy').format(_selectedDate!)
                            : 'Tap to choose',
                        filled: _selectedDate != null,
                      ),
                    ),
                  ])),
              const SizedBox(height: 12),

              _card(c, child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _lbl(c, Icons.access_time_rounded, 'Time'),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _timeCtrl,
                      style: TextStyle(color: c.ink, fontWeight: FontWeight.w500),
                      decoration: _deco(c, 'e.g., 6:00 PM – 9:00 PM'),
                      validator: (v) =>
                      (v == null || v.isEmpty) ? 'Please enter time' : null,
                    ),
                  ])),
              const SizedBox(height: 12),

              _card(c, child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _lbl(c, Icons.location_on_outlined, 'Location'),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _locationCtrl,
                      style: TextStyle(color: c.ink, fontWeight: FontWeight.w500),
                      decoration: _deco(c, 'e.g., Main Hall / Ground'),
                      validator: (v) =>
                      (v == null || v.isEmpty) ? 'Please enter location' : null,
                    ),
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
    hintStyle: TextStyle(color: c.textGrey, fontWeight: FontWeight.w400, fontSize: 13),
    filled: true,
    fillColor: c.blueBg,
    contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
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
        borderSide: const BorderSide(color: Color(0xFFDC2626), width: 1.5)),
  );

  Widget _pickerBox({
    required _C c,
    required IconData icon,
    required String value,
    required bool filled,
  }) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 13),
        decoration: BoxDecoration(
          color: c.blueBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: filled ? c.blue.withOpacity(0.5) : c.blueBorder),
        ),
        child: Row(children: [
          Icon(icon, size: 16, color: filled ? c.blue : c.textGrey),
          const SizedBox(width: 10),
          Expanded(
            child: Text(value,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: filled ? FontWeight.w600 : FontWeight.w400,
                    color: filled ? c.blue : c.textGrey)),
          ),
          Icon(Icons.chevron_right_rounded, size: 18, color: c.textGrey),
        ]),
      );
}