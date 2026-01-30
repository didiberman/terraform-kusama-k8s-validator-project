# Study Guide: Kusama Validator Platform

This document explains how the Kusama Validator Platform repository is structured, how every layer works, and which DevOps concepts it demonstrates. Work through it from top to bottom to build a complete mental model of the system.

## 1. Mental Model

At a high level you describe *state* ("how many validators do I want?", "where do they run?") in Git and let automation materialise the desired runtime:

1. **Terraform** (`terraform/`) provisions a multi-region Hetzner Cloud VPC, firewall, SSH material, and a K3s cluster (1 control-plane + N workers per location). Cloud-init scripts harden/install core software.
2. **Bootstrap scripts** (`scripts/bootstrap-secrets.sh`) store secrets inside the cluster (Hetzner API token, Grafana admin password) without writing them to Git.
3. **ArgoCD ApplicationSet** (`argocd/applicationset.yaml`) watches `validators/*.yaml`. Each file becomes a Helm release of the validator chart.
4. **Helm chart** (`charts/kusama-validator/`) deploys a StatefulSet with persistent storage, services, session keygen job, network policies, metrics, etc.
5. **Monitoring stack** (Prometheus, Grafana, Alertmanager) + Hetzner cluster-autoscaler are deployed through additional ArgoCD Applications.

Everything is GitOps-driven: Git is the single source of truth. Applying Terraform and ArgoCD manifests once lets automation continuously reconcile reality with Git.

## 2. Infrastructure as Code with Terraform

### 2.1 Providers, secrets, and SSH
- `terraform/main.tf` pins the Hetzner Cloud, Local, and TLS providers along with Terraform >= 1.0.
- A fresh ED25519 SSH keypair (`tls_private_key.ssh` + `hcloud_ssh_key.default`) is generated per deployment so Terraform can later run remote commands.
- The private key is written to `terraform/ssh-key` via the `local_file` resource and reused for SSH/kubeconfig retrieval.
- Inputs are defined in `terraform/variables.tf` and populated through `terraform.tfvars` (copy `terraform.tfvars.example`). Sensitive data like `hcloud_token` is read from your tfvars but never committed.

### 2.2 Networking and firewalls
- `hcloud_network.k3s` builds an RFC1918 `/8` network. For each location (`fsn1`, `nbg1`, `hel1`) `hcloud_network_subnet.k3s` carves out `/16` CIDRs (10.1.0.0/16, etc.), providing deterministic addressing per data center.
- `hcloud_firewall.k3s` applies minimum-ingress rules:
  - SSH (22) and API server (6443) restricted to `var.allowed_ips`.
  - Node-to-node traffic (metrics, Prometheus scrape) stays on the private network.
  - P2P port 30333 is open to the world so validators can gossip blocks.

### 2.3 Compute nodes and scaling baseline
- `hcloud_server.control_plane` pins the K3s control-plane to Ubuntu 22.04 with server-type `cpx21` and user-data script `templates/control-plane.sh.tpl`.
- Worker nodes are declared via a local `worker_nodes` list that multiplies the `locations` array by `initial_workers_per_location`. Each worker uses `templates/worker.sh.tpl`, inherits firewall rules, attaches to the private network, and labels itself with its topology zone.
- Terraform gives you deterministic hostnames like `kusama-validators-worker-fsn1-1`, making debugging easier.

### 2.4 Bootstrap scripts executed by cloud-init
- **Control-plane script** installs:
  - K3s server with optional control-plane tainting to keep workloads off master nodes.
  - Helm CLI.
  - ArgoCD (manifests downloaded from the upstream project).
  - Bitnami Sealed Secrets controller (so you *can* manage encrypted secrets in Git later).
  - Hetzner Cloud Controller Manager (CCM) + CSI driver, enabling Kubernetes LoadBalancer objects, persistent volumes, and topology awareness on Hetzner.
- **Worker script** waits for the control plane, then installs the K3s agent and sets node labels for zonal spreading.

### 2.5 Access outputs
- A `null_resource.kubeconfig` waits 120 seconds, then SSHes into the control-plane and copies `/etc/rancher/k3s/k3s.yaml`, swapping `127.0.0.1` for the public control-plane IP. This file plus the generated SSH key are returned as Terraform outputs so you can `kubectl` immediately after `terraform apply`.

## 3. Base Cluster Services

After the nodes boot:

1. ArgoCD is already installed and reconciling whatever Applications you point it to.
2. Sealed Secrets & the Hetzner CCM ensure cloud-native services like LoadBalancers, volumes, and network routes function.
3. Use `scripts/bootstrap-secrets.sh <HCLOUD_TOKEN> <GRAFANA_PASSWORD>` to create:
   - `kube-system/hetzner-cloud` Secret (CCM + autoscaler need the API token and network name).
   - `monitoring/grafana-admin` Secret (referenced in the monitoring Helm values).

At this point the cluster is ready for GitOps reconciliation via ArgoCD.

## 4. GitOps Flow with ArgoCD ApplicationSet

`argocd/applicationset.yaml` defines the GitOps heart beat:

- **Generator**: `spec.generators.git.files` scans `validators/*.yaml`. Each file exports fields like `name`, `stashAccount`, `controllerAccount`, `chain`, `storageSize`.
- **Template**: for every result, ApplicationSet renders an ArgoCD Application named `validator-<name>` that points to this same repo’s Helm chart.
- **Values wiring**: the Helm `valuesObject` injects the fields from the validator YAML. Any change to a validator file instantly becomes a Helm value override.
- **Automation**: `syncPolicy.automated` enables prune + self-heal. Deleting a validator file removes the Kubernetes objects; editing one triggers a rolling upgrade via StatefulSet.

Command chain for adding/removing validators:
1. Create or edit a YAML file under `validators/` (use helper scripts for scaffolding).
2. Commit & push.
3. ApplicationSet notices the Git diff, (re)generates the Application, and ArgoCD deploys/updates the Helm release.

## 5. Helm Chart Deep Dive

The `charts/kusama-validator` Helm chart abstracts the heavy lifting required to run a performant validator pod.

### 5.1 Values of interest
- `values.yaml` exposes validator metadata, chain, image tag, RPC behavior, telemetry, sync optimizations (warp), resources, PVC sizing, service exposure, key management, scheduling hints, and metrics knobs.
- Each validator YAML overrides the essentials (`validatorName`, `stashAccount`, `controllerAccount`, `chain`, `persistence.size`).

### 5.2 StatefulSet (`templates/statefulset.yaml`)
- StatefulSet ensures stable identity, storage, and ordered updates—ideal for a blockchain node that writes hundreds of GB of data.
- `initContainers`:
  - Optional `snapshot-restore` downloads a Polkashots/Stakeworld database snapshot (LZ4/Gzip) if `sync.snapshot.enabled` is true and no DB exists yet—dramatically reducing sync time.
  - `prepare-keystore` pre-creates the keystore directory when auto-generating session keys.
- Main container arguments configure the Polkadot binary with RPC/WS ports exposed, `--validator`, telemetry, Prometheus endpoint, and warp sync.
- Resources default to 4 CPU/8 Gi requests and 8 CPU/16 Gi limits, ensuring nodes do not starve.
- Two volume mounts reuse the same PVC for chain DB and keystore (with `subPath` for keystore).
- Liveness/readiness HTTP probes hit `/health` on the RPC port to remove stuck pods.

### 5.3 Storage
- `volumeClaimTemplates` allocate a PVC per validator pod (default 500 Gi). Storage class can be overridden for NVMe vs HDD.
- Because StatefulSets keep PVCs even if pods restart, keys and blockchain history persist across upgrades.

### 5.4 Services and NetworkPolicy
- `templates/service.yaml` creates an internal ClusterIP exposing P2P, RPC, WS, and Prometheus ports. Optionally, a NodePort service exposes P2P externally with either fixed or auto-assigned port (required for other peers to dial you).
- `templates/networkpolicy.yaml` enforces zero-trust by default (podSelector: `{}`) and only allows ingress from:
  - Any source on TCP 30333 (P2P traffic).
  - Monitoring namespace on TCP 9615 (metrics).
  - In-namespace pods on RPC/WS ports (9933/9944).

### 5.5 Key Management job
- `templates/keygen-job.yaml` is an ArgoCD `PostSync` hook job that waits for the validator’s RPC health endpoint, then calls `author_rotateKeys`. Keys are printed with detailed next steps so ops can immediately call `session.setKeys` on-chain.
- Job logs are kept for one hour; rerun by redeploying the Application or via the provided `scripts/rotate-keys.sh`.

### 5.6 Monitoring integration
- `templates/servicemonitor.yaml` registers all validator services with the Prometheus Operator (`release: monitoring`). As soon as the monitoring stack is deployed, metrics from every validator get scraped.

## 6. Managing Validator Definitions

Validator definitions live under `validators/` and define *desired state*. Tooling helps keep them consistent:

- `scripts/generate-validator.sh` scaffolds one YAML file with placeholders and metadata.
- `scripts/batch-generate-validators.sh` mass-produces multiple files (e.g., `validator-001`..`validator-020`) with unique placeholders and chain-specific storage defaults.
- `scripts/update-accounts.sh accounts.csv` bulk-updates stash/controller addresses once you have them, ensuring there is no manual copy-paste.

Each file includes:
```yaml
name: validator-001
stashAccount: "5..."
controllerAccount: "5..."
chain: westend
storageSize: "100Gi"
```
These map directly to Helm values, so mistakes here translate immediately into Kubernetes runtime behavior.

## 7. Session Keys and Security Posture

- **Automatic keygen**: With `sessionKeys.autoGenerate: true`, the PostSync job produces fresh keys every deployment. Because the keystore folder sits on the PVC, keys survive pod restarts.
- **Manual rotation**: `scripts/rotate-keys.sh <validator>` execs into the pod, checks sync status, and calls `author_rotateKeys`. This is useful before session key expiry or after suspected compromise.
- **Secrets**: Sensitive cluster secrets (Hetzner API token, Grafana admin password) are injected via `kubectl` (or eventually Sealed Secrets) rather than storing in Git.
- **Firewalls/NetworkPolicies**: Hetzner firewall restricts SSH/API, while Kubernetes NetworkPolicy reduces blast radius within the cluster.
- **Persistent keys**: Because the keystore is on the same PVC as the chain data, losing a pod does not lose the keys. Losing the PVC (e.g., node deletion without data migration) would, so backups or replicating keys offline is advised.

## 8. Scaling Strategy

- **Baseline capacity**: `initial_workers_per_location` gives you capacity headroom per datacenter so pods can be evenly spread.
- **Hetzner Cluster Autoscaler** (`argocd/hetzner-autoscaler.yaml`): deploy this ArgoCD Application to allow automatic node provisioning. It needs the `hetzner-cloud` Secret (HCLOUD_TOKEN + network). Extra args tune downscaling windows and balancing.
- **Node discovery**: `node-group-auto-discovery: hcloud:pool-tag=kusama-validators` expects your worker nodes to be tagged accordingly (Terraform labels already include `cluster = var.cluster_name`). Verify tag alignment before relying on autoscaling.
- **Workflow**: When validators exceed available capacity, pods go Pending → autoscaler adds workers via Hetzner API → K3s adds them to the cluster → ArgoCD retries until pods schedule.

## 9. Observability & Alerting

ArgoCD Application `argocd/monitoring.yaml` installs `kube-prometheus-stack` (Helm chart 55.5.0) with custom values:

- **Prometheus** retains 30 days of data and requests a 50 Gi PVC.
- **Grafana** uses the `grafana-admin` Secret for credentials and automatically loads:
  - Community Polkadot dashboard (gnetId 13840).
  - Custom dashboard defined in `argocd/dashboard-configmap.yaml` (stats on validator up/down, syncing state, block height, peers).
- **ServiceMonitor** (from the Helm chart) plus the chart’s own ServiceMonitor ensure validators are scraped every 15 s.
- **Alertmanager** base config exists and is ready for Slack/PagerDuty receivers. Extend `alertmanager.config.receivers` for notifications.
- **PrometheusRule** (`argocd/alerts.yaml`) defines validator health alerts: syncing too long, down, low peers, no blocks, finality lag, high memory, low disk.

Access Grafana via `kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80` and log in with the secret-managed password.

## 10. Operational Runbooks

### 10.1 Provision / Teardown
1. `cd terraform && terraform init && terraform apply` → infrastructure ready.
2. `export KUBECONFIG=$(pwd)/terraform/kubeconfig` → talk to cluster.
3. Run `scripts/bootstrap-secrets.sh ...`.
4. Apply ArgoCD manifests (`kubectl apply -f argocd/*.yaml` as needed).
5. Manage validators in Git going forward.

Destroying involves `terraform destroy` (after draining validators, removing Git definitions, and deleting PVs if needed).

### 10.2 Add a validator
1. `./scripts/generate-validator.sh validator-010`.
2. Edit stash/controller accounts.
3. Commit/push.
4. Watch `kubectl get pods -n validators`.
5. Check keygen job logs → submit `session.setKeys`.

### 10.3 Remove a validator
1. `git rm validators/validator-010.yaml` + commit/push.
2. ApplicationSet prunes resources; PVC deletion depends on finalizers (StatefulSet removal triggers PVC removal if `Retain` isn’t configured elsewhere).
3. Optionally clean up on-chain exposure.

### 10.4 Upgrade Polkadot binary
1. Update `charts/kusama-validator/values.yaml` default image tag **or** override per validator file.
2. Commit/push.
3. ArgoCD performs a rolling update: new pod starts → becomes ready → old pod terminates.
4. Monitor metrics to ensure sync.

### 10.5 Diagnose issues
- **Pending pods**: check node resources, autoscaler logs, PVC events.
- **Syncing forever**: ensure snapshots/restoring, network connectivity, peers (check metrics + `kubectl exec` health).
- **Keygen job failing**: confirm RPC is reachable, inspect `kubectl logs job/<name>-keygen`.

## 11. Concepts to Study Further

The repository is an applied example of several DevOps pillars:

- **Infrastructure as Code (IaC)**: Terraform describing Hetzner networking, servers, firewalls, secrets.
- **Immutable infrastructure**: Provisioning via cloud-init templates ensures reproducible, cattle-not-pets servers.
- **Kubernetes + K3s**: Lightweight distro, control-plane/worker separation, taints, labels, and scheduling.
- **GitOps & ArgoCD**: ApplicationSet generator, automated sync, hooks, drift correction.
- **Helm packaging**: Values abstraction, templating, initContainers, hooks, lifecycle management.
- **Stateful workloads on Kubernetes**: StatefulSets, PVCs, warp sync, snapshot restores.
- **Security**: Network policies, firewalling, secrets handling, key rotations.
- **Observability**: Prometheus, Grafana, dashboards, alert rules, ServiceMonitor patterns.
- **Autoscaling**: Cluster autoscaler, node auto-discovery tags, balancing multi-geo worker pools.

Use this document alongside the source files to trace how configuration flows from Terraform → Kubernetes → validator pods. Apply the same patterns when building other GitOps-managed infrastructure.
