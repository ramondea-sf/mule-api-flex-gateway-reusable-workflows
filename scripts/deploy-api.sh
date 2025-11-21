#!/bin/bash

# Script para registrar e fazer deploy de API no Flex Gateway
# Uso: ./deploy-api.sh <api-name> <api-version> <environment> <gateway-id> <gateway-version> <gateway-label>
#
# Este script:
# 1. Registra a API no API Manager (api-mgr:api:manage)
# 2. Faz o deploy no Flex Gateway (api-mgr:api:deploy)

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
DESTINATION_CLUSTER=$(yq eval '.api.destinationCluster' $CONFIG_FILE)
IS_PUBLIC=$(yq eval '.api.isPublic' $CONFIG_FILE)

# Extrair configurações ESPECÍFICAS do AMBIENTE (do arquivo ${ENVIRONMENT}.yaml)
ENV_ID=$(yq eval ".environment.environmentId" $ENV_FILE)
UPSTREAM_URI=$(yq eval ".environment.upstreamUri" $ENV_FILE)
BASE_PATH=$(yq eval ".environment.basePath" $ENV_FILE)

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
echo "🌐 Configurações de API:"
echo "   UPSTREAM_URI: $UPSTREAM_URI"
echo "   BASE_PATH: $BASE_PATH"
echo "   PATH_STRATEGY: $PATH_STRATEGY"
echo "   PROJECT_ACRONYM: $PROJECT_ACRONYM"
echo "   DESTINATION_CLUSTER: $DESTINATION_CLUSTER"
echo "   IS_PUBLIC: $IS_PUBLIC"
echo ""
echo "🔌 Configurações de Gateway:"
echo "   GATEWAY_ID: $GATEWAY_ID"
echo "   GATEWAY_VERSION: $GATEWAY_VERSION"
echo "   GATEWAY_LABEL: $GATEWAY_LABEL"
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

# Verificar se a API já existe com este label
INSTANCE_LABEL="$GATEWAY_LABEL"
echo "🔍 Verificando se API já existe com label: $INSTANCE_LABEL"

API_LIST=$(anypoint-cli-v4 api-mgr api list \
    --client_id "$ANYPOINT_CLIENT_ID" \
    --client_secret "$ANYPOINT_CLIENT_SECRET" \
    --organization "$ORG_ID" \
    --environment "$ENV_ID" \
    --output json 2>/dev/null || echo "[]")

EXISTING_API_ID=$(echo "$API_LIST" | jq -r ".assets[] | select(.instanceLabel==\"$INSTANCE_LABEL\") | .id" 2>/dev/null | head -n 1)

if [ -n "$EXISTING_API_ID" ] && [ "$EXISTING_API_ID" != "null" ]; then
    # API já existe, verificar versão
    EXISTING_VERSION=$(echo "$API_LIST" | jq -r ".assets[] | select(.instanceLabel==\"$INSTANCE_LABEL\") | .assetVersion" 2>/dev/null | head -n 1)
    
    echo "ℹ️  API já existe:"
    echo "   API ID: $EXISTING_API_ID"
    echo "   Versão atual: $EXISTING_VERSION"
    echo "   Versão a deployar: $DEPLOY_VERSION"
    
    if [ "$EXISTING_VERSION" == "$DEPLOY_VERSION" ]; then
        echo "✅ Versão já está deployada. Nenhuma ação necessária."
        API_ID="$EXISTING_API_ID"
    else
        echo "🔄 Versão diferente detectada!"
        echo "⚠️  Para trocar versão, será necessário remover a API antiga e criar uma nova"
        echo "⚠️  ATENÇÃO: Políticas e configurações personalizadas serão perdidas"
        echo ""
        echo "🗑️  Removendo API antiga (ID: $EXISTING_API_ID)..."
        
        anypoint-cli-v4 api-mgr api delete \
            --client_id "$ANYPOINT_CLIENT_ID" \
            --client_secret "$ANYPOINT_CLIENT_SECRET" \
            --organization "$ORG_ID" \
            --environment "$ENV_ID" \
            --apiId "$EXISTING_API_ID" || true
        
        echo "✅ API antiga removida"
        echo "⏳ Aguardando propagação (3 segundos)..."
        sleep 3
        
        # Marcar para criar nova
        EXISTING_API_ID=""
    fi
fi

# Criar API se não existir ou foi removida
if [ -z "$EXISTING_API_ID" ] || [ "$EXISTING_API_ID" == "null" ]; then
    echo ""
    echo "📝 Registrando nova API no API Manager..."
    echo ""
    echo "🔨 Comando que será executado:"
    echo "   anypoint-cli-v4 api-mgr api manage $ASSET_ID $DEPLOY_VERSION \\"
    echo "     --isFlex --withProxy --deploymentType=hybrid \\"
    echo "     --scheme=https --port=443 \\"
    echo "     --uri=$UPSTREAM_URI \\"
    echo "     --path=$EXPOSED_PATH \\"
    echo "     --environment=$ENV_ID \\"
    echo "     --apiInstanceLabel=\"$INSTANCE_LABEL\""
    echo ""
    
    # Registrar a API usando a sintaxe correta para Flex Gateway
    RESULT=$(anypoint-cli-v4 api-mgr api manage "$ASSET_ID" "$DEPLOY_VERSION" \
        --client_id "$ANYPOINT_CLIENT_ID" \
        --client_secret "$ANYPOINT_CLIENT_SECRET" \
        --organization "$ORG_ID" \
        --environment "$ENVIRONMENT" \
        --isFlex \
        --withProxy \
        --deploymentType hybrid \
        --scheme http \
        --port 80 \
        --uri "$UPSTREAM_URI" \
        --path "$EXPOSED_PATH" \
        --apiInstanceLabel "$INSTANCE_LABEL" \
        --output json 2>&1 || echo '{"error": true}')
    
    echo "📋 Resultado do registro:"
    echo "$RESULT"
    echo ""
    
    # Extrair API ID do resultado
    API_ID=$(echo "$RESULT" | grep -o '"id":[0-9]*' | grep -o '[0-9]*' | head -n 1)
    
    # Se não conseguir, tentar via JSON
    if [ -z "$API_ID" ]; then
        API_ID=$(echo "$RESULT" | jq -r '.id // empty' 2>/dev/null)
    fi
    
    # Se ainda não conseguir, aguardar e listar novamente
    if [ -z "$API_ID" ] || [ "$API_ID" == "null" ]; then
        echo "⏳ Aguardando propagação da API..."
        sleep 5
        
        API_LIST=$(anypoint-cli-v4 api-mgr api list \
            --client_id "$ANYPOINT_CLIENT_ID" \
            --client_secret "$ANYPOINT_CLIENT_SECRET" \
            --organization "$ORG_ID" \
            --environment "$ENV_ID" \
            --output json 2>/dev/null || echo "[]")
        
        API_ID=$(echo "$API_LIST" | jq -r ".assets[] | select(.instanceLabel==\"$INSTANCE_LABEL\") | .id" 2>/dev/null | head -n 1)
    fi
    
    if [ -z "$API_ID" ] || [ "$API_ID" == "null" ]; then
        echo "❌ Erro ao registrar API no API Manager"
        echo ""
        echo "📋 Resultado completo:"
        echo "$RESULT"
        echo ""
        echo "⚠️  Verifique se:"
        echo "   1. Os IDs de organização ($ORG_ID) e ambiente ($ENV_ID) estão corretos"
        echo "   2. A Connected App tem permissões suficientes"
        echo "   3. O asset $ASSET_ID:$DEPLOY_VERSION existe no Exchange"
        echo "   4. O Gateway ID $GATEWAY_ID é válido"
        exit 1
    fi
    
    echo "✅ API registrada com sucesso!"
    echo "📋 API ID: $API_ID"
fi

# ============================================================================
# PASSO 2: FAZER DEPLOY NO FLEX GATEWAY
# ============================================================================
echo ""
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
echo "   3. Testar endpoint: https://{gateway-url}$EXPOSED_PATH"
echo "=================================================="


