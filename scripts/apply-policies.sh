#!/bin/bash

# Script para aplicar políticas na API
# Uso: ./apply-policies.sh <environment>

set -e

ENVIRONMENT=$1

echo "=================================================="
echo "🛡️  Aplicando Políticas na API"
echo "=================================================="
echo "Ambiente: $ENVIRONMENT"
echo ""

# Ler configuração
CONFIG_FILE="api/api-config.yaml"

# Ler IDs necessários
API_ID=$(cat /tmp/api-id.txt)
ENV_ID=$(yq eval ".environments.$ENVIRONMENT.environmentId" $CONFIG_FILE)
ORG_ID=$(yq eval ".environments.$ENVIRONMENT.organizationId" $CONFIG_FILE)

echo "📋 Informações:"
echo "   API ID: $API_ID"
echo "   Environment ID: $ENV_ID"
echo "   Organization ID: $ORG_ID"
echo ""

# Contar quantas políticas estão habilitadas
POLICY_COUNT=$(yq eval '.policies | length' $CONFIG_FILE)
echo "📊 Total de políticas configuradas: $POLICY_COUNT"
echo ""

# Listar políticas existentes na API
echo "🔍 Verificando políticas existentes..."
EXISTING_POLICIES=$(anypoint-cli-v4 api-mgr policy list \
    --organization "$ORG_ID" \
    --environment "$ENV_ID" \
    --apiId "$API_ID" \
    --output json 2>/dev/null || echo "[]")

echo "📋 Políticas existentes: $(echo $EXISTING_POLICIES | jq 'length')"
echo ""

# Processar cada política
for i in $(seq 0 $((POLICY_COUNT - 1))); do
    POLICY_NAME=$(yq eval ".policies[$i].name" $CONFIG_FILE)
    POLICY_ENABLED=$(yq eval ".policies[$i].enabled" $CONFIG_FILE)
    POLICY_ORDER=$(yq eval ".policies[$i].order" $CONFIG_FILE)
    
    echo "----------------------------------------"
    echo "📦 Política: $POLICY_NAME"
    echo "   Habilitada: $POLICY_ENABLED"
    echo "   Ordem: $POLICY_ORDER"
    
    if [ "$POLICY_ENABLED" != "true" ]; then
        echo "   ⏭️  Política desabilitada, pulando..."
        continue
    fi
    
    # Extrair configuração da política
    POLICY_CONFIG=$(yq eval ".policies[$i].configuration" $CONFIG_FILE -o=json)
    
    # Verificar se a política já existe
    EXISTING_POLICY_ID=$(echo "$EXISTING_POLICIES" | jq -r ".[] | select(.name==\"$POLICY_NAME\") | .id" | head -n 1)
    
    if [ -n "$EXISTING_POLICY_ID" ] && [ "$EXISTING_POLICY_ID" != "null" ]; then
        echo "   🔄 Política já existe (ID: $EXISTING_POLICY_ID), atualizando..."
        
        # Remover política existente
        anypoint-cli-v4 api-mgr policy delete \
            --organization "$ORG_ID" \
            --environment "$ENV_ID" \
            --apiId "$API_ID" \
            --policyId "$EXISTING_POLICY_ID" \
            --confirm
        
        echo "   🗑️  Política antiga removida"
    fi
    
    # Criar arquivo temporário com a configuração da política
    TEMP_POLICY_CONFIG=$(mktemp)
    echo "$POLICY_CONFIG" > "$TEMP_POLICY_CONFIG"
    
    echo "   📝 Aplicando política..."
    
    # Aplicar a política (comando genérico - pode precisar ajustes por tipo de política)
    case $POLICY_NAME in
        "rate-limiting-sla-based"|"rate-limiting")
            anypoint-cli-v4 api-mgr policy apply \
                --organization "$ORG_ID" \
                --environment "$ENV_ID" \
                --apiId "$API_ID" \
                --policyName "rate-limiting-sla-based" \
                --config @"$TEMP_POLICY_CONFIG" \
                --order "$POLICY_ORDER" || echo "   ⚠️  Erro ao aplicar política"
            ;;
        "client-id-enforcement")
            anypoint-cli-v4 api-mgr policy apply \
                --organization "$ORG_ID" \
                --environment "$ENV_ID" \
                --apiId "$API_ID" \
                --policyName "client-id-enforcement" \
                --config @"$TEMP_POLICY_CONFIG" \
                --order "$POLICY_ORDER" || echo "   ⚠️  Erro ao aplicar política"
            ;;
        "cors")
            anypoint-cli-v4 api-mgr policy apply \
                --organization "$ORG_ID" \
                --environment "$ENV_ID" \
                --apiId "$API_ID" \
                --policyName "cors" \
                --config @"$TEMP_POLICY_CONFIG" \
                --order "$POLICY_ORDER" || echo "   ⚠️  Erro ao aplicar política"
            ;;
        "jwt-validation")
            anypoint-cli-v4 api-mgr policy apply \
                --organization "$ORG_ID" \
                --environment "$ENV_ID" \
                --apiId "$API_ID" \
                --policyName "jwt-validation" \
                --config @"$TEMP_POLICY_CONFIG" \
                --order "$POLICY_ORDER" || echo "   ⚠️  Erro ao aplicar política"
            ;;
        *)
            # Política genérica
            anypoint-cli-v4 api-mgr policy apply \
                --organization "$ORG_ID" \
                --environment "$ENV_ID" \
                --apiId "$API_ID" \
                --policyName "$POLICY_NAME" \
                --config @"$TEMP_POLICY_CONFIG" \
                --order "$POLICY_ORDER" || echo "   ⚠️  Erro ao aplicar política"
            ;;
    esac
    
    if [ $? -eq 0 ]; then
        echo "   ✅ Política aplicada com sucesso!"
    else
        echo "   ⚠️  Aviso: Não foi possível aplicar a política $POLICY_NAME"
        echo "   Isso pode acontecer se a política não estiver disponível no seu plano"
        echo "   ou se a configuração não estiver correta."
    fi
    
    # Limpar arquivo temporário
    rm -f "$TEMP_POLICY_CONFIG"
done

echo ""
echo "=================================================="
echo "✅ Aplicação de políticas concluída"
echo "=================================================="

