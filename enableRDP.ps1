#Requires -Version 2.0
param (
    [bool]$debugOut = $false,   # Set to $true to enable debug output by default
    [bool]$uninstall = $false,  # Set to $true to run in uninstall mode by default
    [bool]$checkState = $false  # Set to $true to check and report RDP state without changes
)

begin {
    try {
        # Set debug preference to Continue if debugOut is enabled, so Write-Debug outputs to stdout
        if ($debugOut) { $DebugPreference = "Continue" }

        # Define variables
        $rdpServiceName = "TermService"
        $tempAdminUser = "TempRDPAdmin"
        $tempAdminPass = "TempP@ssw0rd123!"  # Change this to a secure password in production
        $regPath = "HKLM:\System\CurrentControlSet\Control\Terminal Server"
        $regName = "fDenyTSConnections"

        # Validate that checkState and uninstall are not both true
        if ($checkState -and $uninstall) {
            Write-Error "Cannot run with both -checkState and -uninstall set to true. Please choose one mode." -ErrorAction Stop
        }

        # Function to check and manage RDP firewall rules state
        function Get-RDPFirewallState {
            param (
                [switch]$DebugMode
            )
            # Create COM object for firewall policy
            $fw = New-Object -ComObject HNetCfg.FwPolicy2
            # Get rules where LocalPorts is 3389 (RDP rules)
            $script:rdpFirewallRules = $fw.Rules | Where-Object { "3389" -eq $_.LocalPorts }

            if (-not $script:rdpFirewallRules) {
                if ($DebugMode) { Write-Debug "No firewall rules found for port 3389." }
                return "Not Found"
            }

            $enabledCount = 0
            $disabledCount = 0

            foreach ($rule in $script:rdpFirewallRules) {
                if ($DebugMode) { Write-Debug "Checking firewall rule: $($rule.Name)" }
                if ($rule.Enabled) {
                    $enabledCount++
                    if ($DebugMode) { Write-Debug "$($rule.Name) is enabled" }
                }
                else {
                    $disabledCount++
                    if ($DebugMode) { Write-Debug "$($rule.Name) is disabled" }
                }
            }

            if ($enabledCount -eq $script:rdpFirewallRules.Count -and $disabledCount -eq 0) {
                return "Enabled"
            }
            elseif ($disabledCount -eq $script:rdpFirewallRules.Count -and $enabledCount -eq 0) {
                return "Disabled"
            }
            else {
                return "Mixed (Enabled: $enabledCount, Disabled: $disabledCount)"
            }
        }

        # Write initial debug message
        Write-Debug "Starting script in BEGIN block. Debug mode: $debugOut, Uninstall mode: $uninstall, CheckState mode: $checkState"

        # No external dependencies to load, keeping it compatible with PS 2.0
    }
    catch {
        Write-Error "Error in BEGIN block: $_" -ErrorAction Stop
    }
}

process {
    try {
        if ($checkState) {
            # CheckState mode: Report current RDP states without changes
            Write-Debug "Running in CheckState mode..."

            # Check 1: Are RDP firewall rules enabled?
            Write-Debug "Checking Remote Desktop firewall rules state..."
            $firewallState = Get-RDPFirewallState -DebugMode:$debugOut
            Write-Output "RDP Firewall Rules: $firewallState"

            # Check 2: Is RDP configured to allow incoming connections?
            Write-Debug "Checking RDP registry configuration..."
            $currentRegValue = (Get-ItemProperty -Path $regPath -Name $regName -ErrorAction SilentlyContinue).$regName
            if ($currentRegValue -eq 0) {
                Write-Output "RDP Connections: Allowed"
            } else {
                Write-Output "RDP Connections: Denied"
            }

            # Check 3: Is RDP service running?
            Write-Debug "Checking RDP service state..."
            $serviceStatus = (Get-Service -Name $rdpServiceName).Status
            if ($serviceStatus -eq "Running") {
                Write-Output "RDP Service: Running"
            } else {
                Write-Output "RDP Service: Not Running (Status: $serviceStatus)"
            }

            # Check 4: Is port 3389 listening?
            Write-Debug "Checking if port 3389 is listening..."
            $portCheck = netstat -an | Select-String "3389.*LISTENING"
            if ($portCheck) {
                Write-Output "Port 3389: Listening"
            } else {
                Write-Output "Port 3389: Not Listening"
            }

            Write-Debug "CheckState mode completed."
        }
        elseif (-not $uninstall) {
            # Install mode: Enable RDP and create user
            Write-Debug "Running in install mode..."

            # Step 1: Check and enable Remote Desktop firewall rules
            Write-Debug "Checking and enabling Remote Desktop firewall rules..."
            $firewallState = Get-RDPFirewallState -DebugMode:$debugOut
            if ($firewallState -ne "Enabled") {
                foreach ($rule in $script:rdpFirewallRules) {
                    if (-not $rule.Enabled) {
                        $rule.Enabled = $true
                        Write-Debug "Enabled rule: $($rule.Name)"
                    }
                }
                Write-Debug "Enabled Remote Desktop firewall rules."
            } else {
                Write-Debug "Remote Desktop firewall rules already enabled."
            }

            # Step 2: Enable RDP connections in registry
            Write-Debug "Enabling RDP connections in registry..."
            $currentRegValue = (Get-ItemProperty -Path $regPath -Name $regName -ErrorAction SilentlyContinue).$regName
            if ($currentRegValue -ne 0) {
                Set-ItemProperty -Path $regPath -Name $regName -Value 0
                Write-Debug "RDP connections enabled in registry."
            } else {
                Write-Debug "RDP connections already enabled in registry."
            }

            # Step 3: Enable and start RDP service
            Write-Debug "Checking and starting RDP service..."
            $service = Get-Service -Name $rdpServiceName
            if ($service.StartType -eq "Disabled") {
                Set-Service -Name $rdpServiceName -StartupType Automatic
                Write-Debug "Set RDP service startup type to Automatic."
            }
            if ($service.Status -ne "Running") {
                Start-Service -Name $rdpServiceName
                Write-Debug "Started RDP service."
            } else {
                Write-Debug "RDP service already running."
            }

            # Step 4: Verify port 3389 is listening with retry loop
            Write-Debug "Verifying port 3389 is listening with retry..."
            $retryCount = 0
            $portListening = $false
            while (-not $portListening -and $retryCount -lt 10) {
                Start-Sleep -Seconds 1
                $portCheck = netstat -an | Select-String "3389.*LISTENING"
                if ($portCheck) {
                    $portListening = $true
                    Write-Debug "Port 3389 is listening after ${retryCount} seconds."
                }
                $retryCount++
                if ($debugOut) { Write-Debug "Retry ${retryCount}: Port 3389 listening = $portListening" }
            }
            if (-not $portListening) {
                Write-Error "Port 3389 failed to start listening after 10 seconds." -ErrorAction Stop
            }

            # Step 5: Verify RDP service is running
            Write-Debug "Verifying RDP service status..."
            $serviceStatus = (Get-Service -Name $rdpServiceName).Status
            if ($serviceStatus -ne "Running") {
                Write-Error "RDP service is not running." -ErrorAction Stop
            }
            Write-Debug "RDP service is running."

            # Step 6: Create temp admin user and add to groups
            Write-Debug "Creating temp admin user and assigning to groups..."
            $userExists = Get-WmiObject -Class Win32_UserAccount -Filter "Name='$tempAdminUser' and LocalAccount='True'"
            if (-not $userExists) {
                net user $tempAdminUser $tempAdminPass /add /fullname:"Temp RDP Admin" /comment:"Temporary RDP admin" /expires:never /Y
                if ($LASTEXITCODE -ne 0) {
                    Write-Error "Failed to create user $tempAdminUser with net user." -ErrorAction Stop
                }
                Add-LocalGroupMember -Group "Administrators" -Member $tempAdminUser -ErrorAction Stop
                Add-LocalGroupMember -Group "Remote Desktop Users" -Member $tempAdminUser -ErrorAction Stop
                Write-Debug "Created $tempAdminUser and added to Administrators and Remote Desktop Users groups."
            } else {
                Write-Debug "User $tempAdminUser already exists."
            }

            # Get local IP address (IPv4 only)
            Write-Debug "Retrieving local IP address..."
            $ipAddress = (Get-WmiObject -Class Win32_NetworkAdapterConfiguration -Filter "IPEnabled = 'True'").IPAddress | Where-Object { $_ -match "\d+\.\d+\.\d+\.\d+" } | Select-Object -First 1

            # Return success message
            Write-Output "Success! RDP is enabled."
            Write-Output "Local IP Address: $ipAddress"
            Write-Output "Temp Admin Username: $tempAdminUser"
            Write-Output "Temp Admin Password: $tempAdminPass"
        }
        else {
            # Uninstall mode: Reverse the changes (except user removal)
            Write-Debug "Running in uninstall mode..."

            # Step 1: Disable Remote Desktop firewall rules
            Write-Debug "Disabling Remote Desktop firewall rules..."
            $firewallState = Get-RDPFirewallState -DebugMode:$debugOut
            if ($firewallState -ne "Disabled") {
                foreach ($rule in $script:rdpFirewallRules) {
                    if ($rule.Enabled) {
                        $rule.Enabled = $false
                        Write-Debug "Disabled rule: $($rule.Name)"
                    }
                }
                Write-Debug "Disabled Remote Desktop firewall rules."
            } else {
                Write-Debug "Remote Desktop firewall rules already disabled."
            }

            # Step 2: Disable RDP connections in registry
            Write-Debug "Disabling RDP connections in registry..."
            Set-ItemProperty -Path $regPath -Name $regName -Value 1
            Write-Debug "RDP connections disabled in registry."

            # Step 3: Stop and disable RDP service
            Write-Debug "Stopping and disabling RDP service..."
            Stop-Service -Name $rdpServiceName -Force
            Set-Service -Name $rdpServiceName -StartupType Disabled
            Write-Debug "Stopped and disabled RDP service."

            Write-Output "Uninstall complete. RDP disabled (temp admin user not removed)."
        }
    }
    catch {
        Write-Error "Error in PROCESS block: $_" -ErrorAction Stop
    }
}

end {
    try {
        # Clean up variables
        Write-Debug "Cleaning up in END block..."
        Remove-Variable -Name rdpServiceName, tempAdminUser, tempAdminPass, regPath, regName, rdpFirewallRules -ErrorAction SilentlyContinue

        # Reset debug preference to default
        if ($debugOut) { $DebugPreference = "SilentlyContinue" }

        # No temp files to clean up in this script
        Write-Debug "Script completed."
    }
    catch {
        Write-Error "Error in END block: $_" -ErrorAction Stop
    }
}