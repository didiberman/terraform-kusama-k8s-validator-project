# Hetzner K3s Cluster for Kusama Validators

terraform {
  required_version = ">= 1.0"

  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.45"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "hcloud" {
  token = var.hcloud_token
}

# SSH Key for node access
resource "tls_private_key" "ssh" {
  algorithm = "ED25519"
}

resource "hcloud_ssh_key" "default" {
  name       = "${var.cluster_name}-ssh-key"
  public_key = tls_private_key.ssh.public_key_openssh
}

resource "local_file" "ssh_private_key" {
  content         = tls_private_key.ssh.private_key_openssh
  filename        = "${path.module}/ssh-key"
  file_permission = "0600"
}

# Private Network
resource "hcloud_network" "k3s" {
  name     = "${var.cluster_name}-network"
  ip_range = "10.0.0.0/8"
}

resource "hcloud_network_subnet" "k3s" {
  for_each     = toset(var.locations)
  network_id   = hcloud_network.k3s.id
  type         = "cloud"
  network_zone = local.location_zones[each.key]
  ip_range     = local.subnet_cidrs[each.key]
}

locals {
  # Map Hetzner locations to network zones
  location_zones = {
    fsn1 = "eu-central"
    nbg1 = "eu-central"
    hel1 = "eu-central"
  }

  # Subnet CIDRs per location
  subnet_cidrs = {
    fsn1 = "10.1.0.0/16"
    nbg1 = "10.2.0.0/16"
    hel1 = "10.3.0.0/16"
  }
}

# Firewall
resource "hcloud_firewall" "k3s" {
  name = "${var.cluster_name}-firewall"

  # SSH
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = var.allowed_ips
  }

  # Kubernetes API
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "6443"
    source_ips = var.allowed_ips
  }

  # K3s metrics
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "10250"
    source_ips = ["10.0.0.0/8"]
  }

  # P2P for Kusama (libp2p)
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "30333"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  # Prometheus metrics
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "9615"
    source_ips = ["10.0.0.0/8"]
  }
}

# Control Plane Node
resource "hcloud_server" "control_plane" {
  name         = "${var.cluster_name}-control-plane"
  image        = "ubuntu-22.04"
  server_type  = var.control_plane_server_type
  location     = var.locations[0]
  ssh_keys     = [hcloud_ssh_key.default.id]
  firewall_ids = [hcloud_firewall.k3s.id]

  labels = {
    cluster = var.cluster_name
    role    = "control-plane"
  }

  user_data = templatefile("${path.module}/templates/control-plane.sh.tpl", {
    k3s_token           = random_password.k3s_token.result
    cluster_name        = var.cluster_name
    taint_control_plane = var.taint_control_plane
    hcloud_token        = var.hcloud_token
  })

  network {
    network_id = hcloud_network.k3s.id
    ip         = "10.1.0.2"
  }

  depends_on = [hcloud_network_subnet.k3s]
}

# K3s Token
resource "random_password" "k3s_token" {
  length  = 64
  special = false
}

# Generate worker nodes based on locations * count
locals {
  worker_nodes = flatten([
    for loc in var.locations : [
      for i in range(var.initial_workers_per_location) : {
        name     = "${var.cluster_name}-worker-${loc}-${i + 1}"
        location = loc
      }
    ]
  ])
}

# Initial Worker Nodes
resource "hcloud_server" "initial_workers" {
  for_each     = { for node in local.worker_nodes : node.name => node }
  name         = each.value.name
  image        = "ubuntu-22.04"
  server_type  = var.worker_server_type
  location     = each.value.location
  ssh_keys     = [hcloud_ssh_key.default.id]
  firewall_ids = [hcloud_firewall.k3s.id]

  labels = {
    cluster  = var.cluster_name
    role     = "worker"
    location = each.value.location
  }

  user_data = templatefile("${path.module}/templates/worker.sh.tpl", {
    k3s_token        = random_password.k3s_token.result
    control_plane_ip = hcloud_server.control_plane.ipv4_address
    node_labels      = "topology.kubernetes.io/zone=${each.value.location}"
  })

  network {
    network_id = hcloud_network.k3s.id
    # IP is auto-assigned from subnet
  }

  depends_on = [
    hcloud_network_subnet.k3s,
    hcloud_server.control_plane
  ]
}

# Fetch kubeconfig after cluster is ready
resource "null_resource" "kubeconfig" {
  depends_on = [hcloud_server.control_plane]

  provisioner "local-exec" {
    command = <<-EOT
      sleep 120  # Wait for K3s to initialize
      ssh -o StrictHostKeyChecking=no -i ${local_file.ssh_private_key.filename} \
        root@${hcloud_server.control_plane.ipv4_address} \
        'cat /etc/rancher/k3s/k3s.yaml' | \
        sed "s/127.0.0.1/${hcloud_server.control_plane.ipv4_address}/g" > ${path.module}/kubeconfig
    EOT
  }
}

# Outputs
output "control_plane_ip" {
  value       = hcloud_server.control_plane.ipv4_address
  description = "Public IP of the K3s control plane"
}

output "worker_ips" {
  value       = { for k, v in hcloud_server.initial_workers : k => v.ipv4_address }
  description = "Public IPs of initial worker nodes"
}

output "kubeconfig_path" {
  value       = "${path.module}/kubeconfig"
  description = "Path to kubeconfig file"
}

output "ssh_private_key_path" {
  value       = local_file.ssh_private_key.filename
  description = "Path to SSH private key"
}
