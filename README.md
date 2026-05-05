# pwshCoveApi

PowerShell module for the [Cove Data Protection](https://www.n-able.com/products/cove-data-protection) API. Current version: **v1.3.0**

Provides authentication, device enumeration, partner and per-device queries, and a parallel execution engine that handles visa distribution to thread jobs automatically.

Requires PowerShell 7.4 or later.

---

## Installation

Clone the repository and import the module by path:

```powershell
Import-Module /path/to/pwshCoveApi/coveApi.psm1
```

---

## Quick Start

```powershell
Import-Module ./coveApi.psm1

Connect-CoveApi -Username 'user@example.com' -Password 'secret'

$devices = Get-CoveDevices -Columns @('AU', 'AB', 'AO', 'B4')

$results = Invoke-CoveParallel -Items $devices -ThrottleLimit 20 -ScriptBlock {
    param($device)
    [PSCustomObject]@{
        AccountId = $device.AccountId
        Errors    = Get-CoveDeviceErrors -AccountId $device.AccountId
    }
}
```

---

## Reference

### Initialization

#### `Initialize-CoveApi`

Sets the API and reporting endpoint URLs. Optional — defaults to the Cove production endpoints.

```powershell
Initialize-CoveApi
Initialize-CoveApi -ApiUrl 'https://api.backup.management/jsonapi' `
                   -ReportingUrl 'https://api.backup.management/reporting_api'
```

| Parameter      | Type   | Default                                       |
|----------------|--------|-----------------------------------------------|
| `-ApiUrl`      | string | `https://api.backup.management/jsonapi`       |
| `-ReportingUrl`| string | `https://api.backup.management/reporting_api` |

Call before `Connect-CoveApi` if you need non-default endpoints.

---

### Authentication

#### `Connect-CoveApi`

Logs in and stores the visa, partner ID, and a `SecureString`-backed credential in module scope. Returns `{Visa, PartnerId}`.

The stored credential is used for automatic visa re-auth: if any API call returns an auth error (expired visa), the module re-authenticates transparently and retries the call once. This works in both direct calls and inside `Invoke-CoveParallel` thread jobs.

```powershell
$session = Connect-CoveApi -Username 'user@example.com' -Password 'secret'
```

| Parameter   | Type   | Required |
|-------------|--------|----------|
| `-Username` | string | Yes      |
| `-Password` | string | Yes      |

#### `Get-CoveVisa`

Returns the stored visa token.

```powershell
$visa = Get-CoveVisa
```

#### `Get-CovePartnerId`

Returns the stored partner ID.

```powershell
$partnerId = Get-CovePartnerId
```

---

### Core JSON-RPC

#### `Invoke-CoveJsonrpc`

Sends a JSON-RPC request to the main API endpoint. Retries automatically on transient failures. Use this for methods not covered by a dedicated function.

```powershell
$resp = Invoke-CoveJsonrpc -Method 'SomeMethod' -Params @{ key = 'value' }
```

| Parameter | Type      | Default     |
|-----------|-----------|-------------|
| `-Method` | string    | Required    |
| `-Params` | hashtable | Required    |
| `-Visa`   | string    | stored visa |

---

### Parallel Execution

#### `Invoke-CoveParallel`

Runs a script block against each item in parallel using thread jobs. Module state (visa, partner ID, API URLs) is pre-initialized in each job — any module function can be called directly from within the script block without passing credentials.

The script block receives one argument: the current item. Plain `{ }` literals work correctly; no `[scriptblock]::Create()` workaround is needed.

```powershell
$results = Invoke-CoveParallel -Items $devices -ThrottleLimit 20 -ScriptBlock {
    param($device)
    [PSCustomObject]@{
        AccountId = $device.AccountId
        Errors    = Get-CoveDeviceErrors -AccountId $device.AccountId
        Sessions  = Get-CoveSessions    -AccountId $device.AccountId
    }
}
```

| Parameter        | Type        | Default  |
|------------------|-------------|----------|
| `-Items`         | object[]    | Required |
| `-ScriptBlock`   | scriptblock | Required |
| `-ThrottleLimit` | int         | 20       |

Returns an array of whatever the script block outputs, one entry per item. Items that fail return `$null`.

---

### Partner

#### `Get-CovePartnerInfo`

Returns the raw `GetPartnerInfoById` result for a partner (includes `Name`, `Type`, and other fields). Defaults to the logged-in partner. Results are cached — repeated calls for the same `PartnerId` within the session return immediately without an API call. Returns `$null` if the partner cannot be resolved.

```powershell
$info = Get-CovePartnerInfo                     # logged-in partner
$info = Get-CovePartnerInfo -PartnerId 12345
Write-Host $info.Name
```

| Parameter    | Type   | Default        |
|--------------|--------|----------------|
| `-PartnerId` | long   | stored partner |
| `-Visa`      | string | stored visa    |

#### `Get-CovePartnerBranding`

Returns `MainColor` (hex string) and `ProductName` from the partner's web branding. Returns `$null` on failure.

```powershell
$branding = Get-CovePartnerBranding
Write-Host "Product: $($branding.ProductName), Color: $($branding.MainColor)"
```

| Parameter | Type   | Default     |
|-----------|--------|-------------|
| `-Visa`   | string | stored visa |

---

### Device Enumeration

#### `Get-CoveDevices`

Fetches all devices via `EnumerateAccountStatistics`. Returns the raw result array.

```powershell
$devices = Get-CoveDevices -Columns @('AU', 'AB', 'AO', 'B4', 'T7', 'TL')
```

| Parameter       | Type     | Default        |
|-----------------|----------|----------------|
| `-Columns`      | string[] | Required       |
| `-Visa`         | string   | stored visa    |
| `-PartnerId`    | long     | stored partner |
| `-RecordsCount` | int      | 10000          |

`-Columns` are Cove column codes (e.g. `AU` = account ID, `AB` = device name, `AO` = OS). See Cove API documentation for the full column reference.

---

### Per-Device Queries

All per-device functions accept an optional `-Visa` parameter (defaults to the stored visa) and an optional `-Endpoint` parameter. When `-Endpoint` is omitted the function resolves the repserv endpoint internally via `Get-CoveAccountInfo`. Pass a pre-fetched endpoint to avoid the extra API call when making multiple queries for the same device.

```powershell
$endpoint = Get-CoveAccountInfo -AccountId 12345
$errors   = Get-CoveDeviceErrors    -AccountId 12345 -Endpoint $endpoint
$sessions = Get-CoveSessions        -AccountId 12345 -Endpoint $endpoint
$progress = Get-CoveSessionProgress -AccountId 12345 -Endpoint $endpoint
```

#### `Get-CoveAccountInfo`

Returns `Name`, `Token`, and `RepservUrl` for a device. Results are cached — repeated calls for the same `AccountId` within the session return immediately without an API call. Returns `$null` if the account cannot be resolved.

```powershell
$info = Get-CoveAccountInfo -AccountId 12345
```

| Parameter    | Type   | Default     |
|--------------|--------|-------------|
| `-AccountId` | int    | Required    |
| `-Visa`      | string | stored visa |

#### `Get-CoveDeviceErrors`

Returns error history from the repserv endpoint for a device. Queries the last 90 days.

```powershell
$errors = Get-CoveDeviceErrors -AccountId 12345 -TopN 5
```

| Parameter   | Type      | Default     |
|-------------|-----------|-------------|
| `-AccountId`| int       | Required    |
| `-Visa`     | string    | stored visa |
| `-TopN`     | int       | 5           |
| `-Endpoint` | hashtable | $null       |

Return object:

| Property        | Type  | Description                                                 |
|-----------------|-------|-------------------------------------------------------------|
| `LatestSession` | array | Top errors from the most recent session                     |
| `LatestMore`    | int   | Number of errors beyond TopN in the latest session          |
| `History`       | array | Top errors across the last 90 days                          |
| `HistoryMore`   | int   | Number of errors beyond TopN in history                     |
| `LastSessionId` | int   | Session ID of the most recent session                       |
| `SourceErrors`  | array | Top errors per datasource from the most recent failing session per plugin |
| `FetchFailed`   | bool  | True if the repserv endpoint was unreachable                |

Each error object: `Code`, `Text`, `Filename`, `Seen` (count), `LatestTime` (Unix seconds).

#### `Get-CoveM365Errors`

Returns M365 error history across Exchange, OneDrive, SharePoint, and Teams via the reporting API. The four data sources are queried in parallel.

```powershell
$m365 = Get-CoveM365Errors -AccountId 12345
$m365 = Get-CoveM365Errors -AccountId 12345 -ActiveSources 'D19D20'
```

| Parameter       | Type   | Default     | Description |
|-----------------|--------|-------------|-------------|
| `-AccountId`    | int    | Required    | |
| `-Visa`         | string | stored visa | |
| `-ActiveSources`| string | ''          | Concatenated 3-char datasource codes to limit which sources are queried (e.g. `'D19D20'`). Empty = all four. |
| `-TopN`         | int    | 5           | |
| `-AccountToken` | string | $null       | Pass a pre-fetched account token to skip the `GetAccountInfoById` call. |

Return shape is identical to `Get-CoveDeviceErrors`. `History` is always empty (the M365 reporting API returns current session errors only).

M365 datasource codes: `D19`=Exchange, `D20`=OneDrive, `D05`=SharePoint, `D23`=Teams.

#### `Get-CoveSessionProgress`

Returns progress of the most recent or active backup session for a device.

```powershell
$progress = Get-CoveSessionProgress -AccountId 12345
Write-Host "$($progress.PercentComplete)% - $($progress.Status)"
```

| Parameter   | Type      | Default     |
|-------------|-----------|-------------|
| `-AccountId`| int       | Required    |
| `-Visa`     | string    | stored visa |
| `-Endpoint` | hashtable | $null       |

Return object: `FetchFailed`, `PercentComplete`, `ProcessedSize`, `SelectedSize`, `ChangedSize`, `ProcessedCount`, `SelectedCount`, `SentSize`, `SessionId`, `Status`.

#### `Get-CoveSessions`

Returns session history for a device. Each session is mapped to a normalized status code. Retries automatically on transient failures.

```powershell
$epoch    = [long]((Get-Date).AddDays(-30) - [DateTime]::new(1970,1,1,0,0,0,'Utc')).TotalSeconds
$sessions = Get-CoveSessions -AccountId 12345 -StartTime $epoch
```

| Parameter   | Type      | Default       |
|-------------|-----------|---------------|
| `-AccountId`| int       | Required      |
| `-Visa`     | string    | stored visa   |
| `-StartTime`| long      | 0 (no filter) |
| `-EndTime`  | long      | 0 (no filter) |
| `-Endpoint` | hashtable | $null         |

Each session object: `SrcCode` (datasource code e.g. `D01`), `StartTimeUnix`, `EndTimeUnix`, `Status` (int), `SelectedSize` (bytes).

Status codes: 1=InProgress, 2=Failed, 3=Aborted, 5=Success, 6=Interrupted, 7=NotStarted, 8=CompletedWithErrors, 9=InProgressWithFaults, 10=OverQuota, 12=Restarted, 13=Blocked.

Returns `$null` if the endpoint is unreachable or no sessions are found.

---

### Device Write

#### `Set-CoveDeviceCustomColumn`

Writes a value to a Cove device custom column. Supports `-WhatIf`.

```powershell
Set-CoveDeviceCustomColumn -DeviceId 12345 -ColumnId 7 -Value 'Server'
Set-CoveDeviceCustomColumn -DeviceId 12345 -ColumnId 7 -Value ''        # clear
Set-CoveDeviceCustomColumn -DeviceId 12345 -ColumnId 7 -Value 'Test' -WhatIf
```

| Parameter   | Type   | Default     |
|-------------|--------|-------------|
| `-DeviceId` | long   | Required    |
| `-ColumnId` | int    | Required    |
| `-Value`    | string | ''          |
| `-Visa`     | string | stored visa |

Throws if the API returns an error response.

---

## Datasource Codes

| Code | Datasource        |
|------|-------------------|
| D01  | Files and Folders |
| D02  | System State      |
| D04  | Exchange Stores   |
| D05  | M365 SharePoint   |
| D06  | Network Shares    |
| D08  | VMware            |
| D10  | MS SQL            |
| D11  | SharePoint        |
| D12  | Oracle            |
| D14  | Hyper-V           |
| D15  | MySQL             |
| D19  | M365 Exchange     |
| D20  | M365 OneDrive     |
| D23  | M365 Teams        |

---

## Author

Stan Clemance
