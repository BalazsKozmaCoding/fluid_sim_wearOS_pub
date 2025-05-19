# Ensure Ultimate Performance plan is available
$ultimateGuid = "e9a42b02-d5df-448d-aa00-03f14749eb61"
$existingPlans = powercfg -list

if ($existingPlans -notmatch $ultimateGuid) {
    powercfg -duplicatescheme $ultimateGuid > $null
}

# Define power plans (from screenshot + Ultimate)
$plans = @(
    @{ Name = "Balanced (OEM 1)"; GUID = "381b4222-f694-41f0-9685-ff5bb260df2e" },
    @{ Name = "Balanced (OEM 2)"; GUID = "49ef8fc0-bb7f-488e-b6a0-f1fc77ec649b" },
    @{ Name = "Cool (Low Temp)";  GUID = "6714fd06-2c45-4789-99d5-c8a90034c8a7" },
    @{ Name = "Quiet (Low Fan)";  GUID = "dea1a47b-7939-4ad2-9293-eafb59386025" },
    @{ Name = "High Performance"; GUID = "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c" },
    @{ Name = "Ultra High Perf";  GUID = $ultimateGuid }
)

# Get desktop path
$desktop = [Environment]::GetFolderPath("Desktop")

# Create desktop shortcuts
foreach ($plan in $plans) {
    $lnkPath = Join-Path $desktop "$($plan.Name).lnk"
    $target = "powercfg"
    $args = "-setactive $($plan.GUID)"

    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($lnkPath)
    $shortcut.TargetPath = $target
    $shortcut.Arguments = $args
    $shortcut.WindowStyle = 1
    $shortcut.IconLocation = "shell32.dll,44"
    $shortcut.Save()
}