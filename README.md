Тестовый стенд пайплайна на Jenkins с проверкой безопасности намеренно уязвимого веб-приложения OWASP Juice Shop. 

**Шаги пайплайна:**
1.  Подготовка окружения 
2.  Клонирование OWASP Juice Shop из официального репозитория 
3.  Secret Scan (параллельно: TruffleHog + Gitleaks)
4.  SAST — Semgrep
5.  SCA — npm audit 
6.  SCA — OWASP Dependency-Check
7.  SBOM Generation — Syft
8.  SCA — Grype (по SBOM)
9. Build — сборка с помощью Kaniko 
10. Container Scan — Trivy (сканирует образ из registry)
11. Deploy 
12. DAST — OWASP ZAP (baseline-скан живого приложения)
13. Security Quality Gate

Все контейнеры инструментов сканирования/разворачивания создаются в одном поде.
После первого "прогона" этапы, относящиеся к сканированию безопасности опционально можно отключить через параметры сборки. ("Build with Parameters")
Этап "Security Quality Gate" сделан с помощью скрипта на Python. Его задача собрать и проанализировать отчеты инструментов сканирования безопасности. По результатам анализа, в случае превышения порога, данный этап помечает сборку как "UNSTABLE" (так как это демо стенд, в реальном проекте следует остановить сборку и деплой с пометкой "FAILURE").
### Инструкция по запуску:
#### Требования:
- У вас должен быть установлен `git` (winget install -e --id Git.Git)
- У вас должен быть установлен и запущен `Docker Desktop` (winget install -e --id Docker.DockerDesktop).
- У вас должен быть установлен `kind` (winget install Kubernetes.kind).
- У вас должен быть установлен `kubectl` (winget install Kubernetes.kubectl).

#### Запуск:
1. Клонируем репозиторий
```powershell
git clone https://github.com/dmtaddict/devsecops-JuiceShop.git
cd devsecops-JuiceShop
```
2. Запускаем стенд (первый раз разворачивание стенда занимает ~5-10 минут - создаётся кластер, собирается и загружается Jenkins-образ)
```powershell
.\setup.ps1
```
Если при первом запуске `.\setup.ps1` PowerShell блокирует выполнение, то нужно разрешить выполнение командой в Powershell: 
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```
Повторный запуск скрипта пропускает уже выполненные шаги (существующий кластер, собранный образ и т.д.).

3. Открываем Jenkins
http://localhost:8090 
Логин: admin  
Пароль: admin

#### Остановка (опционально)

```powershell
.\setup.ps1 -Down
```
**ВНИМАНИЕ** Запуск .\setup.ps1 -Down удаляет кластер и локальный registry!

### Настройка перед первым запуском пайплайна

#### NVD API Key (для OWASP Dependency-Check)

1. Получить бесплатный ключ: https://nvd.nist.gov/developers/request-an-api-key
2. Добавляем ключ в секреты Jenkins: 
**Manage Jenkins → Credentials → System → Global credentials → Add Credentials**
   - Kind: `Secret text`
   - ID: `nvd-api-key`
   - Secret: ваш ключ

**Первый прогон с Dependency-Check**
Первый запуск скачивает базу NVD (достаточно долго, может затянуться на полчаса, а то и дольше). Кэш сохраняется в PVC `dependency-check-cache`, при повторном запуске база качаться не будет.

### Запуск пайплайна

1. Открыть `http://localhost:8090`
2. Войти: `admin` / `admin`
3. Открыть Job **devsecops-JuiceShop**
4. Нажать **Build Now**/**Build with Parameters**
5. Номер сборки → **Console Output**

Полный прогон пайплайна со всеми стейджами на стандартном ПК занимает достаточно много времени, будьте готовы ждать около часа.

После завершения сборки смотрим результаты:

- **Jenkins UI** → Build → Номер сборки → **Console Output** - таблица Quality Gate со
  всеми метриками и порогами
- **Jenkins UI** → Build → **Artifacts** → `reports/`:
  - `trufflehog-report.json`, `gitleaks-report.json` — найденные секреты
  - `semgrep-report.json` — паттерны уязвимостей в коде
  - `npm-audit.json`, `dependency-check-report.json` — CVE в зависимостях
  - `sbom-report.json` — список зависимостей (CycloneDX)
  - `grype-report.json` — CVE по SBOM
  - `trivy-image-report.json` — CVE в собранном образе
  - `zap-report.json` — результаты DAST