# Database Schema (SQLite)

*Part of: [02-architecture.md](02-architecture.md)*

---

## Core Tables

```sql
-- Core Tables
CREATE TABLE Devices (
    DeviceId TEXT PRIMARY KEY,
    Hostname TEXT NOT NULL,
    FQDN TEXT,
    IPAddress TEXT,
    MACAddress TEXT,
    SiteId TEXT,
    GroupIds TEXT,  -- JSON array
    OSName TEXT,
    OSVersion TEXT,
    OSBuild TEXT,
    LastSeen DATETIME,
    LastInventory DATETIME,
    Status TEXT DEFAULT 'Unknown',
    AgentVersion TEXT,
    Tags TEXT,  -- JSON array
    CustomFields TEXT,  -- JSON object
    CreatedAt DATETIME DEFAULT CURRENT_TIMESTAMP,
    UpdatedAt DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE Sites (
    SiteId TEXT PRIMARY KEY,
    Name TEXT NOT NULL,
    Location TEXT,
    Timezone TEXT,
    RelayAgent TEXT,
    ContactEmail TEXT,
    CreatedAt DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE DeviceGroups (
    GroupId TEXT PRIMARY KEY,
    Name TEXT NOT NULL,
    Description TEXT,
    ParentGroupId TEXT,
    PolicyId TEXT,
    CreatedAt DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE Inventory (
    InventoryId INTEGER PRIMARY KEY AUTOINCREMENT,
    DeviceId TEXT NOT NULL,
    Category TEXT NOT NULL,  -- Hardware, Software, Security, Network
    Data TEXT NOT NULL,  -- JSON blob
    CollectedAt DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (DeviceId) REFERENCES Devices(DeviceId)
);

CREATE TABLE Alerts (
    AlertId TEXT PRIMARY KEY,
    DeviceId TEXT NOT NULL,
    AlertType TEXT NOT NULL,
    Severity TEXT NOT NULL,  -- Critical, High, Medium, Low, Info
    Title TEXT NOT NULL,
    Message TEXT,
    Source TEXT,
    CreatedAt DATETIME DEFAULT CURRENT_TIMESTAMP,
    AcknowledgedAt DATETIME,
    AcknowledgedBy TEXT,
    ResolvedAt DATETIME,
    ResolvedBy TEXT,
    AutoResolved INTEGER DEFAULT 0,
    NotificationsSent TEXT,  -- JSON array
    FOREIGN KEY (DeviceId) REFERENCES Devices(DeviceId)
);

CREATE TABLE Actions (
    ActionId TEXT PRIMARY KEY,
    DeviceId TEXT,
    ActionType TEXT NOT NULL,
    Status TEXT DEFAULT 'Pending',  -- Pending, Running, Completed, Failed, Cancelled
    Priority INTEGER DEFAULT 5,
    Payload TEXT,  -- JSON
    Result TEXT,  -- JSON
    ScheduledAt DATETIME,
    StartedAt DATETIME,
    CompletedAt DATETIME,
    CreatedBy TEXT,
    CreatedAt DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE Metrics (
    MetricId INTEGER PRIMARY KEY AUTOINCREMENT,
    DeviceId TEXT NOT NULL,
    MetricType TEXT NOT NULL,  -- CPU, Memory, Disk, Network
    Value REAL NOT NULL,
    Unit TEXT,
    Timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (DeviceId) REFERENCES Devices(DeviceId)
);

CREATE TABLE AuditLog (
    LogId INTEGER PRIMARY KEY AUTOINCREMENT,
    Timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    User TEXT,
    Action TEXT NOT NULL,
    Target TEXT,
    Details TEXT,
    IPAddress TEXT,
    Success INTEGER DEFAULT 1
);

-- Indexes for performance
CREATE INDEX idx_devices_status ON Devices(Status);
CREATE INDEX idx_devices_site ON Devices(SiteId);
CREATE INDEX idx_inventory_device ON Inventory(DeviceId);
CREATE INDEX idx_inventory_date ON Inventory(CollectedAt);
CREATE INDEX idx_alerts_device ON Alerts(DeviceId);
CREATE INDEX idx_alerts_severity ON Alerts(Severity);
CREATE INDEX idx_alerts_created ON Alerts(CreatedAt);
CREATE INDEX idx_actions_status ON Actions(Status);
CREATE INDEX idx_actions_device ON Actions(DeviceId);
CREATE INDEX idx_metrics_device_type ON Metrics(DeviceId, MetricType);
CREATE INDEX idx_metrics_timestamp ON Metrics(Timestamp);
```

---

*Next: [modules/03-core-framework.md](modules/03-core-framework.md)*

