# Public password installer. The application source and node files stay private.
param([switch]$NoPath)
& {
    $ErrorActionPreference = 'Stop'
    if (-not [Environment]::Is64BitOperatingSystem -or $env:PROCESSOR_ARCHITECTURE -ne 'AMD64') { throw 'ccgo requires native Windows x64 PowerShell.' }
    # Refuse early on Windows 10 and Server; ccgo itself checks again before setup.
    # The variable is the documented test-only override for hosted Windows Server CI.
    $system = $null
    try { $system = Get-CimInstance Win32_OperatingSystem } catch { }
    if ($system -and $env:CCGO_TEST_ALLOW_UNSUPPORTED_SETUP -ne '1' -and ($system.ProductType -ne 1 -or [int]$system.BuildNumber -lt 22000)) { throw 'ccgo needs Windows 11.' }
    $feed = 'https://raw.githubusercontent.com/kemarachanger/ccgo-downloads/main/updates/windows-amd64.json'
    $expectedManifestHash = 'e3d00c7d9cd6fba636d515405711ee378286ddcf8d9de60c9cca5abe89c1e474'
    $work = Join-Path ([IO.Path]::GetTempPath()) ('ccgo-download-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $work | Out-Null
    $password = $null
    function Get-CcgoHash([string]$Path) {
        $stream = [IO.File]::OpenRead($Path)
        $sha = [Security.Cryptography.SHA256]::Create()
        try { [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-','').ToLowerInvariant() } finally { $sha.Dispose(); $stream.Dispose() }
    }
    try {
        Write-Output 'ccgo | Downloading the current Windows package'
        $manifestFile = Join-Path $work 'update.json'
        Invoke-WebRequest -UseBasicParsing -Uri $feed -OutFile $manifestFile -TimeoutSec 40
        if ((Get-CcgoHash $manifestFile) -ine $expectedManifestHash) { throw 'Release metadata verification failed.' }
        $manifest = Get-Content -LiteralPath $manifestFile -Raw | ConvertFrom-Json
        if ([int]$manifest.schema -lt 1 -or $manifest.platform -ne 'windows-amd64' -or $manifest.format -ne 'zip' -or $manifest.version -notmatch '^\d+\.\d+\.\d+$' -or $manifest.url -notmatch '^https://github\.com/kemarachanger/ccgo-downloads/releases/download/') { throw 'Unsupported Windows release metadata.' }
        $secure = Read-Host 'ccgo | Download password' -AsSecureString
        $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
        try { $password = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
        if ($password.Length -lt 6 -or $password.Length -gt 128) { throw 'Enter the download password of 6-128 characters.' }
        $encryptedPath = Join-Path $work 'package.zip.enc'
        Invoke-WebRequest -UseBasicParsing -Uri $manifest.url -OutFile $encryptedPath -TimeoutSec 600
        if ((Get-Item -LiteralPath $encryptedPath).Length -gt 209715200 -or (Get-CcgoHash $encryptedPath) -ine $manifest.encrypted_sha256) { throw 'Encrypted package verification failed.' }
        $encrypted = [IO.File]::ReadAllBytes($encryptedPath)
        if ($encrypted.Length -lt 32 -or [Text.Encoding]::ASCII.GetString($encrypted,0,8) -ne 'Salted__') { throw 'Invalid encrypted package.' }
        $salt = New-Object byte[] 8
        [Array]::Copy($encrypted,8,$salt,0,8)
        $derive = [Security.Cryptography.Rfc2898DeriveBytes]::new($password,$salt,1000000,[Security.Cryptography.HashAlgorithmName]::SHA256)
        $derived = $derive.GetBytes(48)
        $key = New-Object byte[] 32
        $iv = New-Object byte[] 16
        [Array]::Copy($derived,0,$key,0,32)
        [Array]::Copy($derived,32,$iv,0,16)
        $aes = [Security.Cryptography.Aes]::Create()
        $aes.Key = $key; $aes.IV = $iv; $aes.Mode = 'CBC'; $aes.Padding = 'PKCS7'
        try { $plain = $aes.CreateDecryptor().TransformFinalBlock($encrypted,16,$encrypted.Length-16) } catch { throw 'Incorrect download password.' } finally { $aes.Dispose(); $derive.Dispose() }
        $archive = Join-Path $work 'package.zip'
        [IO.File]::WriteAllBytes($archive,$plain)
        if ((Get-CcgoHash $archive) -ine $manifest.sha256) { throw 'Decrypted package verification failed.' }
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [IO.Compression.ZipFile]::ExtractToDirectory($archive,$work)
        $bundle = Join-Path $work ('ccgo-' + $manifest.version + '-windows-amd64')
        $start = New-Object Diagnostics.ProcessStartInfo
        $start.FileName = Join-Path $bundle 'ccgo.exe'
        $start.Arguments = '__install "' + $bundle + '"'
        $start.UseShellExecute = $false
        $start.RedirectStandardInput = $true
        $process = [Diagnostics.Process]::Start($start)
        $process.StandardInput.WriteLine($password)
        $process.StandardInput.Close()
        $password = $null
        $process.WaitForExit()
        if ($process.ExitCode -ne 0) { throw 'Installation failed. Run the install command again.' }
        $bin = Join-Path $env:LOCALAPPDATA 'ccgo\bin'
        if (-not $NoPath) {
            $userPath = [Environment]::GetEnvironmentVariable('Path','User')
            if (-not (@($userPath -split ';') | Where-Object { $_.TrimEnd('\') -ieq $bin.TrimEnd('\') })) { [Environment]::SetEnvironmentVariable('Path',($bin + ';' + $userPath).TrimEnd(';'),'User') }
            if (-not (@($env:PATH -split ';') | Where-Object { $_.TrimEnd('\') -ieq $bin.TrimEnd('\') })) { $env:PATH = $bin + ';' + $env:PATH }
        }
        Write-Output 'ccgo | Ready. Run ccgo in a project folder.'
    } finally {
        $password = $null
        $resolvedWork = [IO.Path]::GetFullPath($work)
        $resolvedTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
        if ($resolvedWork.StartsWith($resolvedTemp,[StringComparison]::OrdinalIgnoreCase) -and [IO.Path]::GetFileName($resolvedWork) -like 'ccgo-download-*' -and (Test-Path -LiteralPath $resolvedWork)) { Remove-Item -LiteralPath $resolvedWork -Recurse -Force }
    }
}
