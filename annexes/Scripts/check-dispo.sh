#!/usr/bin/env bash
#===============================================================================
# check-dispo.sh : Sonde de disponibilité pour le TP Haute Disponibilité
#
# Interroge une URL à intervalle régulier, journalise chaque requête en CSV, et
# produit un bilan à l'arrêt (Ctrl+C) : taux de disponibilité, plus longue
# interruption (= RTO observé), répartition entre les serveurs.
#
# Usage :
#   ./check-dispo.sh [URL] [INTERVALLE_SECONDES] [FICHIER_CSV]
#
# Exemples :
#   ./check-dispo.sh                                   # VIP, 1 requête / 200 ms
#   ./check-dispo.sh https://portail.novasante.lan/ 0.2
#   ./check-dispo.sh http://192.168.20.21/ 0.5 mesures/web1-direct.csv
#
# Le CSV produit est un LIVRABLE : ne le retouchez pas, versionnez-le tel quel.
#===============================================================================
set -u

# Formatage numerique en C : sur un systeme en francais, LC_NUMERIC attend une
# VIRGULE decimale et printf rejette « 0.969 » (« nombre non valable »), ce qui
# corrompt silencieusement le CSV. Un journal de mesures doit rester
# machine-lisible quelle que soit la langue du poste.
export LC_ALL=C

URL="${1:-http://192.168.10.100/}"
INTERVALLE="${2:-0.2}"
CSV="${3:-mesures/dispo-$(date +%Y%m%d-%H%M%S).csv}"

ENTETES=$(mktemp) ; CORPS=$(mktemp)
trap 'rm -f "$ENTETES" "$CORPS"' EXIT

mkdir -p "$(dirname "$CSV")"
echo "horodatage;code_http;duree_ms;serveur" > "$CSV"

#-------------------------------------------------------------------------------
# Bilan affiché à l'arrêt (Ctrl+C). Tout est recalculé depuis le CSV : si vous
# perdez le terminal, relancez juste l'analyse avec l'option --bilan.
#-------------------------------------------------------------------------------
bilan() {
    printf '\n\n'
    awk -F';' -v itv="$INTERVALLE" -v url="$URL" '
        NR == 1 { next }
        {
            total++
            if ($2 ~ /^[23]/) {
                ok++
                # Moyenne calculee sur les seules requetes ABOUTIES : inclure
                # les requetes en timeout (2000 ms chacune) degraderait le temps
                # de reponse alors que ces requetes ne sont pas servies du tout.
                # On mesure une chose a la fois.
                # (Pas d apostrophe dans ce bloc : il est entre quotes simples.)
                duree_totale += $3
                if (coupure > 0) {
                    if (coupure > max_coupure) max_coupure = coupure
                    coupure = 0
                }
            } else {
                ko++
                coupure++
                nb_coupures_vu = 1
                if (premiere == "") premiere = $1
                derniere = $1
                codes[$2]++
            }
            if ($4 != "?" && $4 != "") serveurs[$4]++
        }
        END {
            if (coupure > max_coupure) max_coupure = coupure
            if (total == 0) { print "Aucune mesure." ; exit }

            printf "===============================================================\n"
            printf " BILAN DE DISPONIBILITE, %s\n", url
            printf "===============================================================\n"
            printf " Requetes emises        : %d (1 toutes les %s s)\n", total, itv
            printf " Reussies / en echec    : %d / %d\n", ok, ko
            printf " TAUX DE DISPONIBILITE  : %.3f %%\n", ok * 100 / total
            printf " Temps de reponse moyen : %.0f ms (sur les requetes abouties)\n", \
                   (ok ? duree_totale / ok : 0)
            printf "---------------------------------------------------------------\n"
            if (ko > 0) {
                printf " Plus longue interruption : %d requetes consecutives\n", max_coupure
                printf " RTO OBSERVE              : ~%.1f s\n", max_coupure * itv
                printf " Premiere erreur          : %s\n", premiere
                printf " Derniere erreur          : %s\n", derniere
                printf " Codes en echec           :"
                for (c in codes) printf " %s(x%d)", (c == "000" ? "injoignable" : c), codes[c]
                printf "\n"
            } else {
                printf " AUCUNE INTERRUPTION, 100.000 %% de disponibilite\n"
            }
            printf "---------------------------------------------------------------\n"
            printf " Repartition de charge (sur les %d requetes servies) :\n", ok
            for (s in serveurs)
                printf "   %-14s %6d requetes (%.1f %%)\n", \
                       s, serveurs[s], (ok ? serveurs[s] * 100 / ok : 0)
            printf "===============================================================\n"
        }' "$CSV"
    printf '\nJournal brut : %s\n' "$CSV"
    exit 0
}
trap bilan INT TERM

#-------------------------------------------------------------------------------
# Mode analyse seule : ./check-dispo.sh --bilan mesures/xxx.csv [intervalle]
#-------------------------------------------------------------------------------
if [ "$URL" = "--bilan" ]; then
    CSV="${2:?indiquez le fichier CSV à analyser}"
    INTERVALLE="${3:-0.2}"
    URL="(relecture de $CSV)"
    bilan
fi

echo "Sonde en cours sur $URL, 1 requete toutes les $INTERVALLE s"
echo "Journal : $CSV"
echo "Ctrl+C pour arreter et afficher le bilan."
echo

while true; do
    # --max-time 2 : au-dela, on considere la requete perdue (coherent avec un RTO < 30 s)
    # -k accepte car en phase 6 l'AC interne n'est pas encore installee sur le CLIENT ;
    #    retirez-le une fois l'AC installee, c'est justement le point de controle 6.4.
    reponse=$(curl -s -k -o "$CORPS" -D "$ENTETES" -w '%{http_code};%{time_total}' \
                   --max-time 2 "$URL" 2>/dev/null) || reponse="000;2.000"

    code="${reponse%%;*}"
    duree="${reponse##*;}"
    serveur=$(awk 'tolower($1) == "x-served-by:" { print $2 }' "$ENTETES" 2>/dev/null | tr -d '\r' | head -1)

    # La conversion en millisecondes est faite par awk (et injectee avec %s) :
    # le printf du shell ne manipule jamais de decimal, donc pas de piege de locale.
    duree_ms=$(awk -v d="$duree" 'BEGIN { printf "%.0f", d * 1000 }')

    printf '%s;%s;%s;%s\n' \
        "$(date +%FT%T.%3N)" \
        "$code" \
        "$duree_ms" \
        "${serveur:-?}" >> "$CSV"

    # Retour visuel immediat : un point = OK, un X = echec.
    if [ "${code:0:1}" = "2" ] || [ "${code:0:1}" = "3" ]; then
        printf '.'
    else
        printf '\033[31mX\033[0m'
    fi

    sleep "$INTERVALLE"
done
