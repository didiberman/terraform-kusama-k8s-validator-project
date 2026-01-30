# Kusama Validator Platform

A GitOps-driven platform for dynamically scaling Kusama validators on Hetzner Cloud.

## Architecture

- **Infrastructure**: K3s cluster on Hetzner Cloud (multi-geo: fsn1, nbg1, hel1)
- **Orchestration**: ArgoCD with ApplicationSet for dynamic validator scaling
- **Secrets**: Sealed Secrets (encrypted secrets in Git)
- **Scaling**: Add/remove validators by adding/removing YAML files

## Quick Start

```bash
# 1. Provision infrastructure
cd terraform
terraform init
terraform apply

# 2. Access the cluster
export KUBECONFIG=$(terraform output -raw kubeconfig_path)
kubectl get nodes

# 3. Add a validator
cp validators/example.yaml validators/validator-001.yaml
# Edit with your stash account
git add validators/validator-001.yaml
git commit -m "Add validator-001"
git push
# ArgoCD will automatically deploy it
```

## Project Structure

```
├── terraform/          # K3s cluster provisioning
├── charts/             # Helm charts
│   └── kusama-validator/
├── argocd/             # ArgoCD ApplicationSet config
├── validators/         # Validator configurations (GitOps)
└── scripts/            # Helper scripts
```

## Prerequisites

- Terraform >= 1.0
- Hetzner Cloud account + API token
- kubectl
- kubeseal (for Sealed Secrets)
