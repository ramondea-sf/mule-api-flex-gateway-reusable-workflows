#!/bin/bash

# Script para obter configuração do gateway dinamicamente via APIs
# Uso: ./get-gateway-config.sh <environment> <cluster> <is-public> <org-id>

set -e

ENVIRONMENT=$1
CLUSTER=$2
IS_PUBLIC=$3
ORG_ID=$4

echo "=================================================="
echo "🔍 Obtendo configuração do Gateway (Dinâmica)"
echo "=================================================="
echo "Ambiente: $ENVIRONMENT"
echo "Cluster: $CLUSTER"
echo "API Pública: $IS_PUBLIC"
echo "Organization ID: $ORG_ID"
echo ""

# Determinar o tipo de gateway baseado em isPublic
if [ "$IS_PUBLIC" == "true" ]; then
  GATEWAY_TYPE="dmz"
  GATEWAY_LABEL="$ENVIRONMENT - public"
  
  # Validar se o cluster suporta DMZ
  if [ "$CLUSTER" == "pix" ] || [ "$CLUSTER" == "pj" ]; then
    echo "❌ Erro: Clusters PIX e PJ não suportam APIs públicas (DMZ)"
    echo "   Altere isPublic para 'false' ou escolha outro cluster"
    exit 1
  fi
else
  GATEWAY_TYPE="back"
  GATEWAY_LABEL="$ENVIRONMENT - private"
fi

echo "📍 Tipo de Gateway: $GATEWAY_TYPE"
echo "🏷️  Label: $GATEWAY_LABEL"
echo ""

# ============================================================================
# PASSO 1: Obter Environment ID
# ============================================================================
echo "🔍 Passo 1: Obtendo ID do ambiente '$ENVIRONMENT'..."

ENV_LIST=$(anypoint-cli-v4 account environment list \
  --client_id "$ANYPOINT_CLIENT_ID" \
  --client_secret "$ANYPOINT_CLIENT_SECRET" \
  --output json 2>&1)

if [ $? -ne 0 ] || [ -z "$ENV_LIST" ]; then
  echo "❌ Erro ao listar ambientes"
  exit 1
fi

# Buscar environment ID pelo nome (case insensitive)
ENV_ID=$(echo "$ENV_LIST" | jq -r ".[] | select(.name | ascii_upcase == \"$(echo $ENVIRONMENT | tr '[:lower:]' '[:upper:]')\") | .id" 2>/dev/null | head -n 1)

if [ -z "$ENV_ID" ] || [ "$ENV_ID" == "null" ]; then
  echo "❌ Erro: Ambiente '$ENVIRONMENT' não encontrado"
  echo ""
  echo "Ambientes disponíveis:"
  echo "$ENV_LIST" | jq -r '.[].name' 2>/dev/null
  exit 1
fi

echo "✅ Environment ID: $ENV_ID"
echo ""

# ============================================================================
# PASSO 2: Construir nome do gateway baseado na convenção
# ============================================================================
echo "🔍 Passo 2: Construindo nome do gateway..."

# Naming convention para DEV
# Formato: hub-{cluster}-{tipo}-{ambiente-suffix}
case "$ENVIRONMENT|$CLUSTER|$GATEWAY_TYPE" in
  "dev|aws-rosa|back")
    GATEWAY_NAME="flex-demo"
    ;;
  "dev|aws-rosa|dmz")
    GATEWAY_NAME="hub-aws-front-d"
    ;;
  "dev|on-premise|back")
    GATEWAY_NAME="hub-onpre-back-d"
    ;;
  "dev|on-premise|dmz")
    GATEWAY_NAME="hub-onpre-front-d"
    ;;
  "dev|pix|back")
    GATEWAY_NAME="hub-pix-back-d"
    ;;
  "dev|pj|back")
    GATEWAY_NAME="hub-pj-back-d"
    ;;
  *)
    echo "❌ Erro: Naming convention não definida para: $ENVIRONMENT|$CLUSTER|$GATEWAY_TYPE"
    echo ""
    echo "💡 Por favor, configure o naming pattern para este ambiente/cluster"
    exit 1
    ;;
esac

echo "📋 Nome do gateway esperado: $GATEWAY_NAME"
echo ""

# ============================================================================
# PASSO 3: Buscar Gateway via API
# ============================================================================
echo "🔍 Passo 3: Buscando gateway '$GATEWAY_NAME'..."

GATEWAY_API_URL="https://anypoint.mulesoft.com/gatewaymanager/xapi/v1/organizations/$ORG_ID/environments/$ENV_ID/gateways?kind=selfManaged"

# Obter token de acesso
echo "Obtendo token de acesso..."
TOKEN_RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X POST "https://anypoint.mulesoft.com/accounts/api/v2/oauth2/token" \
  -H "Content-Type: application/json" \
  -d "{\"client_id\":\"$ANYPOINT_CLIENT_ID\",\"client_secret\":\"$ANYPOINT_CLIENT_SECRET\",\"grant_type\":\"client_credentials\"}")

HTTP_CODE=$(echo "$TOKEN_RESPONSE" | grep "HTTP_CODE:" | cut -d':' -f2)
TOKEN_BODY=$(echo "$TOKEN_RESPONSE" | grep -v "HTTP_CODE:")

echo "HTTP Status: $HTTP_CODE"

if [ -z "$TOKEN_BODY" ]; then
  echo "❌ Erro: Resposta vazia ao obter token"
  exit 1
fi

ACCESS_TOKEN=$(echo "$TOKEN_BODY" | jq -r '.access_token' 2>/dev/null)

if [ -z "$ACCESS_TOKEN" ] || [ "$ACCESS_TOKEN" == "null" ]; then
  echo "❌ Erro ao obter token de acesso"
  echo "Response: $TOKEN_BODY"
  exit 1
fi

echo "✅ Token obtido"

# Buscar gateways
echo "Buscando gateways no ambiente..."
GATEWAYS_RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X GET "$GATEWAY_API_URL" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json")

GATEWAYS_HTTP_CODE=$(echo "$GATEWAYS_RESPONSE" | grep "HTTP_CODE:" | cut -d':' -f2)
GATEWAYS_BODY=$(echo "$GATEWAYS_RESPONSE" | grep -v "HTTP_CODE:")

echo "HTTP Status: $GATEWAYS_HTTP_CODE"

if [ "$GATEWAYS_HTTP_CODE" != "200" ]; then
  echo "❌ Erro HTTP ao buscar gateways"
  echo "Response: $GATEWAYS_BODY"
  exit 1
fi

if [ -z "$GATEWAYS_BODY" ]; then
  echo "❌ Erro: Resposta vazia ao buscar gateways"
  exit 1
fi

echo "Primeiros 500 chars do response:"
echo "$GATEWAYS_BODY" | head -c 500
echo ""
echo ""

# Filtrar gateway por nome e status RUNNING
echo "Filtrando gateway '$GATEWAY_NAME'..."
GATEWAY_DATA=$(echo "$GATEWAYS_BODY" | jq ".content[] | select(.name == \"$GATEWAY_NAME\" and .status == \"RUNNING\")" 2>&1)
JQ_EXIT=$?

echo "jq exit code: $JQ_EXIT"
echo "Gateway data length: ${#GATEWAY_DATA}"
echo ""

if [ $JQ_EXIT -ne 0 ]; then
  echo "❌ Erro no jq"
  echo "jq output: $GATEWAY_DATA"
  exit 1
fi

if [ -z "$GATEWAY_DATA" ] || [ "$GATEWAY_DATA" == "null" ]; then
  echo "❌ Erro: Gateway '$GATEWAY_NAME' não encontrado ou não está RUNNING"
  echo ""
  echo "Gateways disponíveis:"
  echo "$GATEWAYS_BODY" | jq -r '.content[] | "\(.name) - Status: \(.status)"' 2>/dev/null
  exit 1
fi

GATEWAY_ID=$(echo "$GATEWAY_DATA" | jq -r '.id' 2>/dev/null)

echo "✅ Gateway encontrado!"
echo "   ID: $GATEWAY_ID"
echo "   Status: $(echo "$GATEWAY_DATA" | jq -r '.status' 2>/dev/null)"
echo ""

# ============================================================================
# PASSO 4: Obter versão do gateway
# ============================================================================
echo "🔍 Passo 4: Obtendo versão do gateway..."

REPLICAS_API_URL="https://anypoint.mulesoft.com/standalone/api/v1/organizations/$ORG_ID/environments/$ENV_ID/gateways/$GATEWAY_ID/replicas?pageNumber=0&pageSize=20&status=CONNECTED"

REPLICAS_RESPONSE=$(curl -s -X GET "$REPLICAS_API_URL" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json")

if [ $? -ne 0 ] || [ -z "$REPLICAS_RESPONSE" ]; then
  echo "❌ Erro ao buscar réplicas do gateway"
  exit 1
fi

# Obter todas as versões e pegar a mais alta
GATEWAY_VERSION=$(echo "$REPLICAS_RESPONSE" | jq -r '.gateway.versions[]' 2>/dev/null | sort -V | tail -n 1)

if [ -z "$GATEWAY_VERSION" ] || [ "$GATEWAY_VERSION" == "null" ]; then
  echo "❌ Erro ao obter versão do gateway"
  echo "Response: $REPLICAS_RESPONSE"
  exit 1
fi

echo "✅ Versão do gateway: $GATEWAY_VERSION"
echo ""

echo "=================================================="
echo "✅ Configuração do Gateway obtida"
echo "=================================================="
echo "Gateway ID: $GATEWAY_ID"
echo "Gateway Version: $GATEWAY_VERSION"
echo "Gateway Type: $GATEWAY_TYPE"
echo "Gateway Label: $GATEWAY_LABEL"
echo "=================================================="
echo ""

# Salvar outputs em arquivos temporários
echo "$GATEWAY_ID" > /tmp/gateway-id.txt
echo "$GATEWAY_VERSION" > /tmp/gateway-version.txt
echo "$GATEWAY_LABEL" > /tmp/gateway-label.txt
echo "$GATEWAY_TYPE" > /tmp/gateway-type.txt

