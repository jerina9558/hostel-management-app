// lib/screens/notification_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hostel_management_app/firebase_options.dart';
import 'package:hostel_management_app/main.dart' show navigatorKey;
import 'mess_menu.dart';
import 'student_dashboard.dart';

// ─────────────────────────────────────────────────────────────────────────────
// TOP-LEVEL BACKGROUND HANDLER
// Firebase MUST be initialized here before any Firestore/Auth call.
// Now calls showNotificationFromData() directly instead of showIfAllowed().
// ─────────────────────────────────────────────────────────────────────────────
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  print("Background message received: ${message.data}");

  await NotificationService.instance.showNotificationFromData(message.data);
}

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final _fcm   = FirebaseMessaging.instance;
  final _local = FlutterLocalNotificationsPlugin();

  static const _channelId   = 'hostel_main';
  static const _channelName = 'Hostel Notifications';
  static const _channelDesc = 'All hostel app notifications';

  // ── Notification IDs — one per feature so they replace (not stack) ────────
  static const int idAnnouncement = 1000;
  static const int idEvent        = 2000;
  static const int idGatePass     = 3000;
  static const int idPermission   = 4000;
  static const int idComplaint    = 5000;
  static const int idMessMenu     = 6000;

  // ── Maps FCM message data['type'] → SharedPreferences / Firestore key ─────
  static const Map<String, String> _typeToPrefKey = {
    // Student
    'announcement' : 'announcement_notifications',
    'event'        : 'event_notifications',
    'gatepass'     : 'gatepass_notifications',
    'permission'   : 'permission_status_notifications',
    'complaint'    : 'complaint_updates',
    'mess_menu'    : 'mess_menu_notifications',
    // Tutor
    'tutor_permission' : 'tutor_new_permission_request',
    'tutor_gatepass'   : 'tutor_gatepass_alert',
    'tutor_reminder'   : 'tutor_permission_reminder',
    // Warden
    'warden_gatepass'     : 'warden_gatepass_request',
    'warden_permission'   : 'warden_permission_notif',
    'warden_complaint'    : 'warden_complaint_notif',
    'warden_announcement' : 'warden_announcement_confirm',
    // Admin
    'admin_system'   : 'admin_system_alerts',
    'admin_report'   : 'admin_report_ready',
    'admin_new_user' : 'admin_new_user_notif',
  };

  // ─────────────────────────────────────────────────────────────────────────
  // INIT — call once from main() before runApp()
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> init() async {
    // 1. Request Android 13+ / iOS permission
    await _fcm.requestPermission(alert: true, badge: true, sound: true);

    // 2. Create Android notification channel
    const androidChannel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDesc,
      importance: Importance.high,
      playSound: true,
    );
    await _local
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);

    // 3. Initialise flutter_local_notifications (Android + iOS)
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');

    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    await _local.initialize(
      const InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      ),
      onDidReceiveNotificationResponse: _onLocalTap,
    );

    // 4. Register background/terminated handler (top-level function)
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // 5. FOREGROUND: FCM arrives while app is open
    //    → logs the data AND shows the notification via showNotificationFromData
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      print("Foreground message: ${message.data}");
      await showNotificationFromData(message.data);
    });

    // 6. User taps a notification while app is backgrounded (not killed)
    FirebaseMessaging.onMessageOpenedApp.listen(_handleOpenedMessage);

    // 7. User taps a notification that cold-starts the app from killed state
    final initial = await _fcm.getInitialMessage();
    if (initial != null) _handleOpenedMessage(initial);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // showNotificationFromData — NEW METHOD
  // Called directly from:
  //   • foreground listener (onMessage)
  //   • background handler (firebaseMessagingBackgroundHandler)
  //   • any widget's initState via:
  //       FirebaseMessaging.onMessage.listen((msg) {
  //         NotificationService.instance.showNotificationFromData(msg.data);
  //       });
  //
  // Reads title/body from data map first, then falls back to notification block.
  // Does NOT check user preferences — use showIfAllowed() if you need that.
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> showNotificationFromData(Map<String, dynamic> data) async {
    final String type  = data['type']  as String? ?? '';
    final String title = (data['title'] as String? ?? '').isNotEmpty
        ? data['title'] as String
        : '';
    final String body  = (data['body']  as String? ?? '').isNotEmpty
        ? data['body'] as String
        : '';

    if (title.isEmpty && body.isEmpty) {
      debugPrint('[NotifService] showNotificationFromData: no title/body, skipping.');
      return;
    }

    debugPrint('[NotifService] showNotificationFromData — type: "$type", title: "$title"');

    await showLocal(
      id:      _idForType(type),
      title:   title,
      body:    body,
      payload: type,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CORE — check user preferences THEN show (respects per-type settings)
  // Use this if you want preference-gated notifications.
  // showNotificationFromData() bypasses preferences for simplicity.
  // ─────────────────────────────────────────────────────────────────────────

  /// [fromBackground] = false → foreground  → read SharedPreferences (fast)
  /// [fromBackground] = true  → bg/killed   → read Firestore (SP unavailable)
  Future<void> showIfAllowed({
    required RemoteMessage message,
    required bool fromBackground,
  }) async {
    final type    = message.data['type'] as String? ?? '';
    final prefKey = _typeToPrefKey[type];

    bool masterEnabled = true;
    bool typeEnabled   = true;

    if (fromBackground) {
      // ── Background / Terminated: SharedPreferences is NOT available ───────
      String? uid = FirebaseAuth.instance.currentUser?.uid;

      if (uid == null) {
        try {
          final prefs = await SharedPreferences.getInstance();
          uid = prefs.getString('logged_in_uid');
        } catch (_) {}
      }

      if (uid != null) {
        try {
          final doc = await FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .collection('settings')
              .doc('notifications')
              .get();

          if (doc.exists) {
            final data = doc.data() ?? {};
            masterEnabled = (data['push_notifications'] as bool?) ?? true;
            if (prefKey != null) {
              typeEnabled = (data[prefKey] as bool?) ?? true;
            }
          }
        } catch (e) {
          debugPrint('[NotifService] Firestore settings read error: $e');
        }
      }
    } else {
      // ── Foreground: read from SharedPreferences ───────────────────────────
      try {
        final prefs   = await SharedPreferences.getInstance();
        masterEnabled = prefs.getBool('push_notifications') ?? true;
        if (prefKey != null) {
          typeEnabled = prefs.getBool(prefKey) ?? true;
        }
      } catch (e) {
        debugPrint('[NotifService] SharedPreferences read error: $e');
      }
    }

    if (!masterEnabled || !typeEnabled) {
      debugPrint('[NotifService] Suppressed — type: "$type" | '
          'master: $masterEnabled | typeEnabled: $typeEnabled');
      return;
    }

    final title = (message.data['title'] as String? ?? '').isNotEmpty
        ? message.data['title'] as String
        : message.notification?.title ?? '';
    final body  = (message.data['body'] as String? ?? '').isNotEmpty
        ? message.data['body'] as String
        : message.notification?.body ?? '';

    if (title.isEmpty && body.isEmpty) return;

    await showLocal(
      id:      _idForType(type),
      title:   title,
      body:    body,
      payload: type,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SHOW LOCAL NOTIFICATION
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> showLocal({
    required int    id,
    required String title,
    required String body,
    String          payload = '',
  }) async {
    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance:        Importance.high,
      priority:          Priority.high,
      styleInformation:  BigTextStyleInformation(body),
      icon:              '@mipmap/ic_launcher',
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    await _local.show(
      id,
      title,
      body,
      NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      ),
      payload: payload,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // FCM TOKEN — save & auto-refresh
  // ─────────────────────────────────────────────────────────────────────────
  static Future<void> saveTokenToFirestore() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('logged_in_uid', uid);

      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;

      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .set({'fcmToken': token}, SetOptions(merge: true));

      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
        FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .set({'fcmToken': newToken}, SetOptions(merge: true));
        debugPrint('[NotifService] FCM token refreshed: $newToken');
      });

      debugPrint('[NotifService] FCM token saved: $token');
    } catch (e) {
      debugPrint('[NotifService] saveTokenToFirestore error: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // DEFAULT PREFS DOC — call right after login
  // ─────────────────────────────────────────────────────────────────────────
  static Future<void> initDefaultNotifPrefs() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('settings')
          .doc('notifications')
          .set({'push_notifications': true}, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[NotifService] initDefaultNotifPrefs error: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CANCEL
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> cancelById(int id) => _local.cancel(id);
  Future<void> cancelAll()        => _local.cancelAll();
  Future<String?> getToken()      => _fcm.getToken();

  // ─────────────────────────────────────────────────────────────────────────
  // HELPERS
  // ─────────────────────────────────────────────────────────────────────────
  int _idForType(String type) {
    switch (type) {
      case 'announcement':
      case 'warden_announcement': return idAnnouncement;
      case 'event':               return idEvent;
      case 'gatepass':
      case 'tutor_gatepass':
      case 'warden_gatepass':     return idGatePass;
      case 'permission':
      case 'tutor_permission':
      case 'warden_permission':   return idPermission;
      case 'complaint':
      case 'warden_complaint':    return idComplaint;
      case 'mess_menu':           return idMessMenu;
      default:
        return DateTime.now().millisecondsSinceEpoch ~/ 1000;
    }
  }

  void _onLocalTap(NotificationResponse response) {
    _navigate(response.payload ?? '');
  }

  void _handleOpenedMessage(RemoteMessage message) {
    _navigate(message.data['type'] as String? ?? '');
  }

  void _navigate(String type) {
    Future.delayed(const Duration(milliseconds: 500), () {
      final nav = navigatorKey.currentState;
      if (nav == null) return;

      switch (type) {
        case 'mess_menu':
          nav.push(MaterialPageRoute(
              builder: (_) => const MessMenuStudentPage()));
          break;
        default:
          nav.popUntil((route) => route.isFirst);
          break;
      }
    });
  }
}