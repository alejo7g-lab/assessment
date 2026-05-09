@echo off
REM =============================================================================
REM deploy_local.cmd — Build and run assessment locally with Docker Desktop
REM Usage: deploy_local.cmd [start|stop|restart|logs|status]
REM =============================================================================

set IMAGE_NAME=assessment
set IMAGE_TAG=local
set CONTAINER_NAME=assessment-local
set PORT=8080

if "%~1"=="" goto start
if /i "%~1"=="start" goto start
if /i "%~1"=="stop" goto stop
if /i "%~1"=="restart" goto restart
if /i "%~1"=="logs" goto logs
if /i "%~1"=="status" goto status
goto usage

:start
echo =========================================
echo  Assessment — Local Docker Deploy
echo =========================================

echo [1/2] Building Docker image...
docker build -t %IMAGE_NAME%:%IMAGE_TAG% .
if %errorlevel% neq 0 (
    echo ERROR: Docker build failed.
    exit /b 1
)

REM Remove previous container if exists
docker rm -f %CONTAINER_NAME% >nul 2>&1

echo [2/2] Starting container on port %PORT%...
docker run -d ^
  --name %CONTAINER_NAME% ^
  -p %PORT%:8080 ^
  -e INTEGRATION_UPSTREAM_URL=http://localhost:8080/upstream/process ^
  -e DEMO_FAILURE_RATE=0.6 ^
  -e DEMO_LATENCY_MS=0 ^
  -e OTEL_SAMPLING_PROBABILITY=1.0 ^
  %IMAGE_NAME%:%IMAGE_TAG%
if %errorlevel% neq 0 (
    echo ERROR: Failed to start container.
    exit /b 1
)

echo.
echo Waiting for app to start...
set /a ATTEMPTS=0
:healthcheck
if %ATTEMPTS% geq 30 goto timeout
curl -sf http://localhost:%PORT%/actuator/health/liveness >nul 2>&1
if %errorlevel% equ 0 goto healthy
set /a ATTEMPTS+=1
<nul set /p =.
timeout /t 2 /nobreak >nul
goto healthcheck

:healthy
echo.
echo =========================================
echo  App is running at http://localhost:%PORT%
echo  Health:  http://localhost:%PORT%/actuator/health
echo  Logs:    docker logs -f %CONTAINER_NAME%
echo =========================================
goto end

:timeout
echo.
echo WARNING: App did not become healthy in 60s. Check logs:
echo   docker logs %CONTAINER_NAME%
goto end

:stop
echo Stopping %CONTAINER_NAME%...
docker stop %CONTAINER_NAME% >nul 2>&1
docker rm %CONTAINER_NAME% >nul 2>&1
echo Stopped.
goto end

:restart
call "%~f0" stop
call "%~f0" start
goto end

:logs
docker logs -f %CONTAINER_NAME%
goto end

:status
for /f "tokens=*" %%s in ('docker ps --filter "name=%CONTAINER_NAME%" --format "{{.Status}}" 2^>nul') do set CSTATUS=%%s
if defined CSTATUS (
    echo Container: %CONTAINER_NAME%
    echo Status:    %CSTATUS%
    echo URL:       http://localhost:%PORT%
    echo.
    curl -s http://localhost:%PORT%/actuator/health 2>nul || echo (health endpoint not reachable)
) else (
    echo Container %CONTAINER_NAME% is not running.
)
goto end

:usage
echo Usage: %~nx0 [start^|stop^|restart^|logs^|status]
exit /b 1

:end
