import base64
from random import randint, seed
from typing import Any

from pydantic import ValidationError

from cyber_car_washer_be.models import Key, RequestPayload, Response
from cyber_car_washer_be.responses import json_response, json_response_error

DEFAULT_ACCESS_KEYS_KEY = 0x05C3DB68CF67B71EEAB73640CA04E2E2


def lambda_handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    raw_body = event.get("body") or ""
    if event.get("isBase64Encoded"):
        raw_body = base64.b64decode(raw_body).decode()

    try:
        payload = RequestPayload.model_validate_json(raw_body)
    except ValidationError as exc:
        return json_response_error(
            400,
            {"error": "invalid_request", "details": exc.errors(include_context=False)},
        )

    seed(payload.uid ^ DEFAULT_ACCESS_KEYS_KEY)
    response = Response(keys=[])

    for _ in range(16):
        curr_byte_array_key_a = [hex(randint(0, 255)) for _ in range(6)]
        curr_byte_array_key_b = [hex(randint(0, 255)) for _ in range(6)]
        curr_key_a = "0x"

        for curr_byte in curr_byte_array_key_a:
            curr_key_a += curr_byte.strip("0x")

        curr_key_b = "0x"

        for curr_byte in curr_byte_array_key_b:
            curr_key_b += curr_byte.strip("0x")

        response.keys.append(
            Key(key_a=int(curr_key_a, 16), key_b=int(curr_key_b, 16))
        )

    return json_response(200, response)

if __name__ == "__main__":
    sample_event = {
        "requestContext": {
            "elb": {
                "targetGroupArn": "arn:aws:elasticloadbalancing:eu-west-1:123456789012:targetgroup/example/1234567890123456"
            }
        },
        "httpMethod": "POST",
        "path": "/",
        "queryStringParameters": {},
        "headers": {
            "host": "example.com",
            "content-type": "application/json",
        },
        "body": '{"uid": "0011223344556677"}',
        "isBase64Encoded": False,
    }

    print(lambda_handler(sample_event, None))