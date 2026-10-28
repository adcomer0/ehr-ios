"""Developer-owned platform capabilities, explicitly covered by its own profile."""
SIGN_IN={"com.apple.developer.applesignin":["Default"],"com.apple.developer.game-center":True}

def platform_signin_capabilities(profile_entitlements,enabled):
    if not enabled:return {}
    for key,expected in SIGN_IN.items():
        if profile_entitlements.get(key)!=expected:
            raise ValueError("Selected profile does not cover requested platform capability: "+key)
    return {key:list(value) if isinstance(value,list) else value for key,value in SIGN_IN.items()}

def verify_platform_capabilities(signed,profile):
    for key,expected in SIGN_IN.items():
        if key in signed and (signed[key]!=expected or profile.get(key)!=expected):
            raise ValueError("Signed platform capability is not covered by this profile: "+key)
    return all(signed.get(key)==expected for key,expected in SIGN_IN.items())
