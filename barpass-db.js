/**
 * BarPass Enterprise Data Engine — barpass-db.js
 * Central state, transactions, inventory, analytics, automation
 * All modules (POS, Stadium, Runner, Analytics) share this layer.
 */
'use strict';
(function (global) {

  const STORE_KEY = 'bp_enterprise_v1';
  const STORE_VER = 4;

  // ── Default schema ──────────────────────────────────────────────────────────
  function defaults() {
    return {
      version: STORE_VER,
      settings: {
        venue: 'Hard Rock Stadium',
        taxRate: 0.07,
        defaultTip: 0.18,
        lowStockPct: 0.20,
        criticalStockPct: 0.10,
        autoDispatchEnabled: true,
        currency: 'USD',
        timezone: 'America/New_York',
      },
      inventory: {
        'bar-01': { name: 'Main Bar', zone: 'A', type: 'bar', items: baseInventory() },
        'bar-02': { name: 'VIP Lounge', zone: 'VIP', type: 'bar', items: baseInventory(true) },
        'bar-03': { name: 'Field Bar', zone: 'B', type: 'bar', items: baseInventory() },
        'bar-04': { name: 'Concourse East', zone: 'C', type: 'bar', items: baseInventory() },
        'hub-01': { name: 'Hub West', zone: 'HUB', type: 'hub', items: hubInventory() },
        'hub-02': { name: 'Hub North', zone: 'HUB', type: 'hub', items: hubInventory() },
      },
      transactions: [],
      dispatches: [],
      alerts: [],
      staff: {},
      shifts: [],
      reports: [],
      restockOrders: [],
      automationRules: defaultRules(),
      automationLog: [],
      suppliers: defaultSuppliers(),
    };
  }

  function baseInventory(vip = false) {
    const mult = vip ? 0.6 : 1;
    return {
      'beer-domestic': { name: 'Domestic Beer', cat: 'Beer', emoji: '🍺', qty: Math.round(240 * mult), min: 48, max: Math.round(480 * mult), price: 9, cost: 2.50, unit: 'can', sku: 'BEV-BEER-DOM' },
      'beer-craft':    { name: 'Craft IPA',       cat: 'Beer', emoji: '🍺', qty: Math.round(96 * mult),  min: 24, max: Math.round(192 * mult), price: 14, cost: 4.00, unit: 'can', sku: 'BEV-BEER-CRA' },
      'spirits-vodka': { name: 'Vodka Shot',       cat: 'Spirits', emoji: '🥃', qty: Math.round(80 * mult),  min: 20, max: Math.round(160 * mult), price: 14, cost: 3.50, unit: 'shot', sku: 'BEV-SPR-VOD' },
      'spirits-whiskey':{ name: 'Whiskey',         cat: 'Spirits', emoji: '🥃', qty: Math.round(60 * mult),  min: 15, max: Math.round(120 * mult), price: 16, cost: 5.00, unit: 'shot', sku: 'BEV-SPR-WHI' },
      'spirits-tequila':{ name: 'Tequila',         cat: 'Spirits', emoji: '🥃', qty: Math.round(50 * mult),  min: 12, max: Math.round(100 * mult), price: 15, cost: 4.50, unit: 'shot', sku: 'BEV-SPR-TEQ' },
      'cocktail-mojito':{ name: 'Mojito',          cat: 'Cocktail', emoji: '🍹', qty: Math.round(40 * mult),  min: 10, max: Math.round(80 * mult),  price: 18, cost: 5.00, unit: 'glass', sku: 'BEV-CKT-MOJ' },
      'cocktail-mgm':   { name: 'Margarita',       cat: 'Cocktail', emoji: '🍹', qty: Math.round(40 * mult),  min: 10, max: Math.round(80 * mult),  price: 17, cost: 4.50, unit: 'glass', sku: 'BEV-CKT-MAR' },
      'wine-red':       { name: 'Red Wine',        cat: 'Wine', emoji: '🍷', qty: Math.round(72 * mult),  min: 18, max: Math.round(144 * mult), price: 14, cost: 3.50, unit: 'glass', sku: 'BEV-WIN-RED' },
      'wine-white':     { name: 'White Wine',      cat: 'Wine', emoji: '🥂', qty: Math.round(60 * mult),  min: 15, max: Math.round(120 * mult), price: 13, cost: 3.00, unit: 'glass', sku: 'BEV-WIN-WHI' },
      'na-water':       { name: 'Water',           cat: 'N/A', emoji: '💧', qty: Math.round(200 * mult), min: 50, max: Math.round(400 * mult), price: 4,  cost: 0.50, unit: 'bottle', sku: 'BEV-NA-WAT' },
      'na-soda':        { name: 'Soda',            cat: 'N/A', emoji: '🥤', qty: Math.round(150 * mult), min: 40, max: Math.round(300 * mult), price: 5,  cost: 0.75, unit: 'can', sku: 'BEV-NA-SOD' },
      'food-nachos':    { name: 'Nachos',          cat: 'Food', emoji: '🌮', qty: Math.round(60 * mult),  min: 15, max: Math.round(120 * mult), price: 12, cost: 3.00, unit: 'portion', sku: 'FD-NAC-001' },
      'food-hotdog':    { name: 'Hot Dog',         cat: 'Food', emoji: '🌭', qty: Math.round(80 * mult),  min: 20, max: Math.round(160 * mult), price: 10, cost: 2.50, unit: 'unit', sku: 'FD-HDG-001' },
    };
  }

  function hubInventory() {
    // Hubs hold bulk stock for restocking bars
    const items = baseInventory();
    Object.values(items).forEach(sku => {
      sku.qty = sku.max * 3;
      sku.max = sku.max * 5;
      sku.min = sku.max * 0.2;
    });
    return items;
  }

  // ── Default automation rules ────────────────────────────────────────────────
  function defaultRules() {
    return [
      {
        id: 'rule-001', enabled: true, name: 'Auto-dispatch on CRITICAL stock',
        description: 'When any bar drops below 10% stock, auto-create a runner dispatch from the nearest hub.',
        trigger: { type: 'inventory_threshold', barType: 'bar', threshold: 0.10, comparison: 'lte' },
        action:  { type: 'create_dispatch', fromHub: 'hub-01', priority: 'HIGH', note: 'AUTO: Critical restock' },
        cooldown: 1800000, lastFired: null, fireCount: 0,
      },
      {
        id: 'rule-002', enabled: true, name: 'Alert manager on LOW stock',
        description: 'Send an alert to the manager dashboard when any SKU drops below 20%.',
        trigger: { type: 'inventory_threshold', barType: 'bar', threshold: 0.20, comparison: 'lte' },
        action:  { type: 'create_alert', severity: 'LOW', message: 'Inventory below 20% — review required' },
        cooldown: 900000, lastFired: null, fireCount: 0,
      },
      {
        id: 'rule-003', enabled: true, name: 'Auto-restock order when hub runs low',
        description: 'When a hub drops below 30% on any SKU, create a supplier restock order automatically.',
        trigger: { type: 'inventory_threshold', barType: 'hub', threshold: 0.30, comparison: 'lte' },
        action:  { type: 'create_restock_order', supplierId: 'sup-001', urgency: 'standard' },
        cooldown: 3600000, lastFired: null, fireCount: 0,
      },
      {
        id: 'rule-004', enabled: false, name: 'End-of-shift inventory snapshot',
        description: 'Every day at 11 PM, record a full inventory snapshot and generate a shift report.',
        trigger: { type: 'schedule', cron: '0 23 * * *' },
        action:  { type: 'generate_report', reportType: 'shift_summary' },
        cooldown: 82800000, lastFired: null, fireCount: 0,
      },
    ];
  }

  // ── Default suppliers ────────────────────────────────────────────────────────
  function defaultSuppliers() {
    return [
      { id: 'sup-001', name: 'Miami Beverage Co.', contact: 'Juan Pérez', phone: '+1-305-555-0101', email: 'orders@miamibev.com', leadTimeDays: 2, categories: ['Beer', 'N/A'], rating: 4.8 },
      { id: 'sup-002', name: 'Premium Spirits LLC', contact: 'Sarah K.',  phone: '+1-305-555-0202', email: 'orders@premspirits.com', leadTimeDays: 3, categories: ['Spirits', 'Cocktail'], rating: 4.5 },
      { id: 'sup-003', name: 'SunVine Wines',       contact: 'Carlos M.', phone: '+1-305-555-0303', email: 'orders@sunvine.com', leadTimeDays: 4, categories: ['Wine'], rating: 4.7 },
      { id: 'sup-004', name: 'Stadium Foods Inc.',  contact: 'Lisa T.',   phone: '+1-305-555-0404', email: 'orders@stadiumfoods.com', leadTimeDays: 1, categories: ['Food'], rating: 4.6 },
    ];
  }

  // ── BPDB ────────────────────────────────────────────────────────────────────
  const BPDB = {
    _d: null,
    _listeners: {},
    ready: false,

    // ── Init ──────────────────────────────────────────────────────────────────
    init() {
      try {
        const raw = localStorage.getItem(STORE_KEY);
        if (raw) {
          this._d = JSON.parse(raw);
          // Migrate if needed
          if (!this._d.version || this._d.version < STORE_VER) {
            const fresh = defaults();
            // Preserve transactions and settings, refresh schema
            this._d = Object.assign(fresh, {
              transactions: this._d.transactions || [],
              settings: Object.assign(fresh.settings, this._d.settings || {}),
            });
            this._d.version = STORE_VER;
          }
        } else {
          this._d = defaults();
          this._seedDemo();
        }
      } catch (e) {
        console.warn('[BPDB] Init error, resetting:', e);
        this._d = defaults();
        this._seedDemo();
      }
      this._save();
      this.ready = true;
      this.emit('ready', null);
      console.log('[BPDB] Ready —', this._d.transactions.length, 'transactions,', Object.keys(this._d.inventory).length, 'locations');
      return this;
    },

    _save() {
      try { localStorage.setItem(STORE_KEY, JSON.stringify(this._d)); } catch (e) {
        console.warn('[BPDB] Save failed (storage full?):', e);
      }
    },

    // ── Events ────────────────────────────────────────────────────────────────
    on(event, cb) {
      if (!this._listeners[event]) this._listeners[event] = [];
      this._listeners[event].push(cb);
      return () => { this._listeners[event] = this._listeners[event].filter(f => f !== cb); };
    },

    emit(event, data) {
      (this._listeners[event] || []).forEach(cb => { try { cb(data); } catch(e) {} });
      // Also emit wildcard
      (this._listeners['*'] || []).forEach(cb => { try { cb({ event, data }); } catch(e) {} });
    },

    // ── TRANSACTIONS ──────────────────────────────────────────────────────────
    recordTransaction(txn) {
      const s = this._d.settings;
      const sub  = txn.subtotal || txn.items.reduce((acc, i) => acc + (i.price || 0), 0);
      const disc = txn.discount || 0;
      const tax  = (sub - disc) * s.taxRate;
      const total = sub - disc + tax;

      const t = {
        id:            'TXN-' + Date.now().toString(36).toUpperCase() + '-' + Math.random().toString(36).slice(2, 5).toUpperCase(),
        ts:            Date.now(),
        barId:         txn.barId         || 'bar-01',
        staffId:       txn.staffId       || 'anon',
        staffName:     txn.staffName     || 'Staff',
        items:         (txn.items || []).map(i => ({ name: i.name, emoji: i.emoji || '📦', price: i.price || 0, skuId: i.skuId || null, cat: i.cat || i.dt || 'other' })),
        subtotal:      sub,
        discount:      disc,
        discountLabel: txn.discountLabel || null,
        tax,
        total,
        paymentMethod: txn.paymentMethod || 'card',
        customerName:  txn.customerName  || 'Guest',
        tableId:       txn.tableId       || null,
        shift:         this._currentShift(),
        receiptId:     'RCP-' + Date.now().toString(36).toUpperCase(),
      };

      this._d.transactions.push(t);

      // Decrement inventory for each item with a known skuId
      t.items.forEach(item => {
        if (item.skuId) {
          this.updateInventory(t.barId, item.skuId, -1, 'SALE', t.id);
        }
      });

      this._save();
      this.emit('transaction:new', t);
      this.emit('sales:updated', this.getSalesMetrics());
      return t;
    },

    getTransactions({ barId, staffId, from, to, limit, shift } = {}) {
      let list = [...this._d.transactions];
      if (barId)   list = list.filter(t => t.barId === barId);
      if (staffId) list = list.filter(t => t.staffId === staffId);
      if (from)    list = list.filter(t => t.ts >= from);
      if (to)      list = list.filter(t => t.ts <= to);
      if (shift)   list = list.filter(t => t.shift === shift);
      list.sort((a, b) => b.ts - a.ts);
      if (limit)   list = list.slice(0, limit);
      return list;
    },

    // ── INVENTORY ─────────────────────────────────────────────────────────────
    getInventory(barId) {
      return this._d.inventory[barId] || null;
    },

    getAllInventory() {
      return this._d.inventory;
    },

    getSkuLevel(barId, skuId) {
      const bar = this._d.inventory[barId];
      if (!bar) return null;
      const sku = bar.items[skuId];
      if (!sku) return null;
      return { ...sku, pct: sku.qty / sku.max };
    },

    updateInventory(barId, skuId, delta, reason = 'MANUAL', ref = null) {
      const bar = this._d.inventory[barId];
      if (!bar || !bar.items[skuId]) return null;
      const sku = bar.items[skuId];
      const prev = sku.qty;
      sku.qty = Math.max(0, Math.min(sku.max * 2, sku.qty + delta));
      sku.movements = sku.movements || [];
      sku.movements.push({ ts: Date.now(), delta, reason, ref, before: prev, after: sku.qty });
      if (sku.movements.length > 100) sku.movements = sku.movements.slice(-100);

      // Check thresholds and create alerts
      const pct = sku.qty / sku.max;
      const cfg = this._d.settings;
      if (delta < 0) { // only alert on consumption, not restock
        if (pct <= cfg.criticalStockPct) {
          this._upsertAlert('CRITICAL', barId, bar.name, skuId, sku.name, sku.qty, pct);
        } else if (pct <= cfg.lowStockPct) {
          this._upsertAlert('LOW', barId, bar.name, skuId, sku.name, sku.qty, pct);
        } else {
          this._clearAlert(barId, skuId); // resolved — back to safe level
        }
      } else {
        this._clearAlert(barId, skuId); // restock → clear alert
      }

      this._save();
      this.emit('inventory:updated', { barId, skuId, sku, delta, reason });
      // Evaluate automation rules after every inventory change
      if (delta < 0) setTimeout(() => this.evaluateRules({ barId, skuId, pct: sku.qty / sku.max }), 0);
      return sku;
    },

    bulkRestock(barId, items) {
      // items = [{ skuId, qty, ref }]
      items.forEach(({ skuId, qty, ref }) => {
        this.updateInventory(barId, skuId, qty, 'RESTOCK', ref);
      });
      this.emit('inventory:restocked', { barId, items });
    },

    transferStock(fromId, toId, skuId, qty) {
      const ref = 'XFER-' + Date.now().toString(36).toUpperCase();
      this.updateInventory(fromId, skuId, -qty, 'TRANSFER_OUT', ref);
      this.updateInventory(toId,   skuId, +qty, 'TRANSFER_IN',  ref);
      this.emit('inventory:transfer', { fromId, toId, skuId, qty, ref });
      return ref;
    },

    // ── ALERTS ────────────────────────────────────────────────────────────────
    _upsertAlert(type, barId, barName, skuId, skuName, qty, pct) {
      const key = `${type}::${barId}::${skuId}`;
      const existing = this._d.alerts.find(a => a.key === key && !a.resolved);
      if (existing) { existing.qty = qty; existing.pct = pct; existing.updatedAt = Date.now(); return; }
      const alert = {
        id: 'ALT-' + Date.now().toString(36).toUpperCase(),
        key, type, barId, barName, skuId, skuName, qty,
        pct: Math.round(pct * 100),
        ts: Date.now(), resolved: false,
      };
      this._d.alerts.unshift(alert);
      if (this._d.alerts.length > 200) this._d.alerts = this._d.alerts.slice(0, 200);
      this.emit('alert:new', alert);
    },

    _clearAlert(barId, skuId) {
      let changed = false;
      this._d.alerts.forEach(a => {
        if (a.barId === barId && a.skuId === skuId && !a.resolved) {
          a.resolved = true; a.resolvedAt = Date.now(); changed = true;
        }
      });
      if (changed) this.emit('alert:resolved', { barId, skuId });
    },

    getAlerts({ resolved = false, barId, type } = {}) {
      let list = this._d.alerts;
      list = list.filter(a => a.resolved === resolved);
      if (barId) list = list.filter(a => a.barId === barId);
      if (type)  list = list.filter(a => a.type === type);
      return list;
    },

    resolveAlert(id) {
      const a = this._d.alerts.find(a => a.id === id);
      if (a) { a.resolved = true; a.resolvedAt = Date.now(); this._save(); this.emit('alert:resolved', a); }
    },

    // ── SALES ANALYTICS ───────────────────────────────────────────────────────
    getSalesMetrics({ barId, from, to } = {}) {
      const txns    = this.getTransactions({ barId, from, to });
      const revenue = txns.reduce((s, t) => s + t.total, 0);
      const orders  = txns.length;
      const avgOrder = orders ? revenue / orders : 0;
      const items   = txns.reduce((s, t) => s + t.items.length, 0);
      const discountTotal = txns.reduce((s, t) => s + (t.discount || 0), 0);
      const taxTotal = txns.reduce((s, t) => s + (t.tax || 0), 0);
      const byPayment = txns.reduce((m, t) => { m[t.paymentMethod] = (m[t.paymentMethod] || 0) + t.total; return m; }, {});
      return { revenue, orders, avgOrder, items, discountTotal, taxTotal, byPayment, txns };
    },

    getTopSellers({ barId, from, to, limit = 12 } = {}) {
      const txns = this.getTransactions({ barId, from, to });
      const map  = {};
      txns.forEach(t => {
        t.items.forEach(item => {
          const key = item.skuId || item.name;
          if (!map[key]) map[key] = { name: item.name, emoji: item.emoji || '📦', cat: item.cat || 'other', qty: 0, revenue: 0, skuId: item.skuId };
          map[key].qty++;
          map[key].revenue += item.price || 0;
        });
      });
      return Object.values(map).sort((a, b) => b.qty - a.qty).slice(0, limit);
    },

    getRevenueByHour({ barId, date } = {}) {
      const d     = date ? new Date(date) : new Date();
      const start = new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
      const end   = start + 86400000;
      const txns  = this.getTransactions({ barId, from: start, to: end });
      const hours = Array(24).fill(0).map((_, h) => ({ h, revenue: 0, orders: 0 }));
      txns.forEach(t => { const h = new Date(t.ts).getHours(); hours[h].revenue += t.total; hours[h].orders++; });
      return hours;
    },

    getRevenueByBar({ from, to } = {}) {
      return Object.entries(this._d.inventory).map(([barId, bar]) => {
        const txns = this.getTransactions({ barId, from, to });
        const rev  = txns.reduce((s, t) => s + t.total, 0);
        return { barId, name: bar.name, zone: bar.zone, type: bar.type, revenue: rev, orders: txns.length };
      }).sort((a, b) => b.revenue - a.revenue);
    },

    getInventoryHealth() {
      const results = [];
      Object.entries(this._d.inventory).forEach(([barId, bar]) => {
        Object.entries(bar.items).forEach(([skuId, sku]) => {
          const pct = sku.qty / sku.max;
          const s   = this._d.settings;
          const status = pct <= s.criticalStockPct ? 'critical' : pct <= s.lowStockPct ? 'low' : 'ok';
          if (status !== 'ok') results.push({ barId, barName: bar.name, skuId, ...sku, pct: Math.round(pct * 100), status });
        });
      });
      return results.sort((a, b) => a.pct - b.pct);
    },

    getStaffMetrics({ staffId, from, to } = {}) {
      const txns = this.getTransactions({ staffId, from, to });
      return {
        staffId,
        orders: txns.length,
        revenue: txns.reduce((s, t) => s + t.total, 0),
        avgOrder: txns.length ? txns.reduce((s, t) => s + t.total, 0) / txns.length : 0,
        items: txns.reduce((s, t) => s + t.items.length, 0),
      };
    },

    // ── DISPATCHES ────────────────────────────────────────────────────────────
    recordDispatch(dispatch) {
      const d = {
        id: 'DSP-' + Date.now().toString(36).toUpperCase(),
        ts: Date.now(),
        status: 'PENDING',
        ...dispatch,
        history: [{ ts: Date.now(), status: 'DISPATCHED', by: dispatch.by || 'Manager' }],
      };
      this._d.dispatches.unshift(d);
      if (this._d.dispatches.length > 500) this._d.dispatches = this._d.dispatches.slice(0, 500);
      this._save();
      this.emit('dispatch:new', d);
      return d;
    },

    updateDispatch(id, patch) {
      const d = this._d.dispatches.find(d => d.id === id);
      if (!d) return null;
      Object.assign(d, patch);
      d.history.push({ ts: Date.now(), status: patch.status || 'UPDATED', note: patch.note });
      if (patch.status === 'DELIVERED') {
        // Auto-restock destination bar
        if (d.cargo && d.toBarId) {
          const restockItems = Object.entries(d.cargo).map(([skuId, qty]) => ({ skuId, qty: Number(qty) }));
          this.bulkRestock(d.toBarId, restockItems);
        }
        // Resolve inventory alerts for restocked bar
        if (d.toBarId) this.emit('inventory:restocked', { barId: d.toBarId });
      }
      this._save();
      this.emit('dispatch:updated', d);
      return d;
    },

    getDispatches({ status, limit = 50 } = {}) {
      let list = [...this._d.dispatches];
      if (status) list = list.filter(d => d.status === status);
      return list.slice(0, limit);
    },

    // ── SETTINGS ──────────────────────────────────────────────────────────────
    getSettings() { return { ...this._d.settings }; },

    updateSettings(patch) {
      Object.assign(this._d.settings, patch);
      this._save();
      this.emit('settings:updated', this._d.settings);
    },

    // ── HELPERS ───────────────────────────────────────────────────────────────
    _currentShift() {
      const h = new Date().getHours();
      if (h >= 5  && h < 13) return 'morning';
      if (h >= 13 && h < 21) return 'evening';
      return 'night';
    },

    fmt: {
      currency(n) { return '$' + (n || 0).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 }); },
      pct(n)      { return (n || 0).toFixed(1) + '%'; },
      time(ts)    { return new Date(ts).toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' }); },
      date(ts)    { return new Date(ts).toLocaleDateString('en-US', { month: 'short', day: 'numeric' }); },
      ago(ts)     {
        const s = Math.floor((Date.now() - ts) / 1000);
        if (s < 60)  return s + 's ago';
        if (s < 3600) return Math.floor(s / 60) + 'm ago';
        return Math.floor(s / 3600) + 'h ago';
      },
    },

    // ── DEMO SEED ─────────────────────────────────────────────────────────────
    _seedDemo() {
      if (this._d.transactions.length > 0) return;
      const now    = Date.now();
      const bars   = ['bar-01', 'bar-02', 'bar-03', 'bar-04'];
      const staff  = ['bartender-01', 'bartender-02', 'bartender-03'];
      const skuSets = {
        'bar-01': Object.keys(baseInventory()),
        'bar-02': Object.keys(baseInventory(true)),
        'bar-03': Object.keys(baseInventory()),
        'bar-04': Object.keys(baseInventory()),
      };

      // Build a realistic revenue curve: slow morning, peak evening (6pm-10pm)
      const demoCurve = [0,.1,.05,.03,.02,.02,.05,.1,.15,.2,.25,.3,.4,.55,.65,.75,.85,1,1,0.9,.8,.6,.4,.2];

      // Seed ~180 transactions over the past 8 hours
      for (let i = 0; i < 180; i++) {
        const hoursBack = Math.random() * 8;
        const ts   = now - hoursBack * 3600000;
        const barId = bars[Math.floor(Math.random() * bars.length)];
        const skus = skuSets[barId] || skuSets['bar-01'];
        const count = Math.floor(Math.random() * 4) + 1;
        const items = [];
        let subtotal = 0;
        for (let j = 0; j < count; j++) {
          const skuId = skus[Math.floor(Math.random() * skus.length)];
          const inv = this._d.inventory[barId]?.items[skuId];
          if (!inv) continue;
          items.push({ name: inv.name, emoji: inv.emoji, price: inv.price, skuId, cat: inv.cat });
          subtotal += inv.price;
        }
        if (!items.length) continue;
        const disc  = Math.random() < 0.1 ? subtotal * 0.15 : 0; // 10% chance of discount
        const tax   = (subtotal - disc) * 0.07;
        const total = subtotal - disc + tax;
        this._d.transactions.push({
          id: 'TXN-SEED-' + i,
          ts,
          barId,
          staffId: staff[Math.floor(Math.random() * staff.length)],
          staffName: ['Diego L.', 'Elena R.', 'Marco S.'][Math.floor(Math.random() * 3)],
          items,
          subtotal,
          discount: disc,
          discountLabel: disc ? 'Staff Discount' : null,
          tax,
          total,
          paymentMethod: Math.random() > 0.25 ? 'card' : 'cash',
          customerName: 'Guest',
          shift: this._currentShift(),
          receiptId: 'RCP-SEED-' + i,
        });
      }

      // Reduce inventory to reflect demo sales
      bars.forEach(barId => {
        const bar = this._d.inventory[barId];
        if (!bar) return;
        Object.keys(bar.items).forEach(skuId => {
          const sku = bar.items[skuId];
          const sold = Math.floor(Math.random() * sku.qty * 0.55);
          sku.qty = Math.max(sku.min - 5, sku.qty - sold); // force some below min
        });
      });

      // Seed a few active alerts
      this._upsertAlert('CRITICAL', 'bar-01', 'Main Bar', 'beer-domestic', 'Domestic Beer', 8,  0.033);
      this._upsertAlert('LOW',      'bar-03', 'Field Bar', 'spirits-vodka', 'Vodka Shot',    14, 0.175);
      this._upsertAlert('LOW',      'bar-02', 'VIP Lounge', 'wine-red', 'Red Wine',          9,  0.15);

      this._save();
      console.log('[BPDB] Demo data seeded:', this._d.transactions.length, 'transactions');
    },

    // ── AUTOMATION RULES ──────────────────────────────────────────────────────
    getRules() { return this._d.automationRules || []; },

    createRule(rule) {
      const r = { id: 'rule-' + Date.now().toString(36), enabled: true, fireCount: 0, lastFired: null, createdAt: Date.now(), ...rule };
      this._d.automationRules = this._d.automationRules || [];
      this._d.automationRules.push(r);
      this._save();
      this.emit('rule:created', r);
      return r;
    },

    updateRule(id, patch) {
      const r = (this._d.automationRules || []).find(r => r.id === id);
      if (!r) return null;
      Object.assign(r, patch, { updatedAt: Date.now() });
      this._save();
      this.emit('rule:updated', r);
      return r;
    },

    deleteRule(id) {
      this._d.automationRules = (this._d.automationRules || []).filter(r => r.id !== id);
      this._save();
      this.emit('rule:deleted', { id });
    },

    toggleRule(id) {
      const r = (this._d.automationRules || []).find(r => r.id === id);
      if (r) { r.enabled = !r.enabled; this._save(); this.emit('rule:toggled', r); }
      return r;
    },

    evaluateRules(context = {}) {
      const rules = (this._d.automationRules || []).filter(r => r.enabled);
      const fired = [];
      rules.forEach(rule => {
        const now = Date.now();
        if (rule.lastFired && (now - rule.lastFired) < rule.cooldown) return; // cooldown active
        let matches = false;

        if (rule.trigger.type === 'inventory_threshold') {
          const { barType, threshold, skuId } = rule.trigger;
          const inv = this._d.inventory;
          Object.entries(inv).forEach(([barId, bar]) => {
            if (barType && bar.type !== barType) return;
            Object.entries(bar.items).forEach(([sid, sku]) => {
              if (skuId && sid !== skuId) return;
              const pct = sku.qty / sku.max;
              if (pct <= threshold) matches = true;
            });
          });
        }

        if (matches) {
          rule.lastFired = now;
          rule.fireCount = (rule.fireCount || 0) + 1;
          const logEntry = { ts: now, ruleId: rule.id, ruleName: rule.name, action: rule.action, context };
          this._d.automationLog = this._d.automationLog || [];
          this._d.automationLog.unshift(logEntry);
          if (this._d.automationLog.length > 500) this._d.automationLog = this._d.automationLog.slice(0, 500);

          // Execute action
          this._executeRuleAction(rule, context);
          fired.push(rule);
        }
      });
      if (fired.length) this._save();
      return fired;
    },

    _executeRuleAction(rule, context) {
      const action = rule.action;
      try {
        if (action.type === 'create_dispatch') {
          this.recordDispatch({
            fromHubId: action.fromHub || 'hub-01',
            toBarId: context.barId || 'bar-01',
            priority: action.priority || 'MID',
            by: 'Automation',
            note: action.note || rule.name,
            autoTriggered: true,
            ruleId: rule.id,
          });
        } else if (action.type === 'create_alert') {
          this._upsertAlert(action.severity || 'LOW', context.barId || 'system', 'System', context.skuId || 'system', rule.name, 0, 0);
        } else if (action.type === 'create_restock_order') {
          this.createRestockOrder({
            supplierId: action.supplierId || 'sup-001',
            urgency: action.urgency || 'standard',
            locationId: context.barId || 'hub-01',
            triggeredByRule: rule.id,
            autoTriggered: true,
          });
        }
        this.emit('automation:fired', { rule, context, action });
      } catch(e) { console.warn('[BPDB] Rule action failed:', e); }
    },

    getAutomationLog({ limit = 50 } = {}) {
      return (this._d.automationLog || []).slice(0, limit);
    },

    // ── RESTOCK ORDERS ────────────────────────────────────────────────────────
    createRestockOrder(order) {
      const o = {
        id: 'RST-' + Date.now().toString(36).toUpperCase(),
        ts: Date.now(),
        status: 'PENDING',
        supplierId: order.supplierId || 'sup-001',
        locationId: order.locationId || 'hub-01',
        urgency: order.urgency || 'standard',
        items: order.items || this._autoGenerateRestockItems(order.locationId),
        note: order.note || '',
        estimatedArrival: Date.now() + (order.urgency === 'urgent' ? 86400000 : 3 * 86400000),
        triggeredByRule: order.triggeredByRule || null,
        autoTriggered: order.autoTriggered || false,
        createdBy: order.createdBy || 'System',
        totalCost: 0,
        history: [{ ts: Date.now(), status: 'PENDING', by: order.createdBy || 'System' }],
      };
      o.totalCost = o.items.reduce((s, i) => s + (i.cost || 0) * (i.qty || 0), 0);
      this._d.restockOrders = this._d.restockOrders || [];
      this._d.restockOrders.unshift(o);
      if (this._d.restockOrders.length > 200) this._d.restockOrders = this._d.restockOrders.slice(0, 200);
      this._save();
      this.emit('restock:created', o);
      return o;
    },

    _autoGenerateRestockItems(locationId) {
      const bar = this._d.inventory[locationId];
      if (!bar) return [];
      return Object.entries(bar.items)
        .filter(([, sku]) => (sku.qty / sku.max) < 0.35)
        .map(([skuId, sku]) => ({
          skuId, name: sku.name, emoji: sku.emoji,
          currentQty: sku.qty, targetQty: sku.max,
          qty: sku.max - sku.qty, cost: sku.cost, unit: sku.unit,
        }));
    },

    updateRestockOrder(id, patch) {
      const o = (this._d.restockOrders || []).find(o => o.id === id);
      if (!o) return null;
      const prevStatus = o.status;
      Object.assign(o, patch, { updatedAt: Date.now() });
      o.history.push({ ts: Date.now(), status: patch.status || prevStatus, by: patch.updatedBy || 'Staff', note: patch.note });

      if (patch.status === 'RECEIVED') {
        // Auto-update inventory on receipt
        (o.items || []).forEach(item => {
          if (item.skuId && item.qty) {
            this.updateInventory(o.locationId, item.skuId, item.qty, 'RESTOCK_ORDER', o.id);
          }
        });
      }
      this._save();
      this.emit('restock:updated', o);
      return o;
    },

    getRestockOrders({ status, locationId, limit = 50 } = {}) {
      let list = this._d.restockOrders || [];
      if (status)     list = list.filter(o => o.status === status);
      if (locationId) list = list.filter(o => o.locationId === locationId);
      return list.slice(0, limit);
    },

    // ── SUPPLIERS ─────────────────────────────────────────────────────────────
    getSuppliers() { return this._d.suppliers || []; },

    getSupplier(id) { return (this._d.suppliers || []).find(s => s.id === id); },

    createSupplier(supplier) {
      const s = { id: 'sup-' + Date.now().toString(36), createdAt: Date.now(), rating: 5, ...supplier };
      this._d.suppliers = this._d.suppliers || [];
      this._d.suppliers.push(s);
      this._save();
      this.emit('supplier:created', s);
      return s;
    },

    updateSupplier(id, patch) {
      const s = (this._d.suppliers || []).find(s => s.id === id);
      if (s) { Object.assign(s, patch); this._save(); this.emit('supplier:updated', s); }
      return s;
    },

    // ── DEV UTILITIES ─────────────────────────────────────────────────────────
    reset() {
      localStorage.removeItem(STORE_KEY);
      this._d = defaults();
      this._seedDemo();
      this._save();
      this.emit('reset', null);
      console.log('[BPDB] Reset complete');
    },

    export() {
      return JSON.stringify(this._d, null, 2);
    },

    import(json) {
      try {
        this._d = JSON.parse(json);
        this._save();
        this.emit('import', null);
        return true;
      } catch (e) {
        console.error('[BPDB] Import failed:', e);
        return false;
      }
    },

    // Summary for debugging
    summary() {
      const m = this.getSalesMetrics();
      console.table({
        Transactions: this._d.transactions.length,
        Revenue: this.fmt.currency(m.revenue),
        Orders: m.orders,
        Alerts: this.getAlerts().length,
        Locations: Object.keys(this._d.inventory).length,
      });
    },
  };

  global.BPDB = BPDB;
  // Auto-init if DOM is ready
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', () => BPDB.init());
  } else {
    BPDB.init();
  }

})(window);
