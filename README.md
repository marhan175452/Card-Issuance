# Card Issuance Lineage & KPIs (SQL)

SQL to build a reproducible lineage of card (re)issues and produce monthly KPIs by reason and holder role.

---

## What this script does

- Constructs a normalized **event table** with one row per issued card token, ordered within each account/holder role.
- Derives an **issuance sequence** (`issuance_seq`) using a window function so you can tell first issues from reissues.
- Classifies the **reason for the current card** (e.g., first issue, reissue after a prior block code, or reissue with no block).
- Produces **monthly rollups** that split counts by:
  - Issuance reason
  - Holder role (Primary vs Secondary)
  - Total distinct cards issued

---

## Core logic at a glance

1. **Event base (`card_issue_events`)**
   - Source joins card detail with the account master.
   - Filters to open accounts (or closed after a chosen cut-off date).
   - Computes `issuance_seq` with `row_number()` partitioned by `(card_acct_id, holder_role)`, ordered by `card_issue_date`.

2. **Reason classification**
   - For each issuance event, the script looks at the **immediately previous event** (same account & role, `issuance_seq - 1`).
   - Reason rules:
     - `issuance_seq = 1` → **First Issue**
     - Prior event has a `block_code` → **Block {code}**
     - Otherwise → **No block**

3. **Monthly KPIs**
   - Aggregates by `to_char(card_issue_date, 'YYYY-MM')` and reason, returning:
     - `primary_cards`
     - `secondary_cards`
     - `total_cards`

4. **Diagnostics / Checks**
   - Alternate monthly matrix (L/M/Other/No block).
   - Edge list where a reissue has **no detectable predecessor** (useful for data quality).

---

## SQL objects created

### 1) `card_issue_events`
Event-level view of card issuance.

| Column            | Type        | Description                                   |
|-------------------|-------------|-----------------------------------------------|
| `card_acct_id`    | key         | Card account identifier                       |
| `card_open_date`  | date        | Account open date                             |
| `card_token`      | key         | Issued card token/number                      |
| `holder_role`     | char(1)     | `'P'` primary, `'S'` secondary                |
| `block_code`      | varchar     | Prior card’s block reason (if any)            |
| `card_issue_date` | date        | Program/issue timestamp                        |
| `issuance_seq`    | number      | Sequence within `(card_acct_id, holder_role)` |

> **Note**: `issuance_seq = 1` denotes the first card for that account/role. Later events are reissues.

---

## KPIs produced

1. **Monthly issuance by reason & role**
   - `issue_month` (`YYYY-MM`)
   - `issuance_reason` (`First Issue`, `Block X`, `No block`)
   - `primary_cards`, `secondary_cards`, `total_cards`

2. **Monthly issuance reason matrix (check)**
   - Splits reissues into **L/M/Other/No block**, plus **First Issue**

3. **Edge review**
   - Lists events where a new card has **no matched prior card** for the same account/role.

---

## Business definitions

- **First Issue**: The first observed card for `(account, role)`.
- **Reissue (Block X)**: A card issued where the **previous event** shows a `block_code` (e.g., `L`, `M`, etc.).
- **Reissue (No block)**: A card issued where the previous event exists but has **no block code**.
- **Primary vs Secondary**:
  - `holder_role = 'P'` → **Primary**
  - `holder_role = 'S'` → **Secondary**

---

## Example outputs

### Monthly issuance by reason
