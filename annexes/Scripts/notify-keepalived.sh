#!/bin/bash
#===============================================================================
# notify-keepalived.sh : journalise chaque transition d'etat VRRP
#
# Emplacement : /etc/keepalived/notify.sh    (root:root, mode 0755)
# Appele par keepalived avec 4 arguments :
#   $1 = type       INSTANCE | GROUP
#   $2 = nom        VI_LAN, VI_DMZ, VG_PORTAIL...
#   $3 = etat       MASTER | BACKUP | FAULT | STOP
#   $4 = priorite
#
# Ce fichier de journal est votre PREUVE HORODATEE pour le proces-verbal de
# tests : il permet de dater a la milliseconde le moment ou le noeud a pris ou
# rendu la VIP, et de le corroborer avec le CSV de la sonde cote client.
#
# En production, c'est ici qu'on declencherait une alerte : toute transition
# NON PLANIFIEE doit reveiller quelqu'un. Une bascule silencieuse, c'est une
# redondance consommee sans que personne ne le sache : et la prochaine panne
# sera la panne totale.
#===============================================================================
set -u

TYPE="${1:-?}"
NOM="${2:-?}"
ETAT="${3:-?}"
PRIORITE="${4:-}"

JOURNAL="/var/log/tp-ha/vrrp-transitions.log"
mkdir -p "$(dirname "$JOURNAL")"

HORODATAGE=$(date --rfc-3339=ns)
MACHINE=$(hostname)

# 1) Journal local horodate a la nanoseconde
printf '%s  %-8s  %-12s  %-6s  prio=%-4s  hote=%s\n' \
    "$HORODATAGE" "$TYPE" "$NOM" "$ETAT" "${PRIORITE:--}" "$MACHINE" >> "$JOURNAL"

# 2) Syslog : remonte donc au collecteur central (phase 6.6)
logger -t keepalived-notify -p daemon.notice \
    "TRANSITION $TYPE $NOM -> $ETAT (priorite=${PRIORITE:--}) sur $MACHINE"

# 3) Actions liees a l'etat
case "$ETAT" in
    MASTER)
        # Ce noeud prend la main : on s'assure que le service tourne vraiment.
        systemctl is-active --quiet haproxy || systemctl start haproxy
        logger -t keepalived-notify -p daemon.warning \
            "$MACHINE devient MASTER pour $NOM, verification de HAProxy effectuee"
        # Extension E3 : reprise de la table de suivi de connexions
        # [ -x /etc/conntrackd/primary-backup.sh ] && /etc/conntrackd/primary-backup.sh primary
        ;;
    BACKUP)
        logger -t keepalived-notify -p daemon.notice \
            "$MACHINE passe en BACKUP pour $NOM"
        # [ -x /etc/conntrackd/primary-backup.sh ] && /etc/conntrackd/primary-backup.sh backup
        ;;
    FAULT)
        # Etat le plus important a tracer : le noeud s'est lui-meme declare
        # inapte (lien down, track_script en echec).
        logger -t keepalived-notify -p daemon.err \
            "$MACHINE en FAULT pour $NOM, investigation requise"
        # [ -x /etc/conntrackd/primary-backup.sh ] && /etc/conntrackd/primary-backup.sh fault
        ;;
    STOP)
        logger -t keepalived-notify -p daemon.notice "$MACHINE arrete VRRP pour $NOM"
        ;;
esac

exit 0
