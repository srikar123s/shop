import 'package:flutter/material.dart';
import 'package:shop/database/database_helper.dart';
import 'package:shop/repositories/customer_repository.dart';
import 'package:shop/services/excel_customer_service.dart';

/// Shows an interactive pre-import preview dialog for customers parsed from Excel/CSV
Future<void> showCustomerImportDialog({
  required BuildContext context,
  required List<ExcelCustomerRow> candidates,
  required CustomerRepository customerRepository,
  required VoidCallback onImportComplete,
}) async {
  if (candidates.isEmpty) return;

  final selectedIndices = List<int>.generate(candidates.length, (i) => i).toSet();
  bool recordOpeningBalance = true;
  String searchQuery = '';
  bool isImporting = false;

  await showDialog<void>(
    context: context,
    barrierDismissible: !isImporting,
    builder: (dialogCtx) {
      return StatefulBuilder(
        builder: (ctx, setDialogState) {
          final filteredIndices = <int>[];
          for (int i = 0; i < candidates.length; i++) {
            final c = candidates[i];
            if (searchQuery.isEmpty ||
                c.name.toLowerCase().contains(searchQuery.toLowerCase()) ||
                c.phone.toLowerCase().contains(searchQuery.toLowerCase()) ||
                (c.address?.toLowerCase().contains(searchQuery.toLowerCase()) ?? false)) {
              filteredIndices.add(i);
            }
          }

          final totalBalance = candidates.fold<double>(
            0.0,
            (sum, c) => sum + (selectedIndices.contains(candidates.indexOf(c)) ? c.presentBalance : 0.0),
          );

          final selectedCount = selectedIndices.length;
          final newCount = candidates.where((c) => !c.isExisting && selectedIndices.contains(candidates.indexOf(c))).length;
          final existingCount = candidates.where((c) => c.isExisting && selectedIndices.contains(candidates.indexOf(c))).length;
          final multiPhoneCount = candidates.where((c) => c.hasMultiplePhones && selectedIndices.contains(candidates.indexOf(c))).length;

          return AlertDialog(
            titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.teal.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.group_add_outlined, color: Color(0xFF0F766E), size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Import Customers from Excel',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${candidates.length} total parties found in sheet',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Download Sample Template',
                  icon: const Icon(Icons.file_download_outlined, color: Color(0xFF0F766E)),
                  onPressed: () => ExcelCustomerService.shareSampleCustomerTemplate(),
                ),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 8),
                  // Summary Badges
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildSummaryChip('Selected', '$selectedCount', Colors.teal),
                        const SizedBox(width: 6),
                        _buildSummaryChip('New Parties', '$newCount', Colors.green),
                        const SizedBox(width: 6),
                        if (existingCount > 0) ...[
                          _buildSummaryChip('Matches DB', '$existingCount', Colors.orange),
                          const SizedBox(width: 6),
                        ],
                        if (multiPhoneCount > 0) ...[
                          _buildSummaryChip('Multi-Phone', '$multiPhoneCount', Colors.blue),
                          const SizedBox(width: 6),
                        ],
                        if (totalBalance > 0)
                          _buildSummaryChip(
                            'Udhaar Dues',
                            '₹ ${totalBalance.toStringAsFixed(0)}',
                            Colors.purple,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Opening Balance Checkbox Switch
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    child: CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: recordOpeningBalance,
                      activeColor: const Color(0xFF0F766E),
                      title: const Text(
                        'Record Opening Udhaar Balance into Khata Book',
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                      ),
                      subtitle: const Text(
                        'Creates initial debit ledger entries so customer dues match Excel immediately',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                      onChanged: (val) {
                        setDialogState(() => recordOpeningBalance = val ?? true);
                      },
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Search & Select all row
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 38,
                          child: TextField(
                            decoration: InputDecoration(
                              hintText: 'Search parsed customers...',
                              hintStyle: const TextStyle(fontSize: 12),
                              prefixIcon: const Icon(Icons.search, size: 16),
                              contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 10),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            onChanged: (val) {
                              setDialogState(() => searchQuery = val);
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                        icon: Icon(
                          selectedIndices.length == candidates.length
                              ? Icons.deselect
                              : Icons.select_all,
                          size: 16,
                        ),
                        label: Text(
                          selectedIndices.length == candidates.length ? 'None' : 'All',
                          style: const TextStyle(fontSize: 12),
                        ),
                        onPressed: () {
                          setDialogState(() {
                            if (selectedIndices.length == candidates.length) {
                              selectedIndices.clear();
                            } else {
                              selectedIndices.addAll(List.generate(candidates.length, (i) => i));
                            }
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // List of Customers
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 320),
                    child: filteredIndices.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              'No matching customers found.',
                              style: TextStyle(color: Colors.grey),
                            ),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            itemCount: filteredIndices.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (ctx, i) {
                              final originalIndex = filteredIndices[i];
                              final row = candidates[originalIndex];
                              final isChecked = selectedIndices.contains(originalIndex);

                              return CheckboxListTile(
                                dense: true,
                                controlAffinity: ListTileControlAffinity.leading,
                                value: isChecked,
                                activeColor: const Color(0xFF0F766E),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        row.name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13.5,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (row.isExisting) ...[
                                      const SizedBox(width: 4),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.amber.shade100,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          'Existing',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.amber.shade900,
                                          ),
                                        ),
                                      ),
                                    ],
                                    if (row.hasMultiplePhones) ...[
                                      const SizedBox(width: 4),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.blue.shade50,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          '${row.phoneNumbers.length} phones',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.blue.shade800,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      row.phone.isNotEmpty ? row.phone : 'No phone',
                                      style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                                    ),
                                    if (row.address != null && row.address!.isNotEmpty)
                                      Text(
                                        '📍 ${row.address}',
                                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                      ),
                                    if (row.presentBalance > 0)
                                      Text(
                                        'Balance: ₹ ${row.presentBalance.toStringAsFixed(2)} Udhaar',
                                        style: const TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFFDC2626),
                                        ),
                                      ),
                                  ],
                                ),
                                onChanged: (val) {
                                  setDialogState(() {
                                    if (val == true) {
                                      selectedIndices.add(originalIndex);
                                    } else {
                                      selectedIndices.remove(originalIndex);
                                    }
                                  });
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isImporting ? null : () => Navigator.pop(dialogCtx),
                child: const Text('CANCEL'),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0F766E)),
                icon: isImporting
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Icon(Icons.file_download_done, size: 18),
                label: Text(
                  isImporting ? 'Importing...' : 'IMPORT ($selectedCount)',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                onPressed: selectedCount == 0 || isImporting
                    ? null
                    : () async {
                        setDialogState(() => isImporting = true);

                        int importedNew = 0;
                        int updatedExisting = 0;
                        int balancesRecorded = 0;

                        for (final idx in selectedIndices) {
                          final row = candidates[idx];
                          try {
                            final savedCustomer = await customerRepository.createCustomer(
                              name: row.name,
                              phone: row.phone,
                              address: row.address,
                              creditLimit: row.creditLimit,
                            );

                            if (row.isExisting) {
                              updatedExisting++;
                            } else {
                              importedNew++;
                            }

                            if (recordOpeningBalance &&
                                row.presentBalance > 0.01 &&
                                savedCustomer.id != null) {
                              await DatabaseHelper.instance.recordManualKhataDebit(
                                customerId: savedCustomer.id!,
                                amount: row.presentBalance,
                                description: 'Opening Balance (Imported from Excel)',
                              );
                              balancesRecorded++;
                            }
                          } catch (_) {}
                        }

                        if (!dialogCtx.mounted) return;
                        Navigator.pop(dialogCtx);
                        onImportComplete();

                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: const Color(0xFF0F766E),
                            duration: const Duration(seconds: 4),
                            content: Text(
                              'Imported $selectedCount customers: $importedNew new, '
                              '$updatedExisting updated${balancesRecorded > 0 ? ', $balancesRecorded opening balances recorded in Khata' : ''}.',
                            ),
                          ),
                        );
                      },
              ),
            ],
          );
        },
      );
    },
  );
}

Widget _buildSummaryChip(String label, String value, MaterialColor color) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.shade50,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: color.shade200),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label: ',
          style: TextStyle(fontSize: 11, color: color.shade900),
        ),
        Text(
          value,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color.shade900),
        ),
      ],
    ),
  );
}
