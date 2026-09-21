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

---

## Test 3.8 — Validation de la stratégie de non-préemption (`nopreempt`)

### Objectif
Vérifier que le rétablissement du load-balancer principal (`LB1`) après une défaillance ne provoque pas de retour automatique (*failback*) vers `LB1` tant que le nœud secondaire (`LB2`) fonctionne normalement. Cette configuration élimine toute seconde interruption de service inutile et évite les risques de clignotement (*flapping*) du cluster.

### Configuration appliquée
Dans `/etc/keepalived/keepalived.conf` sur **LB1** et **LB2** :
- Passing du paramètre `state` à **`BACKUP`** sur lb1 dans chaque instance VRRP. (prérequis technique obligatoire pour la non-préemption).
- Ajout de la directive **`nopreempt`** dans chaque instance VRRP (`VI_LAN` et `VI_DMZ`).
- Maintien des priorités relatives : `LB1` (priorité `101`), `LB2` (priorité `100`).

---

### Chronologie du test et observations

| Étape | Action exécutée | État LB1 | État LB2 | Nœud porteur des VIP | Comportement observé |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **1. Boot initial** | Démarrage à froid du cluster | `MASTER` | `BACKUP` | **LB1** | `LB1` devient `MASTER` au démarrage initial grâce à sa priorité supérieure (101 vs 100). |
| **2. Simulation Panne** | `systemctl stop keepalived` sur LB1 | `STOPPED` | `MASTER` | **LB2** | Bascule automatique instantanée des VIP vers `LB2`. |
| **3. Rétablissement** | `systemctl start keepalived` sur LB1 | `BACKUP` | `MASTER` | **LB2** | **Conforme** : `LB1` réintègre le cluster en état `BACKUP`. Les VIP restent stables sur `LB2`. |

---

### Conclusion
La stratégie de non-préemption est **validée**. Le cluster conserve sa stabilité sur le nœud `LB2` sans imposer de coupure réseau supplémentaire lors de la reconnexion de `LB1`. Le basculement inverse vers `LB1` pourra être planifié ultérieurement de façon contrôlée lors d'une fenêtre de maintenance.