# Developer One-Time Patch & Migration Scripts History

This directory contains historical developer utility scripts written during code refactoring and bug fixing sessions.

> **Important**: These Python scripts are **NOT** part of the Flutter app runtime. All code transformations and logic changes they performed have already been directly and permanently implemented in the main Dart codebase (`lib/`).

---

### Scripts Summary

| Script Name | Purpose | Affected Production Dart Files |
| :--- | :--- | :--- |
| `apply_customer_bill_sequence.py` | Updated bill sharing & printing to display customer-specific sequential numbers (`Bill #1`, `Bill #2`...) alongside `#ORD-xxxx` | `lib/services/share_service.dart`<br>`lib/services/invoice_pdf_service.dart` |
| `apply_screen_fixes.py` | Added advance balance detection banner in order preview screen | `lib/screens/order_preview_screen.dart` |
| `fix_flaws.py` | Synced order payments into customer Khata ledger (`recordOrderPayment`), added `advance_credit`, and ensured pending order statistics only count orders with unfulfilled items | `lib/database/database_helper.dart`<br>`lib/repositories/order_repository.dart` |
| `update_code.py` | Updated customer orders list UI to display sequential bill numbers per customer | `lib/screens/customer_orders_screen.dart` |
| `update_passbook.py` | Added `#ORD-xxxx` order badge to Khata Book passbook debit ledger rows | `lib/screens/customer_khata_passbook_screen.dart` |

---

### Production Code Location
The actual production application code lives under:
- `lib/database/` - SQLite database helpers & queries
- `lib/models/` - Data models & bill breakdown logic
- `lib/repositories/` - Data repositories & statistics
- `lib/screens/` - Flutter UI screens
- `lib/services/` - WhatsApp sharing, PDF generation, printing, sync
