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


---

## Test 4.1 — Identification de l'incohérence d'état applicatif (Sessions PHP)

### Objectif
Observer le comportement d'une application PHP utilisant les sessions applicatives (compteur de visites) distribuée sur un cluster HAProxy en équilibrage de charge de type *Round-Robin* sans persistance de session.

### Résultat
debian@client: curl -c /tmp/cj -b /tmp/cj -s http://192.168.10.100/ | grep -i -E 'compteur|served'
        <li><strong>Compteur de visites (Session) :</strong> 1</li>
debian@client: curl -c /tmp/cj -b /tmp/cj -s http://192.168.10.100/ | grep -i -E 'compteur|served'
        <li><strong>Compteur de visites (Session) :</strong> 1</li>
debian@client: curl -c /tmp/cj -b /tmp/cj -s http://192.168.10.100/ | grep -i -E 'compteur|served'
        <li><strong>Compteur de visites (Session) :</strong> 2</li>
debian@client: curl -c /tmp/cj -b /tmp/cj -s http://192.168.10.100/ | grep -i -E 'compteur|served'
        <li><strong>Compteur de visites (Session) :</strong> 2</li>
debian@client: curl -c /tmp/cj -b /tmp/cj -s http://192.168.10.100/ | grep -i -E 'compteur|served'
        <li><strong>Compteur de visites (Session) :</strong> 3</li>
debian@client: curl -c /tmp/cj -b /tmp/cj -s http://192.168.10.100/ | grep -i -E 'compteur|served'
        <li><strong>Compteur de visites (Session) :</strong> 3</li>


### Test exécuté depuis le CLIENT
```bash
curl -c /tmp/cj -b /tmp/cj -s http://192.168.10.100/ | grep -i -E 'compteur|served'
```

---


## Test 4.2 — Résolution par persistance de session (Sticky Sessions HAProxy)

### Objectif
Mettre en place et valider le mécanisme de persistance de session basé sur l'injection d'un cookie applicatif (`SERVERID`) par HAProxy, afin de garantir qu'un client reste orienté vers le même serveur backend tout au long de sa navigation.

### Configuration appliquée
Dans `/etc/haproxy/haproxy.cfg` (sur **LB1** et **LB2**), au sein du bloc `backend web_servers` :
- Ajout de la directive `cookie SERVERID insert indirect nocache`.
- Configuration de l'option `cookie <id>` sur chaque déclaration de serveur backend (`web1` et `web2`).

```haproxy
backend web_servers
    balance roundrobin
    cookie SERVERID insert indirect nocache
    option httpchk GET /health
    http-check expect status 200
    server web1 192.168.20.21:80 check inter 2000ms fall 5 rise 2 cookie web1
    server web2 192.168.20.22:80 check inter 2000ms fall 5 rise 2 cookie web2
```

### Résultats observés

<li><strong>Compteur de visites (Session) :</strong> 1</li>
<li><strong>Compteur de visites (Session) :</strong> 2</li>
<li><strong>Compteur de visites (Session) :</strong> 3</li>
<li><strong>Compteur de visites (Session) :</strong> 4</li>
<li><strong>Compteur de visites (Session) :</strong> 5</li>
<li><strong>Compteur de visites (Session) :</strong> 6</li>

## Conclusion

La persistance de session par cookie HTTP est validée. HAProxy injecte le cookie SERVERID=web1 lors de la première réponse. Pour toutes les requêtes ultérieures, la présence de ce cookie permet au load-balancer d'acheminer le trafic vers le même nœud, assurant la continuité du stockage local des sessions PHP et l'incrémentation linéaire du compteur.









## Test 4.3 — La sonde qui ment (Faux-positif de la sonde de santé statique)

### Objectif
Démontrer qu'une sonde de santé HTTP interrogeant une ressource statique (`/health`) servie directement par le serveur web (Nginx) génère un faux-positif : le load-balancer considère le backend comme opérationnel alors que le moteur d'exécution applicatif (PHP-FPM) est complètement hors service.

### Procédure et épreuves de test

1. **Arrêt du moteur PHP sur WEB1 :**
   ```bash
   sudo systemctl stop php8.2-fpm

---

## Interrogation directe de la page d'accueil applicative depuis LB1 :

Bash
curl -i [http://192.168.20.21/](http://192.168.20.21/)
Résultat : Nginx ne pouvant plus communiquer avec le socket PHP-FPM, la réponse bascule immédiatement en erreur HTTP/1.1 502 Bad Gateway.

## Interrogation directe du point de santé statique depuis LB1 :
Bash
curl -i [http://192.168.20.21/health](http://192.168.20.21/health)
Résultat : Nginx répond HTTP/1.1 200 OK, le fichier statique n'ayant aucune dépendance avec PHP-FPM.

Supervision HAProxy (journalctl -u haproxy) :
HAProxy continue d'interroger la route /health. Recevant un code 200 OK, il maintient web1 à l'état UP dans son pool de serveurs actifs.

## Conclusion
Le test confirme la défaillance de la méthodologie de contrôle statique :
La sonde /health valide exclusivement la disponibilité de la couche web (Nginx).
Elle ne reflète pas la santé réelle du processeur applicatif (PHP-FPM).
Conséquence : HAProxy continue de router du trafic vers un serveur incapable de traiter les requêtes dynamiques des utilisateurs.

---

## Test 4.4 — La sonde honnête (Sonde dynamique /health.php)

### Objectif
Implémenter une sonde de santé dynamique `/health.php` effectuant des contrôles applicatifs réels (exécution PHP, droits d'écriture sur le répertoire de données, absence de drapeau de maintenance) et valider qu'HAProxy isole automatiquement un serveur applicatif en défaillance.

### Procédure et résultats

1. **Création du script `/health.php` sur WEB1 et WEB2 :**
   Le script teste l'existence du drapeau `/etc/tp/maintenance` (HTTP 503), l'accès en écriture à `/var/www/html/data` (HTTP 500) et la capacité d'exécution de PHP (HTTP 200).

```
  GNU nano 7.2                /var/www/html/health.php                          
<?php
// 1. Contrôle du drapeau de maintenance
if (file_exists('/etc/tp/maintenance')) {
    http_response_code(503);
    echo 'MAINTENANCE';
    exit;
}

// 2. Contrôle de l'accès au dossier de données
$data_dir = '/var/www/html/data';
if (!is_dir($data_dir) || !is_writable($data_dir)) {
    http_response_code(500);
    echo 'DATA_DIR_NOT_WRITABLE';
    exit;
}

// 3. Statut nominal
http_response_code(200);
echo 'OK';
```


2. **Mise à jour de la configuration HAProxy :**
   Remplacement de la sonde statique par `option httpchk GET /health.php` et validation du code de retour `200`.

3. **Simulation de panne PHP-FPM sur WEB1 (`systemctl stop php8.2-fpm`) :**
   - **Horodatage :** 11:20:12
   - **Détection HAProxy :** `Server web_servers/web1 is DOWN, reason: Layer7 wrong status, code: 502`
   - **Comportement client :** 100% des requêtes clientes basculées vers `web2` avec succès (HTTP 200).

4. **Rétablissement du service sur WEB1 (`systemctl start php8.2-fpm`) :**
   - **Horodatage :** 11:21:54
   - **Réintégration HAProxy :** `Server web_servers/web1 is UP, reason: Layer7 check passed, code: 200`
   - **Nombre de serveurs actifs :** 2 active servers online.

---

### Conclusion
La sonde dynamique remplit son rôle de contrôle de santé réel. Contrairement à la sonde statique 4.3, toute défaillance du moteur applicatif PHP provoque la sortie immédiate du backend du pool de répartition HAProxy, garantissant zéro erreur côté utilisateur.


## Test 4.5 — Mise à jour sans interruption de service (Rolling Update 1.0 -> 1.1)

### Objectif
Exécuter une procédure de mise à jour applicative (passage de la version 1.0 à 1.1) sur le cluster Web sans aucune interruption de service pour les utilisateurs (taux de disponibilité cible : 100,000 %).

---

### Procédure exécutée

1. **Lancement de la sonde de contrôle (sur CLIENT) :**
   Exécution du script `check-dispo.sh http://192.168.10.100/` avec un intervalle de 0,2 s.

2. **Traitement du nœud WEB1 :**
   - Passage de `WEB1` en mode `DRAIN` via le socket HAProxy (`set server web_servers/web1 state drain`).
   - Attente de l'extinction des sessions actives sur `WEB1`.
   - Mise à jour de la version applicative (`1.1` dans `/var/www/html/version.txt`).
   - Remise en service de `WEB1` (`set server web_servers/web1 state ready`).

3. **Traitement du nœud WEB2 :**
   - Passage de `WEB2` en mode `DRAIN` via le socket HAProxy (`set server web_servers/web2 state drain`).
   - Mise à jour de la version applicative (`1.1` dans `/var/www/html/version.txt`).
   - Remise en service de `WEB2` (`set server web_servers/web2 state ready`).

---

### Bilan de disponibilité (Sonde de test)

```text

===============================================================
 BILAN DE DISPONIBILITE, http://192.168.10.100/
===============================================================
 Requetes emises        : 1040 (1 toutes les 0.2 s)
 Reussies / en echec    : 1040 / 0
 TAUX DE DISPONIBILITE  : 100.000 %
 Temps de reponse moyen : 7 ms (sur les requetes abouties)
---------------------------------------------------------------
 AUCUNE INTERRUPTION, 100.000 % de disponibilite
---------------------------------------------------------------
 Repartition de charge (sur les 1040 requetes servies) :
   web2              799 requetes (76.8 %)
   web1              241 requetes (23.2 %)
===============================================================

```

## Conclusion

La procédure de Rolling Update combinée au mode DRAIN d'HAProxy valide l'objectif de Zero-Downtime Deployment. L'isolation progressive des nœuds a permis de traiter l'intégralité des 1 040 requêtes sans générer la moindre erreur HTTP (0 échec).


---

## Phase 5 — Réplication des données applicatives

### 5.1 Démonstration de l'incohérence des données
Un formulaire de téléversement de fichiers a été déployé sur `/var/www/html/upload.php` sur **WEB1** et **WEB2**, stockant les données dans `/var/www/data/`.

* **Constat :** Lorsqu'un fichier est déposé via la VIP, il est enregistré localement sur le nœud qui traite la requête HTTP `POST` (ex. `WEB1`). Si une requête ultérieure est distribuée sur `WEB2`, le fichier est absent.
* **Conclusion :** En l'absence de mécanisme de synchronisation, l'état applicatif est incohérent d'un serveur à l'autre.

---

### 5.2 Mise en place de la réplication (rsync + systemd timer)

Nous avons retenu l'approche **synchronisation périodique via `rsync` et minuterie `systemd`**, opérant exclusivement sur le réseau dédié **HA-SYNC** (`10.99.99.0/24`).

#### Sécurisation SSH (sur WEB2)
Une clé SSH dédiée SSH `ed25519` sans mot de passe a été générée sur **WEB1**. Côté **WEB2**, l'accès dans `/root/.ssh/authorized_keys` est restreint :
```text
from="10.99.99.21",no-port-forwarding,no-agent-forwarding,no-X11-forwarding,no-pty ssh-ed25519 AAAAC3... root@web1


Automation Systemd (sur WEB1)
Service (/etc/systemd/system/replica-data.service) :

Ini, TOML
[Unit]
Description=Replication rsync de /var/www/data vers WEB2
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/bin/rsync -az --delete -e "ssh -i /root/.ssh/id_rsync" /var/www/data/ root@10.99.99.22:/var/www/data/


Timer (/etc/systemd/system/replica-data.timer) :

Ini, TOML
[Unit]
Description=Timer de réplication /var/www/data toutes les minutes

[Timer]
OnCalendar=*:0/1
Persistent=true

[Install]
WantedBy=timers.target
```


### 5.3 Mesure du RPO réel (Recovery Point Objective)

La mesure du RPO a été effectuée en déposant un fichier via le portail web, puis en provoquant l'extinction brutale du serveur hôte d'écriture avant de vérifier la présence du document sur le second nœud.

| Essai | Fichier déposé | Serveur initial | Action de simulation de panne | Fichier présent sur WEB2 ? | RPO mesuré | Conformité (< 5 min) |
| :---: | :--- | :---: | :---: | :---: | :---: | :---: |
| **1** | `test-rpo-1.txt` | WEB1 | Extinction brutale (`poweroff`) | Oui | < 60 s | Validé |
| **2** | `test-rpo-2.txt` | WEB1 | Extinction brutale (`poweroff`) | Oui | < 60 s | Validé |
| **3** | `test-rpo-3.txt` | WEB1 | Extinction brutale (`poweroff`) | Oui | < 60 s | Validé |


Bilan RPO : Le RPO maximal mesuré est de 60 secondes (égal à la période du timer systemd).
Conformité : L'exigence contractuelle du cahier des charges (RPO < 5 minutes) est pleinement validée.


### 5.4 Arbitrage architectural et limites assumées

En réplication unidirectionnelle (WEB1 --> WEB2), tout fichier écrit sur WEB2 risquerait d'être écrasé par l'option --delete de rsync. 

Solution retenue : Modèle Actif/Passif --> Nous avons ajouté à notre block backend_web_servers sur les deux Haproxy afin de diriger prioritairement les requêtes de modification/dépôt (méthode HTTP POST) vers WEB1 : 

# --- Backend Web (WEB1 & WEB2) ---
backend web_servers
    balance roundrobin
    cookie SERVERID insert indirect nocache

    acl is_write method POST
    use-server web1 if is_write

    option httpchk GET /health.php
    http-check expect status 200

    server web1 192.168.20.21:80 check inter 2000ms fall 5 rise 2 cookie web1
    server web2 192.168.20.22:80 check inter 2000ms fall 5 rise 2 cookie web2 backup


Ainsi que : server web2 192.168.20.22:80 check inter 2s fall 3 rise 2 backup "backup pour web2 afin de garantit que WEB2 ne recevra les écritures que si WEB1 est totalement hors service.

Limite assumée : En cas de panne de WEB1, HAProxy bascule les requêtes POST sur WEB2 (backup). Les fichiers déposés sur WEB2 pendant la période d'indisponibilité devront faire l'objet d'une resynchronisation manuelle vers WEB1 (WEB2 -> WEB1) avant le redémarrage de la minuterie systemd sur WEB1.