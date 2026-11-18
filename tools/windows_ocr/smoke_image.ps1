$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$ocrRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$ocrFixture = Join-Path $ocrRoot 'test/fixtures/synthetic_receipt.png'
$ocrBundle = Join-Path $ocrRoot 'build/windows/x64/runner/Release/ocr'
$ocrBefore = (Get-FileHash -LiteralPath $ocrFixture -Algorithm SHA256).Hash
$ocrBitmap = [Drawing.Bitmap]::FromFile($ocrFixture)
$ocrProcess = New-Object Diagnostics.Process
$ocrStarted = $false
try {
    $ocrProcess.StartInfo.FileName = Join-Path $ocrBundle 'receipt_ocr_worker.exe'
    $ocrProcess.StartInfo.WorkingDirectory = $ocrBundle
    $ocrProcess.StartInfo.UseShellExecute = $false
    $ocrProcess.StartInfo.CreateNoWindow = $true
    $ocrProcess.StartInfo.RedirectStandardInput = $true
    $ocrProcess.StartInfo.RedirectStandardOutput = $true
    $ocrProcess.StartInfo.RedirectStandardError = $true
    $ocrProcess.StartInfo.EnvironmentVariables.Clear()
    $ocrProcess.StartInfo.EnvironmentVariables['SystemRoot'] = $env:SystemRoot
    $ocrProcess.StartInfo.EnvironmentVariables['PATH'] = Join-Path $env:SystemRoot 'System32'
    if (-not $ocrProcess.Start()) { throw 'Worker startup failed' }
    $ocrStarted = $true
    $ocrOutput = $ocrProcess.StandardOutput.ReadToEndAsync()
    $ocrError = $ocrProcess.StandardError.ReadToEndAsync()
    $ocrInput = $ocrProcess.StandardInput.BaseStream
    $ocrHeader = [Text.Encoding]::ASCII.GetBytes('RRO1') + [BitConverter]::GetBytes([uint32]$ocrBitmap.Width) + [BitConverter]::GetBytes([uint32]$ocrBitmap.Height)
    $ocrInput.Write($ocrHeader, 0, $ocrHeader.Length)
    $ocrRectangle = [Drawing.Rectangle]::new(0,0,$ocrBitmap.Width,$ocrBitmap.Height)
    $ocrLocked = $ocrBitmap.LockBits($ocrRectangle,[Drawing.Imaging.ImageLockMode]::ReadOnly,[Drawing.Imaging.PixelFormat]::Format32bppArgb)
    try {
        $ocrRow = New-Object byte[] ($ocrBitmap.Width * 4)
        for ($ocrY = 0; $ocrY -lt $ocrBitmap.Height; $ocrY++) {
            [Runtime.InteropServices.Marshal]::Copy([IntPtr]::Add($ocrLocked.Scan0,$ocrY * $ocrLocked.Stride),$ocrRow,0,$ocrRow.Length)
            for ($ocrX = 0; $ocrX -lt $ocrRow.Length; $ocrX += 4) {
                $ocrBlue = $ocrRow[$ocrX]
                $ocrRow[$ocrX] = $ocrRow[$ocrX+2]
                $ocrRow[$ocrX+2] = $ocrBlue
            }
            $ocrInput.Write($ocrRow,0,$ocrRow.Length)
        }
    } finally { $ocrBitmap.UnlockBits($ocrLocked) }
    $ocrProcess.StandardInput.Close()
    if (-not $ocrProcess.WaitForExit(30000)) { throw 'OCR smoke timed out' }
    $ocrTsv = $ocrOutput.GetAwaiter().GetResult()
    if ($ocrProcess.ExitCode -ne 0 -or $ocrError.GetAwaiter().GetResult()) { throw 'OCR smoke failed' }
    $ocrWords = @($ocrTsv.Split([char]10) | Where-Object { $_.StartsWith('5' + [char]9) } | ForEach-Object { $_.TrimEnd([char]13).Split([char]9)[11] })
    foreach ($ocrExpected in @('18.11.2026','MILK','BREAD','2,00','3,00','5,00',('YHTEENS' + [char]0xC4))) {
        if ($ocrWords -cnotcontains $ocrExpected) { throw ('Synthetic OCR is missing expected token: ' + $ocrExpected) }
    }
    if ((Get-FileHash -LiteralPath $ocrFixture -Algorithm SHA256).Hash -ne $ocrBefore) { throw 'Synthetic source changed' }
    Write-Output 'Synthetic receipt date, two products, amounts and total recognized; source unchanged.'
} finally {
    if ($ocrStarted -and -not $ocrProcess.HasExited) { $ocrProcess.Kill() }
    $ocrProcess.Dispose()
    $ocrBitmap.Dispose()
}
