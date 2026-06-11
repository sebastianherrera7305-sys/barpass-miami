/**
 * BarPass — Firestore Schema (Hardened v1.5)
 * Real-time heatmap + inventory tracking for Factory Town and multi-vendor events
 *
 * Collections:
 *   vendors          — bar/vendor locations + real-time status
 *   orders           — all customer orders (idempotent, immutable)
 *   inventory_logs   — audit trail for every product movement
 *
 * Cloud Function `updateVendorStatus` runs every 60s to power the heatmap.
 */

// ---------------------------------------------------------------------------
// COLLECTION: vendors
// ---------------------------------------------------------------------------
// Path: /vendors/{vendorId}
const VENDOR_SCHEMA = {
  id: 'String — Firestore doc ID (e.g., vendor_001)',
  name: 'String — Display name (e.g., "Bar Central", "VIP Lounge")',
  location: 'GeoPoint — lat/lng for map rendering',
  zone: 'String — Event zone label (e.g., "Main Stage", "Pool Area")',

  // Real-time fields (updated by Cloud Function every 60s)
  current_wait_time: 'Integer — estimated wait in minutes',
  status: 'Enum: OPEN | BUSY | CLOSED',
  active_orders_count: 'Integer — orders currently in PREPARING state',

  // Config
  menu_ids: 'Array<String> — product IDs this vendor serves',
  staff_ids: 'Array<String> — staff assigned tonight',
  max_capacity: 'Integer — orders before auto-BUSY',

  created_at: 'Timestamp',
  updated_at: 'Timestamp',
};

// ---------------------------------------------------------------------------
// COLLECTION: orders
// ---------------------------------------------------------------------------
// Path: /orders/{orderId}
const ORDER_SCHEMA = {
  id: 'String — Firestore doc ID',
  idempotency_key: 'String — UNIQUE INDEX: bp_{vendorId}_{staffId}_{ts}_{rand}',

  vendor_id: 'String — ref to /vendors/{vendorId}',
  staff_id: 'String — bartender who processed',
  customer_id: 'String | null — FastPass member ID if scanned',

  items: [
    {
      product_id: 'String',
      name: 'String',
      qty: 'Integer',
      unit_price: 'Number',
      line_total: 'Number',
    },
  ],

  subtotal: 'Number',
  tax: 'Number',      // 7% FL
  discount: 'Number', // amount discounted
  total: 'Number',

  payment_method: 'Enum: card | apple_pay | cash | rfid',
  stripe_payment_intent_id: 'String | null',

  status: 'Enum: PENDING | PREPARING | READY | COMPLETED | REFUNDED',

  created_at: 'Timestamp',
  updated_at: 'Timestamp',
  completed_at: 'Timestamp | null',
};

// ---------------------------------------------------------------------------
// COLLECTION: inventory_logs
// ---------------------------------------------------------------------------
// Path: /inventory_logs/{logId}
// Append-only audit trail — never update, only add documents
const INVENTORY_LOG_SCHEMA = {
  id: 'String — Firestore doc ID',
  vendor_id: 'String',
  product_id: 'String',
  product_name: 'String',

  change_type: 'Enum: SALE | REFUND | RESTOCK | WASTE | ADJUSTMENT',
  qty_change: 'Integer — negative for deductions, positive for additions',
  qty_after: 'Integer — running balance after this event',

  order_id: 'String | null — linked order if SALE or REFUND',
  staff_id: 'String — who made the change',
  note: 'String | null — optional note (e.g., "bottle broke")',

  created_at: 'Timestamp',
};

// ---------------------------------------------------------------------------
// FIRESTORE INDEXES (create in Firebase Console or firestore.indexes.json)
// ---------------------------------------------------------------------------
const FIRESTORE_INDEXES = [
  // Heatmap query: all PREPARING orders for a vendor
  {
    collectionGroup: 'orders',
    fields: [
      { fieldPath: 'vendor_id', order: 'ASCENDING' },
      { fieldPath: 'status', order: 'ASCENDING' },
      { fieldPath: 'created_at', order: 'DESCENDING' },
    ],
  },
  // Idempotency check
  {
    collectionGroup: 'orders',
    fields: [{ fieldPath: 'idempotency_key', order: 'ASCENDING' }],
  },
  // Inventory audit by vendor + product
  {
    collectionGroup: 'inventory_logs',
    fields: [
      { fieldPath: 'vendor_id', order: 'ASCENDING' },
      { fieldPath: 'product_id', order: 'ASCENDING' },
      { fieldPath: 'created_at', order: 'DESCENDING' },
    ],
  },
];

// ---------------------------------------------------------------------------
// FIRESTORE SECURITY RULES (paste into Firebase Console → Rules)
// ---------------------------------------------------------------------------
const FIRESTORE_RULES = `
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {

    // Vendors: read by all authenticated users, write only by backend service
    match /vendors/{vendorId} {
      allow read: if request.auth != null;
      allow write: if request.auth.token.role == 'service';
    }

    // Orders: staff can read their vendor's orders; only backend can write
    match /orders/{orderId} {
      allow read: if request.auth != null
        && request.auth.token.vendor_id == resource.data.vendor_id;
      allow create: if request.auth.token.role == 'service';
      allow update: if request.auth.token.role == 'service';
    }

    // Inventory logs: append-only; no deletes ever
    match /inventory_logs/{logId} {
      allow read: if request.auth.token.role in ['manager', 'owner', 'service'];
      allow create: if request.auth.token.role == 'service';
      allow delete: if false;  // NEVER allow deletes
    }
  }
}
`;

module.exports = {
  VENDOR_SCHEMA,
  ORDER_SCHEMA,
  INVENTORY_LOG_SCHEMA,
  FIRESTORE_INDEXES,
  FIRESTORE_RULES,
};
