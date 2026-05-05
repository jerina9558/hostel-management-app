// lib/screens/student_notification_listener.dart
//
// Responsibilities:
//   • Request notification permission (iOS + Android 13+)
//   • Initialise flutter_local_notifications
//   • Handle FCM foreground / background / terminated messages
//   • Provide helpers: showLocal(), cancelById(), cancelAll()
//   • StudentNotificationListener: starts/stops Firestore listeners for a student
// ─────────────────────────────────────────────────────────────────────────

import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// ── Background handler (top-level, outside any class) ────────────────────
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  final uid = message.data['toUid'] ?? '';
  int badgeCount = 1;
  if (uid.isNotEmpty) {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('notifications')
          .doc(uid)
          .collection('items')
          .where('seen', isEqualTo: false)
          .count()
          .get();
      badgeCount = snap.count ?? 1;
    } catch (_) {}
  }
  await NotificationService.instance._showFromRemoteWithBadge(
      message, badgeCount);
}

// ─────────────────────────────────────────────────────────────────────────
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final _fcm   = FirebaseMessaging.instance;
  final _local = FlutterLocalNotificationsPlugin();

  // Android notification channel
  static const _channelId   = 'hostel_main';
  static const _channelName = 'Hostel Notifications';
  static const _channelDesc = 'All hostel app notifications';

  // ── Notification IDs (used to cancel specific categories) ────────────
  static const int idAnnouncement   = 1000;
  static const int idEvent          = 2000;
  static const int idGatePass       = 3000;
  static const int idPermission     = 4000;
  static const int idComplaint      = 5000;
  static const int idMessMenu       = 6000;

  // ── init ──────────────────────────────────────────────────────────────
  Future<void> init() async {
    // 1. Request permission
    await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // 2. Android channel
    const androidChannel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDesc,
      importance: Importance.high,
    );

    await _local
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);

    // 3. iOS foreground options
    await _fcm.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    // 4. Init flutter_local_notifications
    const androidSettings =
    AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _local.initialize(
      const InitializationSettings(
          android: androidSettings, iOS: iosSettings),
      onDidReceiveNotificationResponse: _onLocalTap,
    );

    // 5. Background / terminated handler
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // 6. Foreground handler
    FirebaseMessaging.onMessage.listen(_showFromRemote);

    // 7. Opened-from-notification handler (app in background, user taps)
    FirebaseMessaging.onMessageOpenedApp.listen(_handleOpenedMessage);

    // 8. Check if app was launched from a notification (terminated state)
    final initial = await _fcm.getInitialMessage();
    if (initial != null) _handleOpenedMessage(initial);
  }

  // ── Show a local notification from an FCM RemoteMessage ──────────────
  Future<void> _showFromRemote(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;
    final uid = message.data['toUid'] ?? _studentNotificationListenerUid;
    int badgeCount = 1;
    if (uid.isNotEmpty) {
      try {
        final snap = await FirebaseFirestore.instance
            .collection('notifications')
            .doc(uid)
            .collection('items')
            .where('seen', isEqualTo: false)
            .count()
            .get();
        badgeCount = snap.count ?? 1;
      } catch (_) {}
    }
    await _showFromRemoteWithBadge(message, badgeCount);
  }

  Future<void> _showFromRemoteWithBadge(
      RemoteMessage message, int badgeCount) async {
    final notification = message.notification;
    if (notification == null) return;

    final title = notification.title ?? '';
    final body  = notification.body  ?? '';
    final type  = message.data['type'] ?? '';

    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.high,
      priority:   Priority.high,
      number: badgeCount,
      styleInformation: BigTextStyleInformation(body),
    );

    final iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      badgeNumber: badgeCount,
    );

    await _local.show(
      _idForType(type),
      title,
      body,
      NotificationDetails(android: androidDetails, iOS: iosDetails),
      payload: type,
    );
  }

  // ── Show a local notification directly (called by listeners too) ──────
  Future<void> showLocal({
    required int    id,
    required String title,
    required String body,
    String payload = '',
    String? studentId, // pass this to get live unseen count
  }) async {
    // ── Get unseen count for badge ──────────────────────────────────
    int badgeCount = 1;
    final sid = studentId ?? _studentNotificationListenerUid;
    if (sid.isNotEmpty) {
      try {
        final snap = await FirebaseFirestore.instance
            .collection('notifications')
            .doc(sid)
            .collection('items')
            .where('seen', isEqualTo: false)
            .count()
            .get();
        badgeCount = (snap.count ?? 1);
      } catch (_) {}
    }
    // ───────────────────────────────────────────────────────────────

    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.high,
      priority:   Priority.high,
      number: badgeCount, // ← shows count on Android app icon (launcher badge)
      styleInformation: BigTextStyleInformation(body),
    );

    final iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      badgeNumber: badgeCount, // ← shows count on iOS app icon
    );

    await _local.show(
      id,
      title,
      body,
      NotificationDetails(android: androidDetails, iOS: iosDetails),
      payload: payload,
    );
  }

  // ── Internal uid store so showLocal can access it without params ──
  String _studentNotificationListenerUid = '';

  // ── Cancel helpers ────────────────────────────────────────────────────
  Future<void> cancelById(int id) => _local.cancel(id);
  Future<void> cancelAll()        => _local.cancelAll();

  // ── Map notification type string → stable ID ─────────────────────────
  int _idForType(String type) {
    switch (type) {
      case 'announcement': return idAnnouncement;
      case 'event':        return idEvent;
      case 'gatepass':     return idGatePass;
      case 'permission':   return idPermission;
      case 'complaint':    return idComplaint;
      case 'mess_menu':    return idMessMenu;
      default:             return DateTime.now().millisecondsSinceEpoch ~/ 1000;
    }
  }

  // ── Handle tap on notification ────────────────────────────────────────
  void _onLocalTap(NotificationResponse response) {
    // TODO: Navigate to the relevant screen based on response.payload
  }

  void _handleOpenedMessage(RemoteMessage message) {
    // TODO: Navigate based on message.data['type']
  }

  // ── FCM token (send this to your backend / Firestore) ────────────────
  Future<String?> getToken() => _fcm.getToken();
}

// ─────────────────────────────────────────────────────────────────────────
// STUDENT NOTIFICATION LISTENER
// Starts Firestore real-time listeners for a student and shows local
// notifications when documents change. Call start() on login and
// dispose() on logout or when notifications are disabled.
// ─────────────────────────────────────────────────────────────────────────
class StudentNotificationListener {
  StudentNotificationListener._();
  static final StudentNotificationListener instance =
  StudentNotificationListener._();

  bool _isRunning = false;
  String _studentId = '';
  String _hostelId  = '';

  // Active Firestore subscriptions
  final List<dynamic> _subscriptions = [];

  Future<void> start({
    required String studentId,
    required String hostelId,
  }) async {
    if (_isRunning) return;
    _isRunning  = true;
    _studentId  = studentId;
    _hostelId   = hostelId;
    // Give NotificationService access to uid for badge counts
    NotificationService.instance._studentNotificationListenerUid = studentId;

    _listenToAnnouncements();
    _listenToGatePasses();
    _listenToPermissions();
    _listenToComplaints();
  }

  // ── Announcements ─────────────────────────────────────────────────────
  void _listenToAnnouncements() {
    if (_hostelId.isEmpty) return;
    final sub = FirebaseFirestore.instance
        .collection('hostels')
        .doc(_hostelId)
        .collection('announcements')
        .orderBy('createdAt', descending: true)
        .limit(1)
        .snapshots()
        .listen((snap) {
      if (snap.docs.isEmpty) return;
      final doc = snap.docs.first;
      // Only notify on new documents (not on initial load)
      final md = doc.metadata;
      if (md.hasPendingWrites) return;
      final data  = doc.data();
      final title = data['title'] as String? ?? 'New Announcement';
      final body  = data['body']  as String? ?? '';
      NotificationService.instance.showLocal(
        id:      NotificationService.idAnnouncement,
        title:   title,
        body:    body,
        payload: 'announcement',
      );
    });
    _subscriptions.add(sub);
  }

  // ── Gate passes ───────────────────────────────────────────────────────
  void _listenToGatePasses() {
    if (_studentId.isEmpty) return;
    final sub = FirebaseFirestore.instance
        .collection('gatePasses')
        .where('studentId', isEqualTo: _studentId)
        .snapshots()
        .listen((snap) {
      for (final change in snap.docChanges) {
        if (change.type == DocumentChangeType.modified) {
          final data   = change.doc.data()!;
          final status = data['status'] as String? ?? '';
          NotificationService.instance.showLocal(
            id:      NotificationService.idGatePass,
            title:   'Gate Pass $status',
            body:    'Your gate pass has been $status.',
            payload: 'gatepass',
          );
        }
      }
    });
    _subscriptions.add(sub);
  }

  // ── Permission / leave requests ───────────────────────────────────────
  void _listenToPermissions() {
    if (_studentId.isEmpty) return;
    final sub = FirebaseFirestore.instance
        .collection('permissions')
        .where('studentId', isEqualTo: _studentId)
        .snapshots()
        .listen((snap) {
      for (final change in snap.docChanges) {
        if (change.type == DocumentChangeType.modified) {
          final data   = change.doc.data()!;
          final status = data['status'] as String? ?? '';
          NotificationService.instance.showLocal(
            id:      NotificationService.idPermission,
            title:   'Permission Request $status',
            body:    'Your leave request has been $status.',
            payload: 'permission',
          );
        }
      }
    });
    _subscriptions.add(sub);
  }

  // ── Complaints ────────────────────────────────────────────────────────
  void _listenToComplaints() {
    if (_studentId.isEmpty) return;
    final sub = FirebaseFirestore.instance
        .collection('complaints')
        .where('studentId', isEqualTo: _studentId)
        .snapshots()
        .listen((snap) {
      for (final change in snap.docChanges) {
        if (change.type == DocumentChangeType.modified) {
          final data   = change.doc.data()!;
          final status = data['status'] as String? ?? 'updated';
          NotificationService.instance.showLocal(
            id:      NotificationService.idComplaint,
            title:   'Complaint Update',
            body:    'Your complaint status has been updated to: $status.',
            payload: 'complaint',
          );
        }
      }
    });
    _subscriptions.add(sub);
  }

  // ── Dispose: cancel all subscriptions ────────────────────────────────
  Future<void> dispose() async {
    if (!_isRunning) return;
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    _subscriptions.clear();
    _isRunning = false;
    _studentId = '';
    _hostelId  = '';
  }
}