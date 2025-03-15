#Requires -Version 3.0

param (
    [bool]$debugOut = $false,
    [ValidateSet("irm", "iwr", "net", $null)]
    [string]$httpMethod = $null
)

begin {
    try {
        # Set debug preference based on debugOut parameter
        if ($debugOut) { $DebugPreference = "Continue" }
        Write-Debug "Starting script execution in BEGIN block. DebugOut: $debugOut, HttpMethod: $httpMethod"

        # Define variables
        $s3Host = "s3.us-east-1.amazonaws.com"
        $s3Url = "https://mapxpress.s3.us-east-1.amazonaws.com/litchfield/assessormaps/assessormap_35.pdf"
        $port = 443
        $tcpClient = $null  # Will be initialized later if needed
        $httpbinUrl = "https://httpbin.org/get"
        $customUA = "MyCustomAgent/1.0 (Windows; PowerShell/3.0)"  # Custom User-Agent string

        Write-Debug "Variables defined: s3Host=$s3Host, s3Url=$s3Url, port=$port, httpbinUrl=$httpbinUrl, customUA=$customUA"
    }
    catch {
        Write-Error "Error in BEGIN block: $($_.Exception.Message)" -ErrorAction Stop
    }
}

process {
    try {
        # Test 1: DNS resolution
        Write-Output "Testing DNS resolution for $s3Host..."
        Write-Debug "Attempting DNS resolution for $s3Host"
        $dnsResult = [System.Net.Dns]::GetHostAddresses($s3Host)
        if ($dnsResult) {
            Write-Output "DNS resolution succeeded: $($dnsResult.IPAddressToString -join ', ')"
            Write-Debug "DNS resolved to: $($dnsResult.IPAddressToString -join ', ')"
        } else {
            Write-Output "DNS resolution failed: No addresses returned."
            Write-Debug "DNS resolution returned no addresses"
        }

        # Test 2: TCP connectivity to port 443
        Write-Output "Testing TCP connectivity to $s3Host on port $port..."
        Write-Debug "Creating TcpClient and attempting connection to ${s3Host}:${port}"
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        $tcpClient.Connect($s3Host, $port)
        if ($tcpClient.Connected) {
            Write-Output "TCP connection succeeded on port $port."
            Write-Debug "TCP connection established successfully"
            $tcpClient.Close()
            Write-Debug "TCP client closed"
        } else {
            Write-Output "TCP connection failed: Unable to connect."
            Write-Debug "TCP connection attempt failed"
        }

        # Test 3: Check available commands
        Write-Output "Checking available commands..."
        Write-Debug "Testing command availability"

        # Test Invoke-WebRequest
        $iwrAvailable = Get-Command -Name Invoke-WebRequest -ErrorAction SilentlyContinue
        Write-Output "Invoke-WebRequest available: $([bool]$iwrAvailable)"
        Write-Debug "Invoke-WebRequest check result: $([bool]$iwrAvailable)"

        # Test Invoke-RestMethod
        $irmAvailable = Get-Command -Name Invoke-RestMethod -ErrorAction SilentlyContinue
        Write-Output "Invoke-RestMethod available: $([bool]$irmAvailable)"
        Write-Debug "Invoke-RestMethod check result: $([bool]$irmAvailable)"

        # Test System.Net.WebClient (always available in .NET Framework)
        $netAvailable = $true  # WebClient is part of .NET since 1.1
        Write-Output "System.Net.WebClient available: True"
        Write-Debug "System.Net.WebClient check result: True"
        
        # Test 4: Test HTTP connectivity to the S3 URL
        Write-Output "Testing HTTP connectivity to $s3Url..."
        Write-Debug "Starting HTTP connectivity test for S3"

        if ($httpMethod -eq "irm" -or (-not $httpMethod -and $irmAvailable)) {
            if (-not $irmAvailable) { throw "Invoke-RestMethod is not available on this system." }
            if (-not $iwrAvailable) { throw "Invoke-WebRequest is required as a fallback for S3 binary content in PS 3.0." }
            Write-Output "Using Invoke-RestMethod (falling back to Invoke-WebRequest for S3 binary content)..."
            Write-Debug "Executing Invoke-WebRequest for $s3Url (irm not suitable for binary in PS 3.0)"
            $response = Invoke-WebRequest -Uri $s3Url -Method Get -UseBasicParsing
            Write-Output "HTTP test succeeded: Status Code $($response.StatusCode)"
            Write-Debug "Invoke-WebRequest succeeded with status $($response.StatusCode)"
        }
        elseif ($httpMethod -eq "iwr" -or (-not $httpMethod -and $iwrAvailable)) {
            if (-not $iwrAvailable) { throw "Invoke-WebRequest is not available on this system." }
            Write-Output "Using Invoke-WebRequest..."
            Write-Debug "Executing Invoke-WebRequest for $s3Url"
            $response = Invoke-WebRequest -Uri $s3Url -Method Get -UseBasicParsing
            Write-Output "HTTP test succeeded: Status Code $($response.StatusCode)"
            Write-Debug "Invoke-WebRequest succeeded with status $($response.StatusCode)"
        }
        elseif ($httpMethod -eq "net" -or (-not $httpMethod -and $netAvailable)) {
            Write-Output "Using System.Net.WebClient..."
            Write-Debug "Executing WebClient download for $s3Url"
            $webClient = New-Object System.Net.WebClient
            $tempFile = [IO.Path]::GetTempFileName()
            $webClient.DownloadFile($s3Url, $tempFile)
            Write-Output "HTTP test succeeded: File downloaded (assumed 200 OK)"
            Write-Debug "WebClient download completed to $tempFile"
        }
        else {
            Write-Output "No suitable method available to test HTTP connectivity."
            Write-Debug "No HTTP test method available or specified method not supported"
        }

        # Test 5: Test custom User-Agent with httpbin.org
        Write-Output "Testing custom User-Agent with $httpbinUrl..."
        Write-Debug "Starting User-Agent test with httpbin.org"

        if ($httpMethod -eq "irm" -or (-not $httpMethod -and $irmAvailable)) {
            if (-not $irmAvailable) { throw "Invoke-RestMethod is not available on this system." }
            Write-Output "Using Invoke-RestMethod for User-Agent test..."
            Write-Debug "Executing Invoke-RestMethod for $httpbinUrl with custom UA: $customUA"
            $response = Invoke-RestMethod -Uri $httpbinUrl -Method Get -Headers @{"User-Agent" = $customUA} -UseBasicParsing
            $receivedUA = $response.headers.'User-Agent'
            Write-Output "Sent User-Agent: $customUA"
            Write-Output "Received User-Agent: $receivedUA"
            Write-Debug "Invoke-RestMethod User-Agent test completed: Sent=$customUA, Received=$receivedUA"
        }
        elseif ($httpMethod -eq "iwr" -or (-not $httpMethod -and $iwrAvailable)) {
            if (-not $iwrAvailable) { throw "Invoke-WebRequest is not available on this system." }
            Write-Output "Using Invoke-WebRequest for User-Agent test..."
            Write-Debug "Executing Invoke-WebRequest for $httpbinUrl with custom UA: $customUA"
            $response = Invoke-WebRequest -Uri $httpbinUrl -Method Get -Headers @{"User-Agent" = $customUA} -UseBasicParsing
            $receivedUA = ($response.Content | ConvertFrom-Json).headers.'User-Agent'
            Write-Output "Sent User-Agent: $customUA"
            Write-Output "Received User-Agent: $receivedUA"
            Write-Debug "Invoke-WebRequest User-Agent test completed: Sent=$customUA, Received=$receivedUA"
        }
        elseif ($httpMethod -eq "net" -or (-not $httpMethod -and $netAvailable)) {
            Write-Output "Using System.Net.WebClient for User-Agent test..."
            Write-Debug "Executing WebClient download for $httpbinUrl with custom UA: $customUA"
            $webClient = New-Object System.Net.WebClient
            $webClient.Headers.Add("User-Agent", $customUA)
            $tempFile = [IO.Path]::GetTempFileName()
            $webClient.DownloadFile($httpbinUrl, $tempFile)
            $responseContent = Get-Content $tempFile -Raw | ConvertFrom-Json
            $receivedUA = $responseContent.headers.'User-Agent'
            Write-Output "Sent User-Agent: $customUA"
            Write-Output "Received User-Agent: $receivedUA"
            Write-Debug "WebClient User-Agent test completed: Sent=$customUA, Received=$receivedUA"
        }
        else {
            Write-Output "No suitable method available to test User-Agent."
            Write-Debug "No User-Agent test method available or specified method not supported"
        }
    }
    catch {
        $statusCode = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { "Unknown" }
        Write-Error "Error in PROCESS block: $($_.Exception.Message) - Status Code: $statusCode" -ErrorAction Stop
    }
}

end {
    try {
        Write-Debug "Starting cleanup in END block"

        # Clean up TCP client if it exists
        if ($tcpClient) {
            $tcpClient.Dispose()
            Write-Debug "Disposed of TcpClient"
        }

        # Clean up temporary file if created
        if ($tempFile -and (Test-Path $tempFile)) {
            Remove-Item $tempFile -Force
            Write-Debug "Removed temporary file: $tempFile"
        }

        # Clean up variables
        Remove-Variable -Name s3Host, s3Url, port, tcpClient, iwrAvailable, irmAvailable, netAvailable, tempFile, httpbinUrl, customUA -ErrorAction SilentlyContinue
        Write-Debug "Cleared variables"

        # Reset debug preference
        if ($debugOut) { $DebugPreference = "SilentlyContinue" }
        Write-Debug "Script execution completed"
    }
    catch {
        Write-Error "Error in END block: $($_.Exception.Message)" -ErrorAction Stop
    }
}