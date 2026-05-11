@echo off
REM =============================================================================
REM deploy_kubernet.cmd — Build and deploy assessment to local Kubernetes
REM Namespace: kube-node-lease
REM Requires: Docker Desktop with Kubernetes enabled, minikube, or kind
REM Usage: deploy_kubernet.cmd [start|stop|restart|logs|status]
REM =============================================================================

set IMAGE_NAME=assessment
set IMAGE_TAG=local
set NAMESPACE=kube-node-lease
set APP_LABEL=app.kubernetes.io/name=assessment

if "%~1"=="" goto start
if /i "%~1"=="start" goto start
if /i "%~1"=="stop" goto stop
if /i "%~1"=="restart" goto restart
if /i "%~1"=="logs" goto logs
if /i "%~1"=="status" goto status
goto usage

REM ======================== START ========================
:start
echo =========================================
echo  Assessment — Local Kubernetes Deploy
echo  Namespace: %NAMESPACE%
echo =========================================

REM 1. Build Docker image locally
echo [1/3] Building Docker image %IMAGE_NAME%:%IMAGE_TAG%...
docker build -t %IMAGE_NAME%:%IMAGE_TAG% .
if %errorlevel% neq 0 (
    echo ERROR: Docker build failed.
    exit /b 1
)

REM Detect current kubectl context for local cluster image handling
for /f "usebackq tokens=*" %%c in (`kubectl config current-context 2^>nul`) do set "KUBE_CONTEXT=%%c"
if not defined KUBE_CONTEXT (
    echo ERROR: failed to read kubectl current-context. Is kubectl configured?
    exit /b 1
)
echo Current kubectl context: %KUBE_CONTEXT%

set "KIND_CLUSTER_NAME=%KUBE_CONTEXT%"
if /i "%KUBE_CONTEXT%"=="kind" (
    set "KIND_CLUSTER_NAME=kind"
) else if /i "%KUBE_CONTEXT:kind-=%" neq "%KUBE_CONTEXT%" (
    set "KIND_CLUSTER_NAME=%KUBE_CONTEXT:kind-=%"
)

if /i "%KUBE_CONTEXT%"=="kind" if not "%KIND_CLUSTER_NAME%"=="kind" set "KIND_CLUSTER_NAME=kind"

if /i "%KUBE_CONTEXT%"=="kind" ( 
    echo [1b/3] Loading image into kind cluster '%KIND_CLUSTER_NAME%'...
    kind load docker-image %IMAGE_NAME%:%IMAGE_TAG% --name %KIND_CLUSTER_NAME%
    if %errorlevel% neq 0 (
        echo ERROR: Failed to load image into kind cluster.
        exit /b 1
    )
) else if /i "%KUBE_CONTEXT:kind-=%" neq "%KUBE_CONTEXT%" (
    echo [1b/3] Loading image into kind cluster '%KIND_CLUSTER_NAME%'...
    kind load docker-image %IMAGE_NAME%:%IMAGE_TAG% --name %KIND_CLUSTER_NAME%
    if %errorlevel% neq 0 (
        echo ERROR: Failed to load image into kind cluster.
        exit /b 1
    )
) else if /i "%KUBE_CONTEXT%"=="minikube" (
    echo [1b/3] Loading image into minikube...
    minikube image load %IMAGE_NAME%:%IMAGE_TAG%
    if %errorlevel% neq 0 (
        echo ERROR: Failed to load image into minikube.
        exit /b 1
    )
) else (
    echo [1b/3] Using local image in current cluster context.
)

REM 2. Generate local K8s manifests with namespace override and local image
echo [2/3] Generating local manifests...
set "TEMP_DIR=%TEMP%\assessment-k8s-local"
if not exist "%TEMP_DIR%" mkdir "%TEMP_DIR%"

REM -- ConfigMap
(
echo apiVersion: v1
echo kind: ConfigMap
echo metadata:
echo   name: assessment-config
echo   namespace: %NAMESPACE%
echo   labels:
echo     app.kubernetes.io/name: assessment
echo data:
echo   INTEGRATION_UPSTREAM_URL: "http://localhost:8080/upstream/process"
echo   OTEL_SAMPLING_PROBABILITY: "1.0"
echo   DEMO_FAILURE_RATE: "0.6"
echo   DEMO_LATENCY_MS: "0"
echo   JAVA_OPTS: "-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -XX:InitialRAMPercentage=50.0 -Djava.security.egd=file:/dev/./urandom"
) > "%TEMP_DIR%\configmap.yml"

REM -- Deployment (1 replica, local image, imagePullPolicy Never)
(
echo apiVersion: apps/v1
echo kind: Deployment
echo metadata:
echo   name: assessment
echo   namespace: %NAMESPACE%
echo   labels:
echo     app.kubernetes.io/name: assessment
echo     app.kubernetes.io/version: "0.0.1"
echo spec:
echo   replicas: 1
echo   revisionHistoryLimit: 3
echo   selector:
echo     matchLabels:
echo       app.kubernetes.io/name: assessment
echo   strategy:
echo     type: RollingUpdate
echo     rollingUpdate:
echo       maxSurge: 1
echo       maxUnavailable: 0
echo   template:
echo     metadata:
echo       labels:
echo         app.kubernetes.io/name: assessment
echo         app.kubernetes.io/version: "0.0.1"
echo     spec:
echo       terminationGracePeriodSeconds: 60
echo       containers:
echo         - name: assessment
echo           image: %IMAGE_NAME%:%IMAGE_TAG%
echo           imagePullPolicy: IfNotPresent
echo           ports:
echo             - name: http
echo               containerPort: 8080
echo               protocol: TCP
echo           envFrom:
echo             - configMapRef:
echo                 name: assessment-config
echo           resources:
echo             requests:
echo               cpu: 250m
echo               memory: 512Mi
echo             limits:
echo               cpu: "1"
echo               memory: 1Gi
echo           livenessProbe:
echo             httpGet:
echo               path: /actuator/health/liveness
echo               port: http
echo             initialDelaySeconds: 30
echo             periodSeconds: 10
echo             timeoutSeconds: 5
echo             failureThreshold: 3
echo           readinessProbe:
echo             httpGet:
echo               path: /actuator/health/readiness
echo               port: http
echo             initialDelaySeconds: 15
echo             periodSeconds: 5
echo             timeoutSeconds: 3
echo             failureThreshold: 3
echo           startupProbe:
echo             httpGet:
echo               path: /actuator/health/liveness
echo               port: http
echo             initialDelaySeconds: 10
echo             periodSeconds: 5
echo             failureThreshold: 12
echo           lifecycle:
echo             preStop:
echo               exec:
echo                 command: ["sleep", "10"]
) > "%TEMP_DIR%\deployment.yml"

REM -- Service (NodePort for local access)
(
echo apiVersion: v1
echo kind: Service
echo metadata:
echo   name: assessment
echo   namespace: %NAMESPACE%
echo   labels:
echo     app.kubernetes.io/name: assessment
echo spec:
echo   type: NodePort
echo   ports:
echo     - name: http
echo       port: 80
echo       targetPort: http
echo       nodePort: 30080
echo       protocol: TCP
echo   selector:
echo     app.kubernetes.io/name: assessment
) > "%TEMP_DIR%\service.yml"

REM 3. Apply manifests
echo [3/3] Applying manifests to namespace %NAMESPACE%...

kubectl get namespace %NAMESPACE% >nul 2>&1
if %errorlevel% neq 0 (
    echo Creating namespace %NAMESPACE%...
    kubectl create namespace %NAMESPACE%
    if %errorlevel% neq 0 (
        echo ERROR: Failed to create namespace %NAMESPACE%.
        exit /b 1
    )
)

kubectl apply -f "%TEMP_DIR%\configmap.yml"
if %errorlevel% neq 0 exit /b 1

kubectl apply -f "%TEMP_DIR%\deployment.yml"
if %errorlevel% neq 0 exit /b 1

kubectl apply -f "%TEMP_DIR%\service.yml"
if %errorlevel% neq 0 exit /b 1

REM Cleanup temp files
rmdir /s /q "%TEMP_DIR%" >nul 2>&1

echo.
echo Waiting for rollout...
kubectl rollout status deployment/assessment -n %NAMESPACE% --timeout=120s

echo.
echo =========================================
echo  Deployment complete!
echo  App accessible at: http://localhost:30080
echo  Health: http://localhost:30080/actuator/health
echo.
echo  kubectl get pods -n %NAMESPACE%
echo  kubectl logs -n %NAMESPACE% -l %APP_LABEL% -f
echo =========================================
goto end

REM ======================== STOP ========================
:stop
echo Removing assessment from namespace %NAMESPACE%...
kubectl delete deployment assessment -n %NAMESPACE% --ignore-not-found
kubectl delete service assessment -n %NAMESPACE% --ignore-not-found
kubectl delete configmap assessment-config -n %NAMESPACE% --ignore-not-found
echo Stopped.
goto end

REM ======================== RESTART ========================
:restart
call "%~f0" stop
call "%~f0" start
goto end

REM ======================== LOGS ========================
:logs
kubectl logs -n %NAMESPACE% -l %APP_LABEL% -f --tail=100
goto end

REM ======================== STATUS ========================
:status
echo --- Pods ---
kubectl get pods -n %NAMESPACE% -l %APP_LABEL% -o wide
echo.
echo --- Service ---
kubectl get svc assessment -n %NAMESPACE%
echo.
echo --- Health ---
curl -s http://localhost:30080/actuator/health 2>nul || echo (health endpoint not reachable)
goto end

REM ======================== USAGE ========================
:usage
echo Usage: %~nx0 [start^|stop^|restart^|logs^|status]
exit /b 1

:end
