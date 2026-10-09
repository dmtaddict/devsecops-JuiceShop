pipeline {
    agent {
        kubernetes {
            // FIX: yamlFile читает файл из workspace — но workspace не существует
            // до того как агент-под создан. Поэтому pod template должен быть inline.
            yaml """
apiVersion: v1
kind: Pod
metadata:
  namespace: devsecops
spec:
  serviceAccountName: jenkins-sa
  containers:
 
  - name: jnlp
    image: jenkins/inbound-agent:3261.v9c670a_4748a_9-1
 
  - name: trufflehog
    image: trufflesecurity/trufflehog:3.88.0
    command: ["sleep", "infinity"]
 
  - name: gitleaks
    image: zricethezav/gitleaks:v8.24.2
    command: ["sleep", "infinity"]
 
  - name: semgrep
    image: semgrep/semgrep:1.114.0
    command: ["sleep", "infinity"]
 
  - name: npm
    image: node:20-alpine
    command: ["sleep", "infinity"]
 
  - name: dependency-check
    image: owasp/dependency-check:12.1.0
    command: ["sleep", "infinity"]
    volumeMounts:
    - name: dc-cache
      mountPath: /usr/share/dependency-check/data
 
  - name: syft
    image: alpine:3.19
    command: ["sleep", "infinity"]

  - name: grype
    image: alpine:3.19
    command: ["sleep", "infinity"]

  - name: kaniko
    image: gcr.io/kaniko-project/executor:v1.23.2-debug
    command: ["sleep", "infinity"]
 
  - name: trivy
    image: aquasec/trivy:0.61.0
    command: ["sleep", "infinity"]
    volumeMounts:
    - name: trivy-cache
      mountPath: /root/.cache/trivy
 
  - name: zap
    image: ghcr.io/zaproxy/zaproxy:2.16.1
    command: ["sleep", "infinity"]
 
  - name: kubectl
    image: alpine/k8s:1.29.14
    command: ["sleep", "infinity"]
 
  - name: python
    image: python:3.11-slim
    command: ["sleep", "infinity"]
 
  volumes:
  - name: dc-cache
    persistentVolumeClaim:
      claimName: dependency-check-cache
  - name: trivy-cache
    persistentVolumeClaim:
      claimName: trivy-cache
"""
        }
    }

    options {
        timeout(time: 60, unit: 'MINUTES')
        timestamps()
    }

    environment {
        REGISTRY   = "kind-registry:5000"
        IMAGE_NAME = "juice-shop"
        IMAGE_TAG  = "v16.0.0"
        IMAGE_FULL = "kind-registry:5000/juice-shop:v16.0.0"
        NAMESPACE  = "devsecops"
        APP_URL    = "http://juice-shop.devsecops.svc.cluster.local:3000"
    }

    parameters {
        booleanParam(name: 'RUN_CLONE',      defaultValue: true,  description: 'Клонировать исходники')
        booleanParam(name: 'RUN_SECRETS',    defaultValue: true,  description: 'Secret Scan')
        booleanParam(name: 'RUN_SAST',       defaultValue: true,  description: 'Semgrep')
        booleanParam(name: 'RUN_NPM_AUDIT',  defaultValue: true,  description: 'npm audit')
        booleanParam(name: 'RUN_DEPCHECK',   defaultValue: true,  description: 'Dependency-Check')
        booleanParam(name: 'RUN_SBOM',       defaultValue: true,  description: 'Syft SBOM')
        booleanParam(name: 'RUN_GRYPE',      defaultValue: true,  description: 'Syft GRYPE')
        booleanParam(name: 'RUN_BUILD',      defaultValue: true,  description: 'Build Docker Image')
        booleanParam(name: 'RUN_TRIVY',      defaultValue: true,  description: 'Trivy scan')
        booleanParam(name: 'RUN_DEPLOY',     defaultValue: true,  description: 'Deploy')
        booleanParam(name: 'RUN_ZAP',        defaultValue: true,  description: 'OWASP ZAP')
    }
    
    stages {

        stage('1. Настройка Enviroments') {
            steps {
                sh 'mkdir -p reports'
                sh 'rm -rf vuln_app 2>/dev/null || true'
            }
        }

        stage('2. Клонирование OWASP Juice Shop') {
            when { expression { params.RUN_CLONE } }
            steps {
                sh 'git clone --depth 1 --branch ${IMAGE_TAG} https://github.com/juice-shop/juice-shop.git vuln_app'
                echo 'OWASP Juice Shop получен'
            }
        }

        stage('3. Secret Scan') {
            when { expression { params.RUN_SECRETS } }
            parallel {
                stage('Trufflehog') {
                    steps {
                        catchError(buildResult: 'UNSTABLE', stageResult: 'UNSTABLE') {
                            container('trufflehog') {
                                sh '''
                                    trufflehog filesystem vuln_app \
                                        --json \
                                        --no-update \
                                        --log-level=-1 \
                                        --results=verified,unverified \
                                        > reports/trufflehog-report.json
                                '''
                                echo "Trufflehog: отчёт сохранён"
                            }
                        }
                    }
                }
                stage('Gitleaks') {
                    steps {
                        catchError(buildResult: 'UNSTABLE', stageResult: 'UNSTABLE') {
                            container('gitleaks') {
                                sh '''
                                    gitleaks detect \
                                    --source=vuln_app \
                                    --report-format=json \
                                    --report-path=reports/gitleaks-report.json \
                                    --exit-code=0
                                '''
                                echo "Gitleaks: отчёт сохранён"
                            }
                        }
                    }
                }
            }
        }

        stage('4. SAST - Semgrep') {
            when { expression { params.RUN_SAST } }
            steps {
                catchError(buildResult: 'UNSTABLE', stageResult: 'UNSTABLE') {
                    container('semgrep') {
                        echo 'Статический анализ кода с помощью Semgrep'
                        sh '''
                            semgrep scan \
                                --config=p/owasp-top-ten \
                                --config=p/security-audit \
                                --json \
                                -o reports/semgrep-report.json \
                                vuln_app
                        '''
                        echo 'Статический анализ кода завершен'
                    }
                }
            }
        }

        stage('5. SCA - npm audit') {
            when { expression { params.RUN_NPM_AUDIT } }
            steps {
                catchError(buildResult: 'UNSTABLE', stageResult: 'UNSTABLE') {
                    container('npm') {
                        sh '''
                            apk add --no-cache git 2>/dev/null || true
                            cd vuln_app
                            #npm install --package-lock-only --ignore-scripts
                            npm install --ignore-scripts
                            #npm audit --json --package-lock-only > ../reports/npm-audit.json || true
                            npm audit --json > ../reports/npm-audit.json
                            cd ..
                        '''
                        echo 'SCA - npm audit завершен'
                    }
                }
            }
        }

        stage('6. SCA — Анализ зависимостей с помощью dependency-check') {
            when { expression { params.RUN_DEPCHECK } }
            steps {
                catchError(buildResult: 'UNSTABLE', stageResult: 'UNSTABLE') {
                    withCredentials([string(credentialsId: 'nvd-api-key', variable: 'NVD_KEY')]) {
                        container('dependency-check') {
                            sh '''
                                /usr/share/dependency-check/bin/dependency-check.sh --scan vuln_app \
                                    --exclude "**/test/**" \
                                    --exclude "**/node_modules/**" \
                                    --format JSON \
                                    --out reports \
                                    --project "Juice Shop" \
                                    --nvdApiKey \${NVD_KEY} \
                                    --failOnCVSS 7 \
                                    --enableRetired \
                                    --disableOssIndex
                            '''
                            echo "Анализ зависимостей с помощью dependency-check завершён"
                        }
                    }
                }
            }
        }

        stage('7. SBOM Generation') {
            when { expression { params.RUN_SBOM } }
            steps {
                catchError(buildResult: 'UNSTABLE', stageResult: 'UNSTABLE') {
                    retry(2) {
                        container('syft') {
                            sh """
                                apk add --no-cache curl
                                curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh \
                                    | sh -s -- -b /usr/local/bin v1.22.0
                                
                                echo "=== Проверка node_modules ==="
                                ls ${WORKSPACE}/vuln_app/node_modules | wc -l

                                syft scan dir:${WORKSPACE}/vuln_app \
                                    --source-name "${IMAGE_NAME}" \
                                    --source-version "${IMAGE_TAG}" \
                                    -o cyclonedx-json=${WORKSPACE}/reports/sbom-report.json

                                echo "=== Компонентов в SBOM ==="
                                grep -o "\\"purl\\"" ${WORKSPACE}/reports/sbom-report.json | wc -l
                            """
                        }
                    }
                echo "Генерация SBOM отчёта завершена."
                }
            }
        }

        stage('8. SCA сканирование с помощью Grype') {
            when { expression { params.RUN_GRYPE } }
            steps {
                catchError(buildResult: 'UNSTABLE', stageResult: 'UNSTABLE') {
                    retry(2) {
                        container('grype') {
                            sh """
                                apk add --no-cache curl
                                curl -sSfL https://raw.githubusercontent.com/anchore/grype/main/install.sh \
                                    | sh -s -- -b /usr/local/bin v0.114.0
                                grype sbom:${WORKSPACE}/reports/sbom-report.json -o json --file ${WORKSPACE}/reports/grype-report.json
                            """
                            echo 'SCA сканирование с помощью Grype завершено'
                        }
                    }
                }
            }
        }

        stage('9. Build Docker Image с помощью Kaniko') {
            when { expression { params.RUN_BUILD } }
            steps {
                // FIX: node:20-buster — EOL образ, deb.debian.org больше не отдаёт его репозитории.
                // Патчим Dockerfile: переключаем apt на archive.debian.org перед сборкой.
                container('python') {
                    writeFile file: 'patch_dockerfile.py', text: '''
path = "vuln_app/Dockerfile"

with open(path) as f:
    content = f.read()

old_line = "RUN apt-get update && apt-get install -y build-essential python3"
new_line = (
"RUN sed -i "
"-e 's/deb.debian.org/archive.debian.org/g' "
"-e 's/security.debian.org/archive.debian.org/g' "
"-e '/buster-updates/d' "
"/etc/apt/sources.list && "
"echo 'Acquire::Check-Valid-Until \\"false\\";' "
"> /etc/apt/apt.conf.d/99no-check-valid && "
"apt-get update && apt-get install -y build-essential python3"
)

if old_line not in content:
    raise SystemExit("ОШИБКА: маркерная строка не найдена в Dockerfile")

content = content.replace(old_line, new_line)

with open(path, "w") as f:
    f.write(content)

print("Dockerfile пропатчен успешно")
                '''

                sh '''
                    python3 patch_dockerfile.py
                    grep -q "archive.debian.org" vuln_app/Dockerfile \
                        && echo "OK: патч применён" \
                        || { echo "FAIL: патч не сработал"; exit 1; }

                '''
                }
                retry(2) {
                    container('kaniko') {
                        sh """
                            /kaniko/executor \
                                --context=dir://${WORKSPACE}/vuln_app \
                                --dockerfile=${WORKSPACE}/vuln_app/Dockerfile \
                                --destination=${IMAGE_FULL} \
                                --insecure \
                                --skip-tls-verify

                        """
                        echo "Сборка ${IMAGE_NAME} в контейнер завершена"
                    }
                }
            }
        }

        stage('10. Сканирование контейнера с помощью Trivy') {
            when { expression { params.RUN_TRIVY } }
            steps {
                catchError (buildResult: 'UNSTABLE', stageResult: 'UNSTABLE') {
                    container('trivy') {
                        echo "Сканирование Docker-образа ${IMAGE_NAME} с помощью Trivy"
                        sh """
                            trivy image \
                                --scanners vuln \
                                --severity HIGH,CRITICAL \
                                --exit-code 0 \
                                --format json \
                                -o ${WORKSPACE}/reports/trivy-image-report.json \
                                --insecure \
                                ${IMAGE_FULL}
                        """
                        echo 'Сканирование Docker-образа с помощью Trivy завершен'
                    }
                }
            }
        }

        stage('11. Деплой OWASP Juice Shop') {
            when { expression { params.RUN_DEPLOY } }
            steps {
                container('kubectl') {
                    echo "Запуск уязвимого приложения ${IMAGE_NAME}"
                        sh """
                            kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: juice-shop
  namespace: ${NAMESPACE}
  labels:
    app: juice-shop
    managed-by: jenkins
spec:
  replicas: 1
  selector:
    matchLabels:
      app: juice-shop
  template:
    metadata:
      labels:
        app: juice-shop
    spec:
      containers:
      - name: juice-shop
        image: ${IMAGE_FULL}
        ports:
        - containerPort: 3000
        readinessProbe:
          httpGet:
            path: /
            port: 3000
          initialDelaySeconds: 30
          periodSeconds: 10
        resources:
          requests:
            memory: "512Mi"
            cpu: "200m"
          limits:
            memory: "1Gi"
            cpu: "500m"
---
apiVersion: v1
kind: Service
metadata:
  name: juice-shop
  namespace: ${NAMESPACE}
spec:
  selector:
    app: juice-shop
  ports:
  - port: 3000
    targetPort: 3000
EOF
                        kubectl rollout status deployment/juice-shop \
                            -n ${NAMESPACE} --timeout=120s
                    """
                echo "Запуск уязвимого приложения завершен"
                }
            }
        }

        stage('12. DAST. Динамический анализ с помощью OWASP ZAP') {
            when { expression { params.RUN_ZAP } }
            steps {
                catchError(buildResult: 'UNSTABLE', stageResult: 'UNSTABLE') {
                    container('zap') {
                        echo 'Динамический анализ с помощью OWASP ZAP'
                        sh """
                            mkdir -p /zap/wrk
                            zap-baseline.py \
                                -t ${APP_URL} \
                                -J zap-report.json \
                                -I
                            cp /zap/wrk/zap-report.json ${WORKSPACE}/reports/zap-report.json
                        """
                        echo 'Динамический анализ завершен'
                    }
                }
            }
        }
    
        stage('13. Security Quality Gate') {
            steps {
                container('python') {
                    script {
                        // ── Пороговые значения ─────────────────────────────────
                        final int GITLEAKS_MAX      = 0    // любые секреты → блок
                        final int TRUFFLEHOG_MAX    = 0    // любые секреты → блок
                        final int GRYPE_CRIT_MAX    = 15
                        final int TRIVY_CRIT_MAX    = 20   // CRITICAL CVE в образе
                        final int TRIVY_HIGH_MAX    = 100  // HIGH CVE в образе
                        final int ZAP_HIGH_MAX      = 3    // HIGH алерты DAST
                        final int DEPCHECK_CRIT_MAX = 15   // CRITICAL из dependency-check
    
                        def R = [:]
                        def blocked = false
    
                        // ── Gitleaks ───────────────────────────────────────────
                        R.gitleaks = sh(returnStdout: true, script: """
                            python3 - <<'PYEOF'
import json
try:
    data = json.load(open("${WORKSPACE}/reports/gitleaks-report.json"))
    print(len(data) if isinstance(data, list) else 0)
except:
    print(-1)
PYEOF

                        """).trim().toInteger()

                        // ── TruffleHog (NDJSON: одна запись на строку) ─────────
                        R.trufflehog = sh(returnStdout: true, script: """
                            python3 - <<'PYEOF'
try:
    count = sum(1 for line in open("${WORKSPACE}/reports/trufflehog-report.json")
                if line.strip() and not line.startswith('time='))
    print(count)
except:
    print(-1)
PYEOF
                        """).trim().toInteger()

                        // ── Grype: CRITICAL и HIGH ──────────────────────────────
                        def grypeRaw = sh(returnStdout: true, script: """
                            python3 - <<'PYEOF'
import json
try:
    data    = json.load(open("${WORKSPACE}/reports/grype-report.json"))
    matches = data.get("matches", [])
    crit    = sum(1 for m in matches if m.get("vulnerability", {}).get("severity") == "Critical")
    high    = sum(1 for m in matches if m.get("vulnerability", {}).get("severity") == "High")
    print(f"{crit} {high}")
except:
    print("-1 -1")
PYEOF
                        """).trim().split()
                        R.grypeCrit = grypeRaw[0].toInteger()
                        R.grypeHigh = grypeRaw[1].toInteger()

                        // ── Trivy image: CRITICAL и HIGH ───────────────────────
                        def trivyRaw = sh(returnStdout: true, script: """
                            python3 - <<'PYEOF'
import json
try:
    data  = json.load(open("${WORKSPACE}/reports/trivy-image-report.json"))
    vulns = [v for r in data.get("Results", [])
            for v in (r.get("Vulnerabilities") or [])]
    crit  = sum(1 for v in vulns if v.get("Severity") == "CRITICAL")
    high  = sum(1 for v in vulns if v.get("Severity") == "HIGH")
    print(f"{crit} {high}")
except:
    print("-1 -1")
PYEOF
                        """).trim().split()
                        R.trivyCrit = trivyRaw[0].toInteger()
                        R.trivyHigh = trivyRaw[1].toInteger()

                        // ── ZAP: HIGH (riskcode >= 3) и MEDIUM (riskcode 2) ────
                        def zapRaw = sh(returnStdout: true, script: """
                            python3 - <<'PYEOF'
import json
try:
    data   = json.load(open("${WORKSPACE}/reports/zap-report.json"))
    alerts = [a for site in data.get("site", [])
                for a in site.get("alerts", [])]
    high   = sum(1 for a in alerts if int(a.get("riskcode", 0)) >= 3)
    medium = sum(1 for a in alerts if int(a.get("riskcode", 0)) == 2)
    print(f"{high} {medium}")
except:
    print("-1 -1")
PYEOF
                        """).trim().split()
                        R.zapHigh   = zapRaw[0].toInteger()
                        R.zapMedium = zapRaw[1].toInteger()

                        // ── Dependency-Check: CRITICAL CVE ─────────────────────
                        R.depCrit = sh(returnStdout: true, script: """
                            python3 - <<'PYEOF'
import json
try:
    data  = json.load(open("${WORKSPACE}/reports/dependency-check-report.json"))
    vulns = [v for d in data.get("dependencies", [])
            for v in (d.get("vulnerabilities") or [])]
    print(sum(1 for v in vulns if v.get("severity", "").upper() == "CRITICAL"))
except:
    print(-1)
PYEOF
                        """).trim().toInteger()

                        // ── Вывод результатов ──────────────────────────────────
                        def fmt  = { v -> v == -1 ? 'N/A  ' : v.toString().padRight(5) }
                        def icon = { pass -> pass ? 'PASS' : 'FAIL' }
                        def ok   = { v, max -> v == -1 || v <= max }

                        echo """
============================================================
SECURITY QUALITY GATE — РЕЗУЛЬТАТЫ
============================================================
СЕКРЕТЫ
Gitleaks         : ${fmt(R.gitleaks)}  (порог: ${GITLEAKS_MAX})    ${icon(ok(R.gitleaks, GITLEAKS_MAX))}
TruffleHog       : ${fmt(R.trufflehog)}  (порог: ${TRUFFLEHOG_MAX})    ${icon(ok(R.trufflehog, TRUFFLEHOG_MAX))}
------------------------------------------------------------
SUPPLY CHAIN (Grype, по SBOM)
CRITICAL         : ${fmt(R.grypeCrit)}  (порог: ${GRYPE_CRIT_MAX})   ${icon(ok(R.grypeCrit, GRYPE_CRIT_MAX))}
------------------------------------------------------------
УЯЗВИМОСТИ ОБРАЗА (Trivy)
CRITICAL         : ${fmt(R.trivyCrit)}  (порог: ${TRIVY_CRIT_MAX})   ${icon(ok(R.trivyCrit, TRIVY_CRIT_MAX))}
HIGH             : ${fmt(R.trivyHigh)}  (порог: ${TRIVY_HIGH_MAX})  ${icon(ok(R.trivyHigh, TRIVY_HIGH_MAX))}
------------------------------------------------------------
DAST — ZAP
HIGH алерты      : ${fmt(R.zapHigh)}  (порог: ${ZAP_HIGH_MAX})    ${icon(ok(R.zapHigh, ZAP_HIGH_MAX))}
MEDIUM алерты    : ${fmt(R.zapMedium)}  (инфо)
------------------------------------------------------------
ЗАВИСИМОСТИ (Dependency-Check)
CRITICAL CVE     : ${fmt(R.depCrit)}  (порог: ${DEPCHECK_CRIT_MAX})   ${icon(ok(R.depCrit, DEPCHECK_CRIT_MAX))}
============================================================"""

                        // ── Принять решение ────────────────────────────────────
                        if (R.gitleaks   > GITLEAKS_MAX)      { echo "BLOCKED: Gitleaks нашёл ${R.gitleaks} секретов";           blocked = true }
                        if (R.trufflehog > TRUFFLEHOG_MAX)    { echo "BLOCKED: TruffleHog нашёл ${R.trufflehog} секретов";       blocked = true }
                        if (R.grypeCrit  > GRYPE_CRIT_MAX)    { echo "BLOCKED: ${R.grypeCrit} CRITICAL уязвимостей (Grype)";     blocked = true }
                        if (R.trivyCrit  > TRIVY_CRIT_MAX)    { echo "BLOCKED: ${R.trivyCrit} CRITICAL уязвимостей в образе";    blocked = true }
                        if (R.trivyHigh  > TRIVY_HIGH_MAX)    { echo "BLOCKED: ${R.trivyHigh} HIGH уязвимостей в образе";        blocked = true }
                        if (R.zapHigh    > ZAP_HIGH_MAX)      { echo "BLOCKED: ZAP нашёл ${R.zapHigh} HIGH алертов";             blocked = true }
                        if (R.depCrit    > DEPCHECK_CRIT_MAX) { echo "BLOCKED: ${R.depCrit} CRITICAL CVE в зависимостях";        blocked = true }
    
                        if (blocked) {
                            unstable('SECURITY QUALITY GATE FAILED — деплой заблокирован')
                        } else {
                            echo 'SECURITY QUALITY GATE PASSED'
                        }
                    }
                }
            }
        }
    }

    post {
        always {
            container('kubectl') {
                sh """
                    kubectl delete deployment juice-shop -n ${NAMESPACE} --ignore-not-found=true
                    kubectl delete service juice-shop -n ${NAMESPACE} --ignore-not-found=true
                """
            }
            archiveArtifacts(
                artifacts: 'reports/*.json',
                allowEmptyArchive: true
            ) 
        }
        success  { echo 'Пайплайн прошёл все проверки успешно' }
        unstable { echo 'Пайплайн завершён с предупреждениями — проверь отчёты' }
        failure  { echo 'Найдены проблемы, смотри логи выше.' }
    }
}
