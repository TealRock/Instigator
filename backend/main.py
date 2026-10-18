from fastapi import FastAPI, HTTPException, Depends

from database import get_connection
from auth import get_current_user
from typing import Literal
from pydantic import BaseModel
from uuid import UUID
import httpx
from icalendar import Calendar
from urllib.parse import urlparse

from datetime import datetime, timezone
from psycopg.types.json import Jsonb
from psycopg.rows import dict_row

class ProfileRequest(BaseModel):
    username: str
    display_name: str

class CanvasImportRequest(BaseModel):
    calendar_url: str

class CommitmentCreate(BaseModel):
    title: str
    description: str | None = None
    assignment_id: str | None = None
    commitment_type: Literal[
        "assignment", "study", "test_prep", "event", "other"
    ] = "study"
    starts_at: datetime | None = None
    ends_at: datetime | None = None

def validate_canvas_url(calendar_url: str) -> str:
    parsed = urlparse(calendar_url)

    if parsed.scheme != "https":
        raise HTTPException(
            status_code=400,
            detail="Canvas calendar URLs must use HTTPS.",
        )

    if not parsed.hostname or parsed.username or parsed.password:
        raise HTTPException(
            status_code=400,
            detail="Invalid Canvas calendar URL.",
        )

    if parsed.port not in (None, 443):
        raise HTTPException(
            status_code=400,
            detail="Invalid port in calendar URL.",
        )

    return calendar_url

def parse_canvas_calendar(calendar_data: bytes) -> list[dict]:
    try:
        calendar = Calendar.from_ical(calendar_data)
    except Exception as error:
        raise HTTPException(
            status_code=400,
            detail="Could not parse the calendar file.",
        ) from error

    assignments = []

    for component in calendar.walk():
        if component.name != "VEVENT":
            continue

        title = str(component.get("SUMMARY", "")).strip()
        if not title:
            continue

        def get_datetime(property_name: str):
            prop = component.get(property_name)
            if prop is None:
                return None

            value = prop.dt

            if not isinstance(value, datetime):
                value = datetime.combine(value, datetime.min.time())

            if value.tzinfo is None:
                value = value.replace(tzinfo=timezone.utc)

            return value.isoformat()

        def get_text(property_name: str):
            prop = component.get(property_name)
            return str(prop).strip() if prop is not None else None

        # Preserve all original event properties in a JSON-compatible form.
        raw_event = {}

        for key, value in component.items():
            try:
                raw_event[str(key)] = value.to_ical().decode(
                    "utf-8",
                    errors="replace",
                )
            except Exception:
                raw_event[str(key)] = str(value)

        assignments.append({
            "title": title,
            "description": get_text("DESCRIPTION"),
            "course": None,
            "course_name": None,
            "start_at": get_datetime("DTSTART"),
            "due_at": get_datetime("DUE") or get_datetime("DTEND"),
            "location": get_text("LOCATION"),
            "event_url": get_text("URL"),
            "raw_event": raw_event,
        })

    return assignments

app = FastAPI(title="swamphacks API")

@app.get("/")
def health_check():
    return {"status": "ok", "message": "backend is running"}

@app.get("/db-check")
def database_check():
    try:
        with get_connection() as connection:
            with connection.cursor() as cursor:
                cursor.execute("SELECT current_database()")
                database_name = cursor.fetchone()[0]

        return {
            "status": "ok",
            "database": database_name
        }
    except Exception as error:
        print(f"Database connection error: {error!r}")
        raise HTTPException(
            status_code=500,
            detail="Database connection failed. Check the backend terminal."
        )

@app.get("/tables-check")
def tables_check():
    try:
        with get_connection() as connection:
            with connection.cursor() as cursor:
                cursor.execute("""
                    SELECT table_name
                    FROM information_schema.tables
                    WHERE table_schema = 'public'
                    ORDER BY table_name
                """)
                tables = [row[0] for row in cursor.fetchall()]

        return {"tables": tables}

    except Exception as error:
        print(f"Table check error: {error!r}")
        raise HTTPException(
            status_code=500,
            detail="Could not retrieve database tables.",
        )

@app.get("/auth-check")
def auth_check(current_user: dict = Depends(get_current_user)):
    return {
        "status": "authenticated",
        "auth0_sub": current_user["auth0_sub"],
    }

@app.post("/profile")
def create_or_get_profile(
    profile: ProfileRequest,
    current_user: dict = Depends(get_current_user),
):
    try:
        with get_connection() as connection:
            with connection.cursor() as cursor:
                cursor.execute(
                    """
                    INSERT INTO users (
                        auth0_sub,
                        username,
                        display_name
                    )
                    VALUES (%s, %s, %s)
                    ON CONFLICT (auth0_sub)
                    DO UPDATE SET auth0_sub = EXCLUDED.auth0_sub
                    RETURNING id, username, display_name, created_at
                    """,
                    (
                        current_user["auth0_sub"],
                        profile.username,
                        profile.display_name,
                    ),
                )

                user = cursor.fetchone()

            return {
                "id": str(user[0]),
                "username": user[1],
                "display_name": user[2],
                "created_at": user[3].isoformat(),
            }
    except Exception as error:
        print(f"Profile creating error: {error!r}")
        raise HTTPException(
            status_code=500,
            detail="Could not create or retrive profile.",
        )


@app.get("/profile/me")
def get_my_profile(
    current_user: dict = Depends(get_current_user),
):
    try:
        with get_connection() as connection:
            with connection.cursor() as cursor:
                cursor.execute(
                    """
                    SELECT id, username, display_name, completed_commitments, created_at
                    FROM users
                    WHERE auth0_sub = %s
                    """,
                    (current_user["auth0_sub"],),
                )
                user = cursor.fetchone()

        if user is None:
            return {"profile_exists": False}

        return {
            "profile_exists": True,
            "id": str(user[0]),
            "username": user[1],
            "display_name": user[2],
            "completed_commitments": user[3],
            "created_at": user[4].isoformat() if user[4] else None,
        }

    except Exception as error:
        print(f"Profile lookup error: {error!r}")
        raise HTTPException(
            status_code=500,
            detail="Could not retrieve profile.",
        )


@app.post("/assignments/canvas/preview")
async def preview_canvas_import(
    request: CanvasImportRequest,
    current_user: dict = Depends(get_current_user),
):
    calendar_url = validate_canvas_url(request.calendar_url)

    try:
        async with httpx.AsyncClient(
            timeout=15.0,
            follow_redirects=False,
        ) as client:
            response = await client.get(calendar_url)
            response.raise_for_status()
    except httpx.HTTPError as error:
        raise HTTPException(
            status_code=400,
            detail="Could not download the Canvas calendar. Check the URL and try again.",
        ) from error

    assignments = parse_canvas_calendar(response.content)

    return {
        "count": len(assignments),
        "assignments": assignments,
    }

@app.post("/assignments/canvas/import")
async def import_canvas_calendar(
    request: CanvasImportRequest,
    current_user: dict = Depends(get_current_user),
):
    calendar_url = validate_canvas_url(request.calendar_url)

    # Download and parse the complete calendar before changing the database.
    try:
        async with httpx.AsyncClient(
            timeout=20.0,
            follow_redirects=False,
        ) as client:
            response = await client.get(calendar_url)
            response.raise_for_status()
    except httpx.HTTPError as error:
        raise HTTPException(
            status_code=400,
            detail="Could not download the Canvas calendar.",
        ) from error

    assignments = parse_canvas_calendar(response.content)

    if not assignments:
        raise HTTPException(
            status_code=400,
            detail="The calendar contains no importable events. Existing assignments were not changed.",
        )

    try:
        with get_connection() as connection:
            with connection.cursor() as cursor:
                cursor.execute(
                    """
                    DELETE FROM assignments
                    WHERE user_id = (
                        SELECT id FROM users WHERE auth0_sub = %s
                    )
                    AND source = 'canvas'
                    """,
                    (current_user["auth0_sub"],),
                )

                for assignment in assignments:
                    cursor.execute(
                        """
                        INSERT INTO assignments (
                            user_id,
                            title,
                            description,
                            course,
                            course_name,
                            start_at,
                            due_at,
                            location,
                            event_url,
                            source,
                            raw_event
                        )
                        SELECT
                            id,
                            %s, %s, %s, %s, %s, %s, %s, %s,
                            'canvas',
                            %s
                        FROM users
                        WHERE auth0_sub = %s
                        """,
                        (
                            assignment["title"],
                            assignment["description"],
                            assignment["course"],
                            assignment["course_name"],
                            assignment["start_at"],
                            assignment["due_at"],
                            assignment["location"],
                            assignment["event_url"],
                            Jsonb(assignment["raw_event"]),
                            current_user["auth0_sub"],
                        ),
                    )

        return {
            "imported_count": len(assignments),
            "message": "Canvas calendar imported successfully.",
        }

    except Exception as error:
        print(f"Canvas import error: {error!r}")
        raise HTTPException(
            status_code=500,
            detail="Could not save the Canvas calendar.",
        ) from error

@app.get("/assignments")
def get_assignments(
    current_user: dict = Depends(get_current_user),
):
    try:
        with get_connection() as connection:
            with connection.cursor() as cursor:
                cursor.execute(
                    """
                    SELECT
                        a.id,
                        a.title,
                        a.description,
                        a.course,
                        a.course_name,
                        a.start_at,
                        a.due_at,
                        a.location,
                        a.event_url,
                        a.source
                    FROM assignments AS a
                    JOIN users AS u ON u.id = a.user_id
                    WHERE u.auth0_sub = %s
                    ORDER BY
                        a.due_at ASC NULLS LAST,
                        a.title ASC
                    """,
                    (current_user["auth0_sub"],),
                )

                rows = cursor.fetchall()
                columns = [
                    column.name
                    for column in cursor.description
                ]

        assignments = [
            {
                key: value.isoformat()
                if isinstance(value, datetime)
                else str(value)
                if key == "id" and value is not None
                else value
                for key, value in zip(columns, row)
            }
            for row in rows
        ]

        return {
            "count": len(assignments),
            "assignments": assignments,
        }

    except Exception as error:
        print(f"Assignment retrieval error: {error!r}")
        raise HTTPException(
            status_code=500,
            detail="Could not retrieve assignments.",
        ) from error

@app.get("/users/search")
def search_users(
    q: str,
    current_user: dict = Depends(get_current_user),
):
    query = q.strip()

    if len(query) < 2:
        raise HTTPException(
            status_code=400,
            detail="Search query must contain at least 2 characters.",
        )

    try:
        with get_connection() as connection:
            with connection.cursor() as cursor:
                cursor.execute(
                    """
                    SELECT
                        u.id,
                        u.username,
                        u.display_name
                    FROM users u
                    WHERE (
                        u.username ILIKE %s
                        OR u.display_name ILIKE %s
                    )
                    AND u.auth0_sub != %s
                    AND NOT EXISTS (
                        SELECT 1
                        FROM friendships f
                        WHERE (
                            f.requester_id = (
                                SELECT id FROM users WHERE auth0_sub = %s
                            )
                            AND f.recipient_id = u.id
                        )
                        OR (
                            f.recipient_id = (
                                SELECT id FROM users WHERE auth0_sub = %s
                            )
                            AND f.requester_id = u.id
                        )
                    )
                    ORDER BY u.username
                    LIMIT 20;
                    """,
                    (
                        (
                            f"%{q}%",
                            f"%{q}%",
                            current_user["auth0_sub"],
                            current_user["auth0_sub"],
                            current_user["auth0_sub"],
                        )
                    ),
                )

                rows = cursor.fetchall()
                columns = [
                    column.name
                    for column in cursor.description
                ]

        users = [
            {
                key: str(value) if key == "id" else value
                for key, value in zip(columns, row)
            }
            for row in rows
        ]

        return {
            "count": len(users),
            "users": users,
        }

    except Exception as error:
        print(f"User search error: {error!r}")
        raise HTTPException(
            status_code=500,
            detail="Could not search users.",
        ) from error

@app.post("/friends/request/{recipient_id}")
def send_friend_request(
    recipient_id: str,
    current_user: dict = Depends(get_current_user),
):
    try:
        with get_connection() as connection:
            with connection.cursor() as cursor:
                cursor.execute(
                    """
                    SELECT id
                    FROM users
                    WHERE auth0_sub = %s
                    """,
                    (current_user["auth0_sub"],),
                )
                sender = cursor.fetchone()

                if sender is None:
                    raise HTTPException(
                        status_code=404,
                        detail="Your profile was not found.",
                    )

                sender_id = sender[0]

                if str(sender_id) == recipient_id:
                    raise HTTPException(
                        status_code=400,
                        detail="You cannot send a friend request to yourself.",
                    )

                cursor.execute(
                    """
                    SELECT id
                    FROM users
                    WHERE id = %s
                    """,
                    (recipient_id,),
                )
                recipient = cursor.fetchone()

                if recipient is None:
                    raise HTTPException(
                        status_code=404,
                        detail="Recipient not found.",
                    )

                cursor.execute(
                    """
                    SELECT status
                    FROM friendships
                    WHERE
                        (requester_id = %s AND recipient_id = %s)
                        OR
                        (requester_id = %s AND recipient_id = %s)
                    """,
                    (
                        sender_id,
                        recipient_id,
                        recipient_id,
                        sender_id,
                    ),
                )
                existing = cursor.fetchone()

                if existing is not None:
                    raise HTTPException(
                        status_code=409,
                        detail="A friendship request or relationship already exists.",
                    )

                cursor.execute(
                    """
                    INSERT INTO friendships (
                        requester_id,
                        recipient_id,
                        status
                    )
                    VALUES (%s, %s, 'pending')
                    RETURNING status
                    """,
                    (sender_id, recipient_id),
                )
                result = cursor.fetchone()

        return {
            "message": "Friend request sent.",
            "status": result[0],
        }

    except HTTPException:
        raise
    except Exception as error:
        print(f"Friend request error: {error!r}")
        raise HTTPException(
            status_code=500,
            detail="Could not send friend request.",
        ) from error

@app.get("/friends/requests")
def get_friend_requests(
    current_user: dict = Depends(get_current_user),
):
    try:
        with get_connection() as connection:
            with connection.cursor() as cursor:
                cursor.execute(
                    """
                    SELECT
                        f.requester_id,
                        u.username,
                        u.display_name,
                        f.created_at
                    FROM friendships AS f
                    JOIN users AS u
                        ON u.id = f.requester_id
                    JOIN users AS me
                        ON me.id = f.recipient_id
                    WHERE me.auth0_sub = %s
                      AND f.status = 'pending'
                    ORDER BY f.created_at DESC
                    """,
                    (current_user["auth0_sub"],),
                )

                rows = cursor.fetchall()
                columns = [
                    column.name
                    for column in cursor.description
                ]

        requests = [
            {
                key: value.isoformat()
                if isinstance(value, datetime)
                else str(value)
                if key == "requester_id"
                else value
                for key, value in zip(columns, row)
            }
            for row in rows
        ]

        return {
            "count": len(requests),
            "requests": requests,
        }

    except Exception as error:
        print(f"Friend request retrieval error: {error!r}")
        raise HTTPException(
            status_code=500,
            detail="Could not retrieve friend requests.",
        ) from error

@app.post("/friends/requests/{requester_id}/accept")
def accept_friend_request(
    requester_id: str,
    current_user: dict = Depends(get_current_user),
):
    try:
        with get_connection() as connection:
            with connection.cursor() as cursor:
                cursor.execute(
                    """
                    UPDATE friendships AS f
                    SET status = 'accepted'
                    FROM users AS recipient
                    WHERE recipient.auth0_sub = %s
                      AND f.recipient_id = recipient.id
                      AND f.requester_id = %s
                      AND f.status = 'pending'
                    RETURNING f.status
                    """,
                    (current_user["auth0_sub"], requester_id),
                )

                result = cursor.fetchone()

                if result is None:
                    raise HTTPException(
                        status_code=404,
                        detail="Pending friend request not found.",
                    )

        return {
            "message": "Friend request accepted.",
            "status": result[0],
        }

    except HTTPException:
        raise
    except Exception as error:
        print(f"Friend request acceptance error: {error!r}")
        raise HTTPException(
            status_code=500,
            detail="Could not accept friend request.",
        ) from error

@app.get("/friends")
def get_friends(
    current_user: dict = Depends(get_current_user),
):
    try:
        with get_connection() as connection:
            with connection.cursor() as cursor:
                cursor.execute(
                    """
                    SELECT
                        u.id,
                        u.username,
                        u.display_name
                    FROM friendships AS f
                    JOIN users AS me
                        ON me.id = CASE
                            WHEN f.requester_id = (
                                SELECT id
                                FROM users
                                WHERE auth0_sub = %s
                            )
                            THEN f.requester_id
                            ELSE f.recipient_id
                        END
                    JOIN users AS u
                        ON u.id = CASE
                            WHEN f.requester_id = me.id
                            THEN f.recipient_id
                            ELSE f.requester_id
                        END
                    WHERE (
                        f.requester_id = (
                            SELECT id
                            FROM users
                            WHERE auth0_sub = %s
                        )
                        OR f.recipient_id = (
                            SELECT id
                            FROM users
                            WHERE auth0_sub = %s
                        )
                    )
                    AND f.status = 'accepted'
                    ORDER BY u.username ASC
                    """,
                    (
                        current_user["auth0_sub"],
                        current_user["auth0_sub"],
                        current_user["auth0_sub"],
                    ),
                )

                rows = cursor.fetchall()
                columns = [
                    column.name
                    for column in cursor.description
                ]

        friends = [
            {
                key: str(value) if key == "id" else value
                for key, value in zip(columns, row)
            }
            for row in rows
        ]

        return {
            "count": len(friends),
            "friends": friends,
        }

    except Exception as error:
        print(f"Friend retrieval error: {error!r}")
        raise HTTPException(
            status_code=500,
            detail="Could not retrieve friends.",
        ) from error

@app.post("/friends/requests/{requester_id}/reject")
def reject_friend_request(
    requester_id: str,
    current_user: dict = Depends(get_current_user),
):
    try:
        with get_connection() as connection:
            with connection.cursor() as cursor:
                cursor.execute(
                    """
                    UPDATE friendships AS f
                    SET status = 'rejected'
                    FROM users AS recipient
                    WHERE recipient.auth0_sub = %s
                      AND f.recipient_id = recipient.id
                      AND f.requester_id = %s
                      AND f.status = 'pending'
                    RETURNING f.status
                    """,
                    (current_user["auth0_sub"], requester_id),
                )

                result = cursor.fetchone()

                if result is None:
                    raise HTTPException(
                        status_code=404,
                        detail="Pending friend request not found.",
                    )

        return {
            "message": "Friend request rejected.",
            "status": result[0],
        }

    except HTTPException:
        raise
    except Exception as error:
        print(f"Friend request rejection error: {error!r}")
        raise HTTPException(
            status_code=500,
            detail="Could not reject friend request.",
        ) from error


@app.get("/friends/outgoing-requests")
def get_outgoing_friend_requests(
    current_user: dict = Depends(get_current_user),
):
    with get_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute(
                """
                SELECT
                    recipient.id,
                    recipient.username,
                    recipient.display_name,
                    f.created_at
                FROM friendships f
                JOIN users sender ON sender.id = f.requester_id
                JOIN users recipient ON recipient.id = f.recipient_id
                WHERE sender.auth0_sub = %s
                  AND f.status = 'pending'
                ORDER BY f.created_at DESC
                """,
                (current_user["auth0_sub"],),
            )

            requests = [
                {
                    "recipient_id": str(row[0]),
                    "username": row[1],
                    "display_name": row[2],
                    "created_at": row[3].isoformat(),
                }
                for row in cursor.fetchall()
            ]

    return {"count": len(requests), "requests": requests}


@app.post("/commitments")
def create_commitment(
    commitment: CommitmentCreate,
    current_user: dict = Depends(get_current_user),
):
    title = commitment.title.strip()

    if not title:
        raise HTTPException(status_code=400, detail="Title is required.")

    if (
        commitment.starts_at
        and commitment.ends_at
        and commitment.ends_at <= commitment.starts_at
    ):
        raise HTTPException(
            status_code=400,
            detail="End time must be after start time.",
        )

    try:
        with get_connection() as connection:
            with connection.cursor() as cursor:
                cursor.execute(
                    "SELECT id FROM users WHERE auth0_sub = %s",
                    (current_user["auth0_sub"],),
                )
                user = cursor.fetchone()

                if not user:
                    raise HTTPException(
                        status_code=404,
                        detail="User profile not found.",
                    )

                user_id = user[0]

                if commitment.assignment_id:
                    cursor.execute(
                        """
                        SELECT id
                        FROM assignments
                        WHERE id = %s AND user_id = %s
                        """,
                        (commitment.assignment_id, user_id),
                    )
                    if not cursor.fetchone():
                        raise HTTPException(
                            status_code=404,
                            detail="Assignment not found in your account.",
                        )

                cursor.execute(
                    """
                    INSERT INTO commitments (
                        organizer_id,
                        assignment_id,
                        commitment_type,
                        title,
                        description,
                        starts_at,
                        ends_at,
                        status
                    )
                    VALUES (%s, %s, %s, %s, %s, %s, %s, 'planned')
                    RETURNING
                        id, assignment_id, commitment_type, title,
                        description, starts_at, ends_at, status, created_at
                    """,
                    (
                        user_id,
                        commitment.assignment_id,
                        commitment.commitment_type,
                        title,
                        commitment.description,
                        commitment.starts_at,
                        commitment.ends_at,
                    ),
                )

                row = cursor.fetchone()

        return {
            "id": str(row[0]),
            "assignment_id": str(row[1]) if row[1] else None,
            "commitment_type": row[2],
            "title": row[3],
            "description": row[4],
            "starts_at": row[5].isoformat() if row[5] else None,
            "ends_at": row[6].isoformat() if row[6] else None,
            "status": row[7],
            "created_at": row[8].isoformat(),
        }

    except HTTPException:
        raise
    except Exception as error:
        print(f"Commitment creation error: {error!r}")
        raise HTTPException(
            status_code=500,
            detail="Could not create commitment.",
        )


@app.get("/commitments")
def get_commitments(
    current_user: dict = Depends(get_current_user),
):
    try:
        with get_connection() as connection:
            with connection.cursor() as cursor:
                cursor.execute(
                    """
                    SELECT
                        c.id,
                        c.assignment_id,
                        c.commitment_type,
                        c.title,
                        c.description,
                        c.starts_at,
                        c.ends_at,
                        c.status,
                        c.created_at,
                        a.title
                    FROM commitments c
                    JOIN users u ON u.id = c.organizer_id
                    LEFT JOIN assignments a ON a.id = c.assignment_id
                    WHERE u.auth0_sub = %s
                    ORDER BY c.starts_at NULLS LAST, c.created_at DESC
                    """,
                    (current_user["auth0_sub"],),
                )

                rows = cursor.fetchall()

        commitments = [
            {
                "id": str(row[0]),
                "assignment_id": str(row[1]) if row[1] else None,
                "commitment_type": row[2],
                "title": row[3],
                "description": row[4],
                "starts_at": row[5].isoformat() if row[5] else None,
                "ends_at": row[6].isoformat() if row[6] else None,
                "status": row[7],
                "created_at": row[8].isoformat(),
                "assignment_title": row[9],
            }
            for row in rows
        ]

        return {
            "count": len(commitments),
            "commitments": commitments,
        }

    except Exception as error:
        print(f"Commitment retrieval error: {error!r}")
        raise HTTPException(
            status_code=500,
            detail="Could not retrieve commitments.",
        )


@app.post("/commitments/{commitment_id}/invite/{user_id}")
def invite_friend_to_commitment(
    commitment_id: UUID,
    user_id: UUID,
    current_user: dict = Depends(get_current_user),
):
    try:
        with get_connection() as connection:
            with connection.cursor(row_factory=dict_row) as cursor:
                # Find the organizer's profile.
                cursor.execute(
                    "SELECT id FROM users WHERE auth0_sub = %s",
                    (current_user["auth0_sub"],),
                )
                organizer = cursor.fetchone()

                if not organizer:
                    raise HTTPException(404, "Profile not found.")

                organizer_id = organizer["id"]

                # Only the organizer can invite participants.
                cursor.execute(
                    """
                    SELECT id
                    FROM commitments
                    WHERE id = %s AND organizer_id = %s
                    """,
                    (str(commitment_id), str(organizer_id)),
                )
                commitment = cursor.fetchone()

                if not commitment:
                    raise HTTPException(
                        404, "Commitment not found or you are not the organizer."
                    )

                # Invitations are limited to accepted friends.
                cursor.execute(
                    """
                    SELECT 1
                    FROM friendships
                    WHERE status = 'accepted'
                      AND (
                        (requester_id = %s AND recipient_id = %s)
                        OR
                        (requester_id = %s AND recipient_id = %s)
                      )
                    """,
                    (
                        str(organizer_id),
                        str(user_id),
                        str(user_id),
                        str(organizer_id),
                    ),
                )

                if not cursor.fetchone():
                    raise HTTPException(
                        403, "You can only invite accepted friends."
                    )

                # Verify the invited user exists.
                cursor.execute(
                    "SELECT id FROM users WHERE id = %s",
                    (str(user_id),),
                )
                if not cursor.fetchone():
                    raise HTTPException(404, "User not found.")

                # Do not overwrite an existing accepted participation.
                cursor.execute(
                    """
                    SELECT status
                    FROM commitment_participants
                    WHERE commitment_id = %s AND user_id = %s
                    """,
                    (str(commitment_id), str(user_id)),
                )
                existing = cursor.fetchone()

                if existing and existing["status"] in ("invited", "accepted"):
                    raise HTTPException(
                        409, "This user has already been invited or accepted."
                    )

                if existing:
                    cursor.execute(
                        """
                        UPDATE commitment_participants
                        SET status = 'invited', invited_at = NOW(),
                            completed_at = NULL
                        WHERE commitment_id = %s AND user_id = %s
                        """,
                        (str(commitment_id), str(user_id)),
                    )
                else:
                    cursor.execute(
                        """
                        INSERT INTO commitment_participants
                            (commitment_id, user_id, status)
                        VALUES (%s, %s, 'invited')
                        """,
                        (str(commitment_id), str(user_id)),
                    )

        return {"message": "Invitation sent."}

    except HTTPException:
        raise
    except Exception as error:
        print(f"Commitment invitation error: {error!r}")
        raise HTTPException(
            status_code=500, detail="Could not invite friend."
        )


@app.get("/commitments/invitations")
def get_commitment_invitations(
    current_user: dict = Depends(get_current_user),
):
    try:
        with get_connection() as connection:
            with connection.cursor(row_factory=dict_row) as cursor:
                cursor.execute(
                    """
                    SELECT u.id AS organizer_id,
                           u.username AS organizer_username,
                           u.display_name AS organizer_display_name,
                           c.id AS commitment_id,
                           c.title,
                           c.description,
                           c.commitment_type,
                           c.starts_at,
                           c.ends_at,
                           c.status,
                           cp.invited_at
                    FROM commitment_participants cp
                    JOIN users u ON u.id = (
                        SELECT organizer_id
                        FROM commitments
                        WHERE id = cp.commitment_id
                    )
                    JOIN commitments c ON c.id = cp.commitment_id
                    WHERE cp.user_id = (
                        SELECT id FROM users WHERE auth0_sub = %s
                    )
                      AND cp.status = 'invited'
                    ORDER BY cp.invited_at DESC
                    """,
                    (current_user["auth0_sub"],),
                )
                invitations = cursor.fetchall()

        return {
            "count": len(invitations),
            "invitations": [
                {
                    **{
                        key: (
                            str(value)
                            if isinstance(value, UUID)
                            else value.isoformat()
                            if hasattr(value, "isoformat")
                            else value
                        )
                        for key, value in invitation.items()
                    }
                }
                for invitation in invitations
            ],
        }

    except Exception as error:
        print(f"Commitment invitations error: {error!r}")
        raise HTTPException(
            status_code=500, detail="Could not load invitations."
        )


@app.post("/commitments/{commitment_id}/respond")
def respond_to_commitment_invitation(
    commitment_id: UUID,
    accept: bool,
    current_user: dict = Depends(get_current_user),
):
    try:
        with get_connection() as connection:
            with connection.cursor(row_factory=dict_row) as cursor:
                cursor.execute(
                    """
                    UPDATE commitment_participants
                    SET status = %s
                    WHERE commitment_id = %s
                      AND user_id = (
                          SELECT id FROM users WHERE auth0_sub = %s
                      )
                      AND status = 'invited'
                    RETURNING commitment_id
                    """,
                    (
                        "accepted" if accept else "declined",
                        str(commitment_id),
                        current_user["auth0_sub"],
                    ),
                )

                result = cursor.fetchone()

                if not result:
                    raise HTTPException(
                        404, "Pending invitation not found."
                    )

        return {
            "message": "Invitation accepted."
            if accept
            else "Invitation declined."
        }

    except HTTPException:
        raise
    except Exception as error:
        print(f"Commitment invitation response error: {error!r}")
        raise HTTPException(
            status_code=500, detail="Could not respond to invitation."
        )


@app.get("/commitments/participating")
def get_participating_commitments(
    current_user: dict = Depends(get_current_user),
):
    try:
        with get_connection() as connection:
            with connection.cursor(row_factory=dict_row) as cursor:
                cursor.execute(
                    """
                    SELECT c.id, c.organizer_id, c.assignment_id,
                           c.commitment_type, c.title, c.description,
                           c.starts_at, c.ends_at, c.status, c.created_at,
                           u.username AS organizer_username,
                           u.display_name AS organizer_display_name,
                           cp.status AS participation_status
                    FROM commitment_participants cp
                    JOIN commitments c ON c.id = cp.commitment_id
                    JOIN users u ON u.id = c.organizer_id
                    WHERE cp.user_id = (
                        SELECT id FROM users WHERE auth0_sub = %s
                    )
                      AND cp.status IN ('accepted', 'completed')
                    ORDER BY c.created_at DESC
                    """,
                    (current_user["auth0_sub"],),
                )
                rows = cursor.fetchall()

        commitments = []
        for row in rows:
            commitment = {}
            for key, value in row.items():
                if isinstance(value, UUID):
                    commitment[key] = str(value)
                elif hasattr(value, "isoformat"):
                    commitment[key] = value.isoformat()
                else:
                    commitment[key] = value
            commitments.append(commitment)

        return {
            "count": len(commitments),
            "commitments": commitments,
        }

    except Exception as error:
        print(f"Participating commitments error: {error!r}")
        raise HTTPException(
            status_code=500,
            detail="Could not load participating commitments.",
        )




@app.get("/commitments/{commitment_id}/participants")
def get_commitment_participants(
    commitment_id: UUID,
    current_user: dict = Depends(get_current_user),
):
    try:
        with get_connection() as connection:
            with connection.cursor(row_factory=dict_row) as cursor:
                cursor.execute(
                    """
                    SELECT id
                    FROM users
                    WHERE auth0_sub = %s
                    """,
                    (current_user["auth0_sub"],),
                )
                user = cursor.fetchone()

                if not user:
                    raise HTTPException(404, "Profile not found.")

                cursor.execute(
                    """
                    SELECT 1
                    FROM commitments
                    WHERE id = %s AND organizer_id = %s
                    """,
                    (str(commitment_id), str(user["id"])),
                )
                if not cursor.fetchone():
                    raise HTTPException(
                        404, "Commitment not found or you are not the organizer."
                    )

                cursor.execute(
                    """
                    SELECT u.id AS user_id,
                           u.username,
                           u.display_name,
                           cp.status,
                           cp.invited_at,
                           cp.completed_at
                    FROM commitment_participants cp
                    JOIN users u ON u.id = cp.user_id
                    WHERE cp.commitment_id = %s
                    ORDER BY cp.invited_at DESC
                    """,
                    (str(commitment_id),),
                )
                rows = cursor.fetchall()

        participants = []
        for row in rows:
            participants.append({
                key: (
                    str(value)
                    if isinstance(value, UUID)
                    else value.isoformat()
                    if hasattr(value, "isoformat")
                    else value
                )
                for key, value in row.items()
            })

        return {"count": len(participants), "participants": participants}

    except HTTPException:
        raise
    except Exception as error:
        print(f"Commitment participants error: {error!r}")
        raise HTTPException(
            status_code=500,
            detail="Could not load commitment participants.",
        )


@app.post("/commitments/{commitment_id}/complete")
def complete_commitment(
    commitment_id: UUID,
    current_user: dict = Depends(get_current_user),
):
    try:
        with get_connection() as connection:
            with connection.cursor(row_factory=dict_row) as cursor:
                cursor.execute(
                    "SELECT id FROM users WHERE auth0_sub = %s",
                    (current_user["auth0_sub"],),
                )
                user = cursor.fetchone()

                if not user:
                    raise HTTPException(404, "Profile not found.")

                user_id = user["id"]

                # Lock the commitment while checking and updating completion.
                cursor.execute(
                    """
                    SELECT id, organizer_id, status
                    FROM commitments
                    WHERE id = %s
                    FOR UPDATE
                    """,
                    (str(commitment_id),),
                )
                commitment = cursor.fetchone()

                if not commitment:
                    raise HTTPException(404, "Commitment not found.")

                if commitment["organizer_id"] == user_id:
                    if commitment["status"] == "canceled":
                        raise HTTPException(
                            409, "Canceled commitments cannot be completed."
                        )

                    if commitment["status"] != "completed":
                        cursor.execute(
                            """
                            UPDATE commitments
                            SET status = 'completed',
                                completed_at = NOW()
                            WHERE id = %s
                            """,
                            (str(commitment_id),),
                        )
                        cursor.execute(
                            """
                            UPDATE users
                            SET completed_commitments = completed_commitments + 1
                            WHERE id = %s
                            """,
                            (str(user_id),),
                        )

                    return {
                        "message": "Commitment completed.",
                        "already_completed": commitment["status"] == "completed",
                    }

                # Non-organizers must have accepted the invitation.
                cursor.execute(
                    """
                    SELECT status
                    FROM commitment_participants
                    WHERE commitment_id = %s AND user_id = %s
                    FOR UPDATE
                    """,
                    (str(commitment_id), str(user_id)),
                )
                participant = cursor.fetchone()

                if not participant:
                    raise HTTPException(
                        403, "You are not a participant in this commitment."
                    )

                if participant["status"] == "completed":
                    return {
                        "message": "Commitment already completed.",
                        "already_completed": True,
                    }

                if participant["status"] != "accepted":
                    raise HTTPException(
                        409, "You must accept the invitation before completing."
                    )

                cursor.execute(
                    """
                    UPDATE commitment_participants
                    SET status = 'completed', completed_at = NOW()
                    WHERE commitment_id = %s AND user_id = %s
                    """,
                    (str(commitment_id), str(user_id)),
                )
                cursor.execute(
                    """
                    UPDATE users
                    SET completed_commitments = completed_commitments + 1
                    WHERE id = %s
                    """,
                    (str(user_id),),
                )

        return {
            "message": "Commitment completed.",
            "already_completed": False,
        }

    except HTTPException:
        raise
    except Exception as error:
        print(f"Commitment completion error: {error!r}")
        raise HTTPException(
            status_code=500,
            detail="Could not complete commitment.",
        )


@app.get("/users/{user_id}/profile")
def get_friend_profile(
    user_id: str,
    current_user: dict = Depends(get_current_user),
):
    try:
        with get_connection() as connection:
            with connection.cursor(row_factory=dict_row) as cursor:
                # Find the authenticated user's database ID.
                cursor.execute(
                    """
                    SELECT id
                    FROM users
                    WHERE auth0_sub = %s
                    """,
                    (current_user["auth0_sub"],),
                )
                viewer = cursor.fetchone()

                if not viewer:
                    raise HTTPException(
                        status_code=404,
                        detail="Your profile was not found.",
                    )

                # Retrieve the target profile only if the users
                # have an accepted friendship.
                cursor.execute(
                    """
                    SELECT
                        u.id,
                        u.username,
                        u.display_name,
                        u.completed_commitments,
                        u.created_at
                    FROM users u
                    WHERE u.id = %s
                      AND EXISTS (
                          SELECT 1
                          FROM friendships f
                          WHERE f.status = 'accepted'
                            AND (
                                (
                                    f.requester_id = %s
                                    AND f.recipient_id = u.id
                                )
                                OR
                                (
                                    f.recipient_id = %s
                                    AND f.requester_id = u.id
                                )
                            )
                      )
                    """,
                    (user_id, viewer["id"], viewer["id"]),
                )
                profile = cursor.fetchone()

                if not profile:
                    raise HTTPException(
                        status_code=404,
                        detail="Friend profile not found.",
                    )

                # Only assignments with future due dates.
                cursor.execute(
                    """
                    SELECT
                        id,
                        title,
                        description,
                        course,
                        course_name,
                        start_at,
                        due_at,
                        location,
                        event_url,
                        source
                    FROM assignments
                    WHERE user_id = %s
                      AND due_at >= NOW()
                    ORDER BY due_at ASC
                    """,
                    (profile["id"],),
                )
                assignments = cursor.fetchall()

                # Current commitments organized by this friend.
                cursor.execute(
                    """
                    SELECT
                        id,
                        title,
                        description,
                        commitment_type,
                        starts_at,
                        ends_at,
                        status
                    FROM commitments
                    WHERE organizer_id = %s
                      AND status IN ('planned', 'active')
                      AND COALESCE(ends_at, starts_at) >= NOW()
                    ORDER BY COALESCE(starts_at, ends_at) ASC
                    """,
                    (profile["id"],),
                )
                commitments = cursor.fetchall()

        return {
            "id": str(profile["id"]),
            "username": profile["username"],
            "display_name": profile["display_name"],
            "completed_commitments": profile["completed_commitments"],
            "created_at": profile["created_at"],
            "assignments": assignments,
            "commitments": commitments,
        }

    except HTTPException:
        raise
    except Exception as error:
        print(f"Friend profile error: {error!r}")
        raise HTTPException(
            status_code=500,
            detail="Could not retrieve friend profile.",
        )