# ============================================================
#  MVEC — деплой сайта на GitHub Pages + сборки в Releases
#  Запуск (из папки сайта):
#     powershell -ExecutionPolicy Bypass -File deploy.ps1
#  По желанию своё имя репозитория:
#     powershell -ExecutionPolicy Bypass -File deploy.ps1 MVEC
#  Перед запуском один раз выполни:  gh auth login
# ============================================================
param([string]$Repo = "MVEK")
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

# Пути к сборкам
$GAME = "C:\Users\User\Desktop\GriffonMazeHTML"
$EXE = "$GAME\dist-exe\MVEC.exe"
$apkItem = Get-ChildItem "$GAME\android\app\build\outputs\apk\debug\*.apk" -ErrorAction SilentlyContinue | Select-Object -First 1
$APK = if ($apkItem) { $apkItem.FullName } else { "" }

# 0. Обновляем веб-версию игры в ./play (для iPhone и игры в браузере)
Write-Host "== Обновляю веб-версию игры в ./play ==" -ForegroundColor Cyan
if (Test-Path "$GAME\www\index.html") {
    if (Test-Path ".\play") { Remove-Item ".\play" -Recurse -Force }
    New-Item -ItemType Directory -Path ".\play" | Out-Null
    Copy-Item "$GAME\www\*" ".\play\" -Recurse -Force
    # тёмный фон для веба (APK не трогаем)
    $idx = ".\play\index.html"
    $s = Get-Content $idx -Raw
    if ($s -notmatch 'html\{background:#19191c') {
        $s = $s -replace '</head>', "<style>html{background:#19191c;}</style>`n</head>"
        Set-Content $idx $s -Encoding UTF8
    }
}

Write-Host "== Проверяю вход в GitHub ==" -ForegroundColor Cyan
gh auth status | Out-Host

$User = (gh api user --jq ".login").Trim()
if (-not $User) { Write-Error "Не удалось получить логин. Выполни: gh auth login"; exit 1 }
Write-Host "Логин: $User   Репозиторий: $Repo" -ForegroundColor Green

# 1. git-репозиторий
if (-not (Test-Path ".git")) {
    git init -b main | Out-Host
}
git add -A | Out-Host
git commit -m "MVEC website" 2>$null | Out-Host

# 2. создать репозиторий на GitHub и запушить
$exists = $true
try { gh repo view "$User/$Repo" *> $null } catch { $exists = $false }
if (-not $exists) {
    gh repo create $Repo --public --source=. --remote=origin --push | Out-Host
} else {
    git remote remove origin 2>$null
    git remote add origin "https://github.com/$User/$Repo.git"
    # первый пуш сайта — устанавливаем содержимое (force, если в репо был README)
    git push -u origin main --force | Out-Host
}

# 3. включить GitHub Pages (ветка main, корень)
Write-Host "== Включаю GitHub Pages ==" -ForegroundColor Cyan
try {
    '{"source":{"branch":"main","path":"/"}}' | gh api -X POST "repos/$User/$Repo/pages" --input - | Out-Host
} catch {
    Write-Host "Pages уже включены или включатся в настройках репозитория." -ForegroundColor Yellow
}

# 4. релиз со сборками exe + apk
Write-Host "== Загружаю сборки в Releases ==" -ForegroundColor Cyan
$assets = @()
if ($EXE -and (Test-Path $EXE)) { $assets += $EXE } else { Write-Warning "Нет MVEC.exe — собери: npm run dist (в папке игры)" }
if ($APK -and (Test-Path $APK)) {
    Copy-Item $APK ".\MVEC.apk" -Force
    $assets += ".\MVEC.apk"
} else {
    Write-Warning "Нет APK — собери: build.bat (в папке игры)"
}
try { gh release delete v1.0 -y --cleanup-tag 2>$null } catch {}
gh release create v1.0 $assets -t "MVEC v1.0" -n "Сборки игры MVEC: MVEC.exe (ПК) и MVEC.apk (Android)." | Out-Host

Write-Host ""
Write-Host "ГОТОВО!" -ForegroundColor Green
Write-Host "Сайт:    https://$User.github.io/$Repo/" -ForegroundColor Green
Write-Host "Релизы:  https://github.com/$User/$Repo/releases" -ForegroundColor Green
Write-Host "(Pages поднимается ~1 минуту после первого пуша.)"
