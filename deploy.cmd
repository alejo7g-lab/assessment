@echo off
REM =============================================================================
REM deploy.cmd — Build, push, and deploy assessment to AKS
REM Usage: deploy.cmd <ACR_NAME> <AKS_RESOURCE_GROUP> <AKS_CLUSTER_NAME> [IMAGE_TAG]
REM Example: deploy.cmd myacr myResourceGroup myAKSCluster
REM =============================================================================

if "%~1"=="" (
    echo Usage: %~nx0 ^<ACR_NAME^> ^<AKS_RESOURCE_GROUP^> ^<AKS_CLUSTER_NAME^> [IMAGE_TAG]
    exit /b 1
)
if "%~2"=="" (
    echo ERROR: Missing AKS_RESOURCE_GROUP
    exit /b 1
)
if "%~3"=="" (
    echo ERROR: Missing AKS_CLUSTER_NAME
    exit /b 1
)

set ACR_NAME=%~1
set RESOURCE_GROUP=%~2
set CLUSTER_NAME=%~3
if "%~4"=="" (set IMAGE_TAG=latest) else (set IMAGE_TAG=%~4)

set IMAGE=%ACR_NAME%.azurecr.io/assessment:%IMAGE_TAG%

echo =========================================
echo  Assessment — AKS Deployment
echo  ACR:     %ACR_NAME%
echo  Cluster: %CLUSTER_NAME%
echo  Image:   %IMAGE%
echo =========================================

REM 1. Login to Azure Container Registry
echo [1/6] Logging in to ACR...
call az acr login --name %ACR_NAME%
if %errorlevel% neq 0 (
    echo ERROR: ACR login failed.
    exit /b 1
)

REM 2. Build Docker image
echo [2/6] Building Docker image...
docker build -t %IMAGE% .
if %errorlevel% neq 0 (
    echo ERROR: Docker build failed.
    exit /b 1
)

REM 3. Push to ACR
echo [3/6] Pushing image to ACR...
docker push %IMAGE%
if %errorlevel% neq 0 (
    echo ERROR: Docker push failed.
    exit /b 1
)

REM 4. Get AKS credentials
echo [4/6] Getting AKS credentials...
call az aks get-credentials --resource-group %RESOURCE_GROUP% --name %CLUSTER_NAME% --overwrite-existing
if %errorlevel% neq 0 (
    echo ERROR: Failed to get AKS credentials.
    exit /b 1
)

REM 5. Generate deployment manifest with actual ACR name
echo [5/6] Generating deployment manifest...
set "DEPLOY_TEMP=%TEMP%\assessment-deployment.yml"
powershell -Command "(Get-Content 'k8s\deployment.yml') -replace '\$\{ACR_NAME\}', '%ACR_NAME%' -replace ':latest', ':%IMAGE_TAG%' | Set-Content '%DEPLOY_TEMP%'"

REM 6. Apply Kubernetes manifests
echo [6/6] Applying Kubernetes manifests...
kubectl apply -f k8s\namespace.yml
if %errorlevel% neq 0 exit /b 1

kubectl apply -f k8s\configmap.yml
if %errorlevel% neq 0 exit /b 1

kubectl apply -f "%DEPLOY_TEMP%"
if %errorlevel% neq 0 exit /b 1

kubectl apply -f k8s\service.yml
if %errorlevel% neq 0 exit /b 1

kubectl apply -f k8s\hpa.yml
if %errorlevel% neq 0 exit /b 1

kubectl apply -f k8s\ingress.yml
if %errorlevel% neq 0 exit /b 1

del "%DEPLOY_TEMP%" >nul 2>&1

echo.
echo Waiting for rollout to complete...
kubectl rollout status deployment/assessment -n assessment --timeout=120s

echo.
echo =========================================
echo  Deployment complete!
echo  kubectl get pods -n assessment
echo  kubectl logs -n assessment -l app.kubernetes.io/name=assessment -f
echo =========================================
