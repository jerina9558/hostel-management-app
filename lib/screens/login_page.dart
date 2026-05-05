import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'signup_page.dart';
import 'student_dashboard.dart';
import 'male_student_dashboard.dart';
import 'warden_dashboard.dart';
import 'tutor_dashboard.dart';
import 'admin_dashboard.dart';
import 'notification_service.dart'; // ✅ ADDED

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State createState() => _LoginPageState();
}

class _LoginPageState extends State {
  final _formKey = GlobalKey<FormState>();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  bool isLoading = false;
  bool _obscurePassword = true;

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;

  Future<void> signInWithGoogle() async {
    try {
      setState(() => isLoading = true);
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        setState(() => isLoading = false);
        return;
      }
      final GoogleSignInAuthentication googleAuth =
      await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      UserCredential userCredential =
      await FirebaseAuth.instance.signInWithCredential(credential);
      final user = userCredential.user;
      if (user != null) {
        // ✅ Save FCM token after Google sign-in
        await NotificationService.saveTokenToFirestore();

        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const StudentDashboard()),
        );
      }
      setState(() => isLoading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() => isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Google Sign-In Failed")),
      );
    }
  }

  Future<void> login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => isLoading = true);
    try {
      final email = emailController.text.trim().toLowerCase();
      final password = passwordController.text.trim();

      UserCredential userCredential =
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final uid = userCredential.user!.uid;

      // ✅ Save FCM token right after successful login — this handles:
      //   • existing users who signed up before FCM was added
      //   • token refreshes (device reinstall, app clear, etc.)
      await NotificationService.saveTokenToFirestore();

      DocumentSnapshot userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();

      if (!mounted) return;

      if (!userDoc.exists) {
        setState(() => isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("User data not found")),
        );
        return;
      }

      final userData = userDoc.data() as Map<String, dynamic>;
      final String? gender = userData['gender'];

      setState(() => isLoading = false);

      if (email == "admin@gmail.com") {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const AdminDashboard()),
        );
        return;
      }

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
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Your student ID has expired")),
            );
            return;
          }

          if (gender == 'Male') {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const MaleStudentDashboard()),
            );
          } else if (gender == 'Female') {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const StudentDashboard()),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Gender not set properly")),
            );
          }
          return;
        }
      }

      if (email.contains("warden")) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const WardenDashboard()),
        );
        return;
      }

      final tutorKeywords = ["cse", "it", "aids", "ece", "eee", "mech", "civil"];
      if (tutorKeywords.any((keyword) => email.contains(keyword))) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const TutorDashboard()),
        );
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Role not recognized")),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? "Login failed")),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Something went wrong")),
      );
    }
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  InputDecoration _fieldDecoration({
    required String hint,
    required IconData icon,
    Widget? suffixIcon,
  }) {
    final dark = _isDark;
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(
          color: dark ? Colors.white.withOpacity(0.38) : const Color(0xFFBDBDBD),
          fontSize: 14),
      prefixIcon: Icon(icon,
          color: dark ? Colors.white.withOpacity(0.38) : const Color(0xFFBDBDBD),
          size: 20),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: dark ? const Color(0xFF2C2C2C) : const Color(0xFFF0F3FF),
      contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: dark
            ? const BorderSide(color: Color(0x1FFFFFFF))
            : BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(
            color: dark ? const Color(0xFF4A9EDB) : const Color(0xFF1976D2),
            width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Colors.red, width: 1),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Colors.red, width: 1.5),
      ),
    );
  }

  Widget _fieldLabel(String text) {
    final dark = _isDark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: dark
              ? Colors.white.withOpacity(0.87)
              : const Color(0xFF212121),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = _isDark;
    final primaryBlue =
    dark ? const Color(0xFF4A9EDB) : const Color(0xFF1976D2);
    final headerBlue =
    dark ? const Color(0xFF0D2A45) : const Color(0xFF1976D2);
    final scaffoldBg =
    dark ? const Color(0xFF121212) : const Color(0xFFEEEFF4);
    final cardBg = dark ? const Color(0xFF1E1E1E) : Colors.white;

    return Scaffold(
      backgroundColor: scaffoldBg,
      body: Stack(
        children: [
          Container(
            height: MediaQuery.of(context).size.height * 0.38,
            width: double.infinity,
            color: headerBlue,
          ),
          SafeArea(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Welcome Back!',
                          style: TextStyle(
                            color: dark
                                ? Colors.white.withOpacity(0.54)
                                : Colors.white.withOpacity(0.70),
                            fontSize: 16,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Login',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 34,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Login to continue',
                          style: TextStyle(
                            color: dark
                                ? Colors.white.withOpacity(0.54)
                                : Colors.white.withOpacity(0.70),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: dark
                                ? Colors.black.withOpacity(0.4)
                                : Colors.black.withOpacity(0.08),
                            blurRadius: 20,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(24),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _fieldLabel('Email Address'),
                            TextFormField(
                              controller: emailController,
                              keyboardType: TextInputType.emailAddress,
                              style: TextStyle(
                                color: dark
                                    ? Colors.white.withOpacity(0.87)
                                    : Colors.black.withOpacity(0.87),
                              ),
                              decoration: _fieldDecoration(
                                hint: 'your.email@example.com',
                                icon: Icons.mail_outline,
                              ),
                              validator: (v) => v != null && v.contains("@")
                                  ? null
                                  : "Invalid email",
                            ),
                            const SizedBox(height: 20),
                            _fieldLabel('Password'),
                            TextFormField(
                              controller: passwordController,
                              obscureText: _obscurePassword,
                              style: TextStyle(
                                color: dark
                                    ? Colors.white.withOpacity(0.87)
                                    : Colors.black.withOpacity(0.87),
                              ),
                              decoration: _fieldDecoration(
                                hint: 'Enter your password',
                                icon: Icons.lock_outline,
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                    color: dark
                                        ? Colors.white.withOpacity(0.38)
                                        : const Color(0xFFBDBDBD),
                                    size: 20,
                                  ),
                                  onPressed: () => setState(
                                          () => _obscurePassword = !_obscurePassword),
                                ),
                              ),
                              validator: (v) => v != null && v.length >= 6
                                  ? null
                                  : "Min 6 characters",
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              height: 52,
                              child: ElevatedButton(
                                onPressed: isLoading ? null : login,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: primaryBlue,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  elevation: 0,
                                ),
                                child: isLoading
                                    ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2.5,
                                  ),
                                )
                                    : const Text(
                                  'Login',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                            Row(
                              children: [
                                Expanded(
                                    child: Divider(
                                        color: dark
                                            ? const Color(0x1FFFFFFF)
                                            : Colors.grey[300],
                                        thickness: 1)),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16),
                                  child: Text(
                                    'Or',
                                    style: TextStyle(
                                      color: dark
                                          ? Colors.white.withOpacity(0.38)
                                          : Colors.grey[500],
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                Expanded(
                                    child: Divider(
                                        color: dark
                                            ? const Color(0x1FFFFFFF)
                                            : Colors.grey[300],
                                        thickness: 1)),
                              ],
                            ),
                            const SizedBox(height: 20),
                            SizedBox(
                              width: double.infinity,
                              height: 52,
                              child: OutlinedButton.icon(
                                onPressed: isLoading ? null : signInWithGoogle,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: dark
                                      ? Colors.white.withOpacity(0.87)
                                      : Colors.black.withOpacity(0.87),
                                  side: BorderSide(
                                      color: dark
                                          ? const Color(0x1FFFFFFF)
                                          : Colors.grey[300]!),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  backgroundColor: dark
                                      ? const Color(0xFF2C2C2C)
                                      : Colors.white,
                                ),
                                icon: Image.asset(
                                  'assets/google_logo.png',
                                  height: 20,
                                  width: 20,
                                  errorBuilder: (context, error, stackTrace) {
                                    return const Icon(
                                      Icons.g_mobiledata,
                                      size: 24,
                                      color: Color(0xFF4285F4),
                                    );
                                  },
                                ),
                                label: const Text(
                                  'Continue with Google',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        "Don't have an account? ",
                        style: TextStyle(
                          color: dark
                              ? Colors.white.withOpacity(0.54)
                              : Colors.grey[700],
                          fontSize: 14,
                        ),
                      ),
                      GestureDetector(
                        onTap: () => Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(builder: (_) => SignupPage()),
                        ),
                        child: Text(
                          'Sign Up',
                          style: TextStyle(
                            color: primaryBlue,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}