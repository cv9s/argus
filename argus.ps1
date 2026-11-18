<#
  ARGUS PC LINK
  Serves the ARGUS dashboard at http://localhost:8080 and feeds it live
  stats from this computer. Also runs a short list of approved commands.

  Start:  double-click start-argus.bat   (or run .\argus.ps1 in PowerShell)
  Stop:   press Ctrl+C in this window, or close it.
#>
param(
  [int]$Port = 8080,
  [switch]$NoBrowser
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
#  APPROVED COMMANDS  -  add your own here. Only these can be opened.
#  Say or type "open <name>" in the dashboard.
# ---------------------------------------------------------------------------
$Apps = @{
  'notepad'       = 'notepad'
  'calculator'    = 'calc'
  'paint'         = 'mspaint'
  'file explorer' = 'explorer'
  'explorer'      = 'explorer'
  'files'         = 'explorer'
  'settings'      = 'ms-settings:'
  'task manager'  = 'taskmgr'
  'chrome'        = 'chrome'
  'edge'          = 'microsoft-edge:'
  'spotify'       = 'spotify:'
  'vs code'       = 'code'
  'word'          = 'winword'
  'excel'         = 'excel'
  'outlook'       = 'outlook'
}
$Sites = @{
  'youtube'   = 'https://www.youtube.com'
  'google'    = 'https://www.google.com'
  'gmail'     = 'https://mail.google.com'
  'github'    = 'https://github.com'
  'linkedin'  = 'https://www.linkedin.com'
  'indeed'    = 'https://www.indeed.com'
  'calendar'  = 'https://calendar.google.com'
}

# ---------------------------------------------------------------------------
#  DAILY BRIEF  -  clap twice, or say "Argus, how's my day" / "Argus, weather"
#  Change the location to your city (look up latitude/longitude on Google).
# ---------------------------------------------------------------------------
$Location = @{ Name = 'Houston'; Lat = 29.7604; Lon = -95.3698 }   # example: change to your city

# Your big goals right now. ARGUS keeps these in mind in every conversation.
$Priorities = @(
  'Example: finishing the semester strong.',
  'Example: working out three times a week.'
)

# Up to 3 are read out in the daily brief. Edit these to whatever you want reminders about.
$DailySuggestions = @(
  'Knock out your most important task before noon.',
  'Drink some water and get outside for ten minutes.',
  'Take five minutes tonight to plan tomorrow.'
)

# ---------------------------------------------------------------------------
#  CONVERSATION BRAIN  -  lets ARGUS hold a real conversation and remember it.
#  Option A (free, private): install Ollama from ollama.com, then in PowerShell run
#      ollama pull llama3.2
#    ARGUS finds it automatically.
#  Option B (smartest, small cost per question): a Claude API key from
#    console.anthropic.com. Put it in $ClaudeApiKey below, or set the Windows
#    environment variable ANTHROPIC_API_KEY. Never share this file once a key is in it.
#  With neither, ARGUS still answers simple questions using Wikipedia and Google.
# ---------------------------------------------------------------------------
$UserName     = 'Sir'                 # what ARGUS calls you
$OllamaModel  = 'llama3.2'
$ClaudeApiKey = ''
$ClaudeModel  = 'claude-haiku-4-5'    # model names: docs.claude.com/en/docs/about-claude/models
$ForgetAfterMinutes = 20              # conversation resets after this much silence
# ---------------------------------------------------------------------------

$Root = $PSScriptRoot
$PagePath = Join-Path $Root 'dashboard.html'
if (-not (Test-Path $PagePath)) {
  Write-Host "dashboard.html is missing. Put it in the same folder as argus.ps1: $Root" -ForegroundColor Red
  return
}

function Get-Pct($part, $whole) {
  if (-not $whole -or $whole -eq 0) { return $null }
  return [math]::Round([math]::Min(100, [math]::Max(0, 100.0 * $part / $whole)), 1)
}

$script:cache = $null
$script:cacheTime = [datetime]::MinValue

function Get-PcStatus {
  if ($script:cache -and ((Get-Date) - $script:cacheTime).TotalMilliseconds -lt 1500) { return $script:cache }

  $cpu = $null; $mem = $null; $net = $null; $disk = $null; $power = $null; $page = $null
  $powerLabel = 'POWER CELL'

  try { $cpu = [math]::Round((Get-CimInstance Win32_Processor | Measure-Object LoadPercentage -Average).Average, 1) } catch {}
  try {
    $os = Get-CimInstance Win32_OperatingSystem
    $mem = Get-Pct ($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) $os.TotalVisibleMemorySize
  } catch {}
  try {
    $nics = @(Get-CimInstance Win32_PerfFormattedData_Tcpip_NetworkInterface)
    $bits = ($nics | Measure-Object BytesTotalPersec -Sum).Sum * 8
    $bw = ($nics | Measure-Object CurrentBandwidth -Maximum).Maximum
    $net = Get-Pct $bits $bw
  } catch {}
  try {
    $c = Get-PSDrive -Name C
    $disk = Get-Pct $c.Used ($c.Used + $c.Free)
  } catch {}
  try {
    $bat = Get-CimInstance Win32_Battery | Select-Object -First 1
    if ($bat) { $power = [double]$bat.EstimatedChargeRemaining } else { $power = 100; $powerLabel = 'AC POWER' }
  } catch {}
  try {
    $pf = Get-CimInstance Win32_PageFileUsage | Select-Object -First 1
    if ($pf) { $page = Get-Pct $pf.CurrentUsage $pf.AllocatedBaseSize }
  } catch {}

  $script:cache = @{
    machine = $env:COMPUTERNAME
    vitals  = @(
      @{ label = 'CORE CPU';   value = $cpu  },
      @{ label = 'MEMORY';     value = $mem  },
      @{ label = 'NET UPLINK'; value = $net  },
      @{ label = 'DISK C:';    value = $disk },
      @{ label = $powerLabel;  value = $power },
      @{ label = 'PAGEFILE';   value = $page }
    )
  }
  $script:cacheTime = Get-Date
  return $script:cache
}

[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

function Get-WeatherWords([int]$c) {
  switch ($c) {
    0 { 'clear skies' }
    1 { 'mostly clear' }
    2 { 'partly cloudy' }
    3 { 'overcast' }
    { $_ -in 45, 48 } { 'foggy' }
    { $_ -in 51..57 } { 'drizzly' }
    { $_ -in 61..67 } { 'rainy' }
    { $_ -in 71..77 } { 'snowy' }
    { $_ -in 80..82 } { 'showery' }
    { $_ -in 85, 86 } { 'snow showers' }
    { $_ -ge 95 } { 'stormy' }
    default { 'mixed conditions' }
  }
}

$script:briefCache = $null
$script:briefTime = [datetime]::MinValue

function Get-DayBrief {
  if ($script:briefCache -and ((Get-Date) - $script:briefTime).TotalMinutes -lt 10) { return $script:briefCache }
  $weather = @(); $tips = @(); $tomorrow = @(); $tomorrowTips = @()
  try {
    $u = "https://api.open-meteo.com/v1/forecast?latitude=$($Location.Lat)&longitude=$($Location.Lon)" +
         "&current=temperature_2m,apparent_temperature,weather_code,wind_speed_10m" +
         "&daily=temperature_2m_max,temperature_2m_min,precipitation_probability_max,uv_index_max,weather_code" +
         "&temperature_unit=fahrenheit&wind_speed_unit=mph&timezone=auto&forecast_days=2"
    $r = Invoke-RestMethod -Uri $u -TimeoutSec 8
    $now  = [math]::Round($r.current.temperature_2m)
    $feel = [math]::Round($r.current.apparent_temperature)
    $wind = [math]::Round($r.current.wind_speed_10m)
    $hi   = [math]::Round($r.daily.temperature_2m_max[0])
    $lo   = [math]::Round($r.daily.temperature_2m_min[0])
    $rain = [int]$r.daily.precipitation_probability_max[0]
    $uv   = [double]$r.daily.uv_index_max[0]
    $code = [int]$r.daily.weather_code[0]
    $line = "Right now in $($Location.Name) it's $now degrees and $(Get-WeatherWords ([int]$r.current.weather_code))"
    if ([math]::Abs($feel - $now) -ge 3) { $line += ", feeling like $feel" }
    $weather += "$line."
    $weather += "Today's high is $hi with a low of $lo, and a $rain percent chance of rain."

    if ($code -ge 95)      { $tips += 'Thunderstorms are possible, so plan for indoor time.' }
    if ($rain -ge 50)      { $tips += 'Rain is likely. Bring an umbrella.' }
    elseif ($rain -ge 30)  { $tips += 'There is some chance of rain, so keep an umbrella handy.' }
    if ($hi -ge 90)        { $tips += 'It will be hot. Stay hydrated.' }
    if ($lo -le 50 -or $now -le 55) { $tips += 'It is chilly. Grab a jacket.' }
    if ($uv -ge 7)         { $tips += 'UV is high, so wear sunscreen if you are outside.' }
    if ($wind -ge 20)      { $tips += "It's windy out there, about $wind miles per hour." }
    if ($tips.Count -eq 0) { $tips += 'Looks like a good day to get outside.' }

    # Tomorrow
    $hi2   = [math]::Round($r.daily.temperature_2m_max[1])
    $lo2   = [math]::Round($r.daily.temperature_2m_min[1])
    $rain2 = [int]$r.daily.precipitation_probability_max[1]
    $uv2   = [double]$r.daily.uv_index_max[1]
    $code2 = [int]$r.daily.weather_code[1]
    $tomorrow += "Tomorrow looks $(Get-WeatherWords $code2), with a high of $hi2, a low of $lo2, and a $rain2 percent chance of rain."
    if ($code2 -ge 95)      { $tomorrowTips += 'Storms are possible tomorrow.' }
    if ($rain2 -ge 50)      { $tomorrowTips += 'Bring an umbrella and shoes that can handle puddles.' }
    elseif ($rain2 -ge 30)  { $tomorrowTips += 'Keep an umbrella handy just in case.' }
    if ($hi2 -ge 90)        { $tomorrowTips += 'Wear something light and breathable.' }
    elseif ($hi2 -ge 75)    { $tomorrowTips += 'A t-shirt should be fine for most of the day.' }
    if ($lo2 -le 50)        { $tomorrowTips += 'Mornings will be chilly, so bring a jacket or hoodie.' }
    elseif ($lo2 -le 60)    { $tomorrowTips += 'A light layer for the morning is a good idea.' }
    if ($uv2 -ge 7)         { $tomorrowTips += 'UV will be high, so sunscreen if you are outside.' }
  } catch {
    Write-Host "Weather lookup failed: $($_.Exception.Message)" -ForegroundColor Yellow
  }
  $result = @{ weather = $weather; tips = $tips; tomorrow = $tomorrow; tomorrowTips = $tomorrowTips; suggestions = $DailySuggestions }
  if ($weather.Count -gt 0) { $script:briefCache = $result; $script:briefTime = Get-Date }
  return $result
}

# Every app in the Start menu can be opened by name ("open discord", "open steam").
$script:StartApps = @()
try { $script:StartApps = @(Get-StartApps | Where-Object { $_.Name -notmatch 'uninstall|readme|documentation|release notes' }) } catch {}

# Windows ARGUS will never close (closing these would shut ARGUS itself down).
$Protected = @('powershell', 'pwsh', 'WindowsTerminal', 'conhost')

function Get-Simple([string]$s) { return (($s.ToLower() -replace '[^a-z0-9 ]', '') -replace '\s+', ' ').Trim() }

function Find-StartApp([string]$name) {
  $n = Get-Simple $name
  if (-not $n) { return $null }
  $hit = $script:StartApps | Where-Object { (Get-Simple $_.Name) -eq $n } | Select-Object -First 1
  if (-not $hit) { $hit = $script:StartApps | Where-Object { (Get-Simple $_.Name).StartsWith($n) } | Sort-Object { $_.Name.Length } | Select-Object -First 1 }
  if (-not $hit -and $n.Length -ge 3) { $hit = $script:StartApps | Where-Object { (Get-Simple $_.Name).Contains($n) } | Sort-Object { $_.Name.Length } | Select-Object -First 1 }
  return $hit
}

# ---------------------------------------------------------------------------
#  QUESTIONS  -  "Argus, when was World War 2?"  "Argus, who is the president of France?"
#  Tries a quick answer (DuckDuckGo), then Wikipedia, then opens Google.
# ---------------------------------------------------------------------------
function Get-Sentences([string]$text, [int]$count = 2) {
  $parts = [regex]::Split($text.Trim(), '(?<=[.!?])\s+(?=[A-Z0-9])')
  $out = ($parts | Select-Object -First $count) -join ' '
  if ($out.Length -gt 420) { $out = $out.Substring(0, 417) + '...' }
  return $out
}

function Get-Answer([string]$question) {
  $q = ($question -replace '(?i)\b(hey|ok|okay|argus|argos|jarvis|please|can you tell me|do you know|tell me)\b', ' ').Trim(' ', ',', '.', '?', '!')
  $q = ($q -replace '\s+', ' ').Trim()
  if (-not $q) { return "What would you like to know?" }
  $ua = 'ARGUS-PC/1.0 (personal assistant)'

  # 1) Instant answers: math, conversions, quick facts
  try {
    $d = Invoke-RestMethod -Uri ("https://api.duckduckgo.com/?format=json&no_html=1&skip_disambig=1&q=" + [uri]::EscapeDataString($q)) -TimeoutSec 6 -UserAgent $ua
    if ($d.Answer -and "$($d.Answer)".Length -lt 300) { return [string]$d.Answer }
  } catch {}

  # 2) Wikipedia: strip the question words and look up the topic
  $topic = $q -replace '(?i)^(who|what|when|where|why|how|which)(''s|\s+(is|was|are|were|did|does|do|many|much|old|far|long|big|tall))*\s+', ''
  $topic = $topic -replace '(?i)^(the|a|an)\s+', '' -replace '(?i)\s+(start|end|begin|happen|born|die|invented|made|built|founded)$', ''
  $topic = $topic -replace '(?i)\bww\s*2\b|\bwwii\b', 'World War II' -replace '(?i)\bww\s*1\b|\bwwi\b', 'World War I'
  try {
    $s = Invoke-RestMethod -Uri ("https://en.wikipedia.org/w/api.php?action=query&list=search&srlimit=1&format=json&srsearch=" + [uri]::EscapeDataString($topic)) -TimeoutSec 6 -UserAgent $ua
    $title = $s.query.search[0].title
    if ($title) {
      $sum = Invoke-RestMethod -Uri ("https://en.wikipedia.org/api/rest_v1/page/summary/" + [uri]::EscapeDataString($title)) -TimeoutSec 6 -UserAgent $ua
      if ($sum.type -ne 'disambiguation' -and $sum.extract) { return (Get-Sentences $sum.extract 2) }
    }
  } catch {}

  # 3) Fall back to Google on screen
  Start-Process ('https://www.google.com/search?q=' + [uri]::EscapeDataString($q))
  return "I couldn't find a quick answer, so I've pulled it up on Google."
}

# ---------------------------------------------------------------------------
#  CONVERSATION
# ---------------------------------------------------------------------------
$LogPath = Join-Path $Root 'argus-log.txt'
function Write-Log([string]$msg) {
  try { Add-Content -Path $LogPath -Value ("[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $msg) -Encoding UTF8 } catch {}
}
Write-Log '===== ARGUS started ====='

$script:Chat = New-Object System.Collections.ArrayList
$script:ChatLast = Get-Date

function Add-ChatTurn([string]$user, [string]$assistant) {
  if (((Get-Date) - $script:ChatLast).TotalMinutes -gt $ForgetAfterMinutes) { $script:Chat.Clear() }
  [void]$script:Chat.Add(@{ role = 'user'; content = $user })
  [void]$script:Chat.Add(@{ role = 'assistant'; content = $assistant })
  while ($script:Chat.Count -gt 30) { $script:Chat.RemoveRange(0, 2) }
  $script:ChatLast = Get-Date
}

function Get-AiMode {
  $key = if ($ClaudeApiKey) { $ClaudeApiKey } else { $env:ANTHROPIC_API_KEY }
  if ($key) { return @{ kind = 'claude'; key = $key } }
  try { $null = Invoke-RestMethod -Uri 'http://127.0.0.1:11434/api/tags' -TimeoutSec 5; return @{ kind = 'ollama' } }
  catch { Write-Log "Ollama not reachable: $($_.Exception.Message)" }
  return $null
}

function Get-SystemPrompt {
  $b = Get-DayBrief
  $weather = (@($b.weather) + @($b.tips)) -join ' '
  if (-not $weather) { $weather = 'unknown right now' }
  $tmrw = (@($b.tomorrow) + @($b.tomorrowTips)) -join ' '
  if (-not $tmrw) { $tmrw = 'unknown right now' }
  $now = Get-Date
  return @"
You are A.R.G.U.S. (Advanced Response and General User Support), called Argus for short: a personal AI assistant modeled after the calm, hyper-competent demeanor of J.A.R.V.I.S. and the vigilant loyalty of the mythological guardian Argus. Communicate with composed precision, polite authority, and subtle dry wit. Anticipate next steps, flag blind spots proactively, and deliver concise, actionable responses without unnecessary fluff. You are speaking out loud to the user. Call the user "$UserName" now and then.
Your replies are read aloud by a speech engine, so: plain sentences only, no lists, no markdown, no emojis. Keep it to one to three short sentences unless asked for more detail.
Be specific and practical. Use the context below when it helps (for example, use the weather when asked what to wear, and the time of day when asked what to eat). Remember what was said earlier in the conversation and build on it. Always answer the user's newest message directly; never repeat an earlier answer unless asked. Short follow-ups like "what about tomorrow?" or "why?" refer to the previous topic. Ask a short follow-up question when it would help.
You cannot control the computer yourself. If the user wants that, tell them to say things like "open Spotify", "close Chrome", "search for ...", "volume up" or "lock my computer".
Context:
- Now: $($now.ToString('dddd, MMMM d, yyyy h:mm tt'))
- Location: $($Location.Name)
- Weather today: $weather
- Weather tomorrow: $tmrw
- The user's current priorities: $($Priorities -join ' ') Connect your suggestions to these when it fits, without forcing it.
- The user's own reminders for today: $($DailySuggestions -join ' ')
"@
}

function Invoke-Ai($mode, $messages) {
  $system = Get-SystemPrompt
  if ($mode.kind -eq 'claude') {
    $body = @{ model = $ClaudeModel; max_tokens = 350; system = $system; messages = @($messages) } | ConvertTo-Json -Depth 6 -Compress
    $r = Invoke-RestMethod -Uri 'https://api.anthropic.com/v1/messages' -Method Post -TimeoutSec 60 `
      -Headers @{ 'x-api-key' = $mode.key; 'anthropic-version' = '2023-06-01' } `
      -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($body))
    return (($r.content | Where-Object { $_.type -eq 'text' }) | ForEach-Object { $_.text }) -join ' '
  }
  $msgs = @(@{ role = 'system'; content = $system }) + @($messages)
  $body = @{ model = $OllamaModel; messages = $msgs; stream = $false; keep_alive = '30m'; options = @{ num_predict = 220 } } | ConvertTo-Json -Depth 6 -Compress
  $r = Invoke-RestMethod -Uri 'http://127.0.0.1:11434/api/chat' -Method Post -TimeoutSec 90 `
    -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($body))
  return [string]$r.message.content
}

function Get-SimpleAdvice([string]$text) {
  $t = $text.ToLower()
  if ($t -match '\b(wear|outfit|jacket|coat|dress)\b') {
    $b = Get-DayBrief
    if (@($b.weather).Count -eq 0) { return "I can't reach the weather right now, so check outside before you pick an outfit." }
    if ($t -match 'tomorrow') { return ((@($b.tomorrow) + @($b.tomorrowTips)) -join ' ') }
    $tips = @($b.tips) -join ' '
    return "$(@($b.weather)[1]) $tips"
  }
  if ($t -match '\b(eat|hungry|food|breakfast|lunch|dinner|snack|meal)\b') {
    $h = (Get-Date).Hour
    if ($h -lt 11) { return 'For breakfast, eggs with toast or oatmeal with fruit will keep you full until lunch.' }
    if ($h -lt 16) { return 'For lunch, try a chicken wrap or a rice bowl with some vegetables. Something with protein keeps your energy up.' }
    if ($h -lt 21) { return 'For dinner, salmon or chicken with rice and greens is a solid choice. Or treat yourself and order in.' }
    return "It's late, so keep it light. Yogurt, fruit, or a handful of nuts."
  }
  return $null
}

function Get-ChatReply([string]$text) {
  $t = $text.ToLower()
  if ($t -match '(new conversation|start over|forget (that|everything|it)|clear (the |our )?(conversation|chat))') {
    $script:Chat.Clear(); return @{ reply = 'Fresh start. What can I do for you?'; ai = $true }
  }
  $mode = Get-AiMode
  Write-Log ("chat request: `"{0}`" | brain={1} | remembered turns={2}" -f $text, $(if ($mode) { $mode.kind } else { 'none' }), [int]($script:Chat.Count / 2))
  if (-not $mode) {
    $simple = Get-SimpleAdvice $text
    $reply = if ($simple) { $simple } else { Get-Answer $text }
    Add-ChatTurn $text $reply
    return @{ reply = $reply; ai = $false }
  }
  if (((Get-Date) - $script:ChatLast).TotalMinutes -gt $ForgetAfterMinutes) { $script:Chat.Clear() }
  $messages = @($script:Chat | ForEach-Object { @{ role = $_.role; content = $_.content } }) + @(@{ role = 'user'; content = $text })
  try {
    $reply = (Invoke-Ai $mode $messages) -replace '[*#_`]', '' -replace '\s+', ' '
    $reply = $reply.Trim()
    if (-not $reply) { $reply = "Sorry, I lost my train of thought. Could you say that again?" }
  } catch {
    Write-Host "AI error ($($mode.kind)): $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Log "AI error ($($mode.kind)): $($_.Exception.Message)"
    $simple = Get-SimpleAdvice $text
    $reply = if ($simple) { $simple } else { Get-Answer $text }
  }
  Add-ChatTurn $text $reply
  Write-Log "chat reply: $reply"
  return @{ reply = $reply; ai = $true }
}

function Send-Keys($code, $times) {
  $wsh = New-Object -ComObject WScript.Shell
  for ($i = 0; $i -lt $times; $i++) { $wsh.SendKeys([string][char]$code) }
}

function Invoke-PcCommand([string]$text) {
  $t = $text.ToLower() -replace '[^a-z0-9: ]', ' '
  $t = $t -replace '\b(hey|ok|okay|argus|argos|jarvis|please|can you|could you|for me|now)\b', ' '
  $t = ($t -replace '\s+', ' ').Trim()

  if ($t -match '^(open|launch|start|run|pull up|go to)\s+(the\s+|my\s+)?(.+)$') {
    $verb = $Matches[1]
    $name = $Matches[3].Trim()
    if ($Apps.ContainsKey($name)) {
      try { Start-Process $Apps[$name]; return @{ handled = $true; action = "OPEN $name"; reply = "Opening $name." } }
      catch { return @{ handled = $true; action = 'OPEN FAILED'; reply = "I couldn't open $name. It may not be installed." } }
    }
    if ($Sites.ContainsKey($name)) {
      Start-Process $Sites[$name]
      return @{ handled = $true; action = "SITE $name"; reply = "Pulling up $name." }
    }
    $app = Find-StartApp $name
    if ($app) {
      Start-Process explorer.exe "shell:AppsFolder\$($app.AppID)"
      return @{ handled = $true; action = "OPEN $($app.Name)"; reply = "Opening $($app.Name)." }
    }
    # A plain "open X" that isn't installed gets a straight answer; anything else
    # ("start a conversation", "run me through my day") goes to the conversation.
    if ($verb -in 'open', 'launch' -and ($name -split ' ').Count -le 3) {
      return @{ handled = $true; action = 'NOT FOUND'; reply = "I couldn't find an app called $name on this computer." }
    }
    return @{ handled = $false }
  }

  if ($t -match '^(close|quit|exit)\s+(the\s+|my\s+)?(.+)$') {
    $name = $Matches[3].Trim()
    $key = $name -replace ' ', ''
    if ($key.Length -lt 3 -or $name -match '^(it|this|that|everything|all)$') {
      return @{ handled = $true; action = 'CLOSE'; reply = 'Tell me which app to close, like close Spotify.' }
    }
    $wins = @(Get-Process | Where-Object {
      $_.MainWindowHandle -ne 0 -and $_.Id -ne $PID -and
      $_.ProcessName -notin $Protected -and $_.MainWindowTitle -notmatch 'ARGUS|ARGUS' -and
      ($_.ProcessName -like "*$key*" -or $_.MainWindowTitle -like "*$name*")
    })
    if ($wins.Count -eq 0) { return @{ handled = $true; action = 'CLOSE'; reply = "I don't see $name open." } }
    if ($wins.Count -gt 3) { return @{ handled = $true; action = 'CLOSE'; reply = "That matches $($wins.Count) windows. Be a bit more specific." } }
    foreach ($w in $wins) { [void]$w.CloseMainWindow() }
    return @{ handled = $true; action = "CLOSE $name"; reply = "Closing $name." }
  }

  if ($t -match '^play (.+) on youtube$' -or $t -match '^(youtube|search youtube for)\s+(.+)$') {
    $q = if ($t -match '^play (.+) on youtube$') { $Matches[1] } else { ($t -replace '^(youtube|search youtube for)\s+', '') }
    Start-Process ('https://www.youtube.com/results?search_query=' + [uri]::EscapeDataString($q))
    return @{ handled = $true; action = 'YOUTUBE'; reply = "Searching YouTube for $q." }
  }
  if ($t -match '^(search for|search|google|look up)\s+(.+)$') {
    $q = $Matches[2]
    Start-Process ('https://www.google.com/search?q=' + [uri]::EscapeDataString($q))
    return @{ handled = $true; action = 'SEARCH'; reply = "Searching for $q." }
  }
  if ($t -match '^(minimize (everything|all|all windows)|show (me )?(the )?desktop)$') {
    (New-Object -ComObject Shell.Application).MinimizeAll()
    return @{ handled = $true; action = 'MINIMIZE ALL'; reply = 'Clearing the screen.' }
  }
  if ($t -match '^(bring (everything|it all) back|restore (everything|all|windows))$') {
    (New-Object -ComObject Shell.Application).UndoMinimizeALL()
    return @{ handled = $true; action = 'RESTORE'; reply = 'Bringing everything back.' }
  }
  if ($t -match '^(take a )?screenshot$') {
    Start-Process 'ms-screenclip:'
    return @{ handled = $true; action = 'SCREENSHOT'; reply = 'Select the area you want.' }
  }
  if ($t -match '^lock( the| my)?( pc| computer| screen)?$') {
    Start-Process rundll32.exe 'user32.dll,LockWorkStation'
    return @{ handled = $true; action = 'LOCK'; reply = 'Locking the workstation.' }
  }
  if ($t -match '^(mute|unmute)') { Send-Keys 173 1; return @{ handled = $true; action = 'MUTE'; reply = 'Done.' } }
  if ($t -match 'volume up|louder|turn it up')   { Send-Keys 175 5; return @{ handled = $true; action = 'VOLUME UP';   reply = 'Volume up.' } }
  if ($t -match 'volume down|quieter|turn it down') { Send-Keys 174 5; return @{ handled = $true; action = 'VOLUME DOWN'; reply = 'Volume down.' } }
  if ($t -match 'battery') {
    $bat = Get-CimInstance Win32_Battery | Select-Object -First 1
    if ($bat) { return @{ handled = $true; action = 'BATTERY'; reply = "Battery is at $($bat.EstimatedChargeRemaining) percent." } }
    return @{ handled = $true; action = 'BATTERY'; reply = 'This machine is running on wall power. No battery detected.' }
  }
  if ($t -match 'disk|storage|space') {
    $c = Get-PSDrive -Name C
    $free = [math]::Round($c.Free / 1GB)
    return @{ handled = $true; action = 'DISK'; reply = "Drive C has $free gigabytes free." }
  }
  if ($t -match 'uptime|how long.*(on|running)') {
    $up = (Get-Date) - (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
    return @{ handled = $true; action = 'UPTIME'; reply = "This computer has been running for $($up.Days) days and $($up.Hours) hours." }
  }
  if ($t -match '^(shut ?down|restart|reboot)') {
    return @{ handled = $true; action = 'REFUSED'; reply = "I'd rather you do that one yourself, Sir." }
  }
  return @{ handled = $false }
}

function Send-Response($ctx, [int]$code, [string]$type, [byte[]]$bytes) {
  $res = $ctx.Response
  $res.StatusCode = $code
  $res.ContentType = $type
  $res.Headers['Cache-Control'] = 'no-store'
  $res.ContentLength64 = $bytes.Length
  $res.OutputStream.Write($bytes, 0, $bytes.Length)
}
function Send-Json($ctx, $obj, [int]$code = 200) {
  $json = $obj | ConvertTo-Json -Depth 5 -Compress
  Send-Response $ctx $code 'application/json; charset=utf-8' ([Text.Encoding]::UTF8.GetBytes($json))
}

function Handle-Request($ctx) {
  $req = $ctx.Request
  $path = $req.Url.AbsolutePath

  # Only the dashboard served from this address may talk to ARGUS.
  $origin = $req.Headers['Origin']
  if ($origin -and $origin -ne "http://localhost:$Port") { Send-Json $ctx @{ error = 'forbidden' } 403; return }

  if ($path -eq '/' -or $path -eq '/index.html') {
    Send-Response $ctx 200 'text/html; charset=utf-8' ([IO.File]::ReadAllBytes($PagePath)); return
  }
  if ($path -like '/api/*' -and $req.Headers['X-Argus'] -ne '1') { Send-Json $ctx @{ error = 'forbidden' } 403; return }

  if ($path -eq '/api/status' -and $req.HttpMethod -eq 'GET') { Send-Json $ctx (Get-PcStatus); return }
  if ($path -eq '/api/brief' -and $req.HttpMethod -eq 'GET') { Send-Json $ctx (Get-DayBrief); return }
  if ($path -eq '/api/chat' -and $req.HttpMethod -eq 'POST') {
    $body = (New-Object IO.StreamReader($req.InputStream, [Text.Encoding]::UTF8)).ReadToEnd()
    $text = ''
    try { $text = [string]($body | ConvertFrom-Json).text } catch {}
    $res = Get-ChatReply $text
    Write-Host ("[{0}] You: {1}" -f (Get-Date -Format 'HH:mm:ss'), $text) -ForegroundColor White
    Write-Host ("           ARGUS: {0}" -f $res.reply) -ForegroundColor Cyan
    Send-Json $ctx $res; return
  }
  if ($path -eq '/api/log' -and $req.HttpMethod -eq 'POST') {
    $body = (New-Object IO.StreamReader($req.InputStream, [Text.Encoding]::UTF8)).ReadToEnd()
    try { Write-Log ('dashboard: ' + [string]($body | ConvertFrom-Json).msg) } catch {}
    Send-Json $ctx @{ ok = $true }; return
  }
  if ($path -eq '/api/note' -and $req.HttpMethod -eq 'POST') {
    $body = (New-Object IO.StreamReader($req.InputStream, [Text.Encoding]::UTF8)).ReadToEnd()
    try { $n = $body | ConvertFrom-Json; if ($n.user -and $n.assistant) { Add-ChatTurn ([string]$n.user) ([string]$n.assistant) } } catch {}
    Send-Json $ctx @{ ok = $true }; return
  }
  if ($path -eq '/api/ask' -and $req.HttpMethod -eq 'POST') {
    $body = (New-Object IO.StreamReader($req.InputStream, [Text.Encoding]::UTF8)).ReadToEnd()
    $text = ''
    try { $text = [string]($body | ConvertFrom-Json).text } catch {}
    $answer = Get-Answer $text
    Write-Host ("[{0}] Q: {1}  ->  {2}" -f (Get-Date -Format 'HH:mm:ss'), $text, $answer) -ForegroundColor Cyan
    Send-Json $ctx @{ reply = $answer }; return
  }
  if ($path -eq '/api/command' -and $req.HttpMethod -eq 'POST') {
    $body = (New-Object IO.StreamReader($req.InputStream, [Text.Encoding]::UTF8)).ReadToEnd()
    $text = ''
    try { $text = [string]($body | ConvertFrom-Json).text } catch {}
    $result = Invoke-PcCommand $text
    Write-Log ("command check: `"{0}`" -> {1}" -f $text, $(if ($result.handled) { $result.reply } else { 'not a PC command' }))
    if ($result.handled) { Add-ChatTurn $text $result.reply }
    if ($result.handled) { Write-Host ("[{0}] {1}  ->  {2}" -f (Get-Date -Format 'HH:mm:ss'), $text, $result.reply) -ForegroundColor Cyan }
    Send-Json $ctx $result; return
  }
  Send-Json $ctx @{ error = 'not found' } 404
}

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$Port/")
try { $listener.Start() }
catch {
  Write-Host "Port $Port is busy. Try: .\argus.ps1 -Port 8090" -ForegroundColor Red
  return
}

Write-Host ''
Write-Host '  A.R.G.U.S.  ONLINE' -ForegroundColor Cyan
Write-Host "  Dashboard:  http://localhost:$Port" -ForegroundColor Cyan
Write-Host '  Stop:       Ctrl+C or close this window' -ForegroundColor DarkCyan
Write-Host ''
if (-not $NoBrowser) { Start-Process "http://localhost:$Port" }

try {
  while ($listener.IsListening) {
    $task = $listener.GetContextAsync()
    while (-not $task.AsyncWaitHandle.WaitOne(250)) { }
    $ctx = $task.GetAwaiter().GetResult()
    try { Handle-Request $ctx }
    catch {
      Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Yellow
      try { Send-Json $ctx @{ error = 'server error' } 500 } catch {}
    }
    finally { try { $ctx.Response.Close() } catch {} }
  }
}
finally {
  $listener.Stop(); $listener.Close()
  Write-Host 'ARGUS PC LINK OFFLINE' -ForegroundColor DarkCyan
}
