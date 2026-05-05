import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;



class MessMenuScheduler {
  static final MessMenuScheduler instance = MessMenuScheduler._();
  MessMenuScheduler._();

  final _notifs = FlutterLocalNotificationsPlugin();

  // 13 slots: 9 PM, 10 PM, 11 PM, midnight, 1 AM … 8 AM, 9 AM
  static const _baseId = 42;
  static const _count  = 13;

  static const _notifDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      'mess_menu_ch',
      'Mess Menu Reminders',
      channelDescription: 'Hourly non-veg booking reminders (9 PM – 9 AM)',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    ),
  );

  /// Schedule hourly reminders from 9 PM tonight to 9 AM tomorrow.
  /// Slots already in the past are automatically skipped.
  Future<void> scheduleHourlyReminders(Map<String, dynamic> data) async {
    await cancel(); // always clear old slots first

    final items = (data['nonVegItems'] as List?)?.join(', ') ?? '';
    final body  = items.isNotEmpty
        ? 'Non-veg available tomorrow: $items — book before 9 AM!'
        : 'Non-veg is available tomorrow — book before 9 AM!';

    final now       = tz.TZDateTime.now(tz.local);
    final fireTimes = _buildFireTimes(now);

    for (int i = 0; i < fireTimes.length; i++) {
      final fireAt = fireTimes[i];
      if (fireAt.isBefore(now)) continue; // skip past slots

      try {
        await _notifs.zonedSchedule(
          _baseId + i,
          '🍗 Non-Veg Tomorrow – Book Now',
          body,
          fireAt,
          _notifDetails,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
        );
        debugPrint('[MessMenuScheduler] Slot $i scheduled at $fireAt');
      } catch (e) {
        debugPrint('[MessMenuScheduler] Slot $i error: $e');
      }
    }
  }

  /// Builds the 13 fire times: today 21:00, 22:00 … tomorrow 09:00.
  List<tz.TZDateTime> _buildFireTimes(tz.TZDateTime now) {
    final base = tz.TZDateTime(
      tz.local, now.year, now.month, now.day, 21, 0, 0,
    );
    return List.generate(_count, (i) => base.add(Duration(hours: i)));
  }

  /// Cancel all 13 reserved notification slots.
  Future<void> cancel() async {
    for (int i = 0; i < _count; i++) {
      try {
        await _notifs.cancel(_baseId + i);
      } catch (_) {}
    }
    debugPrint('[MessMenuScheduler] All $_count slots cancelled');
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STUDENT REMINDER SCHEDULER
// ─────────────────────────────────────────────────────────────────────────────

Future<void> scheduleMessReminderForStudent({
  required String hostelId,
  String? uid,
}) async {
  final prefs    = await SharedPreferences.getInstance();
  final masterOn = prefs.getBool('push_notifications') ?? true;
  final messOn   = prefs.getBool('mess_menu_notifications') ?? false;

  if (!masterOn || !messOn) {
    await MessMenuScheduler.instance.cancel();
    return;
  }

  if (hostelId.isEmpty) {
    debugPrint('[MessMenu] scheduleMessReminderForStudent: hostelId is empty');
    return;
  }

  final now      = DateTime.now();
  final tomorrow = now.add(const Duration(days: 1));
  final docId    =
      '${tomorrow.year}-${tomorrow.month.toString().padLeft(2, '0')}-${tomorrow.day.toString().padLeft(2, '0')}';

  try {
    final snap = await FirebaseFirestore.instance
        .collection('messMenu')
        .doc(hostelId)
        .collection('daily')
        .doc(docId)
        .get();

    if (!snap.exists || snap.data()?['hasNonVeg'] != true) {
      debugPrint('[MessMenu] No non-veg tomorrow ($docId) — cancelling');
      await MessMenuScheduler.instance.cancel();
      return;
    }

    if (uid != null && uid.isNotEmpty) {
      final tomorrowDayName = _kDays[(tomorrow.weekday - 1) % 7];
      final alreadyBooked   = _Store.i.bookings.any(
            (b) => b.uid == uid && b.day == tomorrowDayName,
      );
      if (alreadyBooked) {
        debugPrint(
            '[MessMenu] Student $uid already booked non-veg for $tomorrowDayName — cancelling reminders');
        await MessMenuScheduler.instance.cancel();
        return;
      }
    }

    debugPrint('[MessMenu] Scheduling hourly reminders for $docId');
    await MessMenuScheduler.instance.scheduleHourlyReminders(snap.data()!);
  } catch (e) {
    debugPrint('[MessMenu] scheduleMessReminderForStudent error: $e');
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// THEME HELPER
// ─────────────────────────────────────────────────────────────────────────────

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
  Color get appBar      => dark ? const Color(0xFF0A0D18) : const Color(0xFF1248A8);
  Color get ink         => dark ? const Color(0xFFE4E8F5) : const Color(0xFF1A1F36);
  Color get textGrey    => dark ? const Color(0xFF7A85A0) : const Color(0xFF6B7280);
  Color get divider     => dark ? const Color(0xFF222638) : const Color(0xFFE8EDF5);
  Color get success     => const Color(0xFF059669);
  Color get danger      => const Color(0xFFDC2626);
  Color get dangerLight => dark ? const Color(0xFF2A1010) : const Color(0xFFFEE2E2);
  Color get warn        => const Color(0xFFD97706);
  Color get warnBg      => dark ? const Color(0xFF231800) : const Color(0xFFFFF7ED);
  Color get star        => const Color(0xFFF59E0B);
  Color get starBg      => dark ? const Color(0xFF261C00) : const Color(0xFFFFFBEB);
}

// ─────────────────────────────────────────────────────────────────────────────
// CONSTANTS
// ─────────────────────────────────────────────────────────────────────────────

const _kDays       = ['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'];
const _kMeals      = ['Morning','Afternoon','Night'];
const _kMealEmoji  = ['☀️','🌤','🌙'];
const _kMealLabels = ['Breakfast','Lunch','Dinner'];

// ─────────────────────────────────────────────────────────────────────────────
// TIME HELPERS
// ─────────────────────────────────────────────────────────────────────────────

String _computeActiveDay() {
  final now = DateTime.now();
  if (now.hour >= 21) {
    final tom = now.add(const Duration(days: 1));
    return _kDays[(tom.weekday - 1) % 7];
  }
  return _kDays[(now.weekday - 1) % 7];
}

bool _isBookingOpen(String dayName) {
  final now       = DateTime.now();
  final todayName = _kDays[(now.weekday - 1) % 7];
  final tomName   = _kDays[(now.add(const Duration(days: 1)).weekday - 1) % 7];
  if (dayName == tomName && now.hour >= 21) return true;
  if (dayName == todayName && now.hour < 9) return true;
  return false;
}

// ─────────────────────────────────────────────────────────────────────────────
// STORE
// ─────────────────────────────────────────────────────────────────────────────

class _Store {
  _Store._();
  static final i = _Store._();

  String hostelId = '';

  Map<String, Map<String, List<String>>> nvSchedule = {
    'Tuesday':   {'Afternoon': ['Boiled Egg','Omelette']},
    'Wednesday': {'Afternoon': ['Chicken','Boiled Egg']},
    'Thursday':  {'Afternoon': ['Egg Gravy','Boiled Egg']},
    'Saturday':  {'Afternoon': ['Full Boiled Egg','Omelette']},
    'Sunday':    {'Afternoon': ['Chicken','Boiled Egg']},
  };

  Map<String, Map<String, String>> menu = {
    'Monday':    {'Morning':'Upma',         'Afternoon':'Dal',                       'Night':'Chappathi'},
    'Tuesday':   {'Morning':'Puri',         'Afternoon':'Sambar Rice / Tomato Rice', 'Night':'Dosa'},
    'Wednesday': {'Morning':'Idly Kesari',  'Afternoon':'Puli Kolambu',              'Night':'Idiyappam'},
    'Thursday':  {'Morning':'Pongal',       'Afternoon':'Puli Kolambu',              'Night':'Dosa'},
    'Friday':    {'Morning':'Idly',         'Afternoon':'Sambar Rice',               'Night':'Chappathi'},
    'Saturday':  {'Morning':'Puri',         'Afternoon':'Puli Kolambu',              'Night':'Variety Rice'},
    'Sunday':    {'Morning':'Special Dosa', 'Afternoon':'Rice & Curry',              'Night':'Idly'},
  };

  final List<_Booking> bookings = [];

  List<String> nvItems(String day, String meal) => nvSchedule[day]?[meal] ?? [];

  Future<void> setNvItems(String day, String meal, List<String> items) async {
    if (items.isEmpty) {
      nvSchedule[day]?.remove(meal);
      if (nvSchedule[day]?.isEmpty ?? false) nvSchedule.remove(day);
    } else {
      nvSchedule.putIfAbsent(day, () => {})[meal] = List.from(items);
    }

    if (hostelId.isEmpty) return;
    try {
      final docId     = _nextDateForDay(day);
      final hasNonVeg = _anyNonVeg(day);

      final allNvItems = <String>[];
      for (final m in _kMeals) {
        allNvItems.addAll(nvSchedule[day]?[m] ?? []);
      }

      await FirebaseFirestore.instance
          .collection('messMenu')
          .doc(hostelId)
          .collection('daily')
          .doc(docId)
          .set({
        'day':         day,
        'hasNonVeg':   hasNonVeg,
        'nonVegItems': allNvItems,
        'nvByMeal': {
          for (final m in _kMeals)
            m: nvSchedule[day]?[m] ?? [],
        },
        'vegMenu':    menu[day] ?? {},
        'updatedAt':  FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Firestore setNvItems error: $e');
    }
  }

  bool _anyNonVeg(String day) {
    final dayMap = nvSchedule[day];
    if (dayMap == null) return false;
    return dayMap.values.any((items) => items.isNotEmpty);
  }

  String _nextDateForDay(String dayName) {
    final now           = DateTime.now();
    final targetWeekday = _kDays.indexOf(dayName) + 1;
    int daysAhead       = (targetWeekday - now.weekday + 7) % 7;
    if (daysAhead == 0) daysAhead = 7;
    final target = now.add(Duration(days: daysAhead));
    return '${target.year}-${target.month.toString().padLeft(2,'0')}-${target.day.toString().padLeft(2,'0')}';
  }

  void upsert(_Booking b) {
    bookings.removeWhere((x) =>
    x.uid == b.uid && x.day == b.day && x.meal == b.meal && x.item == b.item);
    if (b.qty > 0) bookings.add(b);
  }

  void cancel(String uid, String day, String meal, String item) =>
      bookings.removeWhere((x) =>
      x.uid == uid && x.day == day && x.meal == meal && x.item == item);

  Map<String, int> itemCounts(String day, String meal) {
    final r = <String, int>{};
    for (final b in bookings.where((b) => b.day == day && b.meal == meal)) {
      r[b.item] = (r[b.item] ?? 0) + b.qty;
    }
    return r;
  }

  List<_Booking> itemBookings(String day, String meal, String item) =>
      bookings.where((b) => b.day == day && b.meal == meal && b.item == item).toList();
}

class _Booking {
  final String uid, name, rollNo, day, meal, item;
  final int qty;
  final DateTime at;
  _Booking({
    required this.uid, required this.name, required this.rollNo,
    required this.day, required this.meal, required this.item,
    required this.qty, required this.at,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// PROFILE
// ─────────────────────────────────────────────────────────────────────────────

class _Profile {
  final String uid, name, rollNo, dept, year, roomNo, hostelId;
  const _Profile({
    required this.uid, required this.name, required this.rollNo,
    required this.dept, required this.year, required this.roomNo,
    this.hostelId = '',
  });
}

Future<_Profile?> _fetchProfile() async {
  try {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    final doc = await FirebaseFirestore.instance
        .collection('users').doc(user.uid).get();
    if (!doc.exists) return null;
    final d = doc.data()!;
    return _Profile(
      uid:      user.uid,
      name:     d['name']     ?? '',
      rollNo:   d['regNo']    ?? '',
      dept:     d['dept']     ?? '',
      year:     d['year']     ?? '',
      roomNo:   d['roomNo']   ?? '',
      hostelId: d['hostelId'] ?? '',
    );
  } catch (_) { return null; }
}

Future<String> _fetchWardenName() async {
  try {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return '';
    final doc = await FirebaseFirestore.instance
        .collection('users').doc(user.uid).get();
    return doc.data()?['name'] ?? '';
  } catch (_) { return ''; }
}

Future<void> _maybeScheduleReminder(String day) async {
  final now      = DateTime.now();
  final tomorrow = _kDays[(now.add(const Duration(days: 1)).weekday - 1) % 7];
  if (day != tomorrow) return;

  final prefs    = await SharedPreferences.getInstance();
  final masterOn = prefs.getBool('push_notifications') ?? true;
  final messOn   = prefs.getBool('mess_menu_notifications') ?? false;
  if (!masterOn || !messOn) return;

  final hasNonVeg =
      _Store.i.nvSchedule[day]?.values.any((l) => l.isNotEmpty) ?? false;
  if (!hasNonVeg) {
    await MessMenuScheduler.instance.cancel();
    return;
  }

  final allItems = <String>[];
  for (final m in _kMeals) allItems.addAll(_Store.i.nvItems(day, m));

  await MessMenuScheduler.instance.scheduleHourlyReminders({
    'hasNonVeg':   true,
    'nonVegItems': allItems,
  });
}

// ═════════════════════════════════════════════════════════════════════════════
// STUDENT PAGE
// ═════════════════════════════════════════════════════════════════════════════

class MessMenuStudentPage extends StatefulWidget {
  const MessMenuStudentPage({super.key});
  @override State<MessMenuStudentPage> createState() => _StudentState();
}

class _StudentState extends State<MessMenuStudentPage>
    with SingleTickerProviderStateMixin {
  _Profile? _profile;
  bool      _loading = true;
  String    _day     = _computeActiveDay();
  Timer?    _tick;
  final Map<String, int> _qty       = {};
  final Set<String>      _confirmed = {};
  TabController?         _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _tabCtrl!.addListener(() => setState(() {}));

    _fetchProfile().then((p) async {
      if (!mounted) return;
      setState(() { _profile = p; _loading = false; });

      if (p != null && p.hostelId.isNotEmpty) {
        _Store.i.hostelId = p.hostelId;
        await scheduleMessReminderForStudent(
          hostelId: p.hostelId,
          uid: p.uid,
        );
      }
    });

    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) return;
      final nd = _computeActiveDay();
      setState(() {
        if (nd != _day) { _day = nd; _qty.clear(); _confirmed.clear(); }
      });
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _tabCtrl?.dispose();
    super.dispose();
  }

  String _k(String meal, String item) => '$_day|$meal|$item';
  int    _q(String meal, String item) => _qty[_k(meal, item)] ?? 0;
  bool   _isConfirmedItem(String meal, String item) =>
      _confirmed.contains('$_day|$meal|$item');

  void _toggle(String meal, String item) {
    if (_isConfirmedItem(meal, item)) return;
    final k = _k(meal, item);
    setState(() => _qty[k] = (_qty[k] ?? 0) > 0 ? 0 : 1);
  }

  void _setQty(String meal, String item, int v) {
    if (_isConfirmedItem(meal, item)) return;
    setState(() => _qty[_k(meal, item)] = v.clamp(1, 10));
  }

  void _confirmItem(String meal, String item) {
    if (_profile == null) return;
    final q = _q(meal, item);
    if (q > 0) {
      _Store.i.upsert(_Booking(
        uid: _profile!.uid, name: _profile!.name, rollNo: _profile!.rollNo,
        day: _day, meal: meal, item: item, qty: q, at: DateTime.now(),
      ));
    } else {
      _Store.i.cancel(_profile!.uid, _day, meal, item);
    }
    setState(() => _confirmed.add('$_day|$meal|$item'));
    _snack('$item booked!', const Color(0xFF059669));

    if (_profile != null && _profile!.hostelId.isNotEmpty) {
      scheduleMessReminderForStudent(
        hostelId: _profile!.hostelId,
        uid: _profile!.uid,
      );
    }
  }

  void _editItem(String meal, String item) =>
      setState(() => _confirmed.remove('$_day|$meal|$item'));

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w700)),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      duration: const Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final c       = _C.of(context);
    final myBooks = _profile == null
        ? <_Booking>[]
        : _Store.i.bookings.where((b) => b.uid == _profile!.uid).toList();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: c.scaffold,
        appBar: AppBar(
          backgroundColor: c.blueDark, elevation: 0,
          // ← Back arrow instead of menu icon
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: Colors.white, size: 18),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text('Student Mess Booking',
              style: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w700)),
          actions: [
            if (_profile != null)
              GestureDetector(
                onTap: _showProfileSheet,
                child: Container(
                  margin: const EdgeInsets.only(right: 12),
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: ClipOval(child: Container(
                    color: Colors.white24, alignment: Alignment.center,
                    child: Text(
                      _profile!.name.isNotEmpty ? _profile!.name[0].toUpperCase() : '?',
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14),
                    ),
                  )),
                ),
              )
            else
              const Padding(padding: EdgeInsets.only(right: 12),
                  child: Icon(Icons.account_circle, color: Colors.white, size: 34)),
          ],
          systemOverlayStyle: SystemUiOverlayStyle.light,
          bottom: TabBar(
            controller: _tabCtrl!,
            indicatorColor: Colors.white, indicatorWeight: 3,
            indicatorSize: TabBarIndicatorSize.tab,
            labelColor: Colors.white, unselectedLabelColor: Colors.white54,
            labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
            tabs: const [
              Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.restaurant_menu_rounded, size: 15),
                SizedBox(width: 6),
                Text('Booking'),
              ])),
              Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.rate_review_rounded, size: 15),
                SizedBox(width: 6),
                Text('Feedback'),
              ])),
            ],
          ),
        ),
        body: _loading
            ? Center(child: CircularProgressIndicator(color: c.blue))
            : TabBarView(controller: _tabCtrl!, children: [
          _buildBookingTab(c, myBooks),
          _FeedbackTab(profile: _profile, onSnack: _snack),
        ]),
      ),
    );
  }

  Widget _buildBookingTab(_C c, List<_Booking> myBooks) {
    final bookingOpen = _isBookingOpen(_day);
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 48),
      children: [
        _ImageMenuCard(day: _day),
        const SizedBox(height: 14),
        _BookNonVegSection(
          day: _day, bookingOpen: bookingOpen,
          isConfirmedItem: _isConfirmedItem, getQty: _q,
          onToggle: _toggle, onQtyChange: _setQty,
          onConfirmItem: _confirmItem, onEditItem: _editItem,
        ),
        const SizedBox(height: 14),
        _ImageMyBookingsBtn(
            bookings: myBooks, onTap: () => _showMyBookingsSheet(myBooks)),
        const SizedBox(height: 20),
        _WeeklyMenuPreview(activeDay: _day),
        const SizedBox(height: 20),
        const _MessInfoCard(),
      ],
    );
  }

  void _showProfileSheet() {
    if (_profile == null) return;
    showModalBottomSheet(
      context: context, backgroundColor: Colors.transparent, isScrollControlled: true,
      builder: (_) => _ProfileSheet(profile: _profile!),
    );
  }

  void _showMyBookingsSheet(List<_Booking> books) {
    showModalBottomSheet(
      context: context, backgroundColor: Colors.transparent, isScrollControlled: true,
      builder: (_) => _MyBookingsSheet(bookings: books),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FEEDBACK TAB
// ─────────────────────────────────────────────────────────────────────────────

class _FeedbackTab extends StatefulWidget {
  final _Profile? profile;
  final void Function(String, Color) onSnack;
  const _FeedbackTab({required this.profile, required this.onSnack});
  @override State<_FeedbackTab> createState() => _FeedbackTabState();
}

class _FeedbackTabState extends State<_FeedbackTab> {
  String _selectedDay  = _computeActiveDay();
  String _selectedMeal = _kMeals[0];
  int    _rating       = 0;
  final  TextEditingController _commentCtrl = TextEditingController();
  bool   _submitting   = false;
  bool   _submitted    = false;
  List<Map<String, dynamic>> _pastFeedbacks = [];
  bool   _loadingHistory = false;

  @override
  void initState() {
    super.initState();
    if (widget.profile != null) _loadHistory();
  }

  @override
  void dispose() { _commentCtrl.dispose(); super.dispose(); }

  Future<void> _loadHistory() async {
    if (widget.profile == null) return;
    setState(() => _loadingHistory = true);
    try {
      final snap = await FirebaseFirestore.instance
          .collection('mess_feedbacks')
          .where('uid', isEqualTo: widget.profile!.uid)
          .orderBy('submittedAt', descending: true)
          .limit(30)
          .get();
      if (mounted) {
        setState(() {
          _pastFeedbacks =
              snap.docs.map((d) => {'_docId': d.id, ...d.data()}).toList();
        });
      }
    } catch (e) { debugPrint('History load error: $e'); }
    finally { if (mounted) setState(() => _loadingHistory = false); }
  }

  void _reset() =>
      setState(() { _rating = 0; _commentCtrl.clear(); _submitted = false; });

  Future<void> _submit() async {
    if (widget.profile == null) {
      widget.onSnack('Please log in to submit feedback', const Color(0xFFDC2626));
      return;
    }
    if (_rating == 0) {
      widget.onSnack('Please select a rating', const Color(0xFFD97706));
      return;
    }
    if (_commentCtrl.text.trim().isEmpty) {
      widget.onSnack('Please write your feedback', const Color(0xFFD97706));
      return;
    }
    setState(() => _submitting = true);
    try {
      final now     = DateTime.now();
      final payload = {
        'uid': widget.profile!.uid, 'name': widget.profile!.name,
        'rollNo': widget.profile!.rollNo, 'dept': widget.profile!.dept,
        'year': widget.profile!.year, 'roomNo': widget.profile!.roomNo,
        'day': _selectedDay, 'meal': _selectedMeal,
        'rating': _rating, 'comment': _commentCtrl.text.trim(),
        'submittedAt': Timestamp.fromDate(now), 'at': Timestamp.fromDate(now),
      };
      final ref = await FirebaseFirestore.instance
          .collection('mess_feedbacks').add(payload);
      if (mounted) {
        setState(() {
          _pastFeedbacks.insert(0, {'_docId': ref.id, ...payload});
          _submitting = false;
          _submitted  = true;
        });
      }
      widget.onSnack('Feedback submitted! Thank you 🙏', const Color(0xFF059669));
    } catch (e) {
      if (mounted) setState(() => _submitting = false);
      widget.onSnack('Failed to submit: $e', const Color(0xFFDC2626));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _C.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 48),
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
          decoration: BoxDecoration(color: c.blueBg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: c.blueBorder)),
          child: Row(children: [
            Icon(Icons.info_outline_rounded, color: c.blue, size: 16),
            const SizedBox(width: 10),
            Expanded(child: Text(
                'Your feedback helps us improve the mess experience.',
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w500, color: c.blue))),
          ]),
        ),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(color: c.white,
              border: Border.all(color: c.divider),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [BoxShadow(
                  color: Colors.black.withOpacity(c.dark ? 0.3 : 0.06),
                  blurRadius: 8, offset: const Offset(0, 2))]),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                decoration: BoxDecoration(color: c.blue,
                    borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(7))),
                child: const Text('Post Feedback',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w700))),
            Padding(
              padding: const EdgeInsets.all(14),
              child: _submitted
                  ? _SuccessState(onAnother: _reset)
                  : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _FeedbackLabel(label: 'Select Day'),
                const SizedBox(height: 8),
                _DaySelector(
                    selected: _selectedDay,
                    onSelect: (d) => setState(() => _selectedDay = d)),
                const SizedBox(height: 14),
                _FeedbackLabel(label: 'Select Meal'),
                const SizedBox(height: 8),
                _MealSelector(
                    selected: _selectedMeal,
                    onSelect: (m) => setState(() => _selectedMeal = m)),
                const SizedBox(height: 14),
                _FeedbackLabel(label: 'Rate the Meal'),
                const SizedBox(height: 8),
                _StarRating(
                    rating: _rating,
                    onRate: (r) => setState(() => _rating = r)),
                const SizedBox(height: 14),
                _FeedbackLabel(label: 'Your Feedback'),
                const SizedBox(height: 8),
                TextField(
                  controller: _commentCtrl,
                  maxLines: 4, maxLength: 300,
                  textCapitalization: TextCapitalization.sentences,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: c.ink),
                  decoration: InputDecoration(
                    hintText:
                    'Share your thoughts on food quality, quantity, hygiene…',
                    hintStyle: TextStyle(
                        color: c.textGrey,
                        fontWeight: FontWeight.w400,
                        fontSize: 13),
                    filled: true, fillColor: c.blueBg,
                    counterStyle:
                    TextStyle(color: c.textGrey, fontSize: 11),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 13, vertical: 11),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide:
                        BorderSide(color: c.blue, width: 1.5)),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: GestureDetector(
                    onTap: _submitting ? null : _submit,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      height: 46,
                      decoration: BoxDecoration(
                          color: _submitting
                              ? c.blue.withOpacity(0.6)
                              : c.blue,
                          borderRadius: BorderRadius.circular(8)),
                      alignment: Alignment.center,
                      child: _submitting
                          ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2.5))
                          : const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.send_rounded,
                                color: Colors.white, size: 17),
                            SizedBox(width: 8),
                            Text('Submit Feedback',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15)),
                          ]),
                    ),
                  ),
                ),
              ]),
            ),
          ]),
        ),
        if (_loadingHistory)
          Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                  child: CircularProgressIndicator(
                      color: _C.of(context).blue, strokeWidth: 2)))
        else if (_pastFeedbacks.isNotEmpty) ...[
          const SizedBox(height: 22),
          _SectionTitle(title: 'My Past Feedbacks'),
          const SizedBox(height: 10),
          ..._pastFeedbacks.map((f) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _FeedbackHistoryCard(feedback: f))),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FEEDBACK HISTORY CARD
// ─────────────────────────────────────────────────────────────────────────────

class _FeedbackHistoryCard extends StatelessWidget {
  final Map<String, dynamic> feedback;
  const _FeedbackHistoryCard({required this.feedback});

  int      _rating()  => int.tryParse((feedback['rating'] ?? 0).toString()) ?? 0;
  String   _comment() => (feedback['comment'] ?? feedback['feedback'] ?? '—').toString();
  String   _day()     => (feedback['day']  ?? '—').toString();
  String   _meal()    => (feedback['meal'] ?? '—').toString();
  DateTime? _at() {
    final ts = feedback['submittedAt'] ?? feedback['at'];
    if (ts is Timestamp) return ts.toDate();
    return null;
  }

  String _formatDateTime(DateTime dt) {
    final h    = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final min  = dt.minute.toString().padLeft(2, '0');
    final amPm = dt.hour < 12 ? 'AM' : 'PM';
    return '${_kDays[(dt.weekday - 1) % 7]}, ${dt.day}/${dt.month}/${dt.year}  ·  $h:$min $amPm';
  }

  @override
  Widget build(BuildContext context) {
    final c      = _C.of(context);
    final mIdx   = _kMeals.indexOf(_meal());
    final emoji  = mIdx >= 0 ? _kMealEmoji[mIdx] : '🍽';
    final mLabel = mIdx >= 0 ? _kMealLabels[mIdx] : _meal();
    final rating = _rating();
    final at     = _at();
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(color: c.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: c.divider),
          boxShadow: [BoxShadow(
              color: Colors.black.withOpacity(c.dark ? 0.2 : 0.04),
              blurRadius: 4, offset: const Offset(0, 1))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(emoji, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          Expanded(child: Text('${_day()}  ·  $mLabel',
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w700, color: c.ink))),
          Row(children: List.generate(5, (i) => Icon(
            i < rating ? Icons.star_rounded : Icons.star_outline_rounded,
            color: i < rating ? c.star : c.blueBorder, size: 15,
          ))),
        ]),
        const SizedBox(height: 8),
        Text(_comment(),
            style: TextStyle(fontSize: 13, color: c.textGrey, height: 1.5)),
        if (at != null) ...[
          const SizedBox(height: 6),
          Text(_formatDateTime(at),
              style: TextStyle(fontSize: 11, color: c.textGrey)),
        ],
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FEEDBACK FORM SUBWIDGETS
// ─────────────────────────────────────────────────────────────────────────────

class _FeedbackLabel extends StatelessWidget {
  final String label;
  const _FeedbackLabel({required this.label});
  @override
  Widget build(BuildContext context) {
    final c = _C.of(context);
    return Text(label,
        style: TextStyle(
            fontSize: 13, fontWeight: FontWeight.w700, color: c.textGrey));
  }
}

class _DaySelector extends StatelessWidget {
  final String selected;
  final void Function(String) onSelect;
  const _DaySelector({required this.selected, required this.onSelect});
  @override
  Widget build(BuildContext context) {
    final c = _C.of(context);
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _kDays.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final day        = _kDays[i];
          final isSelected = day == selected;
          return GestureDetector(
            onTap: () => onSelect(day),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                  color: isSelected ? c.blue : c.blueBg,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                      color: isSelected ? c.blue : c.blueBorder,
                      width: isSelected ? 1.5 : 1)),
              alignment: Alignment.center,
              child: Text(day.substring(0, 3),
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: isSelected ? Colors.white : c.textGrey)),
            ),
          );
        },
      ),
    );
  }
}

class _MealSelector extends StatelessWidget {
  final String selected;
  final void Function(String) onSelect;
  const _MealSelector({required this.selected, required this.onSelect});
  @override
  Widget build(BuildContext context) {
    final c = _C.of(context);
    return Row(children: List.generate(_kMeals.length, (i) {
      final meal       = _kMeals[i];
      final label      = _kMealLabels[i];
      final emoji      = _kMealEmoji[i];
      final isSelected = meal == selected;
      return Expanded(
        child: Padding(
          padding: EdgeInsets.only(right: i < _kMeals.length - 1 ? 8 : 0),
          child: GestureDetector(
            onTap: () => onSelect(meal),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              height: 48,
              decoration: BoxDecoration(
                  color: isSelected ? c.blue : c.blueBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: isSelected ? c.blue : c.blueBorder,
                      width: isSelected ? 1.5 : 1)),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(emoji, style: const TextStyle(fontSize: 14)),
                const SizedBox(height: 2),
                Text(label,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: isSelected ? Colors.white : c.textGrey)),
              ]),
            ),
          ),
        ),
      );
    }));
  }
}

class _StarRating extends StatelessWidget {
  final int rating;
  final void Function(int) onRate;
  const _StarRating({required this.rating, required this.onRate});
  static const _labels = ['', 'Poor', 'Fair', 'Good', 'Great', 'Excellent'];
  @override
  Widget build(BuildContext context) {
    final c = _C.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: List.generate(5, (i) {
        final star   = i + 1;
        final filled = star <= rating;
        return GestureDetector(
          onTap: () => onRate(star),
          child: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: Icon(
                filled ? Icons.star_rounded : Icons.star_outline_rounded,
                key: ValueKey(filled),
                color: filled ? c.star : c.blueBorder,
                size: 34,
              ),
            ),
          ),
        );
      })),
      if (rating > 0) ...[
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
              color: c.starBg, borderRadius: BorderRadius.circular(5)),
          child: Text(_labels[rating],
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700, color: c.star)),
        ),
      ],
    ]);
  }
}

class _SuccessState extends StatelessWidget {
  final VoidCallback onAnother;
  const _SuccessState({required this.onAnother});
  @override
  Widget build(BuildContext context) {
    final c = _C.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Column(children: [
        Container(
          width: 64, height: 64,
          decoration: BoxDecoration(
              color: const Color(0xFF059669).withOpacity(0.1),
              shape: BoxShape.circle),
          child: const Icon(Icons.check_circle_rounded,
              color: Color(0xFF059669), size: 36),
        ),
        const SizedBox(height: 14),
        Text('Feedback Submitted!',
            style: TextStyle(
                fontSize: 17, fontWeight: FontWeight.w800, color: c.ink)),
        const SizedBox(height: 5),
        Text('Thank you for helping us improve.',
            style: TextStyle(fontSize: 13, color: c.textGrey)),
        const SizedBox(height: 20),
        _OutlineBtn2(label: 'Submit Another', onTap: onAnother),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TODAY'S MENU CARD
// ─────────────────────────────────────────────────────────────────────────────

class _ImageMenuCard extends StatelessWidget {
  final String day;
  const _ImageMenuCard({required this.day});
  @override
  Widget build(BuildContext context) {
    final c = _C.of(context);
    return Container(
      decoration: BoxDecoration(color: c.white,
          border: Border.all(color: c.divider),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [BoxShadow(
              color: Colors.black.withOpacity(c.dark ? 0.3 : 0.06),
              blurRadius: 8, offset: const Offset(0, 2))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(color: c.blue,
              borderRadius:
              const BorderRadius.vertical(top: Radius.circular(7))),
          child: Text("$day's Menu",
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w700)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
          child: Column(children: _kMeals.asMap().entries.map((e) {
            final mealLabel = _kMealLabels[e.key];
            final mealKey   = e.value;
            final item      = _Store.i.menu[day]?[mealKey] ?? '—';
            final nvItems   = _Store.i.nvItems(day, mealKey);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(
                  padding: const EdgeInsets.only(top: 6, right: 9),
                  child: Container(
                      width: 7, height: 7,
                      decoration: BoxDecoration(
                          color: c.blue, shape: BoxShape.circle)),
                ),
                Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start, children: [
                  RichText(
                      text: TextSpan(
                          style: TextStyle(
                              fontSize: 15, color: c.ink, height: 1.5),
                          children: [
                            TextSpan(
                                text: '$mealLabel: ',
                                style: const TextStyle(fontWeight: FontWeight.w700)),
                            TextSpan(text: item),
                          ])),
                  if (nvItems.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: RichText(
                          text: TextSpan(
                              style: TextStyle(
                                  fontSize: 14, color: c.ink, height: 1.5),
                              children: [
                                const TextSpan(
                                    text: 'Non-Veg: ',
                                    style:
                                    TextStyle(fontWeight: FontWeight.w700)),
                                TextSpan(text: nvItems.join(', ')),
                              ])),
                    ),
                ])),
              ]),
            );
          }).toList()),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BOOK NON-VEG SECTION
// ─────────────────────────────────────────────────────────────────────────────

class _BookNonVegSection extends StatelessWidget {
  final String day;
  final bool bookingOpen;
  final bool Function(String, String) isConfirmedItem;
  final int  Function(String, String) getQty;
  final void Function(String, String) onToggle;
  final void Function(String, String, int) onQtyChange;
  final void Function(String, String) onConfirmItem;
  final void Function(String, String) onEditItem;
  const _BookNonVegSection({
    required this.day, required this.bookingOpen,
    required this.isConfirmedItem, required this.getQty,
    required this.onToggle, required this.onQtyChange,
    required this.onConfirmItem, required this.onEditItem,
  });

  @override
  Widget build(BuildContext context) {
    final c        = _C.of(context);
    final allItems = <_NvEntry>[];
    for (final meal in _kMeals) {
      for (final item in _Store.i.nvItems(day, meal)) {
        allItems.add(_NvEntry(meal: meal, item: item));
      }
    }
    if (allItems.isEmpty) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _SectionTitle(title: 'Book Non-Veg Meal'),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: c.white,
              border: Border.all(color: c.divider),
              borderRadius: BorderRadius.circular(8)),
          child: Row(children: [
            const Text('🚫', style: TextStyle(fontSize: 18)),
            const SizedBox(width: 10),
            Text('No non-veg available today',
                style: TextStyle(
                    fontSize: 14,
                    color: c.textGrey,
                    fontWeight: FontWeight.w500)),
          ]),
        ),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _SectionTitle(title: 'Book Non-Veg Meal'),
      const SizedBox(height: 8),
      if (!bookingOpen)
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(color: c.warnBg,
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: c.warn.withOpacity(0.4))),
          child: Row(children: [
            Icon(Icons.lock_clock_rounded, size: 16, color: c.warn),
            const SizedBox(width: 8),
            Expanded(child: Text(
                'Booking not available  ·  Opens today at 9:00 PM',
                style: TextStyle(
                    fontSize: 13,
                    color: c.warn,
                    fontWeight: FontWeight.w600))),
          ]),
        ),
      Container(
        decoration: BoxDecoration(color: c.white,
            border: Border.all(color: c.divider),
            borderRadius: BorderRadius.circular(8),
            boxShadow: [BoxShadow(
                color: Colors.black.withOpacity(c.dark ? 0.3 : 0.05),
                blurRadius: 6, offset: const Offset(0, 2))]),
        child: Column(children: allItems.asMap().entries.map((entry) {
          final i      = entry.key;
          final e      = entry.value;
          final qty    = getQty(e.meal, e.item);
          final conf   = isConfirmedItem(e.meal, e.item);
          final isLast = i == allItems.length - 1;
          return Column(children: [
            _NvItemRow(
              item: e.item, meal: e.meal, qty: qty,
              confirmed: conf, bookingOpen: bookingOpen,
              onDecrement: () => qty > 1
                  ? onQtyChange(e.meal, e.item, qty - 1)
                  : onToggle(e.meal, e.item),
              onIncrement: () => qty == 0
                  ? onToggle(e.meal, e.item)
                  : onQtyChange(e.meal, e.item, qty + 1),
              onBook: conf
                  ? () => onEditItem(e.meal, e.item)
                  : () => onConfirmItem(e.meal, e.item),
            ),
            if (!isLast)
              Divider(
                  height: 1, thickness: 1,
                  color: c.divider, indent: 14, endIndent: 14),
          ]);
        }).toList()),
      ),
    ]);
  }
}

class _NvEntry {
  final String meal, item;
  _NvEntry({required this.meal, required this.item});
}

class _NvItemRow extends StatelessWidget {
  final String item, meal;
  final int qty;
  final bool confirmed, bookingOpen;
  final VoidCallback onDecrement, onIncrement, onBook;
  const _NvItemRow({
    required this.item, required this.meal, required this.qty,
    required this.confirmed, required this.bookingOpen,
    required this.onDecrement, required this.onIncrement, required this.onBook,
  });
  @override
  Widget build(BuildContext context) {
    final c = _C.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Expanded(child: Text(item,
            style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.w700, color: c.ink))),
        Row(children: [
          _StepperBtn(
              icon: Icons.remove,
              enabled: qty > 0 && !confirmed && bookingOpen,
              onTap: onDecrement),
          SizedBox(
            width: 32,
            child: Text('$qty',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w800, color: c.ink)),
          ),
          _StepperBtn(
              icon: Icons.add,
              enabled: !confirmed && bookingOpen,
              onTap: onIncrement),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: bookingOpen ? onBook : null,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: !bookingOpen
                    ? (c.dark ? const Color(0xFF2A2D3E) : Colors.grey.shade300)
                    : confirmed
                    ? (c.dark
                    ? const Color(0xFF3A3D50)
                    : Colors.grey.shade400)
                    : c.blue,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(confirmed ? 'Edit' : 'Book',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14)),
            ),
          ),
        ]),
      ]),
    );
  }
}

class _StepperBtn extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  const _StepperBtn(
      {required this.icon, required this.enabled, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final c = _C.of(context);
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 28, height: 28,
        decoration: BoxDecoration(
          color: enabled
              ? c.blue
              : (c.dark ? const Color(0xFF252838) : Colors.grey.shade200),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Icon(icon,
            size: 16,
            color: enabled
                ? Colors.white
                : (c.dark
                ? const Color(0xFF505570)
                : Colors.grey.shade400)),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MY BOOKINGS
// ─────────────────────────────────────────────────────────────────────────────

class _ImageMyBookingsBtn extends StatelessWidget {
  final List<_Booking> bookings;
  final VoidCallback onTap;
  const _ImageMyBookingsBtn({required this.bookings, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final c     = _C.of(context);
    final count = bookings.length;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration:
        BoxDecoration(color: c.blue, borderRadius: BorderRadius.circular(8)),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Text('My Bookings',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700)),
          if (count > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding:
              const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.25),
                  borderRadius: BorderRadius.circular(10)),
              child: Text('$count',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 12)),
            ),
          ],
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right_rounded,
              color: Colors.white, size: 20),
        ]),
      ),
    );
  }
}

class _MyBookingsSheet extends StatelessWidget {
  final List<_Booking> bookings;
  const _MyBookingsSheet({required this.bookings});
  @override
  Widget build(BuildContext context) {
    final c        = _C.of(context);
    final totalQty = bookings.fold(0, (s, b) => s + b.qty);
    return Container(
      decoration: BoxDecoration(color: c.white,
          borderRadius:
          const BorderRadius.vertical(top: Radius.circular(20))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          color: c.blue,
          child: Row(children: [
            const Text('My Bookings',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w700)),
            const Spacer(),
            if (totalQty > 0)
              Text('$totalQty item${totalQty > 1 ? 's' : ''}',
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
          ]),
        ),
        if (bookings.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 28),
            child: Text('No bookings yet',
                style: TextStyle(color: c.textGrey, fontSize: 15)),
          )
        else
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 28),
              itemCount: bookings.length,
              separatorBuilder: (_, __) =>
                  Divider(height: 1, color: c.divider),
              itemBuilder: (_, i) {
                final b = bookings[i];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(children: [
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(b.item,
                                  style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: c.ink)),
                              const SizedBox(height: 3),
                              Text('${b.day}  ·  ${b.meal}',
                                  style: TextStyle(
                                      fontSize: 13, color: c.textGrey)),
                            ])),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 13, vertical: 6),
                      decoration: BoxDecoration(
                          color: c.blueBg,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: c.blueBorder)),
                      child: Text('× ${b.qty}',
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                              color: c.blue)),
                    ),
                  ]),
                );
              },
            ),
          ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WEEKLY MENU PREVIEW
// ─────────────────────────────────────────────────────────────────────────────

class _WeeklyMenuPreview extends StatefulWidget {
  final String activeDay;
  const _WeeklyMenuPreview({required this.activeDay});
  @override
  State<_WeeklyMenuPreview> createState() => _WeeklyMenuPreviewState();
}

class _WeeklyMenuPreviewState extends State<_WeeklyMenuPreview> {
  bool _expanded = false;
  @override
  Widget build(BuildContext context) {
    final c = _C.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _SectionTitle(title: 'Weekly Menu'),
      const SizedBox(height: 10),
      Container(
        decoration: BoxDecoration(color: c.white,
            border: Border.all(color: c.divider),
            borderRadius: BorderRadius.circular(8),
            boxShadow: [BoxShadow(
                color: Colors.black.withOpacity(c.dark ? 0.25 : 0.05),
                blurRadius: 6, offset: const Offset(0, 2))]),
        child: Column(children: [
          ..._kDays.asMap().entries.map((entry) {
            final idx       = entry.key;
            final d         = entry.value;
            final isActive  = d == widget.activeDay;
            final activeIdx = _kDays.indexOf(widget.activeDay);
            final relIdx    = (idx - activeIdx + 7) % 7;
            if (relIdx > 2 && !_expanded) return const SizedBox.shrink();
            return Column(children: [
              Container(
                color: isActive ? c.blueBg : null,
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 11),
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 90,
                        child: Row(children: [
                          if (isActive)
                            Container(
                              width: 6, height: 6,
                              margin: const EdgeInsets.only(right: 6, top: 5),
                              decoration: BoxDecoration(
                                  color: c.blue, shape: BoxShape.circle),
                            )
                          else
                            const SizedBox(width: 12),
                          Text(d,
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: isActive
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                  color: isActive ? c.blue : c.textGrey)),
                        ]),
                      ),
                      Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: _kMeals.asMap().entries.map((me) {
                              final mLabel  = _kMealLabels[me.key];
                              final mealKey = me.value;
                              final item    = _Store.i.menu[d]?[mealKey] ?? '—';
                              final nvItems = _Store.i.nvItems(d, mealKey);
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 2),
                                child: Column(
                                    crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                    children: [
                                      Text('$mLabel: $item',
                                          style: TextStyle(
                                              fontSize: 13,
                                              color: isActive ? c.ink : c.textGrey,
                                              fontWeight: isActive
                                                  ? FontWeight.w600
                                                  : FontWeight.w400)),
                                      if (nvItems.isNotEmpty)
                                        Text('Non-Veg: ${nvItems.join(', ')}',
                                            style: TextStyle(
                                                fontSize: 12,
                                                color:
                                                isActive ? c.ink : c.textGrey,
                                                fontWeight: isActive
                                                    ? FontWeight.w500
                                                    : FontWeight.w400)),
                                    ]),
                              );
                            }).toList()),
                      ),
                    ]),
              ),
              if (idx < _kDays.length - 1)
                Divider(
                    height: 1,
                    color: c.divider,
                    indent: 14,
                    endIndent: 14),
            ]);
          }),
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 11),
              decoration: BoxDecoration(
                  color: c.blueBg,
                  borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(7)),
                  border: Border(top: BorderSide(color: c.divider))),
              child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(_expanded ? 'Show Less' : 'View Full Week',
                        style: TextStyle(
                            fontSize: 13,
                            color: c.blue,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(width: 4),
                    Icon(
                      _expanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      color: c.blue, size: 18,
                    ),
                  ]),
            ),
          ),
        ]),
      ),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MESS INFO CARD
// ─────────────────────────────────────────────────────────────────────────────

class _MessInfoCard extends StatelessWidget {
  const _MessInfoCard();
  @override
  Widget build(BuildContext context) {
    final c = _C.of(context);
    return Container(
      decoration: BoxDecoration(color: c.white,
          border: Border.all(color: c.divider),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [BoxShadow(
              color: Colors.black.withOpacity(c.dark ? 0.2 : 0.04),
              blurRadius: 5, offset: const Offset(0, 2))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(color: c.blueBg,
              borderRadius:
              const BorderRadius.vertical(top: Radius.circular(7)),
              border: Border(bottom: BorderSide(color: c.divider))),
          child: Text('Mess Timings & Info',
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w700, color: c.blue)),
        ),
        Padding(
          padding: const EdgeInsets.all(14),
          child: Column(children: [
            _InfoRow(emoji: '☀️', label: 'Breakfast', time: '7:30 AM – 9:00 AM'),
            const SizedBox(height: 10),
            _InfoRow(emoji: '🌤', label: 'Lunch', time: '12:50 PM – 1:50 PM'),
            const SizedBox(height: 10),
            _InfoRow(emoji: '🌙', label: 'Dinner', time: '7:00 PM – 8:00 PM'),
            Divider(height: 22, color: c.divider),
            _InfoRow(
                emoji: '🍗',
                label: 'Non-Veg Booking Window',
                time: '9:00 PM (prev) – 9:00 AM (day of)'),
          ]),
        ),
      ]),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String emoji, label, time;
  const _InfoRow(
      {required this.emoji, required this.label, required this.time});
  @override
  Widget build(BuildContext context) {
    final c = _C.of(context);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(emoji, style: const TextStyle(fontSize: 16)),
      const SizedBox(width: 10),
      Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700, color: c.ink)),
            const SizedBox(height: 1),
            Text(time, style: TextStyle(fontSize: 12, color: c.textGrey)),
          ])),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PROFILE SHEET
// ─────────────────────────────────────────────────────────────────────────────

class _ProfileSheet extends StatelessWidget {
  final _Profile profile;
  const _ProfileSheet({required this.profile});
  @override
  Widget build(BuildContext context) {
    final c = _C.of(context);
    return Container(
      decoration: BoxDecoration(color: c.white,
          borderRadius:
          const BorderRadius.vertical(top: Radius.circular(20))),
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 36),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Center(
          child: Container(
            width: 38, height: 4,
            decoration: BoxDecoration(
                color: c.divider, borderRadius: BorderRadius.circular(2)),
          ),
        ),
        const SizedBox(height: 22),
        Container(
          width: 70, height: 70,
          decoration: BoxDecoration(color: c.blue, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: Text(
            profile.name.isNotEmpty ? profile.name[0].toUpperCase() : '?',
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w900, fontSize: 26),
          ),
        ),
        const SizedBox(height: 12),
        Text(profile.name,
            style: TextStyle(
                fontSize: 19, fontWeight: FontWeight.w900, color: c.ink)),
        const SizedBox(height: 3),
        Text(profile.rollNo,
            style: TextStyle(fontSize: 13, color: c.textGrey)),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: c.blueBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: c.blueBorder)),
          child: Row(children: [
            _ProfileTile('Dept', profile.dept, Icons.school_outlined),
            Container(
                width: 1, height: 38, color: c.blueBorder,
                margin: const EdgeInsets.symmetric(horizontal: 4)),
            _ProfileTile('Year', profile.year, Icons.calendar_month_outlined),
            Container(
                width: 1, height: 38, color: c.blueBorder,
                margin: const EdgeInsets.symmetric(horizontal: 4)),
            _ProfileTile('Room', profile.roomNo, Icons.meeting_room_outlined),
          ]),
        ),
        const SizedBox(height: 18),
        _OutlineBtn2(label: 'Close', onTap: () => Navigator.pop(context)),
      ]),
    );
  }
}

class _ProfileTile extends StatelessWidget {
  final String label, value;
  final IconData icon;
  const _ProfileTile(this.label, this.value, this.icon);
  @override
  Widget build(BuildContext context) {
    final c = _C.of(context);
    return Expanded(
        child: Column(children: [
          Icon(icon, size: 16, color: c.blue),
          const SizedBox(height: 5),
          Text(value,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w800, color: c.ink)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 10, color: c.textGrey)),
        ]));
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// WARDEN PAGE
// ═════════════════════════════════════════════════════════════════════════════

class MessMenuWardenPage extends StatefulWidget {
  const MessMenuWardenPage({super.key});
  @override
  State<MessMenuWardenPage> createState() => _WardenState();
}

class _WardenState extends State<MessMenuWardenPage>
    with SingleTickerProviderStateMixin {
  TabController? _tabCtrl;
  bool _editVeg = false;
  Map<String, Map<String, String>> _vegDraft = {};
  String _wardenName = '';

  String get _activeDay => _computeActiveDay();

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _tabCtrl!.addListener(() => setState(() {}));
    _fetchWardenName().then((n) {
      if (mounted) setState(() => _wardenName = n);
    });
  }

  @override
  void dispose() { _tabCtrl?.dispose(); super.dispose(); }

  void _startVegEdit() {
    _vegDraft = {for (final d in _kDays) d: Map.from(_Store.i.menu[d]!)};
    setState(() => _editVeg = true);
  }

  void _saveVegEdit() {
    for (final d in _kDays) _Store.i.menu[d] = Map.from(_vegDraft[d]!);
    setState(() => _editVeg = false);
    _snack('Menu updated!', const Color(0xFF059669));
  }

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style: const TextStyle(fontWeight: FontWeight.w700)),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      margin: const EdgeInsets.all(16),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final c      = _C.of(context);
    final tabIdx = _tabCtrl?.index ?? 0;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: c.scaffold,
        appBar: AppBar(
          backgroundColor: c.blueDark, elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: Colors.white, size: 18),
            onPressed: () {
              if (_editVeg) setState(() => _editVeg = false);
              Navigator.pop(context);
            },
          ),
          title: RichText(
              text: const TextSpan(
                  style: TextStyle(fontSize: 17, color: Colors.white),
                  children: [
                    TextSpan(
                        text: 'Warden ',
                        style: TextStyle(fontWeight: FontWeight.w900)),
                    TextSpan(
                        text: 'Mess Management',
                        style: TextStyle(fontWeight: FontWeight.w400)),
                  ])),
          actions: [
            if (!_editVeg && tabIdx == 0)
              IconButton(
                  icon: const Icon(Icons.edit_rounded,
                      color: Colors.white, size: 20),
                  onPressed: _startVegEdit),
            if (_editVeg && tabIdx == 0) ...[
              TextButton(
                  onPressed: () => setState(() => _editVeg = false),
                  child: const Text('Cancel',
                      style: TextStyle(
                          color: Colors.white70, fontSize: 13))),
              TextButton(
                  onPressed: _saveVegEdit,
                  child: const Text('Save',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 13))),
            ],
          ],
          systemOverlayStyle: SystemUiOverlayStyle.light,
          bottom: TabBar(
            controller: _tabCtrl!,
            indicatorColor: Colors.white, indicatorWeight: 3,
            indicatorSize: TabBarIndicatorSize.tab,
            labelColor: Colors.white, unselectedLabelColor: Colors.white54,
            labelStyle: const TextStyle(
                fontWeight: FontWeight.w700, fontSize: 13),
            unselectedLabelStyle: const TextStyle(
                fontWeight: FontWeight.w500, fontSize: 13),
            tabs: [
              const Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.menu_book_rounded, size: 15),
                SizedBox(width: 6),
                Text('Menu'),
              ])),
              Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.receipt_long_rounded, size: 15),
                const SizedBox(width: 6),
                const Text('Orders'),
                if (_Store.i.bookings.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Container(
                    width: 17, height: 17,
                    decoration: const BoxDecoration(
                        color: Color(0xFFDC2626), shape: BoxShape.circle),
                    alignment: Alignment.center,
                    child: Text('${_Store.i.bookings.length}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w900)),
                  ),
                ],
              ])),
            ],
          ),
        ),
        body: TabBarView(controller: _tabCtrl!, children: [
          _buildMenuTab(c),
          _buildOrdersTab(c),
        ]),
      ),
    );
  }

  Widget _buildMenuTab(_C c) {
    final day = _activeDay;
    return ListView(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: c.blueBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: c.blueBorder)),
            child: Row(children: [
              Icon(Icons.schedule_rounded, color: c.blue, size: 16),
              const SizedBox(width: 10),
              Expanded(child: Text(
                  'Non-veg booking: 9:00 PM (prev day) – 9:00 AM (day of)',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: c.blue))),
            ]),
          ),
          const SizedBox(height: 14),
          if (_editVeg)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                  color: c.warn.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: c.warn.withOpacity(0.35))),
              child: Row(children: [
                Icon(Icons.edit_note_rounded, color: c.warn, size: 16),
                const SizedBox(width: 8),
                Text('Editing menu for all days',
                    style: TextStyle(
                        fontSize: 13,
                        color: c.warn,
                        fontWeight: FontWeight.w600)),
              ]),
            ),
          _WardenMenuCard(
              day: day,
              editing: _editVeg,
              vegDraft: _editVeg ? _vegDraft : null,
              onVegEdit: (meal, v) =>
                  setState(() => _vegDraft[day]![meal] = v)),
          const SizedBox(height: 18),
          _WardenDayNvInline(
            day: day,
            onChanged: () => setState(() {}),
            onAddItemDialog: (meal) => _showAddNvDialog(day, meal),
          ),
          const SizedBox(height: 20),
        ]);
  }

  void _showAddNvDialog(String day, String meal) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final c = _C.of(ctx);
          return Dialog(
            backgroundColor: c.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Add Non-Veg Item',
                        style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: c.ink)),
                    const SizedBox(height: 2),
                    Text('$meal  ·  $day',
                        style: TextStyle(fontSize: 13, color: c.textGrey)),
                    const SizedBox(height: 16),
                    TextField(
                      controller: ctrl,
                      autofocus: true,
                      textCapitalization: TextCapitalization.words,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: c.ink),
                      decoration: InputDecoration(
                        hintText: 'e.g., Chicken Curry',
                        hintStyle: TextStyle(
                            color: c.textGrey, fontWeight: FontWeight.w400),
                        filled: true, fillColor: c.blueBg,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 11),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide.none),
                        focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide:
                            BorderSide(color: c.blue, width: 1.5)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(children: [
                      Expanded(child: _OutlineBtn2(
                          label: 'Cancel',
                          onTap: () => Navigator.pop(context))),
                      const SizedBox(width: 10),
                      Expanded(child: _BlueBtn2(
                        label: 'Add',
                        onTap: () async {
                          final v = ctrl.text.trim();
                          if (v.isNotEmpty) {
                            final list = List<String>.from(
                                _Store.i.nvItems(day, meal));
                            if (!list.contains(v)) {
                              list.add(v);
                              await _Store.i.setNvItems(day, meal, list);
                              await _maybeScheduleReminder(day);
                              if (context.mounted) setState(() {});
                            }
                            if (context.mounted) Navigator.pop(context);
                          }
                        },
                      )),
                    ]),
                  ]),
            ),
          );
        },
      ),
    );
  }

  Widget _buildOrdersTab(_C c) {
    final all = _Store.i.bookings;
    if (all.isEmpty) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(
            padding: EdgeInsets.fromLTRB(14, 14, 14, 0),
            child: _WardenQuickStats()),
        Expanded(
            child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.inbox_outlined, size: 48, color: c.blueBorder),
                  const SizedBox(height: 12),
                  Text('No orders yet',
                      style: TextStyle(color: c.textGrey, fontSize: 15)),
                ]))),
      ]);
    }
    final Map<String, List<_Booking>> byItem = {};
    for (final b in all) {
      byItem.putIfAbsent(b.item, () => []).add(b);
    }
    final itemTotals = {
      for (final e in byItem.entries)
        e.key: e.value.fold(0, (s, b) => s + b.qty)
    };
    return ListView(padding: const EdgeInsets.fromLTRB(14, 14, 14, 16), children: [
      const _WardenQuickStats(),
      const SizedBox(height: 18),
      _SectionTitle(title: 'Orders by Item'),
      const SizedBox(height: 10),
      ...byItem.entries.map((entry) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _WardenOrderItemCard(
              item: entry.key,
              total: itemTotals[entry.key]!,
              bookings: entry.value))),
      const SizedBox(height: 16),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WARDEN QUICK STATS
// ─────────────────────────────────────────────────────────────────────────────

class _WardenQuickStats extends StatelessWidget {
  const _WardenQuickStats();
  @override
  Widget build(BuildContext context) {
    final c              = _C.of(context);
    final all            = _Store.i.bookings;
    final totalPlates    = all.fold(0, (s, b) => s + b.qty);
    final uniqueStudents = all.map((b) => b.uid).toSet().length;
    final uniqueItems    = all.map((b) => b.item).toSet().length;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _SectionTitle(title: 'Summary'),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: _StatTile(
            label: 'Total Plates',
            value: '$totalPlates',
            icon: Icons.restaurant_rounded,
            color: c.blue)),
        const SizedBox(width: 10),
        Expanded(child: _StatTile(
            label: 'Students',
            value: '$uniqueStudents',
            icon: Icons.people_rounded,
            color: c.success)),
        const SizedBox(width: 10),
        Expanded(child: _StatTile(
            label: 'Items',
            value: '$uniqueItems',
            icon: Icons.set_meal_rounded,
            color: c.warn)),
      ]),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: c.blueBg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: c.blueBorder)),
        child: Row(children: [
          Icon(Icons.info_outline_rounded, color: c.blue, size: 15),
          const SizedBox(width: 8),
          Expanded(child: Text(
              'Non-veg bookings close at 9:00 AM on the day of the meal.',
              style: TextStyle(
                  fontSize: 12, color: c.blue, fontWeight: FontWeight.w500))),
        ]),
      ),
    ]);
  }
}

class _StatTile extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const _StatTile({
    required this.label, required this.value,
    required this.icon, required this.color,
  });
  @override
  Widget build(BuildContext context) {
    final c = _C.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(c.dark ? 0.12 : 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(c.dark ? 0.25 : 0.2)),
      ),
      child: Column(children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 6),
        Text(value,
            style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.w900, color: color)),
        const SizedBox(height: 2),
        Text(label,
            style: TextStyle(
                fontSize: 11,
                color: c.textGrey,
                fontWeight: FontWeight.w500),
            textAlign: TextAlign.center),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WARDEN ORDER ITEM CARD
// ─────────────────────────────────────────────────────────────────────────────

class _WardenOrderItemCard extends StatefulWidget {
  final String item;
  final int total;
  final List<_Booking> bookings;
  const _WardenOrderItemCard(
      {required this.item, required this.total, required this.bookings});
  @override
  State<_WardenOrderItemCard> createState() => _WardenOrderItemCardState();
}

class _WardenOrderItemCardState extends State<_WardenOrderItemCard> {
  bool _expanded = false;
  @override
  Widget build(BuildContext context) {
    final c = _C.of(context);
    return Container(
      decoration: BoxDecoration(color: c.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: c.divider),
          boxShadow: [BoxShadow(
              color: Colors.black.withOpacity(c.dark ? 0.25 : 0.04),
              blurRadius: 4, offset: const Offset(0, 1))]),
      child: Column(children: [
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
            decoration: BoxDecoration(
              color: _expanded ? c.blueBg : c.white,
              borderRadius: _expanded
                  ? const BorderRadius.vertical(top: Radius.circular(7))
                  : BorderRadius.circular(8),
            ),
            child: Row(children: [
              Container(
                width: 10, height: 10,
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                    color: c.blue, shape: BoxShape.circle),
              ),
              Expanded(child: Text(widget.item,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: c.ink))),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 5),
                decoration: BoxDecoration(color: c.blueBg,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: c.blueBorder)),
                child: Text('${widget.total} Plates',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: c.blue)),
              ),
              const SizedBox(width: 8),
              Icon(
                _expanded
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                color: c.textGrey, size: 20,
              ),
            ]),
          ),
        ),
        if (_expanded) ...[
          Divider(height: 1, color: c.divider),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  Expanded(child: Text('Student',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: c.textGrey))),
                  Text('Roll No',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: c.textGrey)),
                  const SizedBox(width: 48),
                  Text('Qty',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: c.textGrey)),
                ]),
              ),
              ...widget.bookings.map((b) {
                final initial =
                b.name.isNotEmpty ? b.name[0].toUpperCase() : '?';
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(color: c.blueBg,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: c.blueBorder)),
                  child: Row(children: [
                    Container(
                      width: 34, height: 34,
                      decoration: BoxDecoration(
                          color: c.blue.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8)),
                      alignment: Alignment.center,
                      child: Text(initial,
                          style: TextStyle(
                              color: c.blue,
                              fontWeight: FontWeight.w900,
                              fontSize: 14)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(b.name,
                                  style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: c.ink)),
                              const SizedBox(height: 2),
                              Text('${b.rollNo}  ·  ${b.day}  ·  ${b.meal}',
                                  style: TextStyle(
                                      fontSize: 12, color: c.textGrey)),
                            ])),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                          color: c.blueBorder,
                          borderRadius: BorderRadius.circular(6)),
                      child: Text('×${b.qty}',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              color: c.blue)),
                    ),
                  ]),
                );
              }),
            ]),
          ),
        ],
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WARDEN MENU CARD
// ─────────────────────────────────────────────────────────────────────────────

class _WardenMenuCard extends StatelessWidget {
  final String day;
  final bool editing;
  final Map<String, Map<String, String>>? vegDraft;
  final void Function(String, String) onVegEdit;
  const _WardenMenuCard({
    required this.day, required this.editing,
    required this.vegDraft, required this.onVegEdit,
  });

  @override
  Widget build(BuildContext context) {
    final c = _C.of(context);
    return Container(
      decoration: BoxDecoration(color: c.white,
          border: Border.all(color: c.divider),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [BoxShadow(
              color: Colors.black.withOpacity(c.dark ? 0.25 : 0.05),
              blurRadius: 6, offset: const Offset(0, 2))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(color: c.blue,
              borderRadius:
              const BorderRadius.vertical(top: Radius.circular(7))),
          child: Row(children: [
            Text("$day's Menu",
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w700)),
            const Spacer(),
            if (!editing)
              GestureDetector(
                onTap: () {},
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(5)),
                  child: Text('Edit Menu',
                      style: TextStyle(
                          color: c.blue,
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
                ),
              ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
          child: Column(children: _kMeals.asMap().entries.map((e) {
            final mealLabel = _kMealLabels[e.key];
            final meal      = e.value;
            final item      = editing
                ? (vegDraft?[day]?[meal] ?? '')
                : (_Store.i.menu[day]?[meal] ?? '—');
            final nvItems   = _Store.i.nvItems(day, meal);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: editing
                  ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 7, height: 7,
                  margin: const EdgeInsets.only(right: 9, top: 6),
                  decoration: BoxDecoration(
                      color: c.blue, shape: BoxShape.circle),
                ),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('$mealLabel:',
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: c.ink)),
                          const SizedBox(height: 4),
                          TextFormField(
                            initialValue: item,
                            onChanged: (v) => onVegEdit(meal, v),
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: c.blue),
                            decoration: InputDecoration(
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 8),
                              filled: true, fillColor: c.blueBg,
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6),
                                  borderSide: BorderSide.none),
                              focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6),
                                  borderSide: BorderSide(
                                      color: c.blue, width: 1.5)),
                            ),
                          ),
                        ])),
              ])
                  : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(
                  padding: const EdgeInsets.only(top: 6, right: 9),
                  child: Container(
                      width: 7, height: 7,
                      decoration: BoxDecoration(
                          color: c.blue, shape: BoxShape.circle)),
                ),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          RichText(
                              text: TextSpan(
                                  style: TextStyle(
                                      fontSize: 15,
                                      color: c.ink,
                                      height: 1.5),
                                  children: [
                                    TextSpan(
                                        text: '$mealLabel: ',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w700)),
                                    TextSpan(text: item),
                                  ])),
                          if (nvItems.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: RichText(
                                  text: TextSpan(
                                      style: TextStyle(
                                          fontSize: 14,
                                          color: c.ink,
                                          height: 1.5),
                                      children: [
                                        const TextSpan(
                                            text: 'Non-Veg: ',
                                            style: TextStyle(
                                                fontWeight: FontWeight.w700)),
                                        TextSpan(text: nvItems.join(', ')),
                                      ])),
                            ),
                        ])),
              ]),
            );
          }).toList()),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WARDEN INLINE NV
// ─────────────────────────────────────────────────────────────────────────────

class _WardenDayNvInline extends StatelessWidget {
  final String day;
  final VoidCallback onChanged;
  final void Function(String) onAddItemDialog;
  const _WardenDayNvInline({
    required this.day,
    required this.onChanged,
    required this.onAddItemDialog,
  });

  @override
  Widget build(BuildContext context) {
    final c = _C.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: _SectionTitle(title: 'Non-Veg — $day'))
      ]),
      const SizedBox(height: 10),
      ..._kMeals.asMap().entries.map((entry) {
        final mIdx  = entry.key;
        final meal  = entry.value;
        final items  = _Store.i.nvItems(day, meal);
        final counts = _Store.i.itemCounts(day, meal);
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(color: c.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: c.divider)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: c.blueBg,
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(7))),
              child: Row(children: [
                Text(_kMealEmoji[mIdx],
                    style: const TextStyle(fontSize: 15)),
                const SizedBox(width: 8),
                Text(_kMealLabels[mIdx],
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: c.ink)),
                const Spacer(),
                GestureDetector(
                  onTap: () => onAddItemDialog(meal),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                        color: c.blue,
                        borderRadius: BorderRadius.circular(6)),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.add_rounded, size: 13, color: Colors.white),
                      SizedBox(width: 4),
                      Text('Add Item',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Colors.white)),
                    ]),
                  ),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: items.isEmpty
                  ? Row(children: [
                Icon(Icons.add_circle_outline_rounded,
                    size: 15, color: c.blueBorder),
                const SizedBox(width: 8),
                Text('No items yet — tap Add Item to schedule',
                    style: TextStyle(
                        fontSize: 13,
                        color: c.textGrey,
                        fontWeight: FontWeight.w400)),
              ])
                  : Column(
                  children: items
                      .map((item) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(children: [
                      Container(
                        width: 8, height: 8,
                        margin: const EdgeInsets.only(right: 10),
                        decoration: BoxDecoration(
                            color: c.blue,
                            shape: BoxShape.circle),
                      ),
                      Expanded(child: Text(item,
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: c.ink))),
                      if ((counts[item] ?? 0) > 0)
                        Container(
                          margin:
                          const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                              color: c.dangerLight,
                              borderRadius:
                              BorderRadius.circular(5)),
                          child: Text(
                              '${counts[item]} orders',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: c.danger,
                                  fontWeight:
                                  FontWeight.w700)),
                        ),
                      GestureDetector(
                        onTap: () async {
                          final list = List<String>.from(
                              _Store.i.nvItems(day, meal));
                          list.remove(item);
                          await _Store.i
                              .setNvItems(day, meal, list);
                          await _maybeScheduleReminder(day);
                          onChanged();
                        },
                        child: Container(
                          width: 28, height: 28,
                          decoration: BoxDecoration(
                              color: c.dangerLight,
                              borderRadius:
                              BorderRadius.circular(6)),
                          child: Icon(
                              Icons.delete_outline_rounded,
                              size: 15,
                              color: c.danger),
                        ),
                      ),
                    ]),
                  ))
                      .toList()),
            ),
          ]),
        );
      }).toList(),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SHARED SMALL WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle({required this.title});
  @override
  Widget build(BuildContext context) {
    final c = _C.of(context);
    return Text(title,
        style: TextStyle(
            fontSize: 17, fontWeight: FontWeight.w800, color: c.blue));
  }
}

class _BlueBtn2 extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _BlueBtn2({required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final c = _C.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 42,
        decoration: BoxDecoration(
            color: c.blue, borderRadius: BorderRadius.circular(8)),
        alignment: Alignment.center,
        child: Text(label,
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 15)),
      ),
    );
  }
}

class _OutlineBtn2 extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _OutlineBtn2({required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final c = _C.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 42,
        decoration: BoxDecoration(
            color: c.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: c.blueBorder, width: 1.5)),
        alignment: Alignment.center,
        child: Text(label,
            style: TextStyle(
                color: c.blue,
                fontWeight: FontWeight.w700,
                fontSize: 15)),
      ),
    );
  }
}