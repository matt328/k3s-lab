# -*- mode: ruby -*-
# vi: set ft=ruby :

# k3s multi-cluster lab — Vagrant + libvirt
#
# Two clusters (A, B), each with a local server bridged onto the LAB_BRIDGE
# interface with pinned MACs and static LAN IPs. HOST_* settings describe the
# physical libvirt hosts; CLUSTER_* settings describe the k3s nodes.
#
# All environment-specific values (IPs, MACs, networking, tokens, etc.) live
# in .env.local. Copy .env.example to .env.local and edit before running.

require "pathname"

REPO_ROOT = Pathname.new(__dir__)

# --- env loading --------------------------------------------------------------
# Loads KEY=VALUE pairs from a dotenv-style file. Strips surrounding quotes.
def load_env_file(path)
  return {} unless File.exist?(path)
  File.readlines(path).each_with_object({}) do |line, h|
    line = line.strip
    next if line.empty? || line.start_with?("#")
    k, v = line.split("=", 2)
    next unless k && v
    h[k.strip] = v.strip.gsub(/\A["']|["']\z/, "")
  end
end

# .env.example provides defaults; .env.local overrides. Real env wins over both.
ENV_DEFAULTS = load_env_file(REPO_ROOT.join(".env.example"))
ENV_LOCAL    = load_env_file(REPO_ROOT.join(".env.local"))

def cfg(key, required: true)
  val = ENV[key] || ENV_LOCAL[key] || ENV_DEFAULTS[key]
  if required && (val.nil? || val.empty? || val.start_with?("replace-me") || val.start_with?("YOUR_"))
    abort "config: #{key} is not set. Copy .env.example to .env.local and fill it in."
  end
  val
end

def cfg_bool(key, default: false)
  val = cfg(key, required: false)
  return default if val.nil? || val.empty?

  %w[1 true yes on].include?(val.downcase)
end

def cfg_default(key, default)
  val = cfg(key, required: false)
  val.nil? || val.empty? ? default : val
end

# --- topology -----------------------------------------------------------------
# Node identity is a lab constant; IPs/MACs come from env.
CLUSTER_TOKENS = {
  "a" => cfg("K3S_TOKEN_A"),
  "b" => cfg("K3S_TOKEN_B"),
}

MASTER_IPS = {
  "a" => cfg("CLUSTER_A_SERVER_1_IP"),
  "b" => cfg("CLUSTER_B_SERVER_1_IP"),
}

NETWORK = {
  prefix:  cfg("LAB_PREFIX"),
  gateway: cfg("LAB_GATEWAY"),
  dns:     cfg("LAB_DNS"),
  domain:  cfg("LAB_DOMAIN"),
  bridge:  cfg("LAB_BRIDGE"),
}

GATEWAY_API_VERSION = cfg("GATEWAY_API_VERSION")
LAB_OCI_REGISTRY_HOST = cfg("LAB_OCI_REGISTRY_HOST")
LAB_OCI_REGISTRY_IP = cfg("LAB_OCI_REGISTRY_IP")
def host_profile(prefix, local: false, default_label:)
  enabled = local || cfg_bool("#{prefix}_ENABLED")
  {
    enabled: enabled,
    placement: local ? "local" : "remote",
    label: cfg_default("#{prefix}_LABEL", default_label),
    bridge: cfg_default("#{prefix}_BRIDGE", NETWORK[:bridge]),
    vcpus: cfg("#{prefix}_VM_VCPUS").to_i,
    memory_mb: cfg("#{prefix}_VM_MEMORY_MB").to_i,
    libvirt_uri: local ? nil : cfg("#{prefix}_URI", required: enabled),
    ssh_proxy_command: local ? nil : cfg("#{prefix}_SSH_PROXY_COMMAND", required: enabled),
  }
end

HOSTS = {
  "HOST_LOCAL" => host_profile("HOST_LOCAL", local: true, default_label: "local"),
  "HOST_1" => host_profile("HOST_1", default_label: "host-1"),
  "HOST_2" => host_profile("HOST_2", default_label: "host-2"),
}

HOST_LOCAL_WORKERS_ENABLED = cfg_bool("HOST_LOCAL_WORKERS_ENABLED")

def node_from_env(env_prefix, name:, role:, cluster:, default_host:)
  host_key = cfg_default("#{env_prefix}_HOST", default_host)
  profile = HOSTS[host_key]
  abort "config: #{env_prefix}_HOST references unknown host profile '#{host_key}'." unless profile

  {
    name: name,
    role: role,
    cluster: cluster,
    ip: cfg("#{env_prefix}_IP"),
    mac: cfg("#{env_prefix}_MAC"),
    host_key: host_key,
  }.merge(profile)
end

BASE_NODES = [
  node_from_env(
    "CLUSTER_A_SERVER_1",
    name: "k3s-a-server-1",
    role: "server",
    cluster: "a",
    default_host: "HOST_LOCAL",
  ),
  node_from_env(
    "CLUSTER_B_SERVER_1",
    name: "k3s-b-server-1",
    role: "server",
    cluster: "b",
    default_host: "HOST_LOCAL",
  ),
]

LOCAL_WORKER_NODES = if HOST_LOCAL_WORKERS_ENABLED
  [
    node_from_env(
      "CLUSTER_A_LOCAL_WORKER_1",
      name: "k3s-a-local-worker-1",
      role: "agent",
      cluster: "a",
      default_host: "HOST_LOCAL",
    ),
    node_from_env(
      "CLUSTER_B_LOCAL_WORKER_1",
      name: "k3s-b-local-worker-1",
      role: "agent",
      cluster: "b",
      default_host: "HOST_LOCAL",
    ),
  ]
else
  []
end

WORKER_NODES = [
  node_from_env(
    "CLUSTER_A_WORKER_1",
    name: "k3s-a-worker-1",
    role: "agent",
    cluster: "a",
    default_host: "HOST_1",
  ),
  node_from_env(
    "CLUSTER_A_WORKER_2",
    name: "k3s-a-worker-2",
    role: "agent",
    cluster: "a",
    default_host: "HOST_1",
  ),
  node_from_env(
    "CLUSTER_B_WORKER_1",
    name: "k3s-b-worker-1",
    role: "agent",
    cluster: "b",
    default_host: "HOST_2",
  ),
  node_from_env(
    "CLUSTER_B_WORKER_2",
    name: "k3s-b-worker-2",
    role: "agent",
    cluster: "b",
    default_host: "HOST_2",
  ),
  node_from_env(
    "CLUSTER_B_WORKER_3",
    name: "k3s-b-worker-3",
    role: "agent",
    cluster: "b",
    default_host: "HOST_2",
  ),
].select { |node| node[:enabled] }

NODES = BASE_NODES + LOCAL_WORKER_NODES + WORKER_NODES

def node_labels(node)
  [
    "lab.k3s.io/cluster=cluster-#{node[:cluster]}",
    "lab.k3s.io/placement=#{node[:placement]}",
    "lab.k3s.io/host=#{node[:label]}",
  ].join(",")
end

Vagrant.configure("2") do |config|
  config.vm.box = "bento/fedora-42"
  config.vm.synced_folder ".", "/vagrant", disabled: true

  NODES.each do |node|
    config.vm.define node[:name] do |vm|
      vm.vm.hostname = node[:name]

      # Bridged LAN interface. vagrant-libvirt still creates a private
      # management interface for SSH; this is the workload-facing one.
      vm.vm.network :public_network,
        dev:  node[:bridge],
        mode: "bridge",
        type: "bridge",
        mac:  node[:mac].gsub(":", "")

      vm.vm.provider :libvirt do |lv|
        lv.memory               = node[:memory_mb]
        lv.cpus                 = node[:vcpus]
        lv.machine_virtual_size = 20
        lv.qemu_use_session     = false
        lv.uri                  = node[:libvirt_uri] if node[:libvirt_uri]
        lv.proxy_command        = node[:ssh_proxy_command] if node[:ssh_proxy_command]
      end

      # 1. raise node kernel limits before Kubernetes components start
      vm.vm.provision "shell",
        name: "configure node sysctl",
        path: "scripts/configure-node-sysctl.sh"

      # 2. pin the bridged NIC to its static LAN IP
      vm.vm.provision "shell",
        name: "configure static IP",
        path: "scripts/configure-static-ip.sh",
        env: {
          "VM_MAC"  => node[:mac],
          "VM_IP"   => node[:ip],
          "PREFIX"  => NETWORK[:prefix],
          "GATEWAY" => NETWORK[:gateway],
          "DNS"     => NETWORK[:dns],
          "DOMAIN"  => NETWORK[:domain],
        }

      # 3. install k3s (server or agent)
      if node[:role] == "server"
        vm.vm.provision "shell",
          name: "install k3s server",
          path: "scripts/install-k3s-server.sh",
          env: {
            "K3S_TOKEN"           => CLUSTER_TOKENS[node[:cluster]],
            "NODE_IP"             => node[:ip],
            "GATEWAY_API_VERSION" => GATEWAY_API_VERSION,
            "LAB_OCI_REGISTRY_HOST" => LAB_OCI_REGISTRY_HOST,
            "LAB_OCI_REGISTRY_IP" => LAB_OCI_REGISTRY_IP,
          }
      else
        vm.vm.provision "shell",
          name: "install k3s agent",
          path: "scripts/install-k3s-agent.sh",
          env: {
            "K3S_TOKEN" => CLUSTER_TOKENS[node[:cluster]],
            "MASTER_IP" => MASTER_IPS[node[:cluster]],
            "NODE_IP"   => node[:ip],
            "NODE_LABELS" => node_labels(node),
            "LAB_OCI_REGISTRY_HOST" => LAB_OCI_REGISTRY_HOST,
            "LAB_OCI_REGISTRY_IP" => LAB_OCI_REGISTRY_IP,
          }
      end
    end
  end
end
