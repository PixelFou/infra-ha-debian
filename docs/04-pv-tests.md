## Test 3.6 — Validation de la bascule VRRP (Capture réseau)

### Objectif
Prouver la bascule automatique du rôle MASTER entre LB1 et LB2 lors de l'arrêt du service Keepalived.

### Capture `tcpdump` sur le LAN (enp0s8)
```text
10:55:36.487508 IP 192.168.10.11 > 224.0.0.18: VRRPv2, Advertisement, vrid 10, prio 101, authtype simple, intvl 1s, length 20
10:55:37.489095 IP 192.168.10.11 > 224.0.0.18: VRRPv2, Advertisement, vrid 10, prio 101, authtype simple, intvl 1s, length 20
10:55:38.489322 IP 192.168.10.11 > 224.0.0.18: VRRPv2, Advertisement, vrid 10, prio 101, authtype simple, intvl 1s, length 20
10:55:39.490279 IP 192.168.10.11 > 224.0.0.18: VRRPv2, Advertisement, vrid 10, prio 101, authtype simple, intvl 1s, length 20
10:55:40.491292 IP 192.168.10.11 > 224.0.0.18: VRRPv2, Advertisement, vrid 10, prio 101, authtype simple, intvl 1s, length 20
10:55:41.282865 IP 192.168.10.11 > 224.0.0.18: VRRPv2, Advertisement, vrid 10, prio 0, authtype simple, intvl 1s, length 20
10:55:41.898073 IP 192.168.10.12 > 224.0.0.18: VRRPv2, Advertisement, vrid 10, prio 100, authtype simple, intvl 1s, length 20
10:55:42.898688 IP 192.168.10.12 > 224.0.0.18: VRRPv2, Advertisement, vrid 10, prio 100, authtype simple, intvl 1s, length 20