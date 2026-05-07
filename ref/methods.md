# API Methods — Unwrapped

Endpoint: `https://api.backup.management/jsonapi` (JSON-RPC 2.0, visa in body)

Methods already wrapped by `coveApi.psm1` are omitted: `Login`, `EnumerateAccountStatistics`, `GetAccountInfoById`, `EnumerateAccountRemoteAccessEndpoints`, `GetPartnerInfoById`, `GetPartnerWebBranding`, `UpdateAccountCustomColumnValues`.

---

## Partner / Customer

| Method | Description | Key params |
|--------|-------------|------------|
| `EnumeratePartners` | List sub-partners (customers) under a parent | `parentPartnerId` (int), `fetchRecursively` (bool), `fields` (PartnerFields) |
| `EnumerateChildPartners` | Immediate child partners with pagination | `partnerId`, `fields`, `range`, `partnerFilter` |
| `EnumerateAncestorPartners` | Parent chain up to root | `partnerId` |
| `GetPartnerInfoByUid` | Look up partner by GUID UID | `partnerUid` (string) |
| `GetPartnerState` | Returns state enum | `partnerId` |
| `ChangePartnerState` | Enable / suspend / close a partner | `partnerId`, `action` (PartnerAction enum), `reason` (string) |
| `AddPartner` | Create new customer | `partnerInfo` (PartnerInfo), `createDefaultAccount` (bool) — returns new partner ID |
| `AddPartnerEx` | Create with reset password URL | Same as `AddPartner` plus OUT `resetPasswordUrl` |
| `RemovePartner` | Permanently delete customer and all devices | `partnerId` — **irreversible** |
| `ModifyPartner` | Update partner fields | `partnerInfo`, `forceRemoveCustomColumnValuesInOldScope` |
| `GetAutoDeploymentPartnerState` | Check auto-deploy state | `partnerId` — returns `"Enable"`, `"Disable"`, `"Unspecified"`, `"Undefined"` |
| `ModifyAutoDeploymentPartnerState` | Enable or disable auto-deploy | `partnerId`, `autoDeploymentState` (`"Enable"` or `"Disable"` only — `"Unspecified"` is invalid) |
| `IsAutoDeploymentAllowedForPartner` | License check for auto-deploy | `partnerId` — returns bool |
| `GetAutoDeployCommandLine` | Installer command string with partner-uid | `partnerId`, `profileName` (optional, default `"Default"`) |
| `GetAdvancedPartnerProperties` | Extended partner settings | `partnerId` |
| `SetAdvancedPartnerProperties` | Update extended settings | `partnerId`, `advancedPartnerPropertiesInfo` |
| `EnumeratePartnersAtTime` | Historical partner list at a point in time | `parentPartnerId`, `fetchRecursively`, `time` (AbsoluteTime) |
| `EnumerateRemovedPartners` | Partners deleted in a date range | `parentPartnerId`, `startTime`, `endTime` |

---

## Device / Account

| Method | Description | Key params |
|--------|-------------|------------|
| `AddAccount` | Create a new backup device | `accountInfo` (AccountInfo: PartnerId, AccountName, etc.), `homeNodeInfo` (StorageNodeInfo) — returns AccountCredentials |
| `RemoveAccount` | Delete device permanently | `accountId` (int) — **irreversible** |
| `RemoveAccountData` | Delete backup data only (keep account) | `accountId` |
| `ModifyAccount` | Update device settings | `accountInfo`, `forceRemoveCustomColumnValuesInOldScope` |
| `ModifyAccountsBatch` | Bulk update multiple devices | `accountIds` (set), `accountInfo` |
| `GenerateReinstallationPassphrase` | Generate passphrase to reinstall preserving identity | `accountId` (int — must be integer, not string) — returns passphrase string |
| `GetAccountCustomColumnValues` | Get all custom column values for a device | `accountId` — returns map of `{columnId: value}` |
| `EnumerateAccountIdsByLabel` | Find device IDs by label | `label` (string) |
| `AddAccountLabel` / `RemoveAccountLabel` | Add/remove labels on devices | `accountIdCollection` (set of int), `labelCollection` (set of string) |
| `EnumerateAccountProfiles` | List account profiles/templates | `partnerId` |
| `GetAccountProfileInfo` | Get a single profile | `accountProfileId` |
| `AddAccountProfile` / `ModifyAccountProfile` / `RemoveAccountProfile` | Profile CRUD | profile ID or AccountProfileInfo object |
| `GetAccountInfoByIdWithRemoved` | Like `GetAccountInfoById` but includes deleted accounts | `accountId` |

---

## Columns & Custom Columns

| Method | Description | Key params |
|--------|-------------|------------|
| `EnumerateColumns` | List all available column codes with names and types | `partnerId` — use to discover column codes dynamically |
| `EnumerateCustomColumns` | List custom column definitions at a partner level | `partnerId` |
| `AddCustomColumn` | Create a new custom column | `customColumn` (CustomColumnInfo: Name, PartnerId, ValueType) — returns column ID (integer) |
| `ModifyCustomColumn` | Rename or modify a custom column | `customColumn` (CustomColumnInfo with ID) |
| `RemoveCustomColumn` | Delete a custom column | `customColumnId` (int) |
| `GetCustomColumnInfoById` | Get a single custom column definition | `customColumnId` |

**Gotcha:** custom column codes in `EnumerateAccountStatistics` are `AA<id>` (e.g. `AA3424`), but `UpdateAccountCustomColumnValues` takes the integer `columnId` (e.g. `3424`) in the `values` array — not the `AA`-prefixed string.

---

## Audit Log

| Method | Description | Key params |
|--------|-------------|------------|
| `EnumerateAuditActions` | Retrieve portal audit log entries | `actionInfo` (ServiceAuditActionInfo), `from` (time_t), `to` (time_t), `countLimit` (int), `includeAllSubPartners` (bool), `reverseOrder` (bool) |
| `EnumerateAuditActionEntityTypes` | List entity types for filtering | none |
| `EnumerateAuditActionOperationTypes` | List operation types for filtering | none |
| `EnumerateAuditActionResultTypes` | List result types for filtering | none |

---

## Users & Contacts

| Method | Description | Key params |
|--------|-------------|------------|
| `EnumerateUsers` | List portal users | `partnerIds` (set of int) |
| `EnumerateUsersByFilter` | Filtered user list | `filter` (UserFilter) |
| `GetUserInfoById` | Single user | `userId` |
| `AddUser` | Create portal user | `userInfo` (UserInfo) — returns user ID |
| `ModifyUser` | Update user | `userInfo` |
| `RemoveUser` | Delete user | `userId` |
| `EnumerateContactPersons` | List contacts | `partnerIds` (set) |
| `AddContactPerson` / `ModifyContactPerson` / `RemoveContactPerson` | Contact CRUD | contactPersonInfo or ID |
| `AddContactNote` / `ModifyContactNote` / `RemoveContactNote` | Notes on contacts | contactNoteInfo or ID |
| `EnumerateUserRoles` | List available roles | none |

---

## Notifications

| Method | Description | Key params |
|--------|-------------|------------|
| `EnumerateNotificationRules` | List rules for a partner | `partnerId` |
| `AddNotificationRule` | Create a rule | `rule` (NotificationRule) |
| `ModifyNotificationRule` | Update a rule | `rule` |
| `RemoveNotificationRule` | Delete a rule | `id` (int) |
| `EnableNotificationRule` | Enable or disable a rule | `ruleId`, `partnerId`, `enable` (bool) |
| `EnumerateNotificationTransports` | List email/webhook transports | `partnerId` |
| `AddNotificationTransport` / `ModifyNotificationTransport` / `RemoveNotificationTransport` | Transport CRUD | transport object or ID |
| `EnumerateTemplates` | List notification templates | `partnerId`, `partnerOnly` (bool) |
| `AddNotificationTemplate` / `ModifyNotificationTemplate` / `RemoveNotificationTemplate` | Template CRUD | template object or ID |

---

## Storage

| Method | Description | Key params |
|--------|-------------|------------|
| `EnumerateStorages` | List storage locations | `partnerId` |
| `EnumerateStorageNodes` | List nodes under a storage | `storageId` |
| `EnumerateStorageStatistics` | Storage usage stats | `partnerId` |
| `GetStorageInfo` / `GetStorageNodeInfo` | Single storage / node | `storageId` or `storageNodeId` |
| `EnumerateStorageNodesByAccountId` | Which nodes host specific devices | `accounts` (set of int) |

---

## Aggregated History

| Method | Description | Key params |
|--------|-------------|------------|
| `EnumerateAggregatedStatisticsHistory` | Daily time-series rollup for a partner | `query.PartnerId`, `query.From` (Unix), `query.To` (Unix), `query.Aggregates` (int[]) — see aggregate ID table in `backup-monitor/docs/cove-api.md` |

**Scope:** `PartnerId` accepts customer-level IDs (the `I83` column value) to scope to one customer. **Limitation:** no aggregate exists for backup success/failure counts — only storage sizes, device counts, and data-source counts.

---

## M365 Reporting API

Endpoint: `https://api.backup.management/reporting_api`. Auth: `Authorization: Bearer <visa>` header. Key param: `accountToken` from `GetAccountInfoById`.

| Method | Description | Key params |
|--------|-------------|------------|
| `EnumerateSessions` | M365 per-device session history | `accountToken`, `range` ({Offset, Size}), `filter` ({CreatedAfter, CreatedBefore}) |
| `EnumerateDataSources` | M365 data source configuration (auto-add status, settings) | `accountToken` |
| `EnumerateSessionErrors` | M365 error messages per session | `accountToken`, `dataSourceType` (required: `"Exchange"`, `"OneDrive"`, `"SharePoint"`, `"Teams"`), `filter` ({SessionId, SessionType}), `range` — **one call per datasource** |

**`EnumerateSessionErrors` gotchas:**
- `dataSourceType` is required — omit it and you get -32603
- `Description` field in the response is a JSON-encoded string — must be deserialized to extract `description`, `entity`, `path`
- `Item` field contains the affected mailbox/user name
- Errors repeat across sessions — filter to max `SessionId`, then deduplicate by `description + item + path`

---

## Session / Job Control

| Method | Description | Key params |
|--------|-------------|------------|
| `ControlJob` | Start / stop / pause / resume a job | `jobId` (int), `action` (JobControlAction enum) |
| `SendUserInvitation` | Email a portal invitation | `receiverUserId`, `inviterUserId` (optional), `redeemLink` |

---

## Branding

| Method | Description | Key params |
|--------|-------------|------------|
| `SetBranding` | Set application branding | `partnerId`, `applicationType`, `brandingBody` |
| `SetPartnerWebBranding` | Set web portal branding (ZIP archive) | `partnerId`, `webBrandingArchive` |
| `FindBranding` | Get branding for a partner | `partnerId`, `applicationType` |

---

## Misc

| Method | Description | Key params |
|--------|-------------|------------|
| `GetServerInfo` | API server info (version, etc.) | none |
| `GetEffectiveEnvironmentInfo` | Environment details | none |
| `EnumerateFeatures` | Features enabled for a partner | `partnerId` |
| `EnumerateProducts` | Licensed products | `partnerId`, `currentPartnerOnly` (bool) |
| `GetAutoLoginUrl` | Auto-login URL for portal | `partnerId` — **returns error 13501 in practice; blocked for security reasons** |
| `RemovePersonalData` | GDPR data deletion | `partnerId`, `fromTimestamp` (optional), `toTimestamp` (optional) |
| `GetEncryptionKeyByPassphrase` | Retrieve encryption key | `accountId`, `passphrase` |
| `VerifyEncryptionKey` | Check if key is valid for account | `accountId`, `encryptionKey` |
