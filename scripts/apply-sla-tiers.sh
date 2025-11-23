#!/bin/bash

# Script para aplicar SLA Tiers no API Manager
# Uso: ./apply-sla-tiers.sh <api-id> <environment>

set -e

API_ID=$1
ENVIRONMENT=$2

echo "=================================================="
echo "🎯 Aplicando SLA Tiers"
echo "=================================================="
echo "API ID: $API_ID"
echo "Ambiente: $ENVIRONMENT"
echo ""

# Ler configurações
CONFIG_FILE="api/api-config.yaml"
ENV_FILE="api/${ENVIRONMENT}.yaml"

if [ ! -f "$ENV_FILE" ]; then
    echo "❌ Erro: Arquivo de ambiente não encontrado: $ENV_FILE"
    exit 1
fi

# Extrair configurações
ORG_ID=$(yq eval '.organizationId' $CONFIG_FILE)
ENV_ID=$(yq eval ".environment.environmentId" $ENV_FILE)

echo "🏢 Organization ID: $ORG_ID"
echo "🌍 Environment ID: $ENV_ID"
echo ""

# ============================================================================
# PASSO 1: LISTAR SLA TIERS EXISTENTES
# ============================================================================
echo "=================================================="
echo "🔍 PASSO 1: Listar SLA Tiers existentes"
echo "=================================================="

set +e
EXISTING_TIERS=$(anypoint-cli-v4 api-mgr:tier:list \
    --client_id "$ANYPOINT_CLIENT_ID" \
    --client_secret "$ANYPOINT_CLIENT_SECRET" \
    --organization "$ORG_ID" \
    --environment "$ENV_ID" \
    "$API_ID" \
    --output json 2>/dev/null)

LIST_STATUS=$?
set -e

if [ $LIST_STATUS -ne 0 ]; then
    echo "⚠️  Erro ao listar SLA Tiers. Assumindo que não há tiers."
    EXISTING_TIERS="[]"
fi

if ! echo "$EXISTING_TIERS" | jq empty 2>/dev/null; then
    EXISTING_TIERS="[]"
fi

TIER_COUNT=$(echo "$EXISTING_TIERS" | jq 'length' 2>/dev/null || echo "0")
echo "📊 SLA Tiers existentes: $TIER_COUNT"

if [ "$TIER_COUNT" != "0" ]; then
    echo "$EXISTING_TIERS" | jq -r '.[] | "   - \(.name): \(.description) (ID: \(.id))"' 2>/dev/null || true
fi
echo ""

# ============================================================================
# PASSO 2: CARREGAR SLA TIERS DO ARQUIVO DE CONFIGURAÇÃO
# ============================================================================
echo "=================================================="
echo "📦 PASSO 2: Carregar SLA Tiers da configuração"
echo "=================================================="

SLAS_SECTION=$(yq eval '.SLAs' "$ENV_FILE" 2>/dev/null)

if [ "$SLAS_SECTION" == "null" ] || [ -z "$SLAS_SECTION" ]; then
    echo "ℹ️  Nenhum SLA Tier definido no arquivo de ambiente"
    echo ""
    echo "✅ Processo concluído - Nenhum SLA para aplicar"
    exit 0
fi

SLA_COUNT=$(yq eval '.SLAs | length' "$ENV_FILE" 2>/dev/null || echo "0")
echo "📊 SLA Tiers configurados: $SLA_COUNT"
echo ""

# ============================================================================
# PASSO 3: APLICAR SLA TIERS
# ============================================================================
echo "=================================================="
echo "🔨 PASSO 3: Aplicar SLA Tiers"
echo "=================================================="

ADDED_COUNT=0
SKIPPED_COUNT=0

for i in $(seq 0 $((SLA_COUNT - 1))); do
    NAME=$(yq eval ".SLAs[$i].name" "$ENV_FILE" 2>/dev/null)
    DESCRIPTION=$(yq eval ".SLAs[$i].description" "$ENV_FILE" 2>/dev/null)
    LIMIT=$(yq eval ".SLAs[$i].limit" "$ENV_FILE" 2>/dev/null)
    AUTO_APPROVE=$(yq eval ".SLAs[$i].autoApprove" "$ENV_FILE" 2>/dev/null)
    
    echo ""
    echo "  📝 SLA Tier: $NAME"
    
    # Verificar se SLA já existe
    EXISTING_TIER=$(echo "$EXISTING_TIERS" | jq -c ".[] | select(.name==\"$NAME\")" 2>/dev/null | head -n 1)
    
    if [ -n "$EXISTING_TIER" ] && [ "$EXISTING_TIER" != "null" ]; then
        TIER_ID=$(echo "$EXISTING_TIER" | jq -r '.id' 2>/dev/null)
        echo "     ⏭️  Já existe (ID: $TIER_ID)"
        SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
        continue
    fi
    
    # Criar novo SLA Tier
    echo "     + Criando novo"
    
    CMD="anypoint-cli-v4 api-mgr:tier:add"
    CMD="$CMD --client_id \"$ANYPOINT_CLIENT_ID\""
    CMD="$CMD --client_secret \"$ANYPOINT_CLIENT_SECRET\""
    CMD="$CMD --organization \"$ORG_ID\""
    CMD="$CMD --environment \"$ENV_ID\""
    CMD="$CMD --name \"$NAME\""
    CMD="$CMD --description \"$DESCRIPTION\""
    CMD="$CMD --limit \"$LIMIT\""
    
    # Adicionar autoApprove se true
    if [ "$AUTO_APPROVE" == "true" ]; then
        CMD="$CMD --autoApprove"
    fi
    
    CMD="$CMD --output json"
    CMD="$CMD \"$API_ID\""
    
    set +e
    ADD_RESULT=$(eval $CMD 2>&1)
    ADD_STATUS=$?
    set -e
    
    if [ $ADD_STATUS -ne 0 ]; then
        echo "     ❌ ERRO ao criar SLA Tier"
        echo "$ADD_RESULT" | head -n 10
    else
        echo "     ✅ Criado"
        ADDED_COUNT=$((ADDED_COUNT + 1))
        
        NEW_TIER_ID=$(echo "$ADD_RESULT" | jq -r '.id // empty' 2>/dev/null)
        if [ -n "$NEW_TIER_ID" ]; then
            echo "     📋 Tier ID: $NEW_TIER_ID"
        fi
    fi
done

echo ""
echo "=================================================="
echo "✅ Aplicação de SLA Tiers concluída"
echo "=================================================="
echo "📊 Resumo:"
echo "   - Criados: $ADDED_COUNT"
echo "   - Já existiam: $SKIPPED_COUNT"
echo "   - Total configurados: $SLA_COUNT"
echo "=================================================="

