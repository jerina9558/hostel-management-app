import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'student_dashboard.dart';
import 'male_student_dashboard.dart';
import 'warden_dashboard.dart';
import 'tutor_dashboard.dart';
import 'admin_dashboard.dart';
import 'login_page.dart';

class RoleCheckPage extends StatelessWidget {
  const RoleCheckPage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const LoginPage();
    }

    return FutureBuilder(
      future: FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }

        final data = snapshot.data!;
        final email = user.email ?? "";
        final gender = data['gender'];

        // Admin
        if (email == "admin@gmail.com") {
          return const AdminDashboard();
        }

        // Student
        if (email.contains("@nec.edu.in")) {
          if (gender == 'Male') {
            return const MaleStudentDashboard();
          } else {
            return const StudentDashboard();
          }
        }

        // Warden
        if (email.contains("warden")) {
          return const WardenDashboard();
        }

        // Tutor
        return const TutorDashboard();
      },
    );
  }
}