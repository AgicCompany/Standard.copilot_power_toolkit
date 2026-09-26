#Requires -Version 5.1
<#
.SYNOPSIS
  Secrets Scanner Hook (PowerShell) - mirrors scan-secrets.sh exactly; keep both in sync.
  POSIX character classes ([[:space:]] etc.) from the bash patterns are translated to .NET regex
  equivalents (\s etc.) - same intent, different syntax.
.NOTES
  Env vars: SCAN_MODE (warn|block, default warn), SCAN_SCOPE (diff|staged, default diff),
  SKIP_SECRETS_SCAN (true to disable), SECRETS_LOG_DIR (default logs/copilot/secrets),
  SECRETS_ALLOWLIST (comma-separated patterns to ignore)
#>

$ErrorActionPreference = 'Stop'

# PowerShell 7.3+ turns a native command's non-zero EXIT CODE into a terminating error whenever
# $ErrorActionPreference is 'Stop'. That is fatal here, because a non-zero exit is the normal signal
# this script exists to read - 'git diff HEAD' exits 128 in a repo with no commits yet, which is the
# usual state of a freshly scaffolded project. Redirecting with 2>$null suppresses the stderr text
# but not the exit code, so the script died before scanning anything and wrote no log line at all -
# which reads downstream as "the hook never fired" rather than "the hook crashed".
# Always test $LASTEXITCODE explicitly instead. Harmless on 5.1 and 7.0-7.2, where it is unused.
$PSNativeCommandUseErrorActionPreference = $false

# ...but that variable does not exist in Windows PowerShell 5.1, and 5.1 is what the Copilot host
# launches hooks with. 5.1 turns a native command's STDERR into a TERMINATING ErrorRecord under
# 'Stop' - no non-zero exit needed - and `2>$null` does NOT prevent it (verified 2026-07-27: the
# redirect discards the text, the error record is still raised). The preference must actually be
# lowered around the call. Without this, `git rev-parse --is-inside-work-tree` crashed the script
# whenever it ran outside a repo - i.e. the "skip gracefully, this isn't a repo" path was the one
# path guaranteed to blow up.
function Invoke-NativeCommand {
  param(
    [Parameter(Mandatory = $true)][string]$Command,
    [string[]]$Arguments = @()
  )
  $prev = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    $out = & $Command @Arguments 2>&1 | ForEach-Object {
      if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.ToString() } else { [string]$_ }
    }
    $code = $LASTEXITCODE
    return [PSCustomObject]@{ Output = @($out); ExitCode = $code }
  } catch {
    return [PSCustomObject]@{ Output = @($_.Exception.Message); ExitCode = 1 }
  } finally {
    $ErrorActionPreference = $prev
  }
}

# Appends one JSON line to a log file. Uses .NET AppendAllText rather than Add-Content: the
# provider-backed cmdlet throws "Stream was not readable" when the Copilot host launches the script
# with its standard streams redirected, which is exactly how hooks are invoked. Observed live in a
# preToolUse hook.
#
# The try/catch is not decoration. These scripts run with $ErrorActionPreference = 'Stop', so a
# throw here terminates the script with a non-zero exit - and a non-zero exit from preToolUse BLOCKS
# THE TOOL CALL. A failure to write a log line must never deny Copilot an operation.
function Write-HookLog {
  param(
    [Parameter(ValueFromPipeline = $true)][string]$Json,
    [Parameter(Mandatory = $true)][string]$Path
  )
  process {
    try {
      $dir = Split-Path -Parent $Path
      if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        # Best-effort: Write-HookLog creates this lazily too. Must not throw - a failed
        # mkdir under ErrorActionPreference='Stop' would exit non-zero and, on preToolUse,
        # block the tool call outright.
        try { New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop | Out-Null } catch { }
      }
      [System.IO.File]::AppendAllText($Path, $Json + [Environment]::NewLine)
    } catch {
      # Deliberately swallowed - logging is never worth failing a hook over.
    }
  }
}


$Patterns = @(
  @{ Name = 'AWS_ACCESS_KEY'; Severity = 'critical'; Regex = 'AKIA[0-9A-Z]{16}' }
  @{ Name = 'AWS_SECRET_KEY'; Severity = 'critical'; Regex = "aws_secret_access_key\s*[:=]\s*['\`"]?[A-Za-z0-9/+=]{40}" }
  @{ Name = 'GCP_SERVICE_ACCOUNT'; Severity = 'critical'; Regex = '"type"\s*:\s*"service_account"' }
  @{ Name = 'GCP_API_KEY'; Severity = 'high'; Regex = 'AIza[0-9A-Za-z_-]{35}' }
  @{ Name = 'AZURE_CLIENT_SECRET'; Severity = 'critical'; Regex = "azure[_-]?client[_-]?secret\s*[:=]\s*['\`"]?[A-Za-z0-9_~.-]{34,}" }
  @{ Name = 'GITHUB_PAT'; Severity = 'critical'; Regex = 'ghp_[0-9A-Za-z]{36}' }
  @{ Name = 'GITHUB_OAUTH'; Severity = 'critical'; Regex = 'gho_[0-9A-Za-z]{36}' }
  @{ Name = 'GITHUB_APP_TOKEN'; Severity = 'critical'; Regex = 'ghs_[0-9A-Za-z._-]{36,}' }
  @{ Name = 'GITHUB_REFRESH_TOKEN'; Severity = 'critical'; Regex = 'ghr_[0-9A-Za-z]{36}' }
  @{ Name = 'GITHUB_FINE_GRAINED_PAT'; Severity = 'critical'; Regex = 'github_pat_[0-9A-Za-z_]{82}' }
  @{ Name = 'PRIVATE_KEY'; Severity = 'critical'; Regex = '-----BEGIN (RSA |EC |OPENSSH |DSA |PGP )?PRIVATE KEY-----' }
  @{ Name = 'PGP_PRIVATE_BLOCK'; Severity = 'critical'; Regex = '-----BEGIN PGP PRIVATE KEY BLOCK-----' }
  @{ Name = 'GENERIC_SECRET'; Severity = 'high'; Regex = "(secret|token|password|passwd|pwd|api[_-]?key|apikey|access[_-]?key|auth[_-]?token|client[_-]?secret)\s*[:=]\s*['\`"]?[A-Za-z0-9_/+=~.-]{8,}" }
  @{ Name = 'CONNECTION_STRING'; Severity = 'high'; Regex = "(mongodb(\+srv)?|postgres(ql)?|mysql|redis|amqp|mssql)://[^\s'\`"]{10,}" }
  @{ Name = 'BEARER_TOKEN'; Severity = 'medium'; Regex = '[Bb]earer\s+[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}' }
  @{ Name = 'SLACK_TOKEN'; Severity = 'high'; Regex = 'xox[baprs]-[0-9]{10,}-[0-9A-Za-z-]+' }
  @{ Name = 'SLACK_WEBHOOK'; Severity = 'high'; Regex = 'https://hooks\.slack\.com/services/T[0-9A-Z]{8,}/B[0-9A-Z]{8,}/[0-9A-Za-z]{24}' }
  @{ Name = 'DISCORD_TOKEN'; Severity = 'high'; Regex = '[MN][A-Za-z0-9]{23,}\.[A-Za-z0-9_-]{6}\.[A-Za-z0-9_-]{27,}' }
  @{ Name = 'TWILIO_API_KEY'; Severity = 'high'; Regex = 'SK[0-9a-fA-F]{32}' }
  @{ Name = 'SENDGRID_API_KEY'; Severity = 'high'; Regex = 'SG\.[0-9A-Za-z_-]{22}\.[0-9A-Za-z_-]{43}' }
  @{ Name = 'STRIPE_SECRET_KEY'; Severity = 'critical'; Regex = 'sk_live_[0-9A-Za-z]{24,}' }
  @{ Name = 'STRIPE_RESTRICTED_KEY'; Severity = 'high'; Regex = 'rk_live_[0-9A-Za-z]{24,}' }
  @{ Name = 'NPM_TOKEN'; Severity = 'high'; Regex = 'npm_[0-9A-Za-z]{36}' }
  @{ Name = 'JWT_TOKEN'; Severity = 'medium'; Regex = 'eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}' }
  @{ Name = 'INTERNAL_IP_PORT'; Severity = 'medium'; Regex = '(^|[^.0-9])(10\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}|172\.(1[6-9]|2[0-9]|3[01])\.[0-9]{1,3}\.[0-9]{1,3}|192\.168\.[0-9]{1,3}\.[0-9]{1,3}):[0-9]{2,5}([^0-9]|$)' }
)

$TextExtensions = @('.md','.txt','.json','.yaml','.yml','.xml','.toml','.ini','.cfg','.conf',
  '.sh','.bash','.zsh','.ps1','.bat','.cmd',
  '.py','.rb','.js','.ts','.jsx','.tsx','.go','.rs','.java','.kt','.cs','.cpp','.c','.h',
  '.php','.swift','.scala','.r','.lua','.pl','.ex','.exs','.hs','.ml',
  '.html','.css','.scss','.less','.svg',
  '.sql','.graphql','.proto',
  '.env','.properties')
$TextBasenames = @('Dockerfile','Makefile','Vagrantfile','Gemfile','Rakefile')
$SkipExtensions = @('.lock')
$SkipBasenames = @('package-lock.json','yarn.lock','pnpm-lock.yaml','Cargo.lock','go.sum')

# The scanner's own machinery lives here: scan-secrets.* holds the detection regexes (a PGP header
# pattern IS a PGP header), and the hook READMEs document what a finding looks like. Scanning them
# reports the detector as the threat - 7 guaranteed false positives on a clean project, every run.
# That is worse than missing a real one, because a guard that cries wolf gets ignored wholesale.
# Deliberately scoped to .github/hooks/ and not all of .github/: a credential pasted into
# copilot-instructions.md or a workflow file is a real finding and must still be caught.
$SkipPathPrefixes = @('.github/hooks/')

# The prefix above only fires in a TARGET project, where the hooks live under .github/. When the
# baseline repo scans ITSELF the path is 'hooks/scripts/...' with no prefix, so the detector's own
# regexes and its README's worked examples come back as findings again - 7 of them on the first
# commit. Skipping a bare 'hooks/' prefix is NOT the fix: it would also match 'src/hooks/', where
# every React project keeps its hooks, and silently exclude them from scanning. Match the specific
# files instead.
$SkipBasenames += @('scan-secrets.ps1', 'scan-secrets.sh', 'secrets-scanner.README.md')

function Test-TextFile {
  param([string]$Path)
  $ext = [System.IO.Path]::GetExtension($Path)
  $base = [System.IO.Path]::GetFileName($Path)
  if ($ext -and ($TextExtensions -contains $ext.ToLower())) { return $true }
  if ($base -and ($base -match '^\.env(\..*)?$')) { return $true }
  foreach ($b in $TextBasenames) { if ($base -like "$b*") { return $true } }
  return $false
}

if ($env:SKIP_SECRETS_SCAN -eq 'true') {
  Write-Host "[SKIP]  Secrets scan skipped (SKIP_SECRETS_SCAN=true)"
  exit 0
}

$repoProbe = Invoke-NativeCommand -Command 'git' -Arguments @('rev-parse', '--is-inside-work-tree')
if ($repoProbe.ExitCode -ne 0) {
  Write-Host "[WARN]  Not in a git repository, skipping secrets scan"
  exit 0
}

$Mode = if ($env:SCAN_MODE) { $env:SCAN_MODE } else { 'warn' }
$Scope = if ($env:SCAN_SCOPE) { $env:SCAN_SCOPE } else { 'diff' }
$LogDir = if ($env:SECRETS_LOG_DIR) { $env:SECRETS_LOG_DIR } else { 'logs/copilot/secrets' }
$Timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$FindingCount = 0
# Best-effort: Write-HookLog creates this lazily too. Must not throw - a failed
# mkdir under ErrorActionPreference='Stop' would exit non-zero and, on preToolUse,
# block the tool call outright.
try { New-Item -ItemType Directory -Path $LogDir -Force -ErrorAction Stop | Out-Null } catch { }
$LogFile = [System.IO.Path]::Combine($LogDir, 'scan.log')

# A repo made by 'git init' with nothing committed yet has no HEAD, so every 'git diff HEAD' exits
# 128. That is the normal state of a freshly scaffolded project - precisely when an unscanned
# credential is most likely to be sitting in a new file - so treat it as "every file is new" rather
# than diffing against a revision that does not exist. Checking --is-inside-work-tree is not enough:
# it succeeds here, because the repository does exist. It just has no commits.
$headProbe = Invoke-NativeCommand -Command 'git' -Arguments @('rev-parse', '--verify', '--quiet', 'HEAD')
$HasCommits = ($headProbe.ExitCode -eq 0)

# Collect files to scan based on scope
$Files = @()
if ($Scope -eq 'staged') {
  # 'git diff --cached' needs no HEAD - with no commits it compares the index against the empty tree.
  $Files = (Invoke-NativeCommand -Command 'git' -Arguments @('diff', '--cached', '--name-only', '--diff-filter=ACMR')).Output | Where-Object { $_ }
} elseif (-not $HasCommits) {
  $Files = (Invoke-NativeCommand -Command 'git' -Arguments @('ls-files')).Output | Where-Object { $_ }
  $Files += (Invoke-NativeCommand -Command 'git' -Arguments @('ls-files', '--others', '--exclude-standard')).Output | Where-Object { $_ }
} else {
  $Files = (Invoke-NativeCommand -Command 'git' -Arguments @('diff', '--name-only', '--diff-filter=ACMR', 'HEAD')).Output | Where-Object { $_ }
  if (-not $Files) { $Files = (Invoke-NativeCommand -Command 'git' -Arguments @('diff', '--name-only', '--diff-filter=ACMR')).Output | Where-Object { $_ } }
  $Files += (Invoke-NativeCommand -Command 'git' -Arguments @('ls-files', '--others', '--exclude-standard')).Output | Where-Object { $_ }
}
$Files = $Files | Select-Object -Unique

if (-not $Files -or $Files.Count -eq 0) {
  Write-Host "[CLEAN] No modified files to scan"
  [PSCustomObject]@{ timestamp = $Timestamp; event = 'scan_complete'; mode = $Mode; scope = $Scope; status = 'clean'; files_scanned = 0 } |
    ConvertTo-Json -Compress | Write-HookLog -Path $LogFile
  exit 0
}

$Allowlist = @()
if ($env:SECRETS_ALLOWLIST) {
  $Allowlist = $env:SECRETS_ALLOWLIST -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
}

function Test-Allowlisted {
  param([string]$Match)
  foreach ($p in $Allowlist) { if ($Match -like "*$p*") { return $true } }
  return $false
}

$PlaceholderPattern = '(?i)(example|placeholder|your[_-]|xxx|changeme|TODO|FIXME|replace[_-]?me|dummy|fake|test[_-]?key|sample)'

# A REFERENCE to a secret is not a secret. `password: process.env.DB_PASSWORD` is the correct
# pattern - flagging it punishes doing the right thing, and a scanner that fires on correct code is
# one people switch off. Same class as the vite-env-guard false positives: the NAME matched, the
# VALUE was never inspected.
#
# Suppressed:
#   password: process.env.DB_PASSWORD     env lookup (any language's spelling)
#   token: chatbotToken                   bare identifier - a variable, not a literal
#   apiKey: config.apiKey                 property access
#   secret: ${SECRET}  /  {{ secret }}    interpolation and template placeholders
#   token: <your-token-here>              angle-bracket placeholder
# NOT suppressed: a quoted literal, which is what an actual leaked credential looks like.
$ReferencePattern = '(?ix)
    [:=]\s*[''"]?\s*(
        (process\.env|import\.meta\.env|os\.environ|ENV|Environment\.GetEnvironmentVariable)\b
      | \$\{ | \{\{ | %[A-Za-z_]
      | <[A-Za-z_]
      | [A-Za-z_][A-Za-z0-9_]*\s*[.\[]          # config.apiKey / creds["token"]
      | [A-Za-z_][A-Za-z0-9_]*\s*$              # bare identifier to end of match
    )'

$Findings = @()

foreach ($filepath in $Files) {
  if (-not (Test-Path -LiteralPath $filepath -PathType Leaf)) { continue }
  if (-not (Test-TextFile -Path $filepath)) { continue }
  $ext = [System.IO.Path]::GetExtension($filepath)
  $base = [System.IO.Path]::GetFileName($filepath)
  if ($SkipExtensions -contains $ext.ToLower()) { continue }
  if ($SkipBasenames -contains $base) { continue }
  $normalized = $filepath.Replace('\', '/')
  $skipByPath = $false
  foreach ($prefix in $SkipPathPrefixes) {
    if ($normalized -like "$prefix*" -or $normalized -like "*/$prefix*") { $skipByPath = $true; break }
  }
  if ($skipByPath) { continue }

  $readPath = $filepath
  $tempFile = $null
  if ($Scope -eq 'staged') {
    $tempFile = [System.IO.Path]::GetTempFileName()
    $shown = Invoke-NativeCommand -Command 'git' -Arguments @('show', ":$filepath")
    [System.IO.File]::WriteAllLines($tempFile, [string[]]$shown.Output)
    $readPath = $tempFile
  }

  try {
    # @() forces an array even for a single-line file - otherwise Get-Content returns a bare
    # string for exactly one line, and $lines[0] would index into the first *character*.
    $lines = @(Get-Content -LiteralPath $readPath -ErrorAction SilentlyContinue)
    if ($lines.Count -eq 0) { continue }
    for ($i = 0; $i -lt $lines.Count; $i++) {
      $line = $lines[$i]
      foreach ($p in $Patterns) {
        $m = [regex]::Match($line, $p.Regex)
        if (-not $m.Success) { continue }
        $matchText = $m.Value
        if ($p.Name -eq 'INTERNAL_IP_PORT') {
          $ipMatch = [regex]::Match($matchText, '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+')
          if (-not $ipMatch.Success) { continue }
          $matchText = $ipMatch.Value
        }
        if ($Allowlist.Count -gt 0 -and (Test-Allowlisted -Match $matchText)) { continue }
        if ($matchText -match $PlaceholderPattern) { continue }
        if ($matchText -match $ReferencePattern) { continue }

        $redacted = if ($matchText.Length -le 12) { '[REDACTED]' } else { "$($matchText.Substring(0,4))...$($matchText.Substring($matchText.Length-4))" }
        $Findings += [PSCustomObject]@{ file = $filepath; line = ($i + 1); pattern = $p.Name; severity = $p.Severity; match = $redacted }
        $FindingCount++
      }
    }
  } finally {
    if ($tempFile) { Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue }
  }
}

Write-Host "[CHECK] Scanning $($Files.Count) modified file(s) for secrets..."

if ($FindingCount -gt 0) {
  Write-Host ""
  Write-Host "[WARN]  Found $FindingCount potential secret(s) in modified files:"
  Write-Host ""
  "{0,-40} {1,-6} {2,-28} {3}" -f "FILE", "LINE", "PATTERN", "SEVERITY" | Write-Host
  "{0,-40} {1,-6} {2,-28} {3}" -f "----", "----", "-------", "--------" | Write-Host
  foreach ($f in $Findings) {
    "{0,-40} {1,-6} {2,-28} {3}" -f $f.file, $f.line, $f.pattern, $f.severity | Write-Host
  }
  Write-Host ""

  [PSCustomObject]@{
    timestamp = $Timestamp; event = 'secrets_found'; mode = $Mode; scope = $Scope
    files_scanned = $Files.Count; finding_count = $FindingCount; findings = $Findings
  } | ConvertTo-Json -Compress -Depth 5 | Write-HookLog -Path $LogFile

  if ($Mode -eq 'block') {
    Write-Host "[BLOCKED] Session blocked: resolve the findings above before committing."
    Write-Host "  Set SCAN_MODE=warn to log without blocking, or add patterns to SECRETS_ALLOWLIST."
    exit 1
  } else {
    Write-Host "[TIP] Review the findings above. Set SCAN_MODE=block to prevent commits with secrets."
  }
} else {
  Write-Host "[OK] No secrets detected in $($Files.Count) scanned file(s)"
  [PSCustomObject]@{ timestamp = $Timestamp; event = 'scan_complete'; mode = $Mode; scope = $Scope; status = 'clean'; files_scanned = $Files.Count } |
    ConvertTo-Json -Compress | Write-HookLog -Path $LogFile
}

exit 0
