import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:shop/database/database_helper.dart';
import 'package:shop/l10n/app_localizations.dart';
import 'package:shop/models/customer.dart';
import 'package:shop/repositories/customer_repository.dart';
import 'package:shop/repositories/order_repository.dart';
import 'package:shop/repositories/product_repository.dart';
import 'package:shop/screens/product_selection_screen.dart';
import 'package:shop/services/excel_customer_service.dart';
import 'package:shop/services/voice_search_service.dart';
import 'package:shop/widgets/customer_import_dialog.dart';
import 'package:shop/widgets/large_action_button.dart';

class CustomerScreen extends StatefulWidget {
  const CustomerScreen({
    super.key,
    required this.customerRepository,
    required this.productRepository,
    required this.orderRepository,
  });

  final CustomerRepository customerRepository;
  final ProductRepository productRepository;
  final OrderRepository orderRepository;

  @override
  State<CustomerScreen> createState() => _CustomerScreenState();
}

class _CustomerScreenState extends State<CustomerScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<Customer> _customers = <Customer>[];
  List<Contact> _deviceContacts = <Contact>[];
  Customer? _selected;
  bool _loading = true;
  bool _contactsLoading = false;
  bool _contactsEnabled = false;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _loadCustomers();
  }

  void _onSearchChanged(String _) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) _loadCustomers();
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Map<int, double> _customerBalances = {};

  Future<void> _loadCustomers() async {
    setState(() => _loading = true);
    final data =
        await widget.customerRepository.searchCustomers(_searchController.text);
    final khataList = await DatabaseHelper.instance.getCustomerKhataList();
    final balances = <int, double>{};
    for (final item in khataList) {
      final cid = item['customer_id'] as int?;
      final bal = (item['balance_due'] as num?)?.toDouble() ?? 0.0;
      if (cid != null) {
        balances[cid] = bal;
      }
    }
    if (!mounted) return;
    setState(() {
      _customers = data;
      _customerBalances = balances;
      _loading = false;
    });
  }

  Future<void> _importCustomersFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls', 'csv'],
      );
      if (result == null || result.files.isEmpty || result.files.first.path == null) {
        return;
      }

      final file = File(result.files.first.path!);
      final parsedList = await ExcelCustomerService.parseCustomersFromFile(
        file,
        widget.customerRepository,
      );

      if (!mounted) return;

      if (parsedList.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No valid customers found in file. Please ensure shop/customer names are present.'),
          ),
        );
        return;
      }

      await showCustomerImportDialog(
        context: context,
        candidates: parsedList,
        customerRepository: widget.customerRepository,
        onImportComplete: () => _loadCustomers(),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to read file: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _showAddCustomerDialog() async {
    final s = AppLocalizations.of(context);
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final addressCtrl = TextEditingController();
    final creditLimitCtrl = TextEditingController();

    final Customer? result;
    try {
      result = await showDialog<Customer>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(s.t('addCustomer')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(labelText: '${s.t('name')} *'),
                  autofocus: true,
                ),
                TextField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Phone Number * (Compulsory)',
                    hintText: 'e.g. 9876543210 or 9876543210, 9123456789',
                    helperText: 'Separate multiple numbers with a comma',
                  ),
                ),
                TextField(
                  controller: addressCtrl,
                  decoration: InputDecoration(labelText: s.t('address')),
                ),
                TextField(
                  controller: creditLimitCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Credit Limit (Khata Max ₹)',
                    hintText: 'e.g. 25000 (0 for no limit)',
                    prefixText: '₹ ',
                  ),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(s.t('cancel')),
            ),
            FilledButton(
              onPressed: () async {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Customer Name is required.')),
                  );
                  return;
                }
                final phone = phoneCtrl.text.trim();
                final cleanP = phone.replaceAll(RegExp(r'[^0-9]'), '');
                if (cleanP.length < 6) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text(
                            'Phone Number is compulsory (minimum 6 digits).')),
                  );
                  return;
                }
                final creditLimit =
                    double.tryParse(creditLimitCtrl.text.trim()) ?? 0.0;
                final customer = await widget.customerRepository.createCustomer(
                  name: name,
                  phone: phone,
                  address: addressCtrl.text,
                  creditLimit: creditLimit,
                );
                if (context.mounted) {
                  Navigator.pop(context, customer);
                }
              },
              child: Text(s.t('save')),
            ),
          ],
        );
      },
    );
    } finally {
      nameCtrl.dispose();
      phoneCtrl.dispose();
      addressCtrl.dispose();
      creditLimitCtrl.dispose();
    }

    if (result != null) {
      setState(() => _selected = result);
      await _loadCustomers();
    }
  }

  Future<void> _showEditCustomerDialog(Customer customer) async {
    final s = AppLocalizations.of(context);
    final nameCtrl = TextEditingController(text: customer.name);
    final phoneCtrl = TextEditingController(text: customer.phone ?? '');
    final addressCtrl = TextEditingController(text: customer.address ?? '');
    final creditLimitCtrl = TextEditingController(
      text: customer.creditLimit > 0
          ? customer.creditLimit.toStringAsFixed(0)
          : '',
    );

    final bool? updated;
    try {
      updated = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Edit Customer'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(labelText: '${s.t('name')} *'),
                ),
                TextField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Phone Number(s)',
                    hintText: 'e.g. 9876543210, 9123456789',
                    helperText: 'Separate multiple numbers with a comma',
                  ),
                ),
                TextField(
                  controller: addressCtrl,
                  decoration: InputDecoration(labelText: s.t('address')),
                ),
                TextField(
                  controller: creditLimitCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Credit Limit (Khata Max ₹)',
                    hintText: 'e.g. 25000 (0 for no limit)',
                    prefixText: '₹ ',
                  ),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(s.t('cancel')),
            ),
            FilledButton(
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty || customer.id == null) {
                  return;
                }
                final creditLimit =
                    double.tryParse(creditLimitCtrl.text.trim()) ?? 0.0;
                await widget.customerRepository.updateCustomer(
                  id: customer.id!,
                  name: nameCtrl.text,
                  phone: phoneCtrl.text,
                  address: addressCtrl.text,
                  creditLimit: creditLimit,
                );
                if (context.mounted) {
                  Navigator.pop(context, true);
                }
              },
              child: Text(s.t('save')),
            ),
          ],
        );
      },
    );
    } finally {
      nameCtrl.dispose();
      phoneCtrl.dispose();
      addressCtrl.dispose();
      creditLimitCtrl.dispose();
    }

    if (updated == true && mounted) {
      await _loadCustomers();
      if (_selected?.id == customer.id) {
        _selected = await widget.customerRepository.getCustomerById(customer.id!);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Customer details updated.'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _confirmDeleteCustomer(Customer customer) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${customer.name}?'),
        content: const Text(
          'This will remove this customer record. Past orders will remain in history.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );

    if (confirm == true && customer.id != null && mounted) {
      await widget.customerRepository.deleteCustomer(customer.id!);
      if (_selected?.id == customer.id) {
        _selected = null;
      }
      await _loadCustomers();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${customer.name} deleted.'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _enableContacts() async {
    final status =
        await FlutterContacts.permissions.request(PermissionType.read);
    if (!mounted) return;
    if (status != PermissionStatus.granted &&
        status != PermissionStatus.limited) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Contacts permission is needed to choose a customer.'),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    setState(() => _contactsLoading = true);
    final contacts = await FlutterContacts.getAll();
    if (!mounted) return;
    setState(() {
      _deviceContacts = contacts
        ..sort((a, b) => (a.displayName ?? '').toLowerCase().compareTo(
              (b.displayName ?? '').toLowerCase(),
            ));
      _contactsEnabled = true;
      _contactsLoading = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${contacts.length} contacts loaded'),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _selectContact(Contact contact) async {
    final s = AppLocalizations.of(context);
    if (contact.id == null) return;
    final fullContact = await FlutterContacts.get(
          contact.id!,
          properties: ContactProperties.all,
        ) ??
        contact;
    if (!mounted) return;
    final contactName = fullContact.displayName?.trim() ?? '';
    if (contactName.isEmpty) return;
    final phone = fullContact.phones.isEmpty
        ? null
        : fullContact.phones.first.number.trim();
    Customer? customer;
    if (phone != null && phone.isNotEmpty) {
      customer = await widget.customerRepository.findByPhone(phone) ??
          await widget.customerRepository.createCustomer(
            name: contactName,
            phone: phone,
          );
    } else {
      final phoneCtrl = TextEditingController();
      final String? enteredPhone;
      try {
        enteredPhone = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Phone Number Required'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  'Phone number is compulsory to create orders for "$contactName":'),
              const SizedBox(height: 12),
              TextField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Phone Number *',
                  hintText: 'e.g. 9876543210',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('CANCEL')),
            FilledButton(
              onPressed: () {
                final p =
                    phoneCtrl.text.replaceAll(RegExp(r'[^0-9]'), '').trim();
                if (p.length < 6) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(
                        content: Text('Please enter at least 6 digits')),
                  );
                  return;
                }
                Navigator.pop(ctx, phoneCtrl.text.trim());
              },
              child: const Text('SAVE'),
            ),
          ],
        ),
      );
      } finally {
        phoneCtrl.dispose();
      }
      if (enteredPhone == null || !mounted) return;
      customer = await widget.customerRepository.createCustomer(
        name: contactName,
        phone: enteredPhone,
      );
    }
    if (!mounted) return;
    setState(() => _selected = customer);
    await _loadCustomers();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${s.t('customer')} ${customer.name} selected'),
      duration: const Duration(seconds: 3),
    ));

  }

  Future<void> _proceedWithCustomer(Customer customer) async {
    final cleanP =
        customer.phone?.replaceAll(RegExp(r'[^0-9]'), '').trim() ?? '';
    if (cleanP.length < 6) {
      final phoneCtrl = TextEditingController();
      final String? savedPhone;
      try {
        savedPhone = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Phone Number Required',
              style: TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Phone number is compulsory to create an order for "${customer.name}":',
                style: const TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Phone Number *',
                  hintText: 'e.g. 9876543210',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('CANCEL'),
            ),
            FilledButton(
              onPressed: () {
                final p =
                    phoneCtrl.text.replaceAll(RegExp(r'[^0-9]'), '').trim();
                if (p.length < 6) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(
                        content: Text(
                            'Please enter a valid phone number (at least 6 digits)')),
                  );
                  return;
                }
                Navigator.pop(ctx, phoneCtrl.text.trim());
              },
              child: const Text('SAVE & CONTINUE'),
            ),
          ],
        ),
      );
      } finally {
        phoneCtrl.dispose();
      }

      if (savedPhone == null || !mounted) return;
      if (customer.id != null) {
        await widget.customerRepository.updateCustomer(
          id: customer.id!,
          name: customer.name,
          phone: savedPhone,
          address: customer.address,
        );
        customer = (await widget.customerRepository
                .getCustomerById(customer.id!)) ??
            customer.copyWith(phone: savedPhone);
      } else {
        customer = await widget.customerRepository.createCustomer(
          name: customer.name,
          phone: savedPhone,
          address: customer.address,
        );
      }
      if (!mounted) return;
      setState(() => _selected = customer);
      await _loadCustomers();
    }

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ProductSelectionScreen(
          customer: customer,
          productRepository: widget.productRepository,
          orderRepository: widget.orderRepository,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final query = _searchController.text.trim().toLowerCase();
    final visibleContacts = _deviceContacts.where((contact) {
      return query.isEmpty ||
          (contact.displayName ?? '').toLowerCase().contains(query);
    }).toList();
    final totalRows = _customers.length + visibleContacts.length;

    return Scaffold(
      appBar: AppBar(
        title: Text(s.t('newOrderSelectCustomer')),
        actions: [
          IconButton(
            tooltip: 'Import Customers from Excel / CSV',
            icon: const Icon(Icons.file_upload_outlined),
            onPressed: _importCustomersFile,
          ),
          IconButton(
            tooltip: s.t('addCustomer'),
            icon: const Icon(Icons.person_add_alt_1),
            onPressed: _showAddCustomerDialog,
          ),
          IconButton(
            tooltip: 'Phone contacts',
            icon: _contactsLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    _contactsEnabled
                        ? Icons.contacts
                        : Icons.contacts_outlined,
                  ),
            onPressed: _contactsLoading ? null : _enableContacts,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: <Widget>[
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: s.t('searchCustomer'),
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_searchController.text.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          _loadCustomers();
                        },
                      ),
                    IconButton(
                      tooltip: 'Voice Search Customer',
                      icon: const Icon(Icons.mic, color: Color(0xFF0F766E), size: 20),
                      onPressed: () async {
                        final text = await VoiceSearchService.instance
                            .recordSpeech(
                          context,
                          title: 'Search Customer',
                          hint: 'Say customer name (e.g. Srikar, Kamal)...',
                        );
                        if (text != null && text.trim().isNotEmpty) {
                          _searchController.text = text.trim();
                          _loadCustomers();
                        }
                      },
                    ),
                  ],
                ),
              ),
              onChanged: _onSearchChanged,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 10),
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: _showAddCustomerDialog,
                    icon: const Icon(Icons.add, size: 16),
                    label: Text(
                      s.t('addNewCustomer'),
                      style: const TextStyle(fontSize: 11.5),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 10),
                      visualDensity: VisualDensity.compact,
                      foregroundColor: const Color(0xFF0F766E),
                    ),
                    onPressed: _importCustomersFile,
                    icon: const Icon(Icons.file_upload_outlined, size: 16),
                    label: const Text(
                      'Import Excel',
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F766E)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 10),
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () async {
                      // Fast 1-tap Walk-in Counter Customer
                      var walkIn = _customers.cast<Customer?>().firstWhere(
                            (c) => c?.name.toLowerCase() == 'walk-in customer',
                            orElse: () => null,
                          );
                      walkIn ??= await widget.customerRepository.createCustomer(
                        name: 'Walk-in Customer',
                        phone: 'Counter Sale',
                      );
                      if (!context.mounted) return;
                      Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => ProductSelectionScreen(
                            customer: walkIn!,
                            productRepository: widget.productRepository,
                            orderRepository: widget.orderRepository,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.flash_on_rounded,
                        size: 16, color: Color(0xFFD97706)),
                    label: const Text(
                      'Walk-in',
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFD97706)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : totalRows == 0
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.person_search_outlined,
                                  size: 48, color: Colors.grey.shade400),
                              const SizedBox(height: 12),
                              Text(
                                'No customers found',
                                style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey.shade600),
                              ),
                              const SizedBox(height: 8),
                              FilledButton.tonalIcon(
                                onPressed: _showAddCustomerDialog,
                                icon: const Icon(Icons.add, size: 16),
                                label: Text(s.t('addNewCustomer')),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          itemCount: totalRows,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            if (index >= _customers.length) {
                              final contact =
                                  visibleContacts[index - _customers.length];
                              return Card(
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 4),
                                  leading: CircleAvatar(
                                    backgroundColor: Colors.blue.shade50,
                                    foregroundColor: Colors.blue.shade800,
                                    child: const Icon(Icons.person_outline),
                                  ),
                                  title: Text(
                                    contact.displayName ?? '',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600),
                                  ),
                                  subtitle: const Text('Phone contact',
                                      style: TextStyle(fontSize: 12)),
                                  trailing: const Icon(
                                      Icons.add_circle_outline,
                                      color: Color(0xFF0F766E)),
                                  onTap: () => _selectContact(contact),
                                ),
                              );
                            }
                            final customer = _customers[index];
                            final selected = _selected?.id == customer.id;
                            return Card(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                                side: BorderSide(
                                  color: selected
                                      ? const Color(0xFF0F766E)
                                      : const Color(0xFFE2E8F0),
                                  width: selected ? 1.8 : 1,
                                ),
                              ),
                              color: selected
                                  ? const Color(0xFFF0FDFA)
                                  : Colors.white,
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 4),
                                onTap: () =>
                                    setState(() => _selected = customer),
                                onLongPress: () =>
                                    _showEditCustomerDialog(customer),
                                leading: CircleAvatar(
                                  backgroundColor: selected
                                      ? const Color(0xFF0F766E)
                                      : Theme.of(context)
                                          .colorScheme
                                          .primaryContainer,
                                  foregroundColor: selected
                                      ? Colors.white
                                      : Theme.of(context).colorScheme.primary,
                                  child: Text(
                                    customer.name.isNotEmpty
                                        ? customer.name[0].toUpperCase()
                                        : 'C',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold),
                                  ),
                                ),
                                title: Text(
                                  customer.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(Icons.phone_outlined,
                                            size: 13,
                                            color: Colors.grey.shade500),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            customer.phone?.isNotEmpty == true
                                                ? customer.displayPhone
                                                : s.t('phoneNotAdded'),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                                color: Colors.grey.shade600,
                                                fontSize: 12),
                                          ),
                                        ),
                                        if (customer.hasMultiplePhones) ...[
                                          const SizedBox(width: 4),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 5, vertical: 1),
                                            decoration: BoxDecoration(
                                              color: Colors.blue.shade50,
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                              border: Border.all(
                                                  color: Colors.blue.shade200,
                                                  width: 0.5),
                                            ),
                                            child: Text(
                                              '${customer.phoneNumbers.length} phones',
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
                                    if (customer.creditLimit > 0) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        'Credit Limit: ₹ ${customer.creditLimit.toStringAsFixed(0)}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.teal.shade800,
                                        ),
                                      ),
                                    ],
                                      Builder(
                                        builder: (_) {
                                          final balance = customer.id != null
                                              ? (_customerBalances[customer.id!] ?? 0.0)
                                              : 0.0;
                                          if (balance < -0.01) {
                                            return Container(
                                              margin: const EdgeInsets.only(top: 4),
                                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFCCFBF1),
                                                borderRadius: BorderRadius.circular(6),
                                                border: Border.all(color: const Color(0xFF0F766E), width: 0.8),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  const Icon(Icons.account_balance_wallet, size: 12, color: Color(0xFF0F766E)),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    'Advance: ₹ ${(-balance % 1 == 0) ? (-balance).toInt() : (-balance).toStringAsFixed(2)}',
                                                    style: const TextStyle(
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.w800,
                                                      color: Color(0xFF0F766E),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            );
                                          } else if (balance > 0.01) {
                                            return Container(
                                              margin: const EdgeInsets.only(top: 4),
                                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: Colors.red.shade50,
                                                borderRadius: BorderRadius.circular(6),
                                                border: Border.all(color: Colors.red.shade300, width: 0.8),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(Icons.warning_amber_rounded, size: 12, color: Colors.red.shade800),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    'Khata Due: ₹ ' + ((balance % 1 == 0) ? balance.toInt().toString() : balance.toStringAsFixed(2)),
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.w800,
                                                      color: Colors.red.shade900,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            );
                                          }
                                          return const SizedBox.shrink();
                                        },
                                      ),
                                  ],
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (selected) ...[
                                      const Icon(Icons.check_circle,
                                          color: Color(0xFF0F766E), size: 22),
                                      const SizedBox(width: 4),
                                    ],
                                    PopupMenuButton<String>(
                                      icon:
                                          const Icon(Icons.more_vert, size: 20),
                                      onSelected: (value) {
                                        if (value == 'edit') {
                                          _showEditCustomerDialog(customer);
                                        } else if (value == 'delete') {
                                          _confirmDeleteCustomer(customer);
                                        }
                                      },
                                      itemBuilder: (context) => [
                                        const PopupMenuItem<String>(
                                          value: 'edit',
                                          child: Row(
                                            children: [
                                              Icon(Icons.edit_outlined,
                                                  size: 18),
                                              SizedBox(width: 8),
                                              Text('Edit Customer'),
                                            ],
                                          ),
                                        ),
                                        const PopupMenuItem<String>(
                                          value: 'delete',
                                          child: Row(
                                            children: [
                                              Icon(Icons.delete_outline,
                                                  size: 18, color: Colors.red),
                                              SizedBox(width: 8),
                                              Text('Delete Customer',
                                                  style: TextStyle(
                                                      color: Colors.red)),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),
            const SizedBox(height: 12),
            if (_selected != null)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDFA),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color:
                          const Color(0xFF0F766E).withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle,
                        color: Color(0xFF0F766E), size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Selected: ${_selected!.name}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F766E),
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            LargeActionButton(
              label:
                  _selected == null ? 'SELECT A CUSTOMER' : '${s.t('next')} →',
              onTap: _selected == null
                  ? null
                  : () => _proceedWithCustomer(_selected!),
            ),
          ],
        ),
      ),
    );
  }
}
