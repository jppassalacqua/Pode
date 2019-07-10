function Start-PodeServer
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [scriptblock]
        $ScriptBlock,

        [Parameter()]
        [int]
        $Interval = 0,

        [Parameter()]
        [string]
        $Name,

        [Parameter()]
        [int]
        $Threads = 1,

        [Parameter()]
        [string]
        $RootPath,

        [Parameter()]
        $Request,

        [Parameter()]
        [ValidateSet('', 'Azure-Functions', 'Aws-Lambda')]
        [string]
        $Type,

        [switch]
        $DisableTermination,

        [switch]
        $DisableLogging,

        [switch]
        $Browse
    )

    # ensure the session is clean
    $PodeContext = $null

    try {
        # configure the server's root path
        if (!(Test-IsEmpty $RootPath)) {
            $RootPath = Get-PodeRelativePath -Path $RootPath -RootPath $MyInvocation.PSScriptRoot -JoinRoot -Resolve -TestPath
        }

        # create main context object
        $PodeContext = New-PodeContext -ScriptBlock $ScriptBlock `
            -Threads $Threads `
            -Interval $Interval `
            -ServerRoot (Protect-PodeValue -Value $RootPath -Default $MyInvocation.PSScriptRoot) `
            -ServerType $Type `
            -DisableLogging:$DisableLogging

        # set it so ctrl-c can terminate, unless serverless
        if (!$PodeContext.Server.IsServerless) {
            [Console]::TreatControlCAsInput = $true
        }

        # start the file monitor for interally restarting
        Start-PodeFileMonitor

        # start the server
        Start-PodeInternalServer -Request $Request -Browse:$Browse

        # at this point, if it's just a one-one off script, return
        if ([string]::IsNullOrWhiteSpace($PodeContext.Server.Type) -or $PodeContext.Server.IsServerless) {
            return
        }

        # sit here waiting for termination/cancellation, or to restart the server
        while (!(Test-PodeTerminationPressed -Key $key) -and !($PodeContext.Tokens.Cancellation.IsCancellationRequested)) {
            Start-Sleep -Seconds 1

            # get the next key presses
            $key = Get-PodeConsoleKey

            # check for internal restart
            if (($PodeContext.Tokens.Restart.IsCancellationRequested) -or (Test-PodeRestartPressed -Key $key)) {
                Restart-PodeInternalServer
            }
        }

        Write-Host 'Terminating...' -NoNewline -ForegroundColor Yellow
        $PodeContext.Tokens.Cancellation.Cancel()
    }
    finally {
        # clean the runspaces and tokens
        Close-PodeServer -Exit

        # clean the session
        $PodeContext = $null
    }
}

function Pode
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [ValidateSet('init', 'test', 'start', 'install', 'build')]
        [Alias('a')]
        [string]
        $Action,

        [switch]
        [Alias('d')]
        $Dev
    )

    # default config file name and content
    $file = './package.json'
    $name = Split-Path -Leaf -Path $pwd
    $data = $null

    # default config data that's used to populate on init
    $map = @{
        'name' = $name;
        'version' = '1.0.0';
        'description' = '';
        'main' = './server.ps1';
        'scripts' = @{
            'start' = './server.ps1';
            'install' = 'yarn install --force --ignore-scripts --modules-folder pode_modules';
            "build" = 'psake';
            'test' = 'invoke-pester ./tests/*.ps1'
        };
        'author' = '';
        'license' = 'MIT';
    }

    # check and load config if already exists
    if (Test-Path $file) {
        $data = (Get-Content $file | ConvertFrom-Json)
    }

    # quick check to see if the data is required
    if ($Action -ine 'init') {
        if ($null -eq $data) {
            Write-Host 'package.json file not found' -ForegroundColor Red
            return
        }
        else {
            $actionScript = $data.scripts.$Action

            if ([string]::IsNullOrWhiteSpace($actionScript) -and $Action -ieq 'start') {
                $actionScript = $data.main
            }

            if ([string]::IsNullOrWhiteSpace($actionScript) -and $Action -ine 'install') {
                Write-Host "package.json does not contain a script for the $($Action) action" -ForegroundColor Yellow
                return
            }
        }
    }
    else {
        if ($null -ne $data) {
            Write-Host 'package.json already exists' -ForegroundColor Yellow
            return
        }
    }

    switch ($Action.ToLowerInvariant())
    {
        'init' {
            $v = Read-Host -Prompt "name ($($map.name))"
            if (![string]::IsNullOrWhiteSpace($v)) { $map.name = $v }

            $v = Read-Host -Prompt "version ($($map.version))"
            if (![string]::IsNullOrWhiteSpace($v)) { $map.version = $v }

            $map.description = Read-Host -Prompt "description"

            $v = Read-Host -Prompt "entry point ($($map.main))"
            if (![string]::IsNullOrWhiteSpace($v)) { $map.main = $v; $map.scripts.start = $v }

            $map.author = Read-Host -Prompt "author"

            $v = Read-Host -Prompt "license ($($map.license))"
            if (![string]::IsNullOrWhiteSpace($v)) { $map.license = $v }

            $map | ConvertTo-Json -Depth 10 | Out-File -FilePath $file -Encoding utf8 -Force
            Write-Host 'Success, saved package.json' -ForegroundColor Green
        }

        'test' {
            Invoke-PodePackageScript -ActionScript $actionScript
        }

        'start' {
            Invoke-PodePackageScript -ActionScript $actionScript
        }

        'install' {
            if ($Dev) {
                Install-PodeLocalModules -Modules $data.devModules
            }

            Install-PodeLocalModules -Modules $data.modules
            Invoke-PodePackageScript -ActionScript $actionScript
        }

        'build' {
            Invoke-PodePackageScript -ActionScript $actionScript
        }
    }
}

function Enable-PodeGui
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]
        $Title,

        [Parameter()]
        [string]
        $Icon,

        [Parameter()]
        [ValidateSet('Normal', 'Maximized', 'Minimized')]
        [string]
        $WindowState = 'Normal',

        [Parameter()]
        [ValidateSet('None', 'SingleBorderWindow', 'ThreeDBorderWindow', 'ToolWindow')]
        [string]
        $WindowStyle = 'SingleBorderWindow',

        [Parameter()]
        [ValidateSet('CanResize', 'CanMinimize', 'NoResize')]
        [string]
        $ResizeMode = 'CanResize',

        [Parameter()]
        [int]
        $Height = 0,

        [Parameter()]
        [int]
        $Width = 0,

        [Parameter()]
        [string]
        $EndpointName,

        [switch]
        $HideFromTaskbar
    )

    # error if serverless
    Test-PodeIsServerless -FunctionName 'Enable-PodeGui' -ThrowError

    # only valid for Windows PowerShell
    if (Test-IsPSCore) {
        throw 'The gui function is currently unavailable for PS Core, and only works for Windows PowerShell'
    }

    # enable the gui and set general settings
    $PodeContext.Server.Gui.Enabled = $true
    $PodeContext.Server.Gui.Title = $Title
    $PodeContext.Server.Gui.ShowInTaskbar = !$HideFromTaskbar
    $PodeContext.Server.Gui.WindowState = $WindowState
    $PodeContext.Server.Gui.WindowStyle = $WindowStyle
    $PodeContext.Server.Gui.ResizeMode = $ResizeMode

    # set the window's icon path
    if (![string]::IsNullOrWhiteSpace($Icon)) {
        $PodeContext.Server.Gui.Icon = (Resolve-Path $Icon).Path
        if (!(Test-Path $PodeContext.Server.Gui.Icon)) {
            throw "Path to icon for GUI does not exist: $($PodeContext.Server.Gui.Icon)"
        }
    }

    # set the height of the window
    $PodeContext.Server.Gui.Height = $Height
    if ($PodeContext.Server.Gui.Height -le 0) {
        $PodeContext.Server.Gui.Height = 'auto'
    }

    # set the width of the window
    $PodeContext.Server.Gui.Width = $Width
    if ($PodeContext.Server.Gui.Width -le 0) {
        $PodeContext.Server.Gui.Width = 'auto'
    }

    # set the gui to use a specific listener
    $PodeContext.Server.Gui.EndpointName = $EndpointName

    if (![string]::IsNullOrWhiteSpace($PodeContext.Server.Gui.EndpointName)) {
        $found = ($PodeContext.Server.Endpoints | Where-Object {
            $_.Name -eq $PodeContext.Server.Gui.EndpointName
        } | Select-Object -First 1)

        if ($null -eq $found) {
            throw "Endpoint with name '$($EndpointName)' does not exist"
        }

        $PodeContext.Server.Gui.Endpoint = $found
    }
}

function Add-PodeEndpoint
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]
        $Endpoint,

        [Parameter()]
        [ValidateSet('HTTP', 'HTTPS', 'SMTP', 'TCP')]
        [string]
        $Protocol,

        [Parameter()]
        [string]
        $Certificate = $null,

        [Parameter()]
        [string]
        $CertificateThumbprint = $null,

        [Parameter()]
        [string]
        $Name = $null,

        [switch]
        $Force,

        [switch]
        $SelfSigned
    )

    # error if serverless
    Test-PodeIsServerless -FunctionName 'Add-PodeEndpoint' -ThrowError

    # parse the endpoint for host/port info
    $_endpoint = Get-PodeEndpointInfo -Endpoint $Endpoint

    # if a name was supplied, check it is unique
    if (!(Test-IsEmpty $Name) -and
        (Get-PodeCount ($PodeContext.Server.Endpoints | Where-Object { $_.Name -eq $Name })) -ne 0)
    {
        throw "An endpoint with the name '$($Name)' has already been defined"
    }

    # new endpoint object
    $obj = @{
        Name = $Name
        Address = $null
        RawAddress = $Endpoint
        Port = $null
        IsIPAddress = $true
        HostName = 'localhost'
        Ssl = ($Protocol -ieq 'https')
        Protocol = $Protocol
        Certificate = @{
            Name = $Certificate
            Thumbprint = $CertificateThumbprint
            SelfSigned = $SelfSigned
        }
    }

    # set the ip for the context
    $obj.Address = (Get-PodeIPAddress $_endpoint.Host)
    if (!(Test-PodeIPAddressLocalOrAny -IP $obj.Address)) {
        $obj.HostName = "$($obj.Address)"
    }

    $obj.IsIPAddress = (Test-PodeIPAddress -IP $obj.Address -IPOnly)

    # set the port for the context
    $obj.Port = $_endpoint.Port

    # if the address is non-local, then check admin privileges
    if (!$Force -and !(Test-PodeIPAddressLocal -IP $obj.Address) -and !(Test-IsAdminUser)) {
        throw 'Must be running with administrator priviledges to listen on non-localhost addresses'
    }

    # has this endpoint been added before? (for http/https we can just not add it again)
    $exists = ($PodeContext.Server.Endpoints | Where-Object {
        ($_.Address -eq $obj.Address) -and ($_.Port -eq $obj.Port) -and ($_.Ssl -eq $obj.Ssl)
    } | Measure-Object).Count

    if (!$exists) {
        # has an endpoint already been defined for smtp/tcp?
        if (@('smtp', 'tcp') -icontains $Protocol -and $Protocol -ieq $PodeContext.Server.Type) {
            throw "An endpoint for $($Protocol.ToUpperInvariant()) has already been defined"
        }

        # set server type, ensure we aren't trying to change the server's type
        $_type = (Resolve-PodeValue -Check ($Protocol -ieq 'https') -TrueValue 'http' -FalseValue $Protocol)
        if ([string]::IsNullOrWhiteSpace($PodeContext.Server.Type)) {
            $PodeContext.Server.Type = $_type
        }
        elseif ($PodeContext.Server.Type -ine $_type) {
            throw "Cannot add $($Protocol.ToUpperInvariant()) endpoint when already listening to $($PodeContext.Server.Type.ToUpperInvariant()) endpoints"
        }

        # add the new endpoint
        $PodeContext.Server.Endpoints += $obj
    }
}