import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:shop/l10n/app_localizations.dart';
import 'package:shop/models/customer.dart';
import 'package:shop/repositories/customer_repository.dart';
import 'package:shop/repositories/order_repository.dart';
import 'package:shop/repositories/product_repository.dart';
import 'package:shop/screens/product_selection_screen.dart';
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

  @override
  void initState() {
    super.initState();
    _loadCustomers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCustomers() async {
    setState(() => _loading = true);
    final data =
        await widget.customerRepository.searchCustomers(_searchController.text);
    if (!mounted) return;
    setState(() {
      _customers = data;
      _loading = false;
    });
  }

  Future<void> _showAddCustomerDialog() async {
    final s = AppLocalizations.of(context);
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final addressCtrl = TextEditingController();

    final result = await showDialog<Customer>(
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
                ),
                TextField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(labelText: s.t('phone')),
                ),
                TextField(
                  controller: addressCtrl,
                  decoration: InputDecoration(labelText: s.t('address')),
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
                if (nameCtrl.text.trim().isEmpty) {
                  return;
                }
                final customer = await widget.customerRepository.createCustomer(
                  name: nameCtrl.text,
                  phone: phoneCtrl.text,
                  address: addressCtrl.text,
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

    final updated = await showDialog<bool>(
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
                  decoration: InputDecoration(labelText: s.t('phone')),
                ),
                TextField(
                  controller: addressCtrl,
                  decoration: InputDecoration(labelText: s.t('address')),
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
                await widget.customerRepository.updateCustomer(
                  id: customer.id!,
                  name: nameCtrl.text,
                  phone: phoneCtrl.text,
                  address: addressCtrl.text,
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
    final customer = phone == null
        ? await widget.customerRepository.createCustomer(name: contactName)
        : await widget.customerRepository.findByPhone(phone) ??
            await widget.customerRepository.createCustomer(
              name: contactName,
              phone: phone,
            );
    if (!mounted) return;
    setState(() => _selected = customer);
    await _loadCustomers();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${s.t('customer')} ${customer.name} selected'),
      duration: const Duration(seconds: 3),
    ));

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
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          _loadCustomers();
                        },
                      )
                    : null,
              ),
              onChanged: (_) => _loadCustomers(),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 10),
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: _showAddCustomerDialog,
                    icon: const Icon(Icons.add, size: 16),
                    label: Text(
                      s.t('addNewCustomer'),
                      style: const TextStyle(fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 10),
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: _contactsLoading ? null : _enableContacts,
                    icon: const Icon(Icons.contacts_outlined, size: 16),
                    label: const Text(
                      'Phone Contacts',
                      style: TextStyle(fontSize: 12),
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
                                subtitle: Row(
                                  children: [
                                    Icon(Icons.phone_outlined,
                                        size: 13,
                                        color: Colors.grey.shade500),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        customer.phone?.isNotEmpty == true
                                            ? customer.phone!
                                            : s.t('phoneNotAdded'),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            color: Colors.grey.shade600,
                                            fontSize: 12),
                                      ),
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
                  : () {
                      Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => ProductSelectionScreen(
                            customer: _selected!,
                            productRepository: widget.productRepository,
                            orderRepository: widget.orderRepository,
                          ),
                        ),
                      );
                    },
            ),
          ],
        ),
      ),
    );
  }
}
