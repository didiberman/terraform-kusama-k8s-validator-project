# Kusama Validator Platform

A GitOps-driven platform for dynamically scaling Kusama validators on Hetzner Cloud.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Git Repository                            │
│  validators/                                                 │
│  ├── validator-001.yaml  ← Add file = new validator         │
│  ├── validator-002.yaml                                      │
│  └── validator-003.yaml  ← Delete file = remove validator   │
├─────────────────────────────────────────────────────────────┤
│              ArgoCD ApplicationSet                          │
│              (Auto-generates apps from Git)                  │
├─────────────────────────────────────────────────────────────┤
│              K3s Cluster (Hetzner Cloud)                     │
│              fsn1 | nbg1 | hel1 (multi-geo)                 │
└─────────────────────────────────────────────────────────────┘
```

## Features

- **Dynamic Scaling**: Add/remove validators by editing Git
- **Multi-Geo**: Spread across Falkenstein, Nuremberg, Helsinki
- **Auto Key Generation**: Session keys generated on deployment
- **GitOps**: ArgoCD syncs from Git automatically

## Quick Start

### 1. Provision Infrastructure

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars:
# - Add hcloud_token
# - Set allowed_ips (Recommended)
# - Set initial_workers_per_location (Optional)

terraform init
terraform apply
```

### 2. Bootstrap Secrets (Securely)

Instead of storing secrets in Git, inject them directly into the cluster:

```bash
# Usage: ./scripts/bootstrap-secrets.sh <hcloud-token> <grafana-password>
./scripts/bootstrap-secrets.sh "YOUR_HETZNER_TOKEN" "strong-password-123"
```

### 3. Access the Cluster

```bash
export KUBECONFIG=$(pwd)/terraform/kubeconfig
kubectl get nodes
```

### 4. Configure ArgoCD

```bash
# Get ArgoCD admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d

# Port forward to access UI
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Update the Git repo URL in applicationset.yaml
# Then apply:
kubectl apply -f argocd/applicationset.yaml

# Enable Autoscaling (Optional but Recommended)
kubectl apply -f argocd/hetzner-autoscaler.yaml
```

### 5. Add Validators

**Single validator:**
```bash
./scripts/generate-validator.sh validator-001
# Edit validators/validator-001.yaml with your accounts
git add validators/validator-001.yaml
git commit -m "Add validator-001"
git push
```

**Batch (e.g., 20 validators):**
```bash
./scripts/batch-generate-validators.sh 20
# Edit accounts via CSV:
# validator-001,STASH_ADDR,CONTROLLER_ADDR
./scripts/update-accounts.sh accounts.csv
git add validators/
git commit -m "Add 20 validators"
git push
```

### 5. Get Session Keys

After ArgoCD deploys the validator, check the keygen job logs:

```bash
kubectl logs -n validators job/validator-001-keygen
```

Then submit `session.setKeys(keys, 0x)` from your controller account on [polkadot.js](https://polkadot.js.org/apps).

## Project Structure

```
├── terraform/              # K3s cluster on Hetzner
│   ├── main.tf
│   ├── variables.tf
│   └── templates/          # Cloud-init scripts
├── charts/
│   └── kusama-validator/   # Helm chart
├── argocd/
│   └── applicationset.yaml # Dynamic validator generator
├── validators/             # Validator configs (GitOps)
│   └── example.yaml
└── scripts/                # Helper scripts
    ├── generate-validator.sh
    ├── batch-generate-validators.sh
    ├── update-accounts.sh
    └── rotate-keys.sh
```

## Scaling

| Action | Command |
|--------|---------|
| Add 1 validator | `./scripts/generate-validator.sh validator-XXX` |
| Add N validators | `./scripts/batch-generate-validators.sh N` |
| Remove validator | `git rm validators/validator-XXX.yaml && git push` |
| Rotate keys | `./scripts/rotate-keys.sh validator-XXX` |

## Fast Sync Options

### Warp Sync (Default - Recommended)

Validators use **warp sync** by default, which syncs in ~10 minutes instead of days:

```yaml
# In values.yaml or validator config
sync:
  mode: warp  # Options: warp, fast, full
```

**How it works:**
1. Downloads GRANDPA finality proofs (not all blocks)
2. Fetches latest state directly
3. Validator ready in minutes

### Snapshot Restore (Optional)

For even faster startup, pre-download a database snapshot:

```yaml
sync:
  mode: warp
  snapshot:
    enabled: true
    url: "https://ksm-rocksdb.polkashots.io/snapshot"
    compression: lz4
```

**Snapshot providers:**
- [polkashots.io](https://polkashots.io) - Daily snapshots
- [stakeworld.io](https://stakeworld.io/docs/snapshots) - Fast mirrors

**How it works:**
1. Init container downloads snapshot before validator starts
2. Extracts to `/data` volume
3. Validator starts with pre-synced database
4. Skips download if database already exists

## Session Key Generation

Keys are automatically generated when a validator is deployed:

```
┌─────────────────────────────────────────────────────────────┐
│  1. ArgoCD deploys validator StatefulSet                    │
│  2. Validator syncs (warp sync ~10 min)                     │
│  3. PostSync Job waits for RPC ready                        │
│  4. Job calls author_rotateKeys()                           │
│  5. Keys printed to logs                                    │
│  6. YOU submit session.setKeys() on-chain                   │
└─────────────────────────────────────────────────────────────┘
```

**View generated keys:**
```bash
kubectl logs -n validators job/validator-001-keygen
```

**Submit keys on-chain:**
1. Go to [polkadot.js](https://polkadot.js.org/apps)
2. Connect to Kusama/Westend
3. Developer → Extrinsics
4. Select your **controller** account
5. Submit: `session.setKeys(keys, 0x)`

## Version Upgrades

### Upgrade All Validators

Update the image tag in `charts/kusama-validator/values.yaml`:

```yaml
image:
  repository: parity/polkadot
  tag: v1.7.0  # New version
```

Then push to Git:
```bash
git add charts/kusama-validator/values.yaml
git commit -m "Upgrade polkadot to v1.7.0"
git push
# ArgoCD will rolling-update all validators
```

### Check Available Versions
```bash
# View releases
curl -s https://api.github.com/repos/paritytech/polkadot-sdk/releases | jq '.[].tag_name' | head -10
```

### Rolling Update Strategy

ArgoCD performs rolling updates by default:
1. New validator pod starts with new version
2. Waits for it to be healthy
3. Terminates old pod
4. Repeats for each validator

> ⚠️ **Important**: For critical runtime upgrades, update validators **before** the on-chain upgrade deadline!

## Observability

### Deploy Monitoring Stack

```bash
kubectl apply -f argocd/monitoring.yaml
kubectl apply -f argocd/alerts.yaml
```

This deploys:
- **Prometheus** - Metrics collection
- **Grafana** - Dashboards (pre-loaded with Polkadot dashboard)
- **Alertmanager** - Alert routing

### Access Grafana

```bash
# Port forward
kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80

# Open http://localhost:3000
# Default: admin / admin
```

### Key Metrics

| Metric | Description |
|--------|-------------|
| `substrate_block_height` | Current block height |
| `substrate_sub_libp2p_peers_count` | Connected peers |
| `substrate_sub_libp2p_is_major_syncing` | Sync status |
| `substrate_proposer_block_constructed_count` | Blocks produced |

### Alerts Configured

| Alert | Severity | Condition |
|-------|----------|-----------|
| `ValidatorDown` | Critical | No metrics for 5 min |
| `ValidatorNotSynced` | Warning | Syncing > 15 min |
| `LowPeerCount` | Warning | < 10 peers |
| `DiskSpaceLow` | Critical | < 10% disk free |

### Configure Notifications

Edit `argocd/monitoring.yaml` to add Slack/PagerDuty:

```yaml
alertmanager:
  config:
    receivers:
      - name: 'slack'
        slack_configs:
          - api_url: 'https://hooks.slack.com/...'
            channel: '#validator-alerts'
```

## Security

| Feature | Details | Action Required |
|---------|---------|-----------------|
| **Firewall** | SSH/API restricted to whitelisted IPs | Set `allowed_ips` in `terraform.tfvars` |
| **Secrets** | Grafana/ArgoCD credentials encrypted | Use Sealed Secrets or K8s Secrets |
| **Keys** | Validator keys stored in persistent PVC | Automatic (managed by StatefulSet) |
| **RPC** | Unsafe RPC blocked from internet | Internal access only (ClusterIP) |

### Restrict Access (Recommended)

In `terraform.tfvars`:
```hcl
allowed_ips = ["YOUR_OFFICE_IP/32", "YOUR_HOME_IP/32"]
```

## Scaling Infrastructure

### Initial Scale (Day 1)

Define initial capacity in `terraform.tfvars`:

```hcl
# Start with 2 workers per location (Total: 6 workers + 1 CP)
initial_workers_per_location = 2
```

### Auto-Scaling (Day 2+)

The cluster automatically provisions new nodes when you add more validators than current capacity allows.

1. **Enable Autoscaler:**
   ```bash
   kubectl apply -f argocd/hetzner-autoscaler.yaml
   ```
2. **Add Validators:**
   ```bash
   ./scripts/batch-generate-validators.sh 10
   git push
   ```
3. **Watch it scale:**
   - Pods go `Pending`
   - Autoscaler detects pending pods
   - Provisions new Hetzner servers
   - Pods start automatically

## Requirements

- Terraform >= 1.0
- Hetzner Cloud API token
- kubectl
- Git
