$ErrorActionPreference = 'Stop'

# Path to exported Google Doc text
$docPath = Join-Path -Path (Get-Location) -ChildPath 'doc-export.txt'
if (!(Test-Path $docPath)) {
  Write-Error "doc-export.txt not found. Export the Google Doc to doc-export.txt first."
}

# Read lines
$lines = Get-Content -Path $docPath -Raw -Encoding UTF8 -ErrorAction Stop -ReadCount 0

# Split into blocks by URL lines. A block starts with a URL line and continues until the next URL.
$patternUrl = "(?ms)^(https?://drchetanpatilortho\.com(?:/[^\r\n]*)?)\s*\r?\n(.*?)(?=^https?://drchetanpatilortho\.com|\Z)"
$matches = [regex]::Matches($lines, $patternUrl)

if ($matches.Count -eq 0) {
  Write-Error "No URL blocks found in doc-export.txt"
}

$report = @()

foreach ($m in $matches) {
  $url = $m.Groups[1].Value.Trim()
  $block = $m.Groups[2].Value

  # Map URL to local file
  $uri = [Uri]$url
  $localName = if ($uri.AbsolutePath -eq '/' -or [string]::IsNullOrWhiteSpace($uri.AbsolutePath)) { 'index.html' } else { [IO.Path]::GetFileName($uri.AbsolutePath) }

  $filePath = Join-Path -Path (Get-Location) -ChildPath $localName
  if (!(Test-Path $filePath)) {
    $report += @{ Url = $url; File = $localName; Status = 'Skipped (file not found)'}
    continue
  }

  # Extract Meta Title (handle variants 'Meta Title' / 'Meta TItle')
  $title = $null
  $desc = $null
  $h2 = $null
  $schema = $null

  $titleMatch = [regex]::Match($block, '(?mi)^\s*Meta\s*Titl[eE]\s*:\s*(.+)$')
  if ($titleMatch.Success) { $title = $titleMatch.Groups[1].Value.Trim() }

  $descMatch = [regex]::Match($block, '(?mi)^\s*Meta\s*Description\s*:\s*(.+)$')
  if ($descMatch.Success) { $desc = $descMatch.Groups[1].Value.Trim() }

  $h2Match = [regex]::Match($block, '(?mi)^\s*H2\s*:\s*(.+)$')
  if ($h2Match.Success) { $h2 = $h2Match.Groups[1].Value.Trim() }

  $schemaMatch = [regex]::Match($block, '(?ms)<script\s+type="application/ld\+json">\s*(\{.*?\})\s*</script>')
  if ($schemaMatch.Success) { $schema = $schemaMatch.Groups[1].Value.Trim() }

function Escape-Html([string]$s) {
  if ($null -eq $s) { return '' }
  ($s -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;' -replace '"','&quot;')
}

$html = Get-Content -Path $filePath -Raw -Encoding UTF8
$origHtml = $html

  # Update <title>
  if ($title) {
    if ($html -match '<title>.*?</title>') {
      $html = [regex]::Replace($html, '<title>.*?</title>', ('<title>{0}</title>' -f (Escape-Html $title)), [System.Text.RegularExpressions.RegexOptions]::Singleline)
    } else {
      # Insert before </head>
      $html = [regex]::Replace($html, '</head>', ('  <title>{0}</title>' -f (Escape-Html $title)) + "`r`n</head>")
    }
  }

  # Update/Insert meta description
  if ($desc) {
    $metaTag = '<meta name="description" content="{0}" />' -f ($desc -replace '"','&quot;')
    if ($html -match '<meta\s+name="description"[^>]*>') {
      $html = [regex]::Replace($html, '<meta\s+name="description"[^>]*>', $metaTag, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    } else {
      # place after the <title> if exists, otherwise before </head>
      if ($html -match '<title>.*?</title>') {
        $html = [regex]::Replace($html, '(<title>.*?</title>)', '$1' + "`r`n    " + $metaTag, [System.Text.RegularExpressions.RegexOptions]::Singleline)
      } else {
        $html = [regex]::Replace($html, '</head>', '    ' + $metaTag + "`r`n</head>")
      }
    }
  }

  # Insert/Replace JSON-LD Schema
  if ($schema) {
    # Remove any existing ld+json that references this page '@id' to avoid dupes
    $pageId = ($url.TrimEnd('/')) + '#clinic'
    # Remove script blocks containing the @id string
    $html = [regex]::Replace($html, '(?ms)\s*<script\s+type="application/ld\+json">.*?"@id"\s*:\s*"' + [regex]::Escape($pageId) + '".*?</script>\s*', '')

    $schemaTag = @"
<script type="application/ld+json">
$schema
</script>
"@
    # Insert before </head>
    $html = [regex]::Replace($html, '</head>', $schemaTag + "`r`n</head>")
  }

  if ($html -ne $origHtml) {
    # Backup
    Copy-Item -Path $filePath -Destination ($filePath + '.bak') -Force
    Set-Content -Path $filePath -Value $html -Encoding UTF8
    $report += @{ Url = $url; File = $localName; Status = 'Updated'; Title = $title; Description = $desc }
  } else {
    $report += @{ Url = $url; File = $localName; Status = 'No changes needed' }
  }
}

# Write report
$report | ForEach-Object {
  "{0} -> {1}: {2}" -f $_.Url, $_.File, $_.Status
}
