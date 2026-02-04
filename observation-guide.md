# How to Monitor Your First Validator Deployment

Follow these steps in separate terminal windows to watch the "GitOps Magic" happen in real-time.

### 1. Watch ArgoCD detect the change (The "Brain")
ArgoCD's ApplicationSet controller is responsible for seeing your new file and creating the Application resource.
```bash
# Terminal 1
export KUBECONFIG=./terraform/kubeconfig
kubectl logs -f -n argocd -l app.kubernetes.io/name=argocd-applicationset-controller
```
*Look for: "Generating application from git..."*

### 2. Watch the Application Sync (The "Action")
Once the Application is created, it will show up in the `argocd` namespace. You can watch its status:
```bash
# Terminal 2
export KUBECONFIG=./terraform/kubeconfig
kubectl get applications -n argocd -w
```
*Look for: `validator-validator-001` status changing from `OutOfSync` to `Synced`.*

### 3. Watch the Pod & PV Creation (The "Physical")
This is where the actual validator starts. It will first wait for a PersistentVolume (the 500GB disk) to be created by Hetzner.
```bash
# Terminal 3
export KUBECONFIG=./terraform/kubeconfig
kubectl get pods -n validators -w
```
*Look for: `validator-001-0` moving from `Pending` -> `ContainerCreating` -> `Running`.*

### 4. Tail the Validator Logs (The "Content")
Once the status is `Running`, you can see the Polkadot/Kusama binary starting up and syncing blocks:
```bash
# Terminal 4
export KUBECONFIG=./terraform/kubeconfig
kubectl logs -f -n validators -l validator=validator-001
```

### 5. (Optional) The Graphical View
If you want to see the dependency tree visually:
```bash
# Run this, then open http://localhost:8080
kubectl port-forward svc/argocd-server -n argocd 8080:443
```
*Login:* `admin` / `b596hkrirZP1qirL` (from your previous install).
