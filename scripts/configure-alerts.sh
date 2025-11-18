#!/bin/bash

# Script para configurar alertas na API
# Uso: ./configure-alerts.sh <environment>

set -e

ENVIRONMENT=$1

echo "=================================================="
echo "🔔 Configurando Alertas na API"
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

# Contar quantos alertas estão configurados
ALERT_COUNT=$(yq eval '.alerts | length' $CONFIG_FILE)
echo "📊 Total de alertas configurados: $ALERT_COUNT"
echo ""

# Listar alertas existentes
echo "🔍 Verificando alertas existentes..."
EXISTING_ALERTS=$(anypoint-cli-v4 api-mgr alert list \
    --organization "$ORG_ID" \
    --environment "$ENV_ID" \
    --apiId "$API_ID" \
    --output json 2>/dev/null || echo "[]")

echo "📋 Alertas existentes: $(echo $EXISTING_ALERTS | jq 'length')"
echo ""

# Processar cada alerta
for i in $(seq 0 $((ALERT_COUNT - 1))); do
    ALERT_NAME=$(yq eval ".alerts[$i].name" $CONFIG_FILE)
    ALERT_ENABLED=$(yq eval ".alerts[$i].enabled" $CONFIG_FILE)
    ALERT_SEVERITY=$(yq eval ".alerts[$i].severity" $CONFIG_FILE)
    
    echo "----------------------------------------"
    echo "🔔 Alerta: $ALERT_NAME"
    echo "   Habilitado: $ALERT_ENABLED"
    echo "   Severidade: $ALERT_SEVERITY"
    
    if [ "$ALERT_ENABLED" != "true" ]; then
        echo "   ⏭️  Alerta desabilitado, pulando..."
        continue
    fi
    
    # Extrair configuração do alerta
    CONDITION_TYPE=$(yq eval ".alerts[$i].condition.type" $CONFIG_FILE)
    
    # Extrair emails de notificação
    RECIPIENTS_COUNT=$(yq eval ".alerts[$i].notification.recipients | length" $CONFIG_FILE)
    RECIPIENTS=""
    for j in $(seq 0 $((RECIPIENTS_COUNT - 1))); do
        EMAIL=$(yq eval ".alerts[$i].notification.recipients[$j]" $CONFIG_FILE)
        if [ -z "$RECIPIENTS" ]; then
            RECIPIENTS="$EMAIL"
        else
            RECIPIENTS="$RECIPIENTS,$EMAIL"
        fi
    done
    
    echo "   📧 Destinatários: $RECIPIENTS"
    
    # Verificar se o alerta já existe
    EXISTING_ALERT_ID=$(echo "$EXISTING_ALERTS" | jq -r ".[] | select(.name==\"$ALERT_NAME\") | .id" | head -n 1)
    
    if [ -n "$EXISTING_ALERT_ID" ] && [ "$EXISTING_ALERT_ID" != "null" ]; then
        echo "   🔄 Alerta já existe (ID: $EXISTING_ALERT_ID), removendo para recriar..."
        
        anypoint-cli-v4 api-mgr alert delete \
            --organization "$ORG_ID" \
            --environment "$ENV_ID" \
            --alertId "$EXISTING_ALERT_ID" \
            --confirm
        
        echo "   🗑️  Alerta antigo removido"
    fi
    
    echo "   📝 Criando alerta..."
    
    # Criar alerta baseado no tipo de condição
    case $CONDITION_TYPE in
        "response-code")
            CODES=$(yq eval ".alerts[$i].condition.codes[]" $CONFIG_FILE | tr '\n' ',' | sed 's/,$//')
            THRESHOLD=$(yq eval ".alerts[$i].condition.threshold" $CONFIG_FILE)
            PERIOD=$(yq eval ".alerts[$i].condition.periodMinutes" $CONFIG_FILE)
            
            anypoint-cli-v4 api-mgr alert create \
                --organization "$ORG_ID" \
                --environment "$ENV_ID" \
                --apiId "$API_ID" \
                --name "$ALERT_NAME" \
                --severity "$ALERT_SEVERITY" \
                --type "response-code" \
                --responseCodes "$CODES" \
                --threshold "$THRESHOLD" \
                --periodMinutes "$PERIOD" \
                --recipients "$RECIPIENTS" || echo "   ⚠️  Erro ao criar alerta"
            ;;
            
        "response-time")
            THRESHOLD_MS=$(yq eval ".alerts[$i].condition.thresholdMs" $CONFIG_FILE)
            PERCENTILE=$(yq eval ".alerts[$i].condition.percentile" $CONFIG_FILE)
            PERIOD=$(yq eval ".alerts[$i].condition.periodMinutes" $CONFIG_FILE)
            
            anypoint-cli-v4 api-mgr alert create \
                --organization "$ORG_ID" \
                --environment "$ENV_ID" \
                --apiId "$API_ID" \
                --name "$ALERT_NAME" \
                --severity "$ALERT_SEVERITY" \
                --type "response-time" \
                --responseTime "$THRESHOLD_MS" \
                --percentile "$PERCENTILE" \
                --periodMinutes "$PERIOD" \
                --recipients "$RECIPIENTS" || echo "   ⚠️  Erro ao criar alerta"
            ;;
            
        "request-count")
            THRESHOLD=$(yq eval ".alerts[$i].condition.threshold" $CONFIG_FILE)
            PERIOD=$(yq eval ".alerts[$i].condition.periodMinutes" $CONFIG_FILE)
            
            anypoint-cli-v4 api-mgr alert create \
                --organization "$ORG_ID" \
                --environment "$ENV_ID" \
                --apiId "$API_ID" \
                --name "$ALERT_NAME" \
                --severity "$ALERT_SEVERITY" \
                --type "request-count" \
                --threshold "$THRESHOLD" \
                --periodMinutes "$PERIOD" \
                --recipients "$RECIPIENTS" || echo "   ⚠️  Erro ao criar alerta"
            ;;
            
        *)
            echo "   ⚠️  Tipo de alerta não suportado: $CONDITION_TYPE"
            ;;
    esac
    
    if [ $? -eq 0 ]; then
        echo "   ✅ Alerta criado com sucesso!"
    else
        echo "   ⚠️  Aviso: Não foi possível criar o alerta $ALERT_NAME"
        echo "   Verifique se sua organização tem permissões para criar alertas"
        echo "   e se a configuração está correta."
    fi
done

echo ""
echo "=================================================="
echo "✅ Configuração de alertas concluída"
echo "=================================================="

