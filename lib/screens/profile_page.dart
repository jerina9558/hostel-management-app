import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// ─────────────────────────────────────────────────────────────────────────────
// THEME HELPER
// ─────────────────────────────────────────────────────────────────────────────

class _C {
  final bool dark;
  const _C(this.dark);

  factory _C.of(BuildContext context) =>
      _C(Theme.of(context).brightness == Brightness.dark);

  Color get blue       => const Color(0xFF4169E1);
  Color get scaffold   => dark ? const Color(0xFF0F1117) : const Color(0xFFF5F7FA);
  Color get card       => dark ? const Color(0xFF1C1F2E) : Colors.white;
  Color get appBar     => dark ? const Color(0xFF12151F) : Colors.white;
  Color get ink        => dark ? const Color(0xFFE8ECF4) : const Color(0xFF1A1F36);
  Color get sub        => dark ? const Color(0xFF8A95B0) : const Color(0xFF6B7280);
  Color get divider    => dark ? const Color(0xFF252A3A) : const Color(0xFFE8EDF5);
  Color get appBarText => dark ? const Color(0xFFE8ECF4) : Colors.black87;
}

// ─────────────────────────────────────────────────────────────────────────────
// PROFILE PAGE
// ─────────────────────────────────────────────────────────────────────────────

class ProfilePage extends StatefulWidget {
  final String? initialRole;
  const ProfilePage({super.key, this.initialRole});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _formKey = GlobalKey<FormState>();

  final _nameController   = TextEditingController();
  final _regNoController  = TextEditingController();
  final _deptController   = TextEditingController();
  final _phoneController  = TextEditingController();
  final _roomNoController = TextEditingController();
  final _tutorController  = TextEditingController();
  final _yearController   = TextEditingController();

  bool isEditing  = false;
  bool hasProfile = true;
  bool isLoading  = true;
  bool isSaving   = false;

  String role = 'student';

  @override
  void initState() {
    super.initState();
    if (widget.initialRole != null) role = widget.initialRole!;
    _loadProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _regNoController.dispose();
    _deptController.dispose();
    _phoneController.dispose();
    _roomNoController.dispose();
    _tutorController.dispose();
    _yearController.dispose();
    super.dispose();
  }

  // ── Load ───────────────────────────────────────────────────────────────────

  Future<void> _loadProfile() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() { isEditing = true; hasProfile = false; });
        return;
      }

      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (doc.exists) {
        final data = doc.data()!;
        setState(() {
          role = (data['role'] ?? widget.initialRole ?? 'student')
              .toString().trim().toLowerCase();
        });

        _nameController.text   = data['name']   ?? '';
        _regNoController.text  = data['regNo']  ?? '';
        _deptController.text   = data['dept']   ?? '';
        _phoneController.text  = data['phone']  ?? '';
        _roomNoController.text = data['roomNo'] ?? '';
        _tutorController.text  = data['tutor']  ?? '';
        _yearController.text   = data['year']   ?? '';

        setState(() => hasProfile = true);
      } else {
        setState(() { isEditing = true; hasProfile = false; });
      }
    } catch (e) {
      debugPrint('Error loading profile: $e');
      _showError('Failed to load profile. Please try again.');
    } finally {
      setState(() => isLoading = false);
    }
  }

  // ── Save ───────────────────────────────────────────────────────────────────

  Future<void> saveProfile() async {
    final formValid = _formKey.currentState?.validate() ?? false;
    if (!formValid) {
      _showError('Please fill in all required fields.');
      return;
    }

    if (isSaving) return;
    setState(() => isSaving = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        _showError('Not logged in. Please sign in again.');
        return;
      }

      final updatedName = _nameController.text.trim();
      final Map<String, dynamic> data = {'role': role};

      data['name'] = updatedName;

      if (role == 'warden' || role == 'tutor' || role == 'student') {
        data['phone'] = _phoneController.text.trim();
      }
      if (role == 'tutor' || role == 'student') {
        data['dept'] = _deptController.text.trim();
      }
      if (role == 'student') {
        data['regNo']  = _regNoController.text.trim();
        data['roomNo'] = _roomNoController.text.trim();
        data['tutor']  = _tutorController.text.trim();
        data['year']   = _yearController.text.trim();
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set(data, SetOptions(merge: true));

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('${user.uid}_userName', updatedName);

      if (!mounted) return;
      setState(() { isEditing = false; hasProfile = true; });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile saved successfully'),
          backgroundColor: Color(0xFF059669),
        ),
      );

      Navigator.pop(context, updatedName);
    } catch (e) {
      debugPrint('Save error: $e');
      if (mounted) _showError('Save failed: ${e.toString()}');
    } finally {
      if (mounted) setState(() => isSaving = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.redAccent),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = _C.of(context);
    return Scaffold(
      backgroundColor: c.scaffold,
      appBar: AppBar(
        backgroundColor: c.appBar,
        elevation: 0,
        title: Text(
          role == 'admin'
              ? 'Admin Profile'
              : role == 'warden'
              ? 'Warden Profile'
              : role == 'tutor'
              ? 'Tutor Profile'
              : 'Student Profile',
          style: TextStyle(color: c.appBarText),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: c.appBarText),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (hasProfile && !isEditing)
            IconButton(
              icon: const Icon(Icons.edit, color: Color(0xFF4169E1)),
              onPressed: () => setState(() => isEditing = true),
            ),
        ],
      ),
      body: isLoading
          ? Center(child: CircularProgressIndicator(color: c.blue))
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildRoleAvatar(c),
            const SizedBox(height: 30),
            if (isEditing)
              Form(
                key: _formKey,
                child: Column(
                  children: [
                    _buildEditableFields(c),
                    const SizedBox(height: 30),
                    _buildSaveButton(c),
                    const SizedBox(height: 16),
                  ],
                ),
              )
            else
              _buildViewMode(c),
          ],
        ),
      ),
    );
  }

  // ── Static role avatar (no image picking) ─────────────────────────────────

  Widget _buildRoleAvatar(_C c) {
    final IconData iconData = switch (role) {
      'admin'  => Icons.admin_panel_settings,
      'warden' => Icons.security,
      'tutor'  => Icons.school,
      _        => Icons.person,
    };

    return Center(
      child: Container(
        width: 110,
        height: 110,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: c.blue.withOpacity(0.1),
          border: Border.all(color: c.blue.withOpacity(0.3), width: 2),
        ),
        child: Icon(iconData, size: 54, color: c.blue),
      ),
    );
  }

  // ── Editable fields ───────────────────────────────────────────────────────

  Widget _buildEditableFields(_C c) {
    if (role == 'admin') {
      return Column(children: [
        _field('Admin Name', _nameController, Icons.person, c),
      ]);
    }
    if (role == 'warden') {
      return Column(children: [
        _field('Warden Name', _nameController, Icons.person, c),
        _field('Phone Number', _phoneController, Icons.phone, c,
            type: TextInputType.phone),
      ]);
    }
    if (role == 'tutor') {
      return Column(children: [
        _field('Tutor Name', _nameController, Icons.person, c),
        _field('Department', _deptController, Icons.school, c),
        _field('Phone Number', _phoneController, Icons.phone, c,
            type: TextInputType.phone),
      ]);
    }
    // student
    return Column(children: [
      _field('Name', _nameController, Icons.person, c),
      _field('Register Number', _regNoController, Icons.badge, c),
      _field('Department', _deptController, Icons.school, c),
      _field('Phone Number', _phoneController, Icons.phone, c,
          type: TextInputType.phone),
      _field('Room Number', _roomNoController, Icons.meeting_room, c),
      _field('Tutor Name', _tutorController, Icons.person_outline, c),
      _field('Year of Study', _yearController, Icons.calendar_today, c),
    ]);
  }

  Widget _field(
      String label,
      TextEditingController controller,
      IconData icon,
      _C c, {
        TextInputType type = TextInputType.text,
      }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        keyboardType: type,
        style: TextStyle(color: c.ink),
        validator: (v) =>
        (v == null || v.trim().isEmpty) ? '$label is required' : null,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: c.sub),
          prefixIcon: Icon(icon, color: c.blue),
          filled: true,
          fillColor: c.card,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: c.divider),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: c.blue, width: 1.5),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
          ),
        ),
      ),
    );
  }

  Widget _buildSaveButton(_C c) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: isSaving ? null : saveProfile,
        style: ElevatedButton.styleFrom(
          backgroundColor: c.blue,
          disabledBackgroundColor: c.blue.withOpacity(0.6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 2,
        ),
        child: isSaving
            ? const SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            color: Colors.white,
            strokeWidth: 2.5,
          ),
        )
            : const Text(
          'Save Profile',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  // ── View mode ─────────────────────────────────────────────────────────────

  Widget _buildViewMode(_C c) {
    return Column(
      children: [
        Text(
          _nameController.text.isEmpty ? 'Name' : _nameController.text,
          style: TextStyle(
              fontSize: 24, fontWeight: FontWeight.bold, color: c.ink),
        ),
        const SizedBox(height: 8),
        if (role == 'student')
          Text(
            _regNoController.text.isEmpty
                ? 'Register Number'
                : _regNoController.text,
            style: TextStyle(color: c.sub),
          ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: c.blue.withOpacity(0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            role.toUpperCase(),
            style: TextStyle(
                color: c.blue, fontWeight: FontWeight.bold, fontSize: 12),
          ),
        ),
        const SizedBox(height: 24),
        if (role == 'warden')
          _info('Phone Number', _phoneController.text, Icons.phone, c),
        if (role == 'tutor') ...[
          _info('Department', _deptController.text, Icons.school, c),
          _info('Phone Number', _phoneController.text, Icons.phone, c),
        ],
        if (role == 'student') ...[
          _info('Phone Number', _phoneController.text, Icons.phone, c),
          _info('Department', _deptController.text, Icons.school, c),
          _info('Room Number', _roomNoController.text, Icons.meeting_room, c),
          _info('Tutor Name', _tutorController.text, Icons.person_outline, c),
          _info('Year of Study', _yearController.text, Icons.calendar_today, c),
        ],
      ],
    );
  }

  Widget _info(String label, String value, IconData icon, _C c) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.divider),
        ),
        child: Row(
          children: [
            Icon(icon, color: c.blue),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 12, color: c.sub)),
                Text(
                  value.isEmpty ? 'Not set' : value,
                  style: TextStyle(fontSize: 16, color: c.ink),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}