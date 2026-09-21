#Requires -Version 5.1
# Pester v5 unit tests for the N2C.GuacAdmin private helpers (no network).

# Dot-source the private helpers in BeforeAll so that they resolve inside the
# It blocks (Pester v5 runs the file body in a discovery-only scope, so the
# helpers and their paths must be established in the runtime scope).
BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    foreach ($scriptFile in 'ConvertTo-GuacServerUrl', 'ConvertTo-GuacFormUrlEncoded', 'ConvertTo-GuacMaskedSecret', 'ConvertFrom-GuacSecureString', 'ConvertTo-GuacJson', 'Get-GuacResponseDetails', 'ConvertFrom-GuacErrorBody') {
        . (Join-Path $moduleRoot ('Private/{0}.ps1' -f $scriptFile))
    }
}

Describe 'ConvertTo-GuacServerUrl' {
    It 'accepts a bare https URL' {
        ConvertTo-GuacServerUrl -Server 'https://guac.example.com' | Should -Be 'https://guac.example.com'
    }

    It 'preserves a context path and removes a trailing slash' {
        ConvertTo-GuacServerUrl -Server 'https://guac.example.com/guacamole/' | Should -Be 'https://guac.example.com/guacamole'
    }

    It 'accepts http' {
        ConvertTo-GuacServerUrl -Server 'http://127.0.0.1:8080/guacamole' | Should -Be 'http://127.0.0.1:8080/guacamole'
    }

    It 'rejects an empty value' {
        { ConvertTo-GuacServerUrl -Server '' } | Should -Throw
    }

    It 'rejects a relative value' {
        { ConvertTo-GuacServerUrl -Server 'guac.example.com/guacamole' } | Should -Throw
    }

    It 'rejects a non-http(s) scheme' {
        { ConvertTo-GuacServerUrl -Server 'ftp://guac.example.com' } | Should -Throw
    }
}

Describe 'ConvertTo-GuacRestUrl' {
    It 'joins base and path' {
        ConvertTo-GuacRestUrl -Server 'https://guac.example.com/guacamole/' -Path '/api/session' | Should -Be 'https://guac.example.com/guacamole/api/session'
    }

    It 'adds a leading slash when missing' {
        ConvertTo-GuacRestUrl -Server 'https://guac.example.com' -Path 'api/session' | Should -Be 'https://guac.example.com/api/session'
    }

    It 'preserves an existing query string' {
        ConvertTo-GuacRestUrl -Server 'https://guac.example.com' -Path '/api/x?contains=a&order=startDate' | Should -Be 'https://guac.example.com/api/x?contains=a&order=startDate'
    }
}

Describe 'ConvertTo-GuacFormUrlEncoded' {
    It 'encodes simple fields' {
        ConvertTo-GuacFormUrlEncoded -Fields ([ordered]@{ username = 'guacadmin'; password = 'secret' }) | Should -Be 'username=guacadmin&password=secret'
    }

    It 'percent-encodes special characters' {
        $encoded = ConvertTo-GuacFormUrlEncoded -Fields ([ordered]@{ password = 'p@ss w&rd/ç' })
        $decoded = [uri]::UnescapeDataString($encoded.Substring('password='.Length))
        $decoded | Should -Be 'p@ss w&rd/ç'
    }

    It 'skips null values (optional guac-totp)' {
        ConvertTo-GuacFormUrlEncoded -Fields ([ordered]@{ username = 'a'; password = 'b'; 'guac-totp' = $null }) | Should -Be 'username=a&password=b'
    }

    It 'includes guac-totp when present' {
        ConvertTo-GuacFormUrlEncoded -Fields ([ordered]@{ username = 'a'; password = 'b'; 'guac-totp' = '123456' }) | Should -Be 'username=a&password=b&guac-totp=123456'
    }
}

Describe 'ConvertTo-GuacMaskedSecret' {
    It 'masks empty values entirely' {
        ConvertTo-GuacMaskedSecret -Value '' | Should -Be '****'
    }

    It 'masks short values entirely' {
        ConvertTo-GuacMaskedSecret -Value 'secret8' | Should -Be '****'
    }

    It 'keeps the first and last 4 characters of long values' {
        ConvertTo-GuacMaskedSecret -Value 'averylongtokenvalue1234567890' | Should -Be 'aver...7890'
    }
}

Describe 'ConvertFrom-GuacSecureString' {
    It 'converts a SecureString to plaintext' {
        $secure = ConvertTo-SecureString 'topSecretValue' -AsPlainText -Force
        ConvertFrom-GuacSecureString -SecureString $secure | Should -Be 'topSecretValue'
    }
}

Describe 'ConvertTo-GuacJson' {
    It 'serializes a hashtable' {
        $json = ConvertTo-GuacJson -InputObject @{ name = 'x'; value = 1 }
        $parsed = $json | ConvertFrom-Json
        $parsed.name | Should -Be 'x'
        $parsed.value | Should -Be 1
    }

    It 'preserves a single-element array (5.1 unwrapping guard)' {
        $json = ConvertTo-GuacJson -InputObject (@([ordered]@{ op = 'add'; path = '/new' }))
        $json | Should -BeLike '[[?]*]'
        $parsed = $json | ConvertFrom-Json
        $parsed | Should -BeOfType [System.Management.Automation.PSObject]
        # Re-parse check: it must round-trip as an array with one element.
        $json | Should -Match '^\['
    }

    It 'serializes an empty array as []' {
        ConvertTo-GuacJson -InputObject @() | Should -Be '[]'
    }

    It 'passes strings through unchanged' {
        ConvertTo-GuacJson -InputObject 'plain text body' | Should -Be 'plain text body'
    }
}

Describe 'ConvertFrom-GuacErrorBody' {
    It 'parses an APIError JSON body' {
        $body = '{"message":"No such token.","type":"NOT_FOUND","statusCode":404}'
        $guacError = ConvertFrom-GuacErrorBody -Body $body
        $guacError.Type | Should -Be 'NOT_FOUND'
        $guacError.Message | Should -Be 'No such token.'
        $guacError.StatusCode | Should -Be 404
    }

    It 'returns $null fields for a body without them' {
        $guacError = ConvertFrom-GuacErrorBody -Body '{"message":"boom"}'
        $guacError.Type | Should -BeNullOrEmpty
        $guacError.Message | Should -Be 'boom'
    }

    It 'treats a non-JSON body as a plain message' {
        $guacError = ConvertFrom-GuacErrorBody -Body '<html>Internal Server Error</html>'
        $guacError.Type | Should -BeNullOrEmpty
        $guacError.Message | Should -Be '<html>Internal Server Error</html>'
    }

    It 'handles an empty body' {
        $guacError = ConvertFrom-GuacErrorBody -Body ''
        $guacError.Message | Should -BeNullOrEmpty
    }
}

Describe 'Get-GuacErrorCategory' {
    # Assert by category name: the returned values are genuine
    # [ErrorCategory] enum values (verified via .Equals in the probe), but
    # 'Should -Be' against a [type]::Member expression is unreliable in this
    # Pester/PowerShell combination for enum-typed pipeline input.
    It 'maps 0 (transport failure) to ConnectionError' {
        (Get-GuacErrorCategory -StatusCode 0).ToString() | Should -Be 'ConnectionError'
    }
    It 'maps 401 to SecurityError' {
        (Get-GuacErrorCategory -StatusCode 401).ToString() | Should -Be 'SecurityError'
    }
    It 'maps 403 to SecurityError' {
        (Get-GuacErrorCategory -StatusCode 403).ToString() | Should -Be 'SecurityError'
    }
    It 'maps 404 to InvalidArgument' {
        (Get-GuacErrorCategory -StatusCode 404).ToString() | Should -Be 'InvalidArgument'
    }
    It 'maps 429 (rate limited) to InvalidArgument' {
        (Get-GuacErrorCategory -StatusCode 429).ToString() | Should -Be 'InvalidArgument'
    }
    It 'maps 500 to ResourceUnavailable' {
        (Get-GuacErrorCategory -StatusCode 500).ToString() | Should -Be 'ResourceUnavailable'
    }
    It 'maps 503 to ResourceUnavailable' {
        (Get-GuacErrorCategory -StatusCode 503).ToString() | Should -Be 'ResourceUnavailable'
    }
}

Describe 'Get-GuacResponseHeaderValue' {
    It 'looks up headers case-insensitively' {
        $headers = [ordered]@{ 'Content-Type' = 'application/json' }
        Get-GuacResponseHeaderValue -Headers $headers -Name 'content-type' | Should -Be 'application/json'
    }

    It 'returns $null when the header is absent' {
        $headers = [ordered]@{ 'X-Other' = 'v' }
        Get-GuacResponseHeaderValue -Headers $headers -Name 'Content-Type' | Should -BeNullOrEmpty
    }

    It 'returns $null for null headers' {
        Get-GuacResponseHeaderValue -Headers $null -Name 'Content-Type' | Should -BeNullOrEmpty
    }
}
