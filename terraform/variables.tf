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
