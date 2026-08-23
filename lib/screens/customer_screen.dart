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

  Future<void> _enableContacts() async {
    final status =
        await FlutterContacts.permissions.request(PermissionType.read);
    if (!mounted) return;
    if (status != PermissionStatus.granted &&
        status != PermissionStatus.limited) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('Contacts permission is needed to choose a customer.')),
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
      SnackBar(content: Text('${contacts.length} contacts loaded')),
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
      appBar: AppBar(title: Text(s.t('newOrderSelectCustomer'))),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: <Widget>[
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: s.t('searchCustomer'),
                prefixIcon: IconButton(
                  tooltip: 'Load phone contacts',
                  onPressed: _contactsLoading ? null : _enableContacts,
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
                ),
                suffixIcon: IconButton(
                  onPressed: _loadCustomers,
                  icon: const Icon(Icons.search),
                ),
              ),
              onChanged: (_) => _loadCustomers(),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      itemCount: totalRows,
                      itemBuilder: (context, index) {
                        if (index >= _customers.length) {
                          final contact =
                              visibleContacts[index - _customers.length];
                          return Card(
                            child: ListTile(
                              leading: const CircleAvatar(
                                child: Icon(Icons.person_outline),
                              ),
                              title: Text(contact.displayName ?? ''),
                              subtitle: const Text('Phone contact'),
                              trailing: const Icon(Icons.add_circle_outline),
                              onTap: () => _selectContact(contact),
                            ),
                          );
                        }
                        final customer = _customers[index];
                        final selected = _selected?.id == customer.id;
                        return Card(
                          child: ListTile(
                            title: Text(customer.name),
                            subtitle: Text(
                              customer.phone?.isNotEmpty == true
                                  ? customer.phone!
                                  : s.t('phoneNotAdded'),
                            ),
                            trailing: selected
                                ? const Icon(Icons.check_circle)
                                : null,
                            selected: selected,
                            onTap: () => setState(() => _selected = customer),
                          ),
                        );
                      },
                    ),
            ),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _enableContacts,
                    icon: const Icon(Icons.contacts_outlined),
                    label: const Text('CHOOSE FROM CONTACTS'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _showAddCustomerDialog,
                    icon: const Icon(Icons.person_add_alt_1_outlined),
                    label: Text(s.t('addCustomer')),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            LargeActionButton(
              label: s.t('next'),
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
