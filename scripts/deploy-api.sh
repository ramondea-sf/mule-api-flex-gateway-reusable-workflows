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

# Configurações do Upstream (backend)
UPSTREAM_URI=$(yq eval ".environment.upstream.uri" $ENV_FILE)
BASE_PATH=$(yq eval ".environment.upstream.basePath" $ENV_FILE)
OUTBOUND_TLS_CONTEXT=$(yq eval ".environment.upstream.outboundTlsContextId" $ENV_FILE)
OUTBOUND_SECRET_GROUP=$(yq eval ".environment.upstream.outboundSecretGroupId" $ENV_FILE)

# Configurações do Gateway (listener)
GATEWAY_SCHEMA=$(yq eval ".environment.gateway.schema" $ENV_FILE)
GATEWAY_PORT=$(yq eval ".environment.gateway.port" $ENV_FILE)
INBOUND_TLS_CONTEXT=$(yq eval ".environment.gateway.inboundTlsContextId" $ENV_FILE)
INBOUND_SECRET_GROUP=$(yq eval ".environment.gateway.inboundSecretGroupId" $ENV_FILE)

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
echo "   INBOUND_TLS_CONTEXT: $INBOUND_TLS_CONTEXT"
echo "   INBOUND_SECRET_GROUP: $INBOUND_SECRET_GROUP"
echo "   OUTBOUND_TLS_CONTEXT: $OUTBOUND_TLS_CONTEXT"
echo "   OUTBOUND_SECRET_GROUP: $OUTBOUND_SECRET_GROUP"
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
# PASSO 1: VERIFICAR SE API JÁ EXISTE
# ============================================================================
echo "=================================================="
echo "🔍 PASSO 1: Verificar se API já existe"
echo "=================================================="

INSTANCE_LABEL="$GATEWAY_LABEL"

echo "🔍 DEBUG - Parâmetros de busca:"
echo "   Asset ID: $ASSET_ID"
echo "   Environment: $ENVIRONMENT ($ENV_ID)"
echo "   Label esperado: $INSTANCE_LABEL"
echo "   Versão a deployar: $DEPLOY_VERSION"
echo ""

echo "Listando APIs do asset '$ASSET_ID' no ambiente '$ENVIRONMENT'..."
API_LIST=$(anypoint-cli-v4 api-mgr api list \
    --client_id "$ANYPOINT_CLIENT_ID" \
    --client_secret "$ANYPOINT_CLIENT_SECRET" \
    --organization "$ORG_ID" \
    --environment "$ENV_ID" \
    --assetId "$ASSET_ID" \
    --output json 2>&1 || echo "[]")

echo ""
echo "🔍 DEBUG - Output do comando api-mgr api list:"
echo "----------------------------------------"
echo "$API_LIST"
echo "----------------------------------------"
echo ""

# Verificar se é um array JSON válido
if ! echo "$API_LIST" | jq empty 2>/dev/null; then
    echo "⚠️  Resposta não é JSON válido. Definindo lista vazia."
    API_LIST="[]"
fi

echo "🔍 DEBUG - Estrutura do JSON:"
echo "$API_LIST" | jq '.' 2>/dev/null || echo "Não foi possível parsear JSON"
echo ""

echo "Buscando API com label: $INSTANCE_LABEL"

# Buscar API com o label específico
EXISTING_API=$(echo "$API_LIST" | jq ".assets[] | select(.instanceLabel==\"$INSTANCE_LABEL\")" 2>/dev/null | head -n 1)

echo "🔍 DEBUG - API encontrada (raw):"
echo "$EXISTING_API"
echo ""

if [ -n "$EXISTING_API" ] && [ "$EXISTING_API" != "null" ]; then
    API_ID=$(echo "$EXISTING_API" | jq -r '.id' 2>/dev/null)
    CURRENT_VERSION=$(echo "$EXISTING_API" | jq -r '.assetVersion' 2>/dev/null)
    
    echo "✅ API encontrada!"
    echo "   API ID: $API_ID"
    echo "   Versão atual: $CURRENT_VERSION"
    echo "   Versão a deployar: $DEPLOY_VERSION"
    echo ""
    
    if [ "$CURRENT_VERSION" == "$DEPLOY_VERSION" ]; then
        echo "✅ Versão já está deployada. Nenhuma atualização necessária."
        echo ""
        API_ACTION="skip"
    else
        echo "🔄 Versão diferente detectada. Será necessário atualizar a API."
        echo ""
        API_ACTION="edit"
    fi
else
    echo "ℹ️  API não encontrada com label '$INSTANCE_LABEL'. Será criada uma nova."
    echo ""
    echo "🔍 DEBUG - Labels disponíveis no ambiente:"
    echo "$API_LIST" | jq -r '.assets[]? | "  - \(.instanceLabel) (v\(.assetVersion))"' 2>/dev/null || echo "  Nenhuma API encontrada"
    echo ""
    API_ACTION="create"
fi

# ============================================================================
# PASSO 2: CONSTRUIR PARÂMETROS TLS/SECRET
# ============================================================================
echo "=================================================="
echo "🔧 PASSO 2: Construir parâmetros de configuração"
echo "=================================================="

# Construir parâmetros opcionais
OPTIONAL_PARAMS=""

if [ -n "$INBOUND_TLS_CONTEXT" ] && [ "$INBOUND_TLS_CONTEXT" != "null" ] && [ "$INBOUND_TLS_CONTEXT" != "" ]; then
  OPTIONAL_PARAMS="$OPTIONAL_PARAMS --inboundTlsContextId $INBOUND_TLS_CONTEXT"
  echo "🔒 Inbound TLS Context: $INBOUND_TLS_CONTEXT"
fi

if [ -n "$INBOUND_SECRET_GROUP" ] && [ "$INBOUND_SECRET_GROUP" != "null" ] && [ "$INBOUND_SECRET_GROUP" != "" ]; then
  OPTIONAL_PARAMS="$OPTIONAL_PARAMS --inboundSecretGroupId $INBOUND_SECRET_GROUP"
  echo "🔐 Inbound Secret Group: $INBOUND_SECRET_GROUP"
fi

if [ -n "$OUTBOUND_TLS_CONTEXT" ] && [ "$OUTBOUND_TLS_CONTEXT" != "null" ] && [ "$OUTBOUND_TLS_CONTEXT" != "" ]; then
  OPTIONAL_PARAMS="$OPTIONAL_PARAMS --outboundTlsContextId $OUTBOUND_TLS_CONTEXT"
  echo "🔒 Outbound TLS Context: $OUTBOUND_TLS_CONTEXT"
fi

if [ -n "$OUTBOUND_SECRET_GROUP" ] && [ "$OUTBOUND_SECRET_GROUP" != "null" ] && [ "$OUTBOUND_SECRET_GROUP" != "" ]; then
  OPTIONAL_PARAMS="$OPTIONAL_PARAMS --outboundSecretGroupId $OUTBOUND_SECRET_GROUP"
  echo "🔐 Outbound Secret Group: $OUTBOUND_SECRET_GROUP"
fi

echo ""

# ============================================================================
# PASSO 3: CRIAR OU ATUALIZAR API
# ============================================================================
if [ "$API_ACTION" == "skip" ]; then
    echo "=================================================="
    echo "✅ PASSO 3: API já está atualizada"
    echo "=================================================="
    echo "Nenhuma ação necessária. A versão $DEPLOY_VERSION já está deployada."
    echo ""
elif [ "$API_ACTION" == "create" ]; then
    # ========================================================================
    # CRIAR NOVA API (api-mgr api manage + api-mgr api deploy)
    # ========================================================================
    echo "=================================================="
    echo "📝 PASSO 3: Criar nova API no API Manager"
    echo "=================================================="
    
    echo "Configuração:"
    echo "   Asset ID: $ASSET_ID"
    echo "   Versão: $DEPLOY_VERSION"
    echo "   Label: $INSTANCE_LABEL"
    echo "   Schema: $GATEWAY_SCHEMA"
    echo "   Port: $GATEWAY_PORT"
    echo "   Upstream URI: $UPSTREAM_URI"
    echo "   Path: $EXPOSED_PATH"
    echo ""
    
    echo "🔨 Criando API no API Manager..."
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
        $OPTIONAL_PARAMS \
        --output json 2>&1)
    
    echo "📋 Resultado da criação:"
    echo "$RESULT"
    echo ""
    
    # Extrair API ID do resultado
    API_ID=$(echo "$RESULT" | grep -oP 'ID:\s*\K[0-9]+')
    
    if [ -z "$API_ID" ]; then
        API_ID=$(echo "$RESULT" | jq -r '.id // empty' 2>/dev/null)
    fi
    
    if [ -z "$API_ID" ] || [ "$API_ID" == "null" ]; then
        echo "❌ Erro ao criar API no API Manager"
        exit 1
    fi
    
    echo "✅ API criada com sucesso!"
    echo "📋 API ID: $API_ID"
    echo ""
    
    # ========================================================================
    # FAZER DEPLOY NO FLEX GATEWAY
    # ========================================================================
    echo "=================================================="
    echo "🚀 PASSO 4: Deploy no Flex Gateway"
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
    echo ""
    
elif [ "$API_ACTION" == "edit" ]; then
    # ========================================================================
    # ATUALIZAR API EXISTENTE (apenas api-mgr api edit)
    # ========================================================================
    echo "=================================================="
    echo "🔄 PASSO 3: Atualizar API existente no API Manager"
    echo "=================================================="
    
    echo "Configuração:"
    echo "   API ID: $API_ID"
    echo "   Nova Versão: $DEPLOY_VERSION"
    echo "   Label: $INSTANCE_LABEL"
    echo "   Schema: $GATEWAY_SCHEMA"
    echo "   Port: $GATEWAY_PORT"
    echo "   Upstream URI: $UPSTREAM_URI"
    echo "   Path: $EXPOSED_PATH"
    echo ""
    
    echo "🔨 Atualizando API..."
    RESULT=$(anypoint-cli-v4 api-mgr api edit "$API_ID" \
        --client_id "$ANYPOINT_CLIENT_ID" \
        --client_secret "$ANYPOINT_CLIENT_SECRET" \
        --organization "$ORG_ID" \
        --environment "$ENV_ID" \
        --assetVersion "$DEPLOY_VERSION" \
        --scheme "$GATEWAY_SCHEMA" \
        --port "$GATEWAY_PORT" \
        --uri "$UPSTREAM_URI" \
        --path "$EXPOSED_PATH" \
        $OPTIONAL_PARAMS \
        --output json 2>&1)
    
    echo "📋 Resultado da atualização:"
    echo "$RESULT"
    echo ""
    
    # Verificar se houve erro
    if echo "$RESULT" | grep -qi "error\|failed\|exception"; then
        echo "❌ Erro ao atualizar API"
        exit 1
    fi
    
    echo "✅ API atualizada com sucesso!"
    echo "📋 API ID: $API_ID"
    echo ""
    echo "ℹ️  O comando 'api-mgr api edit' já atualiza a API no gateway."
    echo "   Não é necessário executar 'api-mgr api deploy' novamente."
    echo ""
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
