# EnumerateAccountStatistics Column Codes

All columns are case-sensitive. Pass as a string array in `Columns`. Timestamps are Unix seconds (UTC). Size values are bytes.

---

## Device Identity

| Code | Description | Notes |
|------|-------------|-------|
| `AU` | Device ID (integer) | Same value as `I3`. Use this for all `accountId` params. |
| `I3` | Device ID (integer) | Same as `AU`. `I3` is more commonly seen in query results. |
| `AN` | Device name | Display name in portal |
| `AR` | Partner/customer name | Owning customer's name |
| `PN` | Product name | Licensed product name |
| `PD` | Product ID | Integer |
| `I83` | Partner ID | The customer's partner ID (integer). Used as `PartnerId` in `EnumerateAggregatedStatisticsHistory`. |
| `MN` | Computer hostname | |
| `AL` | Device name alias | |
| `AG` | Device group name | |
| `II` | Installation ID | Hex string. Matches `InstallationId` in local `config.ini`. Use to locate a device from the agent side. |
| `I1` | Device hostname (display) | NOT the account ID. Do not use as `accountId`. |
| `EM` | Email address | |
| `PF` | Partner reference | Free-text field |

---

## Status & Health

| Code | Description | Notes |
|------|-------------|-------|
| `OT` | Device type | 0=Cloud/M365, 1=Workstation, 2=Server |
| `AT` | Account type / active flag | 1=active. Filter `AT == 1` to exclude decommissioned devices. |
| `T0` | Overall status | Status enum (see below) |
| `TJ` | Status of last completed session | Status enum |
| `TQ` | Status of last successful session | Status enum |
| `T7` | Total error count | `>= 1` means device has errors |
| `TL` | Last successful session timestamp | Unix seconds |
| `TO` | Last completed session timestamp | Unix seconds |
| `TS` | Last session timestamp (any outcome) | Unix seconds. Use `TS` to check recency regardless of result. |
| `DS` | Activity description | Current activity string |
| `VN` | Client version | e.g. `"26.1.0.26067"` |
| `OS` | OS name and version | |
| `I78` | Active data sources | Concatenated 3-char codes, e.g. `"D01D02D19"`. Parse as groups of 3. See `datasources.md`. |
| `I82` | Passphrase / encryption status | String |
| `I80` | Continuity | Integer |
| `I81` | Physicality | String |
| `YS` | Backup server status | Integer |
| `YV` | LocalSpeedVault status | Integer |
| `VE` | LocalSpeedVault enabled | Integer |
| `IE` | Standby Image enabled | Integer |
| `IT` | Standby Image status | Integer |

### Status enum (T0, TJ, TQ, and all per-source J/Q columns)

| Value | Label | Alert? |
|-------|-------|--------|
| 0 | No data / unknown | No |
| 1 | In Progress | No |
| 2 | Failed | Yes |
| 3 | Aborted | Yes |
| 4 | Unknown (rare) | No |
| 5 | Success | No |
| 6 | Interrupted | Yes — but Cove auto-resumes |
| 7 | Not Started (device offline at scheduled time) | Yes |
| 8 | Completed with Errors | Yes |
| 9 | In Progress with Faults | Conditional |

---

## Per-Source Status (28-day history)

History columns are strings of digits, one per day, newest-rightmost. Each digit is the Status enum value for that day.

| Code | Source |
|------|--------|
| `TB` | Overall (all sources) |
| `FB` | Files and Folders |
| `SB` | System State |
| `KB` | Linux System State |
| `XB` | Exchange Stores (VSS) |
| `ZB` | MS SQL |
| `LB` | MySQL |
| `YB` | Oracle |
| `NB` | Network Shares |
| `PB` | SharePoint (on-prem) |
| `HB` | Hyper-V |
| `WB` | VMware |
| `GB` | M365 Exchange |
| `JB` | M365 OneDrive |
| `D5F8` | M365 SharePoint |
| `D23F8` | M365 Teams |

**Day interpretation:** `0`=no attempt scheduled, `7`=scheduled but device offline (true miss), `6`=interrupted (will resume), `1`=in-progress at snapshot.

---

## Per-Source Last Session

Pattern: `[prefix]J` = status of last completed session, `[prefix]O` = timestamp of last completed session, `[prefix]Q` = status of last successful session, `[prefix]L` = timestamp of last successful session.

| Source | J (last status) | O (last ts) | Q (success status) | L (success ts) |
|--------|----------------|-------------|-------------------|----------------|
| Files & Folders | `FJ` | `FO` | `FQ` | `FL` |
| System State | `SJ` | `SO` | `SQ` | `SL` |
| Linux System State | `KJ` | `KO` | `KQ` | `KL` |
| Exchange Stores | `XJ` | `XO` | `XQ` | `XL` |
| MS SQL | `ZJ` | `ZO` | `ZQ` | `ZL` |
| MySQL | `LJ` | `LO` | `LQ` | `LL` |
| Oracle | `YJ` | `YO` | `YQ` | `YL` |
| Network Shares | `NJ` | `NO` | `NQ` | `NL` |
| SharePoint (on-prem) | `PJ` | `PO` | `PQ` | `PL` |
| Hyper-V | `HJ` | `HO` | `HQ` | `HL` |
| VMware | `WJ` | `WO` | `WQ` | `WL` |
| M365 Exchange | `GJ` | `GO` | `GQ` | `GL` |
| M365 OneDrive | `JJ` | `JO` | `JQ` | `JL` |
| M365 SharePoint | `D5F17` | `D5F18` | `D5F16` | `D5F9` |
| M365 Teams | `D23F17` | `D23F18` | `D23F16` | `D23F9` |

---

## M365

| Code | Description | Notes |
|------|-------------|-------|
| `TM` | Total M365 billable users | Deduplicated union across Exchange and OneDrive. **Primary billing metric.** Only populated on OT=0 devices. |
| `T@` | M365 total protected objects | Large integer; likely total across all M365 sources. Meaning unconfirmed. |
| `G0` | M365 Exchange backup status | Status enum |
| `G3` | M365 Exchange selected size | Bytes |
| `G7` | M365 Exchange error count | |
| `GM` | M365 Exchange user mailboxes (protected) | |
| `G@` | M365 Exchange shared mailboxes (protected) | Portal "Protected users" = `GM + G@` |
| `GA` | M365 Exchange (unknown large integer) | Likely total item/object count |
| `J0` | M365 OneDrive backup status | Status enum |
| `J3` | M365 OneDrive selected size | Bytes |
| `J7` | M365 OneDrive error count | |
| `JM` | M365 OneDrive protected user count | |
| `JA` | M365 OneDrive (unknown large integer) | Likely total item count |
| `D5F0` | M365 SharePoint backup status | Status enum |
| `D5F3` | M365 SharePoint selected size | Bytes |
| `D5F6` | M365 SharePoint error count | |
| `D5F20` | M365 SharePoint protected user count | |
| `D5F22` | M365 SharePoint protected site count | |
| `D5F12` | M365 SharePoint (unknown large integer) | Likely total item count |
| `D23F0` | M365 Teams backup status | Status enum |
| `D23F3` | M365 Teams selected size | Bytes |
| `D23F6` | M365 Teams error count | |
| `D23F20` | M365 Teams protected team count | |
| `D23F23` | M365 Teams protected channel count | |
| `D23F12` | M365 Teams (unknown large integer) | Likely total item count |

---

## Billing & Storage

| Code | Description | Notes |
|------|-------------|-------|
| `F6` | Files & Folders protected size | Bytes. Primary storage billing metric. Billing = `ceil(F6 / 107374182400)` per 100GB unit. |
| `US` | Used storage | Bytes |
| `AS` | Total archived size | Bytes |
| `F3` | Files & Folders selected size | Bytes |
| `F5` | Files & Folders sent size | Bytes (deduplicated/compressed actual transfer) |
| `F7` | Files & Folders error count | |
| `KU` | SKU (current month) | |
| `PU` | SKU (previous month) | |

---

## Timestamps

All values are Unix seconds (UTC). Convert: `[DateTime]::new(1970,1,1,0,0,0,'Utc').AddSeconds($v)`

| Code | Description |
|------|-------------|
| `CD` | Account creation date |
| `ED` | Expiration date |
| `TS` | Last session timestamp (any outcome) |
| `TL` | Last successful session timestamp (overall) |
| `TO` | Last completed session timestamp (overall) |

---

## Other / Less Common

| Code | Description | Notes |
|------|-------------|-------|
| `I84` | CPU cores | Integer |
| `I85` | RAM size | Bytes |
| `I86` | FIPS status | String |
| `I88` | mTLS status | String |
| `IM` | Installation mode | Integer |
| `OI` | Profile ID | Integer |
| `OP` | Profile name | String |
| `OV` | Profile version | Integer |
| `RU` | Retention policy type | String |
| `MF` | Computer manufacturer | |
| `MO` | Computer model | |
| `TZ` | Time zone offset | String |
| `EI` | External IP address | |
| `IP` | List of IP addresses | |
| `MA` | MAC address | |
| `HN` | Hyper-V VM count | Integer |
| `EN` | ESX/VMware VM count | Integer |
| `IS` | Seeding mode | Integer |
| `PT` | Proxy type | Integer |
| `LN` | Home node location name | Storage node location, not "Last Session" — confusing name |
