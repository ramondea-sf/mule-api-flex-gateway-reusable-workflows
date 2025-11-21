#!/bin/bash

# Script para registrar e fazer deploy de API no Flex Gateway
# Uso: ./deploy-api.sh <api-name> <api-version> <environment> <gateway-id> <gateway-version> <gateway-label>
#
# Este script:
# 1. Registra a API no API Manager (api-mgr api manage)
# 2. Faz o deploy no Flex Gateway (api-mgr api deploy)

set -e

API_NAME=$1
API_VERSION=$2
ENVIRONMENT=$3
GATEWAY_ID=$4
GATEWAY_VERSION=$5
GATEWAY_LABEL=$6

echo "=================================================="
echo "🚀 Deploy da API no Flex Gateway"
echo "=================================================="
echo "API: $API_NAME"
echo "Versão da especificação: $API_VERSION"
echo "Ambiente: $ENVIRONMENT"
echo "Gateway ID: $GATEWAY_ID"
echo "Gateway Version: $GATEWAY_VERSION"
echo "Gateway Label: $GATEWAY_LABEL"
echo ""

# Ler configurações
CONFIG_FILE="api/api-config.yaml"
ENV_FILE="api/${ENVIRONMENT}.yaml"

# Verificar se arquivo de ambiente existe
if [ ! -f "$ENV_FILE" ]; then
    echo "❌ Erro: Arquivo de ambiente não encontrado: $ENV_FILE"
    exit 1
fi

# Extrair configurações GLOBAIS (do api-config.yaml)
ORG_ID=$(yq eval '.organizationId' $CONFIG_FILE)
PROJECT_ACRONYM=$(yq eval '.api.projectAcronym' $CONFIG_FILE)
PATH_STRATEGY=$(yq eval '.version.pathStrategy' $CONFIG_FILE)

# Extrair configurações ESPECÍFICAS do AMBIENTE (do arquivo ${ENVIRONMENT}.yaml)
ENV_ID=$(yq eval ".environment.environmentId" $ENV_FILE)
UPSTREAM_URI=$(yq eval ".environment.upstreamUri" $ENV_FILE)
BASE_PATH=$(yq eval ".environment.basePath" $ENV_FILE)

# Extrair configurações do Gateway
GATEWAY_SCHEMA=$(yq eval ".environment.gateway.schema" $ENV_FILE)
GATEWAY_PORT=$(yq eval ".environment.gateway.port" $ENV_FILE)
GATEWAY_TLS_CONTEXT=$(yq eval ".environment.gateway.tlsContextId" $ENV_FILE)

# Ler informações do Exchange (geradas pelo script anterior)
GROUP_ID=$(cat /tmp/exchange-group-id.txt)
ASSET_ID=$(cat /tmp/exchange-asset-id.txt)
DEPLOY_VERSION=$(cat /tmp/version-to-deploy.txt)

# ============================================================================
# DEBUG: Mostrar todas as variáveis
# ============================================================================
echo ""
echo "=================================================="
echo "🔍 DEBUG - Variáveis de Deploy"
echo "=================================================="
echo "📁 Arquivos de configuração:"
echo "   CONFIG_FILE: $CONFIG_FILE"
echo "   ENV_FILE: $ENV_FILE"
echo ""
echo "📦 Informações da API:"
echo "   API_NAME: $API_NAME"
echo "   API_VERSION (spec): $API_VERSION"
echo "   DEPLOY_VERSION (a deployar): $DEPLOY_VERSION"
echo ""
echo "🏢 Anypoint Platform:"
echo "   ORG_ID: $ORG_ID"
echo "   ENV_ID: $ENV_ID"
echo "   ENVIRONMENT: $ENVIRONMENT"
echo ""
echo "📦 Exchange Asset:"
echo "   GROUP_ID: $GROUP_ID"
echo "   ASSET_ID: $ASSET_ID"
echo "   DEPLOY_VERSION: $DEPLOY_VERSION"
echo ""
echo "🌐 Configurações da API:"
echo "   UPSTREAM_URI: $UPSTREAM_URI"
echo "   BASE_PATH: $BASE_PATH"
echo "   PATH_STRATEGY: $PATH_STRATEGY"
echo "   PROJECT_ACRONYM: $PROJECT_ACRONYM"
echo ""
echo "🔌 Configurações do Gateway:"
echo "   GATEWAY_ID: $GATEWAY_ID"
echo "   GATEWAY_VERSION: $GATEWAY_VERSION"
echo "   GATEWAY_LABEL: $GATEWAY_LABEL"
echo "   GATEWAY_SCHEMA: $GATEWAY_SCHEMA"
echo "   GATEWAY_PORT: $GATEWAY_PORT"
echo "   GATEWAY_TLS_CONTEXT: $GATEWAY_TLS_CONTEXT"
echo ""
echo "=================================================="
echo ""

# Construir o path exposto baseado na estratégia de versionamento
case $PATH_STRATEGY in
    "major")
        VERSION_PATH="v$(echo $DEPLOY_VERSION | cut -d'.' -f1)"
        ;;
    "major-minor")
        VERSION_PATH="v$(echo $DEPLOY_VERSION | cut -d'.' -f1,2 | tr '.' '_')"
        ;;
    "full")
        VERSION_PATH="v$(echo $DEPLOY_VERSION | tr '.' '_')"
        ;;
    "none")
        VERSION_PATH=""
        ;;
    *)
        VERSION_PATH="v$(echo $DEPLOY_VERSION | cut -d'.' -f1)"
        ;;
esac

# Construir o path final: /api/{acronym}/{version}/{base-path}
if [ -n "$VERSION_PATH" ]; then
    EXPOSED_PATH="/api/$(echo $PROJECT_ACRONYM | tr '[:upper:]' '[:lower:]')/$VERSION_PATH$BASE_PATH"
else
    EXPOSED_PATH="/api/$(echo $PROJECT_ACRONYM | tr '[:upper:]' '[:lower:]')$BASE_PATH"
fi

echo ""
echo "=================================================="
echo "✅ Path Final Calculado"
echo "=================================================="
echo "   Estratégia: $PATH_STRATEGY"
echo "   Versão: $DEPLOY_VERSION"
echo "   VERSION_PATH: $VERSION_PATH"
echo "   PROJECT_ACRONYM: $(echo $PROJECT_ACRONYM | tr '[:upper:]' '[:lower:]')"
echo "   BASE_PATH: $BASE_PATH"
echo ""
echo "🌐 PATH EXPOSTO FINAL:"
echo "   $EXPOSED_PATH"
echo "=================================================="
echo ""

# ============================================================================
# PASSO 1: REGISTRAR API NO API MANAGER
# ============================================================================
echo "=================================================="
echo "📝 PASSO 1: Registrar API no API Manager"
echo "=================================================="

INSTANCE_LABEL="$GATEWAY_LABEL"

# Construir parâmetro TLS se necessário
TLS_PARAM=""
if [ "$GATEWAY_SCHEMA" == "https" ] && [ -n "$GATEWAY_TLS_CONTEXT" ] && [ "$GATEWAY_TLS_CONTEXT" != "null" ] && [ "$GATEWAY_TLS_CONTEXT" != "" ]; then
  TLS_PARAM="--tlsContextId $GATEWAY_TLS_CONTEXT"
  echo "🔒 TLS Context configurado: $GATEWAY_TLS_CONTEXT"
fi

echo "📝 Registrando API..."
echo "   Asset ID: $ASSET_ID"
echo "   Versão: $DEPLOY_VERSION"
echo "   Label: $INSTANCE_LABEL"
echo "   Schema: $GATEWAY_SCHEMA"
echo "   Port: $GATEWAY_PORT"
echo "   Upstream URI: $UPSTREAM_URI"
echo "   Path: $EXPOSED_PATH"
echo ""

# Registrar a API usando a sintaxe correta para Flex Gateway
RESULT=$(anypoint-cli-v4 api-mgr api manage "$ASSET_ID" "$DEPLOY_VERSION" \
    --client_id "$ANYPOINT_CLIENT_ID" \
    --client_secret "$ANYPOINT_CLIENT_SECRET" \
    --organization "$ORG_ID" \
    --environment "$ENV_ID" \
    --isFlex \
    --withProxy \
    --deploymentType hybrid \
    --scheme "$GATEWAY_SCHEMA" \
    --port "$GATEWAY_PORT" \
    --uri "$UPSTREAM_URI" \
    --path "$EXPOSED_PATH" \
    --apiInstanceLabel "$INSTANCE_LABEL" \
    $TLS_PARAM \
    --output json 2>&1)

echo "📋 Resultado do registro:"
echo "$RESULT"
echo ""

# Extrair API ID do resultado
# Formato esperado: {"message": "Created new API with ID: 20614056"}
API_ID=$(echo "$RESULT" | grep -oP 'ID:\s*\K[0-9]+')

# Se não encontrou, tentar via jq
if [ -z "$API_ID" ]; then
    API_ID=$(echo "$RESULT" | jq -r '.id // empty' 2>/dev/null)
fi

if [ -z "$API_ID" ] || [ "$API_ID" == "null" ]; then
    echo "❌ Erro ao registrar API no API Manager"
    echo ""
    echo "⚠️  Verifique se:"
    echo "   1. Os IDs de organização ($ORG_ID) e ambiente ($ENV_ID) estão corretos"
    echo "   2. A Connected App tem permissões suficientes"
    echo "   3. O asset $ASSET_ID:$DEPLOY_VERSION existe no Exchange"
    exit 1
fi

echo "✅ API registrada com sucesso!"
echo "📋 API ID: $API_ID"
echo ""

# ============================================================================
# PASSO 2: FAZER DEPLOY NO FLEX GATEWAY
# ============================================================================
echo "=================================================="
echo "🚀 PASSO 2: Deploy no Flex Gateway"
echo "=================================================="
echo "API ID: $API_ID"
echo "Gateway ID: $GATEWAY_ID"
echo "Gateway Version: $GATEWAY_VERSION"
echo "Environment: $ENV_ID"
echo ""

echo "🔨 Executando deploy..."
DEPLOY_RESULT=$(anypoint-cli-v4 api-mgr api deploy "$API_ID" \
    --client_id "$ANYPOINT_CLIENT_ID" \
    --client_secret "$ANYPOINT_CLIENT_SECRET" \
    --organization "$ORG_ID" \
    --environment "$ENV_ID" \
    --target "$GATEWAY_ID" \
    --gatewayVersion "$GATEWAY_VERSION" \
    --output json 2>&1 || echo '{"error": true}')

echo "📋 Resultado do deploy:"
echo "$DEPLOY_RESULT"
echo ""

# Verificar se houve erro no deploy
if echo "$DEPLOY_RESULT" | grep -qi "error\|failed\|exception"; then
    echo "⚠️  Possível erro detectado no deploy"
    echo ""
    echo "⚠️  Verifique se:"
    echo "   1. O Gateway ID $GATEWAY_ID está correto e online"
    echo "   2. A versão do gateway $GATEWAY_VERSION é compatível"
    echo "   3. Não há conflitos de configuração"
    echo ""
    echo "ℹ️  Em alguns casos, o deploy pode ser bem-sucedido mesmo com avisos"
    echo "   Verifique o API Manager para confirmar o status"
else
    echo "✅ Deploy executado com sucesso!"
fi

# Salvar informações para próximos jobs
echo "$API_ID" > /tmp/api-id.txt
echo "$EXPOSED_PATH" > /tmp/exposed-path.txt
echo "$DEPLOY_VERSION" > /tmp/deployed-version.txt
echo "$GATEWAY_LABEL" > /tmp/gateway-label.txt

echo ""
echo "=================================================="
echo "✅ Deploy da API concluído"
echo "=================================================="
echo "API ID: $API_ID"
echo "Gateway Label: $GATEWAY_LABEL"
echo "Path exposto: $EXPOSED_PATH"
echo "Versão deployada: $DEPLOY_VERSION"
echo "Gateway ID: $GATEWAY_ID"
echo "=================================================="
echo ""
echo "📊 Próximos passos:"
echo "   1. Verificar status no API Manager"
echo "   2. Aplicar políticas (se necessário)"
echo "   3. Testar endpoint: $GATEWAY_SCHEMA://{gateway-url}$EXPOSED_PATH"
echo "=================================================="
