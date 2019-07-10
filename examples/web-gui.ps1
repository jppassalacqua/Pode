$path = Split-Path -Parent -Path (Split-Path -Parent -Path $MyInvocation.MyCommand.Path)
Import-Module "$($path)/src/Pode.psm1" -Force -ErrorAction Stop

# or just:
# Import-Module Pode

# create a server, and start listening on port 8090
Start-PodeServer {

    # listen on localhost:8090
    Add-PodeEndpoint -Endpoint localhost:8090 -Protocol HTTP -Name 'local1'
    Add-PodeEndpoint -Endpoint localhost:8091 -Protocol HTTP -Name 'local2'

    # tell this server to run as a desktop gui
    Enable-PodeGui -Title 'Pode Desktop Application' -Icon '../images/icon.png' -EndpointName 'local2' -ResizeMode 'NoResize'

    # set view engine to pode renderer
    Set-PodeViewEngine -Type Pode

    # GET request for web page on "localhost:8090/"
    route 'get' '/' {
        Write-PodeViewResponse -Path 'gui' -Data @{ 'numbers' = @(1, 2, 3); }
    }

 } 