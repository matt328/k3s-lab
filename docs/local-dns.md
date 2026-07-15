# Local DNS for cluster ingress

This lab uses wildcard DNS per cluster so services can be reached without `kubectl port-forward`.

## Desired shape

| Cluster   | DNS suffix   | Ingress IP default | Examples                                   |
| --------- | ------------ | ------------------ | ------------------------------------------ |
| cluster A | `a.lab.home` | `192.168.50.240`   | `argocd.a.lab.home`, `frontend.a.lab.home` |
| cluster B | `b.lab.home` | `192.168.50.245`   | `argocd.b.lab.home`, `frontend.b.lab.home` |

The DNS server does **not** need to know about every Kubernetes service. It only needs wildcard records:

```text
*.a.lab.home -> cluster A ingress IP
*.b.lab.home -> cluster B ingress IP
```

After that, any Kubernetes Ingress or HTTPRoute using a hostname under the cluster suffix becomes resolvable
automatically. For example, an Argo CD Ingress with host `argocd.a.lab.home` resolves because `*.a.lab.home` points at
cluster A's ingress.

## Pick MetalLB IPs

Choose LAN IPs that are:

- on the same LAN as the VMs
- outside your router's DHCP range
- not already used by another host
- reserved/documented so your router does not hand them out later

The repository defaults are documented in `.env.example` for local scripts and in
`gitops/components/lab-network/lab-network.env` for Argo-rendered GitOps manifests:

```bash
METALLB_A_POOL=192.168.50.240-192.168.50.244
METALLB_B_POOL=192.168.50.245-192.168.50.249
CLUSTER_A_INGRESS_IP=192.168.50.240
CLUSTER_B_INGRESS_IP=192.168.50.245
CLUSTER_A_DNS_ZONE=a.lab.home
CLUSTER_B_DNS_ZONE=b.lab.home
```

Update `.env.local` if those addresses conflict with your network. If Argo CD will manage the cluster, also update and
commit `gitops/components/lab-network/lab-network.env` so MetalLB, Traefik, Ingresses, and app endpoints render with the
same values.

## Raspberry Pi DNS setup

The Pi at `192.168.50.210` should answer for the wildcard zones.

### Pi-hole v6+

Pi-hole v6 manages FTL configuration through `/etc/pihole/pihole.toml`. Dropping files into `/etc/dnsmasq.d` is ignored
unless `misc.etc_dnsmasq_d` is enabled, so use the v6-native `misc.dnsmasq_lines` setting:

```bash
sudo pihole-FTL --config misc.dnsmasq_lines \
  '["address=/a.lab.home/192.168.50.240","address=/b.lab.home/192.168.50.245"]'

sudo pihole restartdns
```

If you previously created `/etc/dnsmasq.d/05-k3s-lab-wildcards.conf`, remove it to avoid confusion:

```bash
sudo rm -f /etc/dnsmasq.d/05-k3s-lab-wildcards.conf
```

### Pi-hole v5 or plain dnsmasq

If you are using Pi-hole v5 or plain dnsmasq, add a dnsmasq config file:

```bash
sudo tee /etc/dnsmasq.d/05-k3s-lab-wildcards.conf >/dev/null <<'EOF'
# k3s-lab wildcard ingress zones
# cluster A ingress
address=/a.lab.home/192.168.50.240

# cluster B ingress
address=/b.lab.home/192.168.50.245
EOF
```

Validate and reload DNS:

```bash
sudo pihole restartdns
```

If this Pi runs plain dnsmasq instead of Pi-hole:

```bash
sudo dnsmasq --test
sudo systemctl restart dnsmasq
```

## Verify from the workstation

Query the Pi directly:

```bash
dig @192.168.50.210 argocd.a.lab.home +short
dig @192.168.50.210 frontend.a.lab.home +short
dig @192.168.50.210 argocd.b.lab.home +short
```

Expected:

```text
192.168.50.240
192.168.50.240
192.168.50.245
```

Then verify your workstation is actually using the Pi:

```bash
resolvectl query argocd.a.lab.home
resolvectl query argocd.b.lab.home
```

If direct `dig @192.168.50.210 ...` works but `resolvectl query ...` does not, fix the workstation's DNS server first.
On this Fedora host, `br0` should use the Pi and ignore DHCP-provided DNS:

```bash
sudo nmcli connection modify br0 \
  ipv4.dns "192.168.50.210" \
  ipv4.dns-search "lab.home" \
  ipv4.ignore-auto-dns yes
sudo nmcli connection down br0 && sudo nmcli connection up br0
```

## Why wildcard DNS instead of per-Service records?

Wildcard DNS is intentionally simple and repeatable:

1. MetalLB gives Traefik one stable LoadBalancer IP per cluster.
2. Wildcard DNS points all hostnames under that cluster suffix to that IP.
3. Traefik routes by HTTP hostname to the correct Kubernetes Service.

This means adding a service only requires adding an Ingress or HTTPRoute with a hostname like `api.a.lab.home`; no
Raspberry Pi DNS change is needed.

If you want DNS records per LoadBalancer Service instead, use ExternalDNS with a DNS provider that supports dynamic
updates, such as RFC2136 against BIND or CoreDNS. Pi-hole/dnsmasq is better suited to static wildcard records than
dynamic Kubernetes-managed DNS updates.
