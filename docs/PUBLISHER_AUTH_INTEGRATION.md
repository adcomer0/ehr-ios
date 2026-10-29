# Publisher coordination for Apple / EOS authentication

A device observation reached a genuine Apple authorization callback followed
by normal EOS Connect result **7000**, named
`EOS_Connect_ExternalTokenValidationFailed`. This establishes external-token
validation failure, not its specific cause. Epic lists provider-configuration
failure separately as 7007. No token contents, credentials or account data were
inspected. [Epic SDK error codes](https://dev.epicgames.com/docs/epic-online-services/sdk-error-codes?lang=zh-CN)

The separate launcher's own Apple capability/profile has been checked. Local
signing success does not establish backend acceptance. Apple requires identity
token audience validation against the developer's client ID, alongside its
other verification checks. A changed app identity therefore needs an accepted
provider/client configuration; whether that mismatch caused this 7000 remains
unconfirmed. [Apple: verifying a user](https://developer.apple.com/documentation/signinwithapple/verifying-a-user)

The publisher's authorized EOS administrator should confirm the intended product,
sandbox/deployment, external Apple provider configuration and accepted client
identity for the proposed distribution. Epic requires external providers to be
configured in the product's Developer Portal. This is a general EOS requirement;
this Unity launcher does not use Unreal's OSS plugin. [Epic: external-account configuration](https://dev.epicgames.com/documentation/en-us/unreal-engine/online-subsystem-eos-plugin-in-unreal-engine#loginflowwithexternalaccountcredentials)

A concrete integration handoff needs the supported distribution/signing identity,
intended backend environment and documented public-client initialization flow.
Clarify the issuer and purpose of any proposed “OSS key”; the term alone does
not define an EOS integration contract. Private keys and credentials stay out of
the repository. Any publisher configuration change and authorized test should be
performed by its owner, with a non-sensitive outcome/correlation report rather
than credentials in launcher diagnostics.

Use a separate authorized test identity for verification and retain native
permission, consent, account and error handling. An unrelated EOS product has
its own player identities and does not establish compatibility with the game's
existing service. [Epic: Connect identity model](https://dev.epicgames.com/docs/epic-online-services/eos-fundamentals/connect-interface/connect-guide/log-in-with-an-epic-games-account)

The disabled retry guard only aims to surface an existing native failure once
instead of immediately requesting another Apple authorization. It neither fixes
7000 nor grants authenticated account state. A working online session and this
platform-login failure must be evaluated independently.
