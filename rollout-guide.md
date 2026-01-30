# Rollout Guide: From Zero to Validating

This guide provides a narrative walkthrough of deploying the platform. It bridges the gap between the "what" (Study Guide) and the "how" (README).

## Phase 1: The "Hard" Infrastructure (Terrraform)
**Time Estimate:** ~10 minutes
**Role:** Infrastructure Engineer

Your journey begins with provisioning the physical servers and networks.

1.  **Credentials**: You grab your Hetzner Cloud API Token.
2.  **Configuration**:
    *   You copy `terraform.tfvars.example` to `terraform.tfvars`.
    *   You set `locations = ["fsn1", "nbg1", "hel1"]` to ensure your cluster is distributed across Germany and Finland.
    *   You strictly set `allowed_ips` to your own IP address to lock down SSH access.
3.  **Ignition**:
    *   You run `terraform init` to download the Hetzner providers.
    *   You run `terraform apply`.
    *   **What you see:** Terraform creates a private network, a firewall, an SSH key, 1 Control Plane server, and 3 Worker nodes (one in each city).

## Phase 2: The "Soft" Infrastructure (Bootstrap)
**Time Estimate:** ~5 minutes (Automatic)
**Role:** Observer

Once Terraform finishes, you don't need to SSH into the servers. The `cloud-init` scripts are running automatically in the background.

1.  **The Wait**: You grab a coffee.
2.  **Behind the Scenes**:
    *   The servers wake up and install K3s.
    *   They join the cluster.
    *   The Cloud Controller Manager (CCM) detects it's running on Hetzner and auto-configures the network topology.
    *   ArgoCD installs itself.
3.  **Verification**:
    *   You export the kubeconfig: `export KUBECONFIG=$(pwd)/terraform/kubeconfig`
    *   You run `kubectl get nodes`. You see all nodes `Ready`.

## Phase 3: The "GitOps" Engine (ArgoCD)
**Time Estimate:** ~5 minutes
**Role:** Platform Admin

Now you connect the "Engine" (ArgoCD) to your "Steering Wheel" (Git Repo).

1.  **Secrets Injection**:
    *   You run `./scripts/bootstrap-secrets.sh "YOUR_TOKEN" "GRAFANA_PASSWORD"`.
    *   This securely injects your Hetzner token into the cluster so the CSI driver can buy disks later.
2.  **Unlock ArgoCD**:
    *   You retrieve the initial password via `kubectl`.
    *   You login to the ArgoCD UI (port-forwarded to localhost:8080).
3.  **Start the Engine**:
    *   You verify the `argocd/applicationset.yaml` points to *your* GitHub clone.
    *   You run `kubectl apply -f argocd/applicationset.yaml`.
    *   **What you see:** ArgoCD scans your `validators/` folder (currently empty) and waits.

## Phase 4: Validator Launch (The Daily Workflow)
**Time Estimate:** ~2 minutes active, ~15 minutes wait
**Role:** Validator Operator

This is where you live day-to-day. You want to launch a new validator named "Alice".

1.  **Generate Config**:
    *   You run `./scripts/generate-validator.sh alice`.
    *   A file `validators/alice.yaml` appears.
2.  **Push to Launch**:
    *   You `git add .`, `git commit -m "Add Alice"`, and `git push`.
3.  **The Magic**:
    *   ArgoCD detects the commit.
    *   **Kubernetes** helps scheduling: It finds a node in Helsinki that doesn't have a validator yet.
    *   **CSI Driver** helps storage: It provisions a 500GB SSD from Hetzner and mounts it.
    *   **Pod** starts: Alice boots up using "Warp Sync".
4.  **Key Rotation**:
    *   A few minutes later, you check logs: `kubectl logs job/alice-keygen`.
    *   You copy the session keys and submit them on Polkadot.js.

## Phase 5: Disaster Recovery (The "Oh No" Moment)
**Scenario:** The data center in Nuremberg fires.

1.  **Detection**: Your grafana dashboard alerts you.
2.  **Response**:
    *   Kubernetes marks the Nuremberg node as `NotReady`.
    *   The Validator Pod is rescheduled to a healthy node (e.g., in Falkenstein).
    *   The persistent volume is detached from the dead node and re-attached to the new one (if using centralized storage) OR the validator resyncs from scratch on local storage (if using local-path). *Note: This project defaults to Hetzner CSI, so volumes follow the pod.*
3.  **Outcome**: Downtime is minimized, slashing is avoided.
