if (Get-Module -Name WebAutomation) { Remove-Module WebAutomation }
Import-Module .\WebAutomation.psm1

Describe "Add-AutoCurl" {
    BeforeEach {
        $TD = 'TestDrive:'
        Clear-TempAutoData -DataDir $TD
        if (Test-Path -Path "$TD\curls.dat") { Remove-Item -Path "$TD\curls.dat" }
    }
    It "adds a command to temporary storage" {
        Add-AutoCurl -Action 'A' -Command 'C' -DataDir $TD | Out-Null
        (Get-AutoCurl -Action 'A' -DataDir $TD).Values | Should -Be 'C'
    }
    It "raises errors with duplicate records" {
        Add-AutoCurl -Action 'A' -Command 'C1' -DataDir $TD | Out-Null
        { Add-AutoCurl -Action 'A' -Command 'C2' -DataDir $TD } |
            Should -Throw 'A command for A is already defined.'
    }
    It "adds a command to permanent storage" {
        Add-AutoCurl -Action 'A' -Command 'C' -Permanent -DataDir $TD
        "$TD\curls.dat" | Should -FileContentMatch 'A = C'
    }
}

Describe "Invoke-AutoRequest" {
    BeforeEach {
        $TD = 'TestDrive:'
        Clear-TempAutoData -DataDir $TD
    }
    It "can curl something without data or authentication" {
        'curl "http://httpbin.org/get" -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:67.0) Gecko/20100101 Firefox/67.0" -H "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8" -H "Accept-Language: en-US,en;q=0.5" --compressed -H "DNT: 1" -H "Connection: keep-alive" -H "Cookie: freeform=jkhgkjuhglikuh" -H "Upgrade-Insecure-Requests: 1"' | Add-AutoCurl -Action 'httpbin-echo'
        (Invoke-AutoRequest -Action 'httpbin-echo').Body -join '' | Should -BeLike '*"args": {}*'
    }
    It "can curl something with data but no authentication" {
        'curl "http://httpbin.org/post" -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:67.0) Gecko/20100101 Firefox/67.0" -H "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8" -H "Accept-Language: en-US,en;q=0.5" --compressed -H "DNT: 1" -H "Connection: keep-alive" -H "Upgrade-Insecure-Requests: 1" -H "Cache-Control: max-age=0, no-cache" -H "Pragma: no-cache" --data "key=value"' | Add-AutoCurl -Action 'httpbin-testpost'
        (@{key='newvalue'} | Invoke-AutoRequest -Action 'httpbin-testpost').Body -join '' |
            Should -BeLike '*"key": "newvalue"*'
    }
    It "can access pages behind NTLM authentication" {
        'curl "https://accessnet.coh.org/Main/request_owner_approval.aspx" -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:67.0) Gecko/20100101 Firefox/67.0" -H "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8" -H "Accept-Language: en-US,en;q=0.5" --compressed -H "DNT: 1" -H "Connection: keep-alive" -H "Referer: https://accessnet.coh.org/Main/request_owner_approval.aspx" -H "Cookie: ASP.NET_SessionId=lwm0xplzuvi3ewbhu3hdczbl; p-hcmapp2-6200-PORTAL-PSJSESSIONID=eC-Q78rXdXA8pVaueh-9hUHhq67v8GKy!1698952002; PS_LOGINLIST=-1; PS_TOKENEXPIRE=-1; SignOnDefault=" -H "Upgrade-Insecure-Requests: 1" -H "Authorization: NTLM TlRMTVNTUAADAAAAGAAYAHoAAABIAUgBkgAAAAAAAABYAAAAFAAUAFgAAAAOAA4AbAAAAAAAAADaAQAABYKIogoAqz8AAAAPjJhwO6H+qw0H8Oh7VI98WGEAcABhAG4AYQBzAGUAbgBjAG8AQgBSADEAMwA0ADUANQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABCDOgTbMuGfuLorofHb2mDAQEAAAAAAACb0gdX3ivVAcp7oknN9SlgAAAAAAIADABDAE8ASABCAFIASQABABwAVgBNAFAALQBXAEUAQgBBAFAAUABTADYANABBAAQADgBjAG8AaAAuAG8AcgBnAAMALAB2AG0AcAAtAHcAZQBiAGEAcABwAHMANgA0AGEALgBjAG8AaAAuAG8AcgBnAAUADgBjAG8AaAAuAG8AcgBnAAcACACb0gdX3ivVAQYABAACAAAACAAwADAAAAAAAAAAAQAAAAAgAAABxFjY55YCHNHauSjXWJ8nyLn8x1Etc6z+GfZlJmyFjgoAEABMcGlIABBmbD9uP6/p9nQ7CQAsAEgAVABUAFAALwBhAGMAYwBlAHMAcwBuAGUAdAAuAGMAbwBoAC4AbwByAGcAAAAAAAAAAAAAAAAA"' | Add-AutoCurl -Action 'AN-Owner'
        (Add-Credentials -Site 'AccessNet' | Invoke-AutoRequest -Action 'AN-Owner' -Ntlm).Body -join '' |
            Should -BeLike '*Owner Approval Queue*'
    }
}
