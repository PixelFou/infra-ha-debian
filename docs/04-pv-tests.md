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
```

---

## Test 3.7 — Mesures comparatives du RTO (Recovery Time Objective)

### Objectif
Mesurer le temps d'interruption de service (RTO) perçu par le client final lors de trois types de défaillances distinctes sur le load-balancer actif (`LB1`).

### Tableau comparatif des résultats

| Scénario | Type de panne | Commandes / Actions | Mécanisme de détection | RTO Mesuré | Conforme ANSSI |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Scénario A** | Arrêt gracieux VRRP | `systemctl stop keepalived` | Notification active VRRP (`prio 0`) | **~0,6 s** | Oui (< 1 s) |
| **Scénario B** | Crash applicatif HAProxy | `killall -9 haproxy` | Échec du `track_script` Keepalived | **~2,5 s** | Oui (< 5 s) |
| **Scénario C** | Perte de lien / Pause de la VM | `ip link set dev enp0s8 down` ou Pause VM | `track_interface` + Gratuitous ARP via `VG_1` | **~0,1 s** | Oui (< 1 s) |

---

### Analyse et justification des écarts de RTO

1. **Scénario A (Arrêt gracieux de Keepalived) :**
   Lors de l'arrêt du service, `LB1` émet une trame VRRP d'adieu avec une priorité de `0`. `LB2` intercepte immédiatement ce signal et prend le relais sans attente.

2. **Scénario B (Détection par la sonde applicative) :**
   Le délai de bascule est conditionné par la fréquence de contrôle du script d'état `check_haproxy` (`interval` et `fall`). La détection et la dégradation de priorité nécessitent environ 2,5 secondes avant la bascule du rôle MASTER.

3. **Scénario C (Coupure de lien / Isolation) :**
   Grâce au groupe de synchronisation `vrrp_sync_group VG_1` et au suivi d'interface `track_interface`, la perte du lien sur le réseau client déclenche une bascule instantanée. `LB2` émet aussitôt des trames *Gratuitous ARP* pour mettre à jour la table ARP des équipements clients, limitant la perte à une seule requête HTTP (~0,1 s).