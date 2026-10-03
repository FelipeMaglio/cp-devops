#!/bin/bash
set -e

# ===================== CONFIGURAÇÕES =====================
RG="rg-dimdim"
LOCATION="eastus"                       # região do Web App / App Insights (a que funcionou no deploy anterior)
SQL_LOCATIONS=("eastus" "eastus2" "centralus" "westus3" "brazilsouth")   # tenta em ordem até o SQL aceitar
SUFIXO=$RANDOM
SQL_SERVER="sqlsrv-dimdim-$SUFIXO"      # único globalmente (minúsculo)
SQL_DB="dimdimdb"
SQL_ADMIN="dimdimadmin"
PLAN="plan-dimdim"
APP="webapp-dimdim-$SUFIXO"             # único globalmente
AI="ai-dimdim"

# Senha gerada na hora - não fica salva em nenhum arquivo do repo
SQL_PASS="Dim$(openssl rand -hex 6 | tr -d '\r\n')Aa1"
# ===========================================================

add_gitignore() {
  touch .gitignore
  grep -qxF "$1" .gitignore || echo "$1" >> .gitignore
}

echo ">> 1) Criando o Resource Group..."
az group create --name "$RG" --location "$LOCATION"

echo ">> 2) Criando o SQL Server (tenta várias regiões se faltar capacidade)..."
SQL_REGION=""
for R in "${SQL_LOCATIONS[@]}"; do
  echo "   Tentando $R..."
  if az sql server create -g "$RG" -n "$SQL_SERVER" -l "$R" \
       --admin-user "$SQL_ADMIN" --admin-password "$SQL_PASS" >/dev/null; then
    SQL_REGION="$R"
    echo "   SQL Server criado em $R."
    break
  fi
  az sql server delete -g "$RG" -n "$SQL_SERVER" --yes >/dev/null 2>&1 || true
done
if [ -z "$SQL_REGION" ]; then
  echo "Nenhuma região aceitou criar o SQL Server. Tente outra região em SQL_LOCATIONS."
  exit 1
fi

echo ">> 3) Regras de firewall (serviços Azure + seu IP) e criação do banco..."
MEU_IP=$(curl -s https://api.ipify.org | tr -d '\r\n')
az sql server firewall-rule create -g "$RG" -s "$SQL_SERVER" -n AllowAzure \
  --start-ip-address 0.0.0.0 --end-ip-address 0.0.0.0
az sql server firewall-rule create -g "$RG" -s "$SQL_SERVER" -n MeuIP \
  --start-ip-address "$MEU_IP" --end-ip-address "$MEU_IP"
az sql db create -g "$RG" -s "$SQL_SERVER" -n "$SQL_DB" --service-objective Basic

echo ">> 4) Executando o DDL..."
if command -v sqlcmd >/dev/null 2>&1; then
  sqlcmd -S "$SQL_SERVER.database.windows.net" -d "$SQL_DB" -U "$SQL_ADMIN" -P "$SQL_PASS" -i ddl.sql
else
  echo "   !! sqlcmd não encontrado. Rode o ddl.sql manualmente no Query editor do portal"
  echo "      (SQL databases > $SQL_DB > Query editor), usando usuário/senha do deploy-secrets.txt."
  echo "      Depois de rodar, pressione ENTER para continuar..."
  # a senha precisa estar salva antes da pausa
  cat > deploy-secrets.txt <<EOT
Gerado em: $(date)
SQL Server: $SQL_SERVER.database.windows.net
Banco: $SQL_DB
Usuario: $SQL_ADMIN
Senha: $SQL_PASS
EOT
  add_gitignore "deploy-secrets.txt"
  read -r _
fi

echo ">> 5) Criando o Application Insights..."
az extension add -n application-insights --yes >/dev/null 2>&1 || true
az monitor app-insights component create --app "$AI" -l "$LOCATION" -g "$RG" --application-type web
AI_CONN=$(az monitor app-insights component show --app "$AI" -g "$RG" --query connectionString -o tsv)

echo ">> 6) Criando App Service Plan e Web App (Java 17)..."
az appservice plan create -g "$RG" -n "$PLAN" --sku B1 --is-linux
az webapp create -g "$RG" -p "$PLAN" -n "$APP" --runtime "JAVA:17-java17"

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

echo ">> 9) Aguardando a aplicação subir..."
for i in $(seq 1 12); do
  CODE=$(curl -s -o /dev/null -w "%{http_code}" "https://$APP.azurewebsites.net/" || true)
  [ "$CODE" = "200" ] && { echo "   App respondeu 200."; break; }
  echo "   ainda subindo (HTTP $CODE)... aguardando 15s"
  sleep 15
done

# Credenciais geradas ficam só localmente (nunca commitar)
cat > deploy-secrets.txt <<EOT
Gerado em: $(date)
Web App: https://$APP.azurewebsites.net
SQL Server: $SQL_SERVER.database.windows.net  (região: $SQL_REGION)
Banco: $SQL_DB
Usuario: $SQL_ADMIN
Senha: $SQL_PASS
EOT
add_gitignore "deploy-secrets.txt"

echo ""
echo "App no ar:  https://$APP.azurewebsites.net/api/clientes"
echo "Banco:      $SQL_SERVER.database.windows.net / $SQL_DB / usuário $SQL_ADMIN (senha em deploy-secrets.txt)"
echo "Logs do app: az webapp log tail -g $RG -n $APP"
echo "Apagar tudo no final: az group delete --name $RG --yes --no-wait"
