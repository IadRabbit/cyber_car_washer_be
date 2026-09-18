from pydantic import BaseModel, field_validator


class RequestPayload(BaseModel):
    uid: int

    @field_validator("uid", mode="before")
    @classmethod
    def parse_hex_uid(cls, value: str) -> int:
        if len(value) != 32:
            raise ValueError("UID is not 16")

        return int(value, 16)

class Key(BaseModel):
    key_a: int
    key_b: int

class Response(BaseModel):
    keys: list[Key]