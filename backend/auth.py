
import os

import jwt
from fastapi import Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jwt import PyJWKClient

AUTH0_DOMAIN = os.getenv("AUTH0_DOMAIN", "dev-f5owh2ro2yxx11yw.us.auth0.com")
AUTH0_API_AUDIENCE = os.getenv(
    "AUTH0_API_AUDIENCE",
    "https://swamphacks-api",
)

AUTH0_ISSUER = f"https://{AUTH0_DOMAIN}/"
security = HTTPBearer()

jwks_client = PyJWKClient(
    f"https://{AUTH0_DOMAIN}/.well-known/jwks.json"
)


def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(security),
):
    token = credentials.credentials

    try:
        signing_key = jwks_client.get_signing_key_from_jwt(token)

        payload = jwt.decode(
            token,
            signing_key.key,
            algorithms=["RS256"],
            audience=AUTH0_API_AUDIENCE,
            issuer=AUTH0_ISSUER,
        )

        subject = payload.get("sub")
        if not subject:
            raise HTTPException(
                status_code=401,
                detail="Token has no user identifier.",
            )

        return {"auth0_sub": subject}

    except jwt.PyJWTError as error:
        print(f"Token validation error: {error!r}")
        raise HTTPException(
            status_code=401,
            detail="Invalid or expired access token.",
        )
