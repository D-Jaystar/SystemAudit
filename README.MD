# SystemAudit & Maintenance Suite

A modular, automated PowerShell audit and maintenance tool designed for Windows workstations. This tool audits system health, inspects low-level hardware metrics, validates security integrity, and performs deep automated disk cleanups.

---

## Features

### 1. Hardware & Performance Diagnostics
* **Disk Space:** Monitors free capacity across all logical drives to prevent throttling and degradation.
* **Disk Health & S.M.A.R.T.:** Extracts reliability counters, operational status, wear levels, and read/write error metrics.
* **CPU Load & Processes:** Identifies top resource-heavy processes consuming excessive CPU cycles.
* **Memory (RAM) Usage:** Checks active physical memory allocation and free system capacity.
* **RAM Health & Diagnostics:** Inspects physical modules and queries Event Viewer for memory diagnostic faults.
* **Temperature Monitoring:** Queries ACPI Thermal Zones and hardware sensors to detect thermal throttling risks.
* **Fan Status:** Inspects cooling fan operational status and speed indicators where supported by WMI.
* **Battery Health:** Pulls battery wear, charge capacity, and lifecycle health metrics (generates XML battery reports).
* **Power Supply State:** Verifies power feed, AC adapter status, and enclosure security state.
* **Graphics Card (GPU) Status:** Checks status, driver version, and queries NVIDIA SMI telemetry where available.
* **Peripheral Devices:** Scans connected peripherals and USB devices for device driver errors (`Status != OK`).

### 2. Security & System Integrity
* **Windows Updates:** Checks for pending patches and inspects recent update installation history.
* **Antivirus & Defender:** Validates active real-time protection, signature status, and engine health.
* **Firewall Status:** Verifies firewall state and rule policies across Domain, Private, and Public profiles.
* **Network Connections:** Scans active TCP connections and flags listening ports on non-loopback addresses.
* **Security Event Logs:** Queries the Windows Security log for suspicious audit failures and critical events.
* **User Accounts & Privileges:** Audits local users and verifies the members of the local `Administrators` group.
* **File Integrity Monitoring (FIM):** Computes and verifies SHA-256 hashes of critical system binaries.
* **Scheduled Tasks:** Audits third-party scheduled tasks for persistence vectors or unauthorized automation.
* **Driver Signatures:** Confirms that loaded kernel and device drivers are digitally signed.
* **System Restore:** Validates that System Protection is enabled and recent restore points exist.

### 3. Automated System Maintenance & Cleanup
* **Windows Temp:** Purges system-level temporary files and obsolete installer logs in `C:\Windows\Temp`.
* **User Temp & Cache:** Clears user-level temporary files (`%TEMP%`) and local application caches.
* **Recycle Bin:** Empties the Windows Recycle Bin (`$Recycle.Bin`) across all mounted volumes.
* **Component Store Cleanup:** Executes DISM component cleanup to purge superseded Windows Update backups.
* **Crash Dumps & WER:** Deletes memory crash dumps (`*.dmp`) and Windows Error Reporting logs.
* **Prefetch Data:** Flushes stale prefetch records to reclaim secondary storage.
* **Delivery Optimization:** Clears peer-to-peer Windows Update distribution cache files.
* **Web & Browser Caches:** Flushes temporary internet files and browser runtime caches.
* **Build & Package Caches:** Clears obsolete build artifacts and development package caches.
* **Storage Optimization:** Triggers SSD TRIM optimization to maintain drive endurance and performance.

---

## Installation & Setup

1. Clone the repository:
   ```powershell
   //todo
  