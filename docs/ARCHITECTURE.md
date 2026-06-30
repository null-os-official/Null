# Null OS Architecture

The philosophy behind Null OS is straightforward: modern operating systems are weighed down by unnecessary features, telemetry, and background services that benefit the vendor, not the user. Null OS exists to reverse this. It is a highly opinionated, brutally optimized configuration for Windows 11 Pro, executed via AME Wizard.

## Design Pillars

### 1. Absolute Zero Telemetry
Windows natively collects vast amounts of diagnostic data, usage patterns, and error reports. We consider this unacceptable for both privacy and performance reasons.
- **Approach:** We systematically disable all Connected User Experiences and Telemetry services. We null-route Microsoft telemetry endpoints using local host files and firewall rules. We strip out diagnostic scheduled tasks that run in the background.

### 2. Maximum Privacy Lockdown
A secure system is a private system. By default, Windows opts you into advertising IDs, location tracking, and content synchronization.
- **Approach:** We enforce local accounts only. We disable Cortana, OneDrive integration, and Windows Search web results. Registry policies are applied at the machine and user level to explicitly deny permissions to tracking APIs.

### 3. Brutal Performance & Low Latency
Every background process consumes CPU cycles, RAM, and potentially interrupts hardware processing. For gamers and power users, latency is the enemy. Our concrete goal for Null OS is extreme: **70 background processes on idle, and a maximum of 1.5GB of RAM consumed on a fresh boot**.
- **Approach:**
  - **Service Culling:** We disable non-essential services (e.g., Print Spooler if you don't print, Xbox Live Auth if you don't use it, Windows Defender if you provide your own security context).
  - **Network Stack Tuning:** Disabling Nagle's algorithm (TcpNoDelay), tuning MTU sizes, and disabling background intelligent transfer services (BITS) to ensure packets are processed instantly.
  - **Input Latency:** Adjusting Win32PrioritySeparation and enforcing high-performance power plans so the CPU never downclocks when processing I/O interrupts.

### 4. Enterprise-Tier Engineering
Unlike basic debloat scripts that run a few PowerShell commands and call it a day, Null OS uses AME Wizard's structured playbook system.
- **Approach:** Every change is mapped in `playbook.yaml`. We separate modifications into distinct phases (Configuration, Scripts). We use strict version control. Changes must be justified by measurable performance improvements or explicit privacy gains.

## The AME Wizard Flow
The AME Wizard utilizes a `.apbx` playbook format. 
1. The wizard extracts our playbook.
2. It parses `playbook.yaml`.
3. It executes the defined actions sequentially, running our Registry modifications and PowerShell scripts securely, often bypassing limitations that normal administrators face, thanks to TrustedUninstaller architecture.

Null OS is not for everyone. It is for those who demand total control over their hardware.
