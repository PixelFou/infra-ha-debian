# Infrastructure Haute Disponibilité Debian 12

## Plan d'adressage IP (Phase 0)

| Machine | HA-LAN (192.168.10.0/24) | HA-DMZ (192.168.20.0/24) | HA-SYNC (10.99.99.0/24) |
| :--- | :--- | :--- | :--- |
| **CLIENT** | 192.168.10.50 | - | - |
| **LB1** | 192.168.10.11 | 192.168.20.11 | 10.99.99.11 |
| **LB2** | 192.168.10.12 | 192.168.20.12 | 10.99.99.12 |
| **WEB1** | - | 192.168.20.21 | 10.99.99.21 |
| **WEB2** | - | 192.168.20.22 | 10.99.99.22 |

## État de validation
- [x] Unicité des `machine-id` et clés SSH
- [x] Configuration réseau statique dans `/etc/network/interfaces`
- [x] Résolution de nom dans `/etc/hosts`
- [x] Synchronisation temporelle (`chrony`)
- [x] Tests de connectivité IP (pings OK)
