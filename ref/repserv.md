# Repserv Endpoint

Device-level JSON-RPC endpoint. Hosted on Cove cloud infrastructure — device does not need to be online.

**Endpoint:** `https://<host>/repserv_json`

Derive from `EnumerateAccountRemoteAccessEndpoints` (accountId = device AU):
- Parse `WebRcgUrl` → extract scheme + host → append `/repserv_json`
- Example: `https://ca-tr2-0203-21.cloudbackup.management/repserv_json`

`coveApi.psm1` encapsulates this in `Get-CoveAccountInfo`, which caches the result.

**Auth:** visa in `params` (not top-level). Also pass `account` (device name from `GetAccountInfoById`) and `token` (UUID from `GetAccountInfoById.result.result.Token`).

---

## QueryErrors

Returns backup error records. Errors are stored server-side; history going back years is available.

**Request params:**

| Param | Type | Req | Notes |
|-------|------|-----|-------|
| `accountId` | int | Yes | Device AU value |
| `account` | string | Yes | Device name from `GetAccountInfoById` |
| `token` | string | Yes | UUID from `GetAccountInfoById.result.result.Token` |
| `visa` | string | Yes | Current visa (inside `params`) |
| `sessionId` | int | Yes | `0` for all sessions; set to specific session ID to scope |
| `query` | string | Yes | Filter expression (see below) |
| `orderBy` | string | Yes | e.g. `"Time DESC"` |
| `groupId` | int | Yes | Use `0` |

**Response fields (per error record):**

| Field | Type | Description |
|-------|------|-------------|
| `Id` | int | Record ID |
| `SessionId` | int | Session this error belongs to |
| `Code` | int | Error code (e.g. 1800) |
| `Text` | string | Error message |
| `Filename` | string | Affected file path |
| `Count` | int | Occurrences of this Code+Text+Filename combination within the session |
| `Time` | Unix int | Timestamp of the error |

**`Count` semantics:** per `Code+Text+Filename` group within a session. Group key must include `Filename` — same error at different paths is a distinct row.

**Filter fields:**

| Field | Type | Operators |
|-------|------|-----------|
| `Time` | Unix int | `==`, `!=`, `>`, `>=`, `<`, `<=` |
| `SessionId` | int | `==` etc. |
| `Count` | int | `>=` (use `Count >= 3` to suppress single-occurrence noise) |
| `Filename` | string | `=~` (glob, `*` = any sequence) |
| `Text` | string | `=~` |
| `Code` | int | `==` etc. |

**Recommended queries:**
- All errors in date window, noise suppressed: `Time >= <start> and Time <= <end> and Count >= 3`
- Errors for a specific session: `SessionId == <id>` (also set `sessionId=<id>` in params)

---

## QuerySessions

Returns backup session records for a device.

**Auth note:** `visa` goes inside `params` (not top-level), alongside `account` and `token`.

**Request params:**

| Param | Type | Req | Notes |
|-------|------|-----|-------|
| `accountId` | int | Yes | Device AU value |
| `account` | string | Yes | Device name |
| `token` | string | Yes | UUID from `GetAccountInfoById` |
| `visa` | string | Yes | Inside params |
| `query` | string | Yes | Filter expression (see below) |
| `orderBy` | string | Yes | e.g. `"BackupStartTime DESC"`, `"Id DESC"` |
| `range` | object | No | `{ Offset: 0, Size: 500 }` — paginate large sets |

**Response fields (per session):**

| Field | Type | Description |
|-------|------|-------------|
| `Id` | int | Session ID |
| `PluginId` | string | Data source name, e.g. `"FileSystem"`, `"VssSystemState"` |
| `StartTime` | Unix int | Session start |
| `EndTime` | Unix int | Session end; `0` if still in progress |
| `Status` | string | `"Completed"`, `"CompletedWithErrors"`, `"Failed"`, `"Aborted"`, `"Interrupted"`, `"InProgress"` |
| `ErrorsCount` | int | Errors in this session |
| `Flags` | string[] | e.g. `["Synchronized", "Accelerated"]` |
| `Type` | string | `"BatchBackup"` for normal backup sessions |
| `SelectedSize` | long | Total selected data size, bytes |
| `ProcessedSize` | long | Data processed, bytes |
| `ChangedSize` | long | Changed data, bytes |
| `SentSize` | long | Actual bytes transferred (post dedup/compression) |
| `SelectedCount` | int | Files/items in selection |
| `ProcessedCount` | int | Files/items processed |
| `ChangedCount` | int | Changed files/items |
| `RemovedFilesCount` | int | |
| `BuildVersion` | string | Client version |
| `TransientValues` | object | In-progress tracking; all zero on completed sessions |

**One row per plugin per backup cycle.** A single backup run produces sequential session IDs, one per datasource plugin.

**`Status` string vs filter integer:** response field is a string; the `Status` filter field is an integer (same enum as `T0`). Status string `"Completed"` with `ErrorsCount > 0` is equivalent to status 8.

**Filter fields:**

| Field | Type | Notes |
|-------|------|-------|
| `BackupStartTime` | Unix int | `>=`, `<=` for date range |
| `Plugin` | int | Plugin integer code — see `datasources.md` table |
| `Status` | int | T0 enum: 5=Success, 8=CompletedWithErrors, 2=Failed, 3=Aborted, 6=Interrupted, 7=NotStarted, 1=InProgress |
| `Type` | bitmask | `(Type & 1) == 1` = backup sessions |
| `Flags` | bitmask | 1=Synchronized, 2=Accelerated |
| `ErrorsCount` | int | `> 0` directly selects sessions with errors |
| `SelectedSize` | int | Cove UI uses `>= 234` to exclude trivial sessions |
| `SelectedCount` | int | Cove UI uses `>= 2` |

**Recommended queries:**
- All substantive backup sessions in date window: `BackupStartTime >= <start> and BackupStartTime <= <end> and (Type & 1) == 1 and SelectedCount >= 2`
- Only failing sessions for error follow-up: `(Status == 2 or Status == 3 or Status == 6 or Status == 8) and (Type & 1) == 1 and BackupStartTime >= <cutoff> and ErrorsCount > 0`

---

## EnumerateSessionErrorsGroupDetails

Alternative to `QueryErrors` — returns individual error instances (not deduplicated).

**Request params:** same as `QueryErrors`.

**Response fields (per record):**

| Field | Type | Description |
|-------|------|-------------|
| `ErrorText` | string | Error message (vs `Text` in QueryErrors) |
| `Path` | string | File path (vs `Filename` in QueryErrors) |
| `Plugin` | int | Plugin integer code |
| `GroupId` | int | |
| `NodeId` | int | |
| `Time` | Unix int | |

**Key differences from QueryErrors:** no `Code` field, no `Count` field, has `Plugin`. Use `QueryErrors` for diagnostics (error codes are more actionable); use this if plugin-level attribution is needed.

---

## Device Schedule Write Methods

Available at `https://<host>/rcg/<partner-slug>/<token>/jsonrpcv1` (different path from repserv). Auth via `visa` in body.

### AddNewSchedule

Params: none. Returns: new `scheduleId` (int) in `result.result`.

### ModifySchedule

| Param | Type | Notes |
|-------|------|-------|
| `scheduleId` | int | From `AddNewSchedule` |
| `name` | string | Display name |
| `fireTime` | string | `"HH:mm"` 24-hour |
| `daysOfWeek` | int | Bitmask: Mon=1, Tue=2, Wed=4, Thu=8, Fri=16, Sat=32, Sun=64. Common: 31=weekdays, 127=every day |
| `plugins` | string[] | e.g. `["FileSystem","VssSystemState","NetworkShares","VMWare","VssMsSql","Oracle"]` |
| `preScriptId` | int | 0 for none |
| `postScriptId` | int | 0 for none |

### EnableSchedule

| Param | Type | Notes |
|-------|------|-------|
| `scheduleId` | int | |
| `enable` | bool | `true` to enable |

### RemoveSchedule

| Param | Type | Notes |
|-------|------|-------|
| `scheduleId` | int | |

**Note:** No read method exists for schedules via any API endpoint. The schedule HTML is served by the portal SPA only and requires a web session cookie that cannot be obtained programmatically.
