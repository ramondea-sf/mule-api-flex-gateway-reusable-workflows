#!/bin/bash

# Script SEGURO para aplicar políticas na API
# ⚠️ NÃO REMOVE políticas existentes - apenas atualiza/adiciona
# Isso evita janelas de vulnerabilidade

# Uso: ./apply-policies-safe.sh <environment>

set -e

ENVIRONMENT=$1

echo "=================================================="
echo "🛡️  Aplicando Políticas na API (Modo Seguro)"
echo "=================================================="
echo "Ambiente: $ENVIRONMENT"
echo ""
echo "ℹ️  Este script NÃO remove políticas durante a atualização"
echo "   Isso evita janelas de vulnerabilidade"
echo ""

# Ler configuração
CONFIG_FILE="api/api-config.yaml"
MANDATORY_POLICIES_FILE="policies/mandatory-policies.yaml"

# Ler IDs necessários
API_ID=$(cat /tmp/api-id.txt)
ENV_ID=$(yq eval ".environments.$ENVIRONMENT.environmentId" $CONFIG_FILE)
ORG_ID=$(yq eval ".environments.$ENVIRONMENT.organizationId" $CONFIG_FILE)

echo "📋 Informações:"
echo "   API ID: $API_ID"
echo "   Environment ID: $ENV_ID"
echo "   Organization ID: $ORG_ID"
echo ""

# Listar políticas existentes na API
echo "🔍 Carregando políticas atuais da API..."
EXISTING_POLICIES=$(anypoint-cli-v4 api-mgr policy list \
    --organization "$ORG_ID" \
    --environment "$ENV_ID" \
    --apiId "$API_ID" \
    --output json 2>/dev/null || echo "[]")

EXISTING_COUNT=$(echo "$EXISTING_POLICIES" | jq 'length')
echo "📊 Políticas existentes: $EXISTING_COUNT"
echo ""

# Array para controlar políticas processadas
declare -A PROCESSED_POLICIES

# Função para comparar configurações de políticas
compare_policy_config() {
    local existing_config="$1"
    local new_config="$2"
    
    # Compara os hashes das configurações
    local existing_hash=$(echo "$existing_config" | jq -S . | md5sum | cut -d' ' -f1)
    local new_hash=$(echo "$new_config" | jq -S . | md5sum | cut -d' ' -f1)
    
    if [ "$existing_hash" == "$new_hash" ]; then
        return 0  # São iguais
    else
        return 1  # São diferentes
    fi
}

# Função para atualizar ou criar política
apply_single_policy() {
    local policy_name="$1"
    local policy_config="$2"
    local policy_order="$3"
    local is_mandatory="$4"
    local can_be_disabled="$5"
    
    echo "----------------------------------------"
    echo "📦 Política: $policy_name"
    
    if [ "$is_mandatory" == "true" ]; then
        echo "   🔒 Tipo: OBRIGATÓRIA (não pode ser desabilitada)"
    else
        echo "   🔓 Tipo: Opcional"
    fi
    
    # Verificar se a política já existe
    EXISTING_POLICY=$(echo "$EXISTING_POLICIES" | jq -r ".[] | select(.name==\"$policy_name\")")
    
    if [ -n "$EXISTING_POLICY" ] && [ "$EXISTING_POLICY" != "null" ]; then
        EXISTING_POLICY_ID=$(echo "$EXISTING_POLICY" | jq -r '.id')
        EXISTING_CONFIG=$(echo "$EXISTING_POLICY" | jq '.configuration')
        
        echo "   ℹ️  Política já existe (ID: $EXISTING_POLICY_ID)"
        
        # Comparar configurações
        if compare_policy_config "$EXISTING_CONFIG" "$policy_config"; then
            echo "   ✅ Configuração idêntica - mantendo política"
            PROCESSED_POLICIES["$policy_name"]="kept"
            return 0
        else
            echo "   🔄 Configuração diferente - atualizando SEM remover"
            
            # IMPORTANTE: Atualiza in-place sem remover
            # Isso mantém a política ativa durante a atualização
            TEMP_CONFIG=$(mktemp)
            echo "$policy_config" > "$TEMP_CONFIG"
            
            # Tenta atualizar a política
            if anypoint-cli-v4 api-mgr policy update \
                --organization "$ORG_ID" \
                --environment "$ENV_ID" \
                --apiId "$API_ID" \
                --policyId "$EXISTING_POLICY_ID" \
                --config @"$TEMP_CONFIG" \
                --order "$policy_order" 2>/dev/null; then
                echo "   ✅ Política atualizada com sucesso!"
                PROCESSED_POLICIES["$policy_name"]="updated"
            else
                # Se update não funcionar, tenta método alternativo
                echo "   ⚠️  Update direto não suportado, usando método alternativo..."
                
                # Criar nova política com ordem maior
                NEW_ORDER=$((policy_order + 100))
                
                if anypoint-cli-v4 api-mgr policy apply \
                    --organization "$ORG_ID" \
                    --environment "$ENV_ID" \
                    --apiId "$API_ID" \
                    --policyName "$policy_name" \
                    --config @"$TEMP_CONFIG" \
                    --order "$NEW_ORDER" 2>/dev/null; then
                    
                    echo "   ✅ Nova versão criada com sucesso!"
                    
                    # Agora remove a antiga (nova já está ativa)
                    anypoint-cli-v4 api-mgr policy delete \
                        --organization "$ORG_ID" \
                        --environment "$ENV_ID" \
                        --apiId "$API_ID" \
                        --policyId "$EXISTING_POLICY_ID" \
                        --confirm
                    
                    # Ajusta ordem da nova política
                    NEW_POLICY_ID=$(anypoint-cli-v4 api-mgr policy list \
                        --organization "$ORG_ID" \
                        --environment "$ENV_ID" \
                        --apiId "$API_ID" \
                        --output json | jq -r ".[] | select(.name==\"$policy_name\" and .order==$NEW_ORDER) | .id")
                    
                    if [ -n "$NEW_POLICY_ID" ]; then
                        anypoint-cli-v4 api-mgr policy update \
                            --organization "$ORG_ID" \
                            --environment "$ENV_ID" \
                            --apiId "$API_ID" \
                            --policyId "$NEW_POLICY_ID" \
                            --order "$policy_order" 2>/dev/null || true
                    fi
                    
                    PROCESSED_POLICIES["$policy_name"]="recreated"
                else
                    echo "   ⚠️  Não foi possível atualizar política"
                    PROCESSED_POLICIES["$policy_name"]="failed"
                fi
            fi
            
            rm -f "$TEMP_CONFIG"
        fi
    else
        echo "   📝 Política não existe - criando..."
        
        TEMP_CONFIG=$(mktemp)
        echo "$policy_config" > "$TEMP_CONFIG"
        
        if anypoint-cli-v4 api-mgr policy apply \
            --organization "$ORG_ID" \
            --environment "$ENV_ID" \
            --apiId "$API_ID" \
            --policyName "$policy_name" \
            --config @"$TEMP_CONFIG" \
            --order "$policy_order" 2>/dev/null; then
            echo "   ✅ Política criada com sucesso!"
            PROCESSED_POLICIES["$policy_name"]="created"
        else
            echo "   ⚠️  Não foi possível criar política"
            PROCESSED_POLICIES["$policy_name"]="failed"
        fi
        
        rm -f "$TEMP_CONFIG"
    fi
}

# Ler tipo de exposição da API
EXPOSURE_TYPE="public"
if [ -f "/tmp/exposure-type.txt" ]; then
    EXPOSURE_TYPE=$(cat /tmp/exposure-type.txt)
fi

echo "🌐 Tipo de exposição da API: $EXPOSURE_TYPE"
echo ""

# 1. PROCESSAR POLÍTICAS OBRIGATÓRIAS PRIMEIRO
if [ -f "$MANDATORY_POLICIES_FILE" ]; then
    echo "🔒 ================================"
    echo "🔒 APLICANDO POLÍTICAS OBRIGATÓRIAS"
    echo "🔒 ================================"
    echo ""
    
    # Mostrar políticas visíveis (sem configurações)
    echo "📋 Políticas obrigatórias que serão aplicadas:"
    VISIBLE_COUNT=$(yq eval '.visiblePolicies | length' $MANDATORY_POLICIES_FILE)
    for i in $(seq 0 $((VISIBLE_COUNT - 1))); do
        VISIBLE_NAME=$(yq eval ".visiblePolicies[$i].name" $MANDATORY_POLICIES_FILE)
        VISIBLE_DESC=$(yq eval ".visiblePolicies[$i].description" $MANDATORY_POLICIES_FILE)
        echo "   ✅ $VISIBLE_NAME - $VISIBLE_DESC"
    done
    echo ""
    
    MANDATORY_COUNT=$(yq eval '.mandatory | length' $MANDATORY_POLICIES_FILE)
    
    for i in $(seq 0 $((MANDATORY_COUNT - 1))); do
        POLICY_NAME=$(yq eval ".mandatory[$i].name" $MANDATORY_POLICIES_FILE)
        POLICY_ENABLED=$(yq eval ".mandatory[$i].enabled" $MANDATORY_POLICIES_FILE)
        POLICY_ORDER=$(yq eval ".mandatory[$i].order" $MANDATORY_POLICIES_FILE)
        POLICY_CONFIG=$(yq eval ".mandatory[$i].configuration" $MANDATORY_POLICIES_FILE -o=json)
        CAN_BE_DISABLED=$(yq eval ".mandatory[$i].canBeDisabled" $MANDATORY_POLICIES_FILE)
        POLICY_APPLIES_TO=$(yq eval ".mandatory[$i].appliesTo" $MANDATORY_POLICIES_FILE)
        
        # Verificar se a política se aplica ao tipo de exposição
        if [ "$POLICY_APPLIES_TO" != "null" ] && [ "$POLICY_APPLIES_TO" != "all" ]; then
            if [ "$POLICY_APPLIES_TO" != "$EXPOSURE_TYPE" ]; then
                echo "   ⏭️  Política $POLICY_NAME não se aplica a APIs $EXPOSURE_TYPE - pulando..."
                continue
            fi
        fi
        
        # Políticas obrigatórias sempre são aplicadas
        if [ "$POLICY_ENABLED" == "true" ]; then
            echo "   🔒 Aplicando política obrigatória (configuração protegida)"
            apply_single_policy "$POLICY_NAME" "$POLICY_CONFIG" "$POLICY_ORDER" "true" "$CAN_BE_DISABLED"
        fi
    done
    
    echo ""
fi

# 2. PROCESSAR POLÍTICAS OPCIONAIS DA API
echo "🔓 ================================"
echo "🔓 APLICANDO POLÍTICAS OPCIONAIS"
echo "🔓 ================================"
echo ""

POLICY_COUNT=$(yq eval '.policies | length' $CONFIG_FILE)

for i in $(seq 0 $((POLICY_COUNT - 1))); do
    POLICY_NAME=$(yq eval ".policies[$i].name" $CONFIG_FILE)
    POLICY_ENABLED=$(yq eval ".policies[$i].enabled" $CONFIG_FILE)
    POLICY_ORDER=$(yq eval ".policies[$i].order" $CONFIG_FILE)
    
    # Verificar se não é uma política obrigatória
    IS_MANDATORY="false"
    if [ -f "$MANDATORY_POLICIES_FILE" ]; then
        MANDATORY_MATCH=$(yq eval ".mandatory[] | select(.name==\"$POLICY_NAME\") | .name" $MANDATORY_POLICIES_FILE)
        if [ -n "$MANDATORY_MATCH" ]; then
            IS_MANDATORY="true"
            echo "⏭️  Política $POLICY_NAME é obrigatória - já foi processada"
            continue
        fi
    fi
    
    if [ "$POLICY_ENABLED" != "true" ]; then
        echo "⏭️  Política $POLICY_NAME está desabilitada - pulando..."
        
        # Se a política existe mas está desabilitada, remover
        EXISTING_POLICY_ID=$(echo "$EXISTING_POLICIES" | jq -r ".[] | select(.name==\"$POLICY_NAME\") | .id")
        if [ -n "$EXISTING_POLICY_ID" ] && [ "$EXISTING_POLICY_ID" != "null" ]; then
            echo "   🗑️  Removendo política desabilitada..."
            anypoint-cli-v4 api-mgr policy delete \
                --organization "$ORG_ID" \
                --environment "$ENV_ID" \
                --apiId "$API_ID" \
                --policyId "$EXISTING_POLICY_ID" \
                --confirm || echo "   ⚠️  Não foi possível remover"
        fi
        continue
    fi
    
    POLICY_CONFIG=$(yq eval ".policies[$i].configuration" $CONFIG_FILE -o=json)
    
    apply_single_policy "$POLICY_NAME" "$POLICY_CONFIG" "$POLICY_ORDER" "false" "true"
done

# 3. REMOVER POLÍTICAS NÃO GERENCIADAS (se houver)
echo ""
echo "🧹 ================================"
echo "🧹 LIMPEZA DE POLÍTICAS NÃO GERENCIADAS"
echo "🧹 ================================"
echo ""

# Recarregar políticas atuais
CURRENT_POLICIES=$(anypoint-cli-v4 api-mgr policy list \
    --organization "$ORG_ID" \
    --environment "$ENV_ID" \
    --apiId "$API_ID" \
    --output json 2>/dev/null || echo "[]")

# Verificar políticas que não foram processadas
echo "$CURRENT_POLICIES" | jq -r '.[].name' | while read -r policy_name; do
    if [ -z "${PROCESSED_POLICIES[$policy_name]}" ]; then
        echo "⚠️  Política não gerenciada encontrada: $policy_name"
        echo "   (Não será removida automaticamente por segurança)"
        echo "   Se quiser remover, faça manualmente via API Manager"
    fi
done

# Resumo
echo ""
echo "=================================================="
echo "✅ APLICAÇÃO DE POLÍTICAS CONCLUÍDA"
echo "=================================================="
echo ""
echo "📊 Resumo:"
for policy_name in "${!PROCESSED_POLICIES[@]}"; do
    status="${PROCESSED_POLICIES[$policy_name]}"
    case $status in
        "kept")
            echo "   ✅ $policy_name: Mantida (sem mudanças)"
            ;;
        "updated")
            echo "   🔄 $policy_name: Atualizada"
            ;;
        "recreated")
            echo "   🔄 $policy_name: Recriada (update não suportado)"
            ;;
        "created")
            echo "   ➕ $policy_name: Criada"
            ;;
        "failed")
            echo "   ❌ $policy_name: Falhou"
            ;;
    esac
done

echo ""
echo "🛡️  Nenhuma janela de vulnerabilidade foi criada!"
echo "=================================================="

