# White Paper: FIDO-Centric AGE Key Management for Clan + NixOS

**Status:** Draft plan for implementation  
**Audience:** Operator (Max), future maintainers, security reviewers  
**Scope:** Secrets management for Clan vars + `sops`/`sops-nix` in a multi-host NixOS fleet

---

## 1) Executive Summary

This document proposes a **hybrid key model** that uses **FIDO-backed AGE identities for operator access** and **per-machine AGE identities for runtime decryption**.

This preserves the operational requirement that hosts can decrypt required secrets non-interactively during activation/boot, while eliminating the current risk of sharing one operator private key file across multiple devices.

### Core outcomes

- Operator access is hardware-backed (portable, phishing-resistant, non-exportable private material).
- Hosts retain autonomous non-interactive secret decryption.
- Deployments can be initiated from any workstation that has:
  - access to repo,
  - `age` + FIDO AGE plugin,
  - the operator FIDO token.

---

## 2) Problem Statement

Current pain points:

1. **Shared operator key material** copied to multiple machines increases compromise blast radius.
2. Bootstrapping currently distributes plaintext SOPS key files broadly.
3. Operational simplicity and security are in tension when one key model serves both humans and hosts.

Design requirement:

- Keep deployments easy (`clan vars` + `nixos-rebuild`) from any operator endpoint,
- while reducing lateral movement risk from workstation compromise.

---

## 3) Security Objectives and Non-Objectives

### Objectives

1. Use FIDO as **primary operator authentication source** for secret decryption operations.
2. Ensure each machine can decrypt only what it needs at runtime.
3. Keep emergency recovery feasible if operator token is unavailable.
4. Maintain compatibility with Clan vars and existing NixOS module structure.
5. Preserve reproducible + auditable secret recipient state in Git.

### Non-objectives

1. FIDO-only runtime decryption on unattended servers (not practical).
2. Eliminating machine-local runtime secrets entirely (infeasible for autonomous boot/activation).

---

## 4) Threat Model (Practical)

### In-scope threats

- Stolen/lost laptop with copied operator key file.
- Malware on one operator machine exfiltrating disk-resident key files.
- Overly broad decrypt capability due to single shared private key.
- Bootstrap media compromise exposing reusable key material.

### Out-of-scope (partially mitigated)

- Full root compromise on a target host (host can access secrets intended for it).
- Hardware token theft with PIN/physical bypass.

---

## 5) Proposed Cryptographic Access Model

## 5.1 Identity classes

1. **Operator identities (human)**
   - FIDO-backed AGE recipients (1 primary token + 1 backup token recommended).
   - Used for `clan vars get/check/set`, secret editing, and secret re-encryption.

2. **Machine identities (runtime)**
   - One AGE identity per host.
   - Private key remains only on that host (e.g. `/var/lib/sops-nix/key.txt` or equivalent).
   - Used by `sops-nix` during activation/runtime.

3. **Recovery identity (offline)**
   - Cold/offline recipient for emergency access and rotation events.

## 5.2 Recipient policy (mandatory)

Every encrypted secret must include recipients from all required classes:

- Required machine recipient(s) for runtime consumers.
- At least one operator FIDO recipient.
- One recovery recipient.

This avoids lockout and enforces both operability and resilience.

---

## 6) Integration with Clan + NixOS

## 6.1 Clan vars compatibility

Clan vars uses SOPS/AGE decryption pathways. A decrypt succeeds if local environment can satisfy a recipient in the file.

Therefore:

- On operator workstation: decrypt via FIDO-backed operator identity.
- On host: decrypt via host-local machine key.

No conceptual conflict exists with Clan; this is a recipient-management policy and key-loading strategy.

## 6.2 NixOS / sops-nix compatibility

`sops-nix` on each machine continues to consume machine-local key material for non-interactive decryption.

No runtime dependency on user touch/PIN should be introduced for normal host activation.

## 6.3 Deployment flow compatibility

`just switch <target>` and similar workflows remain compatible when preflight scripts:

- stop hardcoding file-key-only assumptions,
- support FIDO identity loading (plugin identity source),
- preserve env for `clan vars` + `nixos-rebuild` invocation.

---

## 7) User Experience: How Max Interacts with the System

## 7.1 Day-to-day operations

From any trusted workstation:

1. Insert/activate FIDO token.
2. Run existing workflows (e.g. `just switch <target> [--test]`).
3. When secret decrypt is needed, token satisfies operator recipient.
4. Target host activation decrypts runtime secrets using host key.

## 7.2 Bootstrap / new machine

Target behavior:

1. Bootstrap media may be FIDO-gated for payload unlock.
2. Installer generates/imports **host-specific runtime key**.
3. Host recipient is registered in repo metadata if new.
4. **No shared operator private key file is copied** onto host.

## 7.3 Emergency recovery

If FIDO token unavailable:

- Use offline recovery identity to decrypt, rotate operator recipients, and re-establish access.

---

## 8) Migration Plan (Phased, Low Risk)

### Phase 0 — Baseline + audit

- Inventory all current recipients in `vars/**/secret` and `sops/secrets/**`.
- Confirm machine recipient coverage.
- Identify current shared operator key recipient usage.

### Phase 1 — Introduce new operator + recovery recipients

- Generate primary and backup FIDO operator recipients.
- Add recovery recipient.
- Re-encrypt secrets to include: machine + operator(FIDO) + recovery.

### Phase 2 — Validate from clean workstation

- On a machine without legacy operator key file:
  - verify `clan vars check/get` succeeds with FIDO token.
  - verify deploy preflight succeeds.

### Phase 3 — Bootstrap hardening

- Remove distribution of `bootstrap-secrets/sops-age-key.txt`.
- Replace with host-key generation/import flow only.
- Ensure host key placement and permissions are correct for `sops-nix` runtime.

### Phase 4 — Remove legacy shared operator recipient

- Re-encrypt all secrets to remove old shared operator key recipient.
- Validate deploy from at least two operator workstations.

### Phase 5 — Runbook + policy enforcement

- Add `just` checks/lints for required recipient classes.
- Document token loss rotation steps.
- Schedule periodic recovery drill.

---

## 9) Operational Controls and Guardrails

1. **Recipient linting:** CI or `just` command verifies each secret includes required classes.
2. **Dual-token operator model:** primary + backup FIDO tokens.
3. **Recovery drills:** test offline recovery path quarterly.
4. **Least privilege:** per-secret recipient scoping where practical (not every machine needs every secret).
5. **Rotation readiness:** scripted recipient rotation for operator token replacement.

---

## 10) Data Classification Guidance (Recommended)

- **Global shared secrets:** include only machines/services that consume them + operator + recovery.
- **Per-machine secrets:** include that machine + operator + recovery.
- **High-sensitivity admin secrets:** consider tighter machine scope or operator-only where runtime not needed.

---

## 11) Concrete Repo Integration Targets

Planned integration touchpoints:

1. `justfile`
   - Add identity resolution abstraction (file key vs FIDO plugin identity).
   - Keep `switch --test` / `switch` UX stable.
   - Add `check-sops-access` and recipient-lint recipes.

2. Bootstrap scripts (`scripts/bootstrap-write-flash.sh`, installer logic)
   - Remove shared operator key injection into payload/host.
   - Keep FIDO-gated install UX.
   - Add host runtime key provisioning path.

3. Secret metadata / recipient management
   - Update recipients in `vars/**/secret` and `sops/secrets/**`.
   - Maintain machine key metadata in `sops/machines/*/key.json`.

4. Documentation
   - Add runbooks:
     - new workstation setup,
     - new host bootstrap,
     - lost FIDO token recovery/rotation.

---

## 12) Acceptance Criteria

Migration is considered complete when all are true:

1. No shared operator private key file is required across workstations.
2. Deploy from two independent workstations succeeds with only FIDO operator token.
3. Host runtime decrypt works non-interactively after reboot/activation.
4. Bootstrap process does not install shared operator key to hosts.
5. Legacy shared operator recipient removed from all encrypted secrets.
6. Recovery runbook tested and documented.

---

## 13) Risks and Mitigations

- **Risk:** Token loss causes temporary operator lockout.  
  **Mitigation:** backup token + offline recovery recipient + tested rotation playbook.

- **Risk:** Incomplete recipient migration breaks decryption in edge cases.  
  **Mitigation:** phased rollout + automated recipient lint + test on representative hosts.

- **Risk:** Bootstrap transition interrupts install workflow.  
  **Mitigation:** maintain backward-compatible bootstrap mode during migration window.

---

## 14) Recommended Next Steps

1. Approve this architecture.
2. Implement Phase 0 audit script + recipient report.
3. Add FIDO primary/backup + recovery recipients.
4. Re-encrypt secrets in staged batches.
5. Patch bootstrap + just workflows.
6. Remove legacy shared operator key path.

---

## Appendix A — Conceptual Access Matrix

- Operator workstation + FIDO token: can decrypt/edit secrets (operator recipient).
- Target host at runtime: can decrypt only secrets addressed to its machine recipient.
- Compromised single workstation without token: cannot decrypt operator-protected secrets.
- Compromised single host: exposes only host-addressed runtime secrets.

---

## Appendix B — Terminology

- **AGE recipient:** public identifier used to encrypt data.
- **AGE identity:** private key material (or hardware-backed source) used to decrypt.
- **Operator identity:** human-controlled key path for admin operations.
- **Machine identity:** host-controlled key path for runtime operations.
- **Recovery identity:** offline emergency decrypt capability.
