# Reporting (scripts/reports/)

*Previous: [07-alerts.md](07-alerts.md)*

---

## Report-Generator.ps1

### Report Types

| Report | Frequency | Format | Content |
|--------|-----------|--------|---------|
| Executive Summary | Weekly | HTML/PDF | Health scores, trends, top issues |
| Device Inventory | Monthly | Excel | Complete asset list with details |
| Alert Summary | Daily | HTML | Alert counts by severity/device |
| Update Compliance | Weekly | HTML | Patch status across fleet |
| Security Posture | Weekly | HTML/PDF | Security scores, vulnerabilities |
| Performance Trends | Weekly | HTML | Resource utilization graphs |
| Uptime Report | Monthly | HTML | Availability percentages |
| Audit Log | On-demand | CSV | All actions with timestamps |

---

## Compliance-Reporter.ps1

- **Purpose:** Compliance and baseline checking
- **Compliance Frameworks:**
  - CIS Benchmarks (Windows 10/11, Server)
  - NIST guidelines
  - Custom organizational policies
- **Output:** Compliance score, deviations list, remediation recommendations

---

## Executive-Dashboard.ps1

- **Purpose:** Management-friendly overview
- **Metrics:**
  - Fleet health score (aggregate)
  - Active alerts by severity
  - Patch compliance percentage
  - Top 10 problematic devices
  - Trend charts (7/30/90 days)

---

*Next: [09-automation.md](09-automation.md)*

