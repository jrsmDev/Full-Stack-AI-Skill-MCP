<#
.SYNOPSIS
    Universal AI Skills Synchronizer (Claude Code + OpenCode + Unsloth Studio).

.DESCRIPTION
    Scans 'FULL STACK AI SKILL' for SKILL.md files and links every skill into the
    shared hubs with directory junctions:

        %USERPROFILE%\.claude\skills            Claude Code + Unsloth Studio
        %USERPROFILE%\.config\opencode\skills   OpenCode

    Unsloth Studio reads %USERPROFILE%\.claude\skills natively, so linked skills
    show up in Settings > Chat > Skills and in the chat Skills picker.

    Link names come from each SKILL.md `name:` frontmatter, not the folder name.
    Unsloth rejects a skill whose frontmatter name differs from its directory, so
    this also repairs skills that were silently unusable (e.g. skills-brand).

    Idempotent: safe to run repeatedly. Duplicate skills (same name in several
    collections) collapse to one link; stale and dangling links are removed.
    A scheduled task ("Unsloth Skills Sync") runs it every 2 minutes, so a new
    skill folder appears in Studio within ~2 minutes of being added.
#>
[CmdletBinding()]
param(
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
$sourceDir = $PSScriptRoot

$hubs = @(
    @{ Path = (Join-Path $env:USERPROFILE '.claude\skills');         Label = 'Claude Code / Unsloth' },
    @{ Path = (Join-Path $env:USERPROFILE '.config\opencode\skills'); Label = 'OpenCode' }
)

function Test-SamePath([string]$a, [string]$b) {
    if (-not $a -or -not $b) { return $false }
    try {
        $x = [IO.Path]::GetFullPath($a).TrimEnd('\')
        $y = [IO.Path]::GetFullPath($b).TrimEnd('\')
        return [string]::Equals($x, $y, [StringComparison]::OrdinalIgnoreCase)
    } catch { return $false }
}

function Test-UnderSource([string]$target, [string]$root) {
    if (-not $target) { return $false }
    try {
        $t = [IO.Path]::GetFullPath($target).TrimEnd('\')
        $r = [IO.Path]::GetFullPath($root).TrimEnd('\')
        return $t.StartsWith($r + '\', [StringComparison]::OrdinalIgnoreCase)
    } catch { return $false }
}

function Test-SkillName([string]$name) {
    if (-not $name) { return $false }
    if ($name.Length -lt 1 -or $name.Length -gt 64) { return $false }
    if ($name -notmatch '^[a-z0-9]+(-[a-z0-9]+)*$') { return $false }
    if ($name -match '^(con|prn|aux|nul|com[1-9]|lpt[1-9])$') { return $false }
    return $true
}

# Returns @{ Present = $true/$false; Name = normalised name or $null }.
function Get-SkillName([string]$manifestPath) {
    $result = @{ Present = $false; Name = $null }
    try {
        $lines = Get-Content -LiteralPath $manifestPath -TotalCount 80 -ErrorAction Stop
    } catch { return $result }

    $inFrontmatter = $false
    $delimiters = 0
    foreach ($line in $lines) {
        if ($line -match '^---\s*$') {
            $delimiters++
            if ($delimiters -eq 1) { $inFrontmatter = $true; continue }
            break
        }
        if (-not $inFrontmatter) { continue }
        if ($line -match '^name:\s*(.+?)\s*$') {
            $raw = $Matches[1].Trim()
            if ($raw -match '^["''](.*)["'']$') { $raw = $Matches[1] }
            $raw = $raw.Trim().ToLowerInvariant()
            $result.Present = $true
            if (Test-SkillName $raw) { $result.Name = $raw }
            break
        }
    }
    return $result
}

function Remove-Junction([string]$path) {
    try {
        [System.IO.Directory]::Delete($path)
        return $true
    } catch {
        try { Remove-Item -LiteralPath $path -Force -ErrorAction Stop; return $true } catch { return $false }
    }
}

# ---------------------------------------------------------------- scan source
$manifests = @(Get-ChildItem -LiteralPath $sourceDir -Recurse -File -Filter 'SKILL.md' -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch '\\(node_modules|\.git|dist|build|fixtures|tests)\\' })

$scanned = 0
$skipped = New-Object System.Collections.Generic.List[string]
$records = foreach ($manifest in $manifests) {
    $scanned++
    $folder = $manifest.Directory
    $parsed = Get-SkillName $manifest.FullName
    $name = $parsed.Name
    if (-not $name) {
        if ($parsed.Present) {
            $skipped.Add("$($folder.FullName) -> invalid 'name:' frontmatter")
        } else {
            $fallback = $folder.Name.ToLowerInvariant()
            if (Test-SkillName $fallback) {
                $name = $fallback
            } else {
                $skipped.Add("$($folder.FullName) -> no usable skill name")
                continue
            }
        }
    }
    [pscustomobject]@{ Name = $name; Dir = $folder.FullName; Depth = ($folder.FullName.Split('\').Count) }
}

# Existing links in the primary hub win when the same skill exists in several collections.
$existing = @{}
$primary = $hubs[0].Path
if (Test-Path -LiteralPath $primary) {
    foreach ($entry in (Get-ChildItem -LiteralPath $primary -Force -ErrorAction SilentlyContinue)) {
        if ($entry.LinkType -ne 'Junction') { continue }
        $target = @($entry.Target)[0]
        if ($target -and (Test-UnderSource $target $sourceDir)) {
            $existing[$entry.Name] = $target
        }
    }
}

$desired = [ordered]@{}
foreach ($group in ($records | Group-Object Name | Sort-Object Name)) {
    $candidates = @($group.Group | Sort-Object Depth, Dir)
    $pick = $candidates[0]
    if ($existing.ContainsKey($group.Name)) {
        $current = $candidates | Where-Object { Test-SamePath $_.Dir $existing[$group.Name] } | Select-Object -First 1
        if ($current) { $pick = $current }
    }
    $desired[$group.Name] = $pick.Dir
}

# ---------------------------------------------------------------- reconcile hubs
$created = 0
$removed = 0
$failed = New-Object System.Collections.Generic.List[string]

foreach ($hub in $hubs) {
    if (-not (Test-Path -LiteralPath $hub.Path)) {
        New-Item -ItemType Directory -Path $hub.Path -Force | Out-Null
    }

    # Drop stale or dangling links that point into this source tree.
    foreach ($entry in (Get-ChildItem -LiteralPath $hub.Path -Force -ErrorAction SilentlyContinue)) {
        if ($entry.LinkType -ne 'Junction') { continue }
        $target = @($entry.Target)[0]
        if (-not (Test-UnderSource $target $sourceDir)) { continue }
        $wanted = $desired.Contains($entry.Name)
        $alive = $target -and (Test-Path -LiteralPath $target)
        if ((-not $wanted) -or (-not $alive)) {
            if (Remove-Junction $entry.FullName) { $removed++ }
            else { $failed.Add("remove: $($entry.FullName)") }
        }
    }

    foreach ($name in $desired.Keys) {
        $link = Join-Path $hub.Path $name
        if (Test-Path -LiteralPath $link) { continue }
        $target = $desired[$name]
        try {
            New-Item -ItemType Junction -Path $link -Target $target -ErrorAction Stop | Out-Null
            $created++
        } catch {
            $failed.Add("link: $link -> $target")
        }
    }
}

# ---------------------------------------------------------------- catalog index
$indexFile = Join-Path $sourceDir 'SKILLS_INDEX.md'
$rows = foreach ($name in ($desired.Keys | Sort-Object)) {
    $dir = $desired[$name]
    $description = ''
    try {
        $head = Get-Content -LiteralPath (Join-Path $dir 'SKILL.md') -TotalCount 40 -Raw -ErrorAction Stop
        if ($head -match '(?m)^description:\s*(.+)$') {
            $description = $Matches[1].Trim().Trim('"').Trim("'")
        }
    } catch {}
    if (-not $description) { $description = 'Specialized AI workflow/skill' }
    $description = $description -replace '\|', '-'
    $rel = $dir
    if ($rel.StartsWith($sourceDir, [StringComparison]::OrdinalIgnoreCase)) {
        $rel = $rel.Substring($sourceDir.Length).TrimStart('\')
    }
    "| **$name** | $description | ``$rel`` |"
}

$indexLines = @(
    '# Master Skills Catalog Index',
    '',
    'Auto-generated by `sync_skills.ps1`. Skills are linked into `%USERPROFILE%\.claude\skills`',
    '(read by Claude Code and Unsloth Studio) and `%USERPROFILE%\.config\opencode\skills`.',
    '',
    "Total Skills Indexed: $($desired.Count)",
    '',
    '| Skill Name | Description | Source |',
    '| :--- | :--- | :--- |'
) + @($rows)
$indexContent = ($indexLines -join "`r`n") + "`r`n"

$indexChanged = $true
if (Test-Path -LiteralPath $indexFile) {
    $old = Get-Content -LiteralPath $indexFile -Raw -ErrorAction SilentlyContinue
    $indexChanged = ($old -ne $indexContent)
}
if ($indexChanged) {
    Set-Content -LiteralPath $indexFile -Value $indexContent -Encoding utf8
}

# ---------------------------------------------------------------- router skill
# Studio injects only ~4 KB of skill descriptions, so most skills never reach the
# model's catalog. This generated skill sorts first (00-), always lands in the
# catalog, and lists every name so the model can load any skill unprompted.
$routerName = '00-skills-index'
$routerDir = Join-Path $hubs[0].Path $routerName
if (-not (Test-Path -LiteralPath $routerDir)) {
    New-Item -ItemType Directory -Path $routerDir -Force | Out-Null
}
$routerLines = @(
    '---',
    "name: $routerName",
    'description: "Complete index of every installed Agent Skill by name. Read this first when a task might match a skill, then call read_skill with the exact name."',
    '---',
    '',
    "Every Agent Skill installed in this workspace is listed below by name ($($desired.Count) total).",
    '',
    'How to use:',
    '1. Scan the list for names that match the task.',
    '2. Call read_skill with the exact name to load its full SKILL.md.',
    '3. Follow the loaded instructions. Do not invent resource paths.',
    '',
    'Skills:',
    ''
)
$routerLines += @($desired.Keys | Sort-Object | ForEach-Object { "- $_" })
$routerContent = ($routerLines -join "`r`n") + "`r`n"
$routerFile = Join-Path $routerDir 'SKILL.md'
$routerChanged = $true
if (Test-Path -LiteralPath $routerFile) {
    $oldRouter = Get-Content -LiteralPath $routerFile -Raw -ErrorAction SilentlyContinue
    $routerChanged = ($oldRouter -ne $routerContent)
}
if ($routerChanged) {
    Set-Content -LiteralPath $routerFile -Value $routerContent -Encoding utf8
}

# ---------------------------------------------------------------- report
$changed = ($created + $removed) -gt 0
if ($changed -or $failed.Count -gt 0) {
    $stamp = Get-Date -Format 's'
    $logLine = "$stamp created=$created removed=$removed total=$($desired.Count) failed=$($failed.Count)"
    Add-Content -LiteralPath (Join-Path $sourceDir 'sync_skills.log') -Value $logLine -Encoding utf8
    try {
        $log = Get-Content -LiteralPath (Join-Path $sourceDir 'sync_skills.log') -ErrorAction Stop
        if ($log.Count -gt 500) { $log | Select-Object -Last 500 | Set-Content -LiteralPath (Join-Path $sourceDir 'sync_skills.log') -Encoding utf8 }
    } catch {}
}

if (-not $Quiet) {
    Write-Host ''
    Write-Host '  Universal AI Skills Synchronizer' -ForegroundColor Cyan
    Write-Host "  Source:  $sourceDir"
    Write-Host "  Scanned: $scanned SKILL.md files -> $($desired.Count) unique skills"
    Write-Host "  Links:   $created created, $removed removed"
    if ($indexChanged) { Write-Host "  Index:   $indexFile" }
    if ($skipped.Count -gt 0) {
        Write-Host "  Skipped: $($skipped.Count)" -ForegroundColor Yellow
        foreach ($item in $skipped) { Write-Host "    - $item" -ForegroundColor DarkYellow }
    }
    if ($failed.Count -gt 0) {
        Write-Host "  Failed:  $($failed.Count)" -ForegroundColor Red
        foreach ($item in $failed) { Write-Host "    - $item" -ForegroundColor Red }
        exit 1
    }
    Write-Host '  Done.' -ForegroundColor Green
    Write-Host ''
}
