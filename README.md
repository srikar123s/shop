# Hardware Shop Operating System (Shop Wholesale & Shop Retail)

A specialized, offline-first point-of-sale (POS), inventory procurement, and contractor ledger (Khata) management system tailored for family-run wholesale and retail hardware, building materials, and paint stores.

---

## 📱 Dual Production APK Flavors

The project compiles into two distinct production applications, designed to run side-by-side or independently:

| Application | APK File Name | Target Use Case | Architecture |
|---|---|---|---|
| **Shop Wholesale** | `app-wholesale-cloud-release.apk` | Multi-counter store management, contractor ledgers, family collaboration, godown procurement | SQLite + Real-time Cloud Sync + Family Device Pairing |
| **Shop Retail** | `app-retail-local-release.apk` | Fast single-counter billing, walk-in customer checkout | Pure Standalone SQLite (Zero cloud overhead, 100% offline) |

---

## 🛠️ Complete Feature Architecture

### 1. Dual Device Roles: Master & Partner (Family Collaboration)
* **Master Device (👑)**: The primary phone that creates the shop profile, configures settings, and sets permissions.
* **Partner Devices (👥)**: Family members (e.g., Srikar, Sridevi, Amma) connect using the shop's 6-character code (e.g. `SH-MG27`) or QR code.
* **Interactive Approval**: Connecting partner devices require explicit one-tap approval on the Master Device before gaining access.
* **Role Permissions**: Master Device can grant or revoke permissions:
  * Allow Changing Unit Prices
  * Allow Closing Counter Orders
  * Allow Editing Quantity Step Shortcuts
  * Allow Viewing Grand Totals

---

### 2. Live Dashboard & Counter Status
* **Pending Orders Card**:
  * Displays the live count of open counter orders.
  * Highlights overdue orders with an amber/red `>3 days ⚠️` badge and note: *"X need immediate close"*.
  * Tapping navigates directly to the History screen pre-filtered by `Pending / Open`.
* **Procurement Card**:
  * Displays the live count of items needing distributor procurement or godown fetching (*"X to Procure"* or *"All fulfilled 🎉"*).
  * Tapping navigates directly to the Procurement List screen.
* **Price Volatility Alert**:
  * In volatile market conditions, items whose prices haven't been reviewed within configurable days (default 30 days) trigger an alert banner below the header.
  * Tapping navigates directly to **Manage Products**.
* **Review Indicator on Manage Products**:
  * Amber badge highlights when items were added on-the-fly and need price/option review.

---

### 3. Order Creation, Search & Auto-Cataloging
* **Case-Insensitive Search**: Matches uppercase and lowercase queries equally (e.g., `paint`, `Paint`, `PAINT`).
* **Inline Auto-Cataloging**:
  * When a customer requests an unlisted item, typing the name displays an instant button: **"Add [Item] to Cart & Catalog"**.
  * The item is added to the cart and saved into the SQLite product catalog with a `needs_review = 1` flag.
* **Voice Search AI**:
  * 1-tap microphone button supporting Telugu, Hindi, and English.
  * Audio waveform visualization with automatic query triggering upon speech silence.
* **Hierarchical Option Matrix**:
  * Handles multi-step variations (Size → Colour → Brand) with combination-specific pricing (e.g. Paints: Red 1L vs Red 10L; Cut-off wheels: 4-inch vs 14-inch).
* **Speed Quantity Chips**:
  * Quick-tap buttons (`+1`, `+5`, `+6`, `+10`, `+12`, `+50`, `+100`) for carton, dozen, and bulk pack sizes.
* **Draft Auto-Recovery**:
  * Active carts are preserved across unexpected phone calls or app restarts with instant restoration.

---

### 4. Fulfillment & Intentional Less Stock (90/10 Shortage Cutting)
* **Dual-Linked Fulfillment Controls**:
  * Each order item features synchronized **GIVEN** and **NOT GIVEN (SHORT)** counters. Adjusting one immediately recalculates the other.
* **1-Tap Quick Fulfillment Chips**:
  * `[All Given]`: Fulfills 100% of ordered units.
  * `[1 Short]`, `[2 Short]`, `[5 Short]`: Instantly sets common shortage quantities.
  * `[None Given]`: Sets given quantity to 0 when stock is completely unavailable.
* **"✂ Finalize at X (Don't Procure / Cut Shortage)"**:
  * Solves the practical scenario where the shop intentionally delivers fewer items (e.g., customer ordered 12, counter delivers 7 and agrees not to supply the remaining 5).
  * Sets both `quantity_ordered` and `quantity_given` to the delivered amount (e.g. 7).
  * Drops the shortage from godown procurement.
  * Recalculates the bill subtotal, taxes, and grand total strictly for the delivered units.
* **Order Closing Partial Settlement**:
  * Closing an order with partial items prompts: *"Adjust Bill for Given Items & Close"*.
  * Persists on-screen counters, drops remaining godown shortages, and locks the bill to match delivered items with zero discrepancies.
* **1-Tap Repeat Order (🔁)**:
  * Duplicates a past bill with all item specifications into a new active cart in 1 second.

---

### 5. Procurement Management & Godown Workflow
* **Centralized Procurement Screen**:
  * Aggregates shortages and non-catalog items across all active orders into a single list.
  * Grouped by category (Paints, Hardware, Tools) with customer names, order IDs, and creator attribution.
* **1-Tap "Mark as Procured"**:
  * Individual item mark-as-procured and bulk *"Mark All as Procured"*.
  * Automatically updates order line items to delivered and marks orders completed when all items arrive.
* **✂ Cut Shortage from Procurement**:
  * Drop unfulfillable items directly from the procurement screen when distributors run out of stock; automatically recalculates customer bills.

---

### 6. Khata Book (Contractor Ledgers) & Locked Read-Only Receipts
* **Locked Read-Only Bills**:
  * Closed orders posted to Khata Book are permanently immutable.
  * Tapping a bill from Khata Book opens a read-only receipt view (matching the WhatsApp receipt layout) clearly displaying items, rates, taxes, and collected amounts (Cash or UPI outside) with exact timestamps.
* **Dual-Tone Ledger (Passbook)**:
  * 🔴 **YOU GAVE**: Debit entries for credit bills and manual loans.
  * 🟢 **YOU GOT**: Credit entries for cash/UPI/cheque collections.
  * Running balance updated after every transaction.
* **Debt Ageing & Overdue Tracking**:
  * Badges indicate pending debt duration (e.g. `⚠️ 45 days overdue`).
  * 1-tap filter for accounts overdue >30 days.
* **WhatsApp Reminders with Direct UPI Payment Link**:
  * Sends reminders with a pre-filled UPI payment link (`upi://pay?pa=...&am=...`). Customers tap the link to open PhonePe/GPay with the exact amount pre-filled.
* **Reports & Dynamic QR**:
  * Generates A4 Customer Statement PDFs with embedded Dynamic UPI QR codes.
  * Generates a 1-page Market Udhaar Summary PDF.
  * NPCI-compliant dynamic UPI QR code generation on any bill.

---

### 7. Background Notifications & Configurable Timers
* **Automated Daily Alerts**:
  * Scheduled reminders across the business day (Morning 7:00 AM, Afternoon 1:00 PM, Evening 9:00 PM).
  * Pending order alerts, stale order alerts (>3 days old), and procurement alerts.
* **Configurable Settings**:
  * Customize notification hours and alert types in **Shop Settings → Notifications & Reminders**.
  * Configurable stale order threshold and price caution days.

---

### 8. Receipts, Invoicing & Logistics
* **Thermal POS Printing (58mm / 80mm)**: Direct printing to portable Bluetooth printers.
* **A4 PDF Tax Invoices**: Full GSTIN, itemized rates, taxes, and digital stamp/signature.
* **Delivery Challan**: Generates dispatch slips with quantities and delivery addresses while omitting prices.

---

### 9. Analytics & Day-End Closing Reports
* **Top Selling Products**: Real-time sales statistics by Today, Week, Month, or All Time (sorted by Quantity or Revenue).
* **Evening Shop Closing Report**: Computes daily turnover, payment breakdown (Cash vs UPI vs Udhaar), completed vs pending bills, and generates a 1-tap WhatsApp summary for family members.

---

## 🗄️ Database Architecture (SQLite)

Local database powered by `sqflite` with robust table structures:
* `products`: Product catalog with combination configurations, pricing, and `needs_review` flag.
* `product_options`: Step configurations (Size, Colour, Brand).
* `orders`: Order header, customer snapshot, status (`PENDING`, `PARTIALLY COMPLETED`, `COMPLETED`, `CLOSED`), payment details, notes (JSON breakdown), and attribution (`taken_by`).
* `order_items`: Line items with ordered quantity, given quantity, unit, status, and JSON `product_snapshot`.
* `order_item_options`: Selected option key-value pairs per item.
* `customers`: Customer profiles, phone numbers, credit limits, and addresses.
* `customer_payments`: Khata credit/payment transaction history.

---

## 🚀 Building & Generating APKs

Run the automated build script from the workspace root:

```cmd
.\build_both_apks.bat
```

### Build Script Actions:
1. Stops background Gradle daemons to prevent Windows file-locking.
2. Builds **App 1: Shop Wholesale** (`app-wholesale-cloud-release.apk`) with cloud sync enabled.
3. Cleans intermediate jars and compiles **App 2: Shop Retail** (`app-retail-local-release.apk`) in pure offline standalone mode.
4. Cleans all legacy build outputs, `.sha1` hashes, and duplicate APKs.
5. Leaves strictly the two official APKs in `build\app\outputs\flutter-apk\`.

---

## 🧪 Testing & Verification

Run tests and static analysis:

```cmd
flutter analyze
flutter test
```
