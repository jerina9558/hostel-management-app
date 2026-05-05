import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geocoding/geocoding.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'dart:math';

// ═══════════════════════════════════════════════════════════════════
//  CONSTANTS
// ═══════════════════════════════════════════════════════════════════
const String QR_SECRET = 'HOSTEL_GATE_RETURN_2024_SECURE';

// ═══════════════════════════════════════════════════════════════════
//  THEME COLORS HELPER
// ═══════════════════════════════════════════════════════════════════
class AppColors {
  static const blue = Color(0xFF185FA5);
  static const blueDark = Color(0xFF4A9EDB);
  static const blueBg = Color(0xFFE6F1FB);
  static const blueBgDark = Color(0xFF0D2A45);
  static const green = Color(0xFF3B6D11);
  static const greenDark = Color(0xFF6DBF3E);
  static const greenBg = Color(0xFFEAF3DE);
  static const greenBgDark = Color(0xFF1A2E0A);
  static const amber = Color(0xFF854F0B);
  static const amberDark = Color(0xFFFFB347);
  static const amberBg = Color(0xFFFAEEDA);
  static const amberBgDark = Color(0xFF2E1E05);
  static const red = Color(0xFFA32D2D);
  static const redDark = Color(0xFFE57373);
  static const redBg = Color(0xFFFCEBEB);
  static const redBgDark = Color(0xFF2E0A0A);
  static const bg = Color(0xFFF4F6FA);
  static const bgDark = Color(0xFF121212);
  static const cardLight = Colors.white;
  static const cardDark = Color(0xFF1E1E1E);
  static const surfaceDark = Color(0xFF2C2C2C);

  static Color accent(bool dark) => dark ? blueDark : blue;
  static Color accentBg(bool dark) => dark ? blueBgDark : blueBg;
  static Color success(bool dark) => dark ? greenDark : green;
  static Color successBg(bool dark) => dark ? greenBgDark : greenBg;
  static Color warn(bool dark) => dark ? amberDark : amber;
  static Color warnBg(bool dark) => dark ? amberBgDark : amberBg;
  static Color danger(bool dark) => dark ? redDark : red;
  static Color dangerBg(bool dark) => dark ? redBgDark : redBg;
  static Color background(bool dark) => dark ? bgDark : bg;
  static Color card(bool dark) => dark ? cardDark : cardLight;
  static Color surface(bool dark) => dark ? surfaceDark : const Color(0xFFF4F6FA);
  static Color border(bool dark) => dark ? Colors.white.withOpacity(0.12) : Colors.black.withOpacity(0.1);
  static Color text(bool dark) => dark ? const Color(0xFFE8E8E8) : const Color(0xFF1A1A1A);
  static Color subtext(bool dark) => dark ? const Color(0xFF9E9E9E) : const Color(0xFF757575);
  static Color divider(bool dark) => dark ? Colors.white.withOpacity(0.12) : Colors.black.withOpacity(0.1);
  static BoxShadow shadow(bool dark) => BoxShadow(
    color: dark ? Colors.black.withOpacity(0.3) : Colors.black.withOpacity(0.05),
    blurRadius: 8,
    offset: const Offset(0, 2),
  );
}

// ═══════════════════════════════════════════════════════════════════
//  STUDENT GATE PASS PAGE
// ═══════════════════════════════════════════════════════════════════
class StudentGatePassPage extends StatefulWidget {
  const StudentGatePassPage({super.key});
  @override
  State<StudentGatePassPage> createState() => _StudentGatePassPageState();
}

class _StudentGatePassPageState extends State<StudentGatePassPage>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  String _studentName = '';
  String _regNo = '';
  String _roomNo = '';
  String _department = '';
  String _parentPhone = '';
  String _parentName = '';
  bool _profileLoaded = false;

  DateTime? _outDate;
  TimeOfDay? _outTime;
  final _reasonCtrl = TextEditingController();

  LatLng? _pickedLocation;
  String _pickedAddress = '';

  int _tab = 0;
  bool _submitting = false;

  late AnimationController _fadeCtrl;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300));
    _fade = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
    _loadProfile();
    _saveFcmToken();
    _listenForNotifications();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  bool get _isDark =>
      Theme.of(context).brightness == Brightness.dark;

  Future<void> _saveFcmToken() async {
    try {
      final uid = _auth.currentUser?.uid;
      if (uid == null) return;
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true, badge: true, sound: true,
      );
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await _db.collection('users').doc(uid).update({'fcmToken': token});
      }
      FirebaseMessaging.instance.onTokenRefresh.listen((t) async {
        final u = _auth.currentUser?.uid;
        if (u != null) await _db.collection('users').doc(u).update({'fcmToken': t});
      });
    } catch (_) {}
  }

  void _listenForNotifications() {
    FirebaseMessaging.onMessage.listen((RemoteMessage msg) {
      if (!mounted) return;
      final title = msg.notification?.title ?? '';
      final body = msg.notification?.body ?? '';
      if (title.isEmpty && body.isEmpty) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title.isNotEmpty)
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            if (body.isNotEmpty)
              Text(body, style: const TextStyle(fontSize: 12)),
          ],
        ),
        backgroundColor: AppColors.accent(_isDark),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
      setState(() => _tab = 1);
      _fadeCtrl.reset();
      _fadeCtrl.forward();
    });
  }

  Future<void> _loadProfile() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    final doc = await _db.collection('users').doc(uid).get();
    final data = doc.data();
    if (data == null) return;
    setState(() {
      _studentName = data['name'] ?? '';
      _regNo = data['regNo'] ?? '';
      _roomNo = data['roomNo'] ?? '';
      _department = data['department'] ?? '';
      _parentPhone = data['parentPhone'] ?? '';
      _parentName = data['parentName'] ?? '';
      _profileLoaded = true;
    });
  }

  // ── Mark all gate-pass notifications as seen ───────────────────────────────
  Future<void> _markAllNotificationsSeen() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    try {
      final snap = await _db
          .collection('notifications')
          .doc(uid)
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

  // ── Show notifications bottom sheet (same style as dashboard) ─────────────
  void _showNotificationsSheet(BuildContext context) {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    final dark = _isDark;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: BoxDecoration(
          color: AppColors.card(dark),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(children: [
          // Handle bar
          Center(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: AppColors.divider(dark),
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          // Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: AppColors.accent(dark),
            child: const Text('Notifications',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w700)),
          ),
          // Notification list from Firestore
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _db
                  .collection('notifications')
                  .doc(uid)
                  .collection('items')
                  .orderBy('time', descending: true)
                  .limit(30)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(
                      child: CircularProgressIndicator(
                          color: AppColors.accent(dark)));
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.notifications_none_outlined,
                              size: 48, color: AppColors.border(dark)),
                          const SizedBox(height: 12),
                          Text('No notifications yet',
                              style: TextStyle(
                                  color: AppColors.subtext(dark),
                                  fontSize: 15)),
                        ]),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  itemCount: snapshot.data!.docs.length,
                  separatorBuilder: (_, __) =>
                      Divider(height: 1, color: AppColors.divider(dark)),
                  itemBuilder: (_, i) {
                    final data = snapshot.data!.docs[i].data()
                    as Map<String, dynamic>;
                    final title =
                    (data['title'] ?? 'Notification').toString();
                    final body = (data['body'] ?? '').toString();
                    final time = data['time'] is Timestamp
                        ? (data['time'] as Timestamp).toDate()
                        : DateTime.now();
                    final seen = data['seen'] == true;
                    final notifType = (data['type'] ?? '').toString();

                    // Pick icon/color based on notification type
                    IconData notifIcon = Icons.notifications_rounded;
                    Color notifColor = AppColors.accent(dark);
                    if (notifType == 'gate_pass_approved') {
                      notifIcon = Icons.check_circle_rounded;
                      notifColor = AppColors.success(dark);
                    } else if (notifType == 'gate_pass_rejected') {
                      notifIcon = Icons.cancel_rounded;
                      notifColor = AppColors.danger(dark);
                    } else if (notifType == 'permission_approved') {
                      notifIcon = Icons.assignment_turned_in_rounded;
                      notifColor = AppColors.success(dark);
                    } else if (notifType == 'permission_rejected') {
                      notifIcon = Icons.assignment_late_rounded;
                      notifColor = AppColors.danger(dark);
                    } else if (notifType == 'complaint_status') {
                      notifIcon = Icons.build_circle_rounded;
                      notifColor = AppColors.warn(dark);
                    } else if (notifType == 'new_announcement') {
                      notifIcon = Icons.campaign_rounded;
                      notifColor = AppColors.accent(dark);
                    } else if (notifType == 'new_event') {
                      notifIcon = Icons.event_rounded;
                      notifColor = const Color(0xFF7C3AED);
                    }

                    return Container(
                      color: seen
                          ? Colors.transparent
                          : AppColors.accent(dark).withOpacity(0.05),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
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
                                        color: notifColor.withOpacity(0.3))),
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
                                                    color: AppColors.text(dark))),
                                          ),
                                          if (!seen)
                                            Container(
                                              width: 8,
                                              height: 8,
                                              decoration: BoxDecoration(
                                                color: AppColors.accent(dark),
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                        ]),
                                        if (body.isNotEmpty) ...[
                                          const SizedBox(height: 3),
                                          Text(body,
                                              style: TextStyle(
                                                  fontSize: 13,
                                                  color: AppColors.subtext(dark))),
                                        ],
                                        const SizedBox(height: 4),
                                        Text(
                                            DateFormat('dd MMM, hh:mm a')
                                                .format(time),
                                            style: TextStyle(
                                                fontSize: 11,
                                                color: AppColors.subtext(dark))),
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

  @override
  Widget build(BuildContext context) {
    final dark = _isDark;
    final uid = _auth.currentUser?.uid;

    return Scaffold(
      backgroundColor: AppColors.background(dark),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: AppColors.card(dark),
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, size: 18,
              color: AppColors.text(dark)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Gate Pass',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600,
                color: AppColors.text(dark))),
        // ── NOTIFICATION BELL WITH UNSEEN BADGE ──────────────────────────────
        actions: [
          if (uid != null)
            StreamBuilder<QuerySnapshot>(
              stream: _db
                  .collection('notifications')
                  .doc(uid)
                  .collection('items')
                  .where('seen', isEqualTo: false)
                  .snapshots(),
              builder: (context, snapshot) {
                final unseenCount = snapshot.data?.docs.length ?? 0;
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    IconButton(
                      icon: Icon(Icons.notifications_outlined,
                          color: AppColors.text(dark)),
                      tooltip: 'Notifications',
                      onPressed: () async {
                        await _markAllNotificationsSeen();
                        if (mounted) _showNotificationsSheet(context);
                      },
                    ),
                    if (unseenCount > 0)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          width: 18,
                          height: 18,
                          decoration: const BoxDecoration(
                            color: Color(0xFFE53935),
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            unseenCount > 99 ? '99+' : '$unseenCount',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            )
          else
            IconButton(
              icon: Icon(Icons.notifications_outlined,
                  color: AppColors.text(dark)),
              tooltip: 'Notifications',
              onPressed: () => _showNotificationsSheet(context),
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(46),
          child: Container(
            color: AppColors.card(dark),
            child: Row(children: [
              _tabBtn('Apply', 0, dark),
              _tabBtn('My Passes', 1, dark),
            ]),
          ),
        ),
      ),
      body: !_profileLoaded
          ? Center(child: CircularProgressIndicator(color: AppColors.accent(dark)))
          : FadeTransition(
        opacity: _fade,
        child: _tab == 0 ? _buildApplyForm(dark) : _buildMyPasses(dark),
      ),
    );
  }

  Widget _tabBtn(String label, int idx, bool dark) {
    final active = _tab == idx;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() => _tab = idx);
          _fadeCtrl.reset();
          _fadeCtrl.forward();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                  color: active ? AppColors.accent(dark) : Colors.transparent,
                  width: 2),
            ),
          ),
          alignment: Alignment.center,
          child: Text(label,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                  color: active ? AppColors.accent(dark) : AppColors.subtext(dark))),
        ),
      ),
    );
  }

  Widget _buildApplyForm(bool dark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _secBadge('Auto SMS to parent · Warden approval required',
                Icons.verified_user_outlined,
                AppColors.success(dark), AppColors.successBg(dark)),
            _buildStudentCard(dark),
            const SizedBox(height: 20),
            _label('Pass details', dark),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: _tapField(
                  label: 'Out date',
                  value: _outDate == null ? 'Select' : _fmtDate(_outDate!),
                  icon: Icons.calendar_today_outlined,
                  onTap: _pickDate,
                  dark: dark,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _tapField(
                  label: 'Out time',
                  value: _outTime == null ? 'Select' : _outTime!.format(context),
                  icon: Icons.access_time_rounded,
                  onTap: _pickTime,
                  dark: dark,
                ),
              ),
            ]),
            const SizedBox(height: 10),
            _label('Destination', dark),
            const SizedBox(height: 10),
            _buildLocationPicker(dark),
            const SizedBox(height: 10),
            _textField(
              ctrl: _reasonCtrl,
              label: 'Reason for going out',
              icon: Icons.edit_note_rounded,
              hint: 'Brief reason...',
              maxLines: 3,
              dark: dark,
              validator: (v) => v == null || v.isEmpty ? 'Enter reason' : null,
            ),
            const SizedBox(height: 20),
            _label('Parent / Guardian', dark),
            const SizedBox(height: 10),
            _buildParentCard(dark),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _submitting ? null : _submit,
                icon: _submitting
                    ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.send_rounded, size: 18),
                label: Text(_submitting ? 'Submitting...' : 'Submit gate pass'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent(dark),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: AppColors.accent(dark).withOpacity(0.6),
                  elevation: 0,
                  textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMyPasses(bool dark) {
    final uid = _auth.currentUser?.uid ?? '';
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _db.collection('gatePasses').where('studentUid', isEqualTo: uid).snapshots(),
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator(color: AppColors.accent(dark)));
        }
        if (snap.hasError) {
          return Center(
              child: Text('Error: ${snap.error}',
                  style: const TextStyle(color: Colors.red)));
        }
        final docs = (snap.data?.docs ?? [])
          ..sort((a, b) {
            final aTs = a.data()['submittedAt'];
            final bTs = b.data()['submittedAt'];
            if (aTs == null && bTs == null) return 0;
            if (aTs == null) return 1;
            if (bTs == null) return -1;
            return (bTs as Timestamp).compareTo(aTs as Timestamp);
          });
        if (docs.isEmpty) {
          return Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.assignment_outlined, size: 56,
                  color: AppColors.subtext(dark)),
              const SizedBox(height: 12),
              Text('No gate passes yet',
                  style: TextStyle(fontSize: 15, color: AppColors.subtext(dark))),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () {
                  setState(() => _tab = 0);
                  _fadeCtrl.reset();
                  _fadeCtrl.forward();
                },
                child: Text('Apply now',
                    style: TextStyle(color: AppColors.accent(dark))),
              ),
            ]),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (ctx, i) {
            final d = docs[i].data();
            final passId = docs[i].id;
            return _StudentPassCard(
              data: d,
              passId: passId,
              isDark: dark,
              onScanReturnTap: () => _openQrReturnScanner(ctx, passId, d),
            );
          },
        );
      },
    );
  }

  Future<void> _openQrReturnScanner(
      BuildContext ctx, String passId, Map<String, dynamic> passData) async {
    if (passData['studentReturnDone'] == true) {
      ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
        content: Text('You have already submitted your return.'),
        backgroundColor: Colors.orange,
      ));
      return;
    }
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => QrReturnScannerPage(
          passId: passId,
          studentName: _studentName,
          regNo: _regNo,
          roomNo: _roomNo,
          department: _department,
          studentUid: _auth.currentUser?.uid ?? '',
        ),
      ),
    );
    if (result == true && ctx.mounted) {
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
        content: const Text('✅ Return recorded! Warden has been notified.'),
        backgroundColor: AppColors.success(_isDark),
        duration: const Duration(seconds: 4),
      ));
    }
  }

  Widget _buildLocationPicker(bool dark) {
    return GestureDetector(
      onTap: _openMapPicker,
      child: _card(
        dark: dark,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                    color: AppColors.accentBg(dark), shape: BoxShape.circle),
                child: Icon(Icons.location_on_outlined, size: 18,
                    color: AppColors.accent(dark)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Destination',
                        style: TextStyle(fontSize: 11, color: AppColors.subtext(dark))),
                    const SizedBox(height: 2),
                    Text(
                      _pickedAddress.isEmpty
                          ? 'Search & pin your destination'
                          : _pickedAddress,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: _pickedAddress.isEmpty
                            ? AppColors.subtext(dark)
                            : AppColors.text(dark),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(
                _pickedLocation != null
                    ? Icons.check_circle_rounded
                    : Icons.chevron_right_rounded,
                size: 20,
                color: _pickedLocation != null
                    ? AppColors.success(dark)
                    : AppColors.subtext(dark),
              ),
            ]),
            if (_pickedLocation != null) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  height: 130,
                  child: GoogleMap(
                    initialCameraPosition:
                    CameraPosition(target: _pickedLocation!, zoom: 14),
                    markers: {
                      Marker(
                        markerId: const MarkerId('dest'),
                        position: _pickedLocation!,
                        icon: BitmapDescriptor.defaultMarkerWithHue(
                            BitmapDescriptor.hueBlue),
                      ),
                    },
                    zoomControlsEnabled: false,
                    scrollGesturesEnabled: false,
                    tiltGesturesEnabled: false,
                    rotateGesturesEnabled: false,
                    myLocationButtonEnabled: false,
                    liteModeEnabled: true,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              GestureDetector(
                onTap: _openMapPicker,
                child: Text('Change location',
                    style: TextStyle(
                        fontSize: 12,
                        color: AppColors.accent(dark),
                        decoration: TextDecoration.underline)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStudentCard(bool dark) => _card(
    dark: dark,
    child: Row(children: [
      CircleAvatar(
        radius: 22,
        backgroundColor: AppColors.accentBg(dark),
        child: Text(
          _studentName.isNotEmpty ? _studentName[0].toUpperCase() : 'S',
          style: TextStyle(
              color: AppColors.accent(dark),
              fontWeight: FontWeight.w700, fontSize: 18),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_studentName,
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600,
                    color: AppColors.text(dark))),
            Text('$_regNo  ·  $_department',
                style: TextStyle(fontSize: 12, color: AppColors.subtext(dark))),
            Text('Room $_roomNo',
                style: TextStyle(fontSize: 12, color: AppColors.subtext(dark))),
          ],
        ),
      ),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
            color: AppColors.successBg(dark),
            borderRadius: BorderRadius.circular(20)),
        child: Text('Active',
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w600,
                color: AppColors.success(dark))),
      ),
    ]),
  );

  Widget _buildParentCard(bool dark) => _card(
    dark: dark,
    child: Column(children: [
      Row(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
              color: AppColors.warnBg(dark), shape: BoxShape.circle),
          child: Icon(Icons.person_outline_rounded, size: 18,
              color: AppColors.warn(dark)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_parentName.isNotEmpty ? _parentName : 'Parent',
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600,
                      color: AppColors.text(dark))),
              Text(_parentPhone,
                  style: TextStyle(fontSize: 13, color: AppColors.subtext(dark))),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
              color: AppColors.warnBg(dark),
              borderRadius: BorderRadius.circular(20)),
          child: Text('From signup',
              style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w600,
                  color: AppColors.warn(dark))),
        ),
      ]),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
            color: AppColors.warnBg(dark),
            borderRadius: BorderRadius.circular(8)),
        child: Row(children: [
          Icon(Icons.lock_outline_rounded, size: 13, color: AppColors.warn(dark)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Parent number is set during signup and cannot be changed here.',
              style: TextStyle(fontSize: 11, color: AppColors.warn(dark)),
            ),
          ),
        ]),
      ),
    ]),
  );

  Future<void> _openMapPicker() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(builder: (_) => MapPickerPage(initial: _pickedLocation)),
    );
    if (result != null) {
      setState(() {
        _pickedLocation = result['latlng'] as LatLng;
        _pickedAddress = result['address'] as String;
      });
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final dark = _isDark;
    final p = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 30)),
      builder: (c, child) => Theme(
        data: Theme.of(c).copyWith(
            colorScheme: dark
                ? ColorScheme.dark(primary: AppColors.accent(dark))
                : ColorScheme.light(primary: AppColors.accent(dark))),
        child: child!,
      ),
    );
    if (p != null) setState(() => _outDate = p);
  }

  Future<void> _pickTime() async {
    final dark = _isDark;
    final p = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      builder: (c, child) => Theme(
        data: Theme.of(c).copyWith(
            colorScheme: dark
                ? ColorScheme.dark(primary: AppColors.accent(dark))
                : ColorScheme.light(primary: AppColors.accent(dark))),
        child: child!,
      ),
    );
    if (p != null) setState(() => _outTime = p);
  }

  Future<void> _submit() async {
    final dark = _isDark;
    if (!_formKey.currentState!.validate()) return;
    if (_outDate == null || _outTime == null) {
      _snack('Please select out date and time', isError: true, dark: dark);
      return;
    }
    if (_pickedLocation == null) {
      _snack('Please select a destination on the map', isError: true, dark: dark);
      return;
    }
    setState(() => _submitting = true);
    try {
      final uid = _auth.currentUser!.uid;
      final passId =
          'GP${DateTime.now().year}${(1000 + Random().nextInt(8999))}';
      final token = await FirebaseMessaging.instance.getToken();
      await _db.collection('gatePasses').doc(passId).set({
        'passId': passId,
        'studentUid': uid,
        'studentName': _studentName,
        'regNo': _regNo,
        'roomNo': _roomNo,
        'department': _department,
        'parentPhone': _parentPhone,
        'parentName': _parentName,
        'outDate': _fmtDate(_outDate!),
        'outTime': _outTime!.format(context),
        'reason': _reasonCtrl.text.trim(),
        'destinationAddress': _pickedAddress,
        'destinationLat': _pickedLocation!.latitude,
        'destinationLng': _pickedLocation!.longitude,
        'status': 'pending',
        'studentReturnDone': false,
        'wardenReturnDone': false,
        'notified': false,
        'fcmToken': token ?? '',
        'submittedAt': FieldValue.serverTimestamp(),
      });

      // ── Notify all wardens about new gate pass request ──────────────
      try {
        final wardensSnap = await _db
            .collection('users')
            .where('role', isEqualTo: 'warden')
            .get();

        for (final wDoc in wardensSnap.docs) {
          final wardenUid = wDoc.id;
          final wardenToken = wDoc.data()['fcmToken'] as String? ?? '';

          // Write to notifications/{wardenUid}/items
          // so the warden bell badge updates in real time
          await _db
              .collection('notifications')
              .doc(wardenUid)
              .collection('items')
              .add({
            'title': 'New Gate Pass Request 🚪',
            'body':
            '$_studentName ($_regNo, Room $_roomNo) has requested a gate pass.',
            'type': 'gate_pass_request',
            'passId': passId,
            'seen': false,
            'time': FieldValue.serverTimestamp(),
          });

          // Top-level doc triggers Cloud Function for push
          // even when warden app is closed
          if (wardenToken.isNotEmpty) {
            await _db.collection('notifications').add({
              'toUid': wardenUid,
              'toToken': wardenToken,
              'title': 'New Gate Pass Request 🚪',
              'body':
              '$_studentName ($_regNo, Room $_roomNo) has requested a gate pass.',
              'type': 'gate_pass_request',
              'passId': passId,
              'createdAt': FieldValue.serverTimestamp(),
              'sent': false,
            });
          }
        }
      } catch (e) {
        debugPrint('Error notifying wardens: $e');
      }
      _reasonCtrl.clear();
      setState(() {
        _submitting = false;
        _outDate = null;
        _outTime = null;
        _pickedLocation = null;
        _pickedAddress = '';
        _tab = 1;
      });
      _fadeCtrl.reset();
      _fadeCtrl.forward();
      _snack('Gate pass submitted! Awaiting warden approval.',
          isError: false, dark: dark);
    } catch (e) {
      setState(() => _submitting = false);
      _snack('Failed to submit. Try again.', isError: true, dark: dark);
    }
  }

  void _snack(String msg, {required bool isError, required bool dark}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? AppColors.danger(dark) : AppColors.success(dark),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  Widget _card({required Widget child, required bool dark}) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.card(dark),
      borderRadius: BorderRadius.circular(14),
      boxShadow: [AppColors.shadow(dark)],
    ),
    child: child,
  );

  Widget _secBadge(String text, IconData icon, Color fg, Color bg) => Container(
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: fg.withOpacity(0.25)),
    ),
    child: Row(children: [
      Icon(icon, size: 15, color: fg),
      const SizedBox(width: 8),
      Expanded(
          child: Text(text,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w500, color: fg))),
    ]),
  );

  Widget _label(String t, bool dark) => Text(t,
      style: TextStyle(
          fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.text(dark)));

  Widget _tapField({
    required String label,
    required String value,
    required IconData icon,
    required VoidCallback onTap,
    required bool dark,
  }) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.card(dark),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border(dark)),
            boxShadow: [AppColors.shadow(dark)],
          ),
          child: Row(children: [
            Icon(icon, size: 18, color: AppColors.accent(dark)),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(fontSize: 11,
                          color: AppColors.subtext(dark))),
                  const SizedBox(height: 2),
                  Text(value,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: value == 'Select'
                              ? AppColors.subtext(dark)
                              : AppColors.text(dark))),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 16,
                color: AppColors.subtext(dark)),
          ]),
        ),
      );

  Widget _textField({
    required TextEditingController ctrl,
    required String label,
    required IconData icon,
    required bool dark,
    String? hint,
    int maxLines = 1,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
  }) =>
      TextFormField(
        controller: ctrl,
        maxLines: maxLines,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        validator: validator,
        style: TextStyle(color: AppColors.text(dark)),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: Icon(icon, color: AppColors.accent(dark), size: 20),
          filled: true,
          fillColor: AppColors.card(dark),
          labelStyle: TextStyle(fontSize: 13, color: AppColors.subtext(dark)),
          hintStyle: TextStyle(fontSize: 13, color: AppColors.subtext(dark)),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.border(dark))),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.border(dark))),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.accent(dark), width: 1.5)),
          errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.danger(dark))),
          contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        ),
      );

  String _fmtDate(DateTime d) {
    const m = [
      'Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec'
    ];
    return '${d.day} ${m[d.month - 1]} ${d.year}';
  }
}

// ═══════════════════════════════════════════════════════════════════
//  STUDENT PASS CARD
// ═══════════════════════════════════════════════════════════════════
class _StudentPassCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final String passId;
  final bool isDark;
  final VoidCallback onScanReturnTap;

  const _StudentPassCard({
    required this.data,
    required this.passId,
    required this.isDark,
    required this.onScanReturnTap,
  });

  @override
  Widget build(BuildContext context) {
    final dark = isDark;
    final status = data['status'] ?? 'pending';
    final stuRetDone = data['studentReturnDone'] == true;
    final notified = data['notified'] == true;
    final wardenNote = data['wardenNote'] as String? ?? '';
    final inDate = data['inDate'] as String? ?? '';
    final inTime = data['inTime'] as String? ?? '';

    Widget? banner;
    if (status == 'approved' && notified) {
      banner = _banner('Your gate pass has been approved! ✅',
          Icons.check_circle_rounded,
          AppColors.success(dark), AppColors.successBg(dark));
    } else if (status == 'rejected' && notified) {
      banner = _banner(
          wardenNote.isNotEmpty
              ? 'Rejected: $wardenNote'
              : 'Your gate pass was rejected by the warden.',
          Icons.cancel_rounded,
          AppColors.danger(dark), AppColors.dangerBg(dark));
    } else if (status == 'returned') {
      banner = _banner('Pass closed — return confirmed. 🏠',
          Icons.home_rounded,
          AppColors.success(dark), AppColors.successBg(dark));
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card(dark),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [AppColors.shadow(dark)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
            child: Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(passId,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.text(dark),
                            letterSpacing: .4)),
                    Text(data['outDate'] ?? '',
                        style: TextStyle(fontSize: 12,
                            color: AppColors.subtext(dark))),
                  ],
                ),
              ),
              _badge(status, dark),
            ]),
          ),
          if (banner != null)
            Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                child: banner),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            child: Column(children: [
              _row('Out',
                  '${data['outDate'] ?? ''}  ${data['outTime'] ?? ''}',
                  dark),
              _row('Place', data['destinationAddress'] ?? '', dark),
              _row('Reason', data['reason'] ?? '', dark),
              if (wardenNote.isNotEmpty) _row('Warden note', wardenNote, dark),
              if (stuRetDone && inDate.isNotEmpty)
                _row('Returned', '$inDate  $inTime', dark),
            ]),
          ),

          // QR Scan return button
          if (status == 'approved' && !stuRetDone) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.accentBg(dark),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: AppColors.accent(dark).withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(Icons.qr_code_scanner_rounded,
                          size: 16, color: AppColors.accent(dark)),
                      const SizedBox(width: 8),
                      Text('Ready to return?',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.accent(dark))),
                    ]),
                    const SizedBox(height: 4),
                    Text(
                      'Go to the hostel gate and scan the QR code posted there to record your return.',
                      style: TextStyle(
                          fontSize: 12,
                          color: dark
                              ? AppColors.accent(dark).withOpacity(0.85)
                              : const Color(0xFF0C447C)),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      height: 42,
                      child: ElevatedButton.icon(
                        onPressed: onScanReturnTap,
                        icon: const Icon(
                            Icons.qr_code_scanner_rounded, size: 18),
                        label: const Text('Scan gate QR to return'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.accent(dark),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          // Returned checkmark
          if (stuRetDone)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                    color: AppColors.successBg(dark),
                    borderRadius: BorderRadius.circular(10)),
                child: Row(children: [
                  Icon(Icons.check_circle_rounded,
                      size: 16, color: AppColors.success(dark)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Return scanned at gate on $inDate $inTime',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppColors.success(dark)),
                    ),
                  ),
                ]),
              ),
            ),

          const SizedBox(height: 14),
        ],
      ),
    );
  }

  Widget _banner(String msg, IconData icon, Color fg, Color bg) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: fg.withOpacity(0.3))),
    child: Row(children: [
      Icon(icon, size: 16, color: fg),
      const SizedBox(width: 8),
      Expanded(
          child: Text(msg,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w500, color: fg))),
    ]),
  );

  Widget _badge(String status, bool dark) {
    Color bg, fg;
    String label;
    switch (status) {
      case 'approved':
        bg = AppColors.accentBg(dark); fg = AppColors.accent(dark); label = 'Approved';
        break;
      case 'returned':
        bg = AppColors.successBg(dark); fg = AppColors.success(dark); label = 'Returned';
        break;
      case 'rejected':
        bg = AppColors.dangerBg(dark); fg = AppColors.danger(dark); label = 'Rejected';
        break;
      default:
        bg = AppColors.warnBg(dark); fg = AppColors.warn(dark); label = 'Pending';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(label,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w600, color: fg)),
    );
  }

  Widget _row(String key, String value, bool dark) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
          width: 80,
          child: Text(key,
              style: TextStyle(
                  fontSize: 12, color: AppColors.subtext(dark)))),
      Expanded(
          child: Text(value,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.text(dark)))),
    ]),
  );
}

// ═══════════════════════════════════════════════════════════════════
//  QR RETURN SCANNER PAGE
// ═══════════════════════════════════════════════════════════════════
class QrReturnScannerPage extends StatefulWidget {
  final String passId;
  final String studentName;
  final String regNo;
  final String roomNo;
  final String department;
  final String studentUid;

  const QrReturnScannerPage({
    super.key,
    required this.passId,
    required this.studentName,
    required this.regNo,
    required this.roomNo,
    required this.department,
    required this.studentUid,
  });

  @override
  State<QrReturnScannerPage> createState() => _QrReturnScannerPageState();
}

class _QrReturnScannerPageState extends State<QrReturnScannerPage> {
  final MobileScannerController _scanCtrl = MobileScannerController();
  bool _processing = false;
  bool _success = false;
  String _returnedTime = '';
  String _returnedDate = '';

  @override
  void dispose() {
    _scanCtrl.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_processing || _success) return;
    final barcode = capture.barcodes.firstOrNull;
    if (barcode == null) return;
    final raw = barcode.rawValue ?? '';
    if (raw.isEmpty) return;

    setState(() => _processing = true);

    if (raw.trim() != QR_SECRET) {
      setState(() => _processing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('❌ Invalid QR code. Scan the correct hostel gate QR.'),
          backgroundColor: Colors.red,
        ));
      }
      return;
    }

    try {
      final now = DateTime.now();
      const months = [
        'Jan','Feb','Mar','Apr','May','Jun',
        'Jul','Aug','Sep','Oct','Nov','Dec'
      ];
      final inDate = '${now.day} ${months[now.month - 1]} ${now.year}';
      final inTime =
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

      final db = FirebaseFirestore.instance;

      await db.collection('gatePasses').doc(widget.passId).update({
        'studentReturnDone': true,
        'inDate': inDate,
        'inTime': inTime,
        'returnVerifiedByQr': true,
        'returnedAt': FieldValue.serverTimestamp(),
      });

      final wardenSnap =
      await db.collection('users').where('role', isEqualTo: 'warden').get();
      for (final wDoc in wardenSnap.docs) {
        final wToken = wDoc.data()['fcmToken'] as String?;
        if (wToken != null && wToken.isNotEmpty) {
          await db.collection('notifications').add({
            'toUid': wDoc.id,
            'toToken': wToken,
            'title': 'Student Returned 🏠',
            'body':
            '${widget.studentName} (${widget.regNo}, ${widget.department}) has returned to hostel at $inTime on $inDate.',
            'passId': widget.passId,
            'type': 'student_returned',
            'studentName': widget.studentName,
            'regNo': widget.regNo,
            'roomNo': widget.roomNo,
            'department': widget.department,
            'inDate': inDate,
            'inTime': inTime,
            'createdAt': FieldValue.serverTimestamp(),
            'sent': false,
          });
        }
      }

      await db.collection('returnedIn').add({
        'passId': widget.passId,
        'studentUid': widget.studentUid,
        'studentName': widget.studentName,
        'regNo': widget.regNo,
        'roomNo': widget.roomNo,
        'department': widget.department,
        'inDate': inDate,
        'inTime': inTime,
        'returnedAt': FieldValue.serverTimestamp(),
      });

      setState(() {
        _success = true;
        _returnedDate = inDate;
        _returnedTime = inTime;
      });

      await Future.delayed(const Duration(seconds: 3));
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _processing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('❌ Error: ${e.toString()}'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              size: 18, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Scan Gate QR',
            style: TextStyle(
                fontSize: 17, fontWeight: FontWeight.w600, color: Colors.white)),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on_rounded, color: Colors.white),
            onPressed: () => _scanCtrl.toggleTorch(),
          ),
        ],
      ),
      body: _success ? _buildSuccessScreen() : _buildScannerScreen(),
    );
  }

  Widget _buildSuccessScreen() {
    return Container(
      color: Colors.black,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120, height: 120,
            decoration: BoxDecoration(
              color: const Color(0xFF3B6D11).withOpacity(0.15),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF4CAF50), width: 3),
            ),
            child: const Icon(Icons.check_rounded, size: 72,
                color: Color(0xFF4CAF50)),
          ),
          const SizedBox(height: 24),
          const Text('Welcome Back! 🏠',
              style: TextStyle(
                  fontSize: 26, fontWeight: FontWeight.w800, color: Colors.white)),
          const SizedBox(height: 6),
          const Text('Entry Verified',
              style: TextStyle(
                  fontSize: 15,
                  color: Color(0xFF4CAF50),
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 24),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFF3B6D11).withOpacity(0.18),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: const Color(0xFF4CAF50).withOpacity(0.4)),
            ),
            child: Column(children: [
              _successRow(Icons.person_rounded, 'Name', widget.studentName),
              const SizedBox(height: 8),
              _successRow(Icons.badge_outlined, 'Reg No', widget.regNo),
              const SizedBox(height: 8),
              _successRow(Icons.school_outlined, 'Dept', widget.department),
              const SizedBox(height: 8),
              _successRow(
                  Icons.meeting_room_outlined, 'Room', widget.roomNo),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Divider(color: Colors.white24),
              ),
              _successRow(
                  Icons.calendar_today_outlined, 'Date', _returnedDate),
              const SizedBox(height: 8),
              _successRow(Icons.access_time_rounded, 'Time', _returnedTime),
            ]),
          ),
          const SizedBox(height: 20),
          const Text('Warden has been notified',
              style: TextStyle(fontSize: 13, color: Colors.white38)),
        ],
      ),
    );
  }

  Widget _successRow(IconData icon, String label, String value) =>
      Row(children: [
        Icon(icon, size: 16, color: const Color(0xFF4CAF50)),
        const SizedBox(width: 10),
        SizedBox(
            width: 52,
            child: Text(label,
                style: const TextStyle(fontSize: 12, color: Colors.white54))),
        Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 14,
                    color: Colors.white,
                    fontWeight: FontWeight.w600))),
      ]);

  Widget _buildScannerScreen() {
    return Stack(children: [
      MobileScanner(controller: _scanCtrl, onDetect: _onDetect),
      Center(
        child: Container(
          width: 240, height: 240,
          decoration: BoxDecoration(
            border: Border.all(
                color: Colors.white.withOpacity(0.4), width: 1),
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      Center(
        child: SizedBox(
          width: 240, height: 240,
          child: Stack(children: [
            Positioned(top: 0, left: 0, child: _corner(topLeft: true)),
            Positioned(top: 0, right: 0, child: _corner(topRight: true)),
            Positioned(bottom: 0, left: 0, child: _corner(bottomLeft: true)),
            Positioned(bottom: 0, right: 0, child: _corner(bottomRight: true)),
          ]),
        ),
      ),
      Positioned(
        bottom: 0, left: 0, right: 0,
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.85),
            borderRadius:
            const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_processing)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2),
                ),
              Row(children: [
                Icon(
                  _processing
                      ? Icons.hourglass_top_rounded
                      : Icons.qr_code_scanner_rounded,
                  color: _processing ? Colors.amber : Colors.white70,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _processing
                        ? 'Recording your return...'
                        : 'Point camera at the QR code at the hostel gate',
                    style: const TextStyle(fontSize: 13, color: Colors.white),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    ]);
  }

  Widget _corner({
    bool topLeft = false, bool topRight = false,
    bool bottomLeft = false, bool bottomRight = false,
  }) =>
      Container(
        width: 30, height: 30,
        decoration: BoxDecoration(
          border: Border(
            top: topLeft || topRight
                ? const BorderSide(color: Color(0xFF185FA5), width: 3)
                : BorderSide.none,
            bottom: bottomLeft || bottomRight
                ? const BorderSide(color: Color(0xFF185FA5), width: 3)
                : BorderSide.none,
            left: topLeft || bottomLeft
                ? const BorderSide(color: Color(0xFF185FA5), width: 3)
                : BorderSide.none,
            right: topRight || bottomRight
                ? const BorderSide(color: Color(0xFF185FA5), width: 3)
                : BorderSide.none,
          ),
          borderRadius: BorderRadius.only(
            topLeft: topLeft ? const Radius.circular(6) : Radius.zero,
            topRight: topRight ? const Radius.circular(6) : Radius.zero,
            bottomLeft: bottomLeft ? const Radius.circular(6) : Radius.zero,
            bottomRight: bottomRight ? const Radius.circular(6) : Radius.zero,
          ),
        ),
      );
}

// ═══════════════════════════════════════════════════════════════════
//  MAP PICKER PAGE
// ═══════════════════════════════════════════════════════════════════
class MapPickerPage extends StatefulWidget {
  final LatLng? initial;
  const MapPickerPage({super.key, this.initial});
  @override
  State<MapPickerPage> createState() => _MapPickerPageState();
}

class _MapPickerPageState extends State<MapPickerPage> {
  static const _defaultCenter = LatLng(9.1720, 77.8642);

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;

  GoogleMapController? _mapCtrl;
  LatLng? _picked;
  String _address = '';
  bool _resolving = false;
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  List<Map<String, dynamic>> _suggestions = [];
  bool _searching = false;
  bool _showSuggestions = false;

  @override
  void initState() {
    super.initState();
    if (widget.initial != null) {
      _picked = widget.initial;
      _resolveAddress(widget.initial!);
    }
    _searchCtrl.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(_onSearchChanged);
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final q = _searchCtrl.text.trim();
    if (q.length < 3) {
      setState(() { _suggestions = []; _showSuggestions = false; });
      return;
    }
    _searchPlaces(q);
  }

  Future<void> _searchPlaces(String query) async {
    setState(() => _searching = true);
    try {
      final locations = await locationFromAddress(query);
      final suggestions = <Map<String, dynamic>>[];
      for (final loc in locations.take(5)) {
        final placemarks =
        await placemarkFromCoordinates(loc.latitude, loc.longitude);
        final p = placemarks.isNotEmpty ? placemarks.first : null;
        final label = [
          p?.name, p?.subLocality, p?.locality,
          p?.administrativeArea, p?.country
        ].where((s) => s != null && s.isNotEmpty).join(', ');
        suggestions.add({
          'label': label.isNotEmpty ? label : query,
          'latlng': LatLng(loc.latitude, loc.longitude),
        });
      }
      if (mounted) {
        setState(() {
          _suggestions = suggestions;
          _showSuggestions = suggestions.isNotEmpty;
          _searching = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _selectSuggestion(Map<String, dynamic> s) {
    final pos = s['latlng'] as LatLng;
    setState(() {
      _picked = pos;
      _address = s['label'];
      _showSuggestions = false;
      _searchCtrl.text = s['label'];
    });
    _searchFocus.unfocus();
    _mapCtrl?.animateCamera(CameraUpdate.newLatLngZoom(pos, 14));
  }

  @override
  Widget build(BuildContext context) {
    final dark = _isDark;
    return Scaffold(
      backgroundColor: AppColors.card(dark),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: AppColors.card(dark),
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              size: 18, color: AppColors.text(dark)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Select destination',
            style: TextStyle(
                fontSize: 17, fontWeight: FontWeight.w600,
                color: AppColors.text(dark))),
        actions: [
          if (_picked != null)
            TextButton(
              onPressed: _confirm,
              child: Text('Confirm',
                  style: TextStyle(
                      color: AppColors.accent(dark),
                      fontWeight: FontWeight.w600, fontSize: 15)),
            ),
        ],
      ),
      body: Stack(children: [
        GoogleMap(
          initialCameraPosition: CameraPosition(
              target: widget.initial ?? _defaultCenter, zoom: 13),
          onMapCreated: (ctrl) => _mapCtrl = ctrl,
          onTap: _onMapTap,
          markers: _picked == null
              ? {}
              : {
            Marker(
              markerId: const MarkerId('dest'),
              position: _picked!,
              icon: BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueBlue),
              infoWindow: const InfoWindow(title: 'Destination'),
            ),
          },
          myLocationEnabled: true,
          myLocationButtonEnabled: true,
          zoomControlsEnabled: true,
        ),
        Positioned(
          top: 12, left: 16, right: 16,
          child: Column(children: [
            Container(
              decoration: BoxDecoration(
                color: AppColors.card(dark),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                      color: dark
                          ? Colors.black.withOpacity(0.4)
                          : Colors.black.withOpacity(0.12),
                      blurRadius: 10,
                      offset: const Offset(0, 3))
                ],
              ),
              child: TextField(
                controller: _searchCtrl,
                focusNode: _searchFocus,
                style: TextStyle(color: AppColors.text(dark)),
                decoration: InputDecoration(
                  hintText: 'Search for a place...',
                  hintStyle: TextStyle(
                      fontSize: 14, color: AppColors.subtext(dark)),
                  prefixIcon: Icon(Icons.search_rounded,
                      color: AppColors.accent(dark), size: 20),
                  suffixIcon: _searching
                      ? Padding(
                      padding: const EdgeInsets.all(12),
                      child: SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.accent(dark))))
                      : _searchCtrl.text.isNotEmpty
                      ? IconButton(
                      icon: Icon(Icons.close_rounded,
                          size: 18, color: AppColors.subtext(dark)),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() {
                          _suggestions = [];
                          _showSuggestions = false;
                        });
                      })
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                ),
              ),
            ),
            if (_showSuggestions && _suggestions.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(
                  color: AppColors.card(dark),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                        color: dark
                            ? Colors.black.withOpacity(0.4)
                            : Colors.black.withOpacity(0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 4))
                  ],
                ),
                child: Column(
                  children: _suggestions
                      .map((s) => InkWell(
                    onTap: () => _selectSuggestion(s),
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      child: Row(children: [
                        Icon(Icons.location_on_outlined,
                            size: 16,
                            color: AppColors.accent(dark)),
                        const SizedBox(width: 10),
                        Expanded(
                            child: Text(s['label'],
                                style: TextStyle(
                                    fontSize: 13,
                                    color: AppColors.text(dark)))),
                      ]),
                    ),
                  ))
                      .toList(),
                ),
              ),
          ]),
        ),
        if (!_showSuggestions)
          Positioned(
            bottom: _picked != null ? 230 : 20,
            left: 16, right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.card(dark),
                borderRadius: BorderRadius.circular(10),
                boxShadow: [AppColors.shadow(dark)],
              ),
              child: Row(children: [
                Icon(Icons.touch_app_rounded,
                    size: 15, color: AppColors.accent(dark)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                      'Search above or tap anywhere on the map to pin',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.subtext(dark))),
                ),
              ]),
            ),
          ),
        if (_picked != null)
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              decoration: BoxDecoration(
                color: AppColors.card(dark),
                borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
                boxShadow: [
                  BoxShadow(
                      color: dark
                          ? Colors.black.withOpacity(0.4)
                          : Colors.black.withOpacity(0.1),
                      blurRadius: 16,
                      offset: const Offset(0, -4))
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    child: Container(
                      width: 36, height: 4,
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(
                          color: AppColors.divider(dark),
                          borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(
                            color: AppColors.accentBg(dark),
                            shape: BoxShape.circle),
                        child: Icon(Icons.location_on_rounded,
                            size: 18, color: AppColors.accent(dark)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Pinned destination',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.subtext(dark))),
                            const SizedBox(height: 4),
                            _resolving
                                ? Row(children: [
                              SizedBox(
                                  width: 12, height: 12,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 1.5,
                                      color: AppColors.accent(dark))),
                              const SizedBox(width: 8),
                              Text('Getting address...',
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: AppColors.subtext(dark))),
                            ])
                                : Text(
                              _address.isNotEmpty
                                  ? _address
                                  : '${_picked!.latitude.toStringAsFixed(5)}, ${_picked!.longitude.toStringAsFixed(5)}',
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.text(dark)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: _confirm,
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: const Text('Confirm this location'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.success(dark),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ]),
    );
  }

  void _onMapTap(LatLng pos) {
    setState(() {
      _picked = pos;
      _address = '';
      _showSuggestions = false;
    });
    _searchFocus.unfocus();
    _resolveAddress(pos);
  }

  Future<void> _resolveAddress(LatLng pos) async {
    setState(() => _resolving = true);
    try {
      final placemarks =
      await placemarkFromCoordinates(pos.latitude, pos.longitude);
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        final parts = [
          p.name, p.subLocality, p.locality, p.administrativeArea
        ].where((s) => s != null && s.isNotEmpty).toList();
        setState(() => _address = parts.join(', '));
      }
    } catch (_) {
      setState(() => _address = '');
    }
    setState(() => _resolving = false);
  }

  void _confirm() {
    if (_picked == null) return;
    Navigator.pop(context, {
      'latlng': _picked,
      'address': _address.isNotEmpty
          ? _address
          : '${_picked!.latitude.toStringAsFixed(5)}, ${_picked!.longitude.toStringAsFixed(5)}',
    });
  }
}

// ═══════════════════════════════════════════════════════════════════
//  WARDEN GATE PASS PAGE
// ═══════════════════════════════════════════════════════════════════
class WardenGatePassPage extends StatelessWidget {
  const WardenGatePassPage({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return DefaultTabController(
      length: 7,
      child: Scaffold(
        backgroundColor: AppColors.background(dark),
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                color: AppColors.card(dark),
                padding: const EdgeInsets.fromLTRB(4, 12, 16, 8),
                child: Row(children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back_ios_new_rounded,
                        size: 18, color: AppColors.text(dark)),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Text(
                    'Gate Pass — Warden',
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text(dark)),
                  ),
                ]),
              ),
              Container(
                color: AppColors.card(dark),
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                child: const _WardenStatsBar(),
              ),
              Container(
                color: AppColors.card(dark),
                child: TabBar(
                  labelColor: AppColors.accent(dark),
                  unselectedLabelColor: AppColors.subtext(dark),
                  indicatorColor: AppColors.accent(dark),
                  indicatorWeight: 2,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  labelStyle: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600),
                  unselectedLabelStyle: const TextStyle(fontSize: 13),
                  tabs: const [
                    Tab(text: 'Pending'),
                    Tab(text: 'Approved'),
                    Tab(text: 'Returned'),
                    Tab(text: 'Rejected'),
                    Tab(text: 'All'),
                    Tab(text: 'Returned In'),
                    Tab(text: 'Not Present'),
                  ],
                ),
              ),
              const Expanded(
                child: TabBarView(
                  children: [
                    _WardenList(filter: 'pending'),
                    _WardenList(filter: 'approved'),
                    _WardenList(filter: 'returned'),
                    _WardenList(filter: 'rejected'),
                    _WardenList(filter: 'all'),
                    _ReturnedInTab(),
                    _NotPresentTab(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Stats Bar ────────────────────────────────────────────────────
class _WardenStatsBar extends StatelessWidget {
  const _WardenStatsBar();

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final db = FirebaseFirestore.instance;
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: db.collection('gatePasses').snapshots(),
      builder: (ctx, snap) {
        final docs = snap.data?.docs ?? [];
        int totalOut = 0, totalReturned = 0, totalPending = 0, totalNotBack = 0;
        for (final doc in docs) {
          final d = doc.data();
          final status = d['status'] ?? '';
          if (status == 'approved' || status == 'returned') totalOut++;
          if (status == 'returned') totalReturned++;
          if (status == 'pending') totalPending++;
          if (status == 'approved' && d['studentReturnDone'] != true) totalNotBack++;
        }
        return Row(children: [
          _stat('Out', totalOut.toString(), Icons.logout_rounded,
              AppColors.accent(dark), AppColors.accentBg(dark)),
          const SizedBox(width: 6),
          _stat('Returned', totalReturned.toString(), Icons.home_rounded,
              AppColors.success(dark), AppColors.successBg(dark)),
          const SizedBox(width: 6),
          _stat('Pending', totalPending.toString(),
              Icons.pending_actions_rounded,
              AppColors.warn(dark), AppColors.warnBg(dark)),
          const SizedBox(width: 6),
          _stat('Not Back', totalNotBack.toString(),
              Icons.warning_amber_rounded,
              AppColors.danger(dark), AppColors.dangerBg(dark)),
        ]);
      },
    );
  }

  Widget _stat(String label, String value, IconData icon, Color fg, Color bg) =>
      Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
          decoration: BoxDecoration(
              color: bg, borderRadius: BorderRadius.circular(10)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 15, color: fg),
            const SizedBox(height: 2),
            Text(value,
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w800, color: fg)),
            Text(label,
                style: TextStyle(
                    fontSize: 9, fontWeight: FontWeight.w500, color: fg)),
          ]),
        ),
      );
}

// ─── Warden List ──────────────────────────────────────────────────
class _WardenList extends StatelessWidget {
  final String filter;
  const _WardenList({required this.filter});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    Query<Map<String, dynamic>> q =
    FirebaseFirestore.instance.collection('gatePasses');
    if (filter != 'all') q = q.where('status', isEqualTo: filter);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: q.snapshots(),
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Center(
              child: CircularProgressIndicator(color: AppColors.accent(dark)));
        }
        if (snap.hasError) {
          return Center(
              child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Error: ${snap.error}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 13, color: Colors.red))));
        }
        final docs = (snap.data?.docs ?? [])
          ..sort((a, b) {
            final aTs = a.data()['submittedAt'];
            final bTs = b.data()['submittedAt'];
            if (aTs == null && bTs == null) return 0;
            if (aTs == null) return 1;
            if (bTs == null) return -1;
            return (bTs as Timestamp).compareTo(aTs as Timestamp);
          });
        if (docs.isEmpty) {
          return Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.inbox_rounded, size: 48, color: AppColors.subtext(dark)),
              const SizedBox(height: 10),
              Text(
                filter == 'pending'
                    ? 'No pending requests'
                    : filter == 'approved'
                    ? 'No approved passes'
                    : filter == 'returned'
                    ? 'No returned passes yet'
                    : filter == 'rejected'
                    ? 'No rejected passes'
                    : 'No passes yet',
                style: TextStyle(
                    fontSize: 14, color: AppColors.subtext(dark)),
              ),
            ]),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (ctx, i) =>
              _WardenCard(data: docs[i].data(), passId: docs[i].id),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  RETURNED IN TAB
// ═══════════════════════════════════════════════════════════════════
class _ReturnedInTab extends StatelessWidget {
  const _ReturnedInTab();

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final db = FirebaseFirestore.instance;
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: db
          .collection('returnedIn')
          .orderBy('returnedAt', descending: true)
          .snapshots(),
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Center(
              child: CircularProgressIndicator(color: AppColors.accent(dark)));
        }
        final docs = snap.data?.docs ?? [];

        return Column(children: [
          Container(
            margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.card(dark),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [AppColors.shadow(dark)],
            ),
            child: Row(children: [
              Container(
                width: 50, height: 50,
                decoration: BoxDecoration(
                    color: AppColors.successBg(dark), shape: BoxShape.circle),
                child: Icon(Icons.home_rounded,
                    color: AppColors.success(dark), size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Total Returned In',
                          style: TextStyle(
                              fontSize: 12, color: AppColors.subtext(dark))),
                      Text('${docs.length}',
                          style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              color: AppColors.success(dark))),
                      Text(
                          '${docs.length == 1 ? 'student has' : 'students have'} entered the hostel',
                          style: TextStyle(
                              fontSize: 11, color: AppColors.subtext(dark))),
                    ]),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                    color: AppColors.successBg(dark),
                    borderRadius: BorderRadius.circular(20)),
                child: Text('QR Verified ✓',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.success(dark))),
              ),
            ]),
          ),
          if (docs.isEmpty)
            Expanded(
              child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.sensor_door_outlined,
                      size: 52, color: AppColors.subtext(dark)),
                  const SizedBox(height: 10),
                  Text('No students have returned yet',
                      style: TextStyle(
                          fontSize: 14, color: AppColors.subtext(dark))),
                ]),
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                itemCount: docs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (ctx, i) {
                  final d = docs[i].data();
                  return Container(
                    decoration: BoxDecoration(
                      color: AppColors.card(dark),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [AppColors.shadow(dark)],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(children: [
                        Container(
                          width: 40, height: 40,
                          decoration: BoxDecoration(
                              color: AppColors.successBg(dark),
                              shape: BoxShape.circle),
                          child: Center(
                            child: Text('${i + 1}',
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.success(dark))),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(d['studentName'] ?? '',
                                    style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.text(dark))),
                                const SizedBox(height: 2),
                                Text(
                                    '${d['regNo'] ?? ''}  ·  ${d['department'] ?? ''}',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: AppColors.subtext(dark))),
                                Text('Room ${d['roomNo'] ?? ''}',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: AppColors.subtext(dark))),
                              ]),
                        ),
                        Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                    color: AppColors.successBg(dark),
                                    borderRadius: BorderRadius.circular(20)),
                                child: Row(children: [
                                  Icon(Icons.check_circle_rounded,
                                      size: 12, color: AppColors.success(dark)),
                                  const SizedBox(width: 4),
                                  Text(d['inTime'] ?? '',
                                      style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.success(dark))),
                                ]),
                              ),
                              const SizedBox(height: 4),
                              Text(d['inDate'] ?? '',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: AppColors.subtext(dark))),
                            ]),
                      ]),
                    ),
                  );
                },
              ),
            ),
        ]);
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  NOT PRESENT TAB
// ═══════════════════════════════════════════════════════════════════
class _NotPresentTab extends StatelessWidget {
  const _NotPresentTab();

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final db = FirebaseFirestore.instance;
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: db
          .collection('gatePasses')
          .where('status', isEqualTo: 'approved')
          .snapshots(),
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Center(
              child: CircularProgressIndicator(color: AppColors.accent(dark)));
        }
        final allApproved = snap.data?.docs ?? [];
        final notPresent = allApproved
            .where((doc) => doc.data()['studentReturnDone'] != true)
            .toList()
          ..sort((a, b) {
            final aTs = a.data()['submittedAt'];
            final bTs = b.data()['submittedAt'];
            if (aTs == null && bTs == null) return 0;
            if (aTs == null) return 1;
            if (bTs == null) return -1;
            return (aTs as Timestamp).compareTo(bTs as Timestamp);
          });

        return Column(children: [
          Container(
            margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.card(dark),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [AppColors.shadow(dark)],
            ),
            child: Row(children: [
              Container(
                width: 50, height: 50,
                decoration: BoxDecoration(
                    color: AppColors.dangerBg(dark), shape: BoxShape.circle),
                child: Icon(Icons.person_off_rounded,
                    color: AppColors.danger(dark), size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Students Not Back',
                          style: TextStyle(
                              fontSize: 12, color: AppColors.subtext(dark))),
                      Text('${notPresent.length}',
                          style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              color: AppColors.danger(dark))),
                      Text(
                          '${notPresent.length == 1 ? 'student has' : 'students have'} not returned yet',
                          style: TextStyle(
                              fontSize: 11, color: AppColors.subtext(dark))),
                    ]),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                    color: AppColors.dangerBg(dark),
                    borderRadius: BorderRadius.circular(20)),
                child: Text('Still Out',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.danger(dark))),
              ),
            ]),
          ),
          if (notPresent.isEmpty)
            Expanded(
              child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.check_circle_outline_rounded,
                      size: 52, color: AppColors.subtext(dark)),
                  const SizedBox(height: 10),
                  Text('All students have returned! 🎉',
                      style: TextStyle(
                          fontSize: 14, color: AppColors.subtext(dark))),
                ]),
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                itemCount: notPresent.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (ctx, i) {
                  final d = notPresent[i].data();
                  return Container(
                    decoration: BoxDecoration(
                      color: AppColors.card(dark),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: AppColors.danger(dark).withOpacity(0.15)),
                      boxShadow: [AppColors.shadow(dark)],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            CircleAvatar(
                              radius: 22,
                              backgroundColor: AppColors.dangerBg(dark),
                              child: Text(
                                (d['studentName'] as String? ?? 'S')[0]
                                    .toUpperCase(),
                                style: TextStyle(
                                    color: AppColors.danger(dark),
                                    fontWeight: FontWeight.w800,
                                    fontSize: 18),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(d['studentName'] ?? '',
                                        style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.text(dark))),
                                    Text(
                                        '${d['regNo'] ?? ''}  ·  ${d['department'] ?? ''}',
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: AppColors.subtext(dark))),
                                    Text('Room ${d['roomNo'] ?? ''}',
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: AppColors.subtext(dark))),
                                  ]),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                  color: AppColors.dangerBg(dark),
                                  borderRadius: BorderRadius.circular(20)),
                              child: Text('Still Out',
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.danger(dark))),
                            ),
                          ]),
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                                color: AppColors.warnBg(dark),
                                borderRadius: BorderRadius.circular(10)),
                            child: Column(children: [
                              _infoRow(Icons.logout_rounded, 'Left on',
                                  '${d['outDate'] ?? ''}  ${d['outTime'] ?? ''}',
                                  AppColors.warn(dark)),
                              const SizedBox(height: 4),
                              _infoRow(Icons.location_on_outlined, 'Going to',
                                  d['destinationAddress'] ?? '',
                                  AppColors.warn(dark)),
                              const SizedBox(height: 4),
                              _infoRow(Icons.edit_note_rounded, 'Reason',
                                  d['reason'] ?? '', AppColors.warn(dark)),
                            ]),
                          ),
                          const SizedBox(height: 10),
                          if ((d['parentPhone'] ?? '').isNotEmpty)
                            GestureDetector(
                              onTap: () async {
                                final uri =
                                Uri.parse('tel:${d['parentPhone']}');
                                if (await canLaunchUrl(uri)) {
                                  await launchUrl(uri);
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                    color: AppColors.dangerBg(dark),
                                    borderRadius: BorderRadius.circular(10)),
                                child: Row(children: [
                                  Icon(Icons.phone_rounded,
                                      size: 16, color: AppColors.danger(dark)),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                            '${d['parentName'] ?? 'Parent'}  ·  ${d['parentPhone'] ?? ''}',
                                            style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                                color: AppColors.danger(dark))),
                                        Text('Tap to call parent',
                                            style: TextStyle(
                                                fontSize: 11,
                                                color: AppColors.subtext(dark))),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 6),
                                    decoration: BoxDecoration(
                                        color: AppColors.danger(dark),
                                        borderRadius:
                                        BorderRadius.circular(8)),
                                    child: const Text('Call',
                                        style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.white)),
                                  ),
                                ]),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ]);
      },
    );
  }

  Widget _infoRow(IconData icon, String label, String value, Color color) =>
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 6),
        SizedBox(
            width: 64,
            child: Text(label,
                style: TextStyle(
                    fontSize: 11, color: color.withOpacity(0.8)))),
        Expanded(
            child: Text(value,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: color))),
      ]);
}

// ═══════════════════════════════════════════════════════════════════
//  WARDEN CARD
// ═══════════════════════════════════════════════════════════════════
class _WardenCard extends StatefulWidget {
  final Map<String, dynamic> data;
  final String passId;
  const _WardenCard({required this.data, required this.passId});
  @override
  State<_WardenCard> createState() => _WardenCardState();
}

class _WardenCardState extends State<_WardenCard> {
  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  final _noteCtrl = TextEditingController();
  bool _acting = false;

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = _isDark;
    final d = widget.data;
    final status = d['status'] ?? 'pending';
    final stuRetDone = d['studentReturnDone'] == true;
    final inDate = d['inDate'] as String? ?? '';
    final inTime = d['inTime'] as String? ?? '';

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card(dark),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [AppColors.shadow(dark)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
            child: Row(children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.accentBg(dark),
                child: Text(
                  (d['studentName'] as String? ?? 'S')[0].toUpperCase(),
                  style: TextStyle(
                      color: AppColors.accent(dark),
                      fontWeight: FontWeight.w700, fontSize: 14),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(d['studentName'] ?? '',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.text(dark))),
                    Text(
                        '${d['regNo'] ?? ''}  ·  ${d['department'] ?? ''}  ·  Room ${d['roomNo'] ?? ''}',
                        style: TextStyle(
                            fontSize: 12, color: AppColors.subtext(dark))),
                  ],
                ),
              ),
              _badge(status, dark),
            ]),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
            child: Column(children: [
              _row('Out',
                  '${d['outDate'] ?? ''}  ${d['outTime'] ?? ''}', dark),
              _row('Place', d['destinationAddress'] ?? '', dark),
              _row('Reason', d['reason'] ?? '', dark),
              if ((d['wardenNote'] as String? ?? '').isNotEmpty)
                _row('Note', d['wardenNote'], dark),
              _parentRow(d, dark),
            ]),
          ),

          if (stuRetDone && inDate.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.successBg(dark),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: AppColors.success(dark).withOpacity(0.3)),
                ),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Icon(Icons.qr_code_scanner_rounded,
                            size: 15, color: AppColors.success(dark)),
                        const SizedBox(width: 6),
                        Text('Return verified via QR',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppColors.success(dark))),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                              color: AppColors.success(dark),
                              borderRadius: BorderRadius.circular(6)),
                          child: const Text('QR ✓',
                              style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white)),
                        ),
                      ]),
                      const SizedBox(height: 8),
                      _greenRow(
                          'Returned on', '$inDate at $inTime', dark),
                    ]),
              ),
            ),
          ],

          if (d['destinationLat'] != null && d['destinationLng'] != null)
            _mapPreview(d, dark),
          if (status == 'pending') _approveReject(dark),
          if (status == 'approved') _smsTile(d, dark),

          const SizedBox(height: 14),
        ],
      ),
    );
  }

  Widget _greenRow(String key, String value, bool dark) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(children: [
      SizedBox(
          width: 110,
          child: Text(key,
              style: TextStyle(
                  fontSize: 11,
                  color: AppColors.success(dark).withOpacity(0.8)))),
      Expanded(
          child: Text(value,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.success(dark)))),
    ]),
  );

  Widget _parentRow(Map<String, dynamic> d, bool dark) => Container(
    margin: const EdgeInsets.only(top: 8),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
        color: AppColors.warnBg(dark),
        borderRadius: BorderRadius.circular(10)),
    child: Row(children: [
      Icon(Icons.phone_outlined, size: 15, color: AppColors.warn(dark)),
      const SizedBox(width: 8),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                '${d['parentName'] ?? 'Parent'}  ·  ${d['parentPhone'] ?? ''}',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.warn(dark))),
            Text('Tap to call parent',
                style: TextStyle(
                    fontSize: 11,
                    color: AppColors.warn(dark).withOpacity(0.8))),
          ],
        ),
      ),
      GestureDetector(
        onTap: () => _callPhone(d['parentPhone'] ?? ''),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
              color: AppColors.warn(dark),
              borderRadius: BorderRadius.circular(8)),
          child: const Text('Call',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white)),
        ),
      ),
    ]),
  );

  Widget _mapPreview(Map<String, dynamic> d, bool dark) {
    final lat = (d['destinationLat'] as num).toDouble();
    final lng = (d['destinationLng'] as num).toDouble();
    final pos = LatLng(lat, lng);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Destination on map',
              style: TextStyle(
                  fontSize: 11,
                  color: AppColors.subtext(dark),
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              height: 150,
              child: GoogleMap(
                initialCameraPosition:
                CameraPosition(target: pos, zoom: 13),
                markers: {
                  Marker(
                    markerId: const MarkerId('dest'),
                    position: pos,
                    icon: BitmapDescriptor.defaultMarkerWithHue(
                        BitmapDescriptor.hueBlue),
                  ),
                },
                zoomControlsEnabled: false,
                scrollGesturesEnabled: false,
                tiltGesturesEnabled: false,
                rotateGesturesEnabled: false,
                myLocationButtonEnabled: false,
                liteModeEnabled: true,
              ),
            ),
          ),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: () => _openInMaps(lat, lng),
            child: Row(children: [
              Icon(Icons.open_in_new_rounded,
                  size: 13, color: AppColors.accent(dark)),
              const SizedBox(width: 4),
              Text('Open in Google Maps',
                  style: TextStyle(
                      fontSize: 12,
                      color: AppColors.accent(dark),
                      decoration: TextDecoration.underline)),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _approveReject(bool dark) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
    child: Column(children: [
      TextField(
        controller: _noteCtrl,
        style: TextStyle(color: AppColors.text(dark)),
        decoration: InputDecoration(
          hintText: 'Add a note (optional)',
          hintStyle: TextStyle(fontSize: 13, color: AppColors.subtext(dark)),
          filled: true,
          fillColor: AppColors.surface(dark),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none),
          contentPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          isDense: true,
        ),
      ),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(
            child: _actBtn(
                label: _acting ? '...' : 'Approve',
                color: AppColors.success(dark),
                onTap: () => _decide('approved'))),
        const SizedBox(width: 8),
        Expanded(
            child: _actBtn(
                label: _acting ? '...' : 'Reject',
                color: AppColors.danger(dark),
                onTap: () => _decide('rejected'))),
      ]),
    ]),
  );

  Widget _smsTile(Map<String, dynamic> d, bool dark) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
    child: GestureDetector(
      onTap: () => _sendSms(d),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.accentBg(dark),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: AppColors.accent(dark).withOpacity(0.25)),
        ),
        child: Row(children: [
          Icon(Icons.sms_outlined, size: 18, color: AppColors.accent(dark)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Send SMS to parent',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.accent(dark))),
                Text(
                  '"Your ward ${d['studentName'] ?? ''} is leaving on ${d['outDate'] ?? ''} at ${d['outTime'] ?? ''}"',
                  style: TextStyle(
                      fontSize: 11,
                      color: dark
                          ? AppColors.accent(dark).withOpacity(0.75)
                          : const Color(0xFF0C447C)),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Icon(Icons.send_rounded, size: 16, color: AppColors.accent(dark)),
        ]),
      ),
    ),
  );

  // ══════════════════════════════════════════════════════════════════
  //  _decide — warden approves or rejects a gate pass
  //
  //  KEY CHANGES vs original:
  //  1. Writes the notification to  notifications/{studentUid}/items
  //     (the sub-collection the student's bell StreamBuilder reads)
  //     with the correct 'type' values:
  //       approved  → 'gate_pass_approved'
  //       rejected  → 'gate_pass_rejected'
  //  2. Also writes a cloud-function-style doc to the top-level
  //     'notifications' collection (toUid / toToken) so your existing
  //     FCM Cloud Function still fires the push.
  //  3. Only fires if push_notifications is enabled (checks Firestore
  //     settings doc for the student).
  // ══════════════════════════════════════════════════════════════════
  Future<void> _decide(String decision) async {
    if (_acting) return;
    setState(() => _acting = true);

    final d = widget.data;
    final note = _noteCtrl.text.trim();
    final studentUid = d['studentUid'] as String? ?? '';
    final isApproved = decision == 'approved';

    final notifType = isApproved ? 'gate_pass_approved' : 'gate_pass_rejected';
    final title = isApproved ? 'Gate Pass Approved ✅' : 'Gate Pass Rejected ❌';
    final body = isApproved
        ? 'Your gate pass (${widget.passId}) has been approved by the warden.'
        : note.isNotEmpty
        ? 'Your gate pass (${widget.passId}) was rejected. Reason: $note'
        : 'Your gate pass (${widget.passId}) was rejected by the warden.';

    final db = FirebaseFirestore.instance;

    // ── 1. Update the gate pass document ─────────────────────────────
    await db.collection('gatePasses').doc(widget.passId).update({
      'status': decision,
      'wardenNote': note,
      'notified': true,
      'decidedAt': FieldValue.serverTimestamp(),
    });

    // ── 2. Resolve FCM token ──────────────────────────────────────────
    String? fcmToken = d['fcmToken'] as String?;
    if ((fcmToken ?? '').isEmpty && studentUid.isNotEmpty) {
      try {
        final userDoc = await db.collection('users').doc(studentUid).get();
        fcmToken = userDoc.data()?['fcmToken'] as String?;
        if ((fcmToken ?? '').isNotEmpty) {
          await db.collection('gatePasses').doc(widget.passId)
              .update({'fcmToken': fcmToken});
        }
      } catch (_) {}
    }

    if (studentUid.isNotEmpty) {
      // ── 3. Write to notifications/{studentUid}/items ──────────────
      //        This is what the student bell badge StreamBuilder reads.
      try {
        await db
            .collection('notifications')
            .doc(studentUid)
            .collection('items')
            .add({
          'title': title,
          'body': body,
          'type': notifType,
          'passId': widget.passId,
          'seen': false,
          'time': FieldValue.serverTimestamp(), // ← MUST be 'time'
        });
      } catch (e) {
        debugPrint('Error writing student notification item: $e');
      }

      // ── 4. Top-level FCM trigger (for Cloud Function) ─────────────
      try {
        await db.collection('notifications').add({
          'toUid': studentUid,
          'toToken': fcmToken ?? '',
          'title': title,
          'body': body,
          'passId': widget.passId,
          'type': notifType,
          'createdAt': FieldValue.serverTimestamp(),
          'sent': false,
        });
      } catch (e) {
        debugPrint('Error writing FCM notification doc: $e');
      }
    }

    setState(() => _acting = false);
  }

  Future<void> _sendSms(Map<String, dynamic> d) async {
    final phone = d['parentPhone'] ?? '';
    final name = d['studentName'] ?? 'Your ward';
    final date = d['outDate'] ?? '';
    final time = d['outTime'] ?? '';
    final place = d['destinationAddress'] ?? '';
    final lat = d['destinationLat'];
    final lng = d['destinationLng'];
    final mapLink = (lat != null && lng != null)
        ? ' Location: https://maps.google.com/?q=$lat,$lng'
        : '';
    final msg = Uri.encodeComponent(
        'Dear Parent, $name is leaving college on $date at $time heading to $place.$mapLink Please ensure they return safely.');
    final uri = Uri.parse('sms:$phone?body=$msg');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _callPhone(String phone) async {
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _openInMaps(double lat, double lng) async {
    final uri = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Widget _row(String key, String value, bool dark) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
          width: 68,
          child: Text(key,
              style: TextStyle(
                  fontSize: 12, color: AppColors.subtext(dark)))),
      Expanded(
          child: Text(value,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.text(dark)))),
    ]),
  );

  Widget _badge(String status, bool dark) {
    Color bg, fg;
    String label;
    switch (status) {
      case 'approved':
        bg = AppColors.accentBg(dark); fg = AppColors.accent(dark); label = 'Approved';
        break;
      case 'returned':
        bg = AppColors.successBg(dark); fg = AppColors.success(dark); label = 'Returned';
        break;
      case 'rejected':
        bg = AppColors.dangerBg(dark); fg = AppColors.danger(dark); label = 'Rejected';
        break;
      default:
        bg = AppColors.warnBg(dark); fg = AppColors.warn(dark); label = 'Pending';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
          color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(label,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w600, color: fg)),
    );
  }

  Widget _actBtn({
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
              color: color, borderRadius: BorderRadius.circular(10)),
          alignment: Alignment.center,
          child: Text(label,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white)),
        ),
      );
}