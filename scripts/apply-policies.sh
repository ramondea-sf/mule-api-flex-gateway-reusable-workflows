#!/bin/bash

# Script para aplicar políticas de segurança no API Manager
# Uso: ./apply-policies.sh <api-id> <environment> <cluster> <is-public>
#
# Este script:
# 1. Lista políticas existentes na API
# 2. Carrega políticas corporativas (baseadas em ambiente/cluster/isPublic)
# 3. Carrega políticas customizadas da API
# 4. Aplica políticas de forma inteligente (apenas novas ou alteradas)

set -e

API_ID=$1
ENVIRONMENT=$2
CLUSTER=$3
IS_PUBLIC=$4

echo "=================================================="
echo "🔒 Aplicando Políticas de Segurança"
echo "=================================================="
echo "API ID: $API_ID"
echo "Ambiente: $ENVIRONMENT"
echo "Cluster: $CLUSTER"
echo "API Pública: $IS_PUBLIC"
echo ""

# Ler configurações
CONFIG_FILE="api/api-config.yaml"
ENV_FILE="api/${ENVIRONMENT}.yaml"

# Verificar se arquivo de ambiente existe
if [ ! -f "$ENV_FILE" ]; then
    echo "❌ Erro: Arquivo de ambiente não encontrado: $ENV_FILE"
    exit 1
fi

# Extrair configurações
ORG_ID=$(yq eval '.organizationId' $CONFIG_FILE)
ENV_ID=$(yq eval ".environment.environmentId" $ENV_FILE)

# Array para rastrear políticas desejadas (serão adicionadas durante o processamento)
DESIRED_POLICIES=""

echo "🏢 Organization ID: $ORG_ID"
echo "🌍 Environment ID: $ENV_ID"
echo ""

# ============================================================================
# PASSO 1: LISTAR POLÍTICAS EXISTENTES
# ============================================================================
echo "=================================================="
echo "🔍 PASSO 1: Listar políticas existentes"
echo "=================================================="

# Desabilitar exit on error temporariamente
set +e
EXISTING_POLICIES=$(anypoint-cli-v4 api-mgr:policy:list "$API_ID" \
    --client_id "$ANYPOINT_CLIENT_ID" \
    --client_secret "$ANYPOINT_CLIENT_SECRET" \
    --organization "$ORG_ID" \
    --environment "$ENV_ID" \
    --output json 2>/dev/null)

LIST_STATUS=$?
set -e

if [ $LIST_STATUS -ne 0 ]; then
    echo "⚠️  Erro ao listar políticas existentes. Assumindo que não há políticas."
    EXISTING_POLICIES="[]"
fi

# Validar se é um array JSON válido
if ! echo "$EXISTING_POLICIES" | jq empty 2>/dev/null; then
    EXISTING_POLICIES="[]"
fi

POLICY_COUNT=$(echo "$EXISTING_POLICIES" | jq 'length' 2>/dev/null || echo "0")
echo "📊 Políticas existentes: $POLICY_COUNT"

if [ "$POLICY_COUNT" != "0" ]; then
    echo "$EXISTING_POLICIES" | jq -r '.[] | "   - \(.\"Asset ID\") v\(.\"Asset Version\") (ID: \(.ID))"' 2>/dev/null || true
fi
echo ""

# ============================================================================
# PASSO 2: CARREGAR POLÍTICAS CORPORATIVAS
# ============================================================================
echo "=================================================="
echo "🏢 PASSO 2: Carregar políticas corporativas"
echo "=================================================="

# Determinar o tipo de gateway baseado em isPublic
if [ "$IS_PUBLIC" == "true" ]; then
    GATEWAY_TYPE="public"
else
    GATEWAY_TYPE="private"
fi

# Path para arquivo de políticas corporativas
# Estrutura: policies/corporate/{environment}/{cluster}/{gateway-type}.yaml
CORPORATE_POLICIES_FILE="policies/corporate/${ENVIRONMENT}/${CLUSTER}/${GATEWAY_TYPE}.yaml"

echo "🔍 Buscando políticas corporativas em: $CORPORATE_POLICIES_FILE"

# Criar array vazio se arquivo não existir
if [ ! -f "$CORPORATE_POLICIES_FILE" ]; then
    echo "ℹ️  Arquivo de políticas corporativas não encontrado. Usando apenas políticas da API."
    CORPORATE_POLICIES="[]"
else
    echo "✅ Arquivo de políticas corporativas encontrado"
    # Não fazemos nada aqui, usaremos o arquivo diretamente com yq
fi

# ============================================================================
# PASSO 3: CARREGAR POLÍTICAS DA API
# ============================================================================
echo ""
echo "=================================================="
echo "📦 PASSO 3: Carregar políticas da API"
echo "=================================================="

# Verificar se a seção policies existe no arquivo de ambiente
POLICIES_SECTION=$(yq eval '.policies' "$ENV_FILE" 2>/dev/null)

if [ "$POLICIES_SECTION" == "null" ] || [ -z "$POLICIES_SECTION" ]; then
    echo "ℹ️  Nenhuma política customizada definida no arquivo de ambiente"
    API_POLICIES="[]"
fi

echo ""

# ============================================================================
# PASSO 4: MESCLAR E APLICAR POLÍTICAS
# ============================================================================
echo "=================================================="
echo "🔨 PASSO 4: Processar e aplicar políticas"
echo "=================================================="

# Função para aplicar/atualizar uma política
apply_policy() {
    local POLICY_NAME=$1
    local POLICY_GROUP_ID=$2
    local POLICY_VERSION=$3
    local POLICY_CONFIG=$4
    
    echo "  📝 $POLICY_NAME v$POLICY_VERSION"
    
    # Verificar se política já existe
    EXISTING_POLICY=$(echo "$EXISTING_POLICIES" | jq -c ".[] | select(.\"Asset ID\"==\"$POLICY_NAME\")" 2>/dev/null | head -n 1)
    
    # Preparar config
    COMPACT_CONFIG=""
    if [ -n "$POLICY_CONFIG" ] && [ "$POLICY_CONFIG" != "null" ] && [ "$POLICY_CONFIG" != "{}" ]; then
        COMPACT_CONFIG=$(echo "$POLICY_CONFIG" | jq -c . 2>/dev/null || echo "$POLICY_CONFIG")
        if ! echo "$COMPACT_CONFIG" | jq empty 2>/dev/null; then
            COMPACT_CONFIG=""
        fi
    fi
    
    # Adicionar à lista de políticas desejadas
    DESIRED_POLICIES="${DESIRED_POLICIES}${POLICY_NAME},"
    
    if [ -n "$EXISTING_POLICY" ] && [ "$EXISTING_POLICY" != "null" ]; then
        # Política existe - usar EDIT
        POLICY_INSTANCE_ID=$(echo "$EXISTING_POLICY" | jq -r '.ID' 2>/dev/null)
        echo "     ↻ Atualizando (ID: $POLICY_INSTANCE_ID)"
        
        CMD="anypoint-cli-v4 api-mgr:policy:edit"
        CMD="$CMD --client_id \"$ANYPOINT_CLIENT_ID\""
        CMD="$CMD --client_secret \"$ANYPOINT_CLIENT_SECRET\""
        CMD="$CMD --organization \"$ORG_ID\""
        CMD="$CMD --environment \"$ENV_ID\""
        CMD="$CMD --pointcut '[{\"methodRegex\":\".*\",\"uriTemplateRegex\":\".*\"}]'"
        
        if [ -n "$COMPACT_CONFIG" ]; then
            CMD="$CMD --config '$COMPACT_CONFIG'"
        fi
        
        CMD="$CMD \"$API_ID\" \"$POLICY_INSTANCE_ID\""
        
    else
        # Política não existe - usar APPLY
        echo "     + Criando nova"
        
        CMD="anypoint-cli-v4 api-mgr:policy:apply"
        CMD="$CMD --client_id \"$ANYPOINT_CLIENT_ID\""
        CMD="$CMD --client_secret \"$ANYPOINT_CLIENT_SECRET\""
        CMD="$CMD --organization \"$ORG_ID\""
        CMD="$CMD --environment \"$ENV_ID\""
        CMD="$CMD --groupId \"$POLICY_GROUP_ID\""
        CMD="$CMD --policyVersion \"$POLICY_VERSION\""
        CMD="$CMD --pointcut '[{\"methodRegex\":\".*\",\"uriTemplateRegex\":\".*\"}]'"
        CMD="$CMD --output json"
        
        if [ -n "$COMPACT_CONFIG" ]; then
            CMD="$CMD --config '$COMPACT_CONFIG'"
        fi
        
        CMD="$CMD \"$API_ID\" \"$POLICY_NAME\""
    fi
    
    set +e
    APPLY_RESULT=$(eval $CMD 2>&1)
    APPLY_STATUS=$?
    set -e
    
    if [ $APPLY_STATUS -ne 0 ]; then
        echo "     ❌ ERRO:"
        echo "$APPLY_RESULT"
        echo ""
        return 1
    else
        echo "     ✅ Sucesso"
    fi
    
    return 0
}

# ============================================================================
# PROCESSAR POLÍTICAS CORPORATIVAS (se existirem)
# ============================================================================
if [ -f "$CORPORATE_POLICIES_FILE" ]; then
    echo ""
    echo "🏢 Processando políticas corporativas..."
    
    # Processar políticas inbound
    CORPORATE_INBOUND_COUNT=$(yq eval '.policies.inbound | length' "$CORPORATE_POLICIES_FILE" 2>/dev/null || echo "0")
    
    if [ "$CORPORATE_INBOUND_COUNT" != "0" ] && [ "$CORPORATE_INBOUND_COUNT" != "null" ]; then
        echo ""
        echo "📥 Políticas Inbound Corporativas: $CORPORATE_INBOUND_COUNT"
        
        for i in $(seq 0 $((CORPORATE_INBOUND_COUNT - 1))); do
            NAME=$(yq eval ".policies.inbound[$i].policyRef.name" "$CORPORATE_POLICIES_FILE" 2>/dev/null)
            VERSION=$(yq eval ".policies.inbound[$i].policyRef.version" "$CORPORATE_POLICIES_FILE" 2>/dev/null)
            GROUP_ID=$(yq eval ".policies.inbound[$i].policyRef.groupId" "$CORPORATE_POLICIES_FILE" 2>/dev/null)
            
            # Converter config YAML para JSON
            CONFIG_JSON=$(yq eval ".policies.inbound[$i].config" "$CORPORATE_POLICIES_FILE" -o=json 2>/dev/null || echo "{}")
            
            apply_policy "$NAME" "$GROUP_ID" "$VERSION" "$CONFIG_JSON"
        done
    fi
    
    # Processar políticas outbound
    CORPORATE_OUTBOUND_COUNT=$(yq eval '.policies.outbound | length' "$CORPORATE_POLICIES_FILE" 2>/dev/null || echo "0")
    
    if [ "$CORPORATE_OUTBOUND_COUNT" != "0" ] && [ "$CORPORATE_OUTBOUND_COUNT" != "null" ]; then
        echo ""
        echo "📤 Políticas Outbound Corporativas: $CORPORATE_OUTBOUND_COUNT"
        
        for i in $(seq 0 $((CORPORATE_OUTBOUND_COUNT - 1))); do
            NAME=$(yq eval ".policies.outbound[$i].policyRef.name" "$CORPORATE_POLICIES_FILE" 2>/dev/null)
            VERSION=$(yq eval ".policies.outbound[$i].policyRef.version" "$CORPORATE_POLICIES_FILE" 2>/dev/null)
            GROUP_ID=$(yq eval ".policies.outbound[$i].policyRef.groupId" "$CORPORATE_POLICIES_FILE" 2>/dev/null)
            
            CONFIG_JSON=$(yq eval ".policies.outbound[$i].config" "$CORPORATE_POLICIES_FILE" -o=json 2>/dev/null || echo "{}")
            
            apply_policy "$NAME" "$GROUP_ID" "$VERSION" "$CONFIG_JSON"
        done
    fi
fi

# ============================================================================
# PROCESSAR POLÍTICAS DA API (customizadas)
# ============================================================================
echo ""
echo "📦 Processando políticas customizadas da API..."

# Processar políticas inbound
API_INBOUND_COUNT=$(yq eval '.policies.inbound | length' "$ENV_FILE" 2>/dev/null || echo "0")

if [ "$API_INBOUND_COUNT" != "0" ] && [ "$API_INBOUND_COUNT" != "null" ]; then
    echo ""
    echo "📥 Políticas Inbound da API: $API_INBOUND_COUNT"
    
    for i in $(seq 0 $((API_INBOUND_COUNT - 1))); do
        NAME=$(yq eval ".policies.inbound[$i].policyRef.name" "$ENV_FILE" 2>/dev/null)
        VERSION=$(yq eval ".policies.inbound[$i].policyRef.version" "$ENV_FILE" 2>/dev/null)
        GROUP_ID=$(yq eval ".policies.inbound[$i].policyRef.groupId" "$ENV_FILE" 2>/dev/null)
        
        CONFIG_JSON=$(yq eval ".policies.inbound[$i].config" "$ENV_FILE" -o=json 2>/dev/null || echo "{}")
        
        apply_policy "$NAME" "$GROUP_ID" "$VERSION" "$CONFIG_JSON"
    done
fi

# Processar políticas outbound
API_OUTBOUND_COUNT=$(yq eval '.policies.outbound | length' "$ENV_FILE" 2>/dev/null || echo "0")

if [ "$API_OUTBOUND_COUNT" != "0" ] && [ "$API_OUTBOUND_COUNT" != "null" ]; then
    echo ""
    echo "📤 Políticas Outbound da API: $API_OUTBOUND_COUNT"
    
    for i in $(seq 0 $((API_OUTBOUND_COUNT - 1))); do
        NAME=$(yq eval ".policies.outbound[$i].policyRef.name" "$ENV_FILE" 2>/dev/null)
        VERSION=$(yq eval ".policies.outbound[$i].policyRef.version" "$ENV_FILE" 2>/dev/null)
        GROUP_ID=$(yq eval ".policies.outbound[$i].policyRef.groupId" "$ENV_FILE" 2>/dev/null)
        
        CONFIG_JSON=$(yq eval ".policies.outbound[$i].config" "$ENV_FILE" -o=json 2>/dev/null || echo "{}")
        
        apply_policy "$NAME" "$GROUP_ID" "$VERSION" "$CONFIG_JSON"
    done
fi

# ============================================================================
# PASSO 5: REMOVER POLÍTICAS ÓRFÃS
# ============================================================================
echo ""
echo "=================================================="
echo "🗑️  PASSO 5: Remover políticas órfãs"
echo "=================================================="

# Verificar se existem políticas para remover
POLICY_COUNT=$(echo "$EXISTING_POLICIES" | jq 'length' 2>/dev/null || echo "0")

if [ "$POLICY_COUNT" != "0" ] && [ "$POLICY_COUNT" != "null" ]; then
    REMOVED_COUNT=0
    
    # Iterar sobre as políticas existentes
    for idx in $(seq 0 $((POLICY_COUNT - 1))); do
        POLICY_NAME=$(echo "$EXISTING_POLICIES" | jq -r ".[$idx].\"Asset ID\"" 2>/dev/null)
        POLICY_ID=$(echo "$EXISTING_POLICIES" | jq -r ".[$idx].ID" 2>/dev/null)
        
        # Verificar se política está na lista de desejadas
        if [[ "$DESIRED_POLICIES" != *"$POLICY_NAME,"* ]]; then
            echo "  🗑️  Removendo: $POLICY_NAME (ID: $POLICY_ID)"
            
            set +e
            REMOVE_RESULT=$(anypoint-cli-v4 api-mgr:policy:remove \
                --client_id "$ANYPOINT_CLIENT_ID" \
                --client_secret "$ANYPOINT_CLIENT_SECRET" \
                --organization "$ORG_ID" \
                --environment "$ENV_ID" \
                "$API_ID" "$POLICY_ID" 2>&1)
            REMOVE_STATUS=$?
            set -e
            
            if [ $REMOVE_STATUS -ne 0 ]; then
                echo "     ❌ ERRO ao remover"
                echo "$REMOVE_RESULT" | head -n 5
            else
                echo "     ✅ Removida"
                REMOVED_COUNT=$((REMOVED_COUNT + 1))
            fi
        fi
    done
    
    if [ $REMOVED_COUNT -eq 0 ]; then
        echo "   ✅ Nenhuma política órfã encontrada"
    else
        echo "   📊 Total removidas: $REMOVED_COUNT"
    fi
else
    echo "   ✅ Nenhuma política existente para verificar"
fi

echo ""
echo "✅ Aplicação de políticas concluída"


