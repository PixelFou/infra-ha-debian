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

| Scénario | Type de panne | Commandes exécutées | Mécanisme de détection | RTO Mesuré | Conforme ANSSI |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Scénario A** | Arrêt gracieux VRRP | `systemctl stop keepalived` | Notification active VRRP (`prio 0`) | **~0,6 s** |  Oui (< 1s) |
| **Scénario B** | Crash applicatif HAProxy | `killall -9 haproxy` | Échec du `track_script` Keepalived | **~2,5 s** |  Oui (< 5s) |
| **Scénario C** | Perte de lien réseau LAN | `ip link set dev enp0s8 down` | Expiration du *Master Down Timer* | **~3,6 s** |  Oui (< 5s) |

---

### Analyse et justification des écarts de RTO

1. **Scénario A (Bascule la plus rapide) :**
   Lors d'un arrêt propre de Keepalived, `LB1` émet immédiatement une trame VRRP d'adieu avec une priorité de `0`. `LB2` reçoit ce signal et prend instantanément le relais sans attendre de délai d'inactivité.

2. **Scénario B (Détection par la sonde applicative) :**
   Le délai de bascule dépend de la fréquence du script d'état `check_haproxy` (paramètres `interval` et `fall` dans `keepalived.conf`). La détection prend environ 2 secondes avant que Keepalived ne réduise la priorité ou ne bascule en état `FAULT`.

3. **Scénario C (Bascule sur timeout VRRP) :**
   En cas de perte brutale d'interface, `LB1` ne peut émettre aucune trame de notification. `LB2` constate l'absence d'annonces VRRP et déclenche la bascule à l'expiration.