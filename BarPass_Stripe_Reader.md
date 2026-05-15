# BarPass — Stripe Reader Integration Guide
**MVP Stage · April 2026 · Miami, FL**

---

## Hardware Options (US 2026)

| Reader | Price | Connectivity | Best For |
|---|---|---|---|
| **Reader M2** ✅ | $59 | Bluetooth | BarPass MVP |
| BBPOS WisePad 3 | $59 | Bluetooth | Alternative to M2 |
| BBPOS WisePOS E | $249 | WiFi / Ethernet | Standalone kiosk |
| Reader S700 | $299–$349 | WiFi / Ethernet / BLE | Scale / premium |

**Recommendation: Reader M2 @ $59**
Portable, Bluetooth to iPad, accepts chip / tap / swipe / Apple Pay / Google Pay, end-to-end encrypted, PCI-compliant.

---

## Transaction Fees

| Channel | Fee |
|---|---|
| In-person (Terminal) | **2.7% + $0.05** |
| Online | 2.9% + $0.30 |

### Example — $12 ticket
```
Stripe fee = ($12 × 2.7%) + $0.05 = $0.374
Net to BarPass after fee = $11.626
```

---

## Updated Unit Economics (with real M2 fee)

| Metric | Previous estimate | Actual (M2) |
|---|---|---|
| Stripe fee / txn | $0.40 | **$0.374** |
| Net gain / txn | $0.71 | **$0.742** |
| Monthly (900 txn) | $639 | **$668** |
| Hardware cost | — | $59 one-time |

---

## Hardware Cost Per Venue

| Item | Cost |
|---|---|
| Stripe Reader M2 | $59 |
| iPad (refurb) | $399 |
| Mount + case | $45 |
| 4G Router (TP-Link) | $89 |
| **Total hardware / venue** | **$592** |

---

## Integration Notes

- SDK: Stripe Terminal SDK for iOS (Swift)
- Connection: Bluetooth Low Energy (BLE) → iPad
- No monthly hardware fees
- No Stripe POS app included — BarPass v7 IS the POS
- Integration path: `StripeTerminalSDK` → `SCPTerminal` → `SCPReader`
- Offline mode: Stripe Terminal supports offline card capture (sync on reconnect)

---

## Rolling Reserve Impact

Stripe retains 5% rolling reserve during first 90 days.

| Month | Volume | Reserve (5%) | Net Available |
|---|---|---|---|
| 1 | $2,400 | −$120 | $2,280 |
| 2 | $4,800 | −$240 | $4,560 |
| 3 | $7,200 | −$360 | $6,840 |
| 4 | $9,600 | +$120* released | $9,720 |

*Month 1 reserve released after 90 days with zero chargebacks.

---

## Instant Payout

- Available after building Stripe reputation
- Cost: **1% of transfer total**
- Recommendation: avoid until cash flow requires it

---

## Quick Setup Checklist

- [ ] Create Stripe account → enable Terminal
- [ ] Order Reader M2 from Stripe Dashboard ($59)
- [ ] Add Stripe Terminal SDK to BarPass iOS project
- [ ] Configure `SCPTerminal.shared.setConnectionTokenProvider`
- [ ] Connect reader via Bluetooth in app
- [ ] Test with Stripe test card `4242 4242 4242 4242`
- [ ] Go live with first venue

---

*BarPass Technologies · Miami, FL · 2026 · barpass.io*
