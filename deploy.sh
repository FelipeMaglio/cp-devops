#!/usr/bin/env bash
# Deploy completo do DimDim no Azure via Azure CLI
# Uso: az login && ./scripts/deploy.sh
set -e

# ---------- VARIÁVEIS (ajuste) ----------
SUFIXO=$RANDOM
RG=rg-dimdim
LOCATION=brazilsouth            # se o SQL não tiver capacidade, use eastus2
SQL_SERVER=sqlsrv-dimdim-$SUFIXO
SQL_DB=dimdimdb
SQL_ADMIN=dimdimadmin
SQL_PASS='TroqueEssaSenha@123'
PLAN=plan-dimdim
APP=webapp-dimdim-$SUFIXO
AI=ai-dimdim
MEU_IP=$(curl -s https://api.ipify.org)

# ---------- RESOURCE GROUP ----------
az group create -n $RG -l $LOCATION

# ---------- AZURE SQL (PaaS) ----------
az sql server create -g $RG -n $SQL_SERVER -l $LOCATION \
  --admin-user $SQL_ADMIN --admin-password "$SQL_PASS"

# Permite serviços do Azure (Web App) e o seu IP (para rodar o DDL)
az sql server firewall-rule create -g $RG -s $SQL_SERVER -n AllowAzure \
  --start-ip-address 0.0.0.0 --end-ip-address 0.0.0.0
az sql server firewall-rule create -g $RG -s $SQL_SERVER -n MeuIP \
  --start-ip-address $MEU_IP --end-ip-address $MEU_IP

az sql db create -g $RG -s $SQL_SERVER -n $SQL_DB --service-objective Basic

# ---------- DDL (requer sqlcmd; senão rode sql/ddl.sql no Query editor do portal) ----------
sqlcmd -S $SQL_SERVER.database.windows.net -d $SQL_DB -U $SQL_ADMIN -P "$SQL_PASS" -i sql/ddl.sql

# ---------- APPLICATION INSIGHTS ----------
az extension add -n application-insights --yes
az monitor app-insights component create --app $AI -l $LOCATION -g $RG --application-type web
AI_CONN=$(az monitor app-insights component show --app $AI -g $RG --query connectionString -o tsv)

# ---------- APP SERVICE (Java 17) ----------
az appservice plan create -g $RG -n $PLAN --sku B1 --is-linux
az webapp create -g $RG -p $PLAN -n $APP --runtime "JAVA:17-java17"

JDBC="jdbc:sqlserver://$SQL_SERVER.database.windows.net:1433;database=$SQL_DB;encrypt=true;trustServerCertificate=false;loginTimeout=30;"

az webapp config appsettings set -g $RG -n $APP --settings \
  WEBSITES_PORT=8080 \
  DB_URL="$JDBC" \
  DB_USER="$SQL_ADMIN" \
  DB_PASS="$SQL_PASS" \
  APPLICATIONINSIGHTS_CONNECTION_STRING="$AI_CONN" \
  ApplicationInsightsAgent_EXTENSION_VERSION="~3"

# ---------- BUILD + DEPLOY ----------
mvn clean package -DskipTests
az webapp deploy -g $RG -n $APP --src-path target/app.jar --type jar

echo ""
echo "App no ar: https://$APP.azurewebsites.net/api/clientes"
echo "Para apagar tudo: az group delete -n $RG --yes --no-wait"
