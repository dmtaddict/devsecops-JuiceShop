# Usage:  .\setup.ps1          (запуск)
#         .\setup.ps1 -Down    (остановка и очистка)

param([switch]$Down)

$ClusterName   = "devsecops"
$RegistryName  = "kind-registry"
$RegistryPort  = "5001"
$JenkinsImage  = "jenkins-devsecops:latest"
$Namespace     = "devsecops"
$ScriptDir     = Split-Path -Parent $MyInvocation.MyCommand.Path

function Info { param($m) Write-Host "==> $m" -ForegroundColor Cyan }
function Ok   { param($m) Write-Host "[OK] $m" -ForegroundColor Green }
function Warn { param($m) Write-Host "[!]  $m" -ForegroundColor Yellow }
function Fail { param($m) Write-Host "[X]  $m" -ForegroundColor Red; exit 1 }

# Проверяет $LASTEXITCODE после внешней команды; печатает Fail и выходит при ошибке
function Check {
    param($m)
    if ($LASTEXITCODE -ne 0) { Fail $m }
}

# Остановка и очистка
if ($Down) {
    Info "Removing kind cluster and registry..."
    kind delete cluster --name $ClusterName 2>$null
    if ($LASTEXITCODE -ne 0) { Warn "kind delete cluster returned non-zero (cluster may not have existed)" }
    docker rm -f $RegistryName 2>$null
    if ($LASTEXITCODE -ne 0) { Warn "docker rm returned non-zero (registry may not have existed)" }
    Write-Host "Done. All resources removed." -ForegroundColor Green
    exit 0
}

# Проверяем наличие требуемых утилит
Info "Checking prerequisites..."
$requiredFiles = @(
        "jenkins/Dockerfile"
        "Jenkinsfile"
        "k8s/jenkins-deployment.yaml"
        "k8s/pvcs.yaml"
        "k8s/jenkins-casc-config.yaml"
    )
$requiredCmd = @(
        "docker"
        "kind"
        "kubectl"
    )
foreach ($file in $requiredFiles) {
    $path = Join-Path -Path $ScriptDir -ChildPath $file

    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Fail "Required file not found: $file"
    }
}
foreach ($cmd in $requiredCmd) {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
        Fail "$cmd not found. Install: winget install Kubernetes.$cmd (or Docker.$cmd for docker)"
    }
}

$dockerCheck = & docker info 2>&1
Check "Docker Desktop is not running. Please start it."
Ok "docker, kind, kubectl - OK"

# Запускаем локальный registry
Info "Starting local registry..."
$running = docker inspect -f '{{.State.Running}}' $RegistryName 2>$null
if ($running -eq "true") {
    Warn "Registry already running - skipping"
} else {
    docker run -d --restart=always `
        -p "127.0.0.1:${RegistryPort}:5000" `
        --name $RegistryName `
        registry:2 | Out-Null
    Check "Failed to start local registry."
    Ok "Registry started at localhost:${RegistryPort}"
}

# Создаём кластер kind
Info "Creating kind cluster '${ClusterName}'..."
$existingClusters = kind get clusters 2>$null
if ($existingClusters -match $ClusterName) {
    Warn "Cluster already exists - skipping"
} else {
    $kindConfig = @"
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
containerdConfigPatches:
- |-
  [plugins."io.containerd.grpc.v1.cri".registry]
    [plugins."io.containerd.grpc.v1.cri".registry.mirrors]
      [plugins."io.containerd.grpc.v1.cri".registry.mirrors."localhost:${RegistryPort}"]
        endpoint = ["http://${RegistryName}:5000"]
      [plugins."io.containerd.grpc.v1.cri".registry.mirrors."${RegistryName}:5000"]
        endpoint = ["http://${RegistryName}:5000"]
nodes:
- role: control-plane
  extraPortMappings:
  - containerPort: 30080
    hostPort: 8090
    protocol: TCP
"@
    $kindConfig | kind create cluster --name $ClusterName --config=-
    Check "Failed to create kind cluster."
    Ok "Cluster created"
}

# Подключаем registry докера к сети kind
docker network connect "kind" $RegistryName 2>$null
if ($LASTEXITCODE -ne 0) { Warn "Registry already connected to kind network (or connect failed - check manually if issues arise)" }

# Собираем образ Jenkins
Info "Building Jenkins image with plugins..."
$jenkinsDir = Join-Path $ScriptDir "jenkins"
docker build -t $JenkinsImage $jenkinsDir
Check "Failed to build Jenkins image."
Ok "Image $JenkinsImage built"

# Загружаем образ Jenkins вkind
Info "Loading Jenkins image into kind cluster..."
kind load docker-image $JenkinsImage --name $ClusterName
Check "Failed to load image into kind."
Ok "Image loaded"

# Применяем манифесты
Info "Applying Kubernetes manifests..."
$k8s = Join-Path $ScriptDir "k8s"

kubectl apply -f (Join-Path $k8s "jenkins-deployment.yaml")
Check "Failed to apply jenkins-deployment.yaml"
Ok "Namespace, RBAC, Service, Deployment applied"

kubectl apply -f (Join-Path $k8s "pvcs.yaml")
Check "Failed to apply pvcs.yaml"
Ok "PVCs created"

kubectl apply -f (Join-Path $k8s "jenkins-casc-config.yaml")
Check "Failed to apply jenkins-casc-config.yaml"
Ok "JCasC ConfigMap applied"

kubectl delete configmap jenkins-jenkinsfile -n $Namespace --ignore-not-found=true 2>$null
if ($LASTEXITCODE -ne 0) { Warn "Failed to delete old jenkins-jenkinsfile configmap (may not have existed)" }

$JenkinsfilePath = Join-Path $ScriptDir "Jenkinsfile"
kubectl create configmap jenkins-jenkinsfile --from-file=Jenkinsfile=$JenkinsfilePath -n $Namespace
Check "Failed to create Jenkinsfile ConfigMap."
Ok "Jenkinsfile ConfigMap applied"

# Ждём запуска Jenkins
Info "Waiting for Jenkins (~2 minutes)..."
kubectl rollout status deployment/jenkins -n $Namespace --timeout=180s
Check "Jenkins did not start. Check: kubectl logs -n $Namespace deployment/jenkins"
Ok "Jenkins is running!"

# ── Done ─────────────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "  Stand is ready!" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Jenkins UI:   http://localhost:8090"
Write-Host "  Login:        admin / admin"
Write-Host ""
Write-Host "  Registry (from host):      localhost:$RegistryPort"
Write-Host "  Registry (from K8s pods):  kind-registry:5000"
Write-Host ""
Write-Host "  Before first pipeline run:" -ForegroundColor Yellow
Write-Host "    Jenkins -> Manage Jenkins -> Credentials -> Add"
Write-Host "    Kind: Secret text, ID: nvd-api-key"
Write-Host ""
Write-Host "  To update Jenkinsfile without full restart:" -ForegroundColor Cyan
Write-Host "    kubectl delete configmap jenkins-jenkinsfile -n $Namespace"
Write-Host "    kubectl create configmap jenkins-jenkinsfile --from-file=Jenkinsfile=.\Jenkinsfile -n $Namespace"
Write-Host ""
Write-Host "  Stop: .\setup.ps1 -Down"
Write-Host "============================================================" -ForegroundColor Green