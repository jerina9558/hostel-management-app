// lib/screens/settings_page.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hostel_management_app/main.dart';
import 'student_notification_listener.dart';
import 'mess_menu.dart';

class UserRole {
  static const String student = 'student';
  static const String tutor   = 'tutor';
  static const String warden  = 'warden';
  static const String admin   = 'admin';
}

class SettingsPage extends StatefulWidget {
  final Future<void> Function() onLogout;
  final String role;
  final String studentId;
  final String hostelId;

  const SettingsPage({
    super.key,
    required this.onLogout,
    this.role      = UserRole.student,
    this.studentId = '',
    this.hostelId  = '',
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  // ── Master toggle ──────────────────────────────────────────────────────────
  bool _pushNotifications = true;

  // ── STUDENT notifications ──────────────────────────────────────────────────
  bool _announcementNotifications     = true;
  bool _eventNotifications            = true;
  bool _gatePassNotifications         = true;
  bool _permissionStatusNotifications = true;
  bool _complaintUpdates              = true;
  bool _messMenuNotifications         = false;

  // ── TUTOR notifications ────────────────────────────────────────────────────
  bool _newPermissionRequest = true;

  // ── WARDEN notifications ───────────────────────────────────────────────────
  bool _wardenGatePassRequest   = true;
  bool _wardenPermissionNotif   = true;
  bool _wardenComplaintNotif    = true;

  // ── ADMIN notifications ────────────────────────────────────────────────────
  bool _adminSystemAlerts = true;
  bool _adminReportReady  = true;
  bool _adminNewUserNotif = false;

  // ── Shared ────────────────────────────────────────────────────────────────
  bool   _darkMode         = false;
  String _selectedFontSize = 'Medium';

  final List<String> _fontSizes = ['Small', 'Medium', 'Large'];

  Color get _primaryBlue =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF4A9EDB)
          : const Color(0xFF1976D2);

  Color get _appBarBg =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF0D2A45)
          : const Color(0xFF1976D2);

  bool get _isStudent => widget.role == UserRole.student;
  bool get _isTutor   => widget.role == UserRole.tutor;
  bool get _isWarden  => widget.role == UserRole.warden;
  bool get _isAdmin   => widget.role == UserRole.admin;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _pushNotifications             = prefs.getBool('push_notifications') ?? true;
      _announcementNotifications     = prefs.getBool('announcement_notifications') ?? true;
      _eventNotifications            = prefs.getBool('event_notifications') ?? true;
      _gatePassNotifications         = prefs.getBool('gatepass_notifications') ?? true;
      _permissionStatusNotifications = prefs.getBool('permission_status_notifications') ?? true;
      _complaintUpdates              = prefs.getBool('complaint_updates') ?? true;
      _messMenuNotifications         = prefs.getBool('mess_menu_notifications') ?? false;

      _newPermissionRequest = prefs.getBool('tutor_new_permission_request') ?? true;

      _wardenGatePassRequest   = prefs.getBool('warden_gatepass_request') ?? true;
      _wardenPermissionNotif   = prefs.getBool('warden_permission_notif') ?? true;
      _wardenComplaintNotif    = prefs.getBool('warden_complaint_notif') ?? true;

      _adminSystemAlerts = prefs.getBool('admin_system_alerts')  ?? true;
      _adminReportReady  = prefs.getBool('admin_report_ready')   ?? true;
      _adminNewUserNotif = prefs.getBool('admin_new_user_notif') ?? false;

      _darkMode         = prefs.getBool('dark_mode') ?? false;
      _selectedFontSize = prefs.getString('font_size') ?? 'Medium';

      themeNotifier.value    = _darkMode ? ThemeMode.dark : ThemeMode.light;
      fontSizeNotifier.value = _fontSizeToDouble(_selectedFontSize);
    });
  }

  // ── Persist to SharedPreferences only (for non-notification settings) ─────
  Future<void> _saveSetting(String key, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is bool)   await prefs.setBool(key, value);
    if (value is String) await prefs.setString(key, value);
  }

  // ── Mirror a notification bool to Firestore ───────────────────────────────
  Future<void> _saveNotifToFirestore(String key, bool value) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('settings')
          .doc('notifications')
          .set({key: value}, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Firestore settings write error: $e');
    }
  }

  // ── Combined: SharedPreferences + Firestore for ALL notification booleans ─
  Future<void> _saveNotifSetting(String key, bool value) async {
    await _saveSetting(key, value);
    await _saveNotifToFirestore(key, value);
  }

  double _fontSizeToDouble(String size) {
    switch (size) {
      case 'Small': return 12.0;
      case 'Large': return 18.0;
      default:      return 14.0;
    }
  }

  // ── Master toggle ─────────────────────────────────────────────────────────
  Future<void> _onMasterToggle(bool value) async {
    setState(() => _pushNotifications = value);
    await _saveNotifSetting('push_notifications', value);

    if (_isStudent) {
      if (value) {
        await StudentNotificationListener.instance.start(
          studentId: widget.studentId,
          hostelId:  widget.hostelId,
        );
        if (_messMenuNotifications) {
          await scheduleMessReminderForStudent(hostelId: widget.hostelId);
        }
      } else {
        await StudentNotificationListener.instance.dispose();
        await MessMenuScheduler.instance.cancel();
      }
    }
  }

  // ── Mess menu toggle ──────────────────────────────────────────────────────
  Future<void> _onMessMenuToggle(bool value) async {
    setState(() => _messMenuNotifications = value);
    await _saveNotifSetting('mess_menu_notifications', value);

    if (!value) {
      await MessMenuScheduler.instance.cancel();
    } else {
      await scheduleMessReminderForStudent(hostelId: widget.hostelId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Settings',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        backgroundColor: _appBarBg,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [

          // ── Push Notifications ────────────────────────────────────────────
          _buildSectionHeader(Icons.notifications_active, 'Push Notifications'),
          _buildSettingsCard([

            _buildMasterToggle(
              title: 'Enable Push Notifications',
              subtitle: 'Turn on/off all notifications',
              value: _pushNotifications,
              onChanged: _onMasterToggle,
            ),
            Divider(height: 1, color: theme.dividerColor),

            // ── STUDENT ──────────────────────────────────────────────────────
            if (_isStudent) ...[
              _buildSubToggle(
                title: 'Announcements',
                subtitle: 'Hostel announcements & notices',
                icon: Icons.campaign_outlined,
                value: _announcementNotifications,
                enabled: _pushNotifications,
                onChanged: (v) {
                  setState(() => _announcementNotifications = v);
                  _saveNotifSetting('announcement_notifications', v);
                },
              ),
              _buildSubToggle(
                title: 'Events',
                subtitle: 'Upcoming hostel events',
                icon: Icons.event_outlined,
                value: _eventNotifications,
                enabled: _pushNotifications,
                onChanged: (v) {
                  setState(() => _eventNotifications = v);
                  _saveNotifSetting('event_notifications', v);
                },
              ),
              _buildSubToggle(
                title: 'Gate Pass Status',
                subtitle: 'Warden approval or rejection updates',
                icon: Icons.exit_to_app_outlined,
                value: _gatePassNotifications,
                enabled: _pushNotifications,
                onChanged: (v) {
                  setState(() => _gatePassNotifications = v);
                  _saveNotifSetting('gatepass_notifications', v);
                },
              ),
              _buildSubToggle(
                title: 'Permission Status',
                subtitle: 'Tutor approval or rejection of leave requests',
                icon: Icons.assignment_outlined,
                value: _permissionStatusNotifications,
                enabled: _pushNotifications,
                onChanged: (v) {
                  setState(() => _permissionStatusNotifications = v);
                  _saveNotifSetting('permission_status_notifications', v);
                },
              ),
              _buildSubToggle(
                title: 'Complaint Updates',
                subtitle: 'Warden updates the status of your complaint',
                icon: Icons.build_outlined,
                value: _complaintUpdates,
                enabled: _pushNotifications,
                onChanged: (v) {
                  setState(() => _complaintUpdates = v);
                  _saveNotifSetting('complaint_updates', v);
                },
              ),
              _buildSubToggle(
                title: 'Mess Menu Reminder',
                subtitle: 'Notified at 8 AM when tomorrow has non-veg',
                icon: Icons.restaurant_menu_outlined,
                value: _messMenuNotifications,
                enabled: _pushNotifications,
                onChanged: _onMessMenuToggle,
              ),
            ],

            // ── TUTOR ─────────────────────────────────────────────────────────
            if (_isTutor) ...[
              _buildSubToggle(
                title: 'New Permission Request',
                subtitle: 'Alert when a student submits a leave request',
                icon: Icons.assignment_ind_outlined,
                value: _newPermissionRequest,
                enabled: _pushNotifications,
                onChanged: (v) {
                  setState(() => _newPermissionRequest = v);
                  _saveNotifSetting('tutor_new_permission_request', v);
                },
              ),
            ],

            // ── WARDEN ────────────────────────────────────────────────────────
            if (_isWarden) ...[
              _buildSubToggle(
                title: 'Gate Pass Requests',
                subtitle: 'Alert when a student posts a gate pass',
                icon: Icons.exit_to_app_outlined,
                value: _wardenGatePassRequest,
                enabled: _pushNotifications,
                onChanged: (v) {
                  setState(() => _wardenGatePassRequest = v);
                  _saveNotifSetting('warden_gatepass_request', v);
                },
              ),
              _buildSubToggle(
                title: 'Permission Requests',
                subtitle: 'All student permission requests for review',
                icon: Icons.assignment_outlined,
                value: _wardenPermissionNotif,
                enabled: _pushNotifications,
                onChanged: (v) {
                  setState(() => _wardenPermissionNotif = v);
                  _saveNotifSetting('warden_permission_notif', v);
                },
              ),
              _buildSubToggle(
                title: 'Complaint Notifications',
                subtitle: 'New and updated student complaints',
                icon: Icons.build_outlined,
                value: _wardenComplaintNotif,
                enabled: _pushNotifications,
                onChanged: (v) {
                  setState(() => _wardenComplaintNotif = v);
                  _saveNotifSetting('warden_complaint_notif', v);
                },
              ),
            ],

            // ── ADMIN ─────────────────────────────────────────────────────────
            if (_isAdmin) ...[
              _buildSubToggle(
                title: 'System Alerts',
                subtitle: 'Critical errors, maintenance & outage warnings',
                icon: Icons.warning_amber_outlined,
                value: _adminSystemAlerts,
                enabled: _pushNotifications,
                onChanged: (v) {
                  setState(() => _adminSystemAlerts = v);
                  _saveNotifSetting('admin_system_alerts', v);
                },
              ),
              _buildSubToggle(
                title: 'Report Ready',
                subtitle: 'Notify when a scheduled report is generated',
                icon: Icons.analytics_outlined,
                value: _adminReportReady,
                enabled: _pushNotifications,
                onChanged: (v) {
                  setState(() => _adminReportReady = v);
                  _saveNotifSetting('admin_report_ready', v);
                },
              ),
              _buildSubToggle(
                title: 'New User Registration',
                subtitle: 'Alert when a new account is created',
                icon: Icons.person_add_outlined,
                value: _adminNewUserNotif,
                enabled: _pushNotifications,
                onChanged: (v) {
                  setState(() => _adminNewUserNotif = v);
                  _saveNotifSetting('admin_new_user_notif', v);
                },
              ),
            ],

          ], theme),

          const SizedBox(height: 16),

          // ── Appearance ────────────────────────────────────────────────────
          _buildSectionHeader(Icons.palette_outlined, 'Appearance'),
          _buildSettingsCard([
            _buildToggleTile(
              title: 'Dark Mode',
              subtitle: 'Switch to dark theme',
              icon: Icons.dark_mode_outlined,
              value: _darkMode,
              onChanged: (v) {
                setState(() => _darkMode = v);
                themeNotifier.value = v ? ThemeMode.dark : ThemeMode.light;
                _saveSetting('dark_mode', v);
              },
            ),
            Divider(height: 1, color: theme.dividerColor),
            _buildDropdownTile(
              title: 'Font Size',
              subtitle: 'Adjust text size across the app',
              icon: Icons.text_fields_outlined,
              value: _selectedFontSize,
              items: _fontSizes,
              theme: theme,
              onChanged: (v) {
                if (v != null) {
                  setState(() => _selectedFontSize = v);
                  fontSizeNotifier.value = _fontSizeToDouble(v);
                  _saveSetting('font_size', v);
                }
              },
            ),
          ], theme),

          const SizedBox(height: 16),

          // ── About ─────────────────────────────────────────────────────────
          _buildSectionHeader(Icons.info_outline, 'About'),
          _buildSettingsCard([
            _buildInfoTile(
              title: 'App Version',
              subtitle: '1.0.0',
              icon: Icons.phone_android_outlined,
            ),
            Divider(height: 1, color: theme.dividerColor),
            _buildTapTile(
                title: 'Terms & Conditions',
                icon: Icons.description_outlined,
                onTap: () {}),
            Divider(height: 1, color: theme.dividerColor),
            _buildTapTile(
                title: 'Privacy Policy',
                icon: Icons.privacy_tip_outlined,
                onTap: () {}),
            Divider(height: 1, color: theme.dividerColor),
            _buildTapTile(
                title: 'Help & Support',
                icon: Icons.help_outline,
                onTap: () {}),
          ], theme),

          const SizedBox(height: 24),

          // ── Logout ────────────────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Logout'),
                    content: const Text('Are you sure you want to logout?'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel')),
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          style: TextButton.styleFrom(
                              foregroundColor: Colors.red),
                          child: const Text('Logout')),
                    ],
                  ),
                );
                if (confirm == true) {
                  await StudentNotificationListener.instance.dispose();
                  await MessMenuScheduler.instance.cancel();
                  await widget.onLogout();
                }
              },
              icon: const Icon(Icons.logout, color: Colors.red),
              label: const Text('Logout',
                  style: TextStyle(
                      color: Colors.red,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.red, width: 1.5),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ── WIDGET HELPERS ────────────────────────────────────────────────────────

  Widget _buildSectionHeader(IconData icon, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Icon(icon, size: 18, color: _primaryBlue),
        const SizedBox(width: 8),
        Text(title,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: _primaryBlue,
                letterSpacing: 0.5)),
      ]),
    );
  }

  Widget _buildSettingsCard(List<Widget> children, ThemeData theme) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(children: children),
    );
  }

  Widget _buildMasterToggle({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      contentPadding:
      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      secondary: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
            color: _primaryBlue.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10)),
        child: Icon(Icons.notifications, color: _primaryBlue, size: 20),
      ),
      title: Text(title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
      subtitle: Text(subtitle,
          style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6))),
      value: value,
      activeColor: _primaryBlue,
      onChanged: onChanged,
    );
  }

  Widget _buildSubToggle({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool value,
    required bool enabled,
    required ValueChanged<bool> onChanged,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Opacity(
      opacity: enabled ? 1.0 : 0.4,
      child: SwitchListTile(
        contentPadding:
        const EdgeInsets.only(left: 32, right: 16, top: 2, bottom: 2),
        secondary: Icon(icon,
            size: 20, color: colorScheme.onSurface.withOpacity(0.6)),
        title: Text(title, style: const TextStyle(fontSize: 14)),
        subtitle: Text(subtitle,
            style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurface.withOpacity(0.5))),
        value: value,
        activeColor: _primaryBlue,
        onChanged: enabled ? onChanged : null,
      ),
    );
  }

  Widget _buildToggleTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return SwitchListTile(
      contentPadding:
      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      secondary: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
            color: _primaryBlue.withOpacity(0.08),
            borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: _primaryBlue, size: 20),
      ),
      title: Text(title, style: const TextStyle(fontSize: 14)),
      subtitle: Text(subtitle,
          style: TextStyle(
              fontSize: 12,
              color: colorScheme.onSurface.withOpacity(0.6))),
      value: value,
      activeColor: _primaryBlue,
      onChanged: onChanged,
    );
  }

  Widget _buildDropdownTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required String value,
    required List<String> items,
    required ThemeData theme,
    required ValueChanged<String?> onChanged,
  }) {
    final colorScheme = theme.colorScheme;
    return ListTile(
      contentPadding:
      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
            color: _primaryBlue.withOpacity(0.08),
            borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: _primaryBlue, size: 20),
      ),
      title: Text(title, style: const TextStyle(fontSize: 14)),
      subtitle: Text(subtitle,
          style: TextStyle(
              fontSize: 12,
              color: colorScheme.onSurface.withOpacity(0.6))),
      trailing: DropdownButton<String>(
        value: value,
        underline: const SizedBox(),
        dropdownColor: colorScheme.surface,
        style: TextStyle(
            fontSize: 13,
            color: _primaryBlue,
            fontWeight: FontWeight.w600),
        items: items
            .map((e) => DropdownMenuItem(value: e, child: Text(e)))
            .toList(),
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildInfoTile({
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding:
      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
            color: _primaryBlue.withOpacity(0.08),
            borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: _primaryBlue, size: 20),
      ),
      title: Text(title, style: const TextStyle(fontSize: 14)),
      trailing: Text(subtitle,
          style: TextStyle(
              fontSize: 13,
              color: colorScheme.onSurface.withOpacity(0.6),
              fontWeight: FontWeight.w500)),
    );
  }

  Widget _buildTapTile({
    required String title,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding:
      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
            color: _primaryBlue.withOpacity(0.08),
            borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: _primaryBlue, size: 20),
      ),
      title: Text(title, style: const TextStyle(fontSize: 14)),
      trailing: Icon(Icons.chevron_right,
          color: colorScheme.onSurface.withOpacity(0.4)),
      onTap: onTap,
    );
  }
}