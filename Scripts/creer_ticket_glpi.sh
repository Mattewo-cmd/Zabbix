#!/bin/bash

# 1. PARAMÈTRES ET CONFIGURATION
TITLE=$1
DATE_ALERTE=$2
REQUESTER_ID={ID_DEMANDEUR}
EVENT_ID=$3
ZABBIX_SEVERITY=$4

TOKEN_URL="https://{IP/FQDN_GLPI}/api.php/token"
TICKET_URL="https://{IP/FQDN_GLPI}/api.php/Assistance/Ticket"
CLIENT_ID="{CLIENT_ID}"
CLIENT_SECRET="{CLIENT_SECRET}"
APIUSERNAME="zabbix"
APIPASSWORD="{API_PASSWORD}"

# Variables Zabbix
ZABBIX_API_URL="https://{IP/FQDN_ZABBIX}/api_jsonrpc.php"
ZABBIX_API_TOKEN="{ZABBIX_API_TOKEN}"
GLPI_WEB_URL="https://{IP/FQDN_GLPI}/front/ticket.form.php?id="

# Calcul de la criticité selon la sévérité Zabbix
case "$ZABBIX_SEVERITY" in
    "Warning")
        URGENCY=2
        IMPACT=2
        ;;
    "Average")
        URGENCY=3
        IMPACT=3
        ;;
    "High")
        URGENCY=4
        IMPACT=4
        ;;
    "Disaster")
        URGENCY=5
        IMPACT=5
        ;;
esac

# 2. RÉCUPÉRATION DU TOKEN
RESPONSE=$(curl -k -s -X POST "$TOKEN_URL" \
  -d "grant_type=password" \
  -d "client_id=$CLIENT_ID" \
  -d "client_secret=$CLIENT_SECRET" \
  -d "username=$APIUSERNAME" \
  -d "password=$APIPASSWORD" \
  -d "scope=api")

ACCESS_TOKEN=$(echo "$RESPONSE" | jq -r .access_token)

if [ "$ACCESS_TOKEN" == "null" ] || [ -z "$ACCESS_TOKEN" ]; then
    echo "Erreur : $RESPONSE"
    exit 1
fi

# Création ticket
CREATION_RESP=$(curl -k -s -X POST "$TICKET_URL" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "'"$TITLE $DATE_ALERTE"'",
    "content": "'"$TITLE $DATE_ALERTE"'",
    "category": {
      "id": 36
    },
    "location": {
      "id": 31
    },
    "status": 1,
    "urgency": '$URGENCY',
    "impact": '$IMPACT'
  }')

TICKET_ID=$(echo "$CREATION_RESP" | jq -r .id)

if [ "$TICKET_ID" == "null" ] || [ -z "$TICKET_ID" ]; then
    echo "Erreur lors de la création du ticket : $CREATION_RESP"
    exit 1
fi

echo "Ticket créé avec l'ID: $TICKET_ID."

# Demandeur
curl -k -s -X POST "$TICKET_URL/$TICKET_ID/TeamMember" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "type": "User",
    "role": "requester",
    "id": '$REQUESTER_ID'
  }'

# Message Zabbix
if [ ! -z "$EVENT_ID" ] && [ "$EVENT_ID" != "{EVENT.ID}" ]; then
    URL_TICKET_COMPLET="${GLPI_WEB_URL}${TICKET_ID}"
    MESSAGE_ZABBIX="${URL_TICKET_COMPLET}"

    # On balance le jq directement dans le -d du curl
    curl -k -s -X POST "$ZABBIX_API_URL" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer $ZABBIX_API_TOKEN" \
      -d "$(jq -n \
        --arg ev_id "$EVENT_ID" \
        --arg msg "$MESSAGE_ZABBIX" \
        '{
          jsonrpc: "2.0",
          method: "event.acknowledge",
          params: {
            eventids: $ev_id,
            action: 6,
            message: $msg
          },
          id: 1
        }')" > /dev/null
fi

echo "Traitement terminé avec succès !"
