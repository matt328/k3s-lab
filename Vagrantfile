# -*- mode: ruby -*-
# vi: set ft=ruby :

# k3s multi-cluster lab — Vagrant + libvirt
#
# Two clusters (A, B), each with a local server bridged onto the LAB_BRIDGE
# interface with pinned MACs and static LAN IPs. Optional worker profiles can add
# local agents, cluster-A agents on one remote libvirt host, and cluster-B agents
# on a second remote libvirt host named citadel.
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
  "a" => cfg("VM_A_MASTER_IP"),
  "b" => cfg("VM_B_MASTER_IP"),
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
VM_VCPUS     = cfg("VM_VCPUS").to_i
VM_MEMORY_MB = cfg("VM_MEMORY_MB").to_i

def remote_libvirt_profile(prefix, default_bridge:, default_vcpus:, default_memory_mb:, default_hypervisor:)
  enabled = cfg_bool("#{prefix}_LIBVIRT_ENABLED")
  {
    enabled:           enabled,
    placement:         "remote",
    hypervisor:        cfg_default("#{prefix}_HYPERVISOR_LABEL", default_hypervisor),
    uri:               cfg("#{prefix}_LIBVIRT_URI", required: enabled),
    ssh_proxy_command: cfg("#{prefix}_LIBVIRT_SSH_PROXY_COMMAND", required: enabled),
    bridge:            cfg_default("#{prefix}_LAB_BRIDGE", default_bridge),
    vcpus:             cfg_default("#{prefix}_VM_VCPUS", default_vcpus.to_s).to_i,
    memory_mb:         cfg_default("#{prefix}_VM_MEMORY_MB", default_memory_mb.to_s).to_i,
  }
end

LOCAL_AGENTS_ENABLED = cfg_bool("LOCAL_AGENTS_ENABLED")
REMOTE_LIBVIRT = remote_libvirt_profile(
  "REMOTE",
  default_bridge: NETWORK[:bridge],
  default_vcpus: VM_VCPUS,
  default_memory_mb: VM_MEMORY_MB,
  default_hypervisor: "remote",
)
CITADEL_LIBVIRT = remote_libvirt_profile(
  "CITADEL",
  default_bridge: NETWORK[:bridge],
  default_vcpus: VM_VCPUS,
  default_memory_mb: VM_MEMORY_MB,
  default_hypervisor: "citadel",
)

LOCAL_NODE_DEFAULTS = {
  placement: "local",
  hypervisor: cfg_default("LOCAL_HYPERVISOR_LABEL", "local"),
  bridge: NETWORK[:bridge],
  vcpus: VM_VCPUS,
  memory_mb: VM_MEMORY_MB,
}

def remote_node_defaults(profile)
  {
    placement: profile[:placement],
    hypervisor: profile[:hypervisor],
    bridge: profile[:bridge],
    vcpus: profile[:vcpus],
    memory_mb: profile[:memory_mb],
    libvirt_uri: profile[:uri],
    ssh_proxy_command: profile[:ssh_proxy_command],
  }
end

BASE_NODES = [
  {
    name: "k3s-a-master",
    role: "server",
    cluster: "a",
    ip: cfg("VM_A_MASTER_IP"),
    mac: cfg("VM_A_MASTER_MAC"),
  }.merge(LOCAL_NODE_DEFAULTS),
  {
    name: "k3s-b-master",
    role: "server",
    cluster: "b",
    ip: cfg("VM_B_MASTER_IP"),
    mac: cfg("VM_B_MASTER_MAC"),
  }.merge(LOCAL_NODE_DEFAULTS),
]

LOCAL_AGENT_NODES = if LOCAL_AGENTS_ENABLED
  [
    { name: "k3s-a-agent", role: "agent", cluster: "a", ip: cfg("VM_A_AGENT_IP"), mac: cfg("VM_A_AGENT_MAC") },
    { name: "k3s-b-agent", role: "agent", cluster: "b", ip: cfg("VM_B_AGENT_IP"), mac: cfg("VM_B_AGENT_MAC") },
  ].map { |node| node.merge(LOCAL_NODE_DEFAULTS) }
else
  []
end

REMOTE_NODES = if REMOTE_LIBVIRT[:enabled]
  [
    { name: "k3s-a-remote-1", role: "agent", cluster: "a", ip: cfg("VM_A_REMOTE_1_IP"), mac: cfg("VM_A_REMOTE_1_MAC") },
    { name: "k3s-a-remote-2", role: "agent", cluster: "a", ip: cfg("VM_A_REMOTE_2_IP"), mac: cfg("VM_A_REMOTE_2_MAC") },
  ].map { |node| node.merge(remote_node_defaults(REMOTE_LIBVIRT)) }
else
  []
end

CITADEL_NODES = if CITADEL_LIBVIRT[:enabled]
  [
    {
      name: "k3s-b-citadel-1",
      role: "agent",
      cluster: "b",
      ip: cfg("VM_B_CITADEL_1_IP"),
      mac: cfg("VM_B_CITADEL_1_MAC"),
    },
    {
      name: "k3s-b-citadel-2",
      role: "agent",
      cluster: "b",
      ip: cfg("VM_B_CITADEL_2_IP"),
      mac: cfg("VM_B_CITADEL_2_MAC"),
    },
    {
      name: "k3s-b-citadel-3",
      role: "agent",
      cluster: "b",
      ip: cfg("VM_B_CITADEL_3_IP"),
      mac: cfg("VM_B_CITADEL_3_MAC"),
    },
  ].map { |node| node.merge(remote_node_defaults(CITADEL_LIBVIRT)) }
else
  []
end

NODES = BASE_NODES + LOCAL_AGENT_NODES + REMOTE_NODES + CITADEL_NODES

def node_labels(node)
  [
    "lab.k3s.io/cluster=cluster-#{node[:cluster]}",
    "lab.k3s.io/placement=#{node[:placement]}",
    "lab.k3s.io/hypervisor=#{node[:hypervisor]}",
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

      # 1. pin the bridged NIC to its static LAN IP
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

      # 2. install k3s (server or agent)
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
