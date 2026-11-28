import 'package:flutter/material.dart';

/// Shows a bottom sheet allowing the user to select which phone number to dial or message
/// when a customer has multiple phone numbers.
Future<String?> showPhonePickerModal({
  required BuildContext context,
  required String customerName,
  required List<String> phoneNumbers,
  String actionTitle = 'Select Phone Number',
}) async {
  if (phoneNumbers.isEmpty) return null;
  if (phoneNumbers.length == 1) return phoneNumbers.first;

  return showModalBottomSheet<String>(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.contact_phone_outlined,
                        color: Color(0xFF0F766E)),
                    const SizedBox(width: 8),
                    Text(
                      actionTitle,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '$customerName has ${phoneNumbers.length} phone numbers registered:',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 12),
            ...phoneNumbers.asMap().entries.map((entry) {
              final idx = entry.key;
              final p = entry.value;
              return Card(
                elevation: 0,
                color: Colors.grey.shade50,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(color: Colors.grey.shade300),
                ),
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    radius: 16,
                    backgroundColor:
                        idx == 0 ? Colors.teal.shade50 : Colors.blue.shade50,
                    child: Text(
                      '${idx + 1}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: idx == 0
                            ? Colors.teal.shade800
                            : Colors.blue.shade800,
                      ),
                    ),
                  ),
                  title: Text(
                    p,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  subtitle: Text(
                    idx == 0 ? 'Primary Number' : 'Alternate Number',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                  onTap: () => Navigator.pop(ctx, p),
                ),
              );
            }),
          ],
        ),
      ),
    ),
  );
}
