# Deep Study Guide: Kusama Validator Platform (Gemini 3 Pro Edition)

> **Date:** 2026-01-31
> **Audience:** DevOps Engineer / Student
> **Goal:** Deeply understand every "ingredient" used to build this platform.
> **Philosophy:** GitOps-driven, Immutable Infrastructure, Security-first.

---

## 🏗️ 1. The Foundation: Infrastructure as Code (Terraform)

**Concept:** "Infrastructure as Code" (IaC) means we define *what* we want (servers, networks) in text files, not by clicking buttons in a web console.

### The Ingredients:
*   **Hetzner Cloud (`hcloud` provider):** We use Hetzner for its cost-performance ratio.
*   **Private Networking (RFC1918):** Security through isolation.
*   **Cloud-Init (`user_data`):** Boot-time configuration.

### How it works deeply (`terraform/`):
1.  **Network Segmentation:** In `terraform/main.tf`, we create a `hcloud_network` (10.0.0.0/8).
    *   *Why?* Validators gossip over the public internet (P2P), but we don't want their metrics, logs, or SSH ports exposed. We keep that traffic on the private LAN.
    *   Each location (fsn1, nbg1) gets a `/16` subnet (e.g., 10.1.0.0/16). This makes IP addressing **deterministic**. You look at an IP `10.2.x.x` and instantly know "That's Nuremberg".
2.  **Firewalling (The First Wall):** `hcloud_firewall` hardens the outer shell.
    *   It drops *everything* except P2P (30333).
    *   SSH (22) and K8s API (6443) are whitelisted to `var.allowed_ips`.
3.  **The "Cattle" Philosophy:** We use `random_password` for the K3s token and generate SSH keys on the fly (`tls_private_key`).
    *   *Lesson:* Never hardcode secrets. Terraform State holds the secret, and we output the private key locally. If you lose the folder, you lose access (which is secure, if inconvenient).
4.  **Bootstrapping (The "Magic" Link):** The `local-exec` provisioner waits 120s and then SSHs into the new machine to steal the `kubeconfig`.
    *   *Why?* This bridges the gap between "I have a server" and "I can talk to Kubernetes". It automates the "day 0" login.

---

## ⚓ 2. The Runtime: Kubernetes & K3s

**Concept:** Container Orchestration. We stop managing "servers" and start managing "resources" (CPU/RAM).

### The Ingredients:
*   **K3s:** A CNCF-certified lightweight Kubernetes distribution.
*   **Hetzner CCM (Cloud Controller Manager):** The translation layer.
*   **CSI (Container Storage Interface):** The disk manager.

### How it works deeply:
1.  **Lightweight Distro:** K3s is a single binary. It reduces overhead on these small validator nodes so more RAM goes to the blockchain stats.
2.  **Topology Awareness:** Notice `templates/worker.sh.tpl`. We label nodes with `topology.kubernetes.io/zone=${location}`.
    *   *Why?* So Kubernetes knows that `worker-fsn1` is physically in Falkenstein. We can later use "Anti-Affinity" to say "Don't put two validators in the same data center".
3.  **The Cloud Controller Logic:**
    *   Normally, K8s doesn't know it's on Hetzner. The CCM (installed in cloud-init) teaches K8s: "Hey, that LoadBalancer request? Talk to the Hetzner API to create a Floating IP."
    *   The CSI driver allows us to say `volumeClaimTemplates` (give me 500GB) and it automatically provisions a Hetzner Cloud Volume and attaches it to the server.

---

## 🔄 3. The GitOps Engine: ArgoCD

**Concept:** "Git is the Source of Truth." If it's not in Git, it doesn't exist.

### The Ingredients:
*   **ArgoCD:** A controller that constantly compares *Live State* (Cluster) vs *Desired State* (Git).
*   **ApplicationSet:** The "Factory" for Applications.

### How it works deeply (`argocd/applicationset.yaml`):
This is the most powerful part of the stack. Instead of creating 50 ArgoCD Applications manually, we define a **Generator**.

1.  **The Generator:** It looks at the Git repo `validators/*.yaml`.
2.  **The Templating:** For *every* file it finds (e.g., `validators/validator-01.yaml`), it renders a full ArgoCD Application.
3.  **The Parameters:** It extracts fields like `{{stashAccount}}` from the file and injects them as **Helm Values**.

**The Workflow:**
*   **You:** Create `validators/val-99.yaml`. Commit. Push.
*   **Argo:** "I see a file!" -> Generates App `validator-val-99`.
*   **Argo:** Syncs Helm Chart.
*   **K8s:** Spins up Pods.
*   **Result:** You scaled your infrastructure just by adding a text file. No `kubectl apply`. No manual scripts.

---

## 📦 4. The Workload: Managing State (StatefulSets)

**Concept:** Validators are **Stateful**. They have an identity (Session Keys) and History (Block Database).

### The Ingredients:
*   **StatefulSet:** Guarantees pod ordering (`val-0`) and stable storage.
*   **InitContainers:** Tasks that run *before* the main app starts.

### How it works deeply (`charts/kusama-validator/`):
1.  **Identity Persistence:**
    *   A Deployment creates random pods (`val-xf9s2`). A StatefulSet creates predictable ones (`val-0`).
    *   If `val-0` crashes, K8s ensures the replacement is also named `val-0` and **reattaches the same Disk**.
    *   *Critical:* Your Session Keys (crypto secrets proving who you are) live on that disk. If you lose the disk, you get slashed (penalized).
2.  **The "Fast Sync" Trick (`initContainer: snapshot-restore`):**
    *   Syncing Kusama from genesis (block 0) takes days.
    *   The `initContainer` runs `curl` to download a compressed snapshot (e.g., from Polkashots) *before* the validator starts.
    *   This reduces "time-to-online" from days to minutes.
3.  **Key Generation (`keygen-job.yaml`):**
    *   This is an ArgoCD **Hook**. It runs *after* the sync (`PostSync`).
    *   It talks to the Validator's RPC port to say "Generate new keys".
    *   It prints them to the logs so you can register them on-chain.

---

## 🔐 5. Security & Secrets

**Concept:** "The Secret Zero Problem." How do we get the first secret into the cluster securely?

### The Ingredients:
*   **Bootstrap Script (`scripts/bootstrap-secrets.sh`):** Imperative injection.
*   **Network Policies:** Zero-trust inside the cluster.

### How it works deeply:
1.  **Why not Git?** We cannot commit the Hetzner API Token or Grafana Password to Git (public repo!).
2.  **The Bootstrapping:** We use a shell script to `kubectl create secret`. This is the one non-GitOps step.
    *   *Advanced Upgrade:* In a team setting, use **SealedSecrets** or **ExternalSecrets** (Vault/AWS ASM) so even this can be in Git (encrypted).
3.  **Blast Radius Reduction:**
    *   `templates/networkpolicy.yaml` blocks all traffic by default.
    *   It only allows traffic into the exact ports needed (9933 RPC, 30333 P2P, 9615 Metrics).
    *   If a hacker compromises one pod, they cannot scan the rest of the internal network because K3s (via Traefik/Cilium) drops the packets.

---

## 📊 6. Observability

**Concept:** "You can't manage what you can't measure."

### The Ingredients:
*   **Prometheus:** The time-series database.
*   **ServiceMonitor:** The "glue" logic.

### How it works deeply:
1.  **Auto-Discovery:**
    *   Standard Prometheus requires static config ("scrape 10.1.1.5").
    *   In K8s, pods move. The **ServiceMonitor** resource (`templates/servicemonitor.yaml`) tells the Prometheus Operator:
        > "Look for any Service with label `app=kusama-validator`. If found, scrape port `9615` every 15s."
2.  **Visualization:**
    *   We use a ConfigMap to inject the Grafana Dashboard JSON code.
    *   This means your monitoring dashboards are version controlled just like your code.

---

## 🎓 Summary for the Student

You have built a system that demonstrates the **Modern DevOps Maturity Model**:

1.  **Level 1 (Scripting):** You moved past this. (No manual `apt-get install`).
2.  **Level 2 (IaC):** You used Terraform to own the hardware.
3.  **Level 3 (Orchestration):** You used K8s to own the processes.
4.  **Level 4 (GitOps):** You used ArgoCD so Git is the controller.

**Study Tasks for You:**
1.  **Chaos Engineering:** Delete a validator pod manually (`kubectl delete pod`). Watch the StatefulSet recreate it. Check if it attached the same disk (it should).
2.  **Disaster Recovery:** Delete the entire workspace and run `terraform apply` again. See how fast you can restore full service.
3.  **Security Audit:** Try to SSH into a worker node from a public IP (should fail). Try to curl the RPC port from a different namespace (should fail).

Good luck with your DevOps journey!
