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
# Edit terraform.tfvars with your Hetzner API token

terraform init
terraform apply
```

### 2. Access the Cluster

```bash
export KUBECONFIG=$(pwd)/terraform/kubeconfig
kubectl get nodes
```

### 3. Configure ArgoCD

```bash
# Get ArgoCD admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d

# Port forward to access UI
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Update the Git repo URL in applicationset.yaml
# Then apply:
kubectl apply -f argocd/applicationset.yaml
```

### 4. Add Validators

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

## Requirements

- Terraform >= 1.0
- Hetzner Cloud API token
- kubectl
- Git
