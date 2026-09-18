# Plan d'adressage et Matrice de flux

## Plan d'adressage IP

| Équipement | Interface | Réseau | Adresse IP / Masque | Rôle |
| :--- | :--- | :--- | :--- | :--- |
| **CLIENT** | eth0 | HA-LAN | `192.168.10.50/24` | Client de test |
| **LB1** | eth0 | HA-LAN | `192.168.10.11/24` | Load Balancer 1 (Master) |
| **LB1** | eth1 | HA-DMZ | `192.168.20.11/24` | Interface DMZ |
| **LB2** | eth0 | HA-LAN | `192.168.10.12/24` | Load Balancer 2 (Backup) |
| **LB2** | eth1 | HA-DMZ | `192.168.20.12/24` | Interface DMZ |
| **WEB1** | eth0 | HA-DMZ | `192.168.20.21/24` | Serveur Web 1 |
| **WEB2** | eth0 | HA-DMZ | `192.168.20.22/24` | Serveur Web 2 |
| **VIP LAN** | Virtual | HA-LAN | `192.168.10.100/24` | IP Virtuelle Keepalived |
| **VIP DMZ** | Virtual | HA-DMZ | `192.168.20.100/24` | Passerelle Virtuelle |

## Matrice de flux

| Source | Destination | Port/Protocole | Description |
| :--- | :--- | :--- | :--- |
| CLIENT | VIP LAN (`192.168.10.100`) | TCP/80 (HTTP) | Trafic web entrant |
| LB1 / LB2 | WEB1 / WEB2 | TCP/80 (HTTP) | Proxying HAProxy vers backends |
| LB1 | LB2 | VRRP (IP 112) | Heartbeat Keepalived |
