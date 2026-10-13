# Azure Chaos Resilience Lab — Team T087

> **Hackathon Project** | Azure Resilience Engineering | Team T087

---

## 📋 Problem Statement

Modern cloud applications must withstand infrastructure failures without service disruption. This project validates the resilience of a **Virtual Machine Scale Set (VMSS)**-based workload deployed across **Availability Zones** in Azure, using both **planned Chaos Studio experiments** and a **controlled VMSS instance failure test**.

**Key question:** *Can a zone-redundant VMSS behind an Azure Load Balancer maintain 100% request availability during an unplanned instance failure?*

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Azure Region                              │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐              │
│  │  Zone 1     │  │  Zone 2     │  │  Zone 3     │              │
│  │  ┌───────┐  │  │  ┌───────┐  │  │  ┌───────┐  │              │
│  │  │ VMSS  │  │  │  │ VMSS  │  │  │  │ VMSS  │  │              │
│  │  │Instance│  │  │  │Instance│  │  │  │Instance│  │              │
│  │  └───────┘  │  │  └───────┘  │  │  └───────┘  │              │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘              │
│         │                │                │                      │
│         └────────────────┼────────────────┘                      │
│                          ▼                                       │
│              ┌───────────────────────┐                           │
│              │  Azure Load Balancer  │                           │
│              │   (Standard SKU,      │                           │
│              │    Zone-Redundant)    │                           │
│              └───────────┬───────────┘                           │
│                          │                                       │
│                          ▼                                       │
│              ┌───────────────────────┐                           │
│              │   Client / Test       │                           │
│              │   Harness             │                           │
│              └───────────────────────┘                           │
└─────────────────────────────────────────────────────────────────┘
```

### Azure Resources Deployed (via Portal & Cloud Shell)

| Resource | Configuration | Purpose |
|----------|---------------|---------|
| **Resource Group** | `rg-t087-chaos-resilience` | Logical container |
| **Virtual Network** | `vnet-t087` (10.0.0.0/16) | Network isolation |
| **Subnet** | `subnet-vmss` (10.0.1.0/24) | VMSS placement |
| **VM Scale Set** | `vmss-t087-chaos` | Zone-redundant (Zones 1,2,3), 3 instances, Ubuntu 22.04, NGINX |
| **Load Balancer** | `lb-t087-chaos` (Standard, Zone-Redundant) | Traffic distribution, health probes |
| **Public IP** | `pip-t087-chaos` (Standard, Zone-Redundant) | Public endpoint |
| **Network Security Group** | `nsg-t087-chaos` | Allow HTTP (80), SSH (22) |
| **Log Analytics Workspace** | `law-t087-chaos` | Metrics & logs |
| **Chaos Studio** | `chaos-t087` (planned, not executed) | Targeted fault injection |

> **Note:** All infrastructure was provisioned manually via **Azure Portal** and **Azure Cloud Shell (Bash)**. No IaC (Bicep/Terraform) was used in this hackathon.

---

## 🧪 Experiments

### 1. Planned: Azure Chaos Studio Experiment (Not Executed)

A Chaos Studio experiment was **designed and configured** to inject a **zone-down fault** (simulating an entire Availability Zone outage) targeting the VMSS.

| Property | Value |
|----------|-------|
| Experiment Name | `exp-t087-zone-down` |
| Target | `vmss-t087-chaos` (all instances across zones) |
| Fault Type | `Microsoft.Compute/virtualMachineScaleSets` → `zoneDown` |
| Duration | 5 minutes |
| Status | **Blocked** |

**Why it did not run:** The subscription's **Azure Policy — "Allowed resource deployment regions"** prevented Chaos Studio from deploying its internal agent/resources in the required region. The experiment remains in the portal as a saved configuration but was never executed.

> ⚠️ **No actual zone-down fault was injected.** The results below come from a different, controlled test.

---

### 2. Executed: Controlled VMSS Instance Failure Test

A **manual, controlled test** was performed by **deallocating a single VMSS instance** (simulating an unplanned VM failure) while the load balancer distributed traffic across the remaining healthy instances. The instance was subsequently restarted to verify recovery.

| Property | Value |
|----------|-------|
| Action (Failure) | `az vmss deallocate --resource-group rg-t087-chaos-resilience --name vmss-t087-chaos-resilience --instance-ids 0` |
| Action (Recovery) | `az vmss start --resource-group rg-t087-chaos-resilience --name vmss-t087-chaos-resilience --instance-ids 0` |
| Target | Single instance in Zone 1 (instance ID 0) |
| Load Balancer Health Probe | HTTP `/` on port 80, interval 5s, unhealthy threshold 2 |
| VMSS Scale-In Policy | `Default` (oldest VM) |
| Test Duration | ~3 minutes (instance deallocation + restart + health probe recovery) |

---

## 📊 Results

### Test Methodology

A simple HTTP load test was run from a client VM (outside the VNet) against the Load Balancer public IP:

```bash
for i in {1..20}; do curl -s -o /dev/null -w "%{http_code}\n" http://<LB_PUBLIC_IP>/; done
```

Each phase: **20 sampled requests** (not a continuous load test).

| Phase | Requests | HTTP 200 | HTTP 5xx / Failures | Availability |
|-------|----------|----------|---------------------|--------------|
| **Baseline** (steady state) | 20 | 20 | 0 | 100% |
| **During Instance Deallocation** | 20 | 20 | 0 | 100% |
| **After Instance Restart** (all 3 instances running) | 20 | 20 | 0 | 100% |

### Interpretation

- The **zone-redundant Load Balancer** correctly detected the unhealthy instance (via health probes) and stopped routing traffic to it within ~10–15 seconds.
- The **deallocated instance was restarted** (not replaced) and re-registered with the load balancer after passing health probes.
- All 20 sampled requests in each phase returned **HTTP 200**.

> ⚠️ **These are sampled requests, not a proof of 100% availability guarantee.** A continuous high-throughput load test would likely show brief 5xx/connection errors during the health-probe detection window (typically 10–30 seconds depending on probe configuration). The test validates that the *architecture* is sound and *automatic recovery* works, not that zero-downtime is mathematically guaranteed under all conditions.

---

## 🔁 Recovery

- **Detection:** Load Balancer health probe marks instance unhealthy after 2 consecutive failures (10 seconds with 5s interval).
- **Drain:** In-flight connections allowed to complete (default LB behavior).
- **Restart:** Deallocated instance (ID 0) restarted via `az vmss start` — no new instance provisioned.
- **Re-registration:** Restarted instance passes health probes, LB resumes routing.
- **Total recovery time observed:** ~3 minutes (deallocation + start + health probe recovery).

---

## 👥 Team T087

| Member | Role | Preparation Report |
|--------|------|-------------------|
| **Hareesh** | Architecture & Azure Resources | [docs/individual-reports/T087_Hareesh_Final_Review_Preparation_Report.docx](docs/individual-reports/T087_Hareesh_Final_Review_Preparation_Report.docx) |
| **Nandu** | Chaos Studio & Experiment Design | [docs/individual-reports/T087_Nandu_Final_Review_Preparation_Report.docx](docs/individual-reports/T087_Nandu_Final_Review_Preparation_Report.docx) |
| **Rupesh** | Load Testing & Observability | [docs/individual-reports/T087_Rupesh_Final_Review_Preparation_Report.docx](docs/individual-reports/T087_Rupesh_Final_Review_Preparation_Report.docx) |
| **Sneha** | Documentation & Presentation | [docs/individual-reports/T087_Sneha_Final_Review_Preparation_Report.docx](docs/individual-reports/T087_Sneha_Final_Review_Preparation_Report.docx) |

**Team Report:** [docs/team-report/T087_Azure_Chaos_Resilience_Team_Report.docx](docs/team-report/T087_Azure_Chaos_Resilience_Team_Report.docx)

**Presentation:** [docs/presentation/azure-chaos-resilience-presentation.pptx](docs/presentation/azure-chaos-resilience-presentation.pptx)

---

## 📖 Documentation & Scripts

| Document | Description |
|----------|-------------|
| [`architecture/resource-inventory.md`](architecture/resource-inventory.md) | Verified Azure resource configuration from CLI inventory |
| [`architecture/architecture.mmd`](architecture/architecture.mmd) | Mermaid architecture diagram (Internet → LB → VMSS across zones) |
| [`chaos-studio/experiment-configuration.md`](chaos-studio/experiment-configuration.md) | Chaos Studio experiment design, policy blocker, NOT EXECUTED |
| [`scripts/verify-instances.sh`](scripts/verify-instances.sh) | Read-only VMSS instance verification script |
| [`scripts/traffic-test.sh`](scripts/traffic-test.sh) | Configurable HTTP load test against LB public IP |
| [`scripts/controlled-failure.md`](scripts/controlled-failure.md) | Exact deallocation/restart commands and verification steps |
| [`docs/test-results.md`](docs/test-results.md) | Detailed 3-phase test results with limitations |

---

## 📚 Lessons Learned

1. **Chaos Studio region policy is a real blocker** — Even with proper RBAC, an organization-level "Allowed regions" policy can prevent Chaos Studio from deploying its agent resources. Validate policy *before* the hackathon.
2. **Health probe tuning matters** — Default 5s interval / 2 threshold = 10s detection. For stricter SLAs, use 1s interval (requires Standard LB) and/or Application Gateway with faster probes.
3. **VMSS instance replacement is not instant** — Cloud-init + application startup adds minutes. Consider **over-provisioning** (e.g., 4 instances for 3-zone HA) or **pre-warmed instances** for zero-downtime requirements.
4. **Manual Portal/Cloud Shell deployment is fast for prototyping but not reproducible** — Next step: codify as Bicep/Terraform for repeatable chaos experiments.
5. **Sampled curl tests ≠ production load tests** — Use tools like `hey`, `k6`, or `locust` for continuous RPS measurement and latency percentiles.

---

## 📁 Repository Structure

```
azure-chaos-resilience-lab/
├── README.md                    # This file
├── .gitignore                   # Excludes secrets, IDE files, build artifacts
├── SECURITY.md                  # Security guidelines
├── docs/
│   ├── team-report/             # Consolidated team report
│   ├── individual-reports/      # Each member's preparation report
│   ├── presentation/            # Hackathon presentation slides
│   └── test-results.md          # Detailed test results (3 phases)
├── architecture/
│   ├── resource-inventory.md    # Verified Azure resource configuration
│   └── architecture.mmd         # Mermaid architecture diagram
├── scripts/
│   ├── verify-instances.sh      # Read-only VMSS instance verification
│   ├── traffic-test.sh          # Configurable HTTP load test
│   └── controlled-failure.md    # Controlled failure test procedure
├── chaos-studio/
│   └── experiment-configuration.md  # Chaos Studio experiment (NOT EXECUTED)
├── evidence/
│   ├── baseline/                # (Placeholder) Baseline test evidence
│   ├── failure/                 # (Placeholder) Failure injection evidence
│   ├── recovery/                # (Placeholder) Recovery evidence
│   └── chaos-studio/            # (Placeholder) Chaos Studio config exports
└── screenshots/                 # (Placeholder) Portal screenshots, metrics
```

> **Note:** `architecture/`, `scripts/`, `chaos-studio/` now contain verified documentation and scripts based on Azure CLI inventory. `evidence/` and `screenshots/` remain placeholders for future use.

---

## 🔐 Security Note

The file `vmss-t087-chaos-resilience_key.pem` (SSH private key for VMSS access) is **intentionally excluded** from this repository via `.gitignore`. It remains in the original download folder and should be stored securely (Azure Key Vault, password manager, or `~/.ssh/` with restricted permissions).

---

## 📄 License

**License TBD** — Copyright ownership and licensing terms need to be confirmed by the team/organization before a `LICENSE` file is added.

---

## 📌 Next Steps (Post-Hackathon)

- [ ] Codify infrastructure as Bicep/Terraform for reproducible deployments
- [ ] Resolve Azure Policy conflict to enable Chaos Studio zone-down experiment
- [ ] Run continuous load tests (k6/locust) with latency percentile tracking
- [ ] Add Application Insights / Azure Monitor dashboards for observability
- [ ] Document runbooks for common failure scenarios
- [ ] Choose and add an appropriate open-source license

---

*Built for the Azure Resilience Engineering Hackathon — Team T087*