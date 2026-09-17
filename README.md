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


## Phase 1 : Configuration du routage LAN <-> DMZ

Afin de permettre la communication et l'accès SSH/HTTP direct depuis la zone **HA-LAN** (`192.168.10.0/24`) vers les serveurs de la zone **HA-DMZ** (`192.168.20.0/24`) sans passer par un rebond SSH manuel sur `LB1`, la topologie de routage suivante a été mise en place :

### 1. Routage sur le poste CLIENT (`192.168.10.50`)
Ajout d'une route statique pointant vers `LB1` comme passerelle vers la DMZ :
```bash
sudo ip route add 192.168.20.0/24 via 192.168.10.11
