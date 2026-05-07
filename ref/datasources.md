# Data Source Codes

---

## Standard Datasources (repserv/plugin)

Used in `I78` (active datasources column), per-source column prefixes, and `QuerySessions` filter/response.

`coveApi.psm1` maintains `$script:pluginSrcMap` (plugin name/int → D-code) and `$script:dCodeNames` (D-code → display name). Rows marked **in module** are covered by those maps.

| D-Code | Name | Plugin ID string | Plugin int (QuerySessions filter) | In module |
|--------|------|-----------------|-----------------------------------|-----------|
| D01 | Files and Folders | `FileSystem` | 1 | Yes |
| D02 | System State (Windows + Linux) | `VssSystemState`, `LinuxSystemState` | 7, 18 | Yes |
| D04 | Exchange Stores (VSS) | `VssExchange` | 4 | Yes |
| D06 | Network Shares | `NetworkShares` | 6 | Yes |
| D08 | VMware | `VMWare` | 8 | Yes |
| D09 | Total (overall aggregation) | — | — | No |
| D10 | MS SQL (VSS) | `VssSql` | 10 | Yes |
| D11 | SharePoint (on-prem, VSS) | TBC | 11? | No |
| D12 | Oracle | `Oracle` | 12 | Yes |
| D14 | Hyper-V | `HyperV` | 14 | Yes |
| D15 | MySQL | `MySql` | 15 | Yes |
| D16 | Virtual Disaster Recovery | — | — | No |
| D17 | Bare Metal Restore | — | — | No |
| D19 | M365 Exchange | — | — | No |
| D20 | M365 OneDrive | — | — | No |
| D23 | M365 Teams | — | — | No |

**`I78` parsing:** the column value is a concatenated string of D-codes with no separator, e.g. `"D01D02D19"`. Parse as 3-character groups.

**`QuerySessions` note:** the `Plugin` filter field is an integer; the response `PluginId` field is a string. Plugin int 16 and 11 are seen in some captures but their full mappings are unconfirmed (TBC).

---

## M365 Datasources (reporting_api)

Used in `EnumerateSessionErrors` and `EnumerateSessions` on `https://api.backup.management/reporting_api`. Auth via `Authorization: Bearer <visa>` header (not in request body).

`coveApi.psm1` handles all four in `Get-CoveM365Errors` via `$dsTypeMap`.

| D-Code | Name | `dataSourceType` value | In module |
|--------|------|-----------------------|-----------|
| D19 | M365 Exchange | `"Exchange"` | Yes |
| D20 | M365 OneDrive | `"OneDrive"` | Yes |
| D05 | M365 SharePoint | `"SharePoint"` | Yes |
| D23 | M365 Teams | `"Teams"` | Yes |

**`dataSourceType` is required** in `EnumerateSessionErrors` — omitting it returns error -32603. One call per datasource.

**Account token:** both `EnumerateSessionErrors` and `EnumerateSessions` require `accountToken` (a UUID). Obtain from `GetAccountInfoById` → `result.result.Token`. This is a permanent account property, not a session token.
