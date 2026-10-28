"""Explicit local signing identity checks; no developer-specific defaults."""
from __future__ import annotations
import re


def validate_identity(team_id: str, bundle_id: str, team_name: str | None = None):
    if not isinstance(team_id, str) or not re.fullmatch(r"[A-Z0-9]{10}", team_id):
        raise ValueError("An explicit ten-character Apple development team ID is required")
    if (not isinstance(bundle_id, str)
            or not re.fullmatch(r"[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+", bundle_id)
            or len(bundle_id) > 230):
        raise ValueError("An explicit own reverse-DNS bundle identifier is required")
    if bundle_id.casefold() == "com.innersloth.amongus":
        raise ValueError("The official game identifier must never be used for this separate app")
    if team_name is not None and (not isinstance(team_name, str) or not team_name.strip()):
        raise ValueError("An explicit team-name assertion must not be empty")
    return team_id, bundle_id, team_name
