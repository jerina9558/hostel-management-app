import 'package:flutter/material.dart';

class NotifyComplaintPage extends StatefulWidget {
  const NotifyComplaintPage({super.key});

  @override
  State<NotifyComplaintPage> createState() => _NotifyComplaintPageState();
}

class _NotifyComplaintPageState extends State<NotifyComplaintPage> {
  List<Map<String, dynamic>> complaints = [
    {
      'id': 'C001',
      'category': 'Electrical',
      'roomNumber': '204',
      'description': 'Fan not working in Room 204',
      'status': 'Pending',
      'date': '5 Jan 2026',
    },
    {
      'id': 'C002',
      'category': 'Plumbing',
      'roomNumber': '301',
      'description': 'Water leakage in bathroom',
      'status': 'In Progress',
      'date': '7 Jan 2026',
    },
  ];

  final List<String> statusOptions = [
    'Pending',
    'In Progress',
    'Completed',
  ];

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Completed':
        return Colors.green;
      case 'In Progress':
        return Colors.orange;
      default:
        return Colors.red;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: const Color(0xFF1565C0),
        foregroundColor: Colors.white,
        title: const Text('Manage Complaints'),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: complaints.length,
        itemBuilder: (context, index) {
          final complaint = complaints[index];
          final statusColor = _getStatusColor(complaint['status']);

          return Card(
            elevation: 3,
            margin: const EdgeInsets.only(bottom: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // HEADER
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        complaint['id'],
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1565C0),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          complaint['status'],
                          style: TextStyle(
                            color: statusColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),

                  Text(
                    'Room ${complaint['roomNumber']} • ${complaint['category']}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),

                  const SizedBox(height: 6),

                  Text(
                    complaint['description'],
                    style: TextStyle(color: Colors.grey.shade700),
                  ),

                  const SizedBox(height: 12),
                  Divider(color: Colors.grey.shade300),

                  // STATUS UPDATE
                  const Text(
                    'Update Status',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),

                  DropdownButtonFormField<String>(
                    value: complaint['status'],
                    items: statusOptions
                        .map(
                          (s) => DropdownMenuItem(
                        value: s,
                        child: Text(s),
                      ),
                    )
                        .toList(),
                    onChanged: (value) {
                      setState(() {
                        complaints[index]['status'] = value!;
                      });

                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                              'Status updated to "$value" for ${complaint['id']}'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    },
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
