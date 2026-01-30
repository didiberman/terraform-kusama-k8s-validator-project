# Hetzner API Token
variable "hcloud_token" {
  type        = string
  description = "Hetzner Cloud API token"
  sensitive   = true
}

# Cluster Configuration
variable "cluster_name" {
  type        = string
  description = "Name of the K3s cluster"
  default     = "kusama-validators"
}

variable "locations" {
  type        = list(string)
  description = "Hetzner datacenter locations for multi-geo deployment"
  default     = ["fsn1", "nbg1", "hel1"]
}

variable "initial_workers_per_location" {
  type        = number
  description = "Number of initial worker nodes to provision per location"
  default     = 1
}

# Server Types
variable "control_plane_server_type" {
  type        = string
  description = "Hetzner server type for control plane"
  default     = "cpx21" # 3 vCPU, 4GB RAM - sufficient for K3s control plane
}

variable "worker_server_type" {
  type        = string
  description = "Hetzner server type for worker nodes"
  default     = "cpx41" # 8 vCPU, 16GB RAM - good for validators
}

# K3s Options
variable "taint_control_plane" {
  type        = bool
  description = "Taint control plane to prevent workloads (recommended)"
  default     = true
}

variable "allowed_ips" {
  type        = list(string)
  description = "List of CIDRs allowed to access SSH and K8s API"
  default     = ["0.0.0.0/0"]
}
