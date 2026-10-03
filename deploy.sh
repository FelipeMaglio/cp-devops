#!/bin/bash
set -e

# ===================== CONFIGURAÇÕES =====================
RG="rg-dimdim"
RG_LOCATION="eastus"                    # só a "pasta" do Resource Group
# Regiões permitidas pela política da assinatura (ordem de tentativa)
ALLOWED_REGIONS=("southafricanorth" "chilecentral" "eastus2" "eastus" "southcentralus")
SQL_DB="dimdimdb"
SQL_ADMIN="dimdimadmin"
PLAN="plan-dimdim"
APP="webapp-dimdim-$RANDOM"             # único globalmente
AI="ai-dimdim"

# Senha gerada na hora - não fica salva em nenhum arquivo do repo
SQL_PASS="Dim$(openssl rand -hex 6 | tr -d '\r\n')Aa1"
# ===========================================================

add_gitignore() {
  touch .gitignore
  grep -qxF "$1" .gitignore || echo "$1" >> .gitignore
}

echo ">> 1) Criando o Resource Group..."
az group create --name "$RG" --location "$RG_LOCATION" --output none

echo ">> 2) Criando o SQL Server (testa as regiões permitidas, nome novo a cada tentativa)..."
SQL_REGION=""
SQL_SERVER=""
for R in "${ALLOWED_REGIONS[@]}"; do
  TRY_NAME="sqlsrv-dimdim-$RANDOM$RANDOM"
  echo "   Tentando $R ($TRY_NAME)..."
  if az sql server create -g "$RG" -n "$TRY_NAME" -l "$R" \
       --admin-user "$SQL_ADMIN" --admin-password "$SQL_PASS" --output none; then
    SQL_REGION="$R"
    SQL_SERVER="$TRY_NAME"
    echo "   SQL Server criado em $R."
    break
  fi
  az sql server delete -g "$RG" -n "$TRY_NAME" --yes >/dev/null 2>&1 || true
done
if [ -z "$SQL_REGION" ]; then
  echo "Nenhuma região permitida aceitou criar o SQL Server agora. Tente mais tarde ou use outra assinatura."
  exit 1
fi

echo ">> 3) Regras de firewall (serviços Azure + seu IP) e criação do banco..."
MEU_IP=$(curl -s https://api.ipify.org | tr -d '\r\n')
az sql server firewall-rule create -g "$RG" -s "$SQL_SERVER" -n AllowAzure \
  --start-ip-address 0.0.0.0 --end-ip-address 0.0.0.0 --output none
az sql server firewall-rule create -g "$RG" -s "$SQL_SERVER" -n MeuIP \
  --start-ip-address "$MEU_IP" --end-ip-address "$MEU_IP" --output none
az sql db create -g "$RG" -s "$SQL_SERVER" -n "$SQL_DB" --service-objective Basic --output none

# Salva as credenciais já agora (usadas no Query editor)
cat > deploy-secrets.txt <<EOT
Gerado em: $(date)
SQL Server: $SQL_SERVER.database.windows.net  (região: $SQL_REGION)
Banco: $SQL_DB
Usuario: $SQL_ADMIN
Senha: $SQL_PASS
EOT
add_gitignore "deploy-secrets.txt"

echo ">> 4) DDL: as tabelas serão criadas pela própria aplicação na primeira inicialização (ddl.sql embutido no jar)."

echo ">> 5) Criando App Service Plan (região da primeira que aceitar) e Web App (Java 17)..."
# começa pela região do SQL e depois tenta as demais permitidas
REGIOES_APP=("$SQL_REGION")
for R in "${ALLOWED_REGIONS[@]}"; do [ "$R" != "$SQL_REGION" ] && REGIOES_APP+=("$R"); done

LOCATION=""
SKU_USADO=""
for R in "${REGIOES_APP[@]}"; do
  for SKU in B1 F1; do
    echo "   Tentando plano $SKU em $R..."
    if az appservice plan create -g "$RG" -n "$PLAN" -l "$R" --sku "$SKU" --is-linux --output none; then
      LOCATION="$R"; SKU_USADO="$SKU"
      break 2
    fi
    az appservice plan delete -g "$RG" -n "$PLAN" --yes >/dev/null 2>&1 || true
  done
done
if [ -z "$LOCATION" ]; then
  echo "Nenhuma região permitida aceitou criar o App Service Plan (cota/capacidade)."
  exit 1
fi
echo "   Plano $SKU_USADO criado em $LOCATION."
az webapp create -g "$RG" -p "$PLAN" -n "$APP" --runtime "JAVA:17-java17" --output none
az webapp config set -g "$RG" -n "$APP" --always-on true --output none || true
az webapp log config -g "$RG" -n "$APP" --application-logging filesystem --level information \
  --docker-container-logging filesystem --output none || true

echo ">> 6) Criando o Application Insights (região $LOCATION)..."
az extension add -n application-insights --yes >/dev/null 2>&1 || true
az monitor app-insights component create --app "$AI" -l "$LOCATION" -g "$RG" --application-type web --output none
AI_CONN=$(az monitor app-insights component show --app "$AI" -g "$RG" --query connectionString -o tsv)

echo ">> 7) Configurando variáveis de ambiente (App Settings)..."
JDBC="jdbc:sqlserver://$SQL_SERVER.database.windows.net:1433;database=$SQL_DB;encrypt=true;trustServerCertificate=false;loginTimeout=30;"
az webapp config appsettings set -g "$RG" -n "$APP" --output none --settings \
  WEBSITES_PORT=8080 \
  DB_URL="$JDBC" \
  DB_USER="$SQL_ADMIN" \
  DB_PASS="$SQL_PASS" \
  APPLICATIONINSIGHTS_CONNECTION_STRING="$AI_CONN" \
  ApplicationInsightsAgent_EXTENSION_VERSION="~3"

echo ">> 8) Build e deploy do app.jar..."
mvn clean package -DskipTests
MAX_RETRIES=3
for i in $(seq 1 $MAX_RETRIES); do
  if az webapp deploy -g "$RG" -n "$APP" --src-path target/app.jar --type jar; then
    echo "   Deploy concluído."
    break
  fi
  [ "$i" -eq "$MAX_RETRIES" ] && { echo "Deploy falhou após $MAX_RETRIES tentativas."; exit 1; }
  echo "   Tentativa $i falhou. Aguardando 20s..."
  sleep 20
done

echo ">> 9) Aguardando a API subir (testa /api/clientes, que passa pelo banco)..."
OK=""
for i in $(seq 1 24); do
  CODE=$(curl -s -o /dev/null -w "%{http_code}" "https://$APP.azurewebsites.net/api/clientes" || true)
  if [ "$CODE" = "200" ]; then
    echo "   API respondeu 200 (aplicação e banco OK)."
    OK=1
    break
  fi
  echo "   ainda subindo (HTTP $CODE)... aguardando 15s"
  sleep 15
done
if [ -z "$OK" ]; then
  echo "   !! A API não respondeu 200. Veja o log: az webapp log tail -g $RG -n $APP"
fi

echo "Web App: https://$APP.azurewebsites.net" >> deploy-secrets.txt

echo ""
echo "App no ar:  https://$APP.azurewebsites.net/api/clientes"
echo "Banco:      $SQL_SERVER.database.windows.net / $SQL_DB / usuário $SQL_ADMIN (senha em deploy-secrets.txt)"
echo "Logs do app: az webapp log tail -g $RG -n $APP"
echo "Apagar tudo no final: az group delete --name $RG --yes --no-wait"
