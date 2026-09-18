#!/usr/bin/env bash
#===============================================================================
# vbox-create-lab.sh : cree la maquette du TP Haute Disponibilite
#
# A executer SUR L'HOTE, apres avoir prepare une VM gabarit nommee "DEBIAN-BASE"
# (Debian minimal, socle installe, ETEINTE, non declonee).
#
#   ./vbox-create-lab.sh                    # clone les 5 VM et configure le reseau
#   ./vbox-create-lab.sh --reseau           # (re)configure uniquement le reseau
#   ./vbox-create-lab.sh --demarrer [type]  # demarre les 5 VM (gui par defaut,
#                                           # ou headless, ou separate)
#   ./vbox-create-lab.sh --arreter          # extinction propre des 5 VM
#   ./vbox-create-lab.sh --detruire         # supprime les 5 VM du TP
#
# Deux variables independantes. PROFIL dimensionne LES QUATRE SERVEURS,
# CLIENT dimensionne LE POSTE CLIENT. Elles se combinent librement et
# fonctionnent avec tous les modes ci-dessus.
#
#   PROFIL=confort  (defaut)  serveurs a 1 Go    -> poste hote de 16 Go et plus
#   PROFIL=mini               serveurs a 512 Mo  -> poste hote de 8 Go
#
#   CLIENT=console  (defaut)  client 1 Go, 1 CPU, video 16 Mo
#   CLIENT=graphique          client 4 Go (2 Go si PROFIL=mini), 2 CPU,
#                             video 128 Mo, controleur VMSVGA
#
# Totaux : mini+console 3 Go | mini+graphique 4 Go
#          confort+console 5 Go | confort+graphique 8 Go
#
#   ex : CLIENT=graphique ./vbox-create-lab.sh
#        PROFIL=mini CLIENT=graphique ./vbox-create-lab.sh
#        CLIENT=graphique ./vbox-create-lab.sh --reseau   # redimensionne seul
#
# ATTENTION : CLIENT=graphique DIMENSIONNE la VM mais n'installe PAS le bureau.
# La commande apt a passer dans la VM est rappelee en fin d'execution.
#
# ATTENTION : --detruire supprime definitivement les VM LB1, LB2, WEB1, WEB2 et
# CLIENT ainsi que leurs disques. Une confirmation est demandee.
#
# Ce script ne dispense PAS du declonage a faire dans chaque VM (hostname,
# machine-id, cles SSH) : c'est un apprentissage a part entiere (phase 0.3).
#===============================================================================
set -euo pipefail

GABARIT="DEBIAN-BASE"
VMS=(LB1 LB2 WEB1 WEB2 CLIENT)

# --- Profil memoire ----------------------------------------------------------
# Par defaut le profil confortable, adapte a un poste de 16 Go ou plus.
# Sur un poste a 8 Go : PROFIL=mini ./vbox-create-lab.sh
# PROFIL ne dimensionne que les QUATRE SERVEURS.
PROFIL="${PROFIL:-confort}"
if [ "$PROFIL" = "mini" ]; then
    RAM_SERVEUR=512
else
    RAM_SERVEUR=1024
fi

# --- Poste client : console ou graphique -------------------------------------
# La VM CLIENT est dimensionnee par le type de poste retenu, pas par PROFIL :
# un client en console n'a aucun besoin de 4 Go, meme sur une machine large.
#
# CLIENT=graphique porte la memoire video a 128 Mo et fixe le controleur VMSVGA,
# celui que Debian sait piloter. Avec les 16 Mo par defaut, XFCE demarre mais
# reste bride en resolution.
#
# Le script ne peut PAS installer le bureau depuis l'hote : la commande apt a
# passer DANS la VM est rappelee en fin d'execution.
CLIENT="${CLIENT:-console}"
CTRL_CLIENT=vmsvga
if [ "$CLIENT" = "graphique" ]; then
    VRAM_CLIENT=128 ; CPUS_CLIENT=2
    [ "$PROFIL" = "mini" ] && RAM_CLIENT=2048 || RAM_CLIENT=4096
else
    VRAM_CLIENT=16  ; CPUS_CLIENT=1 ; RAM_CLIENT=1024
fi

vb() { VBoxManage "$@"; }

existe() { vb list vms | grep -q "\"$1\""; }

#-------------------------------------------------------------------------------
configurer_reseau() {
    echo ">>> Configuration des adaptateurs reseau"
    echo "    PROFIL=$PROFIL  -> 4 serveurs a ${RAM_SERVEUR} Mo"
    echo "    CLIENT=$CLIENT  -> poste client a ${RAM_CLIENT} Mo," \
         "${CPUS_CLIENT} CPU, video ${VRAM_CLIENT} Mo"

    # Les repartiteurs voient les trois reseaux internes.
    for vm in LB1 LB2; do
        existe "$vm" || { echo "  ! $vm absente, ignoree"; continue; }
        vb modifyvm "$vm" \
            --nic1 nat \
            --nic2 intnet --intnet2 HA-LAN  --nicpromisc2 allow-all \
            --nic3 intnet --intnet3 HA-DMZ  --nicpromisc3 allow-all \
            --nic4 intnet --intnet4 HA-SYNC --nicpromisc4 allow-all \
            --memory $RAM_SERVEUR --cpus 1
        echo "  $vm : NAT + HA-LAN + HA-DMZ + HA-SYNC"
    done

    # Les serveurs applicatifs ne sont PAS sur le LAN utilisateurs : ils ne sont
    # joignables qu'a travers les repartiteurs. C'est le principe de la DMZ.
    for vm in WEB1 WEB2; do
        existe "$vm" || { echo "  ! $vm absente, ignoree"; continue; }
        vb modifyvm "$vm" \
            --nic1 nat \
            --nic2 intnet --intnet2 HA-DMZ  --nicpromisc2 allow-all \
            --nic3 intnet --intnet3 HA-SYNC --nicpromisc3 allow-all \
            --nic4 none \
            --memory $RAM_SERVEUR --cpus 1
        echo "  $vm : NAT + HA-DMZ + HA-SYNC   (NAT a retirer en phase 6)"
    done

    if existe CLIENT; then
        vb modifyvm CLIENT \
            --nic1 nat \
            --nic2 intnet --intnet2 HA-LAN --nicpromisc2 allow-all \
            --nic3 none --nic4 none \
            --memory $RAM_CLIENT --cpus $CPUS_CLIENT \
            --vram $VRAM_CLIENT --graphicscontroller $CTRL_CLIENT
        echo "  CLIENT : NAT + HA-LAN   (poste $CLIENT, ${RAM_CLIENT} Mo, video ${VRAM_CLIENT} Mo)"
    fi

    # Les quatre serveurs n'ont pas d'affichage a piloter : on ne leur laisse
    # que le strict minimum de memoire video.
    for vm in LB1 LB2 WEB1 WEB2; do
        existe "$vm" && vb modifyvm "$vm" --vram 16
    done

    cat <<'EOF'

  RAPPEL, le mode promiscuite est regle sur "allow-all" sur tous les reseaux
  internes. Sans cela, les annonces multicast de VRRP (224.0.0.18) peuvent etre
  filtrees par le commutateur virtuel : les deux noeuds ne se voient pas et se
  declarent tous les deux MASTER. C'est le symptome n.1 des TP VRRP sous
  VirtualBox, et il coute generalement une demi-journee a diagnostiquer.
EOF
}

#-------------------------------------------------------------------------------
cloner() {
    existe "$GABARIT" || {
        echo "ERREUR : la VM gabarit '$GABARIT' est introuvable." >&2
        echo "Creez-la d'abord (Debian minimal + socle), puis eteignez-la." >&2
        exit 1
    }

    echo ">>> Clonage depuis $GABARIT"
    for vm in "${VMS[@]}"; do
        if existe "$vm"; then
            echo "  $vm existe deja, clonage ignore"
            continue
        fi
        # --mode all + --options keepdisknames non utilises volontairement :
        # on veut des disques et des adresses MAC NEUFS pour chaque clone.
        vb clonevm "$GABARIT" --name "$vm" --register --mode machine
        echo "  $vm creee"
    done
    echo
    echo "  Les adresses MAC sont regenerees par VBoxManage lors du clonage."
    echo "  Le declonage INTERNE (hostname, machine-id, cles SSH) reste a votre"
    echo "  charge : voir phase 0.3 de l'enonce."
}

#-------------------------------------------------------------------------------
# Demarrage / arret de la maquette.
#   headless : aucune fenetre, on administre en SSH depuis l'hote. Le plus leger.
#   gui      : une fenetre VirtualBox par VM. Indispensable au premier demarrage
#              (pas encore de reseau ni de SSH) et pour un poste client graphique.
demarrer() {
    local type="${1:-gui}"
    case "$type" in
        gui|headless|separate) ;;
        *) echo "Type d'affichage inconnu : $type (attendu : gui, headless, separate)" >&2
           exit 1 ;;
    esac
    echo ">>> Demarrage de la maquette en mode $type"
    # Ordre volontaire : les serveurs d'abord, le client en dernier, pour que le
    # service reponde deja quand la sonde de disponibilite demarre.
    for vm in WEB1 WEB2 LB1 LB2 CLIENT; do
        existe "$vm" || { echo "  ! $vm absente, ignoree"; continue; }
        if vb list runningvms | grep -q "\"$vm\""; then
            echo "  $vm deja demarree"
        else
            vb startvm "$vm" --type "$type" >/dev/null && echo "  $vm demarree"
            sleep 2      # evite de saturer l'hote par 5 demarrages simultanes
        fi
    done
}

arreter() {
    echo ">>> Extinction propre de la maquette"
    for vm in CLIENT LB2 LB1 WEB2 WEB1; do
        if vb list runningvms | grep -q "\"$vm\""; then
            vb controlvm "$vm" acpipowerbutton && echo "  $vm : extinction demandee"
        else
            echo "  $vm deja arretee"
        fi
    done
    echo
    echo "  acpipowerbutton demande un arret PROPRE au systeme invite."
    echo "  Ne pas confondre avec poweroff, qui coupe l'alimentation et sert"
    echo "  justement a simuler une panne materielle en phase 7."
}

#-------------------------------------------------------------------------------
detruire() {
    echo "Cette operation va SUPPRIMER definitivement les VM suivantes"
    echo "ainsi que leurs disques : ${VMS[*]}"
    read -r -p "Taper exactement SUPPRIMER pour confirmer : " reponse
    [ "$reponse" = "SUPPRIMER" ] || { echo "Annule."; exit 1; }

    for vm in "${VMS[@]}"; do
        existe "$vm" || continue
        vb controlvm "$vm" poweroff 2>/dev/null || true
        sleep 1
        vb unregistervm "$vm" --delete
        echo "  $vm supprimee"
    done
}

#-------------------------------------------------------------------------------
recapitulatif() {
    cat <<EOF

===============================================================================
 MAQUETTE PRETE, etapes suivantes
===============================================================================
 0. Demarrer les 5 VM :
      ./vbox-create-lab.sh --demarrer            # fenetres VirtualBox (gui)
      ./vbox-create-lab.sh --demarrer headless   # sans fenetre, une fois le SSH pret
EOF

    if [ "$CLIENT" = "graphique" ]; then
        cat <<'EOF'

 0 bis. POSTE CLIENT GRAPHIQUE : la VM est dimensionnee (RAM, video, CPU) mais
        le bureau n'est PAS installe. Dans la VM CLIENT, une fois le reseau
        configure :

      sudo apt update
      sudo apt install --no-install-recommends xfce4 xfce4-terminal firefox-esr
      sudo systemctl set-default graphical.target
      sudo reboot

        Puis, pour un affichage a la bonne resolution et le presse-papier
        partage, installer les Additions invite VirtualBox :
      sudo apt install -y build-essential dkms linux-headers-$(uname -r)
        (menu Peripheriques > Inserer l'image CD des Additions invite)

        Le bureau sert a VOIR la chaine de certification de votre AC interne
        (phase 6.4) et le cookie de persistance (phase 4.2). La sonde de
        disponibilite, elle, tourne en console dans un terminal.
EOF
    fi

    cat <<'EOF'

 1. Sur chaque VM, effectuer le DECLONAGE (phase 0.3) :
      hostnamectl set-hostname <nom>   + /etc/hosts
      /etc/machine-id  (truncate + systemd-machine-id-setup)
      cles d'hote SSH  (rm /etc/ssh/ssh_host_* + dpkg-reconfigure openssh-server)

 2. Configurer l'adressage statique (phase 0.4) :
      LB1     192.168.10.11  192.168.20.11  10.99.99.11
      LB2     192.168.10.12  192.168.20.12  10.99.99.12
      WEB1                   192.168.20.21  10.99.99.21
      WEB2                   192.168.20.22  10.99.99.22
      CLIENT  192.168.10.50

 3. Verifier la correspondance adaptateur <-> interface : ip -br link
    (elle PEUT differer de enp0s3/8/9/10 selon le chipset emule)

 4. Synchroniser les horloges (chrony) sur les 5 VM.

 INJECTION DE PANNES (phase 7) :
   VBoxManage controlvm LB1 poweroff           # panne materielle brutale
   VBoxManage controlvm LB1 pause              # machine gelee (panne "molle")
   VBoxManage controlvm LB1 setlinkstate2 off  # debranche le cable HA-LAN
   VBoxManage controlvm LB1 setlinkstate4 off  # coupe HA-SYNC
===============================================================================
EOF
}

#-------------------------------------------------------------------------------
case "${1:-}" in
    --reseau)    configurer_reseau ;;
    --demarrer)  demarrer "${2:-gui}" ;;
    --arreter)   arreter ;;
    --detruire)  detruire ;;
    --aide|-h)   sed -n '2,40p' "$0" ;;
    *)           cloner; configurer_reseau; recapitulatif ;;
esac
