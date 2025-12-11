# Core Architecture

*Previous: [01-repository-structure.md](01-repository-structure.md)*

---

## Hybrid Pull/Push Model

```
                                    ┌─────────────────────────────────────┐
                                    │         CENTRAL CONSOLE             │
                                    │  (Primary Management Server)        │
                                    │                                     │
                                    │  ┌─────────────┐ ┌──────────────┐  │
                                    │  │ Web Dashboard│ │ CLI Console  │  │
                                    │  └──────┬──────┘ └──────┬───────┘  │
                                    │         │               │          │
                                    │  ┌──────┴───────────────┴───────┐  │
                                    │  │      RMM-Core.psm1           │  │
                                    │  │  (Orchestration Engine)      │  │
                                    │  └──────────────┬───────────────┘  │
                                    │                 │                   │
                                    │  ┌──────────────┴───────────────┐  │
                                    │  │     SQLite Database          │  │
                                    │  │  (devices.db + cache/)       │  │
                                    │  └──────────────────────────────┘  │
                                    └─────────────────┬───────────────────┘
                                                      │
                    ┌─────────────────────────────────┼─────────────────────────────────┐
                    │                                 │                                 │
           ┌────────┴────────┐               ┌────────┴────────┐               ┌────────┴────────┐
           │   Site Alpha    │               │   Site Beta     │               │   Site Gamma    │
           │  (50 devices)   │               │  (50 devices)   │               │  (50 devices)   │
           │                 │               │                 │               │                 │
           │ ┌─────────────┐ │               │ ┌─────────────┐ │               │ ┌─────────────┐ │
           │ │ Relay Agent │ │               │ │ Relay Agent │ │               │ │ Relay Agent │ │
           │ │  (Optional) │ │               │ │  (Optional) │ │               │ │  (Optional) │ │
           │ └──────┬──────┘ │               │ └──────┬──────┘ │               │ └──────┬──────┘ │
           │        │        │               │        │        │               │        │        │
           │   WinRM/SSH     │               │   WinRM/SSH     │               │   WinRM/SSH     │
           │        │        │               │        │        │               │        │        │
           │ ┌──┬──┬┴┬──┬──┐ │               │ ┌──┬──┬┴┬──┬──┐ │               │ ┌──┬──┬┴┬──┬──┐ │
           │ │EP│EP│EP│EP│EP│ │               │ │EP│EP│EP│EP│EP│ │               │ │EP│EP│EP│EP│EP│ │
           │ └──┴──┴──┴──┴──┘ │               │ └──┴──┴──┴──┴──┘ │               │ └──┴──┴──┴──┴──┘ │
           └──────────────────┘               └──────────────────┘               └──────────────────┘
```

---

## Communication Methods

| Method | Use Case | Port | Scalability |
|--------|----------|------|-------------|
| WinRM (HTTP) | Internal Windows | 5985 | Up to 500/batch |
| WinRM (HTTPS) | Secure/External | 5986 | Up to 500/batch |
| SSH | Linux/macOS/Cross-platform | 22 | Up to 200/batch |
| SMB Fallback | Firewalled devices | 445 | File-based queue |
| Relay Agent | Remote sites | Custom | Unlimited (queued) |

---

## Data Storage Architecture

### Tiered Storage Model

```
┌─────────────────────────────────────────────────────────────────┐
│                        HOT TIER (In-Memory)                     │
│  - Active sessions                                              │
│  - Real-time metrics (last 5 minutes)                          │
│  - Currently executing actions                                  │
│  TTL: Session duration                                          │
├─────────────────────────────────────────────────────────────────┤
│                      WARM TIER (JSON Cache)                     │
│  - Recent device states (last 24 hours)                        │
│  - Pending alerts                                               │
│  - Action queue                                                 │
│  Location: /data/cache/*.json                                   │
│  TTL: 24 hours, then migrate to cold                           │
├─────────────────────────────────────────────────────────────────┤
│                      COLD TIER (SQLite)                         │
│  - Device inventory (all devices)                               │
│  - Historical metrics                                           │
│  - Alert history                                                │
│  - Audit logs                                                   │
│  Location: /data/devices.db                                     │
│  Retention: Configurable (default 90 days)                     │
├─────────────────────────────────────────────────────────────────┤
│                    ARCHIVE TIER (Compressed)                    │
│  - Historical reports                                           │
│  - Compliance snapshots                                         │
│  - Old logs                                                     │
│  Location: /data/archive/*.zip                                  │
│  Retention: 2 years                                             │
└─────────────────────────────────────────────────────────────────┘
```

---

*Continued in [02-architecture-schema.md](02-architecture-schema.md) (Database Schema)*

*Next: [modules/03-core-framework.md](modules/03-core-framework.md)*

