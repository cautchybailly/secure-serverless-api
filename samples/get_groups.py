"""Excerpt: RBAC group parsing. API Gateway flattens cognito:groups into one string;
substring matching on it is a privilege-escalation bug waiting to happen."""


def get_groups(event):
    """Read cognito:groups off the authorizer claims.

    API Gateway flattens the JWT's group array into a single string before it
    reaches Lambda - "[admins students]", not ["admins", "students"]. Testing
    membership against that string with `in` is substring matching, so a group
    named "admins-readonly" would satisfy a check for "admins".
    """
    claims = event.get("requestContext", {}).get("authorizer", {}).get("claims", {})
    raw = claims.get("cognito:groups", [])

    if isinstance(raw, str):
        raw = raw.strip("[]").replace(",", " ").split()

    return [group for group in raw if group]
