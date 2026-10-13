# Security Guidelines

> **Purpose:** Define security practices for this repository to prevent credential exposure and ensure safe handling of Azure resources.

---

## 🔐 Never Commit These

| Category | Examples | Prevention |
|----------|----------|------------|
| **SSH Private Keys** | `*.pem`, `*.key`, `id_rsa`, `id_ed25519`, `*.ppk` | `.gitignore` excludes all |
| **Azure Credentials** | Service principal secrets, client secrets, certificates | `.gitignore` excludes `*.env`, `secrets/` |
| **Subscription/Resource IDs** | Full resource IDs with subscription IDs in docs/scripts | Use placeholders: `<subscription-id>`, `<resource-group>` |
| **Access Tokens** | Bearer tokens, SAS tokens, PATs | Never hardcode; use Azure CLI auth / Managed Identity |
| **Connection Strings** | Storage, Cosmos DB, SQL, Event Hub | Use Key Vault references |
| **Passwords/Secrets** | Database passwords, API keys, webhook secrets | Use Azure Key Vault / GitHub Secrets |

---

## ✅ Safe Practices

### 1. Authentication
- Use `az login` (interactive) or Managed Identity in Azure environments
- Use GitHub Actions `azure/login` with OIDC federation (no secrets)
- Never store `az` credentials in files

### 2. Documentation
- Replace real subscription IDs with `<subscription-id>` placeholder
- Replace real resource group names in examples with `<resource-group>`
- Sanitize public IPs in examples (use `20.x.x.x` or `<public-ip>`)
- The `architecture/resource-inventory.md` contains real values from inventory — **review before public release**

### 3. Scripts
- All scripts use parameterized resource group/VMSS names
- No hardcoded secrets or credentials
- Scripts are **read-only** or **documented procedures** — no auto-execution

### 4. Private Key Handling
The file `vmss-t087-chaos-resilience_key.pem`:
- **Must never be committed** (excluded by `.gitignore`)
- **Must never be copied** into the repository
- Should be stored in: `~/.ssh/` (chmod 600), Azure Key Vault, or password manager
- If compromised: regenerate key pair immediately in Azure Portal

---

## 🛡️ Repository Security Checklist

Before pushing to any remote:

- [ ] Run `git status` — verify no `*.pem`, `*.key`, `.env`, `secrets/` files staged
- [ ] Run `git diff --staged` — review all staged changes for secrets
- [ ] Search for patterns: `git grep -i "secret\|password\|key\|token" -- "*.md" "*.sh" "*.json"`
- [ ] Verify `.gitignore` includes: `*.pem`, `*.key`, `.env*`, `secrets/`, `*.secret`
- [ ] Confirm no real subscription IDs in documentation (use placeholders)
- [ ] Confirm no real service principal credentials anywhere

---

## 🚨 Incident Response

If a secret is accidentally committed:

1. **Immediately rotate the secret** in Azure (regenerate key, reset password, revoke token)
2. **Remove from Git history** using `git filter-repo` or BFG Repo-Cleaner
3. **Force push** cleaned history: `git push --force`
4. **Notify team** and security contacts
5. **Audit** for any unauthorized access during exposure window

---

## 📋 Azure-Specific Guidance

### RBAC
- Use least-privilege roles: **Reader** for verification scripts, **Contributor** only for deployment
- Avoid **Owner** except for subscription administrators
- Use **Custom Roles** for specific permissions (e.g., "VMSS Instance Operator")

### Network Security
- NSG rules: restrict source IPs where possible (current rule allows `*` for hackathon simplicity)
- Consider **Private Endpoints** for PaaS services
- Enable **DDoS Protection** for production workloads

### Monitoring
- Enable **Microsoft Defender for Cloud** on subscription
- Configure **Activity Log alerts** for sensitive operations (VMSS deallocate, role assignments)
- Use **Azure Policy** to enforce security baselines

---

## 📞 Contacts

| Role | Contact |
|------|---------|
| Repository Owner | Team T087 |
| Azure Subscription Admin | [Your Azure Admin] |
| Security Team | [Your Org Security] |

---

## 📄 Related Files

- `.gitignore` — Exclusion patterns for secrets and artifacts
- `scripts/verify-instances.sh` — Read-only, parameterized
- `scripts/traffic-test.sh` — Read-only, parameterized
- `scripts/controlled-failure.md` — Procedure only, no auto-execution
- `architecture/resource-inventory.md` — Contains real values; review before public release

---

*Last updated: 2026-10-13*
*Review before each release or public sharing*