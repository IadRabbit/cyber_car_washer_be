from typing import Any

from cyber_car_washer_be.models import Response


def json_response(status_code: int, body: Response) -> dict[str, Any]:
    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "application/json"},
        "body": body.model_dump_json(),
        "isBase64Encoded": False,
    }

def json_response_error(status_code: int, body: dict[str, Any]) -> dict[str, int | dict[str, str] | bool]:
    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "application/json"},
        "body": body,
        "isBase64Encoded": False,
    }