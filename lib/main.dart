import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// Screens
import 'screens/notification_service.dart';
import 'screens/login_page.dart';
import 'screens/student_dashboard.dart';
import 'screens/male_student_dashboard.dart';
import 'screens/warden_dashboard.dart';
import 'screens/tutor_dashboard.dart';
import 'screens/admin_dashboard.dart';
import 'firebase_options.dart';

// ── Global navigator key (needed for notification navigation) ─────────────────
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// ── Global notifiers ─────────────────────────────────────────────────────────
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.light);
final ValueNotifier<double> fontSizeNotifier = ValueNotifier(14.0);

// ── Background FCM handler (MUST be top-level, not inside any class) ──────────
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  print("Background message received: ${message.data}");
  await NotificationService.instance.showNotificationFromData(message.data);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Register background message handler
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  // Print FCM token to console for debugging
  FirebaseMessaging.instance.getToken().then((token) {
    print("FCM Token: $token");
  });

  // Handle foreground messages
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    print("Foreground message received: ${message.data}");
    NotificationService.instance.showNotificationFromData(message.data);
  });

  // Handle notification tap when app is in background (not terminated)
  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
    print("Notification tapped (background): ${message.data}");
  });

  // Handle notification tap when app was terminated
  FirebaseMessaging.instance.getInitialMessage().then((RemoteMessage? message) {
    if (message != null) {
      print("Notification tapped (terminated): ${message.data}");
    }
  });

  await NotificationService.instance.init();

  // ✅ IMPORTANT: saveTokenToFirestore() is now called inside login_page.dart
  // right after a successful login/signup, NOT here in main().
  //
  // Calling it here runs before the user is authenticated (uid == null),
  // so it would silently return without saving anything — which was the
  // original bug causing push notifications to not work.
  //
  // It is also called in signup_page.dart after account creation,
  // which handles brand-new users on first install.

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (_, themeMode, __) {
        return ValueListenableBuilder<double>(
          valueListenable: fontSizeNotifier,
          builder: (_, fontSize, __) {
            return MaterialApp(
              navigatorKey: navigatorKey,
              debugShowCheckedModeBanner: false,
              title: 'Hostel Management',
              themeMode: themeMode,

              theme: ThemeData(
                primarySwatch: Colors.blue,
                scaffoldBackgroundColor: Colors.white,
                cardColor: Colors.white,
                textTheme: _buildTextTheme(fontSize, Brightness.light),
              ),

              darkTheme: ThemeData(
                brightness: Brightness.dark,
                primarySwatch: Colors.blue,
                textTheme: _buildTextTheme(fontSize, Brightness.dark),
              ),

              home: StreamBuilder<User?>(
                stream: FirebaseAuth.instance.authStateChanges(),
                initialData: FirebaseAuth.instance.currentUser,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting &&
                      snapshot.data == null) {
                    return const Scaffold(
                      body: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (snapshot.hasData && snapshot.data != null) {
                    // ✅ User is already logged in (returning user / app restart).
                    // Save/refresh their FCM token now that we know who they are.
                    NotificationService.saveTokenToFirestore();
                    return const RoleBasedRedirect();
                  }
                  return const LoginPage();
                },
              ),

              routes: {
                '/login': (context) => const LoginPage(),
                '/studentDashboard': (context) => const StudentDashboard(),
              },
            );
          },
        );
      },
    );
  }

  TextTheme _buildTextTheme(double fontSize, Brightness brightness) {
    final baseColor =
    brightness == Brightness.dark ? Colors.white : Colors.black87;
    return TextTheme(
      bodyLarge: TextStyle(fontSize: fontSize + 2, color: baseColor),
      bodyMedium: TextStyle(fontSize: fontSize, color: baseColor),
      bodySmall: TextStyle(fontSize: fontSize - 2, color: baseColor),
      titleMedium: TextStyle(
          fontSize: fontSize + 1,
          fontWeight: FontWeight.w600,
          color: baseColor),
    );
  }
}

// ── Role-based redirect ───────────────────────────────────────────────────────
class RoleBasedRedirect extends StatelessWidget {
  const RoleBasedRedirect({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const LoginPage();

    final email = user.email?.toLowerCase() ?? '';

    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return const LoginPage();
        }

        final userData = snapshot.data!.data() as Map<String, dynamic>;
        final String? gender = userData['gender'];

        if (email == 'admin@gmail.com') return const AdminDashboard();

        final studentPattern = RegExp(r'^(\d{2})\d{5}@nec\.edu\.in$');
        final studentMatch = studentPattern.firstMatch(email);
        if (studentMatch != null) {
          final batchYearPrefix = studentMatch.group(1);
          if (batchYearPrefix != null) {
            final batchYear = 2000 + int.parse(batchYearPrefix);
            final currentYear = DateTime.now().year;
            final currentMonth = DateTime.now().month;
            final expiryYear = batchYear + 4;

            if (currentYear > expiryYear ||
                (currentYear == expiryYear && currentMonth > 4)) {
              FirebaseAuth.instance.signOut();
              return const LoginPage();
            }

            if (gender == 'Male') return const MaleStudentDashboard();
            if (gender == 'Female') return const StudentDashboard();
          }
        }

        if (email.contains('warden')) return const WardenDashboard();

        final tutorKeywords = ['cse', 'it', 'aids', 'ece', 'eee', 'mech', 'civil'];
        if (tutorKeywords.any((keyword) => email.contains(keyword))) {
          return const TutorDashboard();
        }

        FirebaseAuth.instance.signOut();
        return const LoginPage();
      },
    );
  }
}