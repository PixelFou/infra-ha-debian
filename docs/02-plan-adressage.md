# Plan d'adressage et Matrice de flux

## Plan d'adressage IP

| Équipement | Interface | Réseau | Adresse IP / Masque | Rôle |
| :--- | :--- | :--- | :--- | :--- |
| **CLIENT** | eth0 | HA-LAN | `192.168.10.50/24` | Client de test |
| **LB1** | eth0 | HA-LAN | `192.168.10.11/24` | Load Balancer 1 (Master LAN) |
| **LB1** | eth1 | HA-DMZ | `192.168.20.11/24` | Interface DMZ LB1 |
| **LB1** | eth2 | HA-SYNC | `10.99.99.11/24` | Interconnexion / Administration / Syslog |
| **LB2** | eth0 | HA-LAN | `192.168.10.12/24` | Load Balancer 2 (Backup LAN) |
| **LB2** | eth1 | HA-DMZ | `192.168.20.12/24` | Interface DMZ LB2 |
| **LB2** | eth2 | HA-SYNC | `10.99.99.12/24` | Interconnexion / Administration |
| **WEB1** | eth0 | HA-DMZ | `192.168.20.21/24` | Serveur Web 1 |
| **WEB1** | eth1 | HA-SYNC | `10.99.99.21/24` | Réplication de données (rsync) |
| **WEB2** | eth0 | HA-DMZ | `192.168.20.22/24` | Serveur Web 2 |
| **WEB2** | eth1 | HA-SYNC | `10.99.99.22/24` | Réplication de données (rsync) |
| **VIP LAN** | Virtual | HA-LAN | `192.168.10.100/24` | IP Virtuelle publique (HAProxy) |
| **VIP DMZ** | Virtual | HA-DMZ | `192.168.20.100/24` | Passerelle Virtuelle pour les serveurs Web |

---

## Matrice de flux (Politique Default-Drop)

| Source | Destination | Protocole | Port / Type | Justification |
| :--- | :--- | :---: | :---: | :--- |
| `192.168.10.0/24` (HA-LAN) | `192.168.10.100` (VIP LAN) | TCP | 80, 443 | Flux HTTP/HTTPS des clients vers le portail web (HAProxy) |
| `10.99.99.11`, `.12` (HA-SYNC) | `224.0.0.18` (Multicast) | IP (112) | VRRP | Annonces Heartbeat Keepalived entre LB1 et LB2 |
| `192.168.20.11`, `.12` (HA-DMZ) | `192.168.20.21`, `.22` (WEB) | TCP | 80 | Proxying du trafic web HAProxy vers les serveurs HTTP backend |
| `10.99.99.21` (WEB1) | `10.99.99.22` (WEB2) | TCP | 22 (SSH) | Réplication unidirectionnelle de `/var/www/data/` via `rsync` |
| `10.99.99.0/24` (HA-SYNC) | `10.99.99.0/24` | TCP | 22 (SSH) | Administration SSH sécurisée à accès restreint entre les nœuds |
| `10.99.99.21`, `.22`, `.12` | `10.99.99.11` (LB1) | UDP | 514 (Syslog) | Centralisation des journaux système et applicatifs via `rsyslog` |
| `192.168.20.0/24` (HA-DMZ) | `0.0.0.0/0` (Internet) | Tous | Any | Masquerade / NAT sortant via la passerelle VIP DMZ (LB MASTER) |