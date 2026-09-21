# PSScriptAnalyzer settings for N2C.GuacAdmin.
#
# Policy: the full default ruleset is active. The ONLY deviations are the
# explicit ExcludeRules below, each with a documented rationale. Anything not
# listed here is a real finding and ./run-lint.ps1 fails on it (CI gate, Phase 5).
#
# NOTE: per-rule `Enable = $false` inside a `Rules` hashtable is NOT honored for
# default rules by PSScriptAnalyzer 1.24.0 (verified empirically); `ExcludeRules`
# is the supported mechanism and is what this file uses.
@{
    # No blanket exclusions; only the deliberately-documented ones below.
    ExcludeRules = @(

        # Defensive transport helpers deliberately swallow "no usable X"
        # exceptions and keep walking the exception chain / try the next
        # source (Private/Get-GuacResponseDetails.ps1); the catches are part of
        # the fallback logic, not error suppression.
        'PSAvoidUsingEmptyCatchBlock'

        # Module-internal state bookkeeping (Private/Get-GuacSessionState.ps1)
        # and the test mock lifecycle (Tests/GuacTestHelpers.psm1) are not
        # user-facing mutations. ShouldProcess is honored at the public cmdlet
        # boundary (New/Remove-GuacSession carry SupportsShouldProcess; Remove
        # additionally has ConfirmImpact = 'High').
        'PSUseShouldProcessForStateChangingFunctions'

        # The transport name (Invoke-GuacRest) intentionally keeps the REST
        # acronym: module nouns are Guac* and "GuacRest" reads as a single
        # transport concept, mirroring the Guacamole REST API surface.
        'PSUseSingularNouns'

        # Plaintext SecureStrings exist ONLY in the Pester test files, where
        # test credentials are constructed for the local mock server. The
        # module's public surface accepts SecureString/PSCredential only.
        'PSAvoidUsingConvertToSecureStringWithPlainText'

        # Test files are executed by pwsh (UTF-8) in CI; one test fixture
        # contains a non-ASCII character to exercise multi-byte percent
        # encoding.
        'PSUseBOMForUnicodeEncodedFile'
    )
}
